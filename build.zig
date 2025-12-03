const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Create the logly module
    const logly_module = b.createModule(.{
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
        .{ .name = "color_options", .path = "examples/color_options.zig" },
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

        const install_exe = b.addInstallArtifact(exe, .{});
        const example_step = b.step("example-" ++ example.name, "Build " ++ example.name ++ " example");
        example_step.dependOn(&install_exe.step);
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
