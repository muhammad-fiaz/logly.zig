---
title: Memory-Mapped (mmap) Sinks Example
description: Learn how to set up and run memory-mapped sinks for ultra-high-performance virtual memory writes to disk.
---

# Memory-Mapped (mmap) Sinks Example

This example demonstrates how to configure a file sink to use zero-copy, microsecond-latency memory mapping (`mmap`). The file is pre-allocated and mapped directly into virtual memory space, bypassing high-cost write system calls. Sinks are gracefully truncated to their exact written size during cleanup.

For detailed concepts, see the [Memory-Mapped (mmap) Sinks Guide](/guide/mmap).

---

## Code Listing

The following is the complete source from [examples/mmap_sink.zig](file:///c:/Users/smuha/Downloads/logly.zig/examples/mmap_sink.zig):

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){}; 
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== Logly v0.2.0 Memory-Mapped Sink Example ===\n\n", .{});

    // Configure a sink with mmap enabled for high-performance writes
    const logPath = "mmap_example.log";
    const io = logly.Utils.io();

    var sinkConfig = logly.SinkConfig.file(logPath);
    sinkConfig.name = "mmap_sink";
    sinkConfig.mmap = true; // Enable memory-mapped I/O for high-performance writes

    // Use log-only mode (no console output — we write to our mmap file sink)
    var config = logly.Config.logOnly();
    config.autoSink = false; // Disable auto console sink so our mmap sink is the only one

    const logger = try logly.Logger.initWithConfig(allocator, config);
    defer logger.deinit();

    // Add the mmap sink
     _ = try logger.addSink(sinkConfig);

    std.debug.print("[mmap] Writing 100 log records via memory-mapped sink...\n", .{});

    var i: usize = 0;
    while (i < 100) : (i += 1) {
        try logger.infof("mmap record #{d}: high-performance write", .{i}, @src());
    }

    try logger.warning("mmap sink: completed batch write.", @src());

    // Flush all sinks to ensure data is persisted
    try logger.flush();

    std.debug.print("[mmap] Completed. Log written to: {s}\n", .{logPath});

    // Read back and show first bytes using Zig 0.16 IO API
    const f = std.Io.Dir.cwd().openFile(io, logPath, .{}) catch |err| {
        std.debug.print("[mmap] Could not open output file: {any}\n", .{err});
        return;
    };
    defer f.close(io);
    defer std.Io.Dir.cwd().deleteFile(io, logPath) catch {};

    var previewBuf: [256]u8 = undefined;
    var fileBuf: [512]u8 = undefined;
    var reader = f.reader(io, &fileBuf);
    const n = reader.interface.readSliceShort(&previewBuf) catch 0;
    if (n > 0) {
        std.debug.print("[mmap] First {d} bytes of log file:\n{s}\n", .{ n, previewBuf[0..n] });
    }

    std.debug.print("\n=== mmap Sink Example Complete ===\n", .{});
}
```

---

## Execution Output

When you compile and run this example with `zig build run-mmap_sink` or `zig build example-mmap_sink`, the console will display:

```text
=== Logly v0.2.0 Memory-Mapped Sink Example ===

[mmap] Writing 100 log records via memory-mapped sink...
[mmap] Completed. Log written to: mmap_example.log
[mmap] First 256 bytes of log file:
2026-05-24 11:05:00.123 [INFO] mmap record #0: high-performance write (examples/mmap_sink.zig:33)
2026-05-24 11:05:00.124 [INFO] mmap record #1: high-performance write (examples/mmap_sink.zig:33)
2026-05-24 11:05:00.124 [INFO] mmap record #2: high-performance write (examples/mmap_sink.zig:33)

=== mmap Sink Example Complete ===
```
