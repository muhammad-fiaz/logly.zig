---
title: Sampler API Reference
description: API reference for Logly.zig Sampler struct. Control log volume with probability sampling, rate limiting, every-Nth, and adaptive sampling strategies.
head:
  - - meta
    - name: keywords
      content: sampler api, log sampling, rate limiting, probability sampling, throughput control, adaptive sampling
  - - meta
    - property: og:title
      content: Sampler API Reference | Logly.zig
---

# Sampler API

The `Sampler` struct controls log throughput by selectively processing records.

## Overview

Samplers reduce log volume in high-throughput systems using probability, rate-limit, every-N, adaptive, and token-bucket strategies. Sampling state is mutex-protected; counters are atomic.

## Types

### Sampler

The main sampler controller with atomic state and statistics.

```zig
pub const Sampler = struct {
    allocator: std.mem.Allocator,
    strategy: Strategy,
    bypassLevels: ?LevelMask = null,
    state: SamplerState,
    mutex: std.Io.Mutex,
    io: std.Io,

    onSampleAccept: ?*const fn (f64) void = null,
    onSampleReject: ?*const fn (f64, SampleRejectReason) void = null,
    onRateExceeded: ?*const fn (u32, u32) void = null,
    onRateAdjustment: ?*const fn (f64, f64, []const u8) void = null,
};
```

### Strategy

The sampling strategy to use.

```zig
pub const Strategy = union(enum) {
    none: void,                  // No sampling, all pass
    probability: f64,            // 0.0 - 1.0
    rateLimit: SamplingRateLimitConfig,
    everyN: u32,                // 1 in N
    adaptive: AdaptiveConfig,
    tokenBucket: TokenBucketConfig, // Token bucket for burst sampling
};
```

### SamplingRateLimitConfig

Configuration for rate limiting.

```zig
pub const SamplingRateLimitConfig = struct {
    maxRecords: u32,    // Maximum records per window
    windowMs: u64,      // Window size in milliseconds
};
```

### AdaptiveConfig

Configuration for adaptive sampling.

```zig
pub const AdaptiveConfig = struct {
    targetRate: u32,                    // Target logs per second (0 is normalized to 1)
    minSampleRate: f64 = 0.01,          // Minimum sampling probability
    maxSampleRate: f64 = 1.0,           // Maximum sampling probability
    adjustmentIntervalMs: u64 = 1000,   // How often to adjust (0 is normalized to the default)
};
```

### TokenBucketConfig

Configuration for token bucket (burst) sampling.

```zig
pub const TokenBucketConfig = struct {
    burstCapacity: u32,     // Maximum tokens (burst capacity)
    refillRatePerSec: u32,  // Tokens added per second
};
```

### SamplingConfig

`Sampler.initWithConfig` accepts `Config.SamplingConfig`.

```zig
pub const SamplingConfig = struct {
    enabled: bool = false,
    strategy: Strategy = .{ .probability = 1.0 },
    bypassLevels: ?LevelMask = null,
};
```

### SamplerStats

Statistics for sampler operations.

```zig
pub const SamplerStats = struct {
    totalRecordsSampled: std.atomic.Value(u64),
    recordsAccepted: std.atomic.Value(u64),
    recordsRejected: std.atomic.Value(u64),
    rateLimitExceeded: std.atomic.Value(u64),
    rateAdjustments: std.atomic.Value(u64),
};
```

### SampleDecision

Detailed decision payload returned by `shouldSampleWithReason()`.

```zig
pub const SampleDecision = struct {
    accepted: bool,
    sampleRate: f64,
    rejectReason: ?SampleRejectReason = null,
};
```

## Methods

### Initialization

#### `init(allocator: std.mem.Allocator, strategy: Strategy) Sampler`

Initializes a new Sampler instance with the specified strategy.

#### `initWithConfig(allocator: std.mem.Allocator, config: Config.SamplingConfig) Sampler`

Initializes a new Sampler with full configuration.

#### `initWithIo(allocator: std.mem.Allocator, io_handle: std.Io, config: Config.SamplingConfig) Sampler`

Initializes a new Sampler with an explicit I/O handle and full configuration.

#### `deinit(self: *Sampler) void`

Releases all resources associated with the sampler.

### Sampling

#### `shouldSample() bool`

Determines if the current record should be sampled (processed). Returns `true` to process, `false` to drop.

#### `shouldSampleKey(key: []const u8) bool`

Deterministically samples based on a stable key (user/session/etc.).

#### `shouldSampleKeyWithReason(key: []const u8) SampleDecision`

Deterministic sampling decision with reject reason details.

#### `shouldSampleWithReason() SampleDecision`

Evaluates sampling and returns structured decision details including reject reason.

#### `setStrategy(strategy: Strategy) void`

Updates sampler strategy at runtime and resets strategy-specific counters.

#### `setProbability(probabilityValue: f64) void`

Sets probability sampling strategy and clamps value into `[0.0, 1.0]`.

#### `setRateLimit(maxRecords: u32, windowMs: u64) void`

Sets rate-limit strategy with safe normalization:

- `maxRecords == 0` becomes `1`
- `windowMs == 0` uses centralized default window

#### `setEveryN(n: u32) void`

Sets deterministic every-N sampling strategy.

#### `setAdaptive(config: AdaptiveConfig) void`

Sets adaptive strategy and normalizes min/max sampling bounds.

#### `disableSampling() void`

Disables filtering strategy (`.none`) so all records are accepted.

#### `remainingWindowQuota() ?u32`

For `.rateLimit` strategy, returns remaining records in current window. Returns `null` for non-rate-limit strategies.

#### `windowResetInMs() ?u64`

For `.rateLimit` strategy, returns milliseconds until current window reset. Returns `null` for non-rate-limit strategies.

#### `acceptRate() f64`

Convenience wrapper around sampler stats accept rate.

#### `rejectRate() f64`

Convenience wrapper around sampler stats reject rate.

### Statistics

#### `getStats() SamplerStats`

Returns current sampler statistics.

#### `getCurrentRate() f64`

Returns the current sampling rate.

#### `resetStats() void`

Resets all statistics to zero.

#### `totalProcessed() u64`

Returns total records processed.

#### `totalAccepted() u64`

Returns total records accepted.

#### `totalRejected() u64`

Returns total records rejected.

### SamplerStats Methods

The `SamplerStats` struct tracks counters and rates:

```zig
pub const SamplerStats = struct {
    totalRecordsSampled: std.atomic.Value(Constants.AtomicUnsigned),
    recordsAccepted: std.atomic.Value(Constants.AtomicUnsigned),
    recordsRejected: std.atomic.Value(Constants.AtomicUnsigned),
    rateLimitExceeded: std.atomic.Value(Constants.AtomicUnsigned),
    rateAdjustments: std.atomic.Value(Constants.AtomicUnsigned),

    /// Calculate current accept rate (0.0 - 1.0)
    pub fn getAcceptRate(self: *const SamplerStats) f64;

    /// Calculate current reject rate (0.0 - 1.0)
    pub fn getRejectRate(self: *const SamplerStats) f64;

    /// Returns true if any records have been rejected.
    pub fn hasRejections(self: *const SamplerStats) bool;

    /// Returns true if rate limit has been exceeded at least once.
    pub fn hasRateLimitExceeded(self: *const SamplerStats) bool;

    /// Returns the rate limit exceeded percentage (0.0 - 1.0).
    pub fn getRateLimitExceededRate(self: *const SamplerStats) f64;

    /// Returns total records sampled as u64.
    pub fn getTotal(self: *const SamplerStats) u64;

    /// Returns accepted records count as u64.
    pub fn getAccepted(self: *const SamplerStats) u64;

    /// Returns rejected records count as u64.
    pub fn getRejected(self: *const SamplerStats) u64;
};
```

### State

#### `isEnabled() bool`

Returns true if sampling is enabled (strategy != none).

#### `strategyName() []const u8`

Returns the name of the current strategy.

### Callbacks

#### `setAcceptCallback(callback: *const fn (f64) void) void`

Sets the callback invoked when a record passes sampling. The argument is the effective sample rate.

#### `setRejectCallback(callback: *const fn (f64, SampleRejectReason) void) void`

Sets the callback invoked when a record is rejected.

#### `setRateLimitCallback(callback: *const fn (u32, u32) void) void`

Sets the callback invoked when a rate limit is exceeded. Arguments are the current count and the configured maximum.

#### `setAdjustmentCallback(callback: *const fn (f64, f64, []const u8) void) void`

Sets the callback invoked when adaptive sampling changes the rate. Arguments are the old rate, new rate, and strategy name.

## Presets

### SamplerPresets

```zig
pub const SamplerPresets = struct {
    /// No sampling - all records pass through.
    pub fn none(allocator: std.mem.Allocator) Sampler;

    /// Sample approximately 10% of records.
    pub fn sample10Percent(allocator: std.mem.Allocator) Sampler;

    /// Sample approximately 50% of records.
    pub fn sample50Percent(allocator: std.mem.Allocator) Sampler;

    /// Sample approximately 1% of records (high-volume production).
    pub fn sample1Percent(allocator: std.mem.Allocator) Sampler;

    /// Limit to 10 records per second (debug/low-volume).
    pub fn limit10PerSecond(allocator: std.mem.Allocator) Sampler;

    /// Limit to 100 records per second.
    pub fn limit100PerSecond(allocator: std.mem.Allocator) Sampler;

    /// Limit to 1000 records per second.
    pub fn limit1000PerSecond(allocator: std.mem.Allocator) Sampler;

    /// Sample every 5th record.
    pub fn every5th(allocator: std.mem.Allocator) Sampler;

    /// Sample every 10th record.
    pub fn every10th(allocator: std.mem.Allocator) Sampler;

    /// Sample every 100th record (high-volume production).
    pub fn every100th(allocator: std.mem.Allocator) Sampler;

    /// Adaptive sampling targeting 100 records per second.
    pub fn adaptive100PerSecond(allocator: std.mem.Allocator) Sampler;

    /// Adaptive sampling targeting 1000 records per second.
    pub fn adaptive1000PerSecond(allocator: std.mem.Allocator) Sampler;

    /// Creates a sampled sink configuration.
    pub fn createSampledSink(filePath: []const u8) SinkConfig;
};
```

## Example

```zig
const Sampler = @import("logly").Sampler;
const SamplerPresets = @import("logly").SamplerPresets;

// Create sampler with 10% probability
var sampler = Sampler.init(allocator, .{ .probability = 0.1 });
defer sampler.deinit();

// Or use presets
var sampler2 = SamplerPresets.limit100PerSecond(allocator);
defer sampler2.deinit();

// Check if record should be sampled
for (records) |record| {
    if (sampler.shouldSample()) {
        // Process this record
        processRecord(record);
    }
}

// Check statistics
const stats = sampler.getStats();
std.debug.print("Accept rate: {d:.2}%\n", .{stats.getAcceptRate() * 100});
std.debug.print("Processed: {d}, Accepted: {d}, Rejected: {d}\n", .{
    sampler.totalProcessed(),
    sampler.totalAccepted(),
    sampler.totalRejected(),
});

// Check if sampling is active
if (sampler.isEnabled()) {
    std.debug.print("Strategy: {s}\n", .{sampler.strategyName()});
}
```

## Strategy Selection Guide

| Strategy | Use Case | Overhead |
|----------|----------|----------|
| `none` | No sampling needed | Zero |
| `probability` | Random sampling for debugging | Very low |
| `rateLimit` | Strict throughput control | Low |
| `everyN` | Predictable sampling | Very low |
| `adaptive` | Dynamic load handling | Low |
| `tokenBucket` | Burstable rate limiting | Low |

## Performance

- Atomic counters for statistics
- Mutex-protected strategy state
- Adaptive adjustment only during adjustment intervals

## See Also

- [Filtering Guide](../guide/filtering.md) - Content-based filtering
- [Metrics API](metrics.md) - Performance monitoring
