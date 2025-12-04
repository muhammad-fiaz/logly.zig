# Compression Example

This example demonstrates log compression features in Logly using the LZ77+RLE hybrid algorithm.

## Source Code

```zig
//! Compression Example
//!
//! Demonstrates Logly's LZ77+RLE compression with CRC32 verification.

const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("Logly Compression Demo\n", .{});
    std.debug.print("======================\n\n", .{});

    // Create compression with default settings
    var compression = logly.Compression.init(allocator, .{});
    defer compression.deinit();

    // Test data with varying patterns
    const test_cases = [_][]const u8{
        "Hello, World! " ** 100,                          // Repetitive
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",  // Highly compressible
        "The quick brown fox jumps over the lazy dog. ",  // Normal text
    };

    for (test_cases, 0..) |original, i| {
        const compressed = try compression.compress(original);
        defer allocator.free(compressed);

        const decompressed = try compression.decompress(compressed);
        defer allocator.free(decompressed);

        const ratio = @as(f64, @floatFromInt(compressed.len)) / @as(f64, @floatFromInt(original.len)) * 100;
        const verified = std.mem.eql(u8, original, decompressed);

        std.debug.print("Test {d}: {d} -> {d} bytes ({d:.1}%) - {s}\n", .{
            i + 1,
            original.len,
            compressed.len,
            ratio,
            if (verified) "OK" else "FAIL",
        });
    }
}
```

## Running the Example

```bash
zig build run-compression-demo
```

## Expected Output

```
Logly Compression Demo
======================

Test 1: 1400 -> 28 bytes (2.0%) - OK
Test 2: 46 -> 12 bytes (26.1%) - OK
Test 3: 45 -> 47 bytes (104.4%) - OK
```

## Key Concepts

### Centralized Configuration

```zig
var config = logly.Config.default();
config.compression = logly.CompressionConfig{
    .algorithm = .lz77_rle,
    .level = 6,
    .window_size = 32768,
    .enable_checksums = true,
};

// Or use helper method
var config2 = logly.Config.default().withCompression(.{
    .algorithm = .lz77_rle,
    .level = 6,
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
