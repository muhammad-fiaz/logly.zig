const std = @import("std");
const logly = @import("logly");

/// Repeats `s` exactly `n` times, returning owned memory.
/// The caller owns the result and must free it.
fn repeatAlloc(allocator: std.mem.Allocator, s: []const u8, n: usize) ![]u8 {
    const out = try allocator.alloc(u8, s.len * n);
    for (0..n) |i| @memcpy(out[i * s.len ..][0..s.len], s);
    return out;
}

var threaded = std.Io.Threaded.init_single_threaded;
const io = threaded.io();

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\nLogly Compression Example\n\n", .{});

    // Example 1: Basic compression setup
    std.debug.print("1. Basic Compression Setup\n", .{});
    std.debug.print("\n", .{});

    var comp = logly.Compression.init(allocator);
    defer comp.deinit();

    const testData = try repeatAlloc(allocator, "This is test log data that will be compressed. ", 10);
    defer allocator.free(testData);
    std.debug.print("   Original data size: {d} bytes\n", .{testData.len});

    const compressed = try comp.compress(testData);
    defer allocator.free(compressed);
    std.debug.print("   Compressed size: {d} bytes\n", .{compressed.len});

    const decompressed = try comp.decompress(compressed);
    defer allocator.free(decompressed);
    std.debug.print("   Decompressed size: {d} bytes\n", .{decompressed.len});
    std.debug.print("   Data integrity: {s}\n\n", .{if (std.mem.eql(u8, testData, decompressed)) "[OK] Verified" else "[FAIL] Failed"});

    // Example 2: Using compression presets
    std.debug.print("2. Compression Presets\n", .{});
    std.debug.print("\n", .{});

    const fastConfig = logly.CompressionPresets.fast();
    std.debug.print("   Fast preset - Level: {s}, Mode: {s}\n", .{
        @tagName(fastConfig.level),
        @tagName(fastConfig.mode),
    });

    const balancedConfig = logly.CompressionPresets.balanced();
    std.debug.print("   Balanced preset - Level: {s}, Mode: {s}\n", .{
        @tagName(balancedConfig.level),
        @tagName(balancedConfig.mode),
    });

    const maxConfig = logly.CompressionPresets.maximum();
    std.debug.print("   Maximum preset - Level: {s}, Mode: {s}\n\n", .{
        @tagName(maxConfig.level),
        @tagName(maxConfig.mode),
    });

    // Example 3: Custom compression configuration
    std.debug.print("3. Custom Compression Configuration\n", .{});
    std.debug.print("\n", .{});

    var customComp = logly.Compression.initWithConfig(allocator, .{
        .algorithm = .deflate,
        .level = .best,
        .mode = .onRotation,
        .sizeThreshold = 5 * 1024 * 1024, // 5MB
        .extension = ".gz",
        .keepOriginal = false,
        .checksum = true,
    });
    defer customComp.deinit();

    std.debug.print("   Algorithm: {s}\n", .{@tagName(customComp.config.algorithm)});
    std.debug.print("   Level: {s}\n", .{@tagName(customComp.config.level)});
    std.debug.print("   Mode: {s}\n", .{@tagName(customComp.config.mode)});
    std.debug.print("   Size threshold: {d} bytes\n", .{customComp.config.sizeThreshold});
    std.debug.print("   Extension: {s}\n\n", .{customComp.config.extension});

    // Example 4: Compression statistics
    std.debug.print("4. Compression Statistics\n", .{});
    std.debug.print("\n", .{});

    // Compress some data to generate stats
    const data1 = try repeatAlloc(allocator, "Log entry 1: Application started successfully\n", 50);
    defer allocator.free(data1);
    const data2 = try repeatAlloc(allocator, "Log entry 2: Processing request from user\n", 50);
    defer allocator.free(data2);

    const c1 = try customComp.compress(data1);
    defer allocator.free(c1);
    const c2 = try customComp.compress(data2);
    defer allocator.free(c2);

    const stats = customComp.getStats();
    std.debug.print("   Bytes before compression: {d}\n", .{stats.getBytesBefore()});
    std.debug.print("   Bytes after compression: {d}\n", .{stats.getBytesAfter()});
    std.debug.print("   Compression ratio: {d:.2}%\n\n", .{stats.compressionRatio() * 100});

    // Example 5: Size-based compression trigger
    std.debug.print("5. Size-Based Compression Trigger\n", .{});
    std.debug.print("\n", .{});

    const sizeConfig = logly.CompressionPresets.onSize(10); // 10MB threshold
    std.debug.print("   Threshold: {d} bytes ({d} MB)\n", .{
        sizeConfig.sizeThreshold,
        sizeConfig.sizeThreshold / (1024 * 1024),
    });
    std.debug.print("   Mode: {s}\n\n", .{@tagName(sizeConfig.mode)});

    // Example 6: GZIP Algorithm
    std.debug.print("6. GZIP Algorithm\n", .{});
    std.debug.print("\n", .{});

    var gzipComp = logly.Compression.initWithConfig(allocator, .{
        .algorithm = .gzip,
        .level = .default,
    });
    defer gzipComp.deinit();

    const gzipData = "Data compressed with GZIP algorithm";
    const gzipCompressed = try gzipComp.compress(gzipData);
    defer allocator.free(gzipCompressed);

    std.debug.print("   GZIP compressed size: {d} bytes\n\n", .{gzipCompressed.len});

    // Example 7: Zstd Compression (v0.2.2+)
    std.debug.print("7. Zstd Compression (v0.2.2+)\n", .{});
    std.debug.print("\n", .{});

    var zstdComp = logly.Compression.zstdCompression(allocator);
    defer zstdComp.deinit();

    const zstdData = try repeatAlloc(allocator, "Data compressed with Zstandard algorithm - very fast decompression! ", 5);
    defer allocator.free(zstdData);
    std.debug.print("   Original size: {d} bytes\n", .{zstdData.len});

    const zstdCompressed = try zstdComp.compress(zstdData);
    defer allocator.free(zstdCompressed);
    std.debug.print("   Zstd compressed size: {d} bytes\n", .{zstdCompressed.len});

    const zstdDecompressed = try zstdComp.decompress(zstdCompressed);
    defer allocator.free(zstdDecompressed);
    std.debug.print("   Zstd decompressed: {d} bytes\n", .{zstdDecompressed.len});
    std.debug.print("   Data integrity: {s}\n", .{if (std.mem.eql(u8, zstdData, zstdDecompressed)) "[OK] Verified" else "[FAIL] Failed"});

    // Show zstd preset options
    std.debug.print("   Zstd presets available:\n", .{});
    std.debug.print("     - zstdCompression(): Default (level 6)\n", .{});
    std.debug.print("     - zstdFast(): Speed priority (level 1)\n", .{});
    std.debug.print("     - zstdBest(): Best ratio (level 19)\n", .{});
    std.debug.print("     - zstdProduction(): Background + checksums\n", .{});
    std.debug.print("     - zstdWithLevel(N): Custom level (1-22)\n\n", .{});

    // Example 8: Zstd Custom Levels (v0.2.2+)
    std.debug.print("8. Zstd Custom Levels (v0.2.2+)\n", .{});
    std.debug.print("\n", .{});

    // Test custom zstd level 15
    var zstdCustom = logly.Compression.zstdWithLevel(allocator, 15);
    defer zstdCustom.deinit();

    const customData = try repeatAlloc(allocator, "Custom zstd level compression test data ", 10);
    defer allocator.free(customData);
    std.debug.print("   Original size: {d} bytes\n", .{customData.len});

    const customCompressed = try zstdCustom.compress(customData);
    defer allocator.free(customCompressed);
    std.debug.print("   Custom level 15 compressed: {d} bytes\n", .{customCompressed.len});

    // Show effective level
    std.debug.print("   Effective zstd level: {d}\n", .{zstdCustom.config.getEffectiveZstdLevel()});

    // Compare compression levels
    std.debug.print("   Level comparison:\n", .{});
    std.debug.print("     Level 1 (fastest):  Speed priority, larger files\n", .{});
    std.debug.print("     Level 6 (default):  Balanced speed/ratio\n", .{});
    std.debug.print("     Level 15 (custom):  Good ratio, slower\n", .{});
    std.debug.print("     Level 19 (best):    Best ratio, slowest\n", .{});
    std.debug.print("     Level 22 (ultra):   Maximum compression\n\n", .{});

    // Example 9: Zstd Config Presets (v0.2.2+)
    std.debug.print("9. Zstd Config Presets (v0.2.2+)\n", .{});
    std.debug.print("\n", .{});

    const zstdConfig = logly.Config.CompressionConfig.zstd();
    std.debug.print("   zstd() preset:\n", .{});
    std.debug.print("     Algorithm: {s}\n", .{@tagName(zstdConfig.algorithm)});
    std.debug.print("     Level: {s}\n", .{@tagName(zstdConfig.level)});
    std.debug.print("     Extension: {s}\n", .{zstdConfig.extension});
    std.debug.print("     Checksum: {s}\n", .{if (zstdConfig.checksum) "enabled" else "disabled"});

    const zstdProd = logly.Config.CompressionConfig.zstdProduction();
    std.debug.print("   zstdProduction() preset:\n", .{});
    std.debug.print("     Background: {s}\n", .{if (zstdProd.background) "enabled" else "disabled"});
    std.debug.print("     Keep original: {s}\n\n", .{if (zstdProd.keepOriginal) "yes" else "no"});

    // Example 10: Compression Aliases (v0.2.2+)
    std.debug.print("10. Compression Aliases (v0.2.2+)\n", .{});
    std.debug.print("\n", .{});

    var aliasComp = logly.Compression.init(allocator); // Alias for init()
    defer aliasComp.deinit(); // Alias for deinit()

    const aliasData = "Testing compression aliases";

    // Use encode/decode aliases
    const encoded = try aliasComp.compress(aliasData);
    defer allocator.free(encoded);
    const decoded = try aliasComp.decompress(encoded);
    defer allocator.free(decoded);
    std.debug.print("    encode/decode aliases: {s}\n", .{if (std.mem.eql(u8, aliasData, decoded)) "[OK] Working" else "[FAIL] Failed"});

    // Use deflate/inflate aliases
    const deflated = try aliasComp.compress(aliasData);
    defer allocator.free(deflated);
    const inflated = try aliasComp.decompress(deflated);
    defer allocator.free(inflated);
    std.debug.print("    deflate/inflate aliases: {s}\n", .{if (std.mem.eql(u8, aliasData, inflated)) "[OK] Working" else "[FAIL] Failed"});

    // Check needsCompression alias
    const needs = aliasComp.shouldCompress("test.log");
    std.debug.print("    needsCompression('test.log'): {s}\n", .{if (needs) "true" else "false"});
    const noNeeds = aliasComp.shouldCompress("test.log.gz");
    std.debug.print("    needsCompression('test.log.gz'): {s}\n\n", .{if (noNeeds) "true" else "false"});

    // Example 11: Streaming Compression
    std.debug.print("11. Streaming Compression\n", .{});
    std.debug.print("\n", .{});

    var streamComp = logly.Compression.init(allocator);
    defer streamComp.deinit();

    const streamData = try repeatAlloc(allocator, "Data to be compressed via stream", 5);
    defer allocator.free(streamData);
    var inputReader = std.Io.Reader.fixed(streamData);
    var outputBuffer = std.Io.Writer.Allocating.init(allocator);
    defer outputBuffer.deinit();

    try streamComp.compressStream(&inputReader, &outputBuffer.writer);
    std.debug.print("    Stream compressed size: {d} bytes\n", .{outputBuffer.written().len});

    var decompInput = std.Io.Reader.fixed(outputBuffer.written());
    var decompOutput = std.Io.Writer.Allocating.init(allocator);
    defer decompOutput.deinit();

    try streamComp.decompressStream(&decompInput, &decompOutput.writer);
    const roundTripOk = std.mem.eql(u8, streamData, decompOutput.written());
    std.debug.print("    Stream decompressed verified: {s}\n\n", .{if (roundTripOk) "[OK] Yes" else "[FAIL] No"});

    // Example 12: Directory Compression
    std.debug.print("12. Directory Compression\n", .{});
    std.debug.print("\n", .{});

    // Create dummy logs for directory compression test
    const testDir = "logs_test_batch";
    std.Io.Dir.cwd().createDirPath(io, testDir) catch {};
    // defer {
    //    // Cleanup compressed files
    //    std.fs.cwd().deleteTree(test_dir) catch {};
    // }

    const log1 = try std.Io.Dir.cwd().createFile(io, testDir ++ "/app.log", .{});
    defer log1.close(io);
    try log1.writeStreamingAll(io, "Application log data 1");

    const log2 = try std.Io.Dir.cwd().createFile(io, testDir ++ "/error.log", .{});
    defer log2.close(io);
    try log2.writeStreamingAll(io, "Error log data 2");

    var batchComp = logly.Compression.init(allocator);
    defer batchComp.deinit();

    const filesProcessed = try batchComp.compressDirectory(testDir);
    std.debug.print("    Batch compressed {d} files in '{s}'\n\n", .{ filesProcessed, testDir });

    // Example 13: v0.2.2 New Algorithms
    std.debug.print("13. New Algorithms (v0.2.2+)\n", .{});
    std.debug.print("\n", .{});

    const algoTestData = try repeatAlloc(allocator, "Testing new v0.2.2 compression algorithms ", 30);
    defer allocator.free(algoTestData);

    // LZMA
    {
        var lzmaComp = logly.Compression.lzmaCompression(allocator);
        defer lzmaComp.deinit();
        const lzmaCompressed = try lzmaComp.compress(algoTestData);
        defer allocator.free(lzmaCompressed);
        const lzmaDecompressed = try lzmaComp.decompress(lzmaCompressed);
        defer allocator.free(lzmaDecompressed);
        std.debug.print("    LZMA:   {} -> {} bytes ({s})\n", .{ algoTestData.len, lzmaCompressed.len, if (std.mem.eql(u8, algoTestData, lzmaDecompressed)) "[OK]" else "[FAIL]" });
    }

    // LZMA2
    {
        var lzma2Comp = logly.Compression.lzma2Compression(allocator);
        defer lzma2Comp.deinit();
        const lzma2Compressed = try lzma2Comp.compress(algoTestData);
        defer allocator.free(lzma2Compressed);
        const lzma2Decompressed = try lzma2Comp.decompress(lzma2Compressed);
        defer allocator.free(lzma2Decompressed);
        std.debug.print("    LZMA2:  {} -> {} bytes ({s})\n", .{ algoTestData.len, lzma2Compressed.len, if (std.mem.eql(u8, algoTestData, lzma2Decompressed)) "[OK]" else "[FAIL]" });
    }

    // XZ
    {
        var xzComp = logly.Compression.xzCompression(allocator);
        defer xzComp.deinit();
        const xzCompressed = try xzComp.compress(algoTestData);
        defer allocator.free(xzCompressed);
        const xzDecompressed = try xzComp.decompress(xzCompressed);
        defer allocator.free(xzDecompressed);
        std.debug.print("    XZ:     {} -> {} bytes ({s})\n", .{ algoTestData.len, xzCompressed.len, if (std.mem.eql(u8, algoTestData, xzDecompressed)) "[OK]" else "[FAIL]" });
    }

    // ZIP
    {
        var zipComp = logly.Compression.zipCompression(allocator);
        defer zipComp.deinit();
        const zipCompressed = try zipComp.compress(algoTestData);
        defer allocator.free(zipCompressed);
        const zipDecompressed = try zipComp.decompress(zipCompressed);
        defer allocator.free(zipDecompressed);
        std.debug.print("    ZIP:    {} -> {} bytes ({s})\n", .{ algoTestData.len, zipCompressed.len, if (std.mem.eql(u8, algoTestData, zipDecompressed)) "[OK]" else "[FAIL]" });
    }

    // TAR.GZ
    {
        var targzComp = logly.Compression.tarGzCompression(allocator);
        defer targzComp.deinit();
        const targzCompressed = try targzComp.compress(algoTestData);
        defer allocator.free(targzCompressed);
        const targzDecompressed = try targzComp.decompress(targzCompressed);
        defer allocator.free(targzDecompressed);
        std.debug.print("    TAR.GZ: {} -> {} bytes ({s})\n", .{ algoTestData.len, targzCompressed.len, if (std.mem.eql(u8, algoTestData, targzDecompressed)) "[OK]" else "[FAIL]" });
    }

    // LZ4
    {
        var lz4Comp = logly.Compression.lz4Compression(allocator);
        defer lz4Comp.deinit();
        const lz4Compressed = try lz4Comp.compress(algoTestData);
        defer allocator.free(lz4Compressed);
        const lz4Decompressed = try lz4Comp.decompress(lz4Compressed);
        defer allocator.free(lz4Decompressed);
        std.debug.print("    LZ4:    {} -> {} bytes ({s})\n", .{ algoTestData.len, lz4Compressed.len, if (std.mem.eql(u8, algoTestData, lz4Decompressed)) "[OK]" else "[FAIL]" });
    }

    // Brotli (v0.2.1+)
    {
        var brotliComp = logly.Compression.brotliCompression(allocator);
        defer brotliComp.deinit();
        const brotliCompressed = try brotliComp.compress(algoTestData);
        defer allocator.free(brotliCompressed);
        const brotliDecompressed = try brotliComp.decompress(brotliCompressed);
        defer allocator.free(brotliDecompressed);
        std.debug.print("    Brotli: {} -> {} bytes ({s})\n", .{ algoTestData.len, brotliCompressed.len, if (std.mem.eql(u8, algoTestData, brotliDecompressed)) "[OK]" else "[FAIL]" });
    }

    std.debug.print("\n", .{});

    // Example 14: Config Presets for v0.2.2 Algorithms
    std.debug.print("14. Config Presets (v0.2.2+)\n", .{});
    std.debug.print("\n", .{});

    const lzmaCfg = logly.Config.CompressionConfig.lzma();
    std.debug.print("    CompressionConfig.lzma(): algorithm={s}, ext={s}\n", .{ @tagName(lzmaCfg.algorithm), lzmaCfg.extension });

    const lzma2Cfg = logly.Config.CompressionConfig.lzma2();
    std.debug.print("    CompressionConfig.lzma2(): algorithm={s}, ext={s}\n", .{ @tagName(lzma2Cfg.algorithm), lzma2Cfg.extension });

    const xzCfg = logly.Config.CompressionConfig.xz();
    std.debug.print("    CompressionConfig.xz(): algorithm={s}, ext={s}\n", .{ @tagName(xzCfg.algorithm), xzCfg.extension });

    const zipCfg = logly.Config.CompressionConfig.zip();
    std.debug.print("    CompressionConfig.zip(): algorithm={s}, ext={s}\n", .{ @tagName(zipCfg.algorithm), zipCfg.extension });

    const targzCfg = logly.Config.CompressionConfig.tarGz();
    std.debug.print("    CompressionConfig.tarGz(): algorithm={s}, ext={s}\n", .{ @tagName(targzCfg.algorithm), targzCfg.extension });

    const lz4Cfg = logly.Config.CompressionConfig.lz4();
    std.debug.print("    CompressionConfig.lz4(): algorithm={s}, ext={s}\n\n", .{ @tagName(lz4Cfg.algorithm), lz4Cfg.extension });

    std.debug.print("Compression Example Complete\n", .{});
}
