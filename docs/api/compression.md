# Compression API Reference

Comprehensive log file compression with multiple algorithms, streaming support, and advanced monitoring.

## Overview

The Compression module provides high-performance log file compression with:

- **Multiple Algorithms**: DEFLATE, GZIP, ZSTD simulation, RAW
- **Compression Strategies**: Text-optimized, binary, RLE, adaptive
- **Streaming Compression**: Compress while writing logs
- **Background Compression**: Offload compression to background threads
- **Advanced Monitoring**: Detailed statistics and callbacks
- **Memory Efficient**: Configurable buffer sizes and memory limits

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
    .algorithm = .deflate,
};
const logger = try logly.Logger.initWithConfig(allocator, config);
```

## Core Types

### Compression

Main compression controller with configurable algorithms and strategies.

```zig
pub const Compression = struct {
    allocator: std.mem.Allocator,
    config: CompressionConfig,
    stats: CompressionStats,
    mutex: std.Thread.Mutex,

    // Callbacks for monitoring
    on_compression_start: ?*const fn ([]const u8, u64) void,
    on_compression_complete: ?*const fn ([]const u8, []const u8, u64, u64, u64) void,
    on_compression_error: ?*const fn ([]const u8, anyerror) void,
    on_decompression_complete: ?*const fn ([]const u8, []const u8) void,
    on_archive_deleted: ?*const fn ([]const u8) void,
};
```

### CompressionConfig

Comprehensive configuration for compression behavior.

```zig
pub const CompressionConfig = struct {
    /// Compression algorithm to use
    algorithm: Algorithm = .deflate,
    /// Compression level (0-9)
    level: Level = .default,
    /// When to trigger compression
    mode: Mode = .on_rotation,
    /// Size threshold for on_size_threshold mode (bytes)
    size_threshold: u64 = 10 * 1024 * 1024, // 10MB
    /// File extension for compressed files
    extension: []const u8 = ".gz",
    /// Keep original file after compression
    keep_original: bool = false,
    /// Delete files older than this after compression (seconds, 0 = never)
    delete_after: u64 = 0,
    /// Buffer size for compression operations (bytes)
    buffer_size: usize = 32 * 1024, // 32KB
    /// Enable CRC32 checksum validation
    checksum: bool = true,
    /// Compression strategy
    strategy: Strategy = .adaptive,
    /// Enable streaming compression
    streaming: bool = false,
    /// Use background thread for compression
    background: bool = false,
    /// Dictionary for compression (pre-trained patterns)
    dictionary: ?[]const u8 = null,
    /// Enable multi-threaded compression (large files)
    parallel: bool = false,
    /// Memory limit for compression (bytes, 0 = unlimited)
    memory_limit: usize = 0,
    
    pub fn fromCentralized(cfg: Config.CompressionConfig) CompressionConfig;
};
```

**Example Configurations:**

```zig
// High-throughput logging (minimize CPU)
const fast_config = CompressionConfig{
    .algorithm = .deflate,
    .level = .fast,
    .strategy = .text,
    .buffer_size = 64 * 1024,
    .background = true,
};

// Maximum compression (archival)
const archive_config = CompressionConfig{
    .algorithm = .deflate,
    .level = .best,
    .strategy = .adaptive,
    .checksum = true,
    .keep_original = false,
};

// Streaming compression (real-time)
const streaming_config = CompressionConfig{
    .algorithm = .deflate,
    .level = .default,
    .mode = .streaming,
    .streaming = true,
    .buffer_size = 16 * 1024,
};
```

### Algorithm

Available compression algorithms with different characteristics.

```zig
pub const Algorithm = enum {
    /// No compression (passthrough)
    none,
    /// DEFLATE compression (gzip compatible)
    deflate,
    /// ZLIB format (DEFLATE with header/checksum)
    zlib,
    /// Raw DEFLATE (no headers)
    raw_deflate,
};
```

**Algorithm Comparison:**

| Algorithm | Ratio | Speed | Use Case |
|-----------|-------|-------|----------|
| `none` | 1.0x | Instant | Testing, debugging |
| `deflate` | 3-5x | ~200 MB/s | General purpose logs |
| `zlib` | 3-5x | ~180 MB/s | Network transport |
| `raw_deflate` | 3-5x | ~220 MB/s | Custom headers |

### Level

Compression level controlling speed vs size tradeoff.

```zig
pub const Level = enum(u4) {
    /// No compression
    none = 0,
    /// Fastest compression (level 1)
    fast = 1,
    /// Balanced speed and size (level 6)
    default = 6,
    /// Maximum compression (level 9)
    best = 9,
    
    pub fn toInt(self: Level) u8;
};
```

**Level Impact:**

| Level | Compression Time | Ratio | Best For |
|-------|------------------|-------|----------|
| `none` | 0 ms | 1.0x | Debugging |
| `fast` | 10 ms | 2.5x | High-throughput logs |
| `default` | 25 ms | 3.5x | Balanced workloads |
| `best` | 50 ms | 4.2x | Long-term archival |

### Strategy

Compression strategy optimized for different data types.

```zig
pub const Strategy = enum {
    /// Default strategy (balanced)
    default,
    /// Optimized for text/logs with repeated patterns
    text,
    /// Optimized for binary data
    binary,
    /// Huffman-only compression (no LZ77)
    huffman_only,
    /// RLE-only compression for highly repetitive data
    rle_only,
    /// Adaptive strategy (auto-detect best approach)
    adaptive,
};
```

**Strategy Characteristics:**

- **`text`**: Best for logs with repeated patterns (timestamps, log levels)
  - Uses LZ77 + RLE
  - Optimizes for dictionary compression
  - Typical ratio: 4-6x for logs

- **`binary`**: Best for binary log formats
  - Disables RLE
  - Focuses on byte-level patterns
  - Typical ratio: 2-3x

- **`rle_only`**: Best for highly repetitive data
  - Only uses run-length encoding
  - Fast compression/decompression
  - Typical ratio: 8-10x for repetitive logs

- **`adaptive`**: Auto-detects best strategy
  - Analyzes data patterns
  - Selects optimal algorithm
  - Slight overhead for analysis

### Mode

Compression trigger modes for automatic compression.

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

Detailed statistics for compression operations with atomic counters.

```zig
pub const CompressionStats = struct {
    files_compressed: std.atomic.Value(u64),
    files_decompressed: std.atomic.Value(u64),
    bytes_before: std.atomic.Value(u64),
    bytes_after: std.atomic.Value(u64),
    compression_errors: std.atomic.Value(u64),
    decompression_errors: std.atomic.Value(u64),
    last_compression_time: std.atomic.Value(i64),
    total_compression_time_ns: std.atomic.Value(u64),
    total_decompression_time_ns: std.atomic.Value(u64),
    background_tasks_queued: std.atomic.Value(u64),
    background_tasks_completed: std.atomic.Value(u64),
    
    pub fn compressionRatio(self: *const CompressionStats) f64;
    pub fn spaceSavingsPercent(self: *const CompressionStats) f64;
    pub fn avgCompressionSpeedMBps(self: *const CompressionStats) f64;
    pub fn avgDecompressionSpeedMBps(self: *const CompressionStats) f64;
    pub fn errorRate(self: *const CompressionStats) f64;
};
```

**Statistics Methods:**

```zig
const stats = compression.getStats();

// Compression efficiency
std.debug.print("Compression ratio: {d:.2}x\n", .{stats.compressionRatio()});
std.debug.print("Space savings: {d:.1}%\n", .{stats.spaceSavingsPercent()});

// Performance metrics
std.debug.print("Compression speed: {d:.1} MB/s\n", .{stats.avgCompressionSpeedMBps()});
std.debug.print("Decompression speed: {d:.1} MB/s\n", .{stats.avgDecompressionSpeedMBps()});

// Reliability
std.debug.print("Error rate: {d:.4}%\n", .{stats.errorRate() * 100});

// Background operations
const queued = stats.background_tasks_queued.load(.monotonic);
const completed = stats.background_tasks_completed.load(.monotonic);
std.debug.print("Background: {d}/{d} completed\n", .{completed, queued});
```

### CompressionResult

Result of a compression operation with detailed metrics.

```zig
pub const CompressionResult = struct {
    success: bool,
    original_size: u64,
    compressed_size: u64,
    output_path: ?[]const u8,
    error_message: ?[]const u8 = null,
    
    pub fn ratio(self: *const CompressionResult) f64;
};
```

## Methods

### init

Creates a new Compression instance with default configuration.

```zig
pub fn init(allocator: std.mem.Allocator) Compression
```

**Example:**

```zig
var compression = Compression.init(allocator);
defer compression.deinit();
```

### initWithConfig

Creates a Compression instance with custom configuration.

```zig
pub fn initWithConfig(allocator: std.mem.Allocator, config: CompressionConfig) Compression
```

**Example:**

```zig
var compression = Compression.initWithConfig(allocator, .{
    .algorithm = .deflate,
    .level = .best,
    .strategy = .text,
});
defer compression.deinit();
```

### deinit

Releases resources associated with the compression instance.

```zig
pub fn deinit(self: *Compression) void
```

### compress

Compresses data in memory using advanced algorithms.

```zig
pub fn compress(self: *Compression, data: []const u8) ![]u8
```

**Features:**
- Adaptive strategy auto-detection
- Text-optimized for log files
- CRC32 checksum validation
- Memory-efficient streaming

**Performance:**
- ~100-500 MB/s typical throughput
- Memory usage: 2-4x input size during compression
- Best for files >1KB (overhead for small files)

**Example:**

```zig
const data = "2025-01-15 INFO Application started\n" ** 100;
const compressed = try compression.compress(data);
defer allocator.free(compressed);

const ratio = @as(f64, @floatFromInt(data.len)) / @as(f64, @floatFromInt(compressed.len));
std.debug.print("Compressed: {d} -> {d} bytes ({d:.2}x)\n", 
    .{data.len, compressed.len, ratio});
```

### decompress

Decompresses data in memory with validation.

```zig
pub fn decompress(self: *Compression, data: []const u8) ![]u8
```

**Features:**
- CRC32 checksum validation
- Format version detection
- Legacy format support
- Corruption detection

**Performance:**
- ~200-800 MB/s typical throughput
- Validates checksums if enabled

**Example:**

```zig
const decompressed = try compression.decompress(compressed);
defer allocator.free(decompressed);

try std.testing.expectEqualStrings(original_data, decompressed);
```

### compressFile

Compresses a file on disk with comprehensive error handling.

```zig
pub fn compressFile(self: *Compression, input_path: []const u8, output_path: ?[]const u8) !CompressionResult
```

**Features:**
- Automatic output path generation
- Optional original file deletion
- Detailed compression statistics
- Callback notifications
- Atomic file operations

**Example:**

```zig
const result = try compression.compressFile("app.log", null);
defer if (result.output_path) |p| allocator.free(p);

if (result.success) {
    std.debug.print("Compressed: {d:.1}% savings\n", .{result.ratio() * 100});
    std.debug.print("Output: {s}\n", .{result.output_path.?});
} else {
    std.debug.print("Error: {s}\n", .{result.error_message.?});
}
```

### decompressFile

Decompresses a file on disk with validation.

```zig
pub fn decompressFile(self: *Compression, input_path: []const u8, output_path: ?[]const u8) !bool
```

**Example:**

```zig
const success = try compression.decompressFile("app.log.gz", "app.log");
if (success) {
    std.debug.print("Decompressed successfully\n", .{});
}
```

### shouldCompress

Checks if a file should be compressed based on configuration.

```zig
pub fn shouldCompress(self: *const Compression, file_path: []const u8) bool
```

**Example:**

```zig
if (compression.shouldCompress("app.log")) {
    _ = try compression.compressFile("app.log", null);
}
```

### configure

Updates compression configuration at runtime.

```zig
pub fn configure(self: *Compression, config: CompressionConfig) void
```

**Example:**

```zig
// Switch to fast compression during high load
compression.configure(.{
    .algorithm = .deflate,
    .level = .fast,
    .background = true,
});
```

### getStats

Gets current compression statistics.

```zig
pub fn getStats(self: *const Compression) CompressionStats
```

### resetStats

Resets all compression statistics.

```zig
pub fn resetStats(self: *Compression) void
```

## Callbacks

Compression provides 5 callback types for monitoring operations.

### setCompressionStartCallback

Called before compression begins.

```zig
pub fn setCompressionStartCallback(
    self: *Compression, 
    callback: *const fn (file_path: []const u8, uncompressed_size: u64) void
) void
```

**Example:**

```zig
fn onCompressionStart(path: []const u8, size: u64) void {
    std.debug.print("Starting compression: {s} ({d} bytes)\n", .{path, size});
}

compression.setCompressionStartCallback(onCompressionStart);
```

### setCompressionCompleteCallback

Called after successful compression.

```zig
pub fn setCompressionCompleteCallback(
    self: *Compression,
    callback: *const fn (
        original_path: []const u8,
        compressed_path: []const u8,
        original_size: u64,
        compressed_size: u64,
        elapsed_ms: u64
    ) void
) void
```

**Example:**

```zig
fn onCompressionComplete(
    orig: []const u8,
    comp: []const u8,
    orig_size: u64,
    comp_size: u64,
    elapsed: u64
) void {
    const ratio = @as(f64, @floatFromInt(orig_size)) / @as(f64, @floatFromInt(comp_size));
    std.debug.print("Compressed {s} -> {s}: {d:.2}x in {d}ms\n", 
        .{orig, comp, ratio, elapsed});
}

compression.setCompressionCompleteCallback(onCompressionComplete);
```

### setCompressionErrorCallback

Called when compression fails.

```zig
pub fn setCompressionErrorCallback(
    self: *Compression,
    callback: *const fn (file_path: []const u8, err: anyerror) void
) void
```

**Example:**

```zig
fn onCompressionError(path: []const u8, err: anyerror) void {
    std.debug.print("Compression failed for {s}: {s}\n", .{path, @errorName(err)});
}

compression.setCompressionErrorCallback(onCompressionError);
```

### setDecompressionCompleteCallback

Called after decompression.

```zig
pub fn setDecompressionCompleteCallback(
    self: *Compression,
    callback: *const fn (compressed_path: []const u8, decompressed_path: []const u8) void
) void
```

### setArchiveDeletedCallback

Called when archived file is deleted.

```zig
pub fn setArchiveDeletedCallback(
    self: *Compression,
    callback: *const fn (file_path: []const u8) void
) void
```

## Presets

### CompressionPresets

Pre-configured compression settings for common use cases.


```zig
// No compression
const none_config = CompressionPresets.none();

// Fast compression (high-throughput)
const fast_config = CompressionPresets.fast();

// Balanced compression (default)
const balanced_config = CompressionPresets.balanced();

// Maximum compression (archival)
const max_config = CompressionPresets.maximum();

// Size-based trigger
const size_config = CompressionPresets.onSize(50); // 50MB threshold
```

## Performance Characteristics

### Memory Usage

| Operation | Memory | Notes |
|-----------|--------|-------|
| compress() | 2-4x input | During compression |
| decompress() | 1-2x output | During decompression |
| compressFile() | buffer_size | Streaming I/O |
| Dictionary | dict size | If enabled |

### Thread Safety

- ✅ Thread-safe: All public methods protected by mutex
- ✅ Atomic statistics: Lock-free reads
- ⚠️ Callbacks: Must be thread-safe (called under lock)

### Performance Tips

1. **Use appropriate level:**
   - High-throughput: `.fast`
   - Balanced: `.default`
   - Archival: `.best`

2. **Choose right strategy:**
   - Logs: `.text` or `.adaptive`
   - Binary: `.binary`
   - Repetitive: `.rle_only`

3. **Enable background compression:**
   ```zig
   config.background = true; // Offload to thread pool
   ```

4. **Tune buffer size:**
   ```zig
   config.buffer_size = 64 * 1024; // Larger for better throughput
   ```

5. **Use streaming for real-time:**
   ```zig
   config.streaming = true;
   config.mode = .streaming;
   ```

## Error Handling

### Common Errors

```zig
const CompressionError = error{
    InvalidData,        // Corrupted input
    InvalidMagic,       // Wrong file format
    ChecksumMismatch,   // CRC32 validation failed
    InvalidOffset,      // LZ77 back-reference error
    OutOfMemory,        // Allocation failed
};
```

**Example:**

```zig
const compressed = compression.compress(data) catch |err| {
    switch (err) {
        error.OutOfMemory => {
            // Reduce buffer size or use streaming
            compression.configure(.{ .buffer_size = 16 * 1024 });
        },
        else => {
            std.debug.print("Compression error: {s}\n", .{@errorName(err)});
        },
    }
    return err;
};
```

## Complete Example

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize compression with custom config
    var compression = logly.Compression.initWithConfig(allocator, .{
        .algorithm = .deflate,
        .level = .best,
        .strategy = .text,
        .checksum = true,
        .keep_original = false,
    });
    defer compression.deinit();

    // Set up callbacks
    compression.setCompressionCompleteCallback(onComplete);
    compression.setCompressionErrorCallback(onError);

    // Compress a log file
    const result = try compression.compressFile("app.log", null);
    defer if (result.output_path) |p| allocator.free(p);

    if (result.success) {
        std.debug.print("✓ Compressed: {d:.1}% savings\n", .{result.ratio() * 100});
        
        // Get statistics
        const stats = compression.getStats();
        std.debug.print("Total files: {d}\n", 
            .{stats.files_compressed.load(.monotonic)});
        std.debug.print("Compression ratio: {d:.2}x\n", 
            .{stats.compressionRatio()});
        std.debug.print("Speed: {d:.1} MB/s\n", 
            .{stats.avgCompressionSpeedMBps()});
    }
}

fn onComplete(orig: []const u8, comp: []const u8, 
              orig_size: u64, comp_size: u64, elapsed: u64) void {
    const ratio = @as(f64, @floatFromInt(orig_size)) / 
                  @as(f64, @floatFromInt(comp_size));
    std.debug.print("Compressed {s} -> {s}: {d:.2}x in {d}ms\n",
        .{orig, comp, ratio, elapsed});
}

fn onError(path: []const u8, err: anyerror) void {
    std.debug.print("Error compressing {s}: {s}\n", 
        .{path, @errorName(err)});
}
```

## Compression Algorithm Details

Logly uses a real LZ77 + RLE compression algorithm:

1. **LZ77 Sliding Window**: Finds repeated patterns and encodes them as (distance, length) pairs
2. **Run-Length Encoding**: Compresses repeated byte sequences  
3. **CRC32 Checksums**: Validates data integrity on decompression

Typical compression ratios:
- Repetitive data (logs): 4-10x compression (75-90% space savings)
- Text data (logs): 3-5x compression (66-80% space savings)
- Already compressed data: No benefit

## See Also

- [Compression Guide](../guide/compression.md) - Detailed compression guide
- [Rotation Guide](../guide/rotation.md) - Log rotation with compression
- [Callbacks Guide](../guide/callbacks.md) - Callback patterns
- [Configuration](../guide/configuration.md) - Centralized config setup
