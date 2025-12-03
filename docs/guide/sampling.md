# Sampling

Logly-Zig v0.0.3+ provides a sophisticated sampling system for controlling log volume in high-throughput scenarios. Sample logs by probability, rate limits, or every-Nth message.

## Overview

The `Sampler` module helps you:
- Reduce log volume while maintaining statistical representation
- Implement rate limiting to prevent log flooding
- Sample every Nth message for consistent reduction
- Use adaptive sampling based on system load

## Basic Usage

```zig
const std = @import("std");
const logly = @import("logly");
const Sampler = logly.Sampler;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create a 50% probability sampler
    var sampler = Sampler.init(allocator, .{ .probability = 0.5 });
    defer sampler.deinit();

    // Check if a log should be sampled
    for (0..100) |i| {
        if (sampler.shouldSample()) {
            std.debug.print("Log message {d}\n", .{i});
        }
    }
    // Approximately 50% of messages will be logged
}
```

## Sampler Presets

Logly-Zig provides convenient presets for common scenarios:

```zig
const SamplerPresets = logly.SamplerPresets;

// No sampling (100% of messages pass through)
var none = SamplerPresets.none(allocator);
defer none.deinit();

// 10% probability sampling
var sample10 = SamplerPresets.sample10Percent(allocator);
defer sample10.deinit();

// Rate limit: 100 messages per second
var rate100 = SamplerPresets.limit100PerSecond(allocator);
defer rate100.deinit();

// Every 10th message passes through
var every10 = SamplerPresets.every10th(allocator);
defer every10.deinit();

// Adaptive: targets 1000 messages per second
var adaptive = SamplerPresets.adaptive1000PerSecond(allocator);
defer adaptive.deinit();
```

## Sampling Strategies

### Probability Sampling

Sample a percentage of messages randomly:

```zig
// 25% of messages will pass through
var sampler = Sampler.init(allocator, .{ .probability = 0.25 });
defer sampler.deinit();

for (0..1000) |_| {
    if (sampler.shouldSample()) {
        // Approximately 250 messages will reach here
    }
}
```

### Rate Limiting

Limit to a maximum number of messages per time window:

```zig
// Allow 100 messages per 1000ms window
var sampler = Sampler.init(allocator, .{ .rate_limit = .{
    .max_records = 100,
    .window_ms = 1000,
}});
defer sampler.deinit();

// First 100 calls in each second pass, rest are dropped
```

### Every-Nth Sampling

Keep every Nth message:

```zig
// Keep every 10th message
var sampler = Sampler.init(allocator, .{ .every_n = 10 });
defer sampler.deinit();

// Messages 10, 20, 30, 40, etc. will pass through
```

### Adaptive Sampling

Automatically adjust sampling rate based on throughput:

```zig
var sampler = Sampler.init(allocator, .{ .adaptive = .{
    .target_rate = 1000,          // Target 1000 msgs/sec
    .min_sample_rate = 0.01,      // Never below 1%
    .max_sample_rate = 1.0,       // Up to 100%
    .adjustment_interval_ms = 1000, // Adjust every second
}});
defer sampler.deinit();
```

## Sampler Statistics

Track sampling performance:

```zig
var sampler = Sampler.init(allocator, .{ .probability = 0.5 });
defer sampler.deinit();

// Sample some logs
for (0..100) |_| {
    _ = sampler.shouldSample();
}

// Get statistics
const stats = sampler.getStats();
std.debug.print("Total records: {d}\n", .{stats.total_records});
std.debug.print("Current rate: {d:.2}\n", .{stats.current_rate});
std.debug.print("Window count: {d}\n", .{stats.window_count});

// Get current sampling rate
const rate = sampler.getCurrentRate();
std.debug.print("Sampling rate: {d:.2}%\n", .{rate * 100});

// Reset statistics
sampler.reset();
```

## Production Example

```zig
const std = @import("std");
const logly = @import("logly");
const Sampler = logly.Sampler;
const SamplerPresets = logly.SamplerPresets;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var logger = try logly.Logger.init(allocator);
    defer logger.deinit();

    // Adaptive sampling for production - targets 1000/sec
    var sampler = SamplerPresets.adaptive1000PerSecond(allocator);
    defer sampler.deinit();

    // High-volume logging with sampling
    var i: usize = 0;
    while (i < 10000) : (i += 1) {
        // Sample debug/info logs
        if (sampler.shouldSample()) {
            try logger.infof("Processing item {d}", .{i});
        }
        
        // Never sample errors - always log them
        // try logger.err("Error if needed");
    }
}
```

## Best Practices

1. **Never sample errors/critical**: Always log 100% of error-level logs
2. **Start conservative**: Begin with higher sampling rates, reduce as needed
3. **Use adaptive for variable loads**: Handles traffic spikes automatically
4. **Monitor statistics**: Use `getStats()` to track sampling effectiveness
5. **Test sampling rates**: Verify you can still debug issues with sampled logs

## See Also

- [Filtering](/guide/filtering) - Rule-based log filtering
- [Metrics](/guide/metrics) - Logging metrics collection
- [Configuration](/guide/configuration) - Global configuration options
