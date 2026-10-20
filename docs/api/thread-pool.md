---
title: Thread Pool API
description: API reference for the Logly.zig thread pool and parallel sink writer.
head:
  - - meta
    - name: keywords
      content: thread pool api, parallel sink writer, task submission, worker threads, zig
  - - meta
    - property: og:title
      content: Thread Pool API | Logly.zig
  - - meta
    - property: og:image
      content: https://muhammad-fiaz.github.io/logly.zig/cover.png
---

# Thread Pool API

`ThreadPool` executes function and callback tasks on worker threads. `ParallelSinkWriter` dispatches a payload to multiple sinks through a pool.

## Overview

```zig
const pool = try logly.ThreadPool.initWithConfig(allocator, .{
    .threadCount = 4,
    .queueSize = 1024,
});
defer pool.deinit();

try pool.start();
defer pool.shutdown();
```

## Types

### ThreadPool

```zig
pub const ThreadPool = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    config: ThreadPoolConfig,
    workers: []Worker,
    workQueue: WorkQueue,
    stats: ThreadPoolStats,
    // ...
};
```

### ThreadPoolConfig

```zig
pub const ThreadPoolConfig = struct {
    enabled: bool = false,
    io: ?std.Io = null,
    threadCount: usize = 0,
    queueSize: usize = 10000,
    stackSize: usize = 1024 * 1024,
    workStealing: bool = true,
    threadNamePrefix: []const u8 = "logly-worker",
    keepAliveMs: u64 = 60000,
    threadAffinity: bool = false,
};
```

`default()` returns the default configuration; `highThroughput()` and `ioBound()` return tuned variants. Additional constructors are available through `ThreadPoolPresets`.

### Task

```zig
pub const Task = union(enum) {
    function: struct {
        func: *const fn (?std.mem.Allocator) void,
    },
    callback: struct {
        func: *const fn (*anyopaque, ?std.mem.Allocator) void,
        context: *anyopaque,
    },
};
```

### TaskHandle

```zig
pub const TaskHandle = struct {
    id: u64,

    pub fn isValid(self: TaskHandle) bool;
};
```

An invalid handle (`id == 0`) means the task was rejected or the handle was cancelled.

### WorkItem.Priority

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

### ThreadPoolStats

```zig
pub const ThreadPoolStats = struct {
    tasksSubmitted: std.atomic.Value(u64),
    tasksCompleted: std.atomic.Value(u64),
    tasksStolen: std.atomic.Value(u64),
    tasksDropped: std.atomic.Value(u64),
    tasksCancelled: std.atomic.Value(u64),
    totalWaitTimeNs: std.atomic.Value(u64),
    totalExecTimeNs: std.atomic.Value(u64),
    activeThreads: std.atomic.Value(u32),
};
```

Methods: `avgWaitTimeNs()`, `avgExecTimeNs()`, `throughput()`, `getSubmitted()`, `getCompleted()`, `getStolen()`, `getDropped()`, `getCancelled()`, `completionRate()`, `dropRate()`, `hasDropped()`, `getActiveThreads()`, and `avgWaitTimeMs()`.

### ParallelConfig

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

Presets: `default()`, `highThroughput()`, `lowLatency()`, and `reliable()`.

### ParallelSinkWriter

```zig
pub const ParallelSinkWriter = struct {
    allocator: std.mem.Allocator,
    pool: *ThreadPool,
    config: ParallelConfig,
    sinks: std.ArrayList(SinkHandle),
    buffer: std.ArrayList([]const u8),
    stats: ParallelStats,
};

pub const SinkHandle = struct {
    writeFn: *const fn (data: []const u8) void,
    flushFn: ?*const fn () void = null,
    name: []const u8,
    enabled: bool = true,
};

pub const ParallelStats = struct {
    writesSubmitted: std.atomic.Value(u64),
    writesCompleted: std.atomic.Value(u64),
    writesFailed: std.atomic.Value(u64),
    retries: std.atomic.Value(u64),
    bytesWritten: std.atomic.Value(u64),

    pub fn successRate(self: *const ParallelStats) f64;
};
```

## Lifecycle

### init / initWithConfig

```zig
pub fn init(allocator: std.mem.Allocator) !*ThreadPool
pub fn initWithConfig(allocator: std.mem.Allocator, config: ThreadPoolConfig) !*ThreadPool
```

Allocates the pool and workers. Workers do not start until `start()` is called.

### initWithIo / initWithConfigAndIo

```zig
pub fn initWithIo(allocator: std.mem.Allocator, io_handle: std.Io, config: ThreadPoolConfig) !*ThreadPool
pub fn initWithConfigAndIo(allocator: std.mem.Allocator, config: ThreadPoolConfig, io_handle: std.Io) !*ThreadPool
```

### start

```zig
pub fn start(self: *ThreadPool) !void
```

Spawns worker threads. Calling `start()` while running is a no-op; a partial spawn failure joins already-started workers and returns an error.

### shutdown

```zig
pub fn shutdown(self: *ThreadPool) void
```

Signals workers to stop and joins them. Calling `shutdown()` while stopped is a no-op.

### deinit

```zig
pub fn deinit(self: *ThreadPool) void
```

Calls `shutdown()` and releases worker and queue storage.

### isRunning / threadCount

```zig
pub fn isRunning(self: *const ThreadPool) bool
pub fn threadCount(self: *const ThreadPool) usize
```

## Submission

### submit / submitWithDrop

```zig
pub fn submit(self: *ThreadPool, task: Task, priority: WorkItem.Priority) TaskHandle
pub fn submitWithDrop(
    self: *ThreadPool,
    task: Task,
    priority: WorkItem.Priority,
    onDrop: ?*const fn (?*anyopaque) void,
) TaskHandle
```

Returns an invalid handle when the pool is stopped or the queue is full. A rejected submission does not invoke the drop hook; the caller retains ownership of the task context. For accepted tasks that are later discarded by `clear()` or `cancel()`, the drop hook receives the callback context.

### Function and callback helpers

```zig
pub fn submitFn(self: *ThreadPool, func: *const fn (?std.mem.Allocator) void) bool
pub fn submitFnWithHandle(self: *ThreadPool, func: *const fn (?std.mem.Allocator) void) TaskHandle
pub fn submitCallback(
    self: *ThreadPool,
    func: *const fn (*anyopaque, ?std.mem.Allocator) void,
    context: *anyopaque,
) bool
pub fn submitCallbackWithHandle(
    self: *ThreadPool,
    func: *const fn (*anyopaque, ?std.mem.Allocator) void,
    context: *anyopaque,
) TaskHandle
```

### Priority helpers

```zig
pub fn submitHighPriority(
    self: *ThreadPool,
    func: *const fn (*anyopaque, ?std.mem.Allocator) void,
    context: *anyopaque,
) bool
pub fn submitHighPriorityWithHandle(...) TaskHandle
pub fn submitCritical(...) bool
pub fn submitCriticalWithHandle(...) TaskHandle
```

### Batch submission

```zig
pub fn submitBatch(self: *ThreadPool, tasks: []const Task, priority: WorkItem.Priority) usize
pub fn submitBatchWithRetry(
    self: *ThreadPool,
    tasks: []const Task,
    priority: WorkItem.Priority,
    maxAttempts: u8,
    retryDelayUs: u32,
) usize
```

Both return the number of accepted tasks.

### Non-blocking submission

```zig
pub fn trySubmitWithHandle(self: *ThreadPool, task: Task, priority: WorkItem.Priority) TaskHandle
pub fn trySubmit(self: *ThreadPool, task: Task, priority: WorkItem.Priority) bool
```

These attempts do not wait for queue capacity.

### Worker-specific submission

```zig
pub fn submitToWorkerWithHandle(
    self: *ThreadPool,
    workerId: usize,
    task: Task,
    priority: WorkItem.Priority,
) TaskHandle
pub fn submitToWorker(
    self: *ThreadPool,
    workerId: usize,
    task: Task,
    priority: WorkItem.Priority,
) bool
```

Returns rejection when `workerId` is out of range or the pool is not running.

### cancel

```zig
pub fn cancel(self: *ThreadPool, handle: TaskHandle) bool
```

Removes a queued task if it has not started. Returns `true` when cancelled.

## Waiting and Queue State

```zig
pub fn waitAll(self: *ThreadPool) void
pub fn waitAllTimeout(self: *ThreadPool, timeoutMs: u64) bool
pub fn waitUntilQueueBelow(self: *ThreadPool, threshold: usize, timeoutMs: u64) bool

pub fn pendingTasks(self: *ThreadPool) usize
pub fn pendingTasksByQueue(self: *ThreadPool) QueueDepth
pub fn queueCapacity(self: *const ThreadPool) usize
pub fn availableQueueCapacity(self: *ThreadPool) usize
pub fn canAcceptTasks(self: *ThreadPool, requiredSlots: usize) bool
pub fn queueUtilization(self: *ThreadPool) f64
pub fn isSaturated(self: *ThreadPool, threshold: f64) bool
pub fn activeThreads(self: *const ThreadPool) u32
```

### clear / resetStats

```zig
pub fn clear(self: *ThreadPool) void
pub fn resetStats(self: *ThreadPool) void
```

`clear()` discards pending tasks and invokes their drop hooks. `resetStats()` clears counters.

### isEmpty / isFull / utilization

```zig
pub fn isEmpty(self: *ThreadPool) bool
pub fn isFull(self: *ThreadPool) bool
pub fn utilization(self: *const ThreadPool) f64
```

## Callbacks

```zig
pub fn setThreadStartCallback(self: *ThreadPool, callback: ?*const fn (usize) void) void
pub fn setThreadStopCallback(self: *ThreadPool, callback: ?*const fn (usize, u64, u64) void) void
pub fn setTaskSubmittedCallback(self: *ThreadPool, callback: ?*const fn (u8, usize) void) void
pub fn setTaskDequeuedCallback(self: *ThreadPool, callback: ?*const fn (u8, u64) void) void
pub fn setTaskExecutedCallback(self: *ThreadPool, callback: ?*const fn (u64, bool) void) void
pub fn setWorkStolenCallback(self: *ThreadPool, callback: ?*const fn (usize, usize) void) void
pub fn setQueueOverflowCallback(self: *ThreadPool, callback: ?*const fn (usize, usize) void) void
```

Callbacks must be thread-safe and non-blocking.

## Statistics

```zig
pub fn getStats(self: *const ThreadPool) ThreadPoolStats
```

Returns a snapshot with atomic counters. See `ThreadPoolStats` for available accessors.

## ThreadPoolPresets

```zig
pub fn singleThread() ThreadPoolConfig
pub fn cpuBound() ThreadPoolConfig
pub fn ioBound() ThreadPoolConfig
pub fn highThroughput() ThreadPoolConfig
pub fn lowLatency() ThreadPoolConfig
```

`ThreadPool` also exposes `ThreadPoolPresets.default()` and `lowResource()`.

## ParallelSinkWriter API

### init / initWithConfig

```zig
pub fn init(allocator: std.mem.Allocator, pool: *ThreadPool) !*ParallelSinkWriter
pub fn initWithConfig(
    allocator: std.mem.Allocator,
    pool: *ThreadPool,
    config: ParallelConfig,
) !*ParallelSinkWriter
```

The pool must outlive the writer.

### deinit

```zig
pub fn deinit(self: *ParallelSinkWriter) void
```

Flushes buffered data and releases sinks and buffers.

### addSink / removeSink / setSinkEnabled

```zig
pub fn addSink(self: *ParallelSinkWriter, handle: SinkHandle) !void
pub fn removeSink(self: *ParallelSinkWriter, name: []const u8) void
pub fn setSinkEnabled(self: *ParallelSinkWriter, name: []const u8, enabled: bool) void
```

Sink names are compared byte-for-byte. Removing or disabling an unknown name is a no-op.

### writeParallel

```zig
pub fn writeParallel(self: *ParallelSinkWriter, data: []const u8) void
```

Copies `data` into the writer buffer and dispatches to enabled sinks. There is no `write` alias.

### flushBuffer / flushAll

```zig
pub fn flushBuffer(self: *ParallelSinkWriter) void
pub fn flushAll(self: *ParallelSinkWriter) void
```

`flushBuffer()` drains buffered payloads. `flushAll()` calls `flushBuffer()` and invokes every registered `flushFn`. There is no `flush` alias.

### getStats / sinkCount / hasEnabledSinks

```zig
pub fn getStats(self: *const ParallelSinkWriter) ParallelStats
pub fn sinkCount(self: *const ParallelSinkWriter) usize
pub fn hasEnabledSinks(self: *ParallelSinkWriter) bool
```

## See Also

- [Thread Pool Guide](/guide/thread-pool)
- [Thread Pool Example](/examples/thread-pool)
- [Async Logger API](/api/async)
