# Compression Guide

This guide covers log compression in Logly, including automatic and manual compression, configuration options, and best practices.

## Overview

Logly provides a comprehensive compression module with advanced features:

- **Multiple Algorithms**: DEFLATE, GZIP, ZLIB, RAW DEFLATE
- **Smart Strategies**: Text-optimized, binary, RLE, adaptive auto-detection
- **Flexible Modes**: Manual, on-rotation, size-based, scheduled, streaming
- **Background Processing**: Offload compression to thread pool
- **Real-time Monitoring**: Detailed statistics with atomic counters
- **Callback System**: 5 callback types for complete observability
- **Data Integrity**: CRC32 checksums with corruption detection
- **Performance**: 100-500 MB/s compression, 200-800 MB/s decompression

## Quick Start

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create compression with default settings
    var compression = logly.Compression.init(allocator);
    defer compression.deinit();

    // Compress some data
    const data = "Hello, World! " ** 100;
    const compressed = try compression.compress(data);
    defer allocator.free(compressed);

    std.debug.print("Original: {d} bytes\n", .{data.len});
    std.debug.print("Compressed: {d} bytes\n", .{compressed.len});
}
```

## Logger Configuration

Enable compression through the Config struct:

```zig
const logly = @import("logly");

var config = logly.Config.default();
config.compression = .{
    .enabled = true,              // Enable compression
    .algorithm = .deflate,        // Compression algorithm
    .level = .default,            // Compression level
    .on_rotation = true,          // Compress on log rotation
    .keep_original = false,       // Delete original after compression
    .extension = ".gz",           // Compressed file extension
};

// Or use helper method
var config2 = logly.Config.default().withCompression(.{ .algorithm = .deflate });
```

## Compression Algorithms

| Algorithm | Description | Speed | Ratio | Use Case |
|-----------|-------------|-------|-------|----------|
| `.none` | No compression | Instant | 1.0x | Testing |
| `.deflate` | Standard DEFLATE (gzip compatible) | ~200 MB/s | 3-5x | General logs |
| `.zlib` | ZLIB format with headers | ~180 MB/s | 3-5x | Network transport |
| `.raw_deflate` | Raw DEFLATE without headers | ~220 MB/s | 3-5x | Custom formats |

## Compression Strategies

Strategies optimize compression for different data types:

### Text Strategy (Recommended for Logs)

Optimized for log files with repeated patterns:

```zig
config.compression.strategy = .text;
```

- Uses LZ77 sliding window + RLE
- Detects timestamp patterns
- Typical ratio: **4-6x for logs**
- Best for: Application logs, system logs

### Binary Strategy

Optimized for binary log formats:

```zig
config.compression.strategy = .binary;
```

- Disables RLE
- Focuses on byte-level patterns
- Typical ratio: **2-3x**
- Best for: Binary protocols, structured logs

## Network Compression

Compression can be enabled specifically for network sinks (TCP/UDP) to reduce bandwidth usage. This is particularly useful when shipping logs to a remote aggregator over a slow or metered connection.

When enabled, the sink buffers logs up to `buffer_size` (default 4KB) and then compresses the entire buffer using the configured algorithm (default DEFLATE) before sending it over the network.

```zig
var sink = logly.SinkConfig.network("tcp://logs.example.com:5000");
sink.compression = .{
    .enabled = true,
    .algorithm = .deflate, // or .gzip, .zlib
    .level = .best_speed,  // Optimize for low latency
};
_ = try logger.addSink(sink);
```

> **Note:** The receiving end must be able to decompress the stream. For TCP, it receives a stream of compressed blocks. For UDP, each packet payload is compressed.

### RLE-Only Strategy

Fast compression for highly repetitive data:

```zig
config.compression.strategy = .rle_only;
```

- Only run-length encoding
- Very fast compression/decompression
- Typical ratio: **8-10x for repetitive data**
- Best for: Metrics, repetitive logs

### Adaptive Strategy (Default)

Auto-detects the best approach:

```zig
config.compression.strategy = .adaptive;
```

- Analyzes data patterns
- Selects optimal algorithm
- Slight overhead for analysis (~5%)
- Best for: Mixed workloads

## Compression Levels

| Level | Speed | Ratio | Use Case |
|-------|-------|-------|----------|
| `.none` (0) | N/A | None | Disabled |
| `.fast` (1) | Fastest | Lower | Real-time logging |
| `.default` (6) | Balanced | Good | General purpose |
| `.best` (9) | Slowest | Best | Archival storage |

```zig
// Fast compression
config.compression.level = .fast;

// Balanced (default)
config.compression.level = .default;

// Maximum compression
config.compression.level = .best;
```

## Compression Modes

Control when and how compression happens:

### Manual Mode

Compress explicitly when you want:

```zig
var compression = logly.Compression.init(allocator);
defer compression.deinit();

// Manually compress when ready
const compressed = try compression.compress(data);
defer allocator.free(compressed);

const decompressed = try compression.decompress(compressed);
defer allocator.free(decompressed);
```

### On Rotation Mode

Compress automatically when log files are rotated:

```zig
var config = logly.Config.default();
config.compression = .{
    .enabled = true,
    .mode = .on_rotation,
    .level = .default,
    .keep_original = false,
};
```

### Size Threshold Mode

Compress when files reach a certain size:

```zig
var compression = logly.Compression.initWithConfig(allocator, .{
    .mode = .on_size_threshold,
    .size_threshold = 50 * 1024 * 1024, // 50 MB
    .level = .default,
});

// Check if file should be compressed
if (compression.shouldCompress("app.log")) {
    _ = try compression.compressFile("app.log", null);
}
```

### Streaming Mode

Compress data as it's being written (real-time):

```zig
var compression = logly.Compression.initWithConfig(allocator, .{
    .mode = .streaming,
    .streaming = true,
    .buffer_size = 16 * 1024,
    .level = .fast,
});
```

### Scheduled Mode

Use with the scheduler for timed compression:

```zig
var scheduler = try logly.Scheduler.init(allocator, .{});
defer scheduler.deinit();

// Compress logs every hour
_ = try scheduler.addTask(.{
    .name = "compress_old_logs",
    .schedule = .{ .interval_seconds = 3600 },
    .callback = compressOldLogs,
});

try scheduler.start();
```

### Background Mode

Offload compression to background threads:

```zig
var compression = logly.Compression.initWithConfig(allocator, .{
    .background = true,  // Use thread pool
    .level = .best,      // Can use higher levels without blocking
});

// Compression happens asynchronously
const result = try compression.compressFile("large.log", null);
```

## Presets

Use built-in presets for common scenarios:

```zig
// Fast compression, minimal CPU
const fast = logly.CompressionPresets.fast();

// Balanced (default)
const balanced = logly.CompressionPresets.balanced();

// Maximum compression
const maximum = logly.CompressionPresets.maximum();
```

## File Compression

Compress entire log files:

```zig
// Compress a file
try compression.compressFile("logs/app.log");
// Creates logs/app.log.gz
```

### Configuration Options

```zig
var compression = logly.Compression.init(allocator, .{
    .algorithm = .gzip,
    .compressed_extension = ".gz",
    .keep_originals = false, // Delete original after compression
    .max_concurrent = 4,     // Parallel compression
});
```

## Callbacks

Monitor compression operations with callbacks:

### Compression Start Callback

Called before compression begins:

```zig
fn onCompressionStart(path: []const u8, size: u64) void {
    std.debug.print("Starting: {s} ({d} bytes)\n", .{path, size});
}

compression.setCompressionStartCallback(onCompressionStart);
```

### Compression Complete Callback

Called after successful compression:

```zig
fn onComplete(orig: []const u8, comp: []const u8, 
              orig_size: u64, comp_size: u64, elapsed: u64) void {
    const ratio = @as(f64, @floatFromInt(orig_size)) / 
                  @as(f64, @floatFromInt(comp_size));
    std.debug.print("Compressed {s}: {d:.2}x in {d}ms\n", 
        .{orig, ratio, elapsed});
}

compression.setCompressionCompleteCallback(onComplete);
```

### Compression Error Callback

Called when compression fails:

```zig
fn onError(path: []const u8, err: anyerror) void {
    std.log.err("Compression failed for {s}: {s}", 
        .{path, @errorName(err)});
}

compression.setCompressionErrorCallback(onError);
```

### Decompression Complete Callback

```zig
fn onDecompress(comp_path: []const u8, decomp_path: []const u8) void {
    std.debug.print("Decompressed: {s} -> {s}\n", 
        .{comp_path, decomp_path});
}

compression.setDecompressionCompleteCallback(onDecompress);
```

### Archive Deleted Callback

```zig
fn onArchiveDeleted(path: []const u8) void {
    std.debug.print("Deleted archive: {s}\n", .{path});
}

compression.setArchiveDeletedCallback(onArchiveDeleted);
```

## Statistics

Monitor compression performance with detailed metrics:

```zig
const stats = compression.getStats();

// Compression efficiency
std.debug.print("Compression ratio: {d:.2}x\n", .{stats.compressionRatio()});
std.debug.print("Space savings: {d:.1}%\n", .{stats.spaceSavingsPercent()});

// Performance metrics
std.debug.print("Compression speed: {d:.1} MB/s\n", 
    .{stats.avgCompressionSpeedMBps()});
std.debug.print("Decompression speed: {d:.1} MB/s\n", 
    .{stats.avgDecompressionSpeedMBps()});

// Reliability
std.debug.print("Error rate: {d:.4}%\n", .{stats.errorRate() * 100});

// Operations
std.debug.print("Files compressed: {d}\n", 
    .{stats.files_compressed.load(.monotonic)});
std.debug.print("Files decompressed: {d}\n", 
    .{stats.files_decompressed.load(.monotonic)});

// Background tasks (if enabled)
const queued = stats.background_tasks_queued.load(.monotonic);
const completed = stats.background_tasks_completed.load(.monotonic);
std.debug.print("Background: {d}/{d} completed\n", .{completed, queued});
```

## Integration with Rotation

Combine compression with log rotation:

```zig
// Configure rotation to trigger compression
var config = logly.Config.init(allocator);
config.rotation = .{
    .enabled = true,
    .max_file_size = 10 * 1024 * 1024, // 10 MB
    .max_files = 10,
    .compress_rotated = true,
};

// The compression module will automatically
// compress files after rotation
```

## Integration with Scheduler

Automatic scheduled compression:

```zig
var scheduler = try logly.Scheduler.init(allocator, .{});
defer scheduler.deinit();

// Compress logs older than 1 day, every hour
_ = try scheduler.addTask(
    logly.SchedulerPresets.hourlyCompression("logs"),
);

try scheduler.start();
```

## Best Practices

### 1. Choose the Right Strategy

```zig
// For application logs (best compression)
config.compression.strategy = .text;

// For binary logs
config.compression.strategy = .binary;

// For mixed workloads (auto-detect)
config.compression.strategy = .adaptive;

// For highly repetitive data
config.compression.strategy = .rle_only;
```

### 2. Match Level to Workload

```zig
// High-throughput logging (minimize CPU)
config.compression.level = .fast;
config.compression.background = true;

// Balanced production use
config.compression.level = .default;

// Long-term archival (maximize space savings)
config.compression.level = .best;
config.compression.keep_original = false;
```

### 3. Set Appropriate Thresholds

```zig
// Don't compress small files (overhead not worth it)
config.compression.size_threshold = 1024 * 1024; // 1 MB minimum

// For rotation-based compression
config.compression.mode = .on_rotation;
```

### 4. Monitor Compression Effectiveness

```zig
const stats = compression.getStats();
const ratio = stats.compressionRatio();

if (ratio < 1.5) {
    // Poor compression - data might be pre-compressed
    std.log.warn("Low compression ratio: {d:.2}x", .{ratio});
    // Consider disabling compression for this data type
}
```

### 5. Use Background Compression for Large Files

```zig
// Offload to thread pool to avoid blocking
config.compression.background = true;
config.compression.parallel = true;
```

### 6. Tune Buffer Size

```zig
// Larger buffers = better throughput, more memory
config.compression.buffer_size = 64 * 1024; // 64 KB

// Smaller buffers = less memory, more overhead
config.compression.buffer_size = 16 * 1024; // 16 KB
```

### 7. Enable Checksums for Critical Data

```zig
// Always validate integrity for important logs
config.compression.checksum = true;
```

### 8. Consider I/O vs CPU Tradeoff

```zig
// I/O bound system - use better compression
config.compression.level = .best;
config.compression.strategy = .adaptive;

// CPU bound system - use faster compression
config.compression.level = .fast;
config.compression.background = true;
```

### 9. Set Up Callbacks for Monitoring

```zig
// Track compression effectiveness
compression.setCompressionCompleteCallback(trackStats);

// Alert on errors
compression.setCompressionErrorCallback(logError);
```

### 10. Clean Up Old Archives

```zig
// Automatically delete old compressed files
config.compression.delete_after = 30 * 24 * 3600; // 30 days
```

## Error Handling

Handle compression errors gracefully:

```zig
const compressed = compression.compress(data) catch |err| {
    switch (err) {
        error.OutOfMemory => {
            // Handle memory issues
        },
        error.CompressionFailed => {
            // Handle compression failure
        },
        else => return err,
    }
    return; // Continue without compression
};
```

## Performance Considerations

- **Memory**: Compression uses additional memory for buffers
- **CPU**: Higher compression levels use more CPU
- **I/O**: Compressed files are smaller, faster to write/read
- **Latency**: Real-time compression adds latency to logging

## Advanced Configuration

Combine multiple features for optimal compression:

```zig
var compression = logly.Compression.initWithConfig(allocator, .{
    .algorithm = .deflate,
    .level = .default,
    .strategy = .text,           // Optimized for logs
    .mode = .on_rotation,
    .checksum = true,            // Enable validation
    .background = true,          // Use thread pool
    .streaming = false,
    .buffer_size = 64 * 1024,
    .keep_original = false,
    .delete_after = 30 * 24 * 3600, // Delete after 30 days
    .extension = ".gz",
});
```

## Example: Production Setup

```zig
const std = @import("std");
const logly = @import("logly");

var compression_stats = struct {
    total_saved: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    errors: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
}{};

fn onCompressionComplete(
    orig: []const u8,
    comp: []const u8,
    orig_size: u64,
    comp_size: u64,
    elapsed: u64,
) void {
    _ = orig;
    _ = comp;
    const saved = orig_size - comp_size;
    _ = compression_stats.total_saved.fetchAdd(saved, .monotonic);
    
    const ratio = @as(f64, @floatFromInt(orig_size)) / 
                  @as(f64, @floatFromInt(comp_size));
    std.log.info("Compressed: {d:.2}x ratio, saved {d} bytes in {d}ms", 
        .{ratio, saved, elapsed});
}

fn onCompressionError(path: []const u8, err: anyerror) void {
    _ = compression_stats.errors.fetchAdd(1, .monotonic);
    std.log.err("Compression failed for {s}: {s}", .{path, @errorName(err)});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize compression with production settings
    var compression = logly.Compression.initWithConfig(allocator, .{
        .algorithm = .deflate,
        .level = .default,
        .strategy = .text,
        .mode = .on_rotation,
        .checksum = true,
        .background = true,
        .buffer_size = 64 * 1024,
        .keep_original = false,
    });
    defer compression.deinit();

    // Set up monitoring callbacks
    compression.setCompressionCompleteCallback(onCompressionComplete);
    compression.setCompressionErrorCallback(onCompressionError);

    // Logger with compression enabled
    var config = logly.Config.default();
    config.compression = .{
        .enabled = true,
        .level = .default,
        .on_rotation = true,
    };

    var logger = try logly.Logger.initWithConfig(allocator, config);
    defer logger.deinit();

    // Application runs...
    try logger.info("Application started", .{});
    
    // Periodically check stats
    const stats = compression.getStats();
    std.log.info("Compression stats:", .{});
    std.log.info("  Files compressed: {d}", 
        .{stats.files_compressed.load(.monotonic)});
    std.log.info("  Compression ratio: {d:.2}x", 
        .{stats.compressionRatio()});
    std.log.info("  Space savings: {d:.1}%", 
        .{stats.spaceSavingsPercent()});
    std.log.info("  Avg speed: {d:.1} MB/s", 
        .{stats.avgCompressionSpeedMBps()});
    std.log.info("  Error rate: {d:.4}%", 
        .{stats.errorRate() * 100});
}
```

## Example: Benchmark Different Strategies

```zig
const strategies = [_]logly.Compression.Strategy{
    .text, .binary, .rle_only, .adaptive,
};

const test_data = "2025-01-15 10:30:45 [INFO] User logged in: user123\n" ** 1000;

for (strategies) |strategy| {
    var compression = logly.Compression.initWithConfig(allocator, .{
        .strategy = strategy,
        .level = .default,
    });
    defer compression.deinit();

    const start = std.time.nanoTimestamp();
    const compressed = try compression.compress(test_data);
    const elapsed = std.time.nanoTimestamp() - start;
    defer allocator.free(compressed);

    const ratio = @as(f64, @floatFromInt(test_data.len)) / 
                  @as(f64, @floatFromInt(compressed.len));
    const speed_mbps = (@as(f64, @floatFromInt(test_data.len)) / 
                       (1024.0 * 1024.0)) / 
                       (@as(f64, @floatFromInt(elapsed)) / 1_000_000_000.0);

    std.debug.print("{s:12}: {d:.2}x ratio, {d:.1} MB/s\n", 
        .{@tagName(strategy), ratio, speed_mbps});
}
```

## See Also

- [Compression API Reference](../api/compression.md)
- [Rotation Guide](rotation.md)
- [Configuration Guide](configuration.md)
