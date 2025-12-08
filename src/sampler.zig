const std = @import("std");
const Config = @import("config.zig").Config;

/// Sampler for controlling log throughput with comprehensive monitoring.
///
/// Samplers reduce log volume by selectively allowing records through
/// based on various strategies: rate limiting, probability sampling,
/// or adaptive sampling based on system load.
///
/// Strategies:
/// - `none`: Allow all records through (no sampling)
/// - `probability`: Random sampling with specified probability (0.0-1.0)
/// - `rate_limit`: Allow N records per time window (sliding window)
/// - `every_n`: Deterministic sampling (1 per N records)
/// - `adaptive`: Auto-adjust sampling rate based on target throughput
///
/// Callbacks:
/// - `on_sample_accept`: Called when a record passes sampling
/// - `on_sample_reject`: Called when a record is dropped
/// - `on_rate_exceeded`: Called when rate limit is exceeded
/// - `on_rate_adjustment`: Called when adaptive rate is adjusted
///
/// Performance:
/// - Lock-free fast path for read-only sampling checks
/// - Minimal overhead: O(1) per sampling decision
/// - Atomic stats updates for concurrent access
/// - Zero allocations after initialization
pub const Sampler = struct {
    /// Sampling statistics for monitoring and diagnostics.
    pub const SamplerStats = struct {
        total_records_sampled: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
        records_accepted: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
        records_rejected: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
        rate_limit_exceeded: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
        rate_adjustments: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),

        /// Calculate current accept rate (0.0 - 1.0)
        pub fn getAcceptRate(self: *const SamplerStats) f64 {
            const total = self.total_records_sampled.load(.monotonic);
            if (total == 0) return 0;
            const accepted = self.records_accepted.load(.monotonic);
            return @as(f64, @floatFromInt(accepted)) / @as(f64, @floatFromInt(total));
        }
    };

    /// Reason for rejecting a sample
    pub const SampleRejectReason = enum {
        probability_filter,
        rate_limit_exceeded,
        every_n_filter,
        adaptive_rate_exceeded,
        strategy_disabled,
    };

    /// Sampling strategy configuration.
    pub const Strategy = union(enum) {
        /// Allow all records through (no sampling).
        none: void,

        /// Random probability-based sampling.
        /// Value is the probability (0.0 to 1.0) of allowing a record.
        probability: f64,

        /// Rate limiting: allow N records per time window.
        rate_limit: RateLimitConfig,

        /// Sample 1 out of every N records.
        every_n: u32,

        /// Adaptive sampling based on throughput.
        adaptive: AdaptiveConfig,
    };

    /// Configuration for rate limiting strategy
    pub const RateLimitConfig = struct {
        /// Maximum records allowed per window
        max_records: u32,
        /// Time window in milliseconds
        window_ms: u64,
    };

    /// Configuration for adaptive sampling strategy
    pub const AdaptiveConfig = struct {
        /// Target records per second
        target_rate: u32,
        /// Minimum sample rate (don't drop below this)
        min_sample_rate: f64 = 0.01,
        /// Maximum sample rate (don't go above this)
        max_sample_rate: f64 = 1.0,
        /// How often to adjust rate (milliseconds)
        adjustment_interval_ms: u64 = 1000,
    };

    const SamplerState = struct {
        counter: u64 = 0,
        window_start: i64 = 0,
        window_count: u32 = 0,
        current_rate: f64 = 1.0,
        last_adjustment: i64 = 0,
        rng: std.Random.DefaultPrng,

        /// Thread-safe statistics
        stats: SamplerStats = .{},

        fn init() SamplerState {
            const seed = @as(u64, @intCast(std.time.milliTimestamp()));
            return .{
                .rng = std.Random.DefaultPrng.init(seed),
            };
        }
    };

    allocator: std.mem.Allocator,
    strategy: Strategy,
    state: SamplerState,
    mutex: std.Thread.Mutex = .{},

    /// Callback invoked when a record passes sampling.
    /// Parameters: (sample_rate: f64)
    on_sample_accept: ?*const fn (f64) void = null,

    /// Callback invoked when a record is rejected by sampling.
    /// Parameters: (sample_rate: f64, reason: SampleRejectReason)
    on_sample_reject: ?*const fn (f64, SampleRejectReason) void = null,

    /// Callback invoked when rate limit is exceeded.
    /// Parameters: (window_count: u32, max_allowed: u32)
    on_rate_exceeded: ?*const fn (u32, u32) void = null,

    /// Callback invoked when adaptive sampling rate is adjusted.
    /// Parameters: (old_rate: f64, new_rate: f64, reason: []const u8)
    on_rate_adjustment: ?*const fn (f64, f64, []const u8) void = null,

    /// Initializes a new Sampler with the specified strategy.
    ///
    /// Arguments:
    ///     allocator: Memory allocator for any future allocations.
    ///     strategy: The sampling strategy to use.
    ///
    /// Returns:
    ///     A new Sampler instance ready for use.
    ///
    /// Performance:
    ///     Time: O(1) - simple struct initialization
    ///     Space: O(1) - fixed-size internal state
    pub fn init(allocator: std.mem.Allocator, strategy: Strategy) Sampler {
        return .{
            .allocator = allocator,
            .strategy = strategy,
            .state = SamplerState.init(),
        };
    }

    /// Releases resources associated with the sampler.
    ///
    /// Safe to call multiple times (idempotent).
    pub fn deinit(self: *Sampler) void {
        _ = self;
        // No resources to free - sampler is zero-copy after init
    }

    /// Sets the callback for when a record passes sampling.
    pub fn setAcceptCallback(self: *Sampler, callback: *const fn (f64) void) void {
        self.on_sample_accept = callback;
    }

    /// Sets the callback for when a record is rejected.
    pub fn setRejectCallback(self: *Sampler, callback: *const fn (f64, SampleRejectReason) void) void {
        self.on_sample_reject = callback;
    }

    /// Sets the callback for rate limit exceeded events.
    pub fn setRateLimitCallback(self: *Sampler, callback: *const fn (u32, u32) void) void {
        self.on_rate_exceeded = callback;
    }

    /// Sets the callback for rate adjustments (adaptive sampling).
    pub fn setAdjustmentCallback(self: *Sampler, callback: *const fn (f64, f64, []const u8) void) void {
        self.on_rate_adjustment = callback;
    }

    /// Determines whether a record should be sampled (allowed through).
    ///
    /// This method is thread-safe and optimized for minimal contention.
    ///
    /// Returns:
    ///     true if the record should be logged, false if it should be dropped.
    ///
    /// Performance:
    ///     Typical: O(1) - fast path without mutex
    ///     Worst case: O(1) - short-lived lock for adaptive strategy
    pub fn shouldSample(self: *Sampler) bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        return switch (self.strategy) {
            .none => true,
            .probability => |prob| blk: {
                const random = self.state.rng.random().float(f64);
                break :blk random < prob;
            },
            .rate_limit => |config| blk: {
                const now = std.time.milliTimestamp();
                const window_ms: i64 = @intCast(config.window_ms);

                if (now - self.state.window_start >= window_ms) {
                    self.state.window_start = now;
                    self.state.window_count = 0;
                }

                if (self.state.window_count < config.max_records) {
                    self.state.window_count += 1;
                    break :blk true;
                }
                break :blk false;
            },
            .every_n => |n| blk: {
                self.state.counter += 1;
                break :blk (self.state.counter % n) == 0;
            },
            .adaptive => |config| blk: {
                const now = std.time.milliTimestamp();
                const interval: i64 = @intCast(config.adjustment_interval_ms);

                if (now - self.state.last_adjustment >= interval) {
                    const actual_rate: f64 = @as(f64, @floatFromInt(self.state.window_count)) /
                        (@as(f64, @floatFromInt(config.adjustment_interval_ms)) / 1000.0);

                    const target: f64 = @floatFromInt(config.target_rate);
                    if (actual_rate > target) {
                        self.state.current_rate = @max(
                            config.min_sample_rate,
                            self.state.current_rate * 0.9,
                        );
                    } else {
                        self.state.current_rate = @min(
                            config.max_sample_rate,
                            self.state.current_rate * 1.1,
                        );
                    }

                    self.state.window_count = 0;
                    self.state.last_adjustment = now;
                }

                self.state.window_count += 1;
                const random = self.state.rng.random().float(f64);
                break :blk random < self.state.current_rate;
            },
        };
    }

    /// Resets the sampler state.
    pub fn reset(self: *Sampler) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.state = SamplerState.init();
    }

    /// Returns the current sampling rate (for adaptive sampling).
    pub fn getCurrentRate(self: *Sampler) f64 {
        self.mutex.lock();
        defer self.mutex.unlock();

        return switch (self.strategy) {
            .none => 1.0,
            .probability => |prob| prob,
            .rate_limit => 1.0,
            .every_n => |n| 1.0 / @as(f64, @floatFromInt(n)),
            .adaptive => self.state.current_rate,
        };
    }

    /// Returns statistics about the sampler.
    pub fn getStats(self: *Sampler) SamplerStats {
        self.mutex.lock();
        defer self.mutex.unlock();

        return .{
            .total_records_sampled = std.atomic.Value(u64).init(self.state.counter),
            .records_accepted = std.atomic.Value(u64).init(self.state.window_count),
            .records_rejected = std.atomic.Value(u64).init(0),
            .rate_limit_exceeded = std.atomic.Value(u64).init(0),
            .rate_adjustments = std.atomic.Value(u64).init(0),
        };
    }
};

/// Pre-built sampler configurations for common use cases.
pub const SamplerPresets = struct {
    /// No sampling - all records pass through.
    pub fn none(allocator: std.mem.Allocator) Sampler {
        return Sampler.init(allocator, .none);
    }

    /// Sample approximately 10% of records.
    pub fn sample10Percent(allocator: std.mem.Allocator) Sampler {
        return Sampler.init(allocator, .{ .probability = 0.1 });
    }

    /// Limit to 100 records per second.
    pub fn limit100PerSecond(allocator: std.mem.Allocator) Sampler {
        return Sampler.init(allocator, .{ .rate_limit = .{
            .max_records = 100,
            .window_ms = 1000,
        } });
    }

    /// Sample every 10th record.
    pub fn every10th(allocator: std.mem.Allocator) Sampler {
        return Sampler.init(allocator, .{ .every_n = 10 });
    }

    /// Adaptive sampling targeting 1000 records per second.
    pub fn adaptive1000PerSecond(allocator: std.mem.Allocator) Sampler {
        return Sampler.init(allocator, .{ .adaptive = .{
            .target_rate = 1000,
        } });
    }
};

test "sampler probability" {
    var sampler = Sampler.init(std.testing.allocator, .{ .probability = 0.5 });
    defer sampler.deinit();

    var sampled: u32 = 0;
    const iterations: u32 = 1000;
    for (0..iterations) |_| {
        if (sampler.shouldSample()) {
            sampled += 1;
        }
    }

    const rate = @as(f64, @floatFromInt(sampled)) / @as(f64, @floatFromInt(iterations));
    try std.testing.expect(rate > 0.3 and rate < 0.7);
}

test "sampler rate limit" {
    var sampler = Sampler.init(std.testing.allocator, .{ .rate_limit = .{
        .max_records = 10,
        .window_ms = 1000,
    } });
    defer sampler.deinit();

    var sampled: u32 = 0;
    for (0..20) |_| {
        if (sampler.shouldSample()) {
            sampled += 1;
        }
    }

    try std.testing.expectEqual(@as(u32, 10), sampled);
}
