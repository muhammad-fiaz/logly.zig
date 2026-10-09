//! Log sampling.
//!
//! Probability, rate-limit, every-N, adaptive, and token-bucket strategies.
const std = @import("std");
const Config = @import("config.zig").Config;
const SinkConfig = @import("sink.zig").SinkConfig;
const Constants = @import("constants.zig");
const Utils = @import("utils.zig");

/// Sampler for controlling log throughput with comprehensive monitoring.
pub const Sampler = struct {
    /// Sampling statistics for monitoring and diagnostics.
    pub const SamplerStats = struct {
        totalRecordsSampled: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        recordsAccepted: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        recordsRejected: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        rateLimitExceeded: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        rateAdjustments: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),

        /// Calculate current accept rate (0.0 - 1.0)
        pub fn getAcceptRate(self: *const SamplerStats) f64 {
            return Utils.calculateRate(
                Utils.atomicLoadU64(&self.recordsAccepted),
                Utils.atomicLoadU64(&self.totalRecordsSampled),
            );
        }

        /// Calculate current reject rate (0.0 - 1.0)
        pub fn getRejectRate(self: *const SamplerStats) f64 {
            return Utils.calculateRate(
                Utils.atomicLoadU64(&self.recordsRejected),
                Utils.atomicLoadU64(&self.totalRecordsSampled),
            );
        }

        /// Returns true if any records have been rejected.
        pub fn hasRejections(self: *const SamplerStats) bool {
            return Utils.atomicLoadU64(&self.recordsRejected) > 0;
        }

        /// Returns true if rate limit has been exceeded at least once.
        pub fn hasRateLimitExceeded(self: *const SamplerStats) bool {
            return Utils.atomicLoadU64(&self.rateLimitExceeded) > 0;
        }

        /// Returns the rate limit exceeded percentage (0.0 - 1.0).
        pub fn getRateLimitExceededRate(self: *const SamplerStats) f64 {
            return Utils.calculateRate(
                Utils.atomicLoadU64(&self.rateLimitExceeded),
                Utils.atomicLoadU64(&self.recordsRejected),
            );
        }

        /// Returns total records sampled as u64.
        pub fn getTotal(self: *const SamplerStats) u64 {
            return Utils.atomicLoadU64(&self.totalRecordsSampled);
        }

        /// Returns accepted records count as u64.
        pub fn getAccepted(self: *const SamplerStats) u64 {
            return Utils.atomicLoadU64(&self.recordsAccepted);
        }

        /// Returns rejected records count as u64.
        pub fn getRejected(self: *const SamplerStats) u64 {
            return Utils.atomicLoadU64(&self.recordsRejected);
        }
    };

    /// Reason for rejecting a sample.
    pub const SampleRejectReason = enum {
        /// Rejected due to probability sampling threshold.
        probabilityFilter,
        /// Rejected because rate limit was exceeded in current window.
        rateLimitExceeded,
        /// Rejected by every-N sampling (not Nth record).
        everyNFilter,
        /// Rejected by adaptive sampling rate.
        adaptiveRateExceeded,
        /// Rejected because sampling strategy is disabled.
        strategyDisabled,
    };

    /// Detailed sampling decision payload.
    pub const SampleDecision = struct {
        /// Whether the record was accepted by sampler.
        accepted: bool,
        /// Effective sampling rate used for the decision.
        sampleRate: f64,
        /// Optional reject reason when `accepted` is false.
        rejectReason: ?SampleRejectReason = null,
        /// Whether this was accepted because of a bypass level.
        bypassed: bool = false,
    };

    const RateExceededInfo = struct { count: u32, max: u32 };
    const AdjustmentInfo = struct { old: f64, new: f64 };

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
        windowStart: i64 = 0,
        /// Number of records in current window.
        windowCount: u32 = 0,
        /// Current adaptive sampling rate.
        currentRate: f64 = 1.0,
        /// Last time adaptive rate was adjusted.
        lastAdjustment: i64 = 0,
        /// Random number generator for probability sampling.
        rng: std.Random.DefaultPrng,
        /// Tokens available for token bucket.
        tokens: f64 = 0.0,
        /// Last refill time for token bucket.
        lastRefill: i64 = 0,

        /// Thread-safe statistics.
        stats: SamplerStats = .{},

        fn init() SamplerState {
            const seed = @as(u64, @intCast(Utils.currentMillis()));
            return .{
                .rng = std.Random.DefaultPrng.init(seed),
            };
        }
    };

    /// Memory allocator for any future allocations.
    allocator: std.mem.Allocator,
    /// Active sampling strategy.
    strategy: Strategy,
    /// Mask of levels that always bypass sampling.
    bypassLevels: ?@import("level.zig").LevelMask = null,
    /// Internal state (counters, RNG, window tracking).
    state: SamplerState,
    /// Mutex for thread-safe operations.
    mutex: std.Io.Mutex = std.Io.Mutex.init,
    /// Explicit I/O handle.
    io: std.Io = Utils.defaultIo(),

    /// Callback invoked when a record passes sampling.
    onSampleAccept: ?*const fn (f64) void = null,

    /// Callback invoked when a record is rejected by sampling.
    onSampleReject: ?*const fn (f64, SampleRejectReason) void = null,

    /// Callback invoked when rate limit is exceeded.
    onRateExceeded: ?*const fn (u32, u32) void = null,

    /// Callback invoked when adaptive sampling rate is adjusted.
    onRateAdjustment: ?*const fn (f64, f64, []const u8) void = null,

    /// Initializes a new Sampler with the specified strategy.
    pub fn init(allocator: std.mem.Allocator, strategy: Strategy) Sampler {
        return initWithConfig(allocator, .{ .strategy = strategy });
    }

    /// Initializes a new Sampler with full configuration.
    pub fn initWithConfig(allocator: std.mem.Allocator, config: Config.SamplingConfig) Sampler {
        return initWithIo(allocator, Utils.defaultIo(), config);
    }

    /// Initializes a new Sampler with explicit I/O handle and full configuration.
    pub fn initWithIo(allocator: std.mem.Allocator, io_handle: std.Io, config: Config.SamplingConfig) Sampler {
        var sampler = Sampler{
            .allocator = allocator,
            .io = io_handle,
            .strategy = config.strategy,
            .bypassLevels = config.bypassLevels,
            .state = SamplerState.init(),
        };
        sampler.resetStateForStrategy();
        return sampler;
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
        self.onSampleAccept = callback;
    }

    /// Sets the callback for when a record is rejected.
    pub fn setRejectCallback(self: *Sampler, callback: *const fn (f64, SampleRejectReason) void) void {
        self.onSampleReject = callback;
    }

    /// Sets the callback for rate limit exceeded events.
    pub fn setRateLimitCallback(self: *Sampler, callback: *const fn (u32, u32) void) void {
        self.onRateExceeded = callback;
    }

    /// Sets the callback for rate adjustments (adaptive sampling).
    pub fn setAdjustmentCallback(self: *Sampler, callback: *const fn (f64, f64, []const u8) void) void {
        self.onRateAdjustment = callback;
    }

    /// Determines whether a record should be sampled (allowed through).
    ///
    /// This method is thread-safe and optimized for minimal contention.
    pub fn shouldSample(self: *Sampler) bool {
        return self.shouldSampleWithReason().accepted;
    }

    /// Checks if a specific log level bypasses sampling entirely.
    pub fn shouldSampleLevel(self: *Sampler, level: @import("level.zig").Level) bool {
        return self.shouldSampleLevelWithReason(level).accepted;
    }

    /// Clamps a sampling rate into [0.0, 1.0] (NaN becomes 0.0).
    ///
    /// Out-of-range sampling inputs are normalized, never rejected: this is
    /// explicit API behavior so hot-path construction cannot fail. The
    /// effective (clamped) rate is what sampling decisions use.
    fn clampRate(inputRate: f64) f64 {
        if (std.math.isNan(inputRate)) return 0.0;
        return std.math.clamp(inputRate, 0.0, 1.0);
    }

    fn evaluateSampleDecisionLocked(
        self: *Sampler,
        now: i64,
        rateExceededInfo: *?RateExceededInfo,
        adjustmentInfo: *?AdjustmentInfo,
    ) SampleDecision {
        return switch (self.strategy) {
            .none => .{ .accepted = true, .sampleRate = 1.0 },
            .probability => |prob| blk: {
                const effective = clampRate(prob);
                const random = self.state.rng.random().float(f64);
                if (random < effective) {
                    break :blk .{ .accepted = true, .sampleRate = effective };
                }
                break :blk .{
                    .accepted = false,
                    .sampleRate = effective,
                    .rejectReason = .probabilityFilter,
                };
            },
            .rateLimit => |config| blk: {
                const windowMs: i64 = @intCast(config.windowMs);

                if (now - self.state.windowStart >= windowMs) {
                    self.state.windowStart = now;
                    self.state.windowCount = 0;
                }

                if (self.state.windowCount < config.maxRecords) {
                    self.state.windowCount += 1;
                    break :blk .{ .accepted = true, .sampleRate = 1.0 };
                }

                _ = self.state.stats.rateLimitExceeded.fetchAdd(1, .monotonic);
                rateExceededInfo.* = .{ .count = self.state.windowCount, .max = config.maxRecords };
                break :blk .{
                    .accepted = false,
                    .sampleRate = 1.0,
                    .rejectReason = .rateLimitExceeded,
                };
            },
            .everyN => |n| blk: {
                if (n == 0) {
                    break :blk .{ .accepted = true, .sampleRate = 1.0 };
                }

                const effective = 1.0 / @as(f64, @floatFromInt(n));
                self.state.counter += 1;
                if ((self.state.counter % n) == 0) {
                    break :blk .{ .accepted = true, .sampleRate = effective };
                }

                break :blk .{
                    .accepted = false,
                    .sampleRate = effective,
                    .rejectReason = .everyNFilter,
                };
            },
            .adaptive => |config| blk: {
                if (Utils.elapsedMs(self.state.lastAdjustment) >= config.adjustmentIntervalMs) {
                    const actualRate = Utils.calculateThroughputMs(self.state.windowCount, @intCast(config.adjustmentIntervalMs));
                    const oldRate = self.state.currentRate;
                    const target: f64 = @floatFromInt(config.targetRate);

                    if (actualRate > target) {
                        self.state.currentRate = @max(config.minSampleRate, self.state.currentRate * 0.9);
                    } else {
                        self.state.currentRate = @min(config.maxSampleRate, self.state.currentRate * 1.1);
                    }

                    if (self.state.currentRate != oldRate) {
                        _ = self.state.stats.rateAdjustments.fetchAdd(1, .monotonic);
                        adjustmentInfo.* = .{ .old = oldRate, .new = self.state.currentRate };
                    }

                    self.state.windowCount = 0;
                    self.state.lastAdjustment = now;
                }

                self.state.windowCount += 1;
                const effective = clampRate(self.state.currentRate);
                const random = self.state.rng.random().float(f64);
                if (random < effective) {
                    break :blk .{ .accepted = true, .sampleRate = effective };
                }

                break :blk .{
                    .accepted = false,
                    .sampleRate = effective,
                    .rejectReason = .adaptiveRateExceeded,
                };
            },
            .tokenBucket => |config| blk: {
                const elapsedMs = now - self.state.lastRefill;
                const tokensToAdd = @as(f64, @floatFromInt(elapsedMs)) * (@as(f64, @floatFromInt(config.refillRatePerSec)) / 1000.0);

                self.state.tokens = @min(self.state.tokens + tokensToAdd, @as(f64, @floatFromInt(config.burstCapacity)));
                self.state.lastRefill = now;

                if (self.state.tokens >= 1.0) {
                    self.state.tokens -= 1.0;
                    break :blk .{ .accepted = true, .sampleRate = 1.0 };
                }

                _ = self.state.stats.rateLimitExceeded.fetchAdd(1, .monotonic);
                break :blk .{
                    .accepted = false,
                    .sampleRate = 1.0,
                    .rejectReason = .rateLimitExceeded,
                };
            },
        };
    }

    /// Determines whether a record should be sampled and includes decision details.
    pub fn shouldSampleWithReason(self: *Sampler) SampleDecision {
        return self.shouldSampleLevelWithReason(null);
    }

    /// Determines whether a record of the specified level should be sampled.
    pub fn shouldSampleLevelWithReason(self: *Sampler, level: ?@import("level.zig").Level) SampleDecision {
        if (level) |lvl| {
            if (self.bypassLevels) |bypass| {
                if (bypass.isEnabled(lvl)) {
                    return self.applyDecision(.{ .accepted = true, .sampleRate = 1.0, .bypassed = true }, null, null);
                }
            }
        }

        // Fast path: sampling disabled means immediate accept with no
        // clock reads, no locking, and no statistics traffic.
        if (self.strategy == .none) {
            return .{ .accepted = true, .sampleRate = 1.0 };
        }

        _ = self.state.stats.totalRecordsSampled.fetchAdd(1, .monotonic);

        var rateExceededInfo: ?RateExceededInfo = null;
        var adjustmentInfo: ?AdjustmentInfo = null;

        self.mutex.lockUncancelable(self.io);
        const sampleDecision = self.evaluateSampleDecisionLocked(
            Utils.monotonicMillis(),
            &rateExceededInfo,
            &adjustmentInfo,
        );
        self.mutex.unlock(self.io);

        return self.applyDecision(sampleDecision, rateExceededInfo, adjustmentInfo);
    }

    /// Determines whether a record should be sampled using a deterministic key.
    ///
    /// Useful when you want consistent sampling for the same ID (user/session/etc.).
    pub fn shouldSampleKey(self: *Sampler, key: []const u8) bool {
        return self.shouldSampleKeyWithReason(key).accepted;
    }

    /// Determines whether a record should be sampled using a deterministic key,
    /// returning the structured decision payload.
    pub fn shouldSampleKeyWithReason(self: *Sampler, key: []const u8) SampleDecision {
        return switch (self.strategy) {
            // Fast path: sampling disabled means immediate accept.
            .none => .{ .accepted = true, .sampleRate = 1.0 },
            .probability => |prob| blk: {
                _ = self.state.stats.totalRecordsSampled.fetchAdd(1, .monotonic);
                const effective = clampRate(prob);
                const roll = hashToUnitInterval(key);
                if (roll < effective) {
                    break :blk self.applyDecision(.{ .accepted = true, .sampleRate = effective }, null, null);
                }
                break :blk self.applyDecision(.{ .accepted = false, .sampleRate = effective, .rejectReason = .probabilityFilter }, null, null);
            },
            .everyN => |n| blk: {
                _ = self.state.stats.totalRecordsSampled.fetchAdd(1, .monotonic);
                if (n == 0) {
                    break :blk self.applyDecision(.{ .accepted = true, .sampleRate = 1.0 }, null, null);
                }
                const effective = 1.0 / @as(f64, @floatFromInt(n));
                const keyChoice = if (@mod(hashToU64(key), @as(u64, n)) == 0)
                    SampleDecision{ .accepted = true, .sampleRate = effective }
                else
                    SampleDecision{ .accepted = false, .sampleRate = effective, .rejectReason = .everyNFilter };
                break :blk self.applyDecision(keyChoice, null, null);
            },
            .rateLimit, .adaptive, .tokenBucket => self.shouldSampleWithReason(),
        };
    }

    fn applyDecision(
        self: *Sampler,
        sampleDecision: SampleDecision,
        rateExceededInfo: ?RateExceededInfo,
        adjustmentInfo: ?AdjustmentInfo,
    ) SampleDecision {
        if (adjustmentInfo) |info| {
            if (self.onRateAdjustment) |cb| cb(info.old, info.new, "throughput adjustment");
        }

        if (rateExceededInfo) |info| {
            if (self.onRateExceeded) |cb| cb(info.count, info.max);
        }

        if (sampleDecision.accepted) {
            _ = self.state.stats.recordsAccepted.fetchAdd(1, .monotonic);
            if (self.onSampleAccept) |cb| cb(sampleDecision.sampleRate);
        } else {
            _ = self.state.stats.recordsRejected.fetchAdd(1, .monotonic);
            if (self.onSampleReject) |cb| cb(sampleDecision.sampleRate, sampleDecision.rejectReason orelse .strategyDisabled);
        }

        return sampleDecision;
    }

    fn hashToU64(key: []const u8) u64 {
        return std.hash.Wyhash.hash(0, key);
    }

    fn hashToUnitInterval(key: []const u8) f64 {
        const hash = hashToU64(key);
        const denom: f64 = @floatFromInt(std.math.maxInt(u64));
        return @as(f64, @floatFromInt(hash)) / denom;
    }

    fn resetStateForStrategy(self: *Sampler) void {
        self.state.counter = 0;
        self.state.windowCount = 0;
        self.state.windowStart = Utils.monotonicMillis();
        self.state.lastAdjustment = Utils.monotonicMillis();
        self.state.lastRefill = Utils.monotonicMillis();
        self.state.currentRate = switch (self.strategy) {
            .adaptive => clampRate(self.state.currentRate),
            .probability => |prob| clampRate(prob),
            .none, .rateLimit, .tokenBucket => 1.0,
            .everyN => |n| if (n == 0) 1.0 else 1.0 / @as(f64, @floatFromInt(n)),
        };
        self.state.tokens = switch (self.strategy) {
            .tokenBucket => |config| @as(f64, @floatFromInt(config.burstCapacity)),
            else => 0.0,
        };
    }

    /// Updates strategy at runtime and resets strategy-specific counters.
    pub fn setStrategy(self: *Sampler, strategy: Strategy) void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);

        self.strategy = strategy;
        self.resetStateForStrategy();
    }

    /// Sets probability strategy using clamped probability [0.0, 1.0].
    pub fn setProbability(self: *Sampler, probabilityValue: f64) void {
        self.setStrategy(.{ .probability = clampRate(probabilityValue) });
    }

    /// Sets rate-limit strategy.
    ///
    /// Zero values are normalized to safe defaults.
    pub fn setRateLimit(self: *Sampler, maxRecords: u32, windowMs: u64) void {
        self.setStrategy(.{ .rateLimit = .{
            .maxRecords = if (maxRecords == 0) 1 else maxRecords,
            .windowMs = if (windowMs == 0) Constants.SamplingDefaults.rateLimitWindowMs else windowMs,
        } });
    }

    /// Sets every-N strategy. n == 0 disables decimation (accept-all),
    /// matching the evaluation fast path.
    pub fn setEveryN(self: *Sampler, n: u32) void {
        self.setStrategy(.{ .everyN = n });
    }

    /// Sets adaptive strategy and normalizes bounds.
    pub fn setAdaptive(self: *Sampler, config: AdaptiveConfig) void {
        const minRate = clampRate(config.minSampleRate);
        const maxRate = clampRate(config.maxSampleRate);
        const boundedMin = @min(minRate, maxRate);
        const boundedMax = @max(minRate, maxRate);

        self.setStrategy(.{ .adaptive = .{
            .targetRate = if (config.targetRate == 0) 1 else config.targetRate,
            .adjustmentIntervalMs = if (config.adjustmentIntervalMs == 0)
                Constants.SamplingDefaults.adaptiveAdjustmentIntervalMs
            else
                config.adjustmentIntervalMs,
            .minSampleRate = boundedMin,
            .maxSampleRate = boundedMax,
        } });

        self.mutex.lockUncancelable(self.io);
        self.state.currentRate = boundedMax;
        self.mutex.unlock(self.io);
    }

    /// Reseeds the internal RNG for probability-based sampling.
    pub fn setSeed(self: *Sampler, seed: u64) void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        self.state.rng = std.Random.DefaultPrng.init(seed);
    }

    /// Disables filtering and allows all records through.
    pub fn disableSampling(self: *Sampler) void {
        self.setStrategy(.none);
    }

    /// Returns remaining quota in current rate-limit window, if applicable.
    pub fn remainingWindowQuota(self: *Sampler) ?u32 {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);

        return switch (self.strategy) {
            .rateLimit => |config| {
                if (self.state.windowCount >= config.maxRecords) return 0;
                return config.maxRecords - self.state.windowCount;
            },
            else => null,
        };
    }

    /// Returns milliseconds until rate-limit window reset, if applicable.
    pub fn windowResetInMs(self: *Sampler) ?u64 {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);

        return switch (self.strategy) {
            .rateLimit => |config| {
                const elapsed = Utils.monotonicMillis() - self.state.windowStart;
                const remaining = @as(i64, @intCast(config.windowMs)) - elapsed;
                return if (remaining > 0) @as(u64, @intCast(remaining)) else 0;
            },
            else => null,
        };
    }

    /// Returns accept rate from stats.
    pub fn acceptRate(self: *const Sampler) f64 {
        return self.state.stats.getAcceptRate();
    }

    /// Returns reject rate from stats.
    pub fn rejectRate(self: *const Sampler) f64 {
        return self.state.stats.getRejectRate();
    }

    /// Resets the sampler state.
    pub fn reset(self: *Sampler) void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);

        self.state = SamplerState.init();
    }

    /// Returns the current sampling rate (for adaptive sampling).
    pub fn getCurrentRate(self: *Sampler) f64 {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);

        return switch (self.strategy) {
            .none => 1.0,
            .probability => |prob| prob,
            .rateLimit, .tokenBucket => 1.0,
            .everyN => |n| 1.0 / @as(f64, @floatFromInt(n)),
            .adaptive => self.state.currentRate,
        };
    }

    /// Returns statistics about the sampler.
    pub fn getStats(self: *Sampler) SamplerStats {
        return .{
            .totalRecordsSampled = std.atomic.Value(Constants.AtomicUnsigned).init(@as(Constants.AtomicUnsigned, self.state.stats.totalRecordsSampled.load(.monotonic))),
            .recordsAccepted = std.atomic.Value(Constants.AtomicUnsigned).init(@as(Constants.AtomicUnsigned, self.state.stats.recordsAccepted.load(.monotonic))),
            .recordsRejected = std.atomic.Value(Constants.AtomicUnsigned).init(@as(Constants.AtomicUnsigned, self.state.stats.recordsRejected.load(.monotonic))),
            .rateLimitExceeded = std.atomic.Value(Constants.AtomicUnsigned).init(@as(Constants.AtomicUnsigned, self.state.stats.rateLimitExceeded.load(.monotonic))),
            .rateAdjustments = std.atomic.Value(Constants.AtomicUnsigned).init(@as(Constants.AtomicUnsigned, self.state.stats.rateAdjustments.load(.monotonic))),
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
            .rateLimit => "rate_limit",
            .everyN => "every_n",
            .adaptive => "adaptive",
            .tokenBucket => "token_bucket",
        };
    }

    /// Returns total records processed.
    pub fn totalProcessed(self: *const Sampler) u64 {
        return @as(u64, self.state.stats.totalRecordsSampled.load(.monotonic));
    }

    /// Returns total records accepted.
    pub fn totalAccepted(self: *const Sampler) u64 {
        return @as(u64, self.state.stats.recordsAccepted.load(.monotonic));
    }

    /// Returns total records rejected.
    pub fn totalRejected(self: *const Sampler) u64 {
        return @as(u64, self.state.stats.recordsRejected.load(.monotonic));
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
        return Sampler.init(allocator, .{ .rateLimit = .{
            .maxRecords = 100,
            .windowMs = Constants.SamplingDefaults.rateLimitWindowMs,
        } });
    }

    /// Limit to 1000 records per second.
    pub fn limit1000PerSecond(allocator: std.mem.Allocator) Sampler {
        return Sampler.init(allocator, .{ .rateLimit = .{
            .maxRecords = Constants.RateLimitDefaults.maxPerSecond,
            .windowMs = Constants.SamplingDefaults.rateLimitWindowMs,
        } });
    }

    /// Limit to 10 records per second (debug/low-volume).
    pub fn limit10PerSecond(allocator: std.mem.Allocator) Sampler {
        return Sampler.init(allocator, .{ .rateLimit = .{
            .maxRecords = 10,
            .windowMs = Constants.SamplingDefaults.rateLimitWindowMs,
        } });
    }

    /// Sample every 10th record.
    pub fn every10th(allocator: std.mem.Allocator) Sampler {
        return Sampler.init(allocator, .{ .everyN = 10 });
    }

    /// Sample every 100th record (high-volume production).
    pub fn every100th(allocator: std.mem.Allocator) Sampler {
        return Sampler.init(allocator, .{ .everyN = 100 });
    }

    /// Sample every 5th record.
    pub fn every5th(allocator: std.mem.Allocator) Sampler {
        return Sampler.init(allocator, .{ .everyN = 5 });
    }

    /// Adaptive sampling targeting 1000 records per second.
    pub fn adaptive1000PerSecond(allocator: std.mem.Allocator) Sampler {
        return Sampler.init(allocator, .{ .adaptive = .{
            .targetRate = Constants.ConfigPresetDefaults.highThroughputSamplingTargetRate,
        } });
    }

    /// Adaptive sampling targeting 100 records per second.
    pub fn adaptive100PerSecond(allocator: std.mem.Allocator) Sampler {
        return Sampler.init(allocator, .{ .adaptive = .{
            .targetRate = 100,
        } });
    }

    /// Creates a sampled sink configuration.
    pub fn createSampledSink(filePath: []const u8) SinkConfig {
        return SinkConfig{
            .path = filePath,
            .color = false,
        };
    }
};

test "sampler probability" {
    var sampler = Sampler.init(std.testing.allocator, .{ .probability = 0.5 });
    defer sampler.deinit();

    var sampled: u32 = 0;
    const iterations: u32 = Constants.ConfigPresetDefaults.highThroughputSamplingTargetRate;
    for (0..iterations) |_| {
        if (sampler.shouldSample()) {
            sampled += 1;
        }
    }

    const rate = @as(f64, @floatFromInt(sampled)) / @as(f64, @floatFromInt(iterations));
    try std.testing.expect(rate > 0.3 and rate < 0.7);
}

test "sampler rate limit" {
    var sampler = Sampler.init(std.testing.allocator, .{ .rateLimit = .{
        .maxRecords = 10,
        .windowMs = Constants.SamplingDefaults.rateLimitWindowMs,
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
    var sampler = Sampler.init(std.testing.allocator, .{ .rateLimit = .{
        .maxRecords = 5,
        .windowMs = Constants.SamplingDefaults.rateLimitWindowMs,
    } });
    defer sampler.deinit();

    for (0..10) |_| {
        _ = sampler.shouldSample();
    }

    const stats = sampler.getStats();
    try std.testing.expectEqual(@as(u64, 10), stats.totalRecordsSampled.load(.monotonic));
    try std.testing.expectEqual(@as(u64, 5), stats.recordsAccepted.load(.monotonic));
    try std.testing.expectEqual(@as(u64, 5), stats.recordsRejected.load(.monotonic));
    try std.testing.expectEqual(@as(u64, 5), stats.rateLimitExceeded.load(.monotonic));
}

test "sampler every_n" {
    var sampler = Sampler.init(std.testing.allocator, .{ .everyN = 3 });
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
        .targetRate = 100,
        .adjustmentIntervalMs = 50,
        .minSampleRate = 0.01,
        .maxSampleRate = 1.0,
    } });
    defer sampler.deinit();

    // Initial rate should be 1.0
    try std.testing.expectEqual(1.0, sampler.getCurrentRate());

    // Stimulate with many records to force rate decrease
    for (0..200) |_| {
        _ = sampler.shouldSample();
    }

    // Wait for adjustment interval
    Utils.sleepMs(60);

    // One more sample to trigger adjustment
    _ = sampler.shouldSample();

    const rate = sampler.getCurrentRate();
    try std.testing.expect(rate < 1.0);
}

test "sampler key-based deterministic sampling" {
    var sampler = Sampler.init(std.testing.allocator, .{ .probability = 0.5 });
    defer sampler.deinit();

    const first = sampler.shouldSampleKey("user-123");
    const second = sampler.shouldSampleKey("user-123");
    try std.testing.expectEqual(first, second);
}

test "sampler decision details include reason" {
    var sampler = Sampler.init(std.testing.allocator, .{ .everyN = 2 });
    defer sampler.deinit();

    const first = sampler.shouldSampleWithReason();
    try std.testing.expect(!first.accepted);
    try std.testing.expect(first.rejectReason != null);

    const second = sampler.shouldSampleWithReason();
    try std.testing.expect(second.accepted);
    try std.testing.expectEqual(@as(?Sampler.SampleRejectReason, null), second.rejectReason);
}

test "sampler rate limit quota helpers" {
    var sampler = Sampler.init(std.testing.allocator, .{ .rateLimit = .{
        .maxRecords = 3,
        .windowMs = 500,
    } });
    defer sampler.deinit();

    try std.testing.expectEqual(@as(?u32, 3), sampler.remainingWindowQuota());
    try std.testing.expect(sampler.windowResetInMs().? <= 500);

    _ = sampler.shouldSample();
    _ = sampler.shouldSample();

    try std.testing.expectEqual(@as(?u32, 1), sampler.remainingWindowQuota());
}

test "sampler set strategy runtime" {
    var sampler = Sampler.init(std.testing.allocator, .{ .probability = 1.0 });
    defer sampler.deinit();

    sampler.setStrategy(.{ .everyN = 3 });
    try std.testing.expect(std.mem.eql(u8, sampler.strategyName(), "every_n"));

    // First two are rejected, third accepted for every_n=3.
    try std.testing.expect(!sampler.shouldSample());
    try std.testing.expect(!sampler.shouldSample());
    try std.testing.expect(sampler.shouldSample());
}

test "sampler explicit strategy control helpers" {
    var sampler = Sampler.init(std.testing.allocator, .none);
    defer sampler.deinit();

    sampler.setProbability(1.5);
    try std.testing.expect(std.mem.eql(u8, sampler.strategyName(), "probability"));
    try std.testing.expectEqual(@as(f64, 1.0), sampler.getCurrentRate());

    sampler.setRateLimit(2, 0);
    try std.testing.expect(std.mem.eql(u8, sampler.strategyName(), "rate_limit"));
    try std.testing.expectEqual(@as(?u32, 2), sampler.remainingWindowQuota());
    _ = sampler.shouldSample();
    _ = sampler.shouldSample();
    try std.testing.expectEqual(@as(?u32, 0), sampler.remainingWindowQuota());

    sampler.setEveryN(2);
    try std.testing.expect(!sampler.shouldSample());
    try std.testing.expect(sampler.shouldSample());

    sampler.setAdaptive(.{
        .targetRate = 0,
        .adjustmentIntervalMs = 0,
        .minSampleRate = 0.8,
        .maxSampleRate = 0.2,
    });
    try std.testing.expect(std.mem.eql(u8, sampler.strategyName(), "adaptive"));
    const adaptiveRate = sampler.getCurrentRate();
    try std.testing.expect(adaptiveRate >= 0.2 and adaptiveRate <= 0.8);

    sampler.disableSampling();
    try std.testing.expect(!sampler.isEnabled());
    try std.testing.expect(sampler.shouldSample());
}

test "sampler token bucket phase 3" {
    const alloc = std.testing.allocator;
    var sampler = Sampler.initWithConfig(alloc, .{ .enabled = true, .strategy = .{ .tokenBucket = .{ .burstCapacity = 3, .refillRatePerSec = 1 } } });
    defer sampler.deinit();

    try std.testing.expect(std.mem.eql(u8, sampler.strategyName(), "token_bucket"));

    // Can sample up to burst capacity (3)
    try std.testing.expect(sampler.shouldSample());
    try std.testing.expect(sampler.shouldSample());
    try std.testing.expect(sampler.shouldSample());
    // 4th should fail since capacity is exhausted
    try std.testing.expect(!sampler.shouldSample());
}

test "sampler bypass levels phase 3" {
    const alloc = std.testing.allocator;
    var bypassMask = @import("level.zig").LevelMask.init();
    bypassMask.enable(.err);

    var sampler = Sampler.initWithConfig(alloc, .{
        .enabled = true,
        .strategy = .{ .probability = 0.0 }, // Would normally reject everything
        .bypassLevels = bypassMask,
    });
    defer sampler.deinit();

    const Record = @import("record.zig").Record;
    var errRecord = Record.init(alloc, .err, "error");
    defer errRecord.deinit();
    var infoRecord = Record.init(alloc, .info, "info");
    defer infoRecord.deinit();

    // Verify bypass logic
    if (sampler.bypassLevels) |mask| {
        try std.testing.expect(mask.isEnabled(errRecord.level));
        try std.testing.expect(!mask.isEnabled(infoRecord.level));
    } else {
        try std.testing.expect(false);
    }
}
