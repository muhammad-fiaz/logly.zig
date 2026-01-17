const std = @import("std");
const logly = @import("logly");

const Compression = logly.Compression;
const CompressionPresets = logly.CompressionPresets;

/// Demonstrates comprehensive compression capabilities including batch operations,
/// pattern-based compression, and integration with scheduling.
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n", .{});
    std.debug.print("Logly Compression Demo v0.1.5\n", .{});
    std.debug.print("Featuring zstd, batch, and pattern compression\n\n", .{});

    // Initialize compression with default settings
    var comp = Compression.init(allocator);
    defer comp.deinit();

    // Test 1: Compress simple text
    std.debug.print("Test 1: Simple Text Compression\n", .{});
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
    std.debug.print("\nTest 2: Repetitive Data (RLE)\n", .{});
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
    std.debug.print("\nTest 3: Log-like Data (LZ77)\n", .{});
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
    std.debug.print("\nTest 4: Compression Levels\n", .{});
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
    std.debug.print("\nTest 5: Compression Statistics\n", .{});
    const stats = comp.getStats();
    std.debug.print("  Files compressed:   {}\n", .{stats.getFilesCompressed()});
    std.debug.print("  Files decompressed: {}\n", .{stats.getFilesDecompressed()});
    std.debug.print("  Bytes before:       {} bytes\n", .{stats.getBytesBefore()});
    std.debug.print("  Bytes after:        {} bytes\n", .{stats.getBytesAfter()});
    std.debug.print("  Overall ratio:      {d:.1}%\n", .{stats.compressionRatio() * 100});

    // Test 6: File compression (creates test file)
    std.debug.print("\nTest 6: File Compression\n", .{});

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

    // Test 7: Streaming Compression
    std.debug.print("\nTest 7: Streaming Compression\n", .{});
    const stream_data = "Streaming compression test data " ** 20;

    var in_stream = std.io.fixedBufferStream(stream_data);
    var out_buffer: std.ArrayList(u8) = .empty;
    defer out_buffer.deinit(allocator);

    try comp.compressStream(in_stream.reader(), out_buffer.writer(allocator));

    std.debug.print("  Streamed Input: {} bytes\n", .{stream_data.len});
    std.debug.print("  Streamed Output: {} bytes\n", .{out_buffer.items.len});

    var result_buffer: std.ArrayList(u8) = .empty;
    defer result_buffer.deinit(allocator);
    var compressed_stream = std.io.fixedBufferStream(out_buffer.items);

    try comp.decompressStream(compressed_stream.reader(), result_buffer.writer(allocator));
    const stream_match = std.mem.eql(u8, stream_data, result_buffer.items);
    std.debug.print("  Stream Roundtrip: {s}\n", .{if (stream_match) "OK" else "FAILED"});

    // Test 8: Batch Compression with Multiple Files
    std.debug.print("\nTest 8: Batch Compression\n", .{});

    const test_dir = "logs_test_batch";
    std.fs.cwd().makeDir(test_dir) catch {};

    // Create multiple test files
    var i: usize = 0;
    while (i < 5) : (i += 1) {
        const name = std.fmt.allocPrint(allocator, "{s}/batch_{d}.log", .{ test_dir, i }) catch continue;
        defer allocator.free(name);
        const f = std.fs.cwd().createFile(name, .{}) catch continue;
        // Create repeated content for compression testing
        const base_content = "Log file content with some repeated data for compression test ";
        var content_buf: [1024]u8 = undefined;
        var pos: usize = 0;
        for (0..10) |_| {
            const len = @min(base_content.len, content_buf.len - pos);
            @memcpy(content_buf[pos..][0..len], base_content[0..len]);
            pos += len;
        }
        f.writeAll(content_buf[0..pos]) catch {};
        f.close();
    }
    std.debug.print("  Created 5 test files in {s}/\n", .{test_dir});

    // Batch compress files using pattern matching
    const pattern_count = comp.compressPattern(test_dir, "*.log") catch 0;
    std.debug.print("  Compressed {} files matching *.log\n", .{pattern_count});

    // Test 9: Compression Utility Functions
    std.debug.print("\nTest 9: Utility Functions\n", .{});

    std.debug.print("  Algorithm: {s}\n", .{comp.algorithmName()});
    std.debug.print("  Level: {s}\n", .{comp.levelName()});
    std.debug.print("  Extension: {s}\n", .{comp.getExtension()});
    std.debug.print("  Is zstd: {}\n", .{comp.isZstd()});
    std.debug.print("  Estimated size (10KB): {} bytes\n", .{comp.estimateCompressedSize(10240)});

    // Test using aliases
    std.debug.print("\nTest 10: Compression Aliases\n", .{});
    const alias_data = "Testing compression aliases encode/decode, deflate/inflate";

    // Using encode/decode aliases
    const encoded = try Compression.encode(&comp, alias_data);
    defer allocator.free(encoded);
    const decoded = try Compression.decode(&comp, encoded);
    defer allocator.free(decoded);
    std.debug.print("  encode/decode roundtrip: {s}\n", .{if (std.mem.eql(u8, alias_data, decoded)) "OK" else "FAILED"});

    // Test 11: zstd Compression (if available)
    std.debug.print("\nTest 11: zstd Compression\n", .{});
    var zstd_comp = Compression.zstdCompression(allocator);
    defer zstd_comp.deinit();

    const zstd_data = "zstd provides excellent compression ratios for log data " ** 50;
    if (zstd_comp.isZstd()) {
        const zstd_compressed = zstd_comp.compress(zstd_data) catch |e| {
            std.debug.print("  zstd compression error: {}\n", .{e});
            return;
        };
        defer allocator.free(zstd_compressed);

        const zstd_ratio = 100.0 - (@as(f64, @floatFromInt(zstd_compressed.len)) / @as(f64, @floatFromInt(zstd_data.len)) * 100.0);
        std.debug.print("  Original:   {} bytes\n", .{zstd_data.len});
        std.debug.print("  Compressed: {} bytes\n", .{zstd_compressed.len});
        std.debug.print("  Saved:      {d:.1}%\n", .{zstd_ratio});

        const zstd_decompressed = zstd_comp.decompress(zstd_compressed) catch |e| {
            std.debug.print("  zstd decompression error: {}\n", .{e});
            return;
        };
        defer allocator.free(zstd_decompressed);
        std.debug.print("  Roundtrip:  {s}\n", .{if (std.mem.eql(u8, zstd_data, zstd_decompressed)) "OK" else "FAILED"});
    } else {
        std.debug.print("  zstd not enabled for this configuration\n", .{});
    }

    // Test 12: Compression Presets (using Compression factory methods)
    std.debug.print("\nTest 12: Compression Presets\n", .{});
    const preset_data = "Testing compression presets with various configurations " ** 30;

    // Test using Compression factory methods (these take allocator)
    {
        var fast_comp = Compression.fast(allocator);
        defer fast_comp.deinit();
        const fast_compressed = fast_comp.compress(preset_data) catch null;
        if (fast_compressed) |fc| {
            defer allocator.free(fc);
            const ratio = 100.0 - (@as(f64, @floatFromInt(fc.len)) / @as(f64, @floatFromInt(preset_data.len)) * 100.0);
            std.debug.print("  fast:       {} -> {} bytes ({d:.1}% saved)\n", .{ preset_data.len, fc.len, ratio });
        }
    }

    {
        var balanced_comp = Compression.balanced(allocator);
        defer balanced_comp.deinit();
        const balanced_compressed = balanced_comp.compress(preset_data) catch null;
        if (balanced_compressed) |bc| {
            defer allocator.free(bc);
            const ratio = 100.0 - (@as(f64, @floatFromInt(bc.len)) / @as(f64, @floatFromInt(preset_data.len)) * 100.0);
            std.debug.print("  balanced:   {} -> {} bytes ({d:.1}% saved)\n", .{ preset_data.len, bc.len, ratio });
        }
    }

    {
        var best_comp = Compression.best(allocator);
        defer best_comp.deinit();
        const best_compressed = best_comp.compress(preset_data) catch null;
        if (best_compressed) |bc| {
            defer allocator.free(bc);
            const ratio = 100.0 - (@as(f64, @floatFromInt(bc.len)) / @as(f64, @floatFromInt(preset_data.len)) * 100.0);
            std.debug.print("  best:       {} -> {} bytes ({d:.1}% saved)\n", .{ preset_data.len, bc.len, ratio });
        }
    }

    {
        var logs_comp = Compression.forLogs(allocator);
        defer logs_comp.deinit();
        const logs_compressed = logs_comp.compress(preset_data) catch null;
        if (logs_compressed) |lc| {
            defer allocator.free(lc);
            const ratio = 100.0 - (@as(f64, @floatFromInt(lc.len)) / @as(f64, @floatFromInt(preset_data.len)) * 100.0);
            std.debug.print("  forLogs:    {} -> {} bytes ({d:.1}% saved)\n", .{ preset_data.len, lc.len, ratio });
        }
    }

    {
        var archive_comp = Compression.archive(allocator);
        defer archive_comp.deinit();
        const archive_compressed = archive_comp.compress(preset_data) catch null;
        if (archive_compressed) |ac| {
            defer allocator.free(ac);
            const ratio = 100.0 - (@as(f64, @floatFromInt(ac.len)) / @as(f64, @floatFromInt(preset_data.len)) * 100.0);
            std.debug.print("  archive:    {} -> {} bytes ({d:.1}% saved)\n", .{ preset_data.len, ac.len, ratio });
        }
    }

    std.debug.print("\nCompression Demo Complete!\n", .{});
    std.debug.print("Files created: test_compression.log, test_compression.log.lgz\n", .{});
    std.debug.print("Test directory: {s}/\n", .{test_dir});
}
