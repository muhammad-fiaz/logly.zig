# Sampling Example

Control log throughput using sampling strategies for high-volume applications.

## Probability Sampling

```zig
const std = @import("std");
const logly = @import("logly");
const Sampler = logly.Sampler;
const Config = logly.Config;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Enable colors on Windows
    _ = logly.Terminal.enableAnsiColors();

    const logger = try logly.Logger.init(allocator);
    defer logger.deinit();

    // Create sampler with 50% probability
    var sampler = Sampler.init(allocator, .{ .probability = 0.5 });
    defer sampler.deinit();

    // Check if log should be sampled before logging
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        if (sampler.shouldSample()) {
            try logger.infof("Log message {d}", .{i}, @src());
        }
    }
}
```

## Rate Limiting

```zig
// Rate limit to 100 messages per 1000ms (1 second)
var sampler = Sampler.init(allocator, .{ .rate_limit = .{
    .max_records = 100,
    .window_ms = 1000,
}});
defer sampler.deinit();

// After 100 logs/second, remaining logs are dropped until next window
for (0..200) |i| {
    if (sampler.shouldSample()) {
        try logger.infof("Message {d}", .{i}, @src());
    }
}
```

## Callbacks and Statistics

You can monitor sampling behavior using callbacks and statistics.

```zig
const std = @import("std");
const logly = @import("logly");
const Sampler = logly.Sampler;
const Config = logly.Config;

fn onReject(rate: f64, reason: Sampler.SampleRejectReason) void {
    std.debug.print("Sample rejected (rate: {d:.2}, reason: {s})\n", .{ rate, @tagName(reason) });
}

fn onRateExceeded(count: u32, max: u32) void {
    std.debug.print("Rate limit exceeded: {d}/{d}\n", .{ count, max });
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var sampler = Sampler.init(allocator, .{ .rate_limit = .{
        .max_records = 5,
        .window_ms = 1000,
    }});
    defer sampler.deinit();

    sampler.setRejectCallback(onReject);
    sampler.setRateLimitCallback(onRateExceeded);

    for (0..10) |i| {
        if (sampler.shouldSample()) {
            std.debug.print("Log {d} accepted\n", .{i});
        }
    }

    const stats = sampler.getStats();
    std.debug.print("Stats: Total={d}, Accepted={d}, Rejected={d}\n", .{
        stats.total_records_sampled.load(.monotonic),
        stats.records_accepted.load(.monotonic),
        stats.records_rejected.load(.monotonic),
    });
}
```

## Adaptive Sampling

```zig
// Automatically adjust sampling based on throughput
var sampler = Sampler.init(allocator, .{ .adaptive = .{
    .target_rate = 1000,            // Target 1000 logs/second
    .min_sample_rate = 0.01,        // Never go below 1%
    .max_sample_rate = 1.0,         // Up to 100%
    .adjustment_interval_ms = 1000, // Adjust every second
}});
defer sampler.deinit();
```

## Every Nth Record

```zig
// Sample every 10th record
var sampler = Sampler.init(allocator, .{ .every_n = 10 });
defer sampler.deinit();

// Only every 10th log passes through
for (0..100) |i| {
    if (sampler.shouldSample()) {
        try logger.infof("Sampled message {d}", .{i}, @src());
    }
}
```

## Sampler Presets

```zig
const SamplerPresets = logly.SamplerPresets;

// No sampling - all records pass through
var none_sampler = SamplerPresets.none(allocator);
defer none_sampler.deinit();

// Sample approximately 10% of records
var sample_10 = SamplerPresets.sample10Percent(allocator);
defer sample_10.deinit();

// Limit to 100 records per second
var limit_100 = SamplerPresets.limit100PerSecond(allocator);
defer limit_100.deinit();

// Sample every 10th record
var every_10th = SamplerPresets.every10th(allocator);
defer every_10th.deinit();

// Adaptive sampling targeting 1000 records per second
var adaptive = SamplerPresets.adaptive1000PerSecond(allocator);
defer adaptive.deinit();
```

## Sampler Statistics

```zig
// Get current sampling statistics
const stats = sampler.getStats();
std.debug.print("Total records: {d}\n", .{stats.total_records});
std.debug.print("Current rate: {d:.2}\n", .{stats.current_rate});
std.debug.print("Window count: {d}\n", .{stats.window_count});

// Reset sampler state
sampler.reset();
```

## When to Use Sampling

| Scenario | Recommended Sampling |
|----------|---------------------|
| Development | None (100%) |
| Staging | Light (50-100%) |
| Production | Moderate (10-50%) |
| High Traffic | Aggressive (1-10%) |
| Critical Systems | Errors at 100% |

## Best Practices

1. **Always keep errors** - Never sample error-level logs
2. **Monitor sample rates** - Ensure you're not missing important logs
3. **Adjust dynamically** - Use adaptive sampling for variable loads
4. **Document sampling** - Make sampling configuration visible
