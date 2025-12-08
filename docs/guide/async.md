# Async Logging

Logly provides comprehensive asynchronous logging capabilities to ensure that logging operations do not block your application's main execution flow. This is particularly important for high-performance applications.

## Overview

Logly offers multiple async logging options:

1. **Simple Async Sinks**: Basic buffered file writing
2. **AsyncLogger**: Full-featured async logger with ring buffers
3. **AsyncFileWriter**: Optimized async file writing

## Quick Start

### Simple Async Sinks

The simplest way to use async logging:

```zig
_ = try logger.add(.{  // Short alias for addSink()
    .path = "logs/app.log",
    .async_write = true,      // Enable async (default)
    .buffer_size = 8192,      // Buffer size in bytes (default 8KB)
});
```

### Full AsyncLogger

For more control, use the AsyncLogger directly:

```zig
const logly = @import("logly");

var async_logger = try logly.AsyncLogger.init(allocator, .{
    .buffer_size = 8192,
    .flush_interval_ms = 100,
    .batch_size = 64,
});
defer async_logger.deinit();

try async_logger.start();
defer async_logger.stop();
```

## Parallel Logging (Thread Pool)

For high-throughput scenarios requiring heavy processing (e.g., complex formatting, compression, or multiple slow sinks), Logly supports parallel logging using a work-stealing thread pool.

### Enabling Parallel Logging

```zig
var config = logly.Config.default();
config.thread_pool = .{
    .enabled = true,
    .thread_count = 0, // 0 = auto-detect based on CPU cores
    .queue_size = 10000,
    .work_stealing = true,
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

1. **Queuing**: Messages are added to a lock-free ring buffer
2. **Background Processing**: A worker thread processes queued messages
3. **Batch Writing**: Messages are written in batches for efficiency
4. **Flushing**: Buffers are flushed based on time or size

## Configuration

### Logger Configuration

Enable async logging through the Config struct:

```zig
const logly = @import("logly");

var config = logly.Config.default();
config.async_config = .{
    .enabled = true,              // Enable async logging
    .buffer_size = 8192,          // Ring buffer size
    .batch_size = 100,            // Messages per batch
    .flush_interval_ms = 100,     // Auto-flush interval
    .overflow_policy = .drop_oldest, // On buffer overflow
    .auto_start = true,           // Auto-start worker thread
};

// Or use helper method
var config2 = logly.Config.default().withAsync();
```

### Basic Configuration

```zig
const config = logly.AsyncLogger.AsyncConfig{
    .buffer_size = 8192,        // Ring buffer size
    .flush_interval_ms = 100,   // Auto-flush interval
    .batch_size = 64,           // Messages per batch
    .overflow_policy = .drop_oldest,
    .background_worker = true,
    .enable_metrics = true,
};
```

### Configuration Options

| Option | Default | Description |
|--------|---------|-------------|
| `buffer_size` | 8192 | Ring buffer capacity |
| `flush_interval_ms` | 100 | Auto-flush interval in ms |
| `batch_size` | 64 | Messages written per batch |
| `overflow_policy` | `.drop_oldest` | Behavior when buffer full |
| `background_worker` | true | Enable background thread |
| `shutdown_timeout_ms` | 5000 | Graceful shutdown timeout |
| `max_message_size` | 4096 | Maximum message size |

## Overflow Policies

Control what happens when the buffer is full:

```zig
pub const OverflowPolicy = enum {
    drop_oldest,  // Remove oldest to make room (default)
    drop_newest,  // Drop new messages
    block,        // Block until space available
    expand,       // Grow buffer dynamically
};
```

### Choosing a Policy

- **`drop_oldest`**: Best for most applications, ensures recent logs
- **`drop_newest`**: Use when historical logs are more important
- **`block`**: When you can't afford to lose any logs
- **`expand`**: For bursty workloads with variable volume

## Presets

Use built-in presets for common scenarios:

```zig
// Maximum throughput
const high_throughput = logly.AsyncPresets.highThroughput();

// Minimum latency
const low_latency = logly.AsyncPresets.lowLatency();

// Balanced (default)
const balanced = logly.AsyncPresets.balanced();

// Never drop messages
const no_drop = logly.AsyncPresets.noDrop();
```

## Blocking vs Non-Blocking

- **Console Sink**: Typically blocking (direct write to stdout/stderr)
- **File Sink**: Non-blocking (buffered) by default
- **AsyncLogger**: Fully non-blocking with background worker

## Flushing

### Manual Flush

```zig
// Flush all pending logs
async_logger.flush();

// Or for simple sinks
try logger.flush();
```

### Auto-Flush

Auto-flush triggers based on:
- **Time**: After `flush_interval_ms` milliseconds
- **Size**: When batch reaches `batch_size`
- **Shutdown**: Automatically on `stop()` or `deinit()`

## Statistics

Monitor async performance:

```zig
const stats = async_logger.getStats();

std.debug.print("Queued: {d}\n", .{stats.records_queued.load(.monotonic)});
std.debug.print("Written: {d}\n", .{stats.records_written.load(.monotonic)});
std.debug.print("Dropped: {d}\n", .{stats.records_dropped.load(.monotonic)});
std.debug.print("Drop rate: {d:.2}%\n", .{stats.dropRate() * 100});
std.debug.print("Avg latency: {d}ns\n", .{stats.averageLatencyNs()});
```

## AsyncFileWriter

For optimized file writing:

```zig
var writer = try logly.AsyncFileWriter.init(allocator, .{
    .file_path = "logs/app.log",
    .buffer_size = 64 * 1024, // 64KB
    .flush_interval_ms = 1000,
    .sync_on_flush = false,
});
defer writer.deinit();

try writer.write("Log message\n");
try writer.flush();
```

### FileWriter Options

| Option | Default | Description |
|--------|---------|-------------|
| `file_path` | required | Log file path |
| `buffer_size` | 64KB | Write buffer size |
| `flush_interval_ms` | 1000 | Auto-flush interval |
| `sync_on_flush` | false | fsync on flush |
| `direct_io` | false | Bypass OS cache |
| `append` | true | Append to existing file |

## Best Practices

### 1. Choose Appropriate Buffer Size

```zig
// High volume: larger buffers
.buffer_size = 65536

// Low latency: smaller buffers
.buffer_size = 1024
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
defer async_logger.stop();
```

### 4. Handle Backpressure

```zig
// For critical logs, use blocking policy
const critical_config = logly.AsyncLogger.AsyncConfig{
    .overflow_policy = .block,
};
```

## Performance Tips

1. **Use batch writing**: Larger batches = fewer I/O operations
2. **Tune flush interval**: Balance latency vs throughput
3. **Pre-allocate buffers**: Set `preallocate_buffers = true`
4. **Use direct I/O**: For very high throughput (with caution)

## Example: High-Throughput Setup

```zig
var async_logger = try logly.AsyncLogger.init(allocator, .{
    .buffer_size = 65536,
    .flush_interval_ms = 500,
    .batch_size = 256,
    .overflow_policy = .drop_oldest,
    .preallocate_buffers = true,
});
```

## Example: Low-Latency Setup

```zig
var async_logger = try logly.AsyncLogger.init(allocator, .{
    .buffer_size = 1024,
    .flush_interval_ms = 10,
    .batch_size = 16,
    .overflow_policy = .block,
});
```

## See Also

- [Async API Reference](../api/async.md)
- [Thread Pool Guide](thread-pool.md)
- [Configuration Guide](configuration.md)
