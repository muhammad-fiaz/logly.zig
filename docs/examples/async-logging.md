# Async Logging

This example demonstrates how to configure asynchronous logging for high-performance scenarios. Async logging offloads file I/O to a background thread, preventing logging from blocking your main application flow.

## Code Example

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const logger = try logly.Logger.init(allocator);
    defer logger.deinit();

    // Configure logger
    var config = logly.Config.default();
    config.auto_sink = false;
    logger.configure(config);

    // Add a file sink with async writing enabled (default)
    _ = try logger.addSink(.{
        .path = "logs/async.log",
        .async_write = true,
        .buffer_size = 4096, // 4KB buffer
    });

    // Add a console sink
    _ = try logger.addSink(.{});

    try logger.info("Starting async logging test...");

    // Log many messages quickly
    for (0..1000) |i| {
        const msg = try std.fmt.allocPrint(allocator, "Async log message #{d}", .{i});
        defer allocator.free(msg);
        try logger.info(msg);
    }

    try logger.info("Finished logging 1000 messages");

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
