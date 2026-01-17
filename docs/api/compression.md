---
title: Compression API Reference
description: API reference for Logly.zig Compression module. DEFLATE, GZIP, ZLIB, ZSTD algorithms with streaming support, background processing, and performance monitoring.
head:
  - - meta
    - name: keywords
      content: compression api, gzip api, zlib api, zstd api, deflate, log compression, streaming compression
  - - meta
    - property: og:title
      content: Compression API Reference | Logly.zig
---

# Compression API Reference

Comprehensive log file compression with multiple algorithms, streaming support, and advanced monitoring.

## Quick Reference: Method Aliases

| Full Method | Alias(es) | Description |
|-------------|-----------|-------------|
| `init()` | `create()` | Initialize compression |
| `deinit()` | `destroy()` | Deinitialize compression |
| `compress()` | `encode()`, `deflate()` | Compress data |
| `decompress()` | `decode()`, `inflate()` | Decompress data |
| `compressFile()` | `packFile()` | Compress a file |
| `decompressFile()` | `unpackFile()` | Decompress a file |
| `compressDirectory()` | `packDirectory()`, `archiveFolder()` | Compress directory (v0.1.5+) |
| `getStats()` | `statistics()` | Get compression statistics |
| `resetStats()` | `clearStats()` | Reset statistics (v0.1.5+) |
| `configure()` | `setConfig()`, `updateConfig()` | Update configuration (v0.1.5+) |
| `shouldCompress()` | `needsCompression()` | Check if file needs compression |
| `zstdCompression()` | `zstdDefault()` | Create zstd compressor (v0.1.5+) |
| `zstdFast()` | `zstdSpeed()` | Create fast zstd compressor (v0.1.5+) |
| `zstdBest()` | `zstdMax()` | Create best zstd compressor (v0.1.5+) |

## Batch Compression Methods (v0.1.5+)

| Method | Description |
|--------|-------------|
| `compressBatch(files)` | Compress multiple files at once |
| `compressPattern(dir, pattern)` | Compress files matching a glob pattern |
| `compressOldest(dir, count)` | Compress N oldest files in directory |
| `compressLargerThan(dir, size)` | Compress files larger than threshold |

## Utility Methods (v0.1.5+)

| Method | Description |
|--------|-------------|
| `estimateCompressedSize(size)` | Estimate compressed size for data |
| `getExtension()` | Get file extension for algorithm |
| `isZstd()` | Check if using zstd algorithm |
| `algorithmName()` | Get algorithm name as string |
| `levelName()` | Get compression level as string |

## Overview

The Compression module provides high-performance log file compression with:

- **Multiple Algorithms**: DEFLATE, GZIP, ZLIB, ZSTD, RAW
- **Compression Strategies**: Text-optimized, binary, RLE, adaptive
- **Streaming Support**: `compressStream` and `decompressStream` helpers
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

Comprehensive configuration for compression behavior. Available as `Config.CompressionConfig`.

```zig
pub const CompressionConfig = struct {
    /// Enable compression.
    enabled: bool = false,
    /// Compression algorithm to use
    algorithm: Algorithm = .deflate,
    /// Compression level (0-9)
    level: Level = .default,
    /// Compress on rotation.
    on_rotation: bool = true,
    /// Keep original file after compression.
    keep_original: bool = false,
    /// When to trigger compression
    mode: Mode = .on_rotation,
    /// Size threshold for on_size_threshold mode (bytes)
    size_threshold: u64 = 10 * 1024 * 1024, // 10MB
    /// Buffer size for streaming compression.
    buffer_size: usize = 32 * 1024,
    /// Compression strategy.
    strategy: Strategy = .default,
    /// File extension for compressed files
    extension: []const u8 = ".gz",
    /// Delete files older than this after compression (seconds, 0 = never)
    delete_after: u64 = 0,
    /// Enable CRC32 checksum validation
    checksum: bool = true,
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
    /// GZIP format (standard compression)
    gzip,
    /// Zstandard compression (high performance)
    zstd,  // v0.1.5+
};
```

## CompressionConfig Preset Methods

The `CompressionConfig` struct provides preset factory methods for minimal configuration:

### Basic Presets

| Method | Description |
|--------|-------------|
| `enable()` | Basic enabled compression with defaults |
| `basic()` | Alias for enable() |
| `disable()` | Explicitly disabled compression |
| `implicit()` | Automatic compression on rotation |
| `explicit()` | Manual compression control |

### Performance Presets

| Method | Description |
|--------|-------------|
| `fast()` | Speed priority (level: fastest) |
| `balanced()` | Default speed/ratio tradeoff |
| `best()` | Ratio priority (level: best, gzip) |

### Mode Presets

| Method | Description |
|--------|-------------|
| `backgroundMode()` | Background thread compression |
| `streamingMode()` | Real-time streaming compression |
| `onSize(bytes)` | Compress when file exceeds size |

### Use Case Presets

| Method | Description |
|--------|-------------|
| `forLogs()` | Optimized for log files (text strategy) |
| `archive()` | Archival mode (best compression, delete original) |
| `keepOriginals()` | Keep original files after compression |
| `production()` | Production-ready (balanced, background, checksums) |
| `development()` | Development mode (fast, keep originals) |

### Zstd Presets (v0.1.5+)

Zstandard (zstd) compression provides excellent compression ratios with very fast decompression. It's particularly well-suited for log files and streaming scenarios.

| Method | Description |
|--------|-------------|
| `zstd()` | Default zstd compression (level 6) |
| `zstdDefault()` | Alias for zstd() |
| `zstdFast()` | Fast zstd compression (level 1) |
| `zstdSpeed()` | Alias for zstdFast() |
| `zstdBest()` | Best zstd compression (level 19) |
| `zstdMax()` | Alias for zstdBest() |
| `zstdProduction()` | Production zstd with background processing |
| `zstdWithLevel(level)` | Custom zstd level (1-22) |

### Custom Zstd Levels (v0.1.5+)

Zstd supports compression levels from 1 to 22. Higher levels provide better compression but slower speed.

| Level Range | Use Case |
|------------|----------|
| 1-3 | Speed priority, real-time logging |
| 4-9 | Balanced speed/ratio |
| 10-15 | Good ratio, moderate speed |
| 16-19 | High compression, slower |
| 20-22 | Ultra compression (high memory) |

```zig
// Custom zstd level for fine-grained control
const cfg = CompressionConfig.zstdWithLevel(15);

// Get the effective level
const level = cfg.getEffectiveZstdLevel(); // Returns 15
```

### getEffectiveZstdLevel

Returns the effective zstd compression level, taking custom_zstd_level into account.

```zig
pub fn getEffectiveZstdLevel(self: *const CompressionConfig) i32
```

**Example: Zstd Compression**

```zig
const CompressionConfig = logly.Config.CompressionConfig;

// Default zstd compression
const cfg1 = CompressionConfig.zstd();

// Fast zstd for high-throughput scenarios
const cfg2 = CompressionConfig.zstdFast();

// Best zstd for archival
const cfg3 = CompressionConfig.zstdBest();

// Production-ready zstd with background processing
const cfg4 = CompressionConfig.zstdProduction();

// Custom level for specific use case
const cfg5 = CompressionConfig.zstdWithLevel(12);
```

## File Name Customization Options

CompressionConfig supports extensive file name and path customization:

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `file_prefix` | `?[]const u8` | `null` | Prefix for compressed file names (e.g., "archive_") |
| `file_suffix` | `?[]const u8` | `null` | Suffix before extension (e.g., "_compressed") |
| `archive_root_dir` | `?[]const u8` | `null` | Root directory for all compressed files |
| `create_date_subdirs` | `bool` | `false` | Create YYYY/MM/DD subdirectories in archive |
| `preserve_dir_structure` | `bool` | `true` | Preserve original directory structure in archive |
| `naming_pattern` | `?[]const u8` | `null` | Custom naming pattern with placeholders |

### Naming Pattern Placeholders

| Placeholder | Description |
|-------------|-------------|
| `{base}` | Original file name without extension |
| `{ext}` | Original file extension |
| `{date}` | Current date (YYYY-MM-DD) |
| `{time}` | Current time (HH-MM-SS) |
| `{timestamp}` | Unix timestamp |
| `{index}` | Incremental index |

**Example: Custom Archive Configuration**

```zig
const cfg = logly.Config.CompressionConfig{
    .enabled = true,
    .file_prefix = "archive_",
    .file_suffix = "_compressed",
    .archive_root_dir = "logs/archive",
    .create_date_subdirs = true,
    .naming_pattern = "{base}_{date}{ext}",
};

// Result: logs/archive/2026/01/09/archive_app_2026-01-09_compressed.log.gz
```

**Usage Examples:**

```zig
const CompressionConfig = logly.Config.CompressionConfig;

// One-liner presets
const cfg1 = CompressionConfig.enable();
const cfg2 = CompressionConfig.production();
const cfg3 = CompressionConfig.fast();
const cfg4 = CompressionConfig.onSize(5 * 1024 * 1024); // 5MB threshold

// Use with Config builder
var config = logly.Config.default().withCompression(CompressionConfig.production());
```

## Config Quick-Enable Methods

The `Config` struct provides quick-enable methods for compression:

| Method | Description |
|--------|-------------|
| `withCompressionEnabled()` | Simplest one-liner to enable |
| `withImplicitCompression()` | Automatic on rotation |
| `withExplicitCompression()` | Manual control |
| `withFastCompression()` | Speed priority |
| `withBestCompression()` | Ratio priority |
| `withBackgroundCompression()` | Background thread |
| `withLogCompression()` | Log-optimized |
| `withProductionCompression()` | Production-ready |
| `withZstdCompression()` | Default zstd compression (v0.1.5+) |
| `withZstdFastCompression()` | Fast zstd compression (v0.1.5+) |
| `withZstdBestCompression()` | Best zstd compression (v0.1.5+) |
| `withZstdProductionCompression()` | Production zstd (v0.1.5+) |

**Usage Examples:**

```zig
// Quick-enable compression
var config = logly.Config.default().withCompressionEnabled();

// Production-ready in one line
var config2 = logly.Config.default().withProductionCompression();

// Zstd compression with one line (v0.1.5+)
var config3 = logly.Config.default().withZstdCompression();

// Chain with other settings
var config4 = logly.Config.default()
    .withFastCompression()
    .withRotation(.{ .enabled = true });

// Production zstd with rotation
var config5 = logly.Config.default()
    .withZstdProductionCompression()
    .withRotation(.{ .enabled = true, .max_size = 10 * 1024 * 1024 });
```

## Compression Instance Presets

The `Compression` struct provides preset factory methods for direct instantiation:

| Method | Description |
|--------|-------------|
| `basic(allocator)` | Basic enabled compressor |
| `implicit(allocator)` | Auto compression on rotation |
| `explicit(allocator)` | Manual compression control |
| `fast(allocator)` | Speed priority |
| `balanced(allocator)` | Default balance |
| `best(allocator)` | Ratio priority |
| `forLogs(allocator)` | Log-optimized |
| `archive(allocator)` | Archival mode |
| `production(allocator)` | Production-ready |
| `development(allocator)` | Development mode |
| `background(allocator)` | Background thread |
| `streaming(allocator)` | Streaming mode |
| `zstdCompression(allocator)` | Default zstd (v0.1.5+) |
| `zstdFast(allocator)` | Fast zstd (v0.1.5+) |
| `zstdBest(allocator)` | Best zstd (v0.1.5+) |
| `zstdProduction(allocator)` | Production zstd (v0.1.5+) |

**Usage Examples:**

```zig
// One-liner compression instances
var compressor = logly.Compression.production(allocator);
defer compressor.deinit();

try compressor.compressFile("logs/app.log", null);

// Zstd compression instance (v0.1.5+)
var zstd_compressor = logly.Compression.zstdCompression(allocator);
defer zstd_compressor.deinit();

try zstd_compressor.compressFile("logs/app.log", null);
// Creates: logs/app.log.zst
```

**Algorithm Comparison:**

| Algorithm | Ratio | Compress Speed | Decompress Speed | Use Case |
|-----------|-------|----------------|------------------|----------|
| `none` | 1.0x | Instant | Instant | Testing, debugging |
| `deflate` | 3-5x | ~200 MB/s | ~300 MB/s | General purpose logs |
| `zlib` | 3-5x | ~180 MB/s | ~280 MB/s | Network transport |
| `raw_deflate` | 3-5x | ~220 MB/s | ~320 MB/s | Custom headers |
| `gzip` | 3-5x | ~190 MB/s | ~290 MB/s | Standard file compatibility |
| `zstd` | 3-6x | ~400 MB/s | ~1400 MB/s | High-performance, streaming (v0.1.5+) |


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
};
```

#### Getter Methods

| Method | Return | Description |
|--------|--------|-------------|
| `getFilesCompressed()` | `u64` | Get total files compressed |
| `getFilesDecompressed()` | `u64` | Get total files decompressed |
| `getBytesBefore()` | `u64` | Get total bytes before compression |
| `getBytesAfter()` | `u64` | Get total bytes after compression |
| `getBytesSaved()` | `u64` | Get total bytes saved by compression |
| `getCompressionErrors()` | `u64` | Get compression error count |
| `getDecompressionErrors()` | `u64` | Get decompression error count |
| `getTotalErrors()` | `u64` | Get total error count |
| `getBackgroundTasksQueued()` | `u64` | Get background tasks queued |
| `getBackgroundTasksCompleted()` | `u64` | Get background tasks completed |
| `getTotalOperations()` | `u64` | Get total operations (compress + decompress) |

#### Boolean Checks

| Method | Return | Description |
|--------|--------|-------------|
| `hasOperations()` | `bool` | Check if any operations have been performed |
| `hasErrors()` | `bool` | Check if any errors have occurred |
| `hasCompressionErrors()` | `bool` | Check for compression errors |
| `hasDecompressionErrors()` | `bool` | Check for decompression errors |
| `hasPendingBackgroundTasks()` | `bool` | Check for pending background tasks |

#### Rate Calculations

| Method | Return | Description |
|--------|--------|-------------|
| `compressionRatio()` | `f64` | Calculate compression ratio (before/after) |
| `spaceSavingsPercent()` | `f64` | Calculate space savings percentage |
| `avgCompressionSpeedMBps()` | `f64` | Calculate average compression speed in MB/s |
| `avgDecompressionSpeedMBps()` | `f64` | Calculate average decompression speed in MB/s |
| `errorRate()` | `f64` | Calculate overall error rate (0.0 - 1.0) |
| `successRate()` | `f64` | Calculate success rate (0.0 - 1.0) |
| `backgroundTaskCompletionRate()` | `f64` | Calculate background task completion rate |
| `avgBytesPerOperation()` | `f64` | Calculate average bytes per operation |

#### Reset

| Method | Description |
|--------|-------------|
| `reset()` | Reset all statistics to initial state |

**Statistics Example:**

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
std.debug.print("Background: {d}/{d} completed\n", .{
    stats.getBackgroundTasksCompleted(),
    stats.getBackgroundTasksQueued(),
});
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

**Alias:** `create`

```zig
pub fn init(allocator: std.mem.Allocator) Compression
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

**Alias:** `destroy`

```zig
pub fn deinit(self: *Compression) void
```

#### `compress(self: *Compression, data: []const u8) ![]u8`

Compresses data in memory using advanced algorithms. Uses the internal allocator.

#### `compressWithAllocator(self: *Compression, data: []const u8, scratch_allocator: ?std.mem.Allocator) ![]u8`

Compresses data using an optional scratch allocator. If provided, temporary allocations use this allocator. If null, falls back to the internal allocator.

**Example:**
```zig
const compressed = try compression.compressWithAllocator(data, logger.scratchAllocator());
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
- Automatic creation of output directories
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

### compressDirectory

Compresses all eligible files in a directory.

```zig
pub fn compressDirectory(self: *Compression, dir_path: []const u8) !u64
```

**Features:**
- Scans directory for files
- Checks eligibility with `shouldCompress`
- Skips already compressed files

**Example:**
```zig
const count = try compression.compressDirectory("logs/");
std.debug.print("Compressed {d} files\n", .{count});
```

### compressBatch (v0.1.5+)

Compresses multiple files in a batch operation.

```zig
pub fn compressBatch(self: *Compression, file_paths: []const []const u8) u64
```

**Returns:** Number of successfully compressed files.

**Example:**
```zig
const files = &[_][]const u8{
    "logs/app.log",
    "logs/error.log",
    "logs/access.log",
};
const count = compression.compressBatch(files);
std.debug.print("Compressed {d} files\n", .{count});
```

### compressPattern (v0.1.5+)

Compresses files matching a glob pattern in a directory.

```zig
pub fn compressPattern(self: *Compression, dir_path: []const u8, pattern: []const u8) !u64
```

**Pattern Support:**
- `*.log` - Match all `.log` files
- `*` - Match all files
- Exact name - Match specific file

**Example:**
```zig
// Compress all log files
const count = try compression.compressPattern("logs/", "*.log");
std.debug.print("Compressed {d} log files\n", .{count});

// Compress all json files
const json_count = try compression.compressPattern("data/", "*.json");
```

### compressOldest (v0.1.5+)

Compresses the N oldest files in a directory based on modification time.

```zig
pub fn compressOldest(self: *Compression, dir_path: []const u8, count: usize) !u64
```

**Features:**
- Sorts files by modification time (oldest first)
- Compresses specified number of oldest files
- Useful for rotation-based compression

**Example:**
```zig
// Compress the 5 oldest log files
const count = try compression.compressOldest("logs/", 5);
std.debug.print("Compressed {d} oldest files\n", .{count});
```

### compressLargerThan (v0.1.5+)

Compresses files larger than a specified size threshold.

```zig
pub fn compressLargerThan(self: *Compression, dir_path: []const u8, min_size: u64) !u64
```

**Example:**
```zig
// Compress files larger than 1MB
const count = try compression.compressLargerThan("logs/", 1024 * 1024);
std.debug.print("Compressed {d} large files\n", .{count});

// Compress files larger than 10MB
const large_count = try compression.compressLargerThan("logs/", 10 * 1024 * 1024);
```

## Utility Methods (v0.1.5+)

### estimateCompressedSize

Estimates the compressed size based on the configured algorithm and level.

```zig
pub fn estimateCompressedSize(self: *const Compression, data_size: u64) u64
```

**Example:**
```zig
const estimated = compression.estimateCompressedSize(1024 * 1024); // 1MB
std.debug.print("Estimated compressed size: {} bytes\n", .{estimated});
```

### getExtension

Returns the file extension for the configured compression algorithm.

```zig
pub fn getExtension(self: *const Compression) []const u8
```

**Returns:** `.gz`, `.zst`, `.lgz`, etc.

### isZstd

Returns true if using zstd compression algorithm.

```zig
pub fn isZstd(self: *const Compression) bool
```

### algorithmName

Returns the algorithm name as a string.

```zig
pub fn algorithmName(self: *const Compression) []const u8
```

**Returns:** `"none"`, `"deflate"`, `"zlib"`, `"gzip"`, `"zstd"`, etc.

### levelName

Returns the compression level name as a string.

```zig
pub fn levelName(self: *const Compression) []const u8
```

**Returns:** `"none"`, `"fastest"`, `"fast"`, `"default"`, `"best"`

**Example:**
```zig
std.debug.print("Algorithm: {s}\n", .{compression.algorithmName()});
std.debug.print("Level: {s}\n", .{compression.levelName()});
std.debug.print("Extension: {s}\n", .{compression.getExtension()});
std.debug.print("Is zstd: {}\n", .{compression.isZstd()});
```

### compressStream

Streaming compression from a reader to a writer.

```zig
pub fn compressStream(self: *Compression, reader: anytype, writer: anytype) !void
```

**Features:**
- Low memory footprint (no large buffers)
- Compatible with `std.io.Reader` and `std.io.Writer`
- Supports GZIP and Deflate algorithms

**Example:**

```zig
var input_stream = std.io.fixedBufferStream(data);
var output_buffer = std.ArrayList(u8).init(allocator);
defer output_buffer.deinit();

try compression.compressStream(input_stream.reader(), output_buffer.writer(allocator));
```

### decompressStream

Streaming decompression from a reader to a writer.

```zig
pub fn decompressStream(self: *Compression, reader: anytype, writer: anytype) !void
```

**Example:**

```zig
var input_stream = std.io.fixedBufferStream(compressed_data);
var output_buffer = std.ArrayList(u8).init(allocator);
defer output_buffer.deinit();

try compression.decompressStream(input_stream.reader(), output_buffer.writer(allocator));
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

pub fn getStats(self: *const Compression) CompressionStats

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
        std.debug.print("✓ Compressed: {d:.1}% savings\\n", .{result.ratio() * 100});
        
        // Get statistics
        const stats = compression.getStats();
        std.debug.print("Total files: {d}\\n", 
            .{stats.getFilesCompressed()});
        std.debug.print("Compression ratio: {d:.2}x\\n", 
            .{stats.compressionRatio()});
        std.debug.print("Speed: {d:.1} MB/s\\n", 
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

## Aliases

The Compression module provides convenience aliases:

| Alias | Method |
|-------|--------|
| `encode` | `compress` |
| `deflate` | `compress` |
| `decode` | `decompress` |
| `inflate` | `decompress` |
| `packFile` | `compressFile` |
| `unpackFile` | `decompressFile` |
| `statistics` | `getStats` |
| `needsCompression` | `shouldCompress` |

## Additional Methods

- `isEnabled() bool` - Returns true if compression is enabled
- `ratio() f64` - Returns current compression ratio

## See Also

- [Compression Guide](../guide/compression.md) - Detailed compression guide
- [Rotation Guide](../guide/rotation.md) - Log rotation with compression
- [Callbacks Guide](../guide/callbacks.md) - Callback patterns
- [Configuration](../guide/configuration.md) - Centralized config setup

