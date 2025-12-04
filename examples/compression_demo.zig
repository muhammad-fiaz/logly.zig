const std = @import("std");
const logly = @import("logly");

const Compression = logly.Compression;
const CompressionPresets = logly.CompressionPresets;

/// Demonstrates real compression capabilities with LZ77 + RLE algorithm.
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n", .{});
    std.debug.print("========================================\n", .{});
    std.debug.print("  Logly Compression Demo - LZ77 + RLE\n", .{});
    std.debug.print("========================================\n\n", .{});

    // Initialize compression with default settings
    var comp = Compression.init(allocator);
    defer comp.deinit();

    // Test 1: Compress simple text
    std.debug.print("--- Test 1: Simple Text Compression ---\n", .{});
    const simple_text = "Hello, World! This is a test of the Logly compression system.";
    const compressed1 = try comp.compress(simple_text);
    defer allocator.free(compressed1);

    std.debug.print("  Original:   {} bytes\n", .{simple_text.len});
    std.debug.print("  Compressed: {} bytes\n", .{compressed1.len});

    // Verify roundtrip
    const decompressed1 = try comp.decompress(compressed1);
    defer allocator.free(decompressed1);
    const match1 = std.mem.eql(u8, simple_text, decompressed1);
    std.debug.print("  Roundtrip:  {s}\n", .{if (match1) "OK" else "FAILED"});

    // Test 2: Compress repetitive data (RLE shines here)
    std.debug.print("\n--- Test 2: Repetitive Data (RLE) ---\n", .{});
    const repetitive = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA" ++
        "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB" ++
        "CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC";
    const compressed2 = try comp.compress(repetitive);
    defer allocator.free(compressed2);

    const ratio2 = 100.0 - (@as(f64, @floatFromInt(compressed2.len)) / @as(f64, @floatFromInt(repetitive.len)) * 100.0);
    std.debug.print("  Original:     {} bytes\n", .{repetitive.len});
    std.debug.print("  Compressed:   {} bytes\n", .{compressed2.len});
    std.debug.print("  Space saved:  {d:.1}%\n", .{ratio2});

    const decompressed2 = try comp.decompress(compressed2);
    defer allocator.free(decompressed2);
    const match2 = std.mem.eql(u8, repetitive, decompressed2);
    std.debug.print("  Roundtrip:    {s}\n", .{if (match2) "OK" else "FAILED"});

    // Test 3: Compress log-like data (LZ77 finds patterns)
    std.debug.print("\n--- Test 3: Log-like Data (LZ77) ---\n", .{});
    const log_data =
        \\[2025-01-15 10:00:00] INFO  Application started successfully
        \\[2025-01-15 10:00:01] DEBUG Processing request from user 12345
        \\[2025-01-15 10:00:02] INFO  Database connection established
        \\[2025-01-15 10:00:03] DEBUG Processing request from user 12346
        \\[2025-01-15 10:00:04] INFO  Cache hit ratio: 95.5%
        \\[2025-01-15 10:00:05] DEBUG Processing request from user 12347
        \\[2025-01-15 10:00:06] WARNING Slow query detected: 250ms
        \\[2025-01-15 10:00:07] DEBUG Processing request from user 12348
        \\[2025-01-15 10:00:08] ERROR Connection timeout to external service
        \\[2025-01-15 10:00:09] DEBUG Processing request from user 12349
    ;
    const compressed3 = try comp.compress(log_data);
    defer allocator.free(compressed3);

    const ratio3 = 100.0 - (@as(f64, @floatFromInt(compressed3.len)) / @as(f64, @floatFromInt(log_data.len)) * 100.0);
    std.debug.print("  Original:     {} bytes\n", .{log_data.len});
    std.debug.print("  Compressed:   {} bytes\n", .{compressed3.len});
    std.debug.print("  Space saved:  {d:.1}%\n", .{ratio3});

    const decompressed3 = try comp.decompress(compressed3);
    defer allocator.free(decompressed3);
    const match3 = std.mem.eql(u8, log_data, decompressed3);
    std.debug.print("  Roundtrip:    {s}\n", .{if (match3) "OK" else "FAILED"});

    // Test 4: Different compression levels
    std.debug.print("\n--- Test 4: Compression Levels ---\n", .{});
    const test_data = "The quick brown fox jumps over the lazy dog. " ** 50;

    inline for ([_]struct { name: []const u8, level: Compression.Level }{
        .{ .name = "None", .level = .none },
        .{ .name = "Fast", .level = .fast },
        .{ .name = "Default", .level = .default },
        .{ .name = "Best", .level = .best },
    }) |config| {
        var level_comp = Compression.initWithConfig(allocator, .{ .level = config.level });
        defer level_comp.deinit();

        const compressed = try level_comp.compress(test_data);
        defer allocator.free(compressed);

        const level_ratio = 100.0 - (@as(f64, @floatFromInt(compressed.len)) / @as(f64, @floatFromInt(test_data.len)) * 100.0);
        std.debug.print("  {s:8}: {} -> {} bytes ({d:.1}% saved)\n", .{ config.name, test_data.len, compressed.len, level_ratio });
    }

    // Test 5: Compression stats
    std.debug.print("\n--- Test 5: Compression Statistics ---\n", .{});
    const stats = comp.getStats();
    std.debug.print("  Files compressed:   {}\n", .{stats.files_compressed});
    std.debug.print("  Files decompressed: {}\n", .{stats.files_decompressed});
    std.debug.print("  Bytes before:       {} bytes\n", .{stats.bytes_before});
    std.debug.print("  Bytes after:        {} bytes\n", .{stats.bytes_after});
    std.debug.print("  Overall ratio:      {d:.1}%\n", .{stats.compressionRatio() * 100});

    // Test 6: File compression (creates test file)
    std.debug.print("\n--- Test 6: File Compression ---\n", .{});

    // Create a test log file
    const test_file = std.fs.cwd().createFile("test_compression.log", .{}) catch |err| {
        std.debug.print("  Could not create test file: {}\n", .{err});
        return;
    };

    // Write sample log data
    const sample_logs =
        \\[2025-01-15 10:00:00] INFO  Server starting up...
        \\[2025-01-15 10:00:01] INFO  Loading configuration from config.json
        \\[2025-01-15 10:00:02] DEBUG Parsed 42 configuration options
        \\[2025-01-15 10:00:03] INFO  Initializing database connection pool
        \\[2025-01-15 10:00:04] DEBUG Created 10 database connections
        \\[2025-01-15 10:00:05] INFO  Starting HTTP server on port 8080
        \\[2025-01-15 10:00:06] INFO  Server ready to accept connections
        \\
    ** 100;
    test_file.writeAll(sample_logs) catch |err| {
        std.debug.print("  Could not write test file: {}\n", .{err});
        test_file.close();
        return;
    };
    test_file.close();

    std.debug.print("  Created test_compression.log ({} bytes)\n", .{sample_logs.len});

    // Compress the file
    const file_result = try comp.compressFile("test_compression.log", "test_compression.log.lgz");
    if (file_result.output_path) |out_path| {
        allocator.free(out_path);
    }

    if (file_result.success) {
        const file_ratio = 100.0 - (@as(f64, @floatFromInt(file_result.compressed_size)) / @as(f64, @floatFromInt(file_result.original_size)) * 100.0);
        std.debug.print("  Compressed to test_compression.log.lgz\n", .{});
        std.debug.print("  Original:   {} bytes\n", .{file_result.original_size});
        std.debug.print("  Compressed: {} bytes\n", .{file_result.compressed_size});
        std.debug.print("  Saved:      {d:.1}%\n", .{file_ratio});
    } else {
        std.debug.print("  Compression failed: {s}\n", .{file_result.error_message orelse "Unknown error"});
    }

    // Cleanup test files
    std.fs.cwd().deleteFile("test_compression.log") catch {};
    std.fs.cwd().deleteFile("test_compression.log.lgz") catch {};

    std.debug.print("\n========================================\n", .{});
    std.debug.print("  Compression Demo Complete!\n", .{});
    std.debug.print("========================================\n", .{});
}
