---
title: Async Logging Guide
description: Master asynchronous logging in Logly.zig with ring buffers, worker threads, batch processing, and non-blocking I/O. Achieve up to 36M ops/sec throughput without blocking your application.
head:
  - - meta
    - name: keywords
      content: async logging, non-blocking logging, ring buffer, worker threads, high throughput logging, zig async, background logging
---

# Async Logging

Logly provides asynchronous logging so log submission does not block the application thread. This is useful for latency-sensitive services.

## Overview

Logly offers multiple async logging options:

1. **Simple Async Sinks**: Basic buffered file writing
2. **AsyncLogger**: Full-featured async logger with ring buffers
3. **AsyncFileWriter**: Optimized async file writing

## Quick Start

### Simple Async Sinks

Minimal async logger setup:

```zig
 _ = try logger.add(.{  // Short alias for addSink()
    .path = "logs/app.log",
    .asyncWrite = true,      // Enable async (default)
    .bufferSize = 8192,      // Buffer size in bytes (default 8KB)
});
```

### Full AsyncLogger

For more control, use the AsyncLogger directly:

```zig
const logly = @import("logly");

var asyncLogger = try logly.AsyncLogger.initWithConfig(allocator, .{
    .bufferSize = 8192,
    .flushIntervalMs = 100,
    .batchSize = 64,
});
defer asyncLogger.deinit();

try asyncLogger.startWorker();
defer asyncLogger.stop();
```

## Parallel Logging (Thread Pool)

For high-throughput scenarios requiring heavy processing (e.g., complex formatting, compression, or multiple slow sinks), Logly supports parallel logging using a work-stealing thread pool.

### Enabling Parallel Logging

```zig
var config = logly.Config.default();
config.threadPool = .{
    .enabled = true,
    .threadCount = 0, // 0 = auto-detect based on CPU cores
    .queueSize = 10000,
    .workStealing = true,
};
const logger = try logly.Logger.initWithConfig(allocator, config);
```

When enabled, the `Logger` dispatches log records to the thread pool. Each record is deep-copied to ensure thread safety. The thread pool distributes tasks among worker threads, which then write to the configured sinks.

### Benefits

- **Non-blocking**: The main application thread submits the task and returns immediately (unless the queue is full).
- **Scalability**: Utilizes multiple CPU cores for formatting and I/O.
- **Resilience**: Isolates slow sinks from the main application flow.

## How it Works

When async logging is enabled, log messages follow this flow:

1. **Queuing**: Messages are added to a bounded ring buffer synchronized by a mutex
2. **Background Processing**: A worker thread processes queued messages
3. **Batch Writing**: Messages are written in batches for efficiency
4. **Flushing**: Buffers are flushed based on time or size

The async statistics also track backpressure events, showing when the queue approaches capacity.

The backpressure threshold and drain timeout are configurable:

```zig
const asyncCfg = logly.AsyncConfig.lowLatency()
    .withBufferSize(2048)
    .withBatchSize(32)
    .withBackpressureThreshold(0.75);

var asyncLogger = try logly.AsyncLogger.initWithConfig(allocator, asyncCfg);
defer asyncLogger.deinit();

 _ = asyncLogger.drainAndFlush(asyncCfg.drainTimeoutMs);
```

## Configuration

### Logger Configuration

Enable async logging through the Config struct:

```zig
const logly = @import("logly");

var config = logly.Config.default();
config.asyncConfig = .{
    .enabled = true,              // Enable async logging
    .bufferSize = 8192,          // Ring buffer size
    .batchSize = 100,            // Messages per batch
    .flushIntervalMs = 100,     // Auto-flush interval
    .overflowPolicy = .dropOldest, // On buffer overflow
    .backgroundWorker = true,    // Auto-start worker thread
};

// Or use helper method
var config2 = logly.Config.default().withAsync(.{
    .bufferSize = 16384,
});
```

### Basic Configuration

```zig
const config = logly.AsyncLogger.AsyncConfig{
    .bufferSize = 8192,        // Ring buffer size
    .flushIntervalMs = 100,   // Auto-flush interval
    .batchSize = 64,           // Messages per batch
    .overflowPolicy = .dropOldest,
    .backgroundWorker = true,
    .enableMetrics = true,
};
```

### Configuration Options

| Option | Default | Description |
|--------|---------|-------------|
| `bufferSize` | 8192 | Ring buffer capacity |
| `flushIntervalMs` | 100 | Auto-flush interval in ms |
| `minFlushIntervalMs` | 0 | Minimum time between flushes |
| `maxLatencyMs` | 5000 | Maximum latency before forcing flush |
| `batchSize` | 64 | Messages written per batch |
| `overflowPolicy` | `.dropOldest` | Behavior when buffer full |
| `backgroundWorker` | true | Enable background thread |
| `backpressureThreshold` | 0.9 | Queue utilization ratio that records backpressure |
| `drainTimeoutMs` | 5000 | Default timeout for explicit drain waits |

## Overflow Policies

Control what happens when the buffer is full:

```zig
pub const OverflowPolicy = enum {
    dropOldest,  // Remove oldest to make room (default)
    dropNewest,  // Drop new messages
    block,        // Block until space available
};
```

### Choosing a Policy

- **`dropOldest`**: Best for most applications, ensures recent logs
- **`dropNewest`**: Use when historical logs are more important
- **`block`**: When you can't afford to lose any logs

## Callbacks

AsyncLogger supports various callbacks for monitoring and customization:

```zig
// Define callbacks
fn onOverflow(dropped: u64) void {
    std.debug.print("Dropped {d} records\n", .{dropped});
}

fn onFlush(count: u64, bytes: u64, elapsedMs: u64) void {
    std.debug.print("Flushed {d} records ({d} bytes) in {d}ms\n", .{count, bytes, elapsedMs});
}

// Register callbacks
asyncLogger.setOverflowCallback(onOverflow);
asyncLogger.setFlushCallback(onFlush);
asyncLogger.setFullCallback(onFull);
asyncLogger.setEmptyCallback(onEmpty);
asyncLogger.setWorkerStartCallback(onStart);
asyncLogger.setWorkerStopCallback(onStop);
asyncLogger.setErrorCallback(onError);
```

Available callbacks:
- `on_overflow`: Buffer overflow occurred
- `onFull`: Buffer became full
- `onEmpty`: Buffer became empty
- `onFlush`: Flush operation completed
- `onWorkerStart`: Worker thread started
- `onWorkerStop`: Worker thread stopped (provides uptime)
- `onBatchProcessed`: Batch processed (provides processing time)
- `onLatencyThresholdExceeded`: Latency exceeded threshold
- `onError`: Error occurred during write

## Presets

Use built-in presets for common scenarios:

```zig
// Maximum throughput
const highThroughput = logly.AsyncPresets.highThroughput();

// Minimum latency
const lowLatency = logly.AsyncPresets.lowLatency();

// Balanced (default)
const balanced = logly.AsyncPresets.balanced();

// Never drop messages
const noDrop = logly.AsyncPresets.noDrop();
```

## Blocking vs Non-Blocking

- **Console Sink**: Typically blocking (direct write to stdout/stderr)
- **File Sink**: Non-blocking (buffered) by default
- **AsyncLogger**: Fully non-blocking with background worker

## Auto-Flush vs Async Logging

These two features serve different purposes and are not the same thing:

- **`autoFlush`** controls whether sinks are flushed after every log record (in the synchronous path) or when the async logger processes a batch. When enabled, each log record is written to the underlying sink immediately. This ensures no data loss but adds I/O overhead per record.

- **Async logging** means log records are queued in a ring buffer and processed by background worker threads. Records are batched together before being written to sinks, which improves throughput by reducing the number of I/O operations.

> [!NOTE]
> `autoFlush = true` with async logging means the async worker flushes after each batch, not that your application thread blocks on I/O. The application thread still enqueues to the ring buffer and returns immediately.

## Flushing

### Manual Flush

```zig
// Flush all pending logs
asyncLogger.flush();

// Or for simple sinks
try logger.flush();
```

### Auto-Flush

Auto-flush triggers based on:
- **Time**: After `flushIntervalMs` milliseconds
- **Size**: When batch reaches `batchSize`
- **Shutdown**: Automatically on `stop()` or `deinit()`

## Statistics

Monitor async performance:

```zig
const stats = asyncLogger.getStats();

std.debug.print("Queued: {d}\\n", .{stats.getQueued()});
std.debug.print("Written: {d}\\n", .{stats.getWritten()});
std.debug.print("Dropped: {d}\\n", .{stats.getDropped()});
std.debug.print("Drop rate: {d:.2}%\\n", .{stats.dropRate() * 100});
std.debug.print("Avg latency: {d}ns\\n", .{stats.averageLatencyNs()});
```

## AsyncFileWriter

For optimized file writing:

```zig
var writer = try logly.AsyncFileWriter.init(allocator, .{
    .filePath = "logs/app.log",
    .bufferSize = 64 * 1024, // 64KB
    .flushIntervalMs = 1000,
    .syncOnFlush = false,
});
defer writer.deinit();

try writer.write("Log message\n");
try writer.flush();
```

### FileWriter Options

| Option | Default | Description |
|--------|---------|-------------|
| `filePath` | required | Log file path |
| `bufferSize` | 64KB | Write buffer size |
| `flushIntervalMs` | 1000 | Auto-flush interval |
| `syncOnFlush` | false | fsync on flush |
| `direct_io` | false | Bypass OS cache |
| `append` | true | Append to existing file |

## Best Practices

### 1. Choose Appropriate Buffer Size

```zig
// High volume: larger buffers
.bufferSize = 65536

// Low latency: smaller buffers
.bufferSize = 1024
```

### 2. Monitor Drop Rate

```zig
if (stats.dropRate() > 0.01) { // > 1% drops
    // Consider larger buffer or faster flush
}
```

### 3. Graceful Shutdown

```zig
// Always stop properly to flush pending logs
defer asyncLogger.stop();
```

### 4. Handle Backpressure

```zig
// For critical logs, use blocking policy
const critical_config = logly.AsyncLogger.AsyncConfig{
    .overflowPolicy = .block,
};
```

## Performance Tips

1. **Use batch writing**: Larger batches = fewer I/O operations
2. **Tune flush interval**: Balance latency vs throughput
3. **Size the queue for the load**: Larger queues absorb bursts but increase memory use
4. **Measure sink cost**: Slow sinks become the limiting factor once the queue is full

## Example: High-Throughput Setup

```zig
var asyncLogger = try logly.AsyncLogger.initWithConfig(allocator, .{
    .bufferSize = 65536,
    .flushIntervalMs = 500,
    .batchSize = 256,
    .overflowPolicy = .dropOldest,
});
```

## Example: Low-Latency Setup

```zig
var asyncLogger = try logly.AsyncLogger.initWithConfig(allocator, .{
    .bufferSize = 1024,
    .flushIntervalMs = 10,
    .batchSize = 16,
    .overflowPolicy = .block,
});
```

## See Also

- [Async API Reference](../api/async.md)
- [Thread Pool Guide](thread-pool.md)
- [Configuration Guide](configuration.md)

## Lifecycle & State

```zig
var asyncLogger = try logly.AsyncLogger.initWithConfig(allocator, config);
defer asyncLogger.deinit();

// State methods
const running = asyncLogger.isRunning();
const capacity = asyncLogger.bufferCapacity();
const full = asyncLogger.isFull();
const depth = asyncLogger.queueDepth();
const empty = asyncLogger.isQueueEmpty();

// Reset statistics
asyncLogger.resetStats();
```
