# Arena Allocation

Logly.zig supports optional arena allocation for improved performance in high-throughput logging scenarios. Arena allocation reduces memory allocation overhead by batching temporary allocations and releasing them efficiently.

## Overview

Arena allocation is a memory management technique that:
- **Reduces malloc overhead**: Batches small allocations into larger chunks
- **Improves cache locality**: Related allocations are placed near each other
- **Enables efficient cleanup**: Frees all allocations at once with `resetArena()`

## Enabling Arena Allocation

Enable arena allocation via the `use_arena_allocator` config option:

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    // Configure logger with arena allocator
    const config = logly.Config{
        .use_arena_allocator = true,           // Enable arena allocation
        .arena_reset_threshold = 64 * 1024,    // Reset when arena reaches 64KB (default)
    };

    const logger = try logly.Logger.initWithConfig(gpa.allocator(), config);
    defer logger.deinit();

    // Log messages - temporary allocations use arena
    try logger.info(@src(), "High-throughput logging enabled", .{});
}
```

## Thread Pool Integration

When using the Thread Pool, you can enable per-worker arena allocation to further improve performance for parallel logging tasks. Each worker thread maintains its own arena, which is reset after every task, ensuring minimal memory overhead and contention.

```zig
    // Enable Thread Pool with Arena
    config.thread_pool = .{
        .enabled = true,
        .thread_count = 4,
        .enable_arena = true, // Enable per-worker arena
    };
```

## Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `use_arena_allocator` | `bool` | `false` | Enable/disable arena allocation for main logger |
| `thread_pool.enable_arena` | `bool` | `false` | Enable per-worker arena allocation in thread pool |

## Arena Methods

### `scratchAllocator()`

Returns the arena allocator if enabled, otherwise returns the main allocator:

```zig
// Get the scratch allocator for temporary operations
const allocator = logger.scratchAllocator();

// Use for temporary allocations
const temp_buffer = try allocator.alloc(u8, 1024);
defer allocator.free(temp_buffer);
```

### `resetArena()`

Resets the arena allocator, freeing all temporary allocations at once:

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const config = logly.Config{
        .use_arena_allocator = true,
    };

    const logger = try logly.Logger.initWithConfig(gpa.allocator(), config);
    defer logger.deinit();

    // High-throughput logging loop
    var i: usize = 0;
    while (i < 10000) : (i += 1) {
        try logger.info(@src(), "Processing item {d}", .{i});

        // Periodically reset arena to prevent memory growth
        if (i % 1000 == 0) {
            logger.resetArena();
        }
    }

    // Final reset
    logger.resetArena();
    try logger.info(@src(), "Batch processing complete", .{});
}
```

## Thread Pool Integration

When using the Thread Pool for parallel logging, you can also enable per-worker arena allocation. This provides each worker thread with its own arena for temporary allocations during formatting and sink writing, further reducing contention on the global allocator.

```zig
var config = logly.Config.default();
config.thread_pool = .{
    .enabled = true,
    .thread_count = 4,
    .enable_arena = true, // Enable per-worker arena
};
// Also enable main logger arena for initial record creation
config.use_arena_allocator = true;

const logger = try logly.Logger.initWithConfig(allocator, config);
```

With `enable_arena = true`, each worker thread initializes an `ArenaAllocator`. This allocator is passed to the sink's write method, allowing formatters to use it for temporary string building. The arena is automatically reset after each log task is processed.

## High-Throughput Example

For applications with continuous logging, combine arena allocation with periodic resets:

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const config = logly.Config{
        .use_arena_allocator = true,
        .arena_reset_threshold = 32 * 1024, // Smaller threshold for frequent resets
        .show_filename = true,
        .show_lineno = true,
    };

    const logger = try logly.Logger.initWithConfig(gpa.allocator(), config);
    defer logger.deinit();

    // Add file sink for persistent logs
    _ = try logger.add(logly.SinkConfig.file("app.log"));

    // Simulate high-throughput server logs
    var request_count: u64 = 0;
    while (request_count < 100000) : (request_count += 1) {
        try logger.info(@src(), "Request {d} processed", .{request_count});
        try logger.debug(@src(), "Response time: {d}ms", .{request_count % 100});

        // Reset arena every 500 requests
        if (request_count % 500 == 0) {
            logger.resetArena();
            try logger.debug(@src(), "Arena reset at request {d}", .{request_count});
        }
    }

    try logger.success(@src(), "Processed {d} requests", .{request_count});
}
```

## Performance Benefits

Arena allocation provides significant performance improvements when:

- **High log volume**: Thousands of log messages per second
- **Short-lived allocations**: Formatting buffers, temporary strings
- **Batch processing**: Processing large datasets with logging

### Benchmark Comparison

| Scenario | Standard Allocator | Arena Allocator | Improvement |
|----------|-------------------|-----------------|-------------|
| 10K logs/sec | ~150μs/log | ~50μs/log | 3x faster |
| 100K logs/sec | ~200μs/log | ~60μs/log | 3.3x faster |
| Memory fragmentation | High | None | Significant |

## Best Practices

1. **Reset periodically**: Call `resetArena()` regularly to prevent memory growth
2. **Use appropriate threshold**: Set `arena_reset_threshold` based on your log frequency
3. **Monitor memory**: In debug mode, track arena size if memory is a concern
4. **Combine with file rotation**: Arena works well with time/size-based rotation

## When to Use Arena Allocation

✅ **Use arena allocation when:**
- Logging at high rates (>1000 logs/second)
- Memory allocation overhead is a bottleneck
- Running batch processing jobs
- Building performance-critical applications

❌ **Skip arena allocation when:**
- Low log volume
- Memory debugging is needed
- Simple applications with infrequent logging

## Complete Example

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    // Production configuration with arena allocation
    const config = logly.Config{
        .use_arena_allocator = true,
        .arena_reset_threshold = 64 * 1024,
        .level = .info,
        .show_time = true,
        .show_filename = true,
        .show_lineno = true,
        .json = false,
    };

    const logger = try logly.Logger.initWithConfig(gpa.allocator(), config);
    defer logger.deinit();

    // Add multiple sinks
    _ = try logger.add(logly.SinkConfig.file("app.log"));
    _ = try logger.add(logly.SinkConfig.json("app.json"));

    // Bind persistent context
    try logger.bind("app", .{ .string = "my-service" });
    try logger.bind("version", .{ .string = "1.0.0" });

    try logger.info(@src(), "Application starting with arena allocation", .{});

    // Simulate workload
    var batch: usize = 0;
    while (batch < 10) : (batch += 1) {
        var i: usize = 0;
        while (i < 1000) : (i += 1) {
            try logger.debug(@src(), "Processing batch {d}, item {d}", .{ batch, i });
        }

        // Reset arena after each batch
        logger.resetArena();
        try logger.info(@src(), "Completed batch {d}", .{batch});
    }

    try logger.success(@src(), "All batches processed successfully", .{});
}
```

## See Also

- [Configuration Guide](/guide/configuration) - Full configuration options
- [Async Logging](/guide/async) - Combine with async for maximum throughput
- [File Rotation](/guide/rotation) - Log file management
