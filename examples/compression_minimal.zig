const std = @import("std");
const logly = @import("logly");

/// Repeats `s` exactly `n` times, returning owned memory.
fn repeatAlloc(allocator: std.mem.Allocator, s: []const u8, n: usize) ![]u8 {
    const out = try allocator.alloc(u8, s.len * n);
    for (0..n) |i| @memcpy(out[i * s.len ..][0..s.len], s);
    return out;
}

const Compression = logly.Compression;
const Config = logly.Config;
const CompressionConfig = Config.CompressionConfig;

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\nMinimal Configuration Compression Examples\n", .{});

    // Part 1: Config Builder Methods (Logger Integration)
    std.debug.print("Part 1: Config Builder Methods\n", .{});

    // Simplest one-liner - just enable compression
    const config1 = Config.default().withCompressionEnabled();
    std.debug.print("[OK] withCompressionEnabled(): enabled={}\n", .{config1.compression.enabled});

    // Implicit (automatic) compression on rotation
    const config2 = Config.default().withImplicitCompression();
    std.debug.print("[OK] withImplicitCompression(): mode={s}, onRotation={}\n", .{ @tagName(config2.compression.mode), config2.compression.onRotation });

    // Explicit (manual) compression control
    const config3 = Config.default().withExplicitCompression();
    std.debug.print("[OK] withExplicitCompression(): mode={s}, onRotation={}\n", .{ @tagName(config3.compression.mode), config3.compression.onRotation });

    // Fast compression - prioritize speed
    const config4 = Config.default().withFastCompression();
    std.debug.print("[OK] withFastCompression(): level={s}\n", .{@tagName(config4.compression.level)});

    // Best compression - prioritize ratio
    const config5 = Config.default().withBestCompression();
    std.debug.print("[OK] withBestCompression(): level={s}, algorithm={s}\n", .{ @tagName(config5.compression.level), @tagName(config5.compression.algorithm) });

    // Background compression
    const config6 = Config.default().withBackgroundCompression();
    std.debug.print("[OK] withBackgroundCompression(): background={}\n", .{config6.compression.background});

    // Log-optimized compression
    const config7 = Config.default().withLogCompression();
    std.debug.print("[OK] withLogCompression(): strategy={s}\n", .{@tagName(config7.compression.strategy)});

    // Production-ready compression
    const config8 = Config.default().withProductionCompression();
    std.debug.print("[OK] withProductionCompression(): background={}, checksum={}\n", .{ config8.compression.background, config8.compression.checksum });

    std.debug.print("\n", .{});

    // Part 2: CompressionConfig Presets
    std.debug.print("Part 2: CompressionConfig Presets\n", .{});

    // Basic presets
    const enableCfg = CompressionConfig.enable();
    std.debug.print("[OK] CompressionConfig.enable(): enabled={}\n", .{enableCfg.enabled});

    const basicCfg = CompressionConfig.basic();
    std.debug.print("[OK] CompressionConfig.basic(): enabled={} (alias for enable)\n", .{basicCfg.enabled});

    const implicitCfg = CompressionConfig.implicit();
    std.debug.print("[OK] CompressionConfig.implicit(): mode={s}\n", .{@tagName(implicitCfg.mode)});

    const explicitCfg = CompressionConfig.explicit();
    std.debug.print("[OK] CompressionConfig.explicit(): mode={s}\n", .{@tagName(explicitCfg.mode)});

    // Performance presets
    const fastCfg = CompressionConfig.fast();
    std.debug.print("[OK] CompressionConfig.fast(): level={s}\n", .{@tagName(fastCfg.level)});

    const balancedCfg = CompressionConfig.balanced();
    std.debug.print("[OK] CompressionConfig.balanced(): level={s}\n", .{@tagName(balancedCfg.level)});

    const bestCfg = CompressionConfig.best();
    std.debug.print("[OK] CompressionConfig.best(): level={s}\n", .{@tagName(bestCfg.level)});

    // Mode presets
    const bgCfg = CompressionConfig.backgroundMode();
    std.debug.print("[OK] CompressionConfig.backgroundMode(): background={}\n", .{bgCfg.background});

    const streamCfg = CompressionConfig.streamingMode();
    std.debug.print("[OK] CompressionConfig.streamingMode(): streaming={}, mode={s}\n", .{ streamCfg.streaming, @tagName(streamCfg.mode) });

    const sizeCfg = CompressionConfig.onSize(5 * 1024 * 1024);
    std.debug.print("[OK] CompressionConfig.onSize(5MB): mode={s}, threshold={d}MB\n", .{ @tagName(sizeCfg.mode), sizeCfg.sizeThreshold / (1024 * 1024) });

    // Use case presets
    const logsCfg = CompressionConfig.forLogs();
    std.debug.print("[OK] CompressionConfig.forLogs(): strategy={s}\n", .{@tagName(logsCfg.strategy)});

    const archiveCfg = CompressionConfig.archive();
    std.debug.print("[OK] CompressionConfig.archive(): keepOriginal={}\n", .{archiveCfg.keepOriginal});

    const keepCfg = CompressionConfig.keepOriginals();
    std.debug.print("[OK] CompressionConfig.keepOriginals(): keepOriginal={}\n", .{keepCfg.keepOriginal});

    const prodCfg = CompressionConfig.production();
    std.debug.print("[OK] CompressionConfig.production(): background={}, checksum={}\n", .{ prodCfg.background, prodCfg.checksum });

    const devCfg = CompressionConfig.development();
    std.debug.print("[OK] CompressionConfig.development(): level={s}, keepOriginal={}\n", .{ @tagName(devCfg.level), devCfg.keepOriginal });

    const disableCfg = CompressionConfig.disable();
    std.debug.print("[OK] CompressionConfig.disable(): enabled={}\n", .{disableCfg.enabled});

    std.debug.print("\n", .{});

    // Part 3: Compression Instance Presets
    std.debug.print("Part 3: Compression Instance Presets\n", .{});

    // Create compression instances with presets
    var compEnable = Compression.enable(allocator);
    defer compEnable.deinit();
    std.debug.print("[OK] Compression.enable(): enabled={}\n", .{compEnable.config.enabled});

    var compBasic = Compression.basic(allocator);
    defer compBasic.deinit();
    std.debug.print("[OK] Compression.basic(): enabled={} (alias for enable)\n", .{compBasic.config.enabled});

    var compImplicit = Compression.implicit(allocator);
    defer compImplicit.deinit();
    std.debug.print("[OK] Compression.implicit(): mode={s}\n", .{@tagName(compImplicit.config.mode)});

    var compExplicit = Compression.explicit(allocator);
    defer compExplicit.deinit();
    std.debug.print("[OK] Compression.explicit(): mode={s}\n", .{@tagName(compExplicit.config.mode)});

    var compFast = Compression.fast(allocator);
    defer compFast.deinit();
    std.debug.print("[OK] Compression.fast(): level={s}\n", .{@tagName(compFast.config.level)});

    var compBalanced = Compression.balanced(allocator);
    defer compBalanced.deinit();
    std.debug.print("[OK] Compression.balanced(): level={s}\n", .{@tagName(compBalanced.config.level)});

    var compBest = Compression.best(allocator);
    defer compBest.deinit();
    std.debug.print("[OK] Compression.best(): level={s}\n", .{@tagName(compBest.config.level)});

    var compLogs = Compression.forLogs(allocator);
    defer compLogs.deinit();
    std.debug.print("[OK] Compression.forLogs(): strategy={s}\n", .{@tagName(compLogs.config.strategy)});

    var compArchive = Compression.archive(allocator);
    defer compArchive.deinit();
    std.debug.print("[OK] Compression.archive(): level={s}\n", .{@tagName(compArchive.config.level)});

    var compProd = Compression.production(allocator);
    defer compProd.deinit();
    std.debug.print("[OK] Compression.production(): background={}\n", .{compProd.config.background});

    var compDev = Compression.development(allocator);
    defer compDev.deinit();
    std.debug.print("[OK] Compression.development(): keepOriginal={}\n", .{compDev.config.keepOriginal});

    var compBg = Compression.background(allocator);
    defer compBg.deinit();
    std.debug.print("[OK] Compression.background(): background={}\n", .{compBg.config.background});

    var compStream = Compression.streaming(allocator);
    defer compStream.deinit();
    std.debug.print("[OK] Compression.streaming(): streaming={}\n", .{compStream.config.streaming});

    std.debug.print("\n", .{});

    // Part 4: Practical Usage Demo
    std.debug.print("Part 4: Practical Usage Demo\n", .{});

    // Demo 1: Implicit compression (automatic)
    std.debug.print("\n[Demo 1: Implicit Compression]\n", .{});
    std.debug.print("Setup: Config.default().withImplicitCompression()\n", .{});
    std.debug.print("Behavior: Files compress automatically on rotation\n", .{});
    std.debug.print("Use case: Set-and-forget log management\n", .{});

    // Demo 2: Explicit compression (manual)
    std.debug.print("\n[Demo 2: Explicit Compression]\n", .{});
    var explicitCompressor = Compression.explicit(allocator);
    defer explicitCompressor.deinit();

    // Create test data
    const testData = try repeatAlloc(allocator, "INFO: Application started\n", 100);
    defer allocator.free(testData);
    const compressed = try explicitCompressor.compress(testData);
    defer allocator.free(compressed);

    const ratio = 1.0 - (@as(f64, @floatFromInt(compressed.len)) / @as(f64, @floatFromInt(testData.len)));
    std.debug.print("Setup: Compression.explicit(allocator)\n", .{});
    std.debug.print("Original size: {d} bytes\n", .{testData.len});
    std.debug.print("Compressed size: {d} bytes\n", .{compressed.len});
    std.debug.print("Compression ratio: {d:.1}%\n", .{ratio * 100});
    std.debug.print("Use case: User-controlled compression timing\n", .{});

    // Demo 3: Production setup
    std.debug.print("\n[Demo 3: Production Setup]\n", .{});
    var prodCompressor = Compression.production(allocator);
    defer prodCompressor.deinit();

    const prodCompressed = try prodCompressor.compress(testData);
    defer allocator.free(prodCompressed);

    std.debug.print("Setup: Compression.production(allocator)\n", .{});
    std.debug.print("Features: background={}, checksum={}, level={s}\n", .{
        prodCompressor.config.background,
        prodCompressor.config.checksum,
        @tagName(prodCompressor.config.level),
    });
    std.debug.print("Compressed size: {d} bytes\n", .{prodCompressed.len});

    std.debug.print("\n", .{});

    // Part 5: File Customization Options
    std.debug.print("Part 5: File Customization Options\n", .{});

    // Demo custom file naming and archive root
    const customCfg = CompressionConfig{
        .enabled = true,
        .algorithm = .gzip,
        .level = .best,
        .filePrefix = "archived_",
        .fileSuffix = "_v1",
        .archiveRootDir = "logs/compressed",
        .createDateSubdirs = true,
        .preserveDirStructure = true,
        .namingPattern = "{base}_{date}{ext}",
    };

    std.debug.print("\n[Demo: Custom File Naming]\n", .{});
    std.debug.print("Configuration:\n", .{});
    std.debug.print("  - filePrefix: \"{s}\"\n", .{customCfg.filePrefix.?});
    std.debug.print("  - fileSuffix: \"{s}\"\n", .{customCfg.fileSuffix.?});
    std.debug.print("  - archiveRootDir: \"{s}\"\n", .{customCfg.archiveRootDir.?});
    std.debug.print("  - createDateSubdirs: {}\n", .{customCfg.createDateSubdirs});
    std.debug.print("  - preserveDirStructure: {}\n", .{customCfg.preserveDirStructure});
    std.debug.print("  - namingPattern: \"{s}\"\n", .{customCfg.namingPattern.?});
    std.debug.print("\nResult: logs/compressed/2026/01/09/archived_app_2026-01-09_v1.log.gz\n", .{});

    // Demo scheduler config customization
    const schedCfg = Config.SchedulerConfig{
        .enabled = true,
        .archiveRootDir = "logs/scheduled",
        .createDateSubdirs = true,
        .compressionAlgorithm = .gzip,
        .compressionLevel = .best,
        .keepOriginals = false,
        .archiveFilePrefix = "sched_",
        .cleanEmptyDirs = true,
    };

    std.debug.print("\n[Demo: Scheduler Compression Config]\n", .{});
    std.debug.print("Configuration:\n", .{});
    std.debug.print("  - archiveRootDir: \"{s}\"\n", .{schedCfg.archiveRootDir.?});
    std.debug.print("  - compressionAlgorithm: {s}\n", .{@tagName(schedCfg.compressionAlgorithm)});
    std.debug.print("  - compressionLevel: {s}\n", .{@tagName(schedCfg.compressionLevel)});
    std.debug.print("  - archive_filePrefix: \"{s}\"\n", .{schedCfg.archiveFilePrefix.?});
    std.debug.print("  - cleanEmptyDirs: {}\n", .{schedCfg.cleanEmptyDirs});

    // Demo rotation config customization
    const rotCfg = Config.RotationConfig{
        .enabled = true,
        .archiveRootDir = "logs/rotated",
        .createDateSubdirs = true,
        .filePrefix = "rot_",
        .fileSuffix = "_old",
        .compressionAlgorithm = .deflate,
        .compressionLevel = .fast,
        .compressOnRetention = true,
        .keepOriginal = false,
    };

    std.debug.print("\n[Demo: Rotation Compression Config]\n", .{});
    std.debug.print("Configuration:\n", .{});
    std.debug.print("  - archiveRootDir: \"{s}\"\n", .{rotCfg.archiveRootDir.?});
    std.debug.print("  - filePrefix: \"{s}\"\n", .{rotCfg.filePrefix.?});
    std.debug.print("  - fileSuffix: \"{s}\"\n", .{rotCfg.fileSuffix.?});
    std.debug.print("  - compressionAlgorithm: {s}\n", .{@tagName(rotCfg.compressionAlgorithm)});
    std.debug.print("  - compressOnRetention: {}\n", .{rotCfg.compressOnRetention});

    std.debug.print("\nAll minimal configuration examples completed!\n", .{});
}
