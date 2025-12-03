const std = @import("std");

/// Sampler for controlling log throughput.
///
/// Samplers reduce log volume by selectively allowing records through
/// based on various strategies: rate limiting, probability sampling,
/// or adaptive sampling based on system load.
pub const Sampler = struct {
    allocator: std.mem.Allocator,
    strategy: Strategy,
    state: SamplerState,
    mutex: std.Thread.Mutex = .{},

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

    pub const RateLimitConfig = struct {
        max_records: u32,
        window_ms: u64,
    };

    pub const AdaptiveConfig = struct {
        target_rate: u32,
        min_sample_rate: f64 = 0.01,
        max_sample_rate: f64 = 1.0,
        adjustment_interval_ms: u64 = 1000,
    };

    const SamplerState = struct {
        counter: u64 = 0,
        window_start: i64 = 0,
        window_count: u32 = 0,
        current_rate: f64 = 1.0,
        last_adjustment: i64 = 0,
        rng: std.Random.DefaultPrng,

        fn init() SamplerState {
            const seed = @as(u64, @intCast(std.time.milliTimestamp()));
            return .{
                .rng = std.Random.DefaultPrng.init(seed),
            };
        }
    };

    /// Initializes a new Sampler with the specified strategy.
    ///
    /// Arguments:
    ///     allocator: Memory allocator.
    ///     strategy: The sampling strategy to use.
    ///
    /// Returns:
    ///     A new Sampler instance.
    pub fn init(allocator: std.mem.Allocator, strategy: Strategy) Sampler {
        return .{
            .allocator = allocator,
            .strategy = strategy,
            .state = SamplerState.init(),
        };
    }

    /// Releases resources associated with the sampler.
    pub fn deinit(self: *Sampler) void {
        _ = self;
    }

    /// Determines whether a record should be sampled (allowed through).
    ///
    /// This method is thread-safe.
    ///
    /// Returns:
    ///     true if the record should be logged, false if it should be dropped.
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
            .total_records = self.state.counter,
            .current_rate = self.getCurrentRate(),
            .window_count = self.state.window_count,
        };
    }

    pub const SamplerStats = struct {
        total_records: u64,
        current_rate: f64,
        window_count: u32,
    };
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
