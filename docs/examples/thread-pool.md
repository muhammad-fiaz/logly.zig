---
title: Thread Pool Example
description: Example of parallel log processing with Logly.zig thread pool. Configure worker threads, work stealing, batch submission, and priority-based task scheduling.
head:
  - - meta
    - name: keywords
      content: thread pool example, parallel logging, worker threads, work stealing, batch processing, task scheduling
  - - meta
    - property: og:title
      content: Thread Pool Example | Logly.zig
---

# Thread Pool Example

This example demonstrates parallel log processing using Logly's thread pool.

## Centralized Configuration

```zig
const logly = @import("logly");

var config = logly.Config.default();
config.thread_pool = .{
    .enabled = true,
    .thread_count = 8,
    .queue_size = 2048,
    .stack_size = 1024 * 1024,
};

// Or use helper method
var config2 = logly.Config.default().withThreadPool(.{
    .thread_count = 4,
    .queue_size = 1024,
});
```

## Source Code

```zig
//! Thread Pool Example
//!
//! Demonstrates parallel log processing with configurable thread pools.

const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create thread pool with 4 workers
    var pool = try logly.ThreadPool.init(allocator, .{
        .thread_count = 4,
        .queue_size = 1024,
        .work_stealing = true,
    });
    defer pool.deinit();

    // Start workers
    try pool.start();
    defer pool.stop();

    // Submit tasks
    var counter = std.atomic.Value(u32).init(0);
    
    for (0..50) |_| {
        _ = pool.submitCallback(incrementCounter, @ptrCast(&counter));
    }

    // Submit a batch of tasks
    var tasks: [50]logly.ThreadPool.Task = undefined;
    for (&tasks) |*task| {
        task.* = .{ .callback = .{ .func = incrementCounter, .context = @ptrCast(&counter) } };
    }
    _ = pool.submitBatch(&tasks, .normal);

    // Submit high priority task
    _ = pool.submitHighPriority(incrementCounter, @ptrCast(&counter));

    // Wait for completion
    pool.waitAll();

    // Check results
    std.debug.print("Counter value: {d}\n", .{counter.load(.monotonic)});

    const stats = pool.getStats();
    std.debug.print("Tasks completed: {d}\n", .{
        stats.tasks_completed.load(.monotonic),
    });
}

fn incrementCounter(ctx: *anyopaque) void {
    const counter: *std.atomic.Value(u32) = @alignCast(@ptrCast(ctx));
    _ = counter.fetchAdd(1, .monotonic);
}
```

## Running the Example

```bash
zig build run-thread-pool-demo
```

## Expected Output

```
Counter value: 101
Tasks completed: 101
```

## Key Concepts

### Thread Pool Configuration

```zig
.thread_count = 4,      // Number of worker threads
.queue_size = 1024,     // Queue size per thread
.work_stealing = true,  // Enable work stealing
.enable_priorities = true, // Priority queues
```

### Task Priorities

```zig
.priority = .low,      // Background tasks
.priority = .normal,   // Regular tasks
.priority = .high,     // Important tasks
.priority = .critical, // Must process first
```

### Using Presets

```zig
// Single thread (for testing)
const single = logly.ThreadPoolPresets.singleThread();

// CPU-bound workloads
const cpu = logly.ThreadPoolPresets.cpuBound();

// I/O-bound workloads
const io = logly.ThreadPoolPresets.ioBound();

// Maximum throughput
const high = logly.ThreadPoolPresets.highThroughput();
```

### Parallel Sink Writing

```zig
var writer = try logly.ParallelSinkWriter.init(allocator, .{
    .max_concurrent = 4,
});

try writer.addSink(&file_sink);
try writer.addSink(&console_sink);

// Write to all sinks in parallel
try writer.write(&record);
```

## Statistics

```zig
const stats = pool.getStats();
std.debug.print("Completed: {d}\n", .{stats.tasks_completed.load(.monotonic)});
std.debug.print("Stolen: {d}\n", .{stats.tasks_stolen.load(.monotonic)});
std.debug.print("Throughput: {d:.2}/sec\n", .{stats.throughput()});
```

## See Also

- [Thread Pool API](../api/thread-pool.md)
- [Thread Pool Guide](../guide/thread-pool.md)
- [Async Logging Example](async-logging.md)

## New Methods (v0.0.9)

```zig
var pool = try logly.ThreadPool.init(allocator, config);
defer pool.deinit();

// State methods
const empty = pool.isEmpty();
const full = pool.isFull();

// Performance metrics
const util = pool.utilization();  // 0.0 - 1.0

// Reset statistics
pool.resetStats();
```

## Aliases

| Alias | Method |
|-------|--------|
| `flush` | `clear` |
| `statistics` | `getStats` |
| `stop` | `shutdown` |
| `halt` | `shutdown` |
| `begin` | `start` |
| `add` | `submit` |

