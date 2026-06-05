---
title: Memory Telemetry Example
description: Example showing how to attach a MemoryTracker to a logly logger, observe allocator usage at runtime, and detect memory pressure.
head:
  - - meta
    - name: keywords
    - content: memory tracker, allocator telemetry, zig memory, logly telemetry
---

# Memory Telemetry Example

This example shows how to wrap your `std.mem.Allocator` in a `logly.MemoryTracker`, attach it to a logger, and read live bytes, peak usage, and the host's available memory at runtime.

> [!NOTE]
> Run with: `zig build run-memory_telemetry`

## Code Example

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();

    var tracker = logly.MemoryTracker.init(gpa.allocator());
    const logger = try logly.Logger.initWithConfig(tracker.allocator(), .default());
    defer logger.deinit();
    logger.attachMemoryTracker(&tracker);

    var report = logger.getMemoryReport().?;
    std.debug.print("[start] used={d} peak={d} live={d}\n", .{
        report.bytes_used, report.bytes_peak, report.live_allocations,
    });

    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        var buf: std.ArrayListUnmanaged(u8) = .empty;
        defer buf.deinit(logger.allocator());
        try buf.appendSlice(logger.allocator(), "hello");
    }

    report = logger.getMemoryReport().?;
    std.debug.print("[after_load] used={d} peak={d} live={d}\n", .{
        report.bytes_used, report.bytes_peak, report.live_allocations,
    });

    tracker.resetCounters();
    std.debug.print("[after_reset] used={d} peak={d} live={d}\n", .{
        tracker.bytesUsed(), tracker.bytesPeak(), tracker.liveAllocations(),
    });

    const avail = logly.detectAvailableMemory();
    const rss = logly.detectCurrentMemoryUsage();
    std.debug.print("[os] available={d} current_rss={d}\n", .{ avail, rss });
}
```

> [!TIP]
> On Windows, `logly.detectCurrentMemoryUsage` returns 0 because process RSS is not exposed through `GetProcessMemoryInfo` here. Use the Linux path or a tool like Task Manager for the actual resident set size.
