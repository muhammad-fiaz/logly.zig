# Sampler API

The `Sampler` struct controls log throughput by selectively processing records.

## Overview

Samplers are used to reduce log volume in high-throughput systems. They support various strategies like probability sampling, rate limiting, and adaptive sampling.

## Types

### Sampler

The main sampler controller.

```zig
pub const Sampler = struct {
    allocator: std.mem.Allocator,
    strategy: Strategy,
    state: SamplerState,
    stats: SamplerStats,
};
```

### Strategy

The sampling strategy to use.

```zig
pub const Strategy = union(enum) {
    none: void,
    probability: f64,           // 0.0 - 1.0
    rate_limit: RateLimitConfig,
    every_n: u32,              // 1 in N
    adaptive: AdaptiveConfig,
};
```

### RateLimitConfig

Configuration for rate limiting.

```zig
pub const RateLimitConfig = struct {
    max_per_second: u32,
    burst_size: u32,
};
```

### AdaptiveConfig

Configuration for adaptive sampling.

```zig
pub const AdaptiveConfig = struct {
    target_rate: u32,          // Target logs per second
    min_sampling_rate: f64,    // Minimum sampling probability
};
```

## Methods

### `init(allocator: std.mem.Allocator, strategy: Strategy) Sampler`

Initializes a new Sampler instance.

### `shouldSample() bool`

Determines if the current record should be sampled (processed). Returns `true` to process, `false` to drop.

## Presets

`SamplerPresets` provides common sampler configurations.

### `SamplerPresets.probability(p: f64)`

Creates a probability sampler (e.g., 0.1 for 10%).

### `SamplerPresets.rateLimit(max: u32)`

Creates a rate limiter (e.g., 100 logs/sec).

### `SamplerPresets.adaptive(target: u32)`

Creates an adaptive sampler that adjusts to maintain the target rate.
