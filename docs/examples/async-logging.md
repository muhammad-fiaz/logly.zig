---
title: Async Logging Example
description: Example of high-performance async logging with Logly.zig. Configure ring buffers, batch processing, and background I/O for non-blocking log operations.
head:
  - - meta
    - name: keywords
      content: async logging example, non-blocking logging, ring buffer, background io, high performance logging
  - - meta
    - property: og:title
      content: Async Logging Example | Logly.zig
---

# Async Logging

This example demonstrates how to configure asynchronous logging for high-performance scenarios. Async logging offloads file I/O to a background thread, preventing logging from blocking your main application flow.

## Centralized Configuration

```zig
const logly = @import("logly");

var config = logly.Config.default();
config.asyncConfig = logly.AsyncConfig{
    .bufferSize = 8192,           // Ring buffer size
    .flushIntervalMs = 100,      // Auto-flush interval
    .minFlushIntervalMs = 10,   // Min interval
    .maxLatencyMs = 5000,        // Max latency
    .overflowPolicy = .dropOldest,
    .batchSize = 64,
};

// Or use helper method
var config2 = logly.Config.default().withAsync();
```

## Code Example

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Enable colors on Windows
     _ = logly.Terminal.enableAnsiColors();

    const logger = try logly.Logger.init(allocator);
    defer logger.deinit();

    // Configure logger with async settings
    var config = logly.Config.default();
    config.autoSink = false;
    config.asyncConfig = logly.AsyncConfig{
        .bufferSize = 8192,
        .flushIntervalMs = 100,
    };
    logger.configure(config);

    // Add a file sink with async writing enabled (default)
    // Using add() alias (same as addSink())
     _ = try logger.add(.{
        .path = "logs/async.log",
        .asyncWrite = true,
        .bufferSize = 4096, // 4KB buffer
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
