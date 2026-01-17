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
    std.debug.print("   Bytes before compression: {d}\n", .{stats.getBytesBefore()});
    std.debug.print("   Bytes after compression: {d}\n", .{stats.getBytesAfter()});
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

    // Example 7: Zstd Compression (v0.1.5+)
    std.debug.print("7. Zstd Compression (v0.1.5+)\n", .{});
    std.debug.print("   ---------------------------\n", .{});

    var zstd_comp = logly.Compression.zstdCompression(allocator);
    defer zstd_comp.deinit();

    const zstd_data = "Data compressed with Zstandard algorithm - very fast decompression! " ** 5;
    std.debug.print("   Original size: {d} bytes\n", .{zstd_data.len});

    const zstd_compressed = try zstd_comp.compress(zstd_data);
    defer allocator.free(zstd_compressed);
    std.debug.print("   Zstd compressed size: {d} bytes\n", .{zstd_compressed.len});

    const zstd_decompressed = try zstd_comp.decompress(zstd_compressed);
    defer allocator.free(zstd_decompressed);
    std.debug.print("   Zstd decompressed: {d} bytes\n", .{zstd_decompressed.len});
    std.debug.print("   Data integrity: {s}\n", .{if (std.mem.eql(u8, zstd_data, zstd_decompressed)) "✓ Verified" else "✗ Failed"});

    // Show zstd preset options
    std.debug.print("   Zstd presets available:\n", .{});
    std.debug.print("     - zstdCompression(): Default (level 6)\n", .{});
    std.debug.print("     - zstdFast(): Speed priority (level 1)\n", .{});
    std.debug.print("     - zstdBest(): Best ratio (level 19)\n", .{});
    std.debug.print("     - zstdProduction(): Background + checksums\n", .{});
    std.debug.print("     - zstdWithLevel(N): Custom level (1-22)\n\n", .{});

    // Example 8: Zstd Custom Levels (v0.1.5+)
    std.debug.print("8. Zstd Custom Levels (v0.1.5+)\n", .{});
    std.debug.print("   ----------------------------\n", .{});

    // Test custom zstd level 15
    var zstd_custom = logly.Compression.zstdWithLevel(allocator, 15);
    defer zstd_custom.deinit();

    const custom_data = "Custom zstd level compression test data " ** 10;
    std.debug.print("   Original size: {d} bytes\n", .{custom_data.len});

    const custom_compressed = try zstd_custom.compress(custom_data);
    defer allocator.free(custom_compressed);
    std.debug.print("   Custom level 15 compressed: {d} bytes\n", .{custom_compressed.len});

    // Show effective level
    std.debug.print("   Effective zstd level: {d}\n", .{zstd_custom.config.getEffectiveZstdLevel()});

    // Compare compression levels
    std.debug.print("   Level comparison:\n", .{});
    std.debug.print("     Level 1 (fastest):  Speed priority, larger files\n", .{});
    std.debug.print("     Level 6 (default):  Balanced speed/ratio\n", .{});
    std.debug.print("     Level 15 (custom):  Good ratio, slower\n", .{});
    std.debug.print("     Level 19 (best):    Best ratio, slowest\n", .{});
    std.debug.print("     Level 22 (ultra):   Maximum compression\n\n", .{});

    // Example 9: Zstd Config Presets (v0.1.5+)
    std.debug.print("9. Zstd Config Presets (v0.1.5+)\n", .{});
    std.debug.print("   -----------------------------\n", .{});

    const zstd_config = logly.Config.CompressionConfig.zstd();
    std.debug.print("   zstd() preset:\n", .{});
    std.debug.print("     Algorithm: {s}\n", .{@tagName(zstd_config.algorithm)});
    std.debug.print("     Level: {s}\n", .{@tagName(zstd_config.level)});
    std.debug.print("     Extension: {s}\n", .{zstd_config.extension});
    std.debug.print("     Checksum: {s}\n", .{if (zstd_config.checksum) "enabled" else "disabled"});

    const zstd_prod = logly.Config.CompressionConfig.zstdProduction();
    std.debug.print("   zstdProduction() preset:\n", .{});
    std.debug.print("     Background: {s}\n", .{if (zstd_prod.background) "enabled" else "disabled"});
    std.debug.print("     Keep original: {s}\n\n", .{if (zstd_prod.keep_original) "yes" else "no"});

    // Example 10: Compression Aliases (v0.1.5+)
    std.debug.print("10. Compression Aliases (v0.1.5+)\n", .{});
    std.debug.print("    ------------------------------\n", .{});

    var alias_comp = logly.Compression.create(allocator); // Alias for init()
    defer alias_comp.destroy(); // Alias for deinit()

    const alias_data = "Testing compression aliases";

    // Use encode/decode aliases
    const encoded = try alias_comp.encode(alias_data);
    defer allocator.free(encoded);
    const decoded = try alias_comp.decode(encoded);
    defer allocator.free(decoded);
    std.debug.print("    encode/decode aliases: {s}\n", .{if (std.mem.eql(u8, alias_data, decoded)) "✓ Working" else "✗ Failed"});

    // Use deflate/inflate aliases
    const deflated = try alias_comp.deflate(alias_data);
    defer allocator.free(deflated);
    const inflated = try alias_comp.inflate(deflated);
    defer allocator.free(inflated);
    std.debug.print("    deflate/inflate aliases: {s}\n", .{if (std.mem.eql(u8, alias_data, inflated)) "✓ Working" else "✗ Failed"});

    // Check needsCompression alias
    const needs = alias_comp.needsCompression("test.log");
    std.debug.print("    needsCompression('test.log'): {s}\n", .{if (needs) "true" else "false"});
    const no_needs = alias_comp.needsCompression("test.log.gz");
    std.debug.print("    needsCompression('test.log.gz'): {s}\n\n", .{if (no_needs) "true" else "false"});

    // Example 11: Streaming Compression
    std.debug.print("11. Streaming Compression\n", .{});
    std.debug.print("    ---------------------\n", .{});

    var stream_comp = logly.Compression.init(allocator);
    defer stream_comp.deinit();

    const stream_data = "Data to be compressed via stream" ** 5;
    var input_stream = std.io.fixedBufferStream(stream_data);
    var output_buffer: std.ArrayList(u8) = .empty;
    defer output_buffer.deinit(allocator);

    try stream_comp.compressStream(input_stream.reader(), output_buffer.writer(allocator));
    std.debug.print("    Stream compressed size: {d} bytes\n", .{output_buffer.items.len});

    var decomp_input = std.io.fixedBufferStream(output_buffer.items);
    var decomp_output: std.ArrayList(u8) = .empty;
    defer decomp_output.deinit(allocator);

    try stream_comp.decompressStream(decomp_input.reader(), decomp_output.writer(allocator));
    std.debug.print("    Stream decompressed verified: {s}\n\n", .{if (std.mem.eql(u8, stream_data, decomp_output.items)) "✓ Yes" else "✗ No"});

    // Example 12: Directory Compression
    std.debug.print("12. Directory Compression\n", .{});
    std.debug.print("    ---------------------\n", .{});

    // Create dummy logs for directory compression test
    const test_dir = "logs_test_batch";
    std.fs.cwd().makePath(test_dir) catch {};
    // defer {
    //    // Cleanup compressed files
    //    std.fs.cwd().deleteTree(test_dir) catch {};
    // }

    const log1 = try std.fs.cwd().createFile(test_dir ++ "/app.log", .{});
    try log1.writeAll("Application log data 1");
    log1.close();

    const log2 = try std.fs.cwd().createFile(test_dir ++ "/error.log", .{});
    try log2.writeAll("Error log data 2");
    log2.close();

    var batch_comp = logly.Compression.init(allocator);
    defer batch_comp.deinit();

    const files_processed = try batch_comp.compressDirectory(test_dir);
    std.debug.print("    Batch compressed {d} files in '{s}'\n\n", .{ files_processed, test_dir });

    std.debug.print("=== Compression Example Complete ===\n", .{});
}
