const std = @import("std");
const logly = @import("logly");

const Compression = logly.Compression;
const Config = logly.Config;
const CompressionConfig = Config.CompressionConfig;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n" ++ "=" ** 60 ++ "\n", .{});
    std.debug.print("  Logly Minimal Configuration Compression Examples\n", .{});
    std.debug.print("=" ** 60 ++ "\n\n", .{});

    // Part 1: Config Builder Methods (Logger Integration)
    std.debug.print("PART 1: Config Builder Methods\n", .{});
    std.debug.print("-" ** 40 ++ "\n", .{});

    // Simplest one-liner - just enable compression
    const config1 = Config.default().withCompressionEnabled();
    std.debug.print("✓ withCompressionEnabled(): enabled={}\n", .{config1.compression.enabled});

    // Implicit (automatic) compression on rotation
    const config2 = Config.default().withImplicitCompression();
    std.debug.print("✓ withImplicitCompression(): mode={s}, on_rotation={}\n", .{ @tagName(config2.compression.mode), config2.compression.on_rotation });

    // Explicit (manual) compression control
    const config3 = Config.default().withExplicitCompression();
    std.debug.print("✓ withExplicitCompression(): mode={s}, on_rotation={}\n", .{ @tagName(config3.compression.mode), config3.compression.on_rotation });

    // Fast compression - prioritize speed
    const config4 = Config.default().withFastCompression();
    std.debug.print("✓ withFastCompression(): level={s}\n", .{@tagName(config4.compression.level)});

    // Best compression - prioritize ratio
    const config5 = Config.default().withBestCompression();
    std.debug.print("✓ withBestCompression(): level={s}, algorithm={s}\n", .{ @tagName(config5.compression.level), @tagName(config5.compression.algorithm) });

    // Background compression
    const config6 = Config.default().withBackgroundCompression();
    std.debug.print("✓ withBackgroundCompression(): background={}\n", .{config6.compression.background});

    // Log-optimized compression
    const config7 = Config.default().withLogCompression();
    std.debug.print("✓ withLogCompression(): strategy={s}\n", .{@tagName(config7.compression.strategy)});

    // Production-ready compression
    const config8 = Config.default().withProductionCompression();
    std.debug.print("✓ withProductionCompression(): background={}, checksum={}\n", .{ config8.compression.background, config8.compression.checksum });

    std.debug.print("\n", .{});

    // Part 2: CompressionConfig Presets
    std.debug.print("PART 2: CompressionConfig Presets\n", .{});
    std.debug.print("-" ** 40 ++ "\n", .{});

    // Basic presets
    const enable_cfg = CompressionConfig.enable();
    std.debug.print("✓ CompressionConfig.enable(): enabled={}\n", .{enable_cfg.enabled});

    const basic_cfg = CompressionConfig.basic();
    std.debug.print("✓ CompressionConfig.basic(): enabled={} (alias for enable)\n", .{basic_cfg.enabled});

    const implicit_cfg = CompressionConfig.implicit();
    std.debug.print("✓ CompressionConfig.implicit(): mode={s}\n", .{@tagName(implicit_cfg.mode)});

    const explicit_cfg = CompressionConfig.explicit();
    std.debug.print("✓ CompressionConfig.explicit(): mode={s}\n", .{@tagName(explicit_cfg.mode)});

    // Performance presets
    const fast_cfg = CompressionConfig.fast();
    std.debug.print("✓ CompressionConfig.fast(): level={s}\n", .{@tagName(fast_cfg.level)});

    const balanced_cfg = CompressionConfig.balanced();
    std.debug.print("✓ CompressionConfig.balanced(): level={s}\n", .{@tagName(balanced_cfg.level)});

    const best_cfg = CompressionConfig.best();
    std.debug.print("✓ CompressionConfig.best(): level={s}\n", .{@tagName(best_cfg.level)});

    // Mode presets
    const bg_cfg = CompressionConfig.backgroundMode();
    std.debug.print("✓ CompressionConfig.backgroundMode(): background={}\n", .{bg_cfg.background});

    const stream_cfg = CompressionConfig.streamingMode();
    std.debug.print("✓ CompressionConfig.streamingMode(): streaming={}, mode={s}\n", .{ stream_cfg.streaming, @tagName(stream_cfg.mode) });

    const size_cfg = CompressionConfig.onSize(5 * 1024 * 1024);
    std.debug.print("✓ CompressionConfig.onSize(5MB): mode={s}, threshold={d}MB\n", .{ @tagName(size_cfg.mode), size_cfg.size_threshold / (1024 * 1024) });

    // Use case presets
    const logs_cfg = CompressionConfig.forLogs();
    std.debug.print("✓ CompressionConfig.forLogs(): strategy={s}\n", .{@tagName(logs_cfg.strategy)});

    const archive_cfg = CompressionConfig.archive();
    std.debug.print("✓ CompressionConfig.archive(): keep_original={}\n", .{archive_cfg.keep_original});

    const keep_cfg = CompressionConfig.keepOriginals();
    std.debug.print("✓ CompressionConfig.keepOriginals(): keep_original={}\n", .{keep_cfg.keep_original});

    const prod_cfg = CompressionConfig.production();
    std.debug.print("✓ CompressionConfig.production(): background={}, checksum={}\n", .{ prod_cfg.background, prod_cfg.checksum });

    const dev_cfg = CompressionConfig.development();
    std.debug.print("✓ CompressionConfig.development(): level={s}, keep_original={}\n", .{ @tagName(dev_cfg.level), dev_cfg.keep_original });

    const disable_cfg = CompressionConfig.disable();
    std.debug.print("✓ CompressionConfig.disable(): enabled={}\n", .{disable_cfg.enabled});

    std.debug.print("\n", .{});

    // Part 3: Compression Instance Presets
    std.debug.print("PART 3: Compression Instance Presets\n", .{});
    std.debug.print("-" ** 40 ++ "\n", .{});

    // Create compression instances with presets
    var comp_enable = Compression.enable(allocator);
    defer comp_enable.deinit();
    std.debug.print("✓ Compression.enable(): enabled={}\n", .{comp_enable.config.enabled});

    var comp_basic = Compression.basic(allocator);
    defer comp_basic.deinit();
    std.debug.print("✓ Compression.basic(): enabled={} (alias for enable)\n", .{comp_basic.config.enabled});

    var comp_implicit = Compression.implicit(allocator);
    defer comp_implicit.deinit();
    std.debug.print("✓ Compression.implicit(): mode={s}\n", .{@tagName(comp_implicit.config.mode)});

    var comp_explicit = Compression.explicit(allocator);
    defer comp_explicit.deinit();
    std.debug.print("✓ Compression.explicit(): mode={s}\n", .{@tagName(comp_explicit.config.mode)});

    var comp_fast = Compression.fast(allocator);
    defer comp_fast.deinit();
    std.debug.print("✓ Compression.fast(): level={s}\n", .{@tagName(comp_fast.config.level)});

    var comp_balanced = Compression.balanced(allocator);
    defer comp_balanced.deinit();
    std.debug.print("✓ Compression.balanced(): level={s}\n", .{@tagName(comp_balanced.config.level)});

    var comp_best = Compression.best(allocator);
    defer comp_best.deinit();
    std.debug.print("✓ Compression.best(): level={s}\n", .{@tagName(comp_best.config.level)});

    var comp_logs = Compression.forLogs(allocator);
    defer comp_logs.deinit();
    std.debug.print("✓ Compression.forLogs(): strategy={s}\n", .{@tagName(comp_logs.config.strategy)});

    var comp_archive = Compression.archive(allocator);
    defer comp_archive.deinit();
    std.debug.print("✓ Compression.archive(): level={s}\n", .{@tagName(comp_archive.config.level)});

    var comp_prod = Compression.production(allocator);
    defer comp_prod.deinit();
    std.debug.print("✓ Compression.production(): background={}\n", .{comp_prod.config.background});

    var comp_dev = Compression.development(allocator);
    defer comp_dev.deinit();
    std.debug.print("✓ Compression.development(): keep_original={}\n", .{comp_dev.config.keep_original});

    var comp_bg = Compression.background(allocator);
    defer comp_bg.deinit();
    std.debug.print("✓ Compression.background(): background={}\n", .{comp_bg.config.background});

    var comp_stream = Compression.streaming(allocator);
    defer comp_stream.deinit();
    std.debug.print("✓ Compression.streaming(): streaming={}\n", .{comp_stream.config.streaming});

    std.debug.print("\n", .{});

    // Part 4: Practical Usage Demo
    std.debug.print("PART 4: Practical Usage Demo\n", .{});
    std.debug.print("-" ** 40 ++ "\n", .{});

    // Demo 1: Implicit compression (automatic)
    std.debug.print("\n[Demo 1: Implicit Compression]\n", .{});
    std.debug.print("Setup: Config.default().withImplicitCompression()\n", .{});
    std.debug.print("Behavior: Files compress automatically on rotation\n", .{});
    std.debug.print("Use case: Set-and-forget log management\n", .{});

    // Demo 2: Explicit compression (manual)
    std.debug.print("\n[Demo 2: Explicit Compression]\n", .{});
    var explicit_compressor = Compression.explicit(allocator);
    defer explicit_compressor.deinit();

    // Create test data
    const test_data = "INFO: Application started\n" ** 100;
    const compressed = try explicit_compressor.compress(test_data);
    defer allocator.free(compressed);

    const ratio = 1.0 - (@as(f64, @floatFromInt(compressed.len)) / @as(f64, @floatFromInt(test_data.len)));
    std.debug.print("Setup: Compression.explicit(allocator)\n", .{});
    std.debug.print("Original size: {d} bytes\n", .{test_data.len});
    std.debug.print("Compressed size: {d} bytes\n", .{compressed.len});
    std.debug.print("Compression ratio: {d:.1}%\n", .{ratio * 100});
    std.debug.print("Use case: User-controlled compression timing\n", .{});

    // Demo 3: Production setup
    std.debug.print("\n[Demo 3: Production Setup]\n", .{});
    var prod_compressor = Compression.production(allocator);
    defer prod_compressor.deinit();

    const prod_compressed = try prod_compressor.compress(test_data);
    defer allocator.free(prod_compressed);

    std.debug.print("Setup: Compression.production(allocator)\n", .{});
    std.debug.print("Features: background={}, checksum={}, level={s}\n", .{
        prod_compressor.config.background,
        prod_compressor.config.checksum,
        @tagName(prod_compressor.config.level),
    });
    std.debug.print("Compressed size: {d} bytes\n", .{prod_compressed.len});

    std.debug.print("\n", .{});

    // Part 5: File Customization Options
    std.debug.print("PART 5: File Customization Options\n", .{});
    std.debug.print("-" ** 40 ++ "\n", .{});

    // Demo custom file naming and archive root
    const custom_cfg = CompressionConfig{
        .enabled = true,
        .algorithm = .gzip,
        .level = .best,
        .file_prefix = "archived_",
        .file_suffix = "_v1",
        .archive_root_dir = "logs/compressed",
        .create_date_subdirs = true,
        .preserve_dir_structure = true,
        .naming_pattern = "{base}_{date}{ext}",
    };

    std.debug.print("\n[Demo: Custom File Naming]\n", .{});
    std.debug.print("Configuration:\n", .{});
    std.debug.print("  - file_prefix: \"{s}\"\n", .{custom_cfg.file_prefix.?});
    std.debug.print("  - file_suffix: \"{s}\"\n", .{custom_cfg.file_suffix.?});
    std.debug.print("  - archive_root_dir: \"{s}\"\n", .{custom_cfg.archive_root_dir.?});
    std.debug.print("  - create_date_subdirs: {}\n", .{custom_cfg.create_date_subdirs});
    std.debug.print("  - preserve_dir_structure: {}\n", .{custom_cfg.preserve_dir_structure});
    std.debug.print("  - naming_pattern: \"{s}\"\n", .{custom_cfg.naming_pattern.?});
    std.debug.print("\nResult: logs/compressed/2026/01/09/archived_app_2026-01-09_v1.log.gz\n", .{});

    // Demo scheduler config customization
    const sched_cfg = Config.SchedulerConfig{
        .enabled = true,
        .archive_root_dir = "logs/scheduled",
        .create_date_subdirs = true,
        .compression_algorithm = .gzip,
        .compression_level = .best,
        .keep_originals = false,
        .archive_file_prefix = "sched_",
        .clean_empty_dirs = true,
    };

    std.debug.print("\n[Demo: Scheduler Compression Config]\n", .{});
    std.debug.print("Configuration:\n", .{});
    std.debug.print("  - archive_root_dir: \"{s}\"\n", .{sched_cfg.archive_root_dir.?});
    std.debug.print("  - compression_algorithm: {s}\n", .{@tagName(sched_cfg.compression_algorithm)});
    std.debug.print("  - compression_level: {s}\n", .{@tagName(sched_cfg.compression_level)});
    std.debug.print("  - archive_file_prefix: \"{s}\"\n", .{sched_cfg.archive_file_prefix.?});
    std.debug.print("  - clean_empty_dirs: {}\n", .{sched_cfg.clean_empty_dirs});

    // Demo rotation config customization
    const rot_cfg = Config.RotationConfig{
        .enabled = true,
        .archive_root_dir = "logs/rotated",
        .create_date_subdirs = true,
        .file_prefix = "rot_",
        .file_suffix = "_old",
        .compression_algorithm = .deflate,
        .compression_level = .fast,
        .compress_on_retention = true,
        .keep_original = false,
    };

    std.debug.print("\n[Demo: Rotation Compression Config]\n", .{});
    std.debug.print("Configuration:\n", .{});
    std.debug.print("  - archive_root_dir: \"{s}\"\n", .{rot_cfg.archive_root_dir.?});
    std.debug.print("  - file_prefix: \"{s}\"\n", .{rot_cfg.file_prefix.?});
    std.debug.print("  - file_suffix: \"{s}\"\n", .{rot_cfg.file_suffix.?});
    std.debug.print("  - compression_algorithm: {s}\n", .{@tagName(rot_cfg.compression_algorithm)});
    std.debug.print("  - compress_on_retention: {}\n", .{rot_cfg.compress_on_retention});

    std.debug.print("\n" ++ "=" ** 60 ++ "\n", .{});
    std.debug.print("  All minimal configuration examples completed!\n", .{});
    std.debug.print("=" ** 60 ++ "\n", .{});
}
