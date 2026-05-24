---
title: Log Compression Guide
description: Learn how to compress log files with Logly.zig using DEFLATE, GZIP, ZLIB, ZSTD, LZMA, XZ, LZ4, and archive formats. Covers automatic rotation compression, background processing, streaming mode, and performance optimization.
head:
  - - meta
    - name: keywords
      content: log compression, gzip logs, zlib compression, zstd compression, log archiving, storage optimization, compressed logging, log backup
---

# Compression Guide

This guide covers log compression in Logly, including automatic and manual compression, configuration options, and best practices.

## Overview

Logly provides a comprehensive compression module with advanced features:

- **Multiple Algorithms**: DEFLATE, GZIP, ZLIB, RAW DEFLATE, ZSTD, LZMA, LZMA2, XZ, TAR.GZ, ZIP, LZ4
- **Smart Strategies**: Text-optimized, binary, RLE, adaptive auto-detection
- **Flexible Modes**: Manual, on-rotation, size-based, scheduled, streaming
- **Background Processing**: Offload compression to thread pool
- **Real-time Monitoring**: Detailed statistics with atomic counters
- **Callback System**: Complete observability with event hooks
- **Data Integrity**: CRC32 checksums with corruption detection
- **Performance**: High-speed compression with modern algorithms

## Quick Start

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
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

## Minimal Configuration (One-Liner Setup)

Logly provides preset configurations for the simplest possible compression setup. Use these when you don't need custom settings.

### Config Builder Methods (Logger Integration)

```zig
const logly = @import("logly");

// Simplest - just enable compression
var config = logly.Config.default().withCompressionEnabled();

// Implicit (automatic) - compress on rotation
var config2 = logly.Config.default().withImplicitCompression();

// Explicit (manual) - you control when to compress
var config3 = logly.Config.default().withExplicitCompression();

// Fast compression - prioritize speed
var config4 = logly.Config.default().withFastCompression();

// Best compression - prioritize ratio
var config5 = logly.Config.default().withBestCompression();

// Background - non-blocking compression
var config6 = logly.Config.default().withBackgroundCompression();

// Log-optimized - text strategy for log files
var config7 = logly.Config.default().withLogCompression();

// Production-ready - balanced with checksums
var config8 = logly.Config.default().withProductionCompression();
```

### CompressionConfig Presets

```zig
const CompressionConfig = logly.CompressionConfig;

// Preset configurations
const enable_cfg = CompressionConfig.enable();        // Basic enabled
const implicit_cfg = CompressionConfig.implicit();    // Auto on rotation
const explicit_cfg = CompressionConfig.explicit();    // Manual control
const fast_cfg = CompressionConfig.fast();            // Speed priority
const balanced_cfg = CompressionConfig.balanced();    // Default balance
const best_cfg = CompressionConfig.best();            // Ratio priority
const for_logs_cfg = CompressionConfig.forLogs();     // Log optimized
const archive_cfg = CompressionConfig.archive();      // Archival mode
const keep_cfg = CompressionConfig.keepOriginals();   // Keep original files
const prod_cfg = CompressionConfig.production();      // Production ready
const dev_cfg = CompressionConfig.development();      // Development mode
const disable_cfg = CompressionConfig.disable();      // Disabled
const bg_cfg = CompressionConfig.backgroundMode();    // Background thread
const stream_cfg = CompressionConfig.streamingMode(); // Streaming mode
const zstd_cfg = CompressionConfig.zstd();            // Default zstd
const zstd_fast_cfg = CompressionConfig.zstdFast();   // Fast zstd
const zstd_best_cfg = CompressionConfig.zstdBest();   // Best zstd ratio
const zstd_prod_cfg = CompressionConfig.zstdProduction(); // Production zstd
const zstd_custom = CompressionConfig.zstdWithLevel(12); // Custom level

// v0.1.8+ algorithms
const lzma_cfg = CompressionConfig.lzma();            // LZMA
const xz_cfg = CompressionConfig.xz();                // XZ
const lz4_cfg = CompressionConfig.lz4();              // LZ4
const zip_cfg = CompressionConfig.zip();              // ZIP
const targz_cfg = CompressionConfig.tarGz();          // TAR.GZ

// Size-based trigger (compress when file exceeds 5MB)
const size_cfg = CompressionConfig.onSize(5 * 1024 * 1024);

// Use with Config
var config = logly.Config.default().withCompression(prod_cfg);

// Or use zstd for best performance (v0.1.8+)
var zstd_config = logly.Config.default().withZstdCompression();
```

### Compression Instance Presets

```zig
const allocator = std.heap.page_allocator;

// One-liner compression instances
var comp1 = logly.Compression.init(allocator);         // Basic default
var comp3 = logly.Compression.implicit(allocator);     // Auto on rotation
var comp4 = logly.Compression.explicit(allocator);     // Manual control
var comp5 = logly.Compression.fast(allocator);         // Speed priority
var comp6 = logly.Compression.balanced(allocator);     // Default balance
var comp7 = logly.Compression.best(allocator);         // Ratio priority
var comp8 = logly.Compression.forLogs(allocator);      // Log optimized
var comp9 = logly.Compression.archive(allocator);      // Archival mode
var comp10 = logly.Compression.production(allocator);  // Production ready
var comp11 = logly.Compression.development(allocator); // Development mode
var comp14 = logly.Compression.zstdCompression(allocator);   // Default zstd
var comp15 = logly.Compression.zstdFast(allocator);          // Fast zstd
var comp16 = logly.Compression.zstdBest(allocator);          // Best zstd ratio
var comp17 = logly.Compression.zstdProduction(allocator);    // Production zstd

// v0.1.8+ factory methods
var lzma_comp = logly.Compression.lzmaCompression(allocator);
var xz_comp = logly.Compression.xzCompression(allocator);
var lz4_comp = logly.Compression.lz4Compression(allocator);
var zip_comp = logly.Compression.zipCompression(allocator);
var targz_comp = logly.Compression.tarGzCompression(allocator);

defer comp1.deinit();
// ... defer for others
```

## Zstd Compression (v0.1.8+)

Zstandard (zstd) is a high-performance compression algorithm that provides excellent compression ratios with very fast decompression. It's ideal for log files, especially in production environments.

### Why Use Zstd?

| Feature | Zstd | GZIP/DEFLATE |
|---------|------|--------------|
| **Compression Ratio** | 3-6x | 3-5x |
| **Compression Speed** | ~400 MB/s | ~200 MB/s |
| **Decompression Speed** | ~1400 MB/s | ~300 MB/s |
| **File Extension** | `.zst` | `.gz` |
| **Best For** | High-throughput, streaming | Compatibility |

### Quick Zstd Setup

```zig
const logly = @import("logly");

// One-liner zstd compression
var config = logly.Config.default().withZstdCompression();

// Or with specific settings
var config2 = logly.Config.default().withZstdFastCompression();      // Speed priority
var config3 = logly.Config.default().withZstdBestCompression();      // Ratio priority
var config4 = logly.Config.default().withZstdProductionCompression(); // Background + checksums
```

### Zstd Compression Levels

| Preset | Level | Speed | Ratio | Use Case |
|--------|-------|-------|-------|----------|
| `zstdFast()` | 1 | Fastest | Good | High-throughput logging |
| `zstd()` | 6 | Balanced | Better | Default, general purpose |
| `zstdBest()` | 19 | Slower | Best | Long-term archival |
| `zstdProduction()` | 6 | Balanced | Better | Production with checksums + background |

### Direct Zstd Compression

```zig
var gpa = std.heap.DebugAllocator(.{}){};
defer _ = gpa.deinit();
const allocator = gpa.allocator();

// Create zstd compressor
var compressor = logly.Compression.zstdCompression(allocator);
defer compressor.deinit();

// Compress data
const data = "Log data to compress..." ** 100;
const compressed = try compressor.compress(data);
defer allocator.free(compressed);

// Decompress
const decompressed = try compressor.decompress(compressed);
defer allocator.free(decompressed);

std.debug.print("Original: {d} bytes, Compressed: {d} bytes\n", 
    .{data.len, compressed.len});
```

### Zstd File Compression

```zig
var compressor = logly.Compression.zstdProduction(allocator);
defer compressor.deinit();

// Compress a log file (creates .zst file)
try compressor.compressFile("logs/app.log", null);
// Result: logs/app.log.zst

// Compress directory
const files_compressed = try compressor.compressDirectory("logs/archive/");
std.debug.print("Compressed {d} files\n", .{files_compressed});
```

### Zstd Dictionary Support

For highly repetitive logs, Zstd supports compression with a pre-trained dictionary, massively improving compression ratio and speed for small records:

```zig
var config = logly.Config.default().withZstdCompression();
config.compression.zstd_dict = my_pre_trained_dict_bytes;

var compressor = logly.Compression.initWithConfig(allocator, config.compression);
defer compressor.deinit();
```

## New Compression Algorithms (v0.1.8+)

v0.1.8 introduces full compression and decompression support for six additional algorithms, providing flexibility for different use cases.

### Algorithm Overview

| Algorithm | Factory Method | Extension | Best For |
|-----------|---------------|-----------|----------|
| **LZMA** | `lzmaCompression()` | `.lzma` | High-ratio archival |
| **LZMA2** | `lzma2Compression()` | `.lzma2` | Large file archival |
| **XZ** | `xzCompression()` | `.xz` | Distribution packages |
| **ZIP** | `zipCompression()` | `.zip` | Cross-platform sharing |
| **TAR.GZ** | `tarGzCompression()` | `.tar.gz` | Unix-style archives |
| **LZ4** | `lz4Compression()` | `.lz4` | Real-time high-speed |

### LZMA/LZMA2/XZ Compression

High-ratio compression ideal for long-term log archival:

```zig
const logly = @import("logly");

// LZMA - highest compression ratio
var lzma_comp = logly.Compression.lzmaCompression(allocator);
defer lzma_comp.deinit();

const data = "Log data for archival..." ** 1000;
const compressed = try lzma_comp.compress(data);
defer allocator.free(compressed);

std.debug.print("LZMA: {d} -> {d} bytes\n", .{data.len, compressed.len});

// XZ - standard distribution format
var xz_comp = logly.Compression.xzCompression(allocator);
defer xz_comp.deinit();

const xz_compressed = try xz_comp.compress(data);
defer allocator.free(xz_compressed);
```

### ZIP Compression

Create standard ZIP archives compatible with all systems:

```zig
var zip_comp = logly.Compression.zipCompression(allocator);
defer zip_comp.deinit();

const log_data = "[2026-01-19] INFO: Application started\n" ** 100;
const zipped = try zip_comp.compress(log_data);
defer allocator.free(zipped);

// Decompress back
const original = try zip_comp.decompress(zipped);
defer allocator.free(original);
```

### TAR.GZ Compression

Unix-style tar archive with gzip compression:

```zig
var targz_comp = logly.Compression.tarGzCompression(allocator);
defer targz_comp.deinit();

const log_content = "Server log entry...\n" ** 500;
const archived = try targz_comp.compress(log_content);
defer allocator.free(archived);

// Extract
const extracted = try targz_comp.decompress(archived);
defer allocator.free(extracted);
```

### LZ4 Fast Compression

Ultra-fast compression for real-time logging scenarios:

```zig
var lz4_comp = logly.Compression.lz4Compression(allocator);
defer lz4_comp.deinit();

// LZ4 prioritizes speed over ratio
const fast_data = "High-throughput log data..." ** 200;
const fast_compressed = try lz4_comp.compress(fast_data);
defer allocator.free(fast_compressed);
```

### Using CompressionConfig Presets

```zig
const CompressionConfig = logly.Config.CompressionConfig;

// Use preset configurations
const lzma_cfg = CompressionConfig.lzma();     // .lzma extension
const lzma2_cfg = CompressionConfig.lzma2();   // .lzma2 extension
const xz_cfg = CompressionConfig.xz();         // .xz extension
const zip_cfg = CompressionConfig.zip();       // .zip extension
const targz_cfg = CompressionConfig.tarGz();   // .tar.gz extension
const lz4_cfg = CompressionConfig.lz4();       // .lz4 extension

// Apply to config
var config = logly.Config.default().withCompression(lzma_cfg);
```

## File Name Customization

Customize compressed file names, locations, and archive structure:

### Customization Options

| Option | Description | Example |
|--------|-------------|---------|
| `file_prefix` | Prefix for file names | `"archive_"` â†’ `archive_app.log.gz` |
| `file_suffix` | Suffix before extension | `"_old"` â†’ `app_old.log.gz` |
| `archive_root_dir` | Centralized archive location | `"logs/archive"` |
| `create_date_subdirs` | Create YYYY/MM/DD structure | `logs/archive/2026/01/09/` |
| `preserve_dir_structure` | Keep original folder structure | Original: `src/logs/` â†’ `archive/src/logs/` |
| `naming_pattern` | Custom naming with placeholders | `"{base}_{date}{ext}"` |

### Naming Pattern Placeholders

| Placeholder | Description | Example |
|-------------|-------------|---------|
| `{base}` | Original file name | `app` from `app.log` |
| `{ext}` | Original extension | `.log` |
| `{date}` | Current date | `2026-01-09` |
| `{time}` | Current time | `14-30-45` |
| `{timestamp}` | Unix timestamp | `1736433045` |
| `{index}` | Incremental index | `001`, `002` |

### Configuration Example

```zig
const cfg = logly.Config.CompressionConfig{
    .enabled = true,
    .algorithm = .gzip,
    .level = .best,
    // File name customization
    .file_prefix = "archived_",
    .file_suffix = "_v1",
    // Centralized archive
    .archive_root_dir = "logs/compressed",
    .create_date_subdirs = true,
    .preserve_dir_structure = true,
    // Custom naming
    .naming_pattern = "{base}_{date}{ext}",
};

// Result: logs/compressed/2026/01/09/archived_app_2026-01-09_v1.log.gz
```

### Archive Root Directory

Store all compressed files in a centralized location:

```zig
var config = logly.Config.default();
config.compression = .{
    .enabled = true,
    .archive_root_dir = "logs/archive",      // All compressed files go here
    .create_date_subdirs = true,              // Organize by date
    .preserve_dir_structure = false,          // Flatten directory structure
};

// Input:  logs/app/server.log
// Output: logs/archive/2026/01/09/server.log.gz
```

### Implicit vs Explicit Compression

| Feature | Implicit | Explicit |
|---------|----------|----------|
| **Control** | Automatic | Manual |
| **Trigger** | On rotation, size threshold, or schedule | User calls compress methods |
| **Config** | `withImplicitCompression()` | `withExplicitCompression()` |
| **Use Case** | Set-and-forget log management | Fine-grained control |
| **Methods** | Automatic via rotation/scheduler | `compressFile()`, `compressDirectory()`, `compressStream()` |

**Implicit Example:**
```zig
// Automatic compression - library handles everything
var config = logly.Config.default()
    .withImplicitCompression()
    .withRotation(.{ .enabled = true, .interval = "daily" });
// Logs are compressed automatically when rotated
```

**Explicit Example:**
```zig
// Manual compression - you control when
var config = logly.Config.default().withExplicitCompression();
var compression = logly.Compression.explicit(allocator);
defer compression.deinit();

// Compress when YOU decide
try compression.compressFile("logs/app.log", null);
try compression.compressDirectory("logs/archive/");
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
| `.gzip` | GZIP format (standard compression) | ~190 MB/s | 3-5x | Standard file compatibility |

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

## File Compression Methods

Logly offers two approaches for file compression: **Implicit** (automated) and **Explicit** (manual stream control).

### Implicit File Creation (Recommended)

Use `compressFile` or `compressDirectory`. The library automatically handles:
- File creation and path management
- Creating parent directories (like `mkdir -p`) if they don't exist
- Opening/Closing file handles safely

```zig
// 1. Single File Compression
// Automatically creates "archive/app.log.gz", creating the 'archive' folder if needed
try compression.compressFile("app.log", "archive/app.log.gz");

// 2. Directory Batch Compression
// Compresses every file in "logs/" to a corresponding .gz file
try compression.compressDirectory("logs/");
```

### Explicit File Creation (Advanced)

Use `compressStream` when you need fine-grained control, such as using existing file handles, sockets, or custom permissions. You are responsible for opening and closing the files.

```zig
// 1. Manually create/open files
const io = logly.Utils.io();
var out_file = try std.Io.Dir.cwd().createFile(io, "custom_output.gz", .{});
defer out_file.close(io);

var in_file = try std.Io.Dir.cwd().openFile(io, "input.log", .{});
defer in_file.close(io);

// 2. Stream compression
var in_buffer: [4096]u8 = undefined;
var out_buffer: [4096]u8 = undefined;
var input_reader = in_file.reader(io, &in_buffer);
var output_writer = out_file.writer(io, &out_buffer);
try compression.compressStream(&input_reader.interface, &output_writer.interface);
try output_writer.interface.flush();
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

Compress data directly to a file stream as it is generated. This is useful for large datasets where you don't want to buffer the entire content in memory.

**Note:** This mode requires manual management of the output stream.

```zig
var stream_comp = logly.Compression.init(allocator);
defer stream_comp.deinit();

// 1. Create the output file (compressed destination)
const io = logly.Utils.io();
var file = try std.Io.Dir.cwd().createFile(io, "data.gz", .{});
defer file.close(io);

// 2. Prepare input stream (e.g., from a network socket or another file)
// Here we use a fixed buffer for demonstration
const data = "Log data to be streamed..." ** 100;
var input_stream = std.Io.Reader.fixed(data);

// 3. Compress directly to the file
// The data flows: input_stream -> compressor -> file
var file_buffer: [4096]u8 = undefined;
var file_writer = file.writer(io, &file_buffer);
try stream_comp.compressStream(&input_stream, &file_writer.interface);
try file_writer.interface.flush();

// 4. Verify file creation
const stat = try std.Io.Dir.cwd().statFile(io, "data.gz");
std.debug.print("Created data.gz: {d} bytes\n", .{stat.size});
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

### Background Mode (Asynchronous Compression)

Offload compression to background threads using the `ThreadPool` so the main application thread doesn't block:

```zig
var pool = try logly.ThreadPool.init(allocator, .{});
try pool.start();
defer pool.stop();

var compression = logly.Compression.initWithConfig(allocator, .{
    .algorithm = .zstd,
    .thread_pool = &pool,
});

// Compression is dispatched asynchronously to the thread pool
try compression.asyncCompress("large.log", "archive/large.log.zst");

// Or using aliases
try compression.asyncPack("large.log", "archive/large.log.zst");
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

Compress entire log files. Logly automatically handles creating necessary directories for the output file.

```zig
// Compress a file
// If logs/archive does not exist, it will be created automatically.
try compression.compressFile("logs/app.log", "logs/archive/app.log.gz");
```

### Batch Compression

Compress all log files in a directory:

```zig
// Scan directory and compress all eligible files
const count = try compression.compressDirectory("logs/");
std.debug.print("Batch compressed {d} files\n", .{count});
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
    .{stats.getFilesCompressed()});
std.debug.print("Files decompressed: {d}\n", 
    .{stats.getFilesDecompressed()});

// Background tasks (if enabled)
const queued = stats.getBackgroundTasksQueued();
const completed = stats.getBackgroundTasksCompleted();
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
    var gpa = std.heap.DebugAllocator(.{}){};
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
        .{stats.getFilesCompressed()});
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

    const start = logly.Utils.currentNanos();
    const compressed = try compression.compress(test_data);
    const elapsed = logly.Utils.currentNanos() - start;
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
