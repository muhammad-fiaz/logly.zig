//! Compression Example
//!
//! Demonstrates how to use log compression features in Logly.
//! Includes automatic compression on rotation and manual compression.

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

    // Example 2: Using compression presets
    std.debug.print("2. Compression Presets\n", .{});
    std.debug.print("   -------------------\n", .{});

    const fast_config = logly.CompressionPresets.fast();
    std.debug.print("   Fast preset - Level: {s}, Mode: {s}\n", .{
        @tagName(fast_config.level),
        @tagName(fast_config.mode),
    });

    const balanced_config = logly.CompressionPresets.balanced();
    std.debug.print("   Balanced preset - Level: {s}, Mode: {s}\n", .{
        @tagName(balanced_config.level),
        @tagName(balanced_config.mode),
    });

    const max_config = logly.CompressionPresets.maximum();
    std.debug.print("   Maximum preset - Level: {s}, Mode: {s}\n\n", .{
        @tagName(max_config.level),
        @tagName(max_config.mode),
    });

    // Example 3: Custom compression configuration
    std.debug.print("3. Custom Compression Configuration\n", .{});
    std.debug.print("   ---------------------------------\n", .{});

    var custom_comp = logly.Compression.initWithConfig(allocator, .{
        .algorithm = .deflate,
        .level = .best,
        .mode = .on_rotation,
        .size_threshold = 5 * 1024 * 1024, // 5MB
        .extension = ".gz",
        .keep_original = false,
        .checksum = true,
    });
    defer custom_comp.deinit();

    std.debug.print("   Algorithm: {s}\n", .{@tagName(custom_comp.config.algorithm)});
    std.debug.print("   Level: {s}\n", .{@tagName(custom_comp.config.level)});
    std.debug.print("   Mode: {s}\n", .{@tagName(custom_comp.config.mode)});
    std.debug.print("   Size threshold: {d} bytes\n", .{custom_comp.config.size_threshold});
    std.debug.print("   Extension: {s}\n\n", .{custom_comp.config.extension});

    // Example 4: Compression statistics
    std.debug.print("4. Compression Statistics\n", .{});
    std.debug.print("   -----------------------\n", .{});

    // Compress some data to generate stats
    const data1 = "Log entry 1: Application started successfully\n" ** 50;
    const data2 = "Log entry 2: Processing request from user\n" ** 50;

    const c1 = try custom_comp.compress(data1);
    defer allocator.free(c1);
    const c2 = try custom_comp.compress(data2);
    defer allocator.free(c2);

    const stats = custom_comp.getStats();
    std.debug.print("   Bytes before compression: {d}\n", .{stats.bytes_before});
    std.debug.print("   Bytes after compression: {d}\n", .{stats.bytes_after});
    std.debug.print("   Compression ratio: {d:.2}%\n\n", .{stats.compressionRatio() * 100});

    // Example 5: Size-based compression trigger
    std.debug.print("5. Size-Based Compression Trigger\n", .{});
    std.debug.print("   -------------------------------\n", .{});

    const size_config = logly.CompressionPresets.onSize(10); // 10MB threshold
    std.debug.print("   Threshold: {d} bytes ({d} MB)\n", .{
        size_config.size_threshold,
        size_config.size_threshold / (1024 * 1024),
    });
    std.debug.print("   Mode: {s}\n\n", .{@tagName(size_config.mode)});

    std.debug.print("=== Compression Example Complete ===\n", .{});
}
