# Compression Guide

This guide covers log compression in Logly, including automatic and manual compression, configuration options, and best practices.

## Overview

Logly provides a compression module using DEFLATE-style compression that achieves good compression ratios for log data. The compression module includes CRC32 checksums for data integrity verification.

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
var config2 = logly.Config.default().withCompression();
```

## Compression Algorithms

| Algorithm | Description |
|-----------|-------------|
| `.none` | No compression |
| `.deflate` | Standard DEFLATE (gzip compatible) |
| `.zlib` | ZLIB compression with headers |
| `.raw_deflate` | Raw DEFLATE without headers |

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

Control when compression happens:

### Manual Mode

Compress explicitly when you want:

```zig
var compression = logly.Compression.init(allocator, .{});

// Manually compress when ready
const compressed = try compression.compress(data);
const decompressed = try compression.decompress(compressed);
```

### On Rotation

Compress when log files are rotated:

```zig
var config = logly.Config.default();
config.rotation = .{
    .enabled = true,
    .compress_rotated = true,
};
```

### Size Threshold

Compress when files reach a certain size:

```zig
config.compression.chunk_size = 10 * 1024 * 1024; // 10 MB chunks
```

### Scheduled

Use with the scheduler for timed compression:

```zig
var compression = logly.Compression.init(allocator, .{
    .mode = .scheduled,
});

// Add to scheduler
_ = try scheduler.addTask(.{
    .name = "compress_logs",
    .task_type = .compression,
    .schedule = logly.Schedule.everyHours(1),
    .config = .{ .compression = .{
        .path = "logs",
        .min_age_days = 1,
    }},
});
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

## Statistics

Monitor compression performance:

```zig
const stats = compression.stats;

std.debug.print("Files compressed: {d}\n", .{
    stats.files_compressed.load(.monotonic),
});
std.debug.print("Bytes saved: {d}\n", .{
    stats.bytes_before.load(.monotonic) - stats.bytes_after.load(.monotonic),
});
std.debug.print("Compression ratio: {d:.2}%\n", .{
    compression.getCompressionRatio() * 100,
});
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

### 1. Choose the Right Algorithm

```zig
// For production with high throughput
.algorithm = .lz4

// For archival
.algorithm = .zstd

// For compatibility
.algorithm = .gzip
```

### 2. Set Appropriate Thresholds

```zig
// Don't compress small files
.size_threshold = 1024 * 1024 // 1 MB minimum
```

### 3. Monitor Compression Ratio

If the ratio is poor (> 90%), the data might already be compressed or incompressible.

### 4. Use Concurrent Compression

For many files, enable parallel compression:

```zig
.max_concurrent = std.Thread.getCpuCount() catch 4
```

### 5. Consider I/O Impact

Compression uses CPU but saves I/O. Balance based on your system:

```zig
// I/O bound system - use better compression
.level = .best

// CPU bound system - use faster compression
.level = .fast
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

## Example: Production Setup

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Production config with compression enabled
    var config = logly.Config.production(); // Includes compression

    // Or customize compression settings
    var custom_config = logly.Config.default().withCompression(.{
        .algorithm = .lz77_rle,
        .level = 6,
        .window_size = 32768,
        .enable_checksums = true,
    });

    var logger = try logly.Logger.initWithConfig(allocator, config);
    defer logger.deinit();

    // Direct compression usage
    var compression = logly.Compression.init(allocator, .{});
    defer compression.deinit();

    const data = "Application log data..." ** 100;
    const compressed = try compression.compress(data);
    defer allocator.free(compressed);

    // Verify integrity
    const decompressed = try compression.decompress(compressed);
    defer allocator.free(decompressed);

    const ratio = @as(f64, @floatFromInt(compressed.len)) / @as(f64, @floatFromInt(data.len)) * 100;
    std.debug.print("Compression ratio: {d:.1}%\n", .{ratio});
    std.debug.print("Data verified: {}\n", .{std.mem.eql(u8, data, decompressed)});
}
```

## See Also

- [Compression API Reference](../api/compression.md)
- [Rotation Guide](rotation.md)
- [Configuration Guide](configuration.md)
