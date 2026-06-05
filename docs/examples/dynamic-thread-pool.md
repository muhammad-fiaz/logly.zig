---
title: Dynamic Thread Pool Example
description: Example showing how to auto-detect host cores, validate thread counts, submit batch work, and use worker start/stop callbacks with logly.ThreadPool.
head:
  - - meta
    - name: keywords
    - content: thread pool, auto-detect, batch submit, worker callback, logly
---

# Dynamic Thread Pool Example

This example shows the v0.2.1 thread pool: auto-detected thread count, validation against the host's hardware cores, batch task submission, and per-worker start/stop callbacks.

> [!NOTE]
> Run with: `zig build run-dynamic_thread_pool`

## Code Example

```zig
const std = @import("std");
const logly = @import("logly");

fn increment(user_data: *anyopaque) void {
    const counter: *std.atomic.Value(u32) = @ptrCast(@alignCast(user_data));
    _ = counter.fetchAdd(1, .monotonic);
}

fn onStart(user_data: *anyopaque) void {
    _ = user_data;
    std.debug.print("[worker] started\n", .{});
}

fn onStop(user_data: *anyopaque) void {
    _ = user_data;
    std.debug.print("[worker] stopped\n", .{});
}

pub fn main() !void {
    const max = logly.ThreadPool.getMaxThreads();
    std.debug.print("Detected max threads: {d}\n", .{max});

    const pool = try logly.ThreadPool.initWithConfig(.{ .thread_count = 0 });
    defer pool.deinit();

    pool.setOnWorkerStart(.{ .user_data = null, .fn = onStart });
    pool.setOnWorkerStop(.{ .user_data = null, .fn = onStop });
    _ = pool.start();
    std.debug.print("Pool started with {d} workers\n", .{pool.numWorkers()});

    var counter = std.atomic.Value(u32).init(0);
    var tasks: [64]fn (*anyopaque) void = undefined;
    for (&tasks) |*t| t.* = increment;

    const batch = try pool.submitBatch(&tasks, &counter);
    try batch.waitAll();
    std.debug.print("Counter after waitAll: {d}\n", .{counter.load(.monotonic)});

    // Demonstrating rejection of an invalid count
    if (logly.ThreadPool.initWithConfig(.{ .thread_count = max + 1 })) |_| {
        @panic("expected rejection");
    } else |err| {
        std.debug.print("Rejected: {s}\n", .{@errorName(err)});
    }
}
```

> [!WARNING]
> Passing a `thread_count` larger than `logly.ThreadPool.getMaxThreads()` is rejected with `error.ThreadCountExceedsCores` and a `std.log.warn` (which is captured by the active logger when wired to `logly.stdLogFn`).
