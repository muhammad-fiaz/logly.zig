---
title: Allocator Strategies Example
description: Compare the default DebugAllocator logger flow with optional arena allocation in Logly.zig.
head:
  - - meta
    - name: keywords
      content: allocator strategies, DebugAllocator, arena allocation, zig logging memory management
  - - meta
    - property: og:title
      content: Allocator Strategies Example | Logly.zig
---

# Allocator Strategies Example

This example demonstrates both supported allocator strategies:

- Default: logger uses the allocator passed to `Logger.init(...)` or `Logger.initWithConfig(...)` (typically `DebugAllocator`).
- Optional: arena allocation enabled via explicit config field (`use_arena_allocator`) or alias builder (`withArenaAllocator()`) for high-throughput temporary allocations.

## Source Code

```zig
const std = @import("std");
const logly = @import("logly");

fn runDefaultAllocatorExample(allocator: std.mem.Allocator) !void {
    var config = logly.Config.default();
    config.check_for_updates = false;

    const logger = try logly.Logger.initWithConfig(allocator, config);
    defer logger.deinit();

    try logger.info("Default strategy: logger uses the allocator passed to init (GPA in this example)", @src());
    try logger.info("Arena allocation is disabled by default", @src());
}

fn runArenaAllocatorExample(allocator: std.mem.Allocator) !void {
    var config = logly.Config.default();
    config.use_arena_allocator = true;
    config.check_for_updates = false;
    config.arena_reset_threshold = 64 * 1024;

    const logger = try logly.Logger.initWithConfig(allocator, config);
    defer logger.deinit();

    try logger.info("Arena strategy: temporary record/format allocations use logger scratch arena", @src());

    var i: usize = 0;
    while (i < 10) : (i += 1) {
        try logger.infof("Arena batch item {d}", .{i}, @src());
    }

    logger.resetArena();
    try logger.success("Arena reset completed for current batch", @src());
}

fn runArenaAllocatorAliasExample(allocator: std.mem.Allocator) !void {
    var config = logly.Config.default().withArenaAllocator();
    config.check_for_updates = false;
    config.arena_reset_threshold = 64 * 1024;

    const logger = try logly.Logger.initWithConfig(allocator, config);
    defer logger.deinit();

    try logger.info("Arena alias strategy: equivalent to use_arena_allocator=true", @src());
  }

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    _ = logly.Terminal.enableAnsiColors();

    std.debug.print("\\n=== Allocator Strategies Demo ===\\n", .{});
    std.debug.print("1) Default allocator path (GPA)\\n", .{});
    try runDefaultAllocatorExample(allocator);

    std.debug.print("\\n2) Optional arena allocator path\\n", .{});
    try runArenaAllocatorExample(allocator);

    std.debug.print("\\n3) Optional arena allocator alias path\\n", .{});
    try runArenaAllocatorAliasExample(allocator);

    std.debug.print("\\nDone.\\n", .{});
}
```

Both syntaxes are valid and supported:

```zig
config.use_arena_allocator = true;
// or
config = config.withArenaAllocator();
```

Difference:
- `config.use_arena_allocator = true` mutates an existing config variable.
- `config = config.withArenaAllocator()` returns a modified copy (reassign it).

All examples in this repository initialize Logly with `std.heap.DebugAllocator` and then optionally enable arena scratch allocation per logger config.

## Build and Run

```bash
zig build example-allocator_strategies
zig build run-allocator_strategies
```

## See Also

- [Arena Allocation Guide](../guide/arena-allocation.md)
- [Basic Example](basic.md)
- [Thread Pool Example](thread-pool.md)
