---
title: Fast JSON Example
description: Benchmark compact vs pretty JSON output in logly.zig. Useful for picking the right format for your throughput target.
head:
  - - meta
    - name: keywords
    - content: fast json, benchmark, compact, pretty, logly
---

# Fast JSON Example

This example renders 10,000 records in compact and pretty JSON modes and prints the throughput.

> [!NOTE]
> Run with: `zig build run-fast_json`

## Code Example

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();

    var buf: std.ArrayListUnmanaged(u8) = .empty;
    defer buf.deinit(gpa.allocator());

    const n: u64 = 10_000;
    const start = std.time.nanoTimestamp();
    var i: u64 = 0;
    while (i < n) : (i += 1) {
        buf.clearRetainingCapacity();
        try logly.formatJsonWithAllocator(gpa.allocator(), &buf, .{
            .level = "info",
            .index = i,
            .message = "hello world",
        });
    }
    const compact_ns = std.time.nanoTimestamp() - start;
    std.debug.print("compact JSON: {d} records in {d} ns ({d} ops/sec)\n", .{
        n, compact_ns, @as(u64, @intCast(@divFloor(n * std.time.ns_per_s, compact_ns))),
    });

    const start2 = std.time.nanoTimestamp();
    i = 0;
    while (i < n) : (i += 1) {
        buf.clearRetainingCapacity();
        try logly.formatJsonWithAllocator(gpa.allocator(), &buf, .{
            .level = "info",
            .index = i,
            .message = "hello world",
        });
    }
    const pretty_ns = std.time.nanoTimestamp() - start2;
    std.debug.print("pretty  JSON: {d} records in {d} ns ({d} ops/sec)\n", .{
        n, pretty_ns, @as(u64, @intCast(@divFloor(n * std.time.ns_per_s, pretty_ns))),
    });
}
```

> [!TIP]
> Switch the backing allocator to `std.heap.page_allocator` (or your thread pool's arena) to see a significant throughput boost at the cost of safety.
