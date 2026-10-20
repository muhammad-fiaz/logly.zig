---
title: Thread Pool Example
description: Example of parallel log processing with the Logly.zig thread pool. Configure workers, submit tasks, and inspect pool statistics.
head:
  - - meta
    - name: keywords
      content: thread pool example, parallel logging, worker threads, task submission, work stealing, zig
  - - meta
    - property: og:title
      content: Thread Pool Example | Logly.zig
---

# Thread Pool Example

This example creates a worker pool, submits callback tasks, waits for completion, and reads pool statistics.

## Configuration

```zig
const pool = try logly.ThreadPool.initWithConfig(allocator, .{
    .threadCount = 4,
    .queueSize = 1024,
    .workStealing = true,
});
defer pool.deinit();
```

`queueSize` is the capacity per worker. The pool allocates `queueSize * threadCount` global queue slots.

## Source

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const pool = try logly.ThreadPool.initWithConfig(allocator, .{
        .threadCount = 4,
        .queueSize = 1024,
        .workStealing = true,
    });
    defer pool.deinit();

    try pool.start();

    var counter = std.atomic.Value(u32).init(0);
    const Task = struct {
        fn increment(context: *anyopaque, maybe_allocator: ?std.mem.Allocator) void {
            _ = maybe_allocator;
            const value: *std.atomic.Value(u32) = @ptrCast(@alignCast(context));
            _ = value.fetchAdd(1, .monotonic);
        }
    };

    for (0..200) |_| {
        _ = pool.submitCallback(Task.increment, @ptrCast(&counter));
    }

    pool.waitAll();
    std.debug.print("completed: {d}\n", .{counter.load(.monotonic)});

    const stats = pool.getStats();
    std.debug.print("submitted: {d}\n", .{stats.getSubmitted()});
    std.debug.print("completed: {d}\n", .{stats.getCompleted()});
    std.debug.print("stolen: {d}\n", .{stats.getStolen()});
    std.debug.print("throughput: {d:.2} tasks/s\n", .{stats.throughput()});

    pool.shutdown();
}
```

## Running the Example

```bash
zig build run-thread_pool
```

## Key Concepts

### Presets

```zig
const single = logly.ThreadPoolPresets.singleThread();
const cpu = logly.ThreadPoolPresets.cpuBound();
const io = logly.ThreadPoolPresets.ioBound();
const high = logly.ThreadPoolPresets.highThroughput();
const low = logly.ThreadPoolPresets.lowLatency();
```

`ThreadPoolPresets` returns `ThreadPoolConfig` values. Pass one to `initWithConfig`.

### Task submission

```zig
const handle = pool.submit(.{
    .callback = .{ .func = runCallback, .context = context },
}, .normal);

if (!handle.isValid()) {
    // Rejected because the pool is stopped or the queue is full.
}

const accepted = pool.submitCallback(runCallback, context);
const accepted_fn = pool.submitFn(runFunction);
```

Submission is rejected with an invalid `TaskHandle` or `false`; it does not return `error.QueueFull`. Check the return value and preserve ownership of rejected task contexts.

### Priorities

```zig
_ = pool.submitHighPriority(runCallback, context);
_ = pool.submitCritical(runCallback, context);
_ = pool.submitToWorker(0, task, .normal);
```

### Waiting and shutdown

```zig
pool.waitAll();
_ = pool.waitAllTimeout(2000);
_ = pool.waitUntilQueueBelow(100, 1000);

pool.shutdown();
```

`waitAllTimeout` and `waitUntilQueueBelow` return `false` on timeout. `deinit` calls `shutdown`.

### Statistics

```zig
const stats = pool.getStats();

std.debug.print("submitted: {d}\n", .{stats.getSubmitted()});
std.debug.print("completed: {d}\n", .{stats.getCompleted()});
std.debug.print("dropped: {d}\n", .{stats.getDropped()});
std.debug.print("cancelled: {d}\n", .{stats.getCancelled()});
std.debug.print("stolen: {d}\n", .{stats.getStolen()});
std.debug.print("avg wait: {d} ns\n", .{stats.avgWaitTimeNs()});
std.debug.print("avg exec: {d} ns\n", .{stats.avgExecTimeNs()});
std.debug.print("throughput: {d:.2} tasks/s\n", .{stats.throughput()});
```

## See Also

- [Thread Pool API](/api/thread-pool)
- [Thread Pool Guide](/guide/thread-pool)
- [Async Logging Example](/examples/async-logging)
