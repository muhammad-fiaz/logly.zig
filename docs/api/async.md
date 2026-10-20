---
title: Async API Reference
description: API reference for Logly.zig AsyncLogger and ring buffer. Non-blocking logging with configurable buffering, batch processing, and up to 36M ops/sec throughput.
head:
  - - meta
    - name: keywords
      content: async api, async logger, ring buffer, non-blocking logging, background processing, high throughput
  - - meta
    - property: og:title
      content: Async API Reference | Logly.zig
---

# Async API

The async module provides non-blocking asynchronous logging with configurable buffering, background processing, and high-throughput capabilities.

## Overview

```zig
const logly = @import("logly");
const AsyncLogger = logly.AsyncLogger;
const AsyncFileWriter = logly.AsyncFileWriter;
```

## Centralized Configuration

Async logging can be enabled through the central `Config` struct:

```zig
var config = logly.Config.default();
config.asyncConfig = .{
    .enabled = true,
    .bufferSize = 16384,
    .batchSize = 128,
    .flushIntervalMs = 50,
};
const logger = try logly.Logger.initWithConfig(allocator, config);
```

Or use the fluent API:

```zig
const config = logly.Config.default().withAsync();
```

## Types

### AsyncLogger

The main async logging struct with ring buffer and background worker.

```zig
pub const AsyncLogger = struct {
    allocator: std.mem.Allocator,
    config: AsyncConfig,
    buffer: RingBuffer,
    stats: AsyncStats,
    workerThread: ?std.Thread,
    sinks: std.ArrayList(*Sink),
};
```

### AsyncConfig

Configuration available through `Config.AsyncConfig`:

```zig
pub const AsyncConfig = struct {
    /// Enable async logging.
    enabled: bool = false,
    /// Number of slots in the queue.
    bufferSize: usize = 8192,
    /// Records dequeued per batch.
    batchSize: usize = 64,
    /// Interval between flushes, in milliseconds.
    flushIntervalMs: u64 = 1000,
    /// Minimum time between flushes, in milliseconds.
    minFlushIntervalMs: u64 = 0,
    /// Maximum time a record may wait before a forced flush, in milliseconds.
    maxLatencyMs: u64 = 5000,
    /// Behavior when the queue is full.
    overflowPolicy: OverflowPolicy = .dropOldest,
    /// Start the worker during initialization.
    backgroundWorker: bool = true,
    /// Queue utilization that records a backpressure event.
    backpressureThreshold: f64 = 0.9,
    /// Default timeout for explicit drain waits, in milliseconds.
    drainTimeoutMs: u64 = 5000,
    /// Shutdown grace period, in milliseconds.
    shutdownTimeoutMs: u64 = 5000,
    /// Explicit I/O handle. Inherited from the logger when null.
    io: ?std.Io = null,

    pub const OverflowPolicy = enum {
        dropOldest,
        dropNewest,
        block,
    };
};
```

### OverflowPolicy

What to do when the buffer is full.

```zig
pub const OverflowPolicy = enum {
    /// Drop the oldest queued entry to make room.
    dropOldest,
    /// Drop the incoming entry.
    dropNewest,
    /// Block the producer until space is available.
    block,
};
```

### WorkerPriority

Worker thread priority levels.

```zig
pub const WorkerPriority = enum {
    low,
    normal,
    high,
    realtime,
};
```

### AsyncStats

Statistics for async operations.

```zig
pub const AsyncStats = struct {
    recordsQueued: std.atomic.Value(u64),
    recordsWritten: std.atomic.Value(u64),
    recordsDropped: std.atomic.Value(u64),
    bufferOverflows: std.atomic.Value(u64),
    backpressureEvents: std.atomic.Value(u64),
    flushCount: std.atomic.Value(u64),
    totalLatencyNs: std.atomic.Value(u64),
    maxQueueDepth: std.atomic.Value(u64),
    lastFlushTimestamp: std.atomic.Value(i64),
};
```

### RingBuffer

Circular buffer used by `AsyncLogger`.

```zig
pub const RingBuffer = struct {
    allocator: std.mem.Allocator,
    entries: []BufferEntry,
    head: usize,
    tail: usize,
    count: usize,
    capacity: usize,
};
```

### AsyncFileWriter

Buffered file writer with optional periodic flushing.

```zig
pub const AsyncFileWriter = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    file: std.Io.File,
    buffer: std.ArrayList(u8),
    config: FileConfig,
    mutex: std.Io.Mutex,
    flushThread: ?std.Thread,
    running: std.atomic.Value(bool),
    totalBytesWritten: std.atomic.Value(u64),
    lastFlush: std.atomic.Value(i64),
};
```

### FileConfig

Configuration for `AsyncFileWriter`.

```zig
pub const FileConfig = struct {
    bufferSize: usize,
    flushIntervalMs: u64,
    syncOnFlush: bool = false,
    appendMode: bool = true,
    io: ?std.Io = null,
};
```

## AsyncLogger Methods

### init

Create a new async logger with default configuration.

```zig
pub fn init(allocator: std.mem.Allocator) !*AsyncLogger
```

### initWithConfig

Create a new async logger with custom configuration. Uses `config.io` if set, otherwise defaults to `logly.defaultIo()`.

```zig
pub fn initWithConfig(allocator: std.mem.Allocator, config: AsyncConfig) !*AsyncLogger
```

### initWithIo

Create a new async logger with an explicit `std.Io` handle and custom configuration.

```zig
pub fn initWithIo(allocator: std.mem.Allocator, io_handle: std.Io, config: AsyncConfig) !*AsyncLogger
```

### deinit

Clean up resources and stop worker thread.

```zig
pub fn deinit(self: *AsyncLogger) void
```

### startWorker

Start the background worker thread.

```zig
pub fn startWorker(self: *AsyncLogger) !void
```

### stop

Stop the background worker and flush remaining logs.

```zig
pub fn stop(self: *AsyncLogger) void
```

### queue

Queue a preformatted message with its level priority. Returns false when the queue is full under a drop policy.

```zig
pub fn queue(self: *AsyncLogger, message: []const u8, levelPriority: u8) bool
```

### addSink

Add a sink for the async logger to write to.

```zig
pub fn addSink(self: *AsyncLogger, sink: *Sink) !void
```

### flush

Force flush all pending records.

```zig
pub fn flush(self: *AsyncLogger) void
```

### drainAndFlush

Wait up to `timeoutMs` for the queue to drain completely, then flush the buffer to ensure durability before shutting down.

```zig
pub fn drainAndFlush(self: *AsyncLogger, timeoutMs: u64) bool
```

### isBackpressured

Returns `isNearCapacity(0.9)`. Signals that the async queue is close to capacity.

```zig
pub fn isBackpressured(self: *AsyncLogger) bool
```

### getStats

Get current async statistics.

```zig
pub fn getStats(self: *const AsyncLogger) AsyncStats
```

### availableCapacity

Get available slots before the queue reaches capacity.

```zig
pub fn availableCapacity(self: *AsyncLogger) usize
```

### queueUtilization

Get queue utilization as a ratio in `[0.0, 1.0]`.

```zig
pub fn queueUtilization(self: *AsyncLogger) f64
```

### isNearCapacity

Check whether queue utilization is above a threshold.

```zig
pub fn isNearCapacity(self: *AsyncLogger, threshold: f64) bool
```

### waitUntilDrained

Wait for the queue to drain until timeout.

```zig
pub fn waitUntilDrained(self: *AsyncLogger, timeoutMs: u64) bool
```

## AsyncStats Methods

### Getter Methods

#### getQueued
Get total records queued.
```zig
pub fn getQueued(self: *const AsyncStats) u64
```

#### getWritten
Get total records written.
```zig
pub fn getWritten(self: *const AsyncStats) u64
```

#### getDropped
Get total records dropped.
```zig
pub fn getDropped(self: *const AsyncStats) u64
```

#### getFlushCount
Get total flush operations.
```zig
pub fn getFlushCount(self: *const AsyncStats) u64
```

#### inFlight
Get queued-but-not-yet-written records.
```zig
pub fn inFlight(self: *const AsyncStats) u64
```

#### getMaxQueueDepth
Get maximum queue depth reached.
```zig
pub fn getMaxQueueDepth(self: *const AsyncStats) u64
```

#### getBufferOverflows
Get total buffer overflows.
```zig
pub fn getBufferOverflows(self: *const AsyncStats) u64
```

### Boolean Checks

#### hasDropped
Check if any records have been dropped.
```zig
pub fn hasDropped(self: *const AsyncStats) bool
```

#### hasOverflows
Check if any buffer overflows occurred.
```zig
pub fn hasOverflows(self: *const AsyncStats) bool
```

### Rate Calculations

#### dropRate
Calculate the percentage of dropped records.
```zig
pub fn dropRate(self: *const AsyncStats) f64
```

#### successRate
Calculate successful write rate (0.0 - 1.0).
```zig
pub fn successRate(self: *const AsyncStats) f64
```

#### getBackpressureEvents()
Return the number of backpressure events.
```zig
pub fn getBackpressureEvents(self: *const AsyncStats) u64
```

#### hasBackpressureEvents()
Return true when a backpressure event has been recorded.
```zig
pub fn hasBackpressureEvents(self: *const AsyncStats) bool
```

#### averageLatencyMs
Get average latency in milliseconds.
```zig
pub fn averageLatencyMs(self: *const AsyncStats) f64
```

#### averageLatencyNs
Get average latency in nanoseconds.
```zig
pub fn averageLatencyNs(self: *const AsyncStats) u64
```

### Reset

`AsyncLogger.resetStats()` resets the logger's runtime statistics.

## AsyncFileWriter Methods

### init

Open a file for buffered writes.

```zig
pub fn init(allocator: std.mem.Allocator, path: []const u8, config: FileConfig) !*AsyncFileWriter
```

### deinit

Flush remaining data, stop the flush thread, close the file, and free the writer.

```zig
pub fn deinit(self: *AsyncFileWriter) void
```

### write

Queue bytes verbatim; flushes when the buffer reaches `bufferSize`.

```zig
pub fn write(self: *AsyncFileWriter, data: []const u8) !void
```

### writeLine

Queue bytes followed by a newline; flushes when the buffer reaches `bufferSize`.

```zig
pub fn writeLine(self: *AsyncFileWriter, data: []const u8) !void
```

### flushSync

Flush the buffer on the calling thread.

```zig
pub fn flushSync(self: *AsyncFileWriter) void
```

### startAutoFlush / stop

Start or stop periodic flushing using `flushIntervalMs`.

```zig
pub fn startAutoFlush(self: *AsyncFileWriter) !void
pub fn stop(self: *AsyncFileWriter) void
```

### bytesWritten

Return the number of bytes flushed by this writer.

```zig
pub fn bytesWritten(self: *const AsyncFileWriter) u64
```

## Presets

`AsyncPresets` returns `AsyncLogger.AsyncConfig` values:

| Preset | Buffer | Batch | Flush | Max latency | Overflow |
|--------|--------|-------|-------|-------------|----------|
| `highThroughput()` | 65,536 | 256 | 500 ms | 1,000 ms | `dropOldest` |
| `lowLatency()` | 1,024 | 16 | 10 ms | 50 ms | `block` |
| `balanced()` | 8,192 | 64 | 100 ms | 500 ms | `dropOldest` |
| `noDrop()` | 16,384 | 64 | 100 ms | 500 ms | `block` |

All presets enable the background worker and set `enabled = true`.

## Usage Example

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create async logger with high throughput config
    var asyncLogger = try logly.AsyncLogger.initWithConfig(
        allocator,
        logly.AsyncPresets.highThroughput(),
    );
    defer asyncLogger.deinit();

    // Start the background worker
    try asyncLogger.startWorker();
    defer asyncLogger.stop();

    // Queue preformatted messages (non-blocking)
    for (0..1000) |i| {
        _ = i;
        _ = asyncLogger.queue("message", 20);
    }

    // Check statistics
    const stats = asyncLogger.getStats();
    std.debug.print("Queued: {d}, Written: {d}, Dropped: {d}\\n", .{
        stats.getQueued(),
        stats.getWritten(),
        stats.getDropped(),
    });
    std.debug.print("Drop rate: {d:.2}%\\n", .{stats.dropRate() * 100});
}
```

> [!IMPORTANT]
> **Async logging vs `autoFlush`**: These are independent concepts that are often confused:
> - **Async logging** (`asyncConfig.enabled`): Records are queued in a bounded ring buffer synchronized by a mutex and processed by background worker threads. This controls *when* and *how* log records are dispatched.
> - **`autoFlush`**: Controls whether sinks are flushed after each record (sync path) or after each batch (async path). This controls *durability guarantees*.
> - **Thread pool**: Records are submitted as tasks to a worker pool. No flush occurs at submission time; the task is still queued and not yet written to any sink.
>
> In practice: if you enable async logging with `autoFlush = false`, records are batched and flushed on the configured interval or when the batch size is reached. If you enable async logging with `autoFlush = true`, sinks are flushed after every batch, which can reduce throughput.

## See Also

- [Async Logging Guide](../guide/async.md) - In-depth async logging guide
- [Thread Pool API](thread-pool.md) - Parallel logging
- [Configuration Guide](../guide/configuration.md) - Full configuration options

## Additional Methods

- `isRunning() bool` - Returns true if the async logger worker is running
- `bufferCapacity() usize` - Returns the buffer capacity
- `isFull() bool` - Returns true if the buffer is at capacity
- `queueDepth() usize` - Returns current queue depth
- `isQueueEmpty() bool` - Returns true if queue is empty
- `availableCapacity() usize` - Returns remaining queue slots
- `queueUtilization() f64` - Returns current queue utilization ratio
- `isNearCapacity(threshold: f64) bool` - Returns true when utilization exceeds threshold
- `waitUntilDrained(timeoutMs: u64) bool` - Waits for queue drain until timeout
- `resetStats() void` - Resets all statistics

## Callbacks

```zig
// Set callbacks for various events
logger.setOverflowCallback(onOverflow);
logger.setFlushCallback(onFlush);
logger.setWorkerStartCallback(onWorkerStart);
logger.setWorkerStopCallback(onWorkerStop);
logger.setBatchProcessedCallback(onBatchProcessed);
logger.setLatencyThresholdExceededCallback(onLatencyExceeded);
logger.setFullCallback(onBufferFull);
logger.setEmptyCallback(onBufferEmpty);
logger.setErrorCallback(onError);
```
