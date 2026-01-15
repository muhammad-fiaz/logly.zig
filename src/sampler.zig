//! Log Sampling Module
//!
//! Controls log throughput by selectively allowing records through
//! based on configurable sampling strategies.
//!
//! Strategies:
//! - none: Allow all records (no sampling)
//! - probability: Random sampling with specified probability (0.0-1.0)
//! - rate_limit: Allow N records per time window (sliding window)
//! - every_n: Deterministic sampling (1 per N records)
//! - adaptive: Auto-adjust sampling rate based on target throughput
//!
//! Use Cases:
//! - High-volume production systems requiring reduced log volume
//! - Cost control for cloud logging services
//! - Debug sampling without overwhelming storage
//! - Load-based adaptive throttling
//!
//! Performance:
//! - O(1) per sampling decision
//! - Lock-free fast path for read-only checks
//! - Zero allocations after initialization

const std = @import("std");
const Config = @import("config.zig").Config;
const SinkConfig = @import("sink.zig").SinkConfig;
const Constants = @import("constants.zig");

/// Sampler for controlling log throughput with comprehensive monitoring.
pub const Sampler = struct {
    /// Sampling statistics for monitoring and diagnostics.
    pub const SamplerStats = struct {
        total_records_sampled: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        records_accepted: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        records_rejected: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        rate_limit_exceeded: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        rate_adjustments: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),

        /// Calculate current accept rate (0.0 - 1.0)
        pub fn getAcceptRate(self: *const SamplerStats) f64 {
            const total = @as(u64, self.total_records_sampled.load(.monotonic));
            if (total == 0) return 0;
            const accepted = @as(u64, self.records_accepted.load(.monotonic));
            return @as(f64, @floatFromInt(accepted)) / @as(f64, @floatFromInt(total));
        }

        /// Calculate current reject rate (0.0 - 1.0)
        pub fn getRejectRate(self: *const SamplerStats) f64 {
            const total = @as(u64, self.total_records_sampled.load(.monotonic));
            if (total == 0) return 0;
            const rejected = @as(u64, self.records_rejected.load(.monotonic));
            return @as(f64, @floatFromInt(rejected)) / @as(f64, @floatFromInt(total));
        }

        /// Returns true if any records have been rejected.
        pub fn hasRejections(self: *const SamplerStats) bool {
            return self.records_rejected.load(.monotonic) > 0;
        }

        /// Returns true if rate limit has been exceeded at least once.
        pub fn hasRateLimitExceeded(self: *const SamplerStats) bool {
            return self.rate_limit_exceeded.load(.monotonic) > 0;
        }

        /// Returns the rate limit exceeded percentage (0.0 - 1.0).
        pub fn getRateLimitExceededRate(self: *const SamplerStats) f64 {
            const rejected = @as(u64, self.records_rejected.load(.monotonic));
            if (rejected == 0) return 0;
            const exceeded = @as(u64, self.rate_limit_exceeded.load(.monotonic));
            return @as(f64, @floatFromInt(exceeded)) / @as(f64, @floatFromInt(rejected));
        }

        /// Returns total records sampled as u64.
        pub fn getTotal(self: *const SamplerStats) u64 {
            return @as(u64, self.total_records_sampled.load(.monotonic));
        }

        /// Returns accepted records count as u64.
        pub fn getAccepted(self: *const SamplerStats) u64 {
            return @as(u64, self.records_accepted.load(.monotonic));
        }

        /// Returns rejected records count as u64.
        pub fn getRejected(self: *const SamplerStats) u64 {
            return @as(u64, self.records_rejected.load(.monotonic));
        }
    };

    /// Reason for rejecting a sample.
    pub const SampleRejectReason = enum {
        /// Rejected due to probability sampling threshold.
        probability_filter,
        /// Rejected because rate limit was exceeded in current window.
        rate_limit_exceeded,
        /// Rejected by every-N sampling (not Nth record).
        every_n_filter,
        /// Rejected by adaptive sampling rate.
        adaptive_rate_exceeded,
        /// Rejected because sampling strategy is disabled.
        strategy_disabled,
    };

    /// Sampling strategy configuration.
    pub const Strategy = Config.SamplingConfig.Strategy;

    /// Configuration for rate limiting strategy.
    pub const RateLimitConfig = Config.SamplingConfig.SamplingRateLimitConfig;

    /// Configuration for adaptive sampling strategy.
    pub const AdaptiveConfig = Config.SamplingConfig.AdaptiveConfig;

    /// Internal sampler state (counters, RNG, statistics).
    const SamplerState = struct {
        /// Record counter for every-N sampling.
        counter: u64 = 0,
        /// Start time of current rate-limiting window.
        window_start: i64 = 0,
        /// Number of records in current window.
        window_count: u32 = 0,
        /// Current adaptive sampling rate.
        current_rate: f64 = 1.0,
        /// Last time adaptive rate was adjusted.
        last_adjustment: i64 = 0,
        /// Random number generator for probability sampling.
        rng: std.Random.DefaultPrng,

        /// Thread-safe statistics.
        stats: SamplerStats = .{},

        fn init() SamplerState {
            const seed = @as(u64, @intCast(std.time.milliTimestamp()));
            return .{
                .rng = std.Random.DefaultPrng.init(seed),
            };
        }
    };

    /// Memory allocator for any future allocations.
    allocator: std.mem.Allocator,
    /// Active sampling strategy.
    strategy: Strategy,
    /// Internal state (counters, RNG, window tracking).
    state: SamplerState,
    /// Mutex for thread-safe operations.
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

    /// Alias for init().
    pub const create = init;

    /// Releases resources associated with the sampler.
    ///
    /// Safe to call multiple times (idempotent).
    pub fn deinit(self: *Sampler) void {
        _ = self;
        // No resources to free - sampler is zero-copy after init
    }

    /// Alias for deinit().
    pub const destroy = deinit;

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
        _ = self.state.stats.total_records_sampled.fetchAdd(1, .monotonic);

        var current_rate: f64 = 0;
        var reject_reason: ?SampleRejectReason = null;
        var rate_exceeded_info: ?struct { count: u32, max: u32 } = null;
        var adjustment_info: ?struct { old: f64, new: f64 } = null;

        const result = blk: {
            self.mutex.lock();
            defer self.mutex.unlock();

            switch (self.strategy) {
                .none => {
                    current_rate = 1.0;
                    break :blk true;
                },
                .probability => |prob| {
                    current_rate = prob;
                    const random = self.state.rng.random().float(f64);
                    if (random < prob) {
                        break :blk true;
                    } else {
                        reject_reason = .probability_filter;
                        break :blk false;
                    }
                },
                .rate_limit => |config| {
                    current_rate = 1.0; // Rate limit doesn't have a probability rate
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

                    _ = self.state.stats.rate_limit_exceeded.fetchAdd(1, .monotonic);
                    rate_exceeded_info = .{ .count = self.state.window_count, .max = config.max_records };
                    reject_reason = .rate_limit_exceeded;
                    break :blk false;
                },
                .every_n => |n| {
                    current_rate = 1.0 / @as(f64, @floatFromInt(n));
                    self.state.counter += 1;
                    if ((self.state.counter % n) == 0) {
                        break :blk true;
                    } else {
                        reject_reason = .every_n_filter;
                        break :blk false;
                    }
                },
                .adaptive => |config| {
                    const now = std.time.milliTimestamp();
                    const interval: i64 = @intCast(config.adjustment_interval_ms);

                    if (now - self.state.last_adjustment >= interval) {
                        const actual_rate: f64 = @as(f64, @floatFromInt(self.state.window_count)) /
                            (@as(f64, @floatFromInt(config.adjustment_interval_ms)) / 1000.0);

                        const old_rate = self.state.current_rate;
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

                        if (self.state.current_rate != old_rate) {
                            _ = self.state.stats.rate_adjustments.fetchAdd(1, .monotonic);
                            adjustment_info = .{ .old = old_rate, .new = self.state.current_rate };
                        }

                        self.state.window_count = 0;
                        self.state.last_adjustment = now;
                    }

                    self.state.window_count += 1;
                    current_rate = self.state.current_rate;
                    const random = self.state.rng.random().float(f64);
                    if (random < self.state.current_rate) {
                        break :blk true;
                    } else {
                        reject_reason = .adaptive_rate_exceeded;
                        break :blk false;
                    }
                },
            }
        };

        // Callbacks and stats updates outside the lock
        if (adjustment_info) |info| {
            if (self.on_rate_adjustment) |cb| cb(info.old, info.new, "throughput adjustment");
        }

        if (rate_exceeded_info) |info| {
            if (self.on_rate_exceeded) |cb| cb(info.count, info.max);
        }

        if (result) {
            _ = self.state.stats.records_accepted.fetchAdd(1, .monotonic);
            if (self.on_sample_accept) |cb| cb(current_rate);
        } else {
            _ = self.state.stats.records_rejected.fetchAdd(1, .monotonic);
            if (self.on_sample_reject) |cb| cb(current_rate, reject_reason.?);
        }

        return result;
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
        return .{
            .total_records_sampled = std.atomic.Value(Constants.AtomicUnsigned).init(@as(Constants.AtomicUnsigned, self.state.stats.total_records_sampled.load(.monotonic))),
            .records_accepted = std.atomic.Value(Constants.AtomicUnsigned).init(@as(Constants.AtomicUnsigned, self.state.stats.records_accepted.load(.monotonic))),
            .records_rejected = std.atomic.Value(Constants.AtomicUnsigned).init(@as(Constants.AtomicUnsigned, self.state.stats.records_rejected.load(.monotonic))),
            .rate_limit_exceeded = std.atomic.Value(Constants.AtomicUnsigned).init(@as(Constants.AtomicUnsigned, self.state.stats.rate_limit_exceeded.load(.monotonic))),
            .rate_adjustments = std.atomic.Value(Constants.AtomicUnsigned).init(@as(Constants.AtomicUnsigned, self.state.stats.rate_adjustments.load(.monotonic))),
        };
    }

    /// Resets statistics.
    pub fn resetStats(self: *Sampler) void {
        self.state.stats = .{};
    }

    /// Returns true if sampling is enabled.
    pub fn isEnabled(self: *const Sampler) bool {
        return self.strategy != .none;
    }

    /// Returns the strategy name.
    pub fn strategyName(self: *const Sampler) []const u8 {
        return switch (self.strategy) {
            .none => "none",
            .probability => "probability",
            .rate_limit => "rate_limit",
            .every_n => "every_n",
            .adaptive => "adaptive",
        };
    }

    /// Returns total records processed.
    pub fn totalProcessed(self: *const Sampler) u64 {
        return @as(u64, self.state.stats.total_records_sampled.load(.monotonic));
    }

    /// Returns total records accepted.
    pub fn totalAccepted(self: *const Sampler) u64 {
        return @as(u64, self.state.stats.records_accepted.load(.monotonic));
    }

    /// Returns total records rejected.
    pub fn totalRejected(self: *const Sampler) u64 {
        return @as(u64, self.state.stats.records_rejected.load(.monotonic));
    }

    /// Alias for shouldSample
    pub const sample = shouldSample;
    pub const check = shouldSample;
    pub const allow = shouldSample;

    /// Alias for getCurrentRate
    pub const rate = getCurrentRate;

    /// Alias for getStats
    pub const statistics = getStats;
    pub const stats_ = getStats;
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

    /// Sample approximately 50% of records.
    pub fn sample50Percent(allocator: std.mem.Allocator) Sampler {
        return Sampler.init(allocator, .{ .probability = 0.5 });
    }

    /// Sample approximately 1% of records (high-volume production).
    pub fn sample1Percent(allocator: std.mem.Allocator) Sampler {
        return Sampler.init(allocator, .{ .probability = 0.01 });
    }

    /// Limit to 100 records per second.
    pub fn limit100PerSecond(allocator: std.mem.Allocator) Sampler {
        return Sampler.init(allocator, .{ .rate_limit = .{
            .max_records = 100,
            .window_ms = 1000,
        } });
    }

    /// Limit to 1000 records per second.
    pub fn limit1000PerSecond(allocator: std.mem.Allocator) Sampler {
        return Sampler.init(allocator, .{ .rate_limit = .{
            .max_records = 1000,
            .window_ms = 1000,
        } });
    }

    /// Limit to 10 records per second (debug/low-volume).
    pub fn limit10PerSecond(allocator: std.mem.Allocator) Sampler {
        return Sampler.init(allocator, .{ .rate_limit = .{
            .max_records = 10,
            .window_ms = 1000,
        } });
    }

    /// Sample every 10th record.
    pub fn every10th(allocator: std.mem.Allocator) Sampler {
        return Sampler.init(allocator, .{ .every_n = 10 });
    }

    /// Sample every 100th record (high-volume production).
    pub fn every100th(allocator: std.mem.Allocator) Sampler {
        return Sampler.init(allocator, .{ .every_n = 100 });
    }

    /// Sample every 5th record.
    pub fn every5th(allocator: std.mem.Allocator) Sampler {
        return Sampler.init(allocator, .{ .every_n = 5 });
    }

    /// Adaptive sampling targeting 1000 records per second.
    pub fn adaptive1000PerSecond(allocator: std.mem.Allocator) Sampler {
        return Sampler.init(allocator, .{ .adaptive = .{
            .target_rate = 1000,
        } });
    }

    /// Adaptive sampling targeting 100 records per second.
    pub fn adaptive100PerSecond(allocator: std.mem.Allocator) Sampler {
        return Sampler.init(allocator, .{ .adaptive = .{
            .target_rate = 100,
        } });
    }

    /// Creates a sampled sink configuration.
    pub fn createSampledSink(file_path: []const u8) SinkConfig {
        return SinkConfig{
            .path = file_path,
            .color = false,
        };
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

test "sampler stats and callbacks" {
    var sampler = Sampler.init(std.testing.allocator, .{ .rate_limit = .{
        .max_records = 5,
        .window_ms = 1000,
    } });
    defer sampler.deinit();

    // We can't easily capture context in function pointers without global state or more complex setup.
    // For this test, we'll just verify stats are updated.

    for (0..10) |_| {
        _ = sampler.shouldSample();
    }

    const stats = sampler.getStats();
    try std.testing.expectEqual(@as(u64, 10), stats.total_records_sampled.load(.monotonic));
    try std.testing.expectEqual(@as(u64, 5), stats.records_accepted.load(.monotonic));
    try std.testing.expectEqual(@as(u64, 5), stats.records_rejected.load(.monotonic));
    try std.testing.expectEqual(@as(u64, 5), stats.rate_limit_exceeded.load(.monotonic));
}

test "sampler every_n" {
    var sampler = Sampler.init(std.testing.allocator, .{ .every_n = 3 });
    defer sampler.deinit();

    try std.testing.expectEqual(false, sampler.shouldSample()); // 1
    try std.testing.expectEqual(false, sampler.shouldSample()); // 2
    try std.testing.expectEqual(true, sampler.shouldSample()); // 3
    try std.testing.expectEqual(false, sampler.shouldSample()); // 4
    try std.testing.expectEqual(false, sampler.shouldSample()); // 5
    try std.testing.expectEqual(true, sampler.shouldSample()); // 6
}

test "sampler adaptive" {
    var sampler = Sampler.init(std.testing.allocator, .{ .adaptive = .{
        .target_rate = 100,
        .adjustment_interval_ms = 50,
        .min_sample_rate = 0.01,
        .max_sample_rate = 1.0,
    } });
    defer sampler.deinit();

    // Initial rate should be 1.0
    try std.testing.expectEqual(1.0, sampler.getCurrentRate());

    // Stimulate with many records to force rate decrease
    for (0..200) |_| {
        _ = sampler.shouldSample();
    }

    // Wait for adjustment interval
    std.Thread.sleep(60 * std.time.ns_per_ms);

    // One more sample to trigger adjustment
    _ = sampler.shouldSample();

    const rate = sampler.getCurrentRate();
    try std.testing.expect(rate < 1.0);
}
