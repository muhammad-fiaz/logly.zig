# Async Logging

This example demonstrates how to configure asynchronous logging for high-performance scenarios. Async logging offloads file I/O to a background thread, preventing logging from blocking your main application flow.

## Centralized Configuration

```zig
const logly = @import("logly");

var config = logly.Config.default();
config.async_config = logly.AsyncConfig{
    .buffer_size = 8192,           // Ring buffer size
    .flush_interval_ms = 100,      // Auto-flush interval
    .max_pending = 10000,          // Max queued messages
    .overflow_strategy = .drop_oldest,
    .enable_batching = true,
    .batch_size = 64,
};

// Or use helper method
var config2 = logly.Config.default().withAsync(.{
    .buffer_size = 4096,
    .flush_interval_ms = 50,
});
```

## Code Example

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Enable colors on Windows
    _ = logly.Terminal.enableAnsiColors();

    const logger = try logly.Logger.init(allocator);
    defer logger.deinit();

    // Configure logger with async settings
    var config = logly.Config.default();
    config.auto_sink = false;
    config.async_config = logly.AsyncConfig{
        .buffer_size = 8192,
        .flush_interval_ms = 100,
    };
    logger.configure(config);

    // Add a file sink with async writing enabled (default)
    // Using add() alias (same as addSink())
    _ = try logger.add(.{
        .path = "logs/async.log",
        .async_write = true,
        .buffer_size = 4096, // 4KB buffer
    });

    // Add a console sink
    _ = try logger.add(.{});

    try logger.info("Starting async logging test...", @src());

    // Log many messages quickly
    for (0..1000) |i| {
        try logger.infof("Async log message #{d}", .{i}, @src());
    }

    try logger.info("Finished logging 1000 messages", @src());

    // Flush is important for async sinks before exit
    try logger.flush();

    std.debug.print("Async logging example completed!\n", .{});
}
```

## Expected Output

Console output:

```text
[INFO] Starting async logging test...
[INFO] Async log message #0
...
[INFO] Async log message #999
[INFO] Finished logging 1000 messages
Async logging example completed!
```

File output (`logs/async.log`):

```text
[INFO] Starting async logging test...
[INFO] Async log message #0
...
[INFO] Async log message #999
[INFO] Finished logging 1000 messages
```
