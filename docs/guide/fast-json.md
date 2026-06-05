---
title: Fast JSON Formatting
description: Pre-sized buffers, bulk-safe-run escape, and an estimateJsonSize heuristic for high-throughput JSON output.
head:
  - - meta
    - name: keywords
      content: logly, zig, json, fast json, formatter, escape, bulk write
---

# Fast JSON Formatting

`logly.formatJsonWithAllocator` and `logly.escapeJsonString` were rewritten for v0.2.1 to keep up with the 10K records / second goal.

## What Changed

- `formatJsonWithAllocator` switched from `std.Io.Writer.Allocating` to a pre-sized `std.ArrayList(u8)` + `Utils.ArrayListWriter` + an `estimateJsonSize` heuristic. The list never has to grow more than once.
- `escapeJsonString` now bulk-writes runs of safe bytes and only pays per-byte cost when an actual escape character is encountered.
- `escapeJsonStringToBuf` is the bounded form that returns `error.NoSpaceLeft` on overflow.

## Compact vs Pretty

```zig
const logly = @import("logly");
const std = @import("std");

var buf: std.ArrayListUnmanaged(u8) = .empty;
defer buf.deinit(allocator);

const n = 10_000;
var i: usize = 0;
while (i < n) : (i += 1) {
    buf.clearRetainingCapacity();
    try logly.formatJsonWithAllocator(allocator, &buf, .{
        .level = "info",
        .index = i,
        .message = "hello world",
    });
}
```

> [!TIP]
> For human-readable output, set `logly.Config.pretty_json = true`. For maximum throughput, leave the default (compact).

## Benchmarks

`zig build bench` reports the throughput in your local environment. On the v0.2.1 development host (Windows, debug build, 22 cores, 16 GiB available):

| Mode          | ops/sec      |
| ------------- | ------------ |
| Compact JSON  | 33,000–37,000 |
| Pretty JSON   | 32,000–35,000 |

Run `zig build run-fast_json` to see the exact numbers on your machine.

> [!NOTE]
> Numbers are sensitive to allocator choice. Switching from `std.heap.page_allocator` to `std.heap.DebugAllocator(.{}){}` typically halves throughput, which is the expected cost of safety.
