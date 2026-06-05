---
title: Allocator Strategies
description: Pass any std.mem.Allocator to Logly.zig. Learn how to pick between DebugAllocator, ArenaAllocator, page_allocator, and custom allocators for high-performance logging.
head:
  - - meta
    - name: keywords
      content: allocator, memory management, debug allocator, arena allocator, page allocator, high-performance, zig logging
  - - meta
    - property: og:title
      content: Allocator Strategies | Logly.zig
  - - meta
    - property: og:image
      content: https://muhammad-fiaz.github.io/logly.zig/cover.png
---

# Allocator Strategies

Logly.zig allocates exclusively through the `std.mem.Allocator` you pass to `Logger.init(allocator)` / `Logger.initWithConfig(allocator, ...)`. There is no implicit internal arena or hidden allocator state — what you pass is exactly what the logger uses for every allocation: records, formatted output, sinks, async buffers, and the optional thread pool.

This means you can swap in any allocator that satisfies `std.mem.Allocator` to match your workload, and the choice is entirely yours.

## Recommended: `DebugAllocator`

`std.heap.DebugAllocator` wraps any backing allocator with leak detection, double-free detection, and never-reuse behaviour. It is the recommended default in production application code because it surfaces memory bugs at the point of use.

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();

    const logger = try logly.Logger.init(gpa.allocator());
    defer logger.deinit();

    try logger.info("Hello from Logly");
}
```

## High-Throughput: `ArenaAllocator`

For workloads that churn a lot of temporary allocations (formatting, rule evaluation, redaction), wrapping a long-lived arena around your backing allocator and passing the wrapped handle into Logly lets you reclaim all temporary memory in a single `arena.deinit()` call.

```zig
pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();

    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();

    const logger = try logly.Logger.init(arena.allocator());
    defer logger.deinit();

    try logger.info("All temporary allocations flow through the arena");
}
```

## Fastest: `page_allocator`

`std.heap.page_allocator` is the system page allocator. It is the fastest allocator in microbenchmarks but does **not** free individual allocations — only when the OS reclaims the pages. Use it only in short-lived utilities or benchmarks.

```zig
pub fn main() !void {
    const logger = try logly.Logger.init(std.heap.page_allocator);
    defer logger.deinit();

    try logger.info("Using the system page allocator");
}
```

## Custom Allocators

Any struct that satisfies the `std.mem.Allocator` vtable can be passed in: thread-local allocators, slab allocators, off-heap allocators backed by a `mmap` region, memory pools, or your own service-specific allocator. Logly treats them all the same way.

```zig
const Slab = struct {
    backing: []align(std.mem.page_size) u8,
    next: std.atomic.Value(usize),

    pub fn allocator(self: *Slab) std.mem.Allocator {
        return .{ .ptr = self, .vtable = &.{
            .alloc = alloc,
            .resize = resize,
            .remap = remap,
            .free = free,
        } };
    }
    // ... implement the vtable functions for your slab.
};
```

## Choosing an Allocator

| Allocator | Best for | Trade-offs |
|-----------|----------|------------|
| `std.heap.DebugAllocator` | Production application code, debugging, default | Slight overhead for the safety checks |
| `std.heap.ArenaAllocator` | High-throughput temporary churn | Free everything at once with `deinit()` |
| `std.heap.page_allocator` | Short-lived utilities, microbenchmarks | Individual allocations are never freed until exit |
| Custom | Specialised memory topologies | Whatever your service requires |

Logly does not own the lifetime of the allocator you pass in — `Logger.deinit()` releases the resources the logger itself owns (records, sinks, async buffers, thread pool), but does not free the allocator. Deinit the allocator after you deinit the logger.
