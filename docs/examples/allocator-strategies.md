---
title: Allocator Usage
description: How to use allocators with Logly.zig.
head:
  - - meta
    - name: keywords
      content: allocator, DebugAllocator, zig logging memory management
  - - meta
    - property: og:title
      content: Allocator Usage | Logly.zig
---

# Allocator Usage

> **Note:** Arena allocation was removed in v0.2.1. Pass your own allocator to `Logger.initWithConfig(allocator, config)` directly.

Logly works with any `std.mem.Allocator` implementation. Pass your allocator to `Logger.init(allocator)` or `Logger.initWithConfig(allocator, config)`.

## Example

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const logger = try logly.Logger.init(allocator);
    defer logger.deinit();

    try logger.info("Using DebugAllocator", @src());
}
```

## Notes

- The recommended default in applications is `std.heap.DebugAllocator`.
- For high-throughput workloads, callers can wrap their allocator with a custom arena and pass it to `Logger.initWithConfig(allocator, config)`.
