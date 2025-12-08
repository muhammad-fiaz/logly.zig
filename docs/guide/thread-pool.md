# Thread Pool Guide

This guide covers parallel log processing in Logly using thread pools, including configuration, task submission, work stealing, and best practices.

## Overview

The thread pool module enables parallel log processing for high-throughput scenarios. It provides configurable worker threads, priority queues, work stealing, and parallel sink writing.

## Logger Configuration

Configure thread pool settings through the logger's `Config`:

```zig
const logly = @import("logly");

var config = logly.Config.default();
config.thread_pool = .{
    .enabled = true,              // Enable thread pool
    .thread_count = 8,            // Number of worker threads
    .queue_size = 2048,           // Max queued tasks
    .stack_size = 1024 * 1024,    // 1MB per thread
    .work_stealing = true,        // Enable work stealing
};

// Or use helper method
var config2 = logly.Config.default().withThreadPool(4); // 4 worker threads
```

## Quick Start

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create thread pool with default settings
    var pool = try logly.ThreadPool.init(allocator, .{
        .thread_count = 4,
        .work_stealing = true,
    });
    defer pool.deinit();

    // Start workers
    try pool.start();
    defer pool.stop();

    // Submit tasks
    // pool.submit(...);
}
```

## Configuration

### Thread Count

```zig
// Specific number of threads
.thread_count = 8

// Auto-detect (0 = CPU cores)
.thread_count = 0
```

### Queue Size

```zig
// Per-thread queue size
.queue_size = 1024

// Large queue for bursty workloads
.queue_size = 4096
```

### Work Stealing

Enable threads to steal work from other threads' queues:

```zig
.work_stealing = true
```

This improves load balancing when some threads finish faster than others.

### Arena Allocation

Enable per-worker arena allocation for efficient memory usage:

```zig
.enable_arena = true
```

When enabled, each worker thread maintains its own arena allocator. This is particularly useful for formatting operations, as it reduces contention on the global allocator and improves cache locality. The arena is automatically reset after each task.

### Priority Queues

Enable task prioritization:

```zig
.enable_priorities = true
```

## Presets

Use built-in presets for common scenarios:

```zig
// Single thread (for testing/debugging)
const single = logly.ThreadPoolPresets.singleThread();

// CPU-bound tasks (N threads, work stealing)
const cpu = logly.ThreadPoolPresets.cpuBound();

// I/O-bound tasks (2N threads, large queues)
const io = logly.ThreadPoolPresets.ioBound();

// Maximum throughput
const high = logly.ThreadPoolPresets.highThroughput();
```

## Submitting Tasks

### Basic Task Submission

```zig
try pool.submit(.{
    .func = myTaskFunction,
    .context = @ptrCast(&myData),
    .priority = .normal,
    .submitted_at = std.time.milliTimestamp(),
});

fn myTaskFunction(ctx: *anyopaque) void {
    const data: *MyData = @alignCast(@ptrCast(ctx));
    // Process data...
}
```

### Priority Levels

```zig
pub const TaskPriority = enum(u8) {
    low = 0,      // Background tasks
    normal = 1,   // Regular logging
    high = 2,     // Important logs
    critical = 3, // Error/alert logs
};
```

### Submit with Priority

```zig
try pool.submitWithPriority(
    myFunction,
    @ptrCast(&data),
    .critical,
);
```

## Parallel Sink Writing

Write to multiple sinks concurrently:

```zig
var writer = try logly.ParallelSinkWriter.init(allocator, .{
    .max_concurrent = 4,
    .retry_on_failure = true,
    .fail_fast = false,
});
defer writer.deinit();

// Add sinks
try writer.addSink(&file_sink);
try writer.addSink(&console_sink);
try writer.addSink(&network_sink);

// Write to all sinks in parallel
try writer.write(&record);
```

### Configuration Options

```zig
pub const ParallelConfig = struct {
    max_concurrent: usize = 8,       // Max parallel writes
    write_timeout_ms: u64 = 1000,    // Timeout per write
    retry_on_failure: bool = true,   // Retry failed writes
    max_retries: u3 = 3,             // Max retry attempts
    fail_fast: bool = false,         // Stop on first error
    buffered: bool = true,           // Buffer before dispatch
    buffer_size: usize = 64,         // Buffer size
};
```

## Statistics

Monitor pool performance:

```zig
const stats = pool.getStats();

std.debug.print("Tasks completed: {d}\n", .{
    stats.tasks_completed.load(.monotonic),
});
std.debug.print("Tasks stolen: {d}\n", .{
    stats.tasks_stolen.load(.monotonic),
});
std.debug.print("Throughput: {d:.2} tasks/sec\n", .{
    stats.throughput(),
});
std.debug.print("Avg wait time: {d}ns\n", .{
    stats.averageWaitTimeNs(),
});
std.debug.print("Avg exec time: {d}ns\n", .{
    stats.averageExecTimeNs(),
});
```

## Use Cases

### 1. High-Volume Logging

```zig
// Use high throughput preset
var pool = try logly.ThreadPool.init(
    allocator,
    logly.ThreadPoolPresets.highThroughput(),
);
```

### 2. Multiple Log Destinations

```zig
// Write to file, console, and network simultaneously
var writer = try logly.ParallelSinkWriter.init(allocator, .{
    .max_concurrent = 3,
});
try writer.addSink(&file_sink);
try writer.addSink(&console_sink);
try writer.addSink(&network_sink);
```

### 3. Batch Processing

```zig
// Process log batches in parallel
for (log_batches) |batch| {
    try pool.submit(.{
        .func = processBatch,
        .context = @ptrCast(&batch),
    });
}
pool.waitIdle();
```

### 4. Priority-Based Logging

```zig
// Critical logs get processed first
try pool.submitWithPriority(logError, &error_data, .critical);

// Regular logs processed normally
try pool.submitWithPriority(logInfo, &info_data, .normal);

// Debug logs processed last
try pool.submitWithPriority(logDebug, &debug_data, .low);
```

## Work Stealing

Work stealing improves efficiency when:
- Tasks have variable execution times
- Some threads finish faster than others
- You want better CPU utilization

```zig
var pool = try logly.ThreadPool.init(allocator, .{
    .work_stealing = true, // Enable work stealing
    .thread_count = 8,
});
```

### How It Works

1. Each thread has its own work queue
2. When a thread's queue is empty, it "steals" from others
3. Stealing is done from the back of other queues
4. This balances work across all threads

## Integration with Async Logger

Combine thread pools with async logging:

```zig
var async_logger = try logly.AsyncLogger.init(allocator, .{
    .buffer_size = 8192,
});

var pool = try logly.ThreadPool.init(allocator, .{
    .thread_count = 4,
});

// Use pool for parallel sink writing
var parallel_writer = try logly.ParallelSinkWriter.init(allocator, .{});

// Connect components...
```

## Best Practices

### 1. Choose Appropriate Thread Count

```zig
// CPU-bound: Use CPU core count
.thread_count = std.Thread.getCpuCount() catch 4

// I/O-bound: Use 2x CPU cores
.thread_count = (std.Thread.getCpuCount() catch 4) * 2
```

### 2. Size Queues Appropriately

```zig
// For bursty workloads, use larger queues
.queue_size = 4096

// For steady workloads, smaller is fine
.queue_size = 256
```

### 3. Handle Queue Full

```zig
pool.submit(task) catch |err| {
    if (err == error.QueueFull) {
        // Handle backpressure
        // - Wait and retry
        // - Drop the task
        // - Expand queue
    }
};
```

### 4. Graceful Shutdown

```zig
// Stop accepting new tasks
pool.stop();

// Or with timeout
pool.stopWithTimeout(5000); // 5 second timeout
```

### 5. Monitor Performance

Regularly check statistics to identify bottlenecks:

```zig
const stats = pool.getStats();
if (stats.tasks_dropped.load(.monotonic) > 0) {
    // Queue overflow - increase queue size or threads
}
```

## Error Handling

```zig
try pool.submit(task) catch |err| {
    switch (err) {
        error.PoolNotRunning => {
            // Pool hasn't started or has stopped
        },
        error.QueueFull => {
            // All queues are full
        },
        error.OutOfMemory => {
            // Memory allocation failed
        },
    }
};
```

## Performance Considerations

- **Thread overhead**: Each thread has memory overhead (~8KB stack)
- **Context switching**: Too many threads can cause overhead
- **Cache locality**: Work stealing may affect cache performance
- **Lock contention**: Minimize shared state between tasks

## Example: Production Setup

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Production thread pool config
    const cpu_count = std.Thread.getCpuCount() catch 4;
    
    var pool = try logly.ThreadPool.init(allocator, .{
        .thread_count = cpu_count,
        .queue_size = 2048,
        .work_stealing = true,
        .enable_priorities = true,
        .shutdown_timeout_ms = 10000,
    });
    defer pool.deinit();

    // Parallel sink writer
    var writer = try logly.ParallelSinkWriter.init(allocator, .{
        .max_concurrent = 4,
        .retry_on_failure = true,
        .max_retries = 3,
    });
    defer writer.deinit();

    try pool.start();
    defer pool.stop();

    // Application runs...
    
    // Check final stats
    const stats = pool.getStats();
    std.debug.print("Total processed: {d}\n", .{
        stats.tasks_completed.load(.monotonic),
    });
}
```

## See Also

- [Thread Pool API Reference](../api/thread-pool.md)
- [Async Logging Guide](async.md)
- [Configuration Guide](configuration.md)
