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

Samplers reduce log volume in high-throughput systems using various strategies like probability sampling, rate limiting, every-n sampling, and adaptive sampling. All operations are thread-safe with atomic counters.

## Types

### Sampler

The main sampler controller with atomic state and statistics.

```zig
pub const Sampler = struct {
    allocator: std.mem.Allocator,
    strategy: Strategy,
    state: SamplerState,
    stats: SamplerStats,
    mutex: std.Thread.Mutex,
    
    // Callbacks
    on_sample_accepted: ?*const fn (u64) void,
    on_sample_rejected: ?*const fn (u64) void,
    on_rate_adjusted: ?*const fn (f64, f64) void,
};
```

### Strategy

The sampling strategy to use.

```zig
pub const Strategy = union(enum) {
    none: void,                  // No sampling, all pass
    probability: f64,            // 0.0 - 1.0
    rate_limit: RateLimitConfig,
    every_n: u32,                // 1 in N
    adaptive: AdaptiveConfig,
};
```

### RateLimitConfig

Configuration for rate limiting.

```zig
pub const RateLimitConfig = struct {
    max_records: u64,    // Maximum records per window
    window_ms: u64,      // Window size in milliseconds
};
```

### AdaptiveConfig

Configuration for adaptive sampling.

```zig
pub const AdaptiveConfig = struct {
    target_rate: u32,           // Target logs per second
    min_sampling_rate: f64,     // Minimum sampling probability
    adjustment_interval_ms: u64, // How often to adjust
};
```

### SamplerStats

Statistics for sampler operations.

```zig
pub const SamplerStats = struct {
    total_processed: std.atomic.Value(u64),
    total_accepted: std.atomic.Value(u64),
    total_rejected: std.atomic.Value(u64),
    current_rate: std.atomic.Value(f32),
    
    pub fn acceptRate(self: *const SamplerStats) f64;
};
```

## Methods

### Initialization

#### `init(allocator: std.mem.Allocator, strategy: Strategy) Sampler`

Initializes a new Sampler instance with the specified strategy.

**Alias:** `create`

#### `deinit(self: *Sampler) void`

Releases all resources associated with the sampler.

**Alias:** `destroy`

### Sampling

#### `shouldSample() bool`

Determines if the current record should be sampled (processed). Returns `true` to process, `false` to drop.

**Alias**: `sample`, `check`, `allow`

### Statistics

#### `getStats() SamplerStats`

Returns current sampler statistics.

**Alias**: `statistics`, `stats_`

#### `getCurrentRate() f64`

Returns the current sampling rate.

**Alias**: `rate`

#### `resetStats() void`

Resets all statistics to zero.

#### `totalProcessed() u64`

Returns total records processed.

#### `totalAccepted() u64`

Returns total records accepted.

#### `totalRejected() u64`

Returns total records rejected.

### State

#### `isEnabled() bool`

Returns true if sampling is enabled (strategy != none).

#### `strategyName() []const u8`

Returns the name of the current strategy.

### Callbacks

#### `setAcceptedCallback(callback: *const fn (u64) void) void`

Sets callback for accepted samples.

#### `setRejectedCallback(callback: *const fn (u64) void) void`

Sets callback for rejected samples.

#### `setRateAdjustedCallback(callback: *const fn (f64, f64) void) void`

Sets callback for rate adjustments (adaptive strategy).

## Presets

### SamplerPresets

```zig
pub const SamplerPresets = struct {
    /// No sampling - all records pass through.
    pub fn none(allocator) Sampler;
    
    /// Sample approximately 10% of records.
    pub fn sample10Percent(allocator) Sampler;
    
    /// Sample approximately 50% of records.
    pub fn sample50Percent(allocator) Sampler;
    
    /// Sample approximately 1% of records (high-volume production).
    pub fn sample1Percent(allocator) Sampler;
    
    /// Limit to 10 records per second (debug/low-volume).
    pub fn limit10PerSecond(allocator) Sampler;
    
    /// Limit to 100 records per second.
    pub fn limit100PerSecond(allocator) Sampler;
    
    /// Limit to 1000 records per second.
    pub fn limit1000PerSecond(allocator) Sampler;
    
    /// Sample every 5th record.
    pub fn every5th(allocator) Sampler;
    
    /// Sample every 10th record.
    pub fn every10th(allocator) Sampler;
    
    /// Sample every 100th record (high-volume production).
    pub fn every100th(allocator) Sampler;
    
    /// Adaptive sampling targeting 100 records per second.
    pub fn adaptive100PerSecond(allocator) Sampler;
    
    /// Adaptive sampling targeting 1000 records per second.
    pub fn adaptive1000PerSecond(allocator) Sampler;
    
    /// Creates a sampled sink configuration.
    pub fn createSampledSink(file_path: []const u8) SinkConfig;
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
std.debug.print("Accept rate: {d:.2}%\n", .{stats.acceptRate() * 100});
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
| `rate_limit` | Strict throughput control | Low |
| `every_n` | Predictable sampling | Very low |
| `adaptive` | Dynamic load handling | Low |

## Performance

- **Lock-free** fast path for read-only checks
- **Atomic counters** for thread-safe statistics
- **Minimal overhead** in all strategies
- **Adaptive adjustment** only during adjustment intervals

## See Also

- [Filtering Guide](../guide/filtering.md) - Content-based filtering
- [Metrics API](metrics.md) - Performance monitoring
