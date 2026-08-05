---
title: Allocator Usage
description: Learn how to use allocators in Logly.zig for logging. Pass your own allocator to Logger.initWithConfig for full control over memory management.
head:
  - - meta
    - name: keywords
      content: allocator, memory management, high-performance, logging performance, zig allocator
  - - meta
    - property: og:title
      content: Allocator Usage | Logly.zig
  - - meta
    - property: og:image
      content: https://muhammad-fiaz.github.io/logly.zig/cover.png
---

# Allocator Usage

Logly works with any `std.mem.Allocator` implementation. Pass your own allocator to `Logger.init(allocator)` or `Logger.initWithConfig(allocator, config)`.

In most applications, that allocator is `std.heap.DebugAllocator`.

## Basic Usage

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();

    const logger = try logly.Logger.initWithConfig(gpa.allocator(), logly.Config.default());
    defer logger.deinit();

    try logger.info("Hello from Logly!", @src());
}
```

## Using Your Own Arena

If your application already uses arena allocation (for example, per-request memory), keep using it. Pass the arena allocator to `Logger.initWithConfig`:

```zig
var gpa = std.heap.DebugAllocator(.{}){};
defer _ = gpa.deinit();

// Application-level arena
var request_arena = std.heap.ArenaAllocator.init(gpa.allocator());
defer request_arena.deinit();

const logger = try logly.Logger.initWithConfig(request_arena.allocator(), logly.Config.default());
```

## Thread Pool Integration

When using the Thread Pool, each worker thread receives the allocator you pass to `Logger.initWithConfig`. For parallel logging, ensure thread-safe allocation:

```zig
var config = logly.Config.default();
config.thread_pool = .{
    .enabled = true,
    .thread_count = 4,
};

const logger = try logly.Logger.initWithConfig(allocator, config);
```

## Best Practices

1. **Use `DebugAllocator` in development** — catches memory leaks and double-frees
2. **Use a dedicated arena for high-throughput logging** — reduce malloc overhead
3. **Keep allocations simple** — Logly's internal allocations are designed to be minimal

## See Also

- [Configuration Guide](/guide/configuration) - Full configuration options
- [Async Logging](/guide/async) - Combine with async for maximum throughput
- [Thread Pool](/guide/thread-pool) - Parallel log processing
