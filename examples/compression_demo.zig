const std = @import("std");
const logly = @import("logly");

const Compression = logly.Compression;
const CompressionPresets = logly.CompressionPresets;

/// Comprehensive compression demo for Logly v0.1.6
/// Demonstrates all compression algorithms: deflate, gzip, zlib, zstd, lzma, lzma2, xz, zip, tar.gz, lz4
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n", .{});
    std.debug.print("=" ** 70 ++ "\n", .{});
    std.debug.print("  Logly Compression Demo v0.1.6\n", .{});
    std.debug.print("  All Compression Algorithms: deflate, gzip, zstd, lzma, xz, zip, tar.gz, lz4\n", .{});
    std.debug.print("=" ** 70 ++ "\n\n", .{});

    const log_dir = "logs";
    std.fs.cwd().makePath(log_dir) catch {};

    // Create sample log data
    const sample_log =
        \\[2026-01-19 19:30:00] INFO  Application started successfully
        \\[2026-01-19 19:30:01] DEBUG Loading configuration from config.json
        \\[2026-01-19 19:30:02] INFO  Database connection established
        \\[2026-01-19 19:30:03] DEBUG Processing request from user 12345
        \\[2026-01-19 19:30:04] INFO  Cache initialized with 1024 entries
        \\[2026-01-19 19:30:05] WARNING High memory usage detected: 85%
        \\[2026-01-19 19:30:06] ERROR Connection timeout to external service
        \\[2026-01-19 19:30:07] INFO  Retry successful after 3 attempts
        \\
    ** 50;

    std.debug.print("Sample log data: {} bytes\n\n", .{sample_log.len});

    // =========================================================================
    // Test 1: DEFLATE (Default)
    // =========================================================================
    std.debug.print("Test 1: DEFLATE Compression (Default)\n", .{});
    std.debug.print("-" ** 50 ++ "\n", .{});
    {
        var comp = Compression.init(allocator);
        defer comp.deinit();

        const compressed = try comp.compress(sample_log);
        defer allocator.free(compressed);

        const decompressed = try comp.decompress(compressed);
        defer allocator.free(decompressed);

        const ratio = 100.0 - (@as(f64, @floatFromInt(compressed.len)) / @as(f64, @floatFromInt(sample_log.len)) * 100.0);
        std.debug.print("  Original:    {} bytes\n", .{sample_log.len});
        std.debug.print("  Compressed:  {} bytes\n", .{compressed.len});
        std.debug.print("  Saved:       {d:.1}%\n", .{ratio});
        std.debug.print("  Roundtrip:   {s}\n\n", .{if (std.mem.eql(u8, sample_log, decompressed)) "✓ OK" else "✗ FAILED"});
    }

    // =========================================================================
    // Test 2: GZIP
    // =========================================================================
    std.debug.print("Test 2: GZIP Compression\n", .{});
    std.debug.print("-" ** 50 ++ "\n", .{});
    {
        var comp = Compression.initWithConfig(allocator, .{ .algorithm = .gzip });
        defer comp.deinit();

        const compressed = try comp.compress(sample_log);
        defer allocator.free(compressed);

        const decompressed = try comp.decompress(compressed);
        defer allocator.free(decompressed);

        const ratio = 100.0 - (@as(f64, @floatFromInt(compressed.len)) / @as(f64, @floatFromInt(sample_log.len)) * 100.0);
        std.debug.print("  Original:    {} bytes\n", .{sample_log.len});
        std.debug.print("  Compressed:  {} bytes\n", .{compressed.len});
        std.debug.print("  Saved:       {d:.1}%\n", .{ratio});
        std.debug.print("  Roundtrip:   {s}\n\n", .{if (std.mem.eql(u8, sample_log, decompressed)) "✓ OK" else "✗ FAILED"});
    }

    // =========================================================================
    // Test 3: ZSTD
    // =========================================================================
    std.debug.print("Test 3: ZSTD Compression (v0.1.5+)\n", .{});
    std.debug.print("-" ** 50 ++ "\n", .{});
    {
        var comp = Compression.zstdCompression(allocator);
        defer comp.deinit();

        const compressed = try comp.compress(sample_log);
        defer allocator.free(compressed);

        const decompressed = try comp.decompress(compressed);
        defer allocator.free(decompressed);

        const ratio = 100.0 - (@as(f64, @floatFromInt(compressed.len)) / @as(f64, @floatFromInt(sample_log.len)) * 100.0);
        std.debug.print("  Original:    {} bytes\n", .{sample_log.len});
        std.debug.print("  Compressed:  {} bytes\n", .{compressed.len});
        std.debug.print("  Saved:       {d:.1}%\n", .{ratio});
        std.debug.print("  Roundtrip:   {s}\n\n", .{if (std.mem.eql(u8, sample_log, decompressed)) "✓ OK" else "✗ FAILED"});
    }

    // =========================================================================
    // Test 4: LZMA (v0.1.6+)
    // =========================================================================
    std.debug.print("Test 4: LZMA Compression (v0.1.6+)\n", .{});
    std.debug.print("-" ** 50 ++ "\n", .{});
    {
        var comp = Compression.lzmaCompression(allocator);
        defer comp.deinit();

        const compressed = try comp.compress(sample_log);
        defer allocator.free(compressed);

        const decompressed = try comp.decompress(compressed);
        defer allocator.free(decompressed);

        const ratio = 100.0 - (@as(f64, @floatFromInt(compressed.len)) / @as(f64, @floatFromInt(sample_log.len)) * 100.0);
        std.debug.print("  Original:    {} bytes\n", .{sample_log.len});
        std.debug.print("  Compressed:  {} bytes\n", .{compressed.len});
        std.debug.print("  Saved:       {d:.1}%\n", .{ratio});
        std.debug.print("  Roundtrip:   {s}\n\n", .{if (std.mem.eql(u8, sample_log, decompressed)) "✓ OK" else "✗ FAILED"});
    }

    // =========================================================================
    // Test 5: LZMA2 (v0.1.6+)
    // =========================================================================
    std.debug.print("Test 5: LZMA2 Compression (v0.1.6+)\n", .{});
    std.debug.print("-" ** 50 ++ "\n", .{});
    {
        var comp = Compression.lzma2Compression(allocator);
        defer comp.deinit();

        const compressed = try comp.compress(sample_log);
        defer allocator.free(compressed);

        const decompressed = try comp.decompress(compressed);
        defer allocator.free(decompressed);

        const ratio = 100.0 - (@as(f64, @floatFromInt(compressed.len)) / @as(f64, @floatFromInt(sample_log.len)) * 100.0);
        std.debug.print("  Original:    {} bytes\n", .{sample_log.len});
        std.debug.print("  Compressed:  {} bytes\n", .{compressed.len});
        std.debug.print("  Saved:       {d:.1}%\n", .{ratio});
        std.debug.print("  Roundtrip:   {s}\n\n", .{if (std.mem.eql(u8, sample_log, decompressed)) "✓ OK" else "✗ FAILED"});
    }

    // =========================================================================
    // Test 6: XZ (v0.1.6+)
    // =========================================================================
    std.debug.print("Test 6: XZ Compression (v0.1.6+)\n", .{});
    std.debug.print("-" ** 50 ++ "\n", .{});
    {
        var comp = Compression.xzCompression(allocator);
        defer comp.deinit();

        const compressed = try comp.compress(sample_log);
        defer allocator.free(compressed);

        const decompressed = try comp.decompress(compressed);
        defer allocator.free(decompressed);

        const ratio = 100.0 - (@as(f64, @floatFromInt(compressed.len)) / @as(f64, @floatFromInt(sample_log.len)) * 100.0);
        std.debug.print("  Original:    {} bytes\n", .{sample_log.len});
        std.debug.print("  Compressed:  {} bytes\n", .{compressed.len});
        std.debug.print("  Saved:       {d:.1}%\n", .{ratio});
        std.debug.print("  Roundtrip:   {s}\n\n", .{if (std.mem.eql(u8, sample_log, decompressed)) "✓ OK" else "✗ FAILED"});
    }

    // =========================================================================
    // Test 7: ZIP (v0.1.6+)
    // =========================================================================
    std.debug.print("Test 7: ZIP Compression (v0.1.6+)\n", .{});
    std.debug.print("-" ** 50 ++ "\n", .{});
    {
        var comp = Compression.zipCompression(allocator);
        defer comp.deinit();

        const compressed = try comp.compress(sample_log);
        defer allocator.free(compressed);

        const decompressed = try comp.decompress(compressed);
        defer allocator.free(decompressed);

        const ratio = 100.0 - (@as(f64, @floatFromInt(compressed.len)) / @as(f64, @floatFromInt(sample_log.len)) * 100.0);
        std.debug.print("  Original:    {} bytes\n", .{sample_log.len});
        std.debug.print("  Compressed:  {} bytes\n", .{compressed.len});
        std.debug.print("  Saved:       {d:.1}%\n", .{ratio});
        std.debug.print("  Roundtrip:   {s}\n\n", .{if (std.mem.eql(u8, sample_log, decompressed)) "✓ OK" else "✗ FAILED"});
    }

    // =========================================================================
    // Test 8: TAR.GZ (v0.1.6+)
    // =========================================================================
    std.debug.print("Test 8: TAR.GZ Compression (v0.1.6+)\n", .{});
    std.debug.print("-" ** 50 ++ "\n", .{});
    {
        var comp = Compression.tarGzCompression(allocator);
        defer comp.deinit();

        const compressed = try comp.compress(sample_log);
        defer allocator.free(compressed);

        const decompressed = try comp.decompress(compressed);
        defer allocator.free(decompressed);

        const ratio = 100.0 - (@as(f64, @floatFromInt(compressed.len)) / @as(f64, @floatFromInt(sample_log.len)) * 100.0);
        std.debug.print("  Original:    {} bytes\n", .{sample_log.len});
        std.debug.print("  Compressed:  {} bytes\n", .{compressed.len});
        std.debug.print("  Saved:       {d:.1}%\n", .{ratio});
        std.debug.print("  Roundtrip:   {s}\n\n", .{if (std.mem.eql(u8, sample_log, decompressed)) "✓ OK" else "✗ FAILED"});
    }

    // =========================================================================
    // Test 9: LZ4 (v0.1.6+)
    // =========================================================================
    std.debug.print("Test 9: LZ4 Compression (v0.1.6+)\n", .{});
    std.debug.print("-" ** 50 ++ "\n", .{});
    {
        var comp = Compression.lz4Compression(allocator);
        defer comp.deinit();

        const compressed = try comp.compress(sample_log);
        defer allocator.free(compressed);

        const decompressed = try comp.decompress(compressed);
        defer allocator.free(decompressed);

        const ratio = 100.0 - (@as(f64, @floatFromInt(compressed.len)) / @as(f64, @floatFromInt(sample_log.len)) * 100.0);
        std.debug.print("  Original:    {} bytes\n", .{sample_log.len});
        std.debug.print("  Compressed:  {} bytes\n", .{compressed.len});
        std.debug.print("  Saved:       {d:.1}%\n", .{ratio});
        std.debug.print("  Roundtrip:   {s}\n\n", .{if (std.mem.eql(u8, sample_log, decompressed)) "✓ OK" else "✗ FAILED"});
    }

    // =========================================================================
    // Test 10: File Compression - Create actual compressed files
    // =========================================================================
    std.debug.print("Test 10: File Compression (Creates actual files)\n", .{});
    std.debug.print("-" ** 50 ++ "\n", .{});

    // Create log file
    const log_file_path = log_dir ++ "/app.log";
    {
        const f = try std.fs.cwd().createFile(log_file_path, .{});
        defer f.close();
        try f.writeAll(sample_log);
    }
    std.debug.print("  Created: {s} ({} bytes)\n", .{ log_file_path, sample_log.len });

    // Compress with different algorithms
    const algorithms = [_]struct { name: []const u8, factory: *const fn (std.mem.Allocator) Compression, ext: []const u8 }{
        .{ .name = "deflate", .factory = Compression.init, .ext = ".gz" },
        .{ .name = "zstd", .factory = Compression.zstdCompression, .ext = ".zst" },
        .{ .name = "lzma", .factory = Compression.lzmaCompression, .ext = ".lzma" },
        .{ .name = "xz", .factory = Compression.xzCompression, .ext = ".xz" },
        .{ .name = "zip", .factory = Compression.zipCompression, .ext = ".zip" },
        .{ .name = "tar.gz", .factory = Compression.tarGzCompression, .ext = ".tar.gz" },
        .{ .name = "lz4", .factory = Compression.lz4Compression, .ext = ".lz4" },
    };

    for (algorithms) |algo| {
        // Re-create log file for each algorithm since some might delete it
        {
            const f = try std.fs.cwd().createFile(log_file_path, .{});
            try f.writeAll(sample_log);
            f.close();
        }

        var comp = algo.factory(allocator);
        defer comp.deinit();

        const out_path = std.fmt.allocPrint(allocator, "{s}/app_{s}.log{s}", .{ log_dir, algo.name, algo.ext }) catch continue;
        defer allocator.free(out_path);

        const result = try comp.compressFile(log_file_path, out_path);
        if (result.output_path) |p| allocator.free(p);

        if (result.success) {
            std.debug.print("  {s:8}: {s} ({} bytes)\n", .{ algo.name, out_path, result.compressed_size });
        } else {
            std.debug.print("  {s:8}: FAILED ({s})\n", .{ algo.name, result.error_message orelse "unknown" });
        }
    }
    std.debug.print("\n", .{});

    // =========================================================================
    // Test 11: Compression Statistics
    // =========================================================================
    std.debug.print("Test 11: Compression Statistics\n", .{});
    std.debug.print("-" ** 50 ++ "\n", .{});
    {
        var comp = Compression.init(allocator);
        defer comp.deinit();

        // Run multiple compressions
        for (0..5) |_| {
            const c = try comp.compress(sample_log);
            allocator.free(c);
        }

        const stats = comp.getStats();
        std.debug.print("  Files compressed:   {}\n", .{stats.getFilesCompressed()});
        std.debug.print("  Bytes before:       {} bytes\n", .{stats.getBytesBefore()});
        std.debug.print("  Bytes after:        {} bytes\n", .{stats.getBytesAfter()});
        std.debug.print("  Overall ratio:      {d:.1}%\n", .{stats.compressionRatio() * 100});
    }

    std.debug.print("\n", .{});
    std.debug.print("=" ** 70 ++ "\n", .{});
    std.debug.print("  Compression Demo Complete!\n", .{});
    std.debug.print("  Log files created in: {s}/\n", .{log_dir});
    std.debug.print("=" ** 70 ++ "\n", .{});
}
