---
title: Thread Pool Guide
description: Use the Logly.zig thread pool for parallel log processing. Covers worker configuration, task submission, priorities, work stealing, and parallel sink writes.
head:
  - - meta
    - name: keywords
      content: zig thread pool, parallel logging, async logging, worker threads, task queue, work stealing, batch processing, high throughput logging
---

# Thread Pool Guide

The thread pool executes log work and application tasks on worker threads. It supports fixed or auto-detected thread counts, work stealing, priorities, batching, cancellation, and parallel sink writes.

## Configuration

`ThreadPoolConfig` is available as `logly.ThreadPoolConfig` (an alias of `Config.ThreadPoolConfig`).

```zig
const logly = @import("logly");

const config = logly.ThreadPoolConfig{
    .enabled = true,
    .threadCount = 4,          // 0 selects a CPU-based default
    .queueSize = 1024,         // Capacity per worker
    .workStealing = true,
    .threadNamePrefix = "logly-worker",
};
```

| Field | Type | Default | Purpose |
|---|---|---|---|
| `enabled` | `bool` | `false` | Enables thread-pool integration |
| `io` | `?std.Io` | `null` | Explicit I/O handle |
| `threadCount` | `usize` | auto | Worker count; `0` selects a default |
| `queueSize` | `usize` | default | Capacity per worker; global capacity is multiplied by worker count |
| `stackSize` | `usize` | default | Stack size per worker |
| `workStealing` | `bool` | `true` | Allows idle workers to steal queued work |
| `threadNamePrefix` | `[]const u8` | `"logly-worker"` | Worker thread name prefix |
| `keepAliveMs` | `u64` | `60000` | Idle keep-alive period |
| `threadAffinity` | `bool` | `false` | Requests CPU affinity where supported |

## Quick Start

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const pool = try logly.ThreadPool.initWithConfig(allocator, .{
        .threadCount = 4,
        .workStealing = true,
    });
    defer pool.deinit();

    try pool.start();
    defer pool.shutdown();

    const Task = struct {
        fn run(maybe_allocator: ?std.mem.Allocator) void {
            _ = maybe_allocator;
            std.debug.print("task executed\n", .{});
        }
    };

    if (!pool.submitFn(Task.run)) {
        return error.QueueFull;
    }

    pool.waitAll();
}
```

`init(allocator)` uses default configuration. `initWithIo` and `initWithConfigAndIo` accept an explicit `std.Io`. `start()` spawns workers; `shutdown()` stops them and drains or cancels pending work as described below.

## Presets

```zig
const single = logly.ThreadPoolPresets.singleThread();
const cpu = logly.ThreadPoolPresets.cpuBound();
const io = logly.ThreadPoolPresets.ioBound();
const high = logly.ThreadPoolPresets.highThroughput();
const low = logly.ThreadPoolPresets.lowLatency();
```

`ThreadPoolPresets` and `ThreadPoolConfig` also provide `default()` and `highThroughput()` variants. `ThreadPoolPresets.lowResource()` exists for constrained environments.

## Task Submission

`Task` is a tagged union with two variants:

```zig
pub const Task = union(enum) {
    function: struct { func: *const fn (?std.mem.Allocator) void },
    callback: struct {
        func: *const fn (*anyopaque, ?std.mem.Allocator) void,
        context: *anyopaque,
    },
};
```

### Core methods

```zig
const handle = pool.submit(task, .normal);          // TaskHandle
const handle = pool.submitWithDrop(task, .high, onDrop);
const ok = pool.submitFn(runTask);                  // fn (?Allocator) void
const handle = pool.submitFnWithHandle(runTask);
const ok = pool.submitCallback(runCallback, context);
const handle = pool.submitCallbackWithHandle(runCallback, context);
const ok = pool.submitHighPriority(runCallback, context);
const ok = pool.submitCritical(runCallback, context);
```

`TaskHandle.isValid()` reports whether the task was accepted. Submission can be rejected when the pool is not running or the queue is full; in that case the returned handle has `id == 0`, `tasksDropped` increments, and the caller retains ownership of any context. A drop hook runs only for accepted tasks that are later discarded by `clear()` or `cancel()`.

### Batch submission

```zig
var tasks: [10]logly.ThreadPool.Task = undefined;
for (&tasks) |*task| {
    task.* = .{ .callback = .{ .func = runCallback, .context = context } };
}

const accepted = pool.submitBatch(&tasks, .normal);
const accepted_with_retry = pool.submitBatchWithRetry(&tasks, .normal, 3, 100);
```

Both return the number of accepted tasks.

### Non-blocking and worker-specific submission

```zig
if (pool.trySubmit(task, .high)) {
    // Accepted.
}

const worker_handle = pool.submitToWorkerWithHandle(0, task, .normal);
```

### Cancellation

```zig
const handle = pool.submitFnWithHandle(runTask);
if (pool.cancel(handle)) {
    // Cancelled before execution.
}
```

## Priorities

```zig
pub const WorkItem = struct {
    pub const Priority = enum(u8) {
        low = 0,
        normal = 1,
        high = 2,
        critical = 3,
    };
};
```

Priority-specific helpers accept function or callback tasks and return `true` when accepted. `submitBatch` and `submitBatchWithRetry` take an explicit priority.

## Waiting and Queue Control

```zig
pool.waitAll();
if (!pool.waitAllTimeout(5000)) {
    // Timed out.
}
if (!pool.waitUntilQueueBelow(100, 2000)) {
    // Timed out.
}

const pending = pool.pendingTasks();
const depth = pool.pendingTasksByQueue();
const capacity = pool.queueCapacity();
const available = pool.availableQueueCapacity();
const can_accept = pool.canAcceptTasks(4);
const utilization = pool.queueUtilization();
const saturated = pool.isSaturated(0.9);
const active = pool.activeThreads();
const empty = pool.isEmpty();
const full = pool.isFull();
```

`clear()` discards pending tasks and runs their drop hooks. `resetStats()` clears counters.

## Parallel Sink Writing

`ParallelSinkWriter` dispatches the same payload to multiple sinks through the pool.

```zig
const pool = try logly.ThreadPool.initWithConfig(allocator, .{ .threadCount = 4 });
defer pool.deinit();
try pool.start();
defer pool.shutdown();

const writer = try logly.ParallelSinkWriter.initWithConfig(allocator, pool, .{
    .maxConcurrent = 4,
    .retryOnFailure = true,
    .maxRetries = 3,
    .buffered = true,
    .bufferSize = 64,
});
defer writer.deinit();

fn writeToFile(data: []const u8) void {
    // Write data to the file sink.
}

fn flushFile() void {
    // Flush the file sink.
}

try writer.addSink(.{
    .name = "file",
    .writeFn = writeToFile,
    .flushFn = flushFile,
});

writer.writeParallel("log record");
writer.flushAll();
```

`SinkHandle` fields are `name`, `writeFn`, optional `flushFn`, and `enabled` (default `true`). `removeSink(name)` and `setSinkEnabled(name, enabled)` manage registered sinks. `sinkCount()` and `hasEnabledSinks()` report state. Buffered payloads are flushed by `flushBuffer()` or `flushAll()`.

`ParallelConfig` fields:

```zig
pub const ParallelConfig = struct {
    maxConcurrent: usize = 8,
    writeTimeoutMs: u64 = 5000,
    retryOnFailure: bool = true,
    maxRetries: u3 = 3,
    failFast: bool = false,
    buffered: bool = true,
    bufferSize: usize = 64,
};
```

Presets: `ParallelConfig.default()`, `highThroughput()`, `lowLatency()`, and `reliable()`.

## Statistics

### Pool statistics

```zig
const stats = pool.getStats();

std.debug.print("submitted: {d}\n", .{stats.getSubmitted()});
std.debug.print("completed: {d}\n", .{stats.getCompleted()});
std.debug.print("stolen: {d}\n", .{stats.getStolen()});
std.debug.print("dropped: {d}\n", .{stats.getDropped()});
std.debug.print("cancelled: {d}\n", .{stats.getCancelled()});
std.debug.print("throughput: {d:.2} tasks/s\n", .{stats.throughput()});
std.debug.print("avg wait: {d} ns\n", .{stats.avgWaitTimeNs()});
std.debug.print("avg exec: {d} ns\n", .{stats.avgExecTimeNs()});
```

Additional methods: `completionRate()`, `dropRate()`, `hasDropped()`, `getActiveThreads()`, and `avgWaitTimeMs()`.

### Parallel writer statistics

`ParallelSinkWriter.getStats()` returns `ParallelStats` with atomic counters `writesSubmitted`, `writesCompleted`, `writesFailed`, `retries`, and `bytesWritten`, plus `successRate()`. Read counters with `load(.monotonic)` or the `Utils.atomicLoadU64` helper used by the library.

## Callbacks

```zig
pool.setThreadStartCallback(onThreadStart);
pool.setThreadStopCallback(onThreadStop);
pool.setTaskSubmittedCallback(onSubmitted);
pool.setTaskDequeuedCallback(onDequeued);
pool.setTaskExecutedCallback(onExecuted);
pool.setWorkStolenCallback(onStolen);
pool.setQueueOverflowCallback(onOverflow);
```

Callbacks run on worker or submitting threads. Keep them short and avoid blocking, logging, or acquiring locks that the pool itself may hold.

## Lifecycle and Shutdown

- `start()` is idempotent while the pool is running.
- `shutdown()` stops accepting work, signals workers, and waits for them to exit.
- `deinit()` calls `shutdown()` and frees worker and queue storage.
- Do not call `submit()` concurrently with `deinit()`.
- Call `waitAll()` before shutdown when pending work must complete.

## Async Logger Integration

`ParallelSinkWriter` requires a started `ThreadPool`. The async logger has its own queue and worker and does not use the pool. They can run together, but they are independent components; construct the pool explicitly and pass it to the writer.

## Best Practices

- Size the pool from measured workload, not core count alone.
- Use larger queues for bursty workloads and smaller queues to apply backpressure sooner.
- Treat an invalid `TaskHandle` as an explicit rejection; do not retry a task whose context was already transferred.
- Prefer `trySubmit` when the caller must not block.
- Use priorities only when ordering matters; excess priority inversion can starve normal work.
- Inspect `tasksDropped` and queue utilization before increasing concurrency.

## See Also

- [Thread Pool API](/api/thread-pool)
- [Async Logging Guide](/guide/async)
- [Configuration Guide](/guide/configuration)
