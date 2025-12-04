# Compression API

The compression module provides real LZ77 + RLE compression for log files with CRC32 checksums for data integrity.

## Overview

```zig
const logly = @import("logly");
const Compression = logly.Compression;
const CompressionPresets = logly.CompressionPresets;
```

## Centralized Configuration

Compression can be configured through the central `Config` struct:

```zig
var config = logly.Config.default();
config.compression = .{
    .enabled = true,
    .level = .default,
    .on_rotation = true,
};
const logger = try logly.Logger.initWithConfig(allocator, config);
```

## Types

### Compression

The main compression struct that handles all compression operations using LZ77 sliding window + RLE algorithms.

```zig
pub const Compression = struct {
    allocator: std.mem.Allocator,
    config: CompressionConfig,
    stats: CompressionStats,
    mutex: std.Thread.Mutex,
};
```

### CompressionConfig

Configuration for compression behavior.

```zig
pub const CompressionConfig = struct {
    /// Compression algorithm to use
    algorithm: Algorithm = .deflate,
    /// Compression level
    level: Level = .default,
    /// When to trigger compression
    mode: Mode = .on_rotation,
    /// Size threshold in bytes for on_size_threshold mode
    size_threshold: u64 = 10 * 1024 * 1024, // 10MB default
    /// File extension for compressed files
    extension: []const u8 = ".gz",
    /// Keep original file after compression
    keep_original: bool = false,
    /// Delete files older than this after compression (seconds, 0 = never)
    delete_after: u64 = 0,
    /// Buffer size for compression operations
    buffer_size: usize = 32 * 1024, // 32KB
    /// Enable checksum validation
    checksum: bool = true,
};
```

### Algorithm

Available compression algorithms.

```zig
pub const Algorithm = enum {
    /// No compression
    none,
    /// DEFLATE compression (gzip compatible) - LZ77 + RLE
    deflate,
    /// ZLIB compression
    zlib,
    /// Raw DEFLATE without headers
    raw_deflate,
};
```

### Level

Compression levels balancing speed vs ratio.

```zig
pub const Level = enum(u4) {
    /// No compression, fastest
    none = 0,
    /// Best speed, larger files
    fast = 1,
    /// Balanced speed and size
    default = 6,
    /// Maximum compression, slower
    best = 9,
};
```

### Mode

When compression should be triggered.

```zig
pub const Mode = enum {
    /// No automatic compression
    disabled,
    /// Compress on file rotation
    on_rotation,
    /// Compress when file reaches size threshold
    on_size_threshold,
    /// Compress on schedule (e.g., daily)
    scheduled,
    /// Always compress output (streaming compression)
    streaming,
};
```

### CompressionStats

Statistics for compression operations.

```zig
pub const CompressionStats = struct {
    files_compressed: u64,
    files_decompressed: u64,
    bytes_before: u64,
    bytes_after: u64,
    total_time_ns: u64,
    errors: u64,

    /// Calculate compression ratio (0.0 to 1.0)
    pub fn compressionRatio(self: *const CompressionStats) f64;
};
```

### CompressionResult

Result of a file compression operation.

```zig
pub const CompressionResult = struct {
    success: bool,
    original_size: u64,
    compressed_size: u64,
    output_path: ?[]const u8,
    error_message: ?[]const u8,
};
```

## Methods

### init

Create a new compression instance with default configuration.

```zig
pub fn init(allocator: std.mem.Allocator) Compression
```

### initWithConfig

Create a new compression instance with custom configuration.

```zig
pub fn initWithConfig(allocator: std.mem.Allocator, config: CompressionConfig) Compression
```

### deinit

Clean up resources.

```zig
pub fn deinit(self: *Compression) void
```

### compress

Compress data in memory using LZ77 + RLE algorithm with CRC32 checksum.

```zig
pub fn compress(self: *Compression, data: []const u8) ![]u8
```

**Parameters:**
- `data`: Raw data to compress

**Returns:** Compressed data with header and checksum (caller owns memory)

### decompress

Decompress previously compressed data with checksum validation.

```zig
pub fn decompress(self: *Compression, data: []const u8) ![]u8
```

**Parameters:**
- `data`: Compressed data

**Returns:** Decompressed data (caller owns memory)

**Errors:**
- `error.InvalidMagic` - Not valid compressed data
- `error.ChecksumMismatch` - Data corruption detected

### compressFile

Compress a file on disk.

```zig
pub fn compressFile(self: *Compression, input_path: []const u8, output_path: ?[]const u8) !CompressionResult
```

**Parameters:**
- `input_path`: Path to file to compress
- `output_path`: Optional output path (auto-generated if null)

**Returns:** `CompressionResult` with compression details

### getStats

Get current compression statistics.

```zig
pub fn getStats(self: *const Compression) CompressionStats
```

## Presets

### CompressionPresets.fast

Optimized for speed with minimal CPU usage.

```zig
pub fn fast() CompressionConfig {
    return .{
        .algorithm = .deflate,
        .level = .fast,
        .mode = .on_rotation,
        .buffer_size = 64 * 1024,
    };
}
```

### CompressionPresets.balanced

Balance between speed and compression ratio.

```zig
pub fn balanced() CompressionConfig {
    return .{
        .algorithm = .deflate,
        .level = .default,
        .mode = .on_rotation,
    };
}
```

### CompressionPresets.maximum

Maximum compression ratio for archival.

```zig
pub fn maximum() CompressionConfig {
    return .{
        .algorithm = .deflate,
        .level = .best,
        .mode = .on_rotation,
        .keep_original = false,
    };
}
```

### CompressionPresets.archival

Optimized for long-term storage.

```zig
pub fn archival() CompressionConfig {
    return .{
        .algorithm = .deflate,
        .level = .best,
        .mode = .scheduled,
        .checksum = true,
    };
}
```

## Usage Examples

### Basic Compression

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create compression instance
    var comp = logly.Compression.init(allocator);
    defer comp.deinit();

    // Compress data
    const data = "Hello, World! " ** 100;
    const compressed = try comp.compress(data);
    defer allocator.free(compressed);

    std.debug.print("Original: {} bytes\n", .{data.len});
    std.debug.print("Compressed: {} bytes\n", .{compressed.len});

    // Decompress and verify
    const decompressed = try comp.decompress(compressed);
    defer allocator.free(decompressed);

    std.debug.print("Roundtrip: {s}\n", .{
        if (std.mem.eql(u8, data, decompressed)) "OK" else "FAILED"
    });
}
```

### File Compression

```zig
// Compress with custom output path
const result = try comp.compressFile("app.log", "app.log.gz");
if (result.output_path) |path| {
    allocator.free(path);
}

if (result.success) {
    const ratio = 100.0 - (@as(f64, @floatFromInt(result.compressed_size)) / 
                          @as(f64, @floatFromInt(result.original_size)) * 100.0);
    std.debug.print("Saved: {d:.1}%\n", .{ratio});
}
```

### With Centralized Config

```zig
// Enable compression through Config
var config = logly.Config.production();
config.compression = .{
    .enabled = true,
    .level = .best,
    .on_rotation = true,
};

const logger = try logly.Logger.initWithConfig(allocator, config);
defer logger.deinit();

// Compression will be applied automatically on rotation
```

### Compression Levels Comparison

```zig
const test_data = "The quick brown fox jumps over the lazy dog. " ** 50;

inline for ([_]struct { name: []const u8, level: logly.Compression.Level }{
    .{ .name = "None", .level = .none },
    .{ .name = "Fast", .level = .fast },
    .{ .name = "Default", .level = .default },
    .{ .name = "Best", .level = .best },
}) |cfg| {
    var comp = logly.Compression.initWithConfig(allocator, .{ .level = cfg.level });
    defer comp.deinit();

    const compressed = try comp.compress(test_data);
    defer allocator.free(compressed);

    std.debug.print("{s}: {} -> {} bytes\n", .{
        cfg.name, test_data.len, compressed.len
    });
}
```

## Compression Algorithm Details

Logly uses a real LZ77 + RLE compression algorithm:

1. **LZ77 Sliding Window**: Finds repeated patterns and encodes them as (distance, length) pairs
2. **Run-Length Encoding**: Compresses repeated byte sequences  
3. **CRC32 Checksums**: Validates data integrity on decompression

Typical compression ratios:
- Repetitive data (logs): 95-98% space savings
- Text data: 40-60% space savings
- Already compressed data: No benefit

## See Also

- [Compression Guide](../guide/compression.md) - Detailed compression guide
- [Rotation Guide](../guide/rotation.md) - Log rotation with compression
- [Scheduler API](scheduler.md) - Scheduled compression tasks
- [Config API](config.md) - Centralized configuration
