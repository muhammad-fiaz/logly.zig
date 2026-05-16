---
title: Log Compression Example
description: Example of log compression with Logly.zig using DEFLATE, GZIP, ZLIB, ZSTD, LZMA, LZMA2, XZ, TAR.GZ, ZIP, and LZ4 algorithms. Compress logs with CRC32 verification, configurable levels, and rotation integration.
head:
  - - meta
    - name: keywords
      content: log compression example, gzip logs, zstd compression, log archiving, compression ratio, crc32 verification
  - - meta
    - property: og:title
      content: Log Compression Example | Logly.zig
---

# Compression Example

This example demonstrates log compression features in Logly, including GZIP, ZSTD (v0.1.8+), LZMA, XZ, TAR.GZ, ZIP, LZ4, and the Streaming API.

## Source Code

```zig
//! Compression Example
//!
//! Demonstrates how to use log compression features in Logly.
//! Includes automatic compression on rotation, manual compression, GZIP, ZSTD, and Streaming.

const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n=== Logly Compression Example ===\n\n", .{});

    // Example 1: Basic compression setup
    std.debug.print("1. Basic Compression Setup\n", .{});
    std.debug.print("   -------------------------\n", .{});

    var comp = logly.Compression.init(allocator);
    defer comp.deinit();

    const test_data = "This is test log data that will be compressed. " ** 10;
    std.debug.print("   Original data size: {d} bytes\n", .{test_data.len});

    const compressed = try comp.compress(test_data);
    defer allocator.free(compressed);
    std.debug.print("   Compressed size: {d} bytes\n", .{compressed.len});

    const decompressed = try comp.decompress(compressed);
    defer allocator.free(decompressed);
    std.debug.print("   Decompressed size: {d} bytes\n", .{decompressed.len});
    std.debug.print("   Data integrity: {s}\n\n", .{if (std.mem.eql(u8, test_data, decompressed)) "âœ“ Verified" else "âœ— Failed"});

    // Example 2: Compression presets
    std.debug.print("2. Compression Presets\n", .{});
    // ... (See full example file for details)

    // Example 6: GZIP Algorithm
    std.debug.print("6. GZIP Algorithm\n", .{});
    std.debug.print("   ------------------------\n", .{});

    var gzip_comp = logly.Compression.initWithConfig(allocator, .{
        .algorithm = .gzip,
        .level = .default,
    });
    defer gzip_comp.deinit();

    const gzip_data = "Data compressed with GZIP algorithm";
    const gzip_compressed = try gzip_comp.compress(gzip_data);
    defer allocator.free(gzip_compressed);

    std.debug.print("   GZIP compressed size: {d} bytes\n\n", .{gzip_compressed.len});

    // Example 7: Zstd Compression (v0.1.8+)
    std.debug.print("7. Zstd Compression (v0.1.8+)\n", .{});
    std.debug.print("   ---------------------------\n", .{});

    var zstd_comp = logly.Compression.zstdCompression(allocator);
    defer zstd_comp.deinit();

    const zstd_data = "Data compressed with Zstandard algorithm - very fast decompression! " ** 5;
    const zstd_compressed = try zstd_comp.compress(zstd_data);
    defer allocator.free(zstd_compressed);

    std.debug.print("   Original size: {d} bytes\n", .{zstd_data.len});
    std.debug.print("   Zstd compressed size: {d} bytes\n", .{zstd_compressed.len});

    const zstd_decompressed = try zstd_comp.decompress(zstd_compressed);
    defer allocator.free(zstd_decompressed);
    std.debug.print("   Zstd decompressed: {d} bytes\n", .{zstd_decompressed.len});
    std.debug.print("   Data integrity: {s}\n\n", .{if (std.mem.eql(u8, zstd_data, zstd_decompressed)) "âœ“ Verified" else "âœ— Failed"});

    // Example 8: Streaming Compression
    std.debug.print("8. Streaming Compression\n", .{});
    std.debug.print("   ---------------------\n", .{});

    var stream_comp = logly.Compression.init(allocator);
    defer stream_comp.deinit();

    const stream_data = "Data to be compressed via stream" ** 5;
    var input_stream = std.Io.Reader.fixed(stream_data);
    var output_buffer: std.ArrayList(u8) = .empty;
    defer output_buffer.deinit(allocator);

    var output_writer = logly.Utils.ArrayListWriter.init(&output_buffer, allocator);
    try stream_comp.compressStream(&input_stream, &output_writer.writer);
    std.debug.print("   Stream compressed size: {d} bytes\n", .{output_buffer.items.len});

    // Example 9: Directory Compression
    std.debug.print("9. Directory Compression\n", .{});
    const files_processed = try stream_comp.compressDirectory("logs_test_batch");
    std.debug.print("   Batch compressed {d} files\n", .{files_processed});
}
```

## Running the Example

```bash
zig build run-compression
```

## Expected Output

```
=== Logly Compression Example ===

1. Basic Compression Setup
   -------------------------
   Original data size: 470 bytes
   Compressed size: 77 bytes
   Decompressed size: 470 bytes
   Data integrity: âœ“ Verified

...

6. GZIP Algorithm
   ------------------------
   GZIP compressed size: 49 bytes

7. Streaming Compression
   ---------------------
   Stream compressed size: 57 bytes
   Stream decompressed verified: âœ“ Yes

8. Directory Compression
   ---------------------
   Batch compressed 2 files in 'logs_test_batch'
```

## Key Concepts

### Centralized Configuration

```zig
var config = logly.Config.default();
config.compression = logly.CompressionConfig{
    .algorithm = .gzip, // Supports .deflate, .gzip, .zlib, .raw_deflate, .zstd, .lzma, .lzma2, .xz, .zip, .tar_gz, .lz4
    .level = .default,
    .mode = .on_rotation,
};
```

### Streaming API

The streaming API allows you to compress data directly from a `Reader` to a `Writer` without buffering the entire content in memory.

```zig
try compression.compressStream(reader, writer);
try compression.decompressStream(reader, writer);
```

### Directory Compression

You can compress all log files in a directory at once:

```zig
// Compress all log files in the "logs" folder
const files_processed = try compression.compressDirectory("logs");
```
});
```

### Compression Algorithm

Logly uses a **hybrid LZ77+RLE** algorithm:

- **LZ77**: Finds repeated patterns using sliding window
- **RLE**: Compresses runs of identical bytes
- **CRC32**: Verifies data integrity

### Compression Levels

```zig
.level = 1,  // Fast, lower ratio
.level = 6,  // Balanced (default)
.level = 9,  // Best ratio, slower
```

```

## Integration with Rotation

```zig
var config = logly.Config.init(allocator);
config.rotation = .{
    .enabled = true,
    .max_file_size = 10 * 1024 * 1024,
    .compress_rotated = true,
};
```

## New Algorithms (v0.1.8+)

### LZMA/XZ Compression

High-ratio compression for archiving:

```zig
// LZMA - Maximum compression ratio
var lzma_comp = logly.Compression.lzmaCompression(allocator);
defer lzma_comp.deinit();

const lzma_compressed = try lzma_comp.compress(log_data);
defer allocator.free(lzma_compressed);

// XZ - Standard archive format
var xz_comp = logly.Compression.xzCompression(allocator);
defer xz_comp.deinit();

const xz_compressed = try xz_comp.compress(log_data);
defer allocator.free(xz_compressed);
```

### ZIP Archive

Cross-platform compatible archives:

```zig
var zip_comp = logly.Compression.zipCompression(allocator);
defer zip_comp.deinit();

const zipped = try zip_comp.compress(log_data);
defer allocator.free(zipped);

// Decompress
const unzipped = try zip_comp.decompress(zipped);
defer allocator.free(unzipped);
```

### TAR.GZ Archive

Unix-style archives:

```zig
var targz_comp = logly.Compression.tarGzCompression(allocator);
defer targz_comp.deinit();

const archived = try targz_comp.compress(log_content);
defer allocator.free(archived);
```

### LZ4 Fast Compression

Ultra-fast for real-time logging:

```zig
var lz4_comp = logly.Compression.lz4Compression(allocator);
defer lz4_comp.deinit();

// LZ4 prioritizes speed over ratio
const fast_compressed = try lz4_comp.compress(log_data);
defer allocator.free(fast_compressed);
```

### Algorithm Comparison

| Algorithm | Speed | Ratio | Use Case |
|-----------|-------|-------|----------|
| `deflate` | â˜…â˜…â˜…â˜… | â˜…â˜…â˜… | General purpose |
| `zstd` | â˜…â˜…â˜…â˜…â˜… | â˜…â˜…â˜…â˜… | High performance |
| `lzma` | â˜…â˜… | â˜…â˜…â˜…â˜…â˜… | Long-term storage |
| `xz` | â˜…â˜… | â˜…â˜…â˜…â˜…â˜… | Distribution |
| `zip` | â˜…â˜…â˜…â˜… | â˜…â˜…â˜… | Cross-platform |
| `tar_gz` | â˜…â˜…â˜… | â˜…â˜…â˜…â˜… | Unix archives |
| `lz4` | â˜…â˜…â˜…â˜…â˜… | â˜…â˜… | Real-time |

## See Also

- [Compression API](../api/compression.md)
- [Compression Guide](../guide/compression.md)
- [Rotation Example](rotation.md)
