# Thread Pool API

The thread pool module provides parallel log processing capabilities with work stealing, priority queues, and concurrent sink writing.

## Overview

```zig
const logly = @import("logly");
const ThreadPool = logly.ThreadPool;
const ThreadPoolPresets = logly.ThreadPoolPresets;
```

## Centralized Configuration

Thread pool can be enabled through the central `Config` struct:

```zig
var config = logly.Config.default();
config.thread_pool = .{
    .enabled = true,
    .thread_count = 4,  // 0 = auto-detect
    .queue_size = 10000,
    .work_stealing = true,
};
const logger = try logly.Logger.initWithConfig(allocator, config);
```

Or use the fluent API:

```zig
const config = logly.Config.default().withThreadPool(4);
```

## Types

### ThreadPool

The core thread pool implementation that manages worker threads and task distribution. It employs a work-stealing algorithm to balance load across multiple worker threads, ensuring high throughput and low latency.

**Fields:**
- `allocator`: The memory allocator used for internal structures.
- `config`: The active configuration for the thread pool.
- `workers`: Slice of worker threads.
- `work_queue`: The global task queue for incoming tasks.
- `stats`: Performance statistics (submitted, completed, stolen tasks).
- `running`: Atomic flag indicating the pool's operational state.

```zig
pub const ThreadPool = struct {
    allocator: std.mem.Allocator,
    config: ThreadPoolConfig,
    workers: []Worker,
    work_queue: WorkQueue,
    stats: ThreadPoolStats,
    running: std.atomic.Value(bool),
};
```

### ThreadPoolConfig (Centralized)

Configuration available through `Config.ThreadPoolConfig`. This struct controls the initialization and behavior of the thread pool.

**Fields:**
- `enabled`: Master switch to enable/disable the thread pool.
- `thread_count`: Number of worker threads to spawn. Set to 0 to automatically detect and use the number of available CPU cores.
- `queue_size`: Capacity of the global task queue. If the queue is full, submission may block or fail depending on policy.
- `stack_size`: Stack size allocated for each worker thread (in bytes). Default is 1MB.
- `work_stealing`: Enables the work-stealing algorithm, allowing idle workers to take tasks from busy workers' local queues.

```zig
pub const ThreadPoolConfig = struct {
    /// Enable thread pool for parallel processing.
    enabled: bool = false,
    /// Number of worker threads (0 = auto-detect based on CPU cores).
    thread_count: usize = 0,
    /// Maximum queue size for pending tasks.
    queue_size: usize = 10000,
    /// Stack size per thread in bytes.
    stack_size: usize = 1024 * 1024,
    /// Enable work stealing between threads.
    work_stealing: bool = true,
    /// Enable per-worker arena allocator.
    enable_arena: bool = false,
};
```

### Module-specific ThreadPoolConfig

The `ThreadPool` module has its own detailed config:

```zig
pub const ThreadPoolConfig = struct {
    /// Number of worker threads (0 = auto-detect CPU cores)
    num_threads: usize = 0,
    /// Maximum queue size per worker
    queue_size: usize = 1024,
    /// Enable work stealing between threads
    work_stealing: bool = true,
    /// Thread naming prefix
    thread_name_prefix: []const u8 = "logly-worker",
    /// Stack size for worker threads (0 = default)
    stack_size: usize = 0,
    /// Keep alive time for idle threads (milliseconds)
    keep_alive_ms: u64 = 60000,
    /// Enable thread affinity (pin threads to CPUs)
    thread_affinity: bool = false,
    /// Enable per-worker arena allocator for temporary allocations
    enable_arena: bool = false,
};
```

### ThreadPoolPresets

Helper functions to create common thread pool configurations.

```zig
pub const ThreadPoolPresets = struct {
    /// Default configuration: auto-detect threads, standard queue size.
    pub fn default() ThreadPoolConfig { ... }

    /// High-throughput configuration: larger queues, work stealing enabled.
    pub fn highThroughput() ThreadPoolConfig { ... }

    /// Low-resource configuration: minimal threads, small queues.
    pub fn lowResource() ThreadPoolConfig { ... }
};
```

### TaskPriority

Priority levels for tasks.

```zig
pub const TaskPriority = enum(u8) {
    low = 0,
    normal = 1,
    high = 2,
    critical = 3,
};
```

### Task

A unit of work for the thread pool.

```zig
pub const Task = union(enum) {
    /// Function pointer task
    func: *const fn () void,
    /// Callback with context
    callback: struct {
        func: *const fn (*anyopaque) void,
        context: *anyopaque,
    },
    /// Shutdown signal
    shutdown: void,
};
```

### ThreadPoolStats

Statistics for the thread pool.

```zig
pub const ThreadPoolStats = struct {
    tasks_submitted: std.atomic.Value(u64),
    tasks_completed: std.atomic.Value(u64),
    tasks_dropped: std.atomic.Value(u64),
    tasks_stolen: std.atomic.Value(u64),
    total_wait_time_ns: std.atomic.Value(u64),
    total_exec_time_ns: std.atomic.Value(u64),
    active_threads: std.atomic.Value(u32),

    pub fn avgWaitTimeNs(self: *const ThreadPoolStats) u64;
    pub fn avgExecTimeNs(self: *const ThreadPoolStats) u64;
    pub fn throughput(self: *const ThreadPoolStats) f64;
};
```

### ParallelSinkWriter

Writes to multiple sinks in parallel.

```zig
pub const ParallelSinkWriter = struct {
    allocator: std.mem.Allocator,
    config: ParallelConfig,
    sinks: std.ArrayList(*Sink),
    thread_pool: ThreadPool,
    stats: WriterStats,
};
```

### ParallelConfig

Configuration for parallel sink writing.

```zig
pub const ParallelConfig = struct {
    /// Maximum concurrent writes
    max_concurrent: usize = 8,
    /// Timeout for each write operation (ms)
    write_timeout_ms: u64 = 1000,
    /// Retry failed writes
    retry_on_failure: bool = true,
    /// Maximum retry attempts
    max_retries: u3 = 3,
    /// Fail-fast on any sink error
    fail_fast: bool = false,
    /// Buffer writes before parallel dispatch
    buffered: bool = true,
    /// Buffer size
    buffer_size: usize = 64,
};
```

## ThreadPool Methods

### init

Create a new thread pool.

```zig
pub fn init(allocator: std.mem.Allocator, config: ThreadPoolConfig) !ThreadPool
```

**Parameters:**
- `allocator`: Memory allocator
- `config`: Thread pool configuration

**Returns:** A new `ThreadPool` instance

### deinit

Clean up resources and stop all workers.

```zig
pub fn deinit(self: *ThreadPool) void
```

### start

Start all worker threads.

```zig
pub fn start(self: *ThreadPool) !void
```

### stop

Stop all workers gracefully.

```zig
pub fn stop(self: *ThreadPool) void
```

### submit

Submit a task to the pool.

```zig
pub fn submit(self: *ThreadPool, task: Task) !void
```

**Parameters:**
- `task`: The task to execute

### submitWithPriority

Submit a task with specific priority.

```zig
pub fn submitWithPriority(
    self: *ThreadPool,
    func: *const fn (*anyopaque) void,
    context: *anyopaque,
    priority: TaskPriority,
) !void
```

### waitIdle

Wait until all tasks are completed.

```zig
pub fn waitIdle(self: *ThreadPool) void
```

### getStats

Get current pool statistics.

```zig
pub fn getStats(self: *const ThreadPool) PoolStats
```

## PoolStats Methods

### throughput

Calculate tasks per second.

```zig
pub fn throughput(self: *const PoolStats) f64
```

### averageWaitTimeNs

Get average task wait time.

```zig
pub fn averageWaitTimeNs(self: *const PoolStats) u64
```

### averageExecTimeNs

Get average task execution time.

```zig
pub fn averageExecTimeNs(self: *const PoolStats) u64
```

## ParallelSinkWriter Methods

### init

Create a new parallel sink writer.

```zig
pub fn init(allocator: std.mem.Allocator, config: ParallelConfig) !ParallelSinkWriter
```

### deinit

Clean up resources.

```zig
pub fn deinit(self: *ParallelSinkWriter) void
```

### addSink

Add a sink for parallel writing.

```zig
pub fn addSink(self: *ParallelSinkWriter, sink: *Sink) !void
```

### write

Write to all sinks in parallel.

```zig
pub fn write(self: *ParallelSinkWriter, record: *const Record) !void
```

### flush

Flush all sinks.

```zig
pub fn flush(self: *ParallelSinkWriter) void
```

## Presets

### singleThread

Single-threaded pool for testing or simple use cases.

```zig
pub fn singleThread() ThreadPoolConfig {
    return .{
        .thread_count = 1,
        .work_stealing = false,
        .queue_size = 256,
    };
}
```

### cpuBound

Optimized for CPU-intensive tasks.

```zig
pub fn cpuBound() ThreadPoolConfig {
    const cpu_count = std.Thread.getCpuCount() catch 4;
    return .{
        .thread_count = cpu_count,
        .work_stealing = true,
        .enable_priorities = true,
    };
}
```

### ioBound

Optimized for I/O-intensive tasks.

```zig
pub fn ioBound() ThreadPoolConfig {
    const cpu_count = std.Thread.getCpuCount() catch 4;
    return .{
        .thread_count = cpu_count * 2,
        .queue_size = 2048,
        .work_stealing = true,
    };
}
```

### highThroughput

Maximum throughput configuration.

```zig
pub fn highThroughput() ThreadPoolConfig {
    return .{
        .thread_count = 0, // Auto
        .queue_size = 4096,
        .work_stealing = true,
        .enable_priorities = false,
        .thread_local_cache = true,
    };
}
```

## Usage Example

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create thread pool with CPU-bound preset
    var pool = try logly.ThreadPool.init(
        allocator,
        logly.ThreadPoolPresets.cpuBound(),
    );
    defer pool.deinit();

    // Start workers
    try pool.start();
    defer pool.stop();

    // Submit tasks
    var counter: std.atomic.Value(u32) = std.atomic.Value(u32).init(0);
    
    for (0..100) |_| {
        try pool.submit(.{
            .func = incrementTask,
            .context = @ptrCast(&counter),
            .priority = .normal,
            .submitted_at = std.time.milliTimestamp(),
        });
    }

    // Wait for completion
    pool.waitIdle();

    // Check stats
    const stats = pool.getStats();
    std.debug.print("Completed: {d}, Throughput: {d:.2} tasks/sec\n", .{
        stats.tasks_completed.load(.monotonic),
        stats.throughput(),
    });
}

fn incrementTask(ctx: *anyopaque) void {
    const counter: *std.atomic.Value(u32) = @alignCast(@ptrCast(ctx));
    _ = counter.fetchAdd(1, .monotonic);
}
```

## See Also

- [Async API](async.md) - Async logging with ring buffers
- [Scheduler API](scheduler.md) - Scheduled tasks
- [Configuration Guide](../guide/configuration.md) - Full configuration options
