---
title: Log Compression Example
description: Example of log compression with Logly.zig using LZ77+RLE hybrid algorithm. Compress logs with CRC32 verification, configurable levels, and rotation integration.
head:
  - - meta
    - name: keywords
      content: log compression example, gzip logs, lz77 compression, log archiving, compression ratio, crc32 verification
  - - meta
    - property: og:title
      content: Log Compression Example | Logly.zig
---

# Compression Example

This example demonstrates log compression features in Logly, including GZIP support and Streaming APIs.

## Source Code

```zig
//! Compression Example
//!
//! Demonstrates how to use log compression features in Logly.
//! Includes automatic compression on rotation, manual compression, GZIP, and Streaming.

const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
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
    std.debug.print("   Data integrity: {s}\n\n", .{if (std.mem.eql(u8, test_data, decompressed)) "✓ Verified" else "✗ Failed"});

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

    // Example 7: Streaming Compression
    std.debug.print("7. Streaming Compression\n", .{});
    std.debug.print("   ---------------------\n", .{});

    var stream_comp = logly.Compression.init(allocator);
    defer stream_comp.deinit();

    const stream_data = "Data to be compressed via stream" ** 5;
    var input_stream = std.io.fixedBufferStream(stream_data);
    var output_buffer: std.ArrayList(u8) = .empty;
    defer output_buffer.deinit(allocator);

    try stream_comp.compressStream(input_stream.reader(), output_buffer.writer(allocator));
    std.debug.print("   Stream compressed size: {d} bytes\n", .{output_buffer.items.len});

    // Example 8: Directory Compression
    std.debug.print("8. Directory Compression\n", .{});
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
   Data integrity: ✓ Verified

...

6. GZIP Algorithm
   ------------------------
   GZIP compressed size: 49 bytes

7. Streaming Compression
   ---------------------
   Stream compressed size: 57 bytes
   Stream decompressed verified: ✓ Yes

8. Directory Compression
   ---------------------
   Batch compressed 2 files in 'logs_test_batch'
```

## Key Concepts

### Centralized Configuration

```zig
var config = logly.Config.default();
config.compression = logly.CompressionConfig{
    .algorithm = .gzip, // Supports .deflate, .gzip, .zlib, .raw_deflate
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

## Integration with Rotation

```zig
var config = logly.Config.init(allocator);
config.rotation = .{
    .enabled = true,
    .max_file_size = 10 * 1024 * 1024,
    .compress_rotated = true,
};
```

## See Also

- [Compression API](../api/compression.md)
- [Compression Guide](../guide/compression.md)
- [Rotation Example](rotation.md)
