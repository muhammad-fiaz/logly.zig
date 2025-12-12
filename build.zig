const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Create the logly module
    const logly_module = b.createModule(.{
        .root_source_file = b.path("src/logly.zig"),
    });

    // Expose the module for external projects that depend on this package.
    // This allows users to do: `const logly = @import("logly");` in their code
    // after adding logly as a dependency and calling `dep.module("logly")` in their build.zig
    _ = b.addModule("logly", .{
        .root_source_file = b.path("src/logly.zig"),
    });

    // Build examples
    const examples = [_]struct { name: []const u8, path: []const u8 }{
        .{ .name = "basic", .path = "examples/basic.zig" },
        .{ .name = "file_logging", .path = "examples/file_logging.zig" },
        .{ .name = "rotation", .path = "examples/rotation.zig" },
        .{ .name = "json_logging", .path = "examples/json_logging.zig" },
        .{ .name = "callbacks", .path = "examples/callbacks.zig" },
        .{ .name = "context", .path = "examples/context.zig" },
        .{ .name = "custom_colors", .path = "examples/custom_colors.zig" },
        .{ .name = "async_logging", .path = "examples/async_logging.zig" },
        .{ .name = "advanced_config", .path = "examples/advanced_config.zig" },
        .{ .name = "module_levels", .path = "examples/module_levels.zig" },
        .{ .name = "sink_formats", .path = "examples/sink_formats.zig" },
        .{ .name = "formatted_logging", .path = "examples/formatted_logging.zig" },
        .{ .name = "json_extended", .path = "examples/json_extended.zig" },
        .{ .name = "time", .path = "examples/time.zig" },
        .{ .name = "filtering", .path = "examples/filtering.zig" },
        .{ .name = "sampling", .path = "examples/sampling.zig" },
        .{ .name = "redaction", .path = "examples/redaction.zig" },
        .{ .name = "metrics", .path = "examples/metrics.zig" },
        .{ .name = "tracing", .path = "examples/tracing.zig" },
        .{ .name = "production_config", .path = "examples/production_config.zig" },
        .{ .name = "diagnostics", .path = "examples/diagnostics.zig" },
        .{ .name = "color_options", .path = "examples/color_options.zig" },
        .{ .name = "custom_levels_full", .path = "examples/custom_levels_full.zig" },
        .{ .name = "compression", .path = "examples/compression.zig" },
        .{ .name = "thread_pool", .path = "examples/thread_pool.zig" },
        .{ .name = "scheduler", .path = "examples/scheduler.zig" },
        .{ .name = "async_advanced", .path = "examples/async_advanced.zig" },
        .{ .name = "compression_demo", .path = "examples/compression_demo.zig" },
        .{ .name = "scheduler_demo", .path = "examples/scheduler_demo.zig" },
        .{ .name = "thread_pool_arena", .path = "examples/thread_pool_arena.zig" },
        .{ .name = "dynamic_path", .path = "examples/dynamic_path.zig" },
        .{ .name = "customizations", .path = "examples/customizations.zig" },
        .{ .name = "sink_write_modes", .path = "examples/sink_write_modes.zig" },
        .{ .name = "network_logging", .path = "examples/network_logging.zig" },
        .{ .name = "update_check", .path = "examples/update_check.zig" },
        .{ .name = "advanced_features", .path = "examples/advanced_features.zig" },
        .{ .name = "custom_theme", .path = "examples/custom_theme.zig" },
    };

    inline for (examples) |example| {
        const exe = b.addExecutable(.{
            .name = example.name,
            .root_module = b.createModule(.{
                .root_source_file = b.path(example.path),
                .target = target,
                .optimize = optimize,
            }),
        });
        exe.root_module.addImport("logly", logly_module);
        if (std.mem.eql(u8, example.name, "network_logging")) {
            exe.linkLibC();
        }

        const install_exe = b.addInstallArtifact(exe, .{});
        const example_step = b.step("example-" ++ example.name, "Build " ++ example.name ++ " example");
        example_step.dependOn(&install_exe.step);

        // Add run step for each example
        const run_exe = b.addRunArtifact(exe);
        run_exe.step.dependOn(&install_exe.step);
        const run_step = b.step("run-" ++ example.name, "Run " ++ example.name ++ " example");
        run_step.dependOn(&run_exe.step);
    }

    // Create run-all-examples step that runs all examples sequentially
    const run_all_examples = b.step("run-all-examples", "Run all examples sequentially");
    var previous_step: ?*std.Build.Step = null;

    inline for (examples) |example| {
        const exe = b.addExecutable(.{
            .name = "run-all-" ++ example.name,
            .root_module = b.createModule(.{
                .root_source_file = b.path(example.path),
                .target = target,
                .optimize = optimize,
            }),
        });
        exe.root_module.addImport("logly", logly_module);
        if (std.mem.eql(u8, example.name, "network_logging")) {
            exe.linkLibC();
        }

        const install_exe = b.addInstallArtifact(exe, .{});
        const run_exe = b.addRunArtifact(exe);
        run_exe.step.dependOn(&install_exe.step);

        if (previous_step) |prev| {
            run_exe.step.dependOn(prev);
        }
        previous_step = &run_exe.step;
    }

    if (previous_step) |last| {
        run_all_examples.dependOn(last);
    }

    // Unit tests
    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/logly.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);

    // Benchmark
    const bench_exe = b.addExecutable(.{
        .name = "benchmark",
        .root_module = b.createModule(.{
            .root_source_file = b.path("bench/benchmark.zig"),
            .target = target,
            .optimize = .ReleaseFast,
        }),
    });
    bench_exe.root_module.addImport("logly", logly_module);

    const install_bench = b.addInstallArtifact(bench_exe, .{});
    const run_bench = b.addRunArtifact(bench_exe);
    run_bench.step.dependOn(&install_bench.step);

    const bench_step = b.step("bench", "Run benchmarks");
    bench_step.dependOn(&run_bench.step);

    // Install step for library
    const lib = b.addLibrary(.{
        .name = "logly",
        .linkage = .static,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/logly.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    b.installArtifact(lib);
}
