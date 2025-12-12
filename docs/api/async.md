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
config.async_config = .{
    .enabled = true,
    .buffer_size = 16384,
    .batch_size = 128,
    .flush_interval_ms = 50,
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
    worker_thread: ?std.Thread,
    sinks: std.ArrayList(*Sink),
};
```

### AsyncConfig

Configuration available through `Config.AsyncConfig`:

```zig
pub const AsyncConfig = struct {
    /// Enable async logging.
    enabled: bool = false,
    /// Buffer size for async queue.
    buffer_size: usize = 8192,
    /// Batch size for flushing.
    batch_size: usize = 100,
    /// Flush interval in milliseconds.
    flush_interval_ms: u64 = 100,
    /// Minimum time between flushes to avoid thrashing.
    min_flush_interval_ms: u64 = 0,
    /// Maximum latency before forcing a flush.
    max_latency_ms: u64 = 5000,
    /// What to do when buffer is full.
    overflow_policy: OverflowPolicy = .drop_oldest,
    /// Auto-start worker thread.
    background_worker: bool = true,

    pub const OverflowPolicy = enum {
        drop_oldest,
        drop_newest,
        block,
    };
};
```

### OverflowPolicy

What to do when the buffer is full.

```zig
pub const OverflowPolicy = enum {
    /// Drop the oldest entries to make room
    drop_oldest,
    /// Drop new entries (block if blocking enabled)
    drop_newest,
    /// Block until space is available
    block,
    /// Expand buffer dynamically
    expand,
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
    records_queued: std.atomic.Value(u64),
    records_written: std.atomic.Value(u64),
    records_dropped: std.atomic.Value(u64),
    flush_count: std.atomic.Value(u64),
    total_latency_ns: std.atomic.Value(u64),
    max_latency_ns: std.atomic.Value(u64),
    buffer_high_watermark: std.atomic.Value(u64),
};
```

### RingBuffer

Lock-free ring buffer for async message queuing.

```zig
pub const RingBuffer = struct {
    entries: []BufferEntry,
    head: std.atomic.Value(usize),
    tail: std.atomic.Value(usize),
    capacity: usize,
};
```

### AsyncFileWriter

Optimized async file writer with buffering.

```zig
pub const AsyncFileWriter = struct {
    allocator: std.mem.Allocator,
    config: FileWriterConfig,
    write_buffer: []u8,
    buffer_pos: usize,
    stats: FileWriterStats,
    background_thread: ?std.Thread,
};
```

### FileWriterConfig

Configuration for async file writing.

```zig
pub const FileWriterConfig = struct {
    /// Path to the log file
    file_path: []const u8,
    /// Write buffer size
    buffer_size: usize = 64 * 1024, // 64KB
    /// Auto-flush interval in milliseconds
    flush_interval_ms: u64 = 1000,
    /// Sync to disk on flush
    sync_on_flush: bool = false,
    /// Enable direct I/O (bypass OS cache)
    direct_io: bool = false,
    /// Create parent directories if needed
    create_dirs: bool = true,
    /// Append to existing file
    append: bool = true,
};
```

## AsyncLogger Methods

### init

Create a new async logger.

```zig
pub fn init(allocator: std.mem.Allocator, config: AsyncConfig) !AsyncLogger
```

### deinit

Clean up resources and stop worker thread.

```zig
pub fn deinit(self: *AsyncLogger) void
```

### start

Start the background worker thread.

```zig
pub fn start(self: *AsyncLogger) !void
```

### stop

Stop the background worker and flush remaining logs.

```zig
pub fn stop(self: *AsyncLogger) void
```

### log

Queue a log record for async processing.

```zig
pub fn log(self: *AsyncLogger, record: *const Record) !void
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

### getStats

Get current async statistics.

```zig
pub fn getStats(self: *const AsyncLogger) AsyncStats
```

## AsyncStats Methods

### dropRate

Calculate the percentage of dropped records.

```zig
pub fn dropRate(self: *const AsyncStats) f64
```

### averageLatencyNs

Get average latency in nanoseconds.

```zig
pub fn averageLatencyNs(self: *const AsyncStats) u64
```

## AsyncFileWriter Methods

### init

Create a new async file writer.

```zig
pub fn init(allocator: std.mem.Allocator, config: FileWriterConfig) !AsyncFileWriter
```

### deinit

Clean up and close file.

```zig
pub fn deinit(self: *AsyncFileWriter) void
```

### write

Write data to the buffer (async).

```zig
pub fn write(self: *AsyncFileWriter, data: []const u8) !void
```

### flush

Flush buffer to file.

```zig
pub fn flush(self: *AsyncFileWriter) !void
```

## Presets

### highThroughput

Optimized for maximum throughput.

```zig
pub fn highThroughput() AsyncConfig {
    return .{
        .buffer_size = 65536,
        .flush_interval_ms = 500,
        .batch_size = 256,
        .overflow_policy = .drop_oldest,
        .preallocate_buffers = true,
    };
}
```

### lowLatency

Optimized for minimum latency.

```zig
pub fn lowLatency() AsyncConfig {
    return .{
        .buffer_size = 1024,
        .flush_interval_ms = 10,
        .batch_size = 16,
        .overflow_policy = .block,
    };
}
```

### balanced

Balance between throughput and latency.

```zig
pub fn balanced() AsyncConfig {
    return .{
        .buffer_size = 8192,
        .flush_interval_ms = 100,
        .batch_size = 64,
    };
}
```

### noDrop

Never drop messages (may block).

```zig
pub fn noDrop() AsyncConfig {
    return .{
        .buffer_size = 16384,
        .overflow_policy = .block,
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

    // Create async logger with high throughput config
    var async_logger = try logly.AsyncLogger.init(
        allocator,
        logly.AsyncPresets.highThroughput(),
    );
    defer async_logger.deinit();

    // Start the background worker
    try async_logger.start();
    defer async_logger.stop();

    // Log messages (non-blocking)
    for (0..1000) |i| {
        _ = i;
        // async_logger.log(&record);
    }

    // Check statistics
    const stats = async_logger.getStats();
    std.debug.print("Queued: {d}, Written: {d}, Dropped: {d}\n", .{
        stats.records_queued.load(.monotonic),
        stats.records_written.load(.monotonic),
        stats.records_dropped.load(.monotonic),
    });
    std.debug.print("Drop rate: {d:.2}%\n", .{stats.dropRate() * 100});
}
```

## See Also

- [Async Logging Guide](../guide/async.md) - In-depth async logging guide
- [Thread Pool API](thread-pool.md) - Parallel logging
- [Configuration Guide](../guide/configuration.md) - Full configuration options
