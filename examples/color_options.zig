const std = @import("std");
const logly = @import("logly");
const Config = logly.Config;
const SinkConfig = logly.SinkConfig;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Enable ANSI colors on Windows (no-op on Linux/macOS)
    // This is essential for colors to display correctly on Windows terminals
    _ = logly.Terminal.enableAnsiColors();

    std.debug.print("=== Color Control Example ===\n", .{});
    std.debug.print("Note: Entire log lines are colored, not just the level tag!\n\n", .{});

    // --- Global Color Disable ---
    std.debug.print("--- 1. Global Color Disabled ---\n\n", .{});
    {
        const logger = try logly.Logger.init(allocator);
        defer logger.deinit();

        var config = Config.default();
        config.global_color_display = false; // Disable colors globally
        config.color = false; // Also disable at config level
        logger.configure(config);

        std.debug.print("All logs below have colors DISABLED globally:\n", .{});
        try logger.info("Info message (no color)");
        try logger.success("Success message (no color)");
        try logger.warning("Warning message (no color)");
        try logger.err("Error message (no color)");
    }

    // --- Global Color Enable (default) ---
    std.debug.print("\n--- 2. Global Color Enabled (Default) ---\n\n", .{});
    {
        const logger = try logly.Logger.init(allocator);
        defer logger.deinit();

        var config = Config.default();
        config.global_color_display = true; // Enable colors globally (default)
        config.color = true; // Enable at config level
        logger.configure(config);

        std.debug.print("All logs below have colors ENABLED:\n", .{});
        try logger.info("Info message (with color)");
        try logger.success("Success message (with color)");
        try logger.warning("Warning message (with color)");
        try logger.err("Error message (with color)");
    }

    // --- Per-Sink Color Control ---
    std.debug.print("\n--- 3. Per-Sink Color Control ---\n\n", .{});
    {
        const logger = try logly.Logger.init(allocator);
        defer logger.deinit();

        var config = Config.default();
        config.auto_sink = false; // We're providing our own sinks
        config.global_color_display = true;
        logger.configure(config);

        // Console sink with colors enabled (default)
        _ = try logger.addSink(.{
            .name = "console",
            .color = true, // Force colors on
        });

        // File sink with colors disabled (auto for files)
        _ = try logger.addSink(.{
            .path = "logs/no_color.log",
            .color = false, // Force colors off for file
        });

        std.debug.print("Console has colors, file sink does not:\n", .{});
        try logger.info("This appears colored on stdout, plain in file");
        try logger.warning("Warning with different formats per sink");
        try logger.flush();
    }

    // --- Auto-Detection for Files ---
    std.debug.print("\n--- 4. Auto-Detection (null = auto) ---\n\n", .{});
    {
        const logger = try logly.Logger.init(allocator);
        defer logger.deinit();

        var config = Config.default();
        config.auto_sink = false;
        config.global_color_display = true;
        logger.configure(config);

        // Console with auto-detection (uses terminal detection)
        _ = try logger.addSink(.{
            .name = "console",
            .color = null, // Auto-detect based on terminal
        });

        // File with auto-detection (will be disabled for files)
        _ = try logger.addSink(.{
            .path = "logs/auto_color.log",
            .color = null, // Auto-detect (off for files)
        });

        std.debug.print("Auto-detection: terminal=on, file=off:\n", .{});
        try logger.info("Color auto-detected based on output type");
        try logger.success("Files automatically get no ANSI codes");
        try logger.flush();
    }

    // --- Force Colors for File (e.g., for ANSI-aware viewers) ---
    std.debug.print("\n--- 5. Force Colors in File (for ANSI viewers) ---\n\n", .{});
    {
        const logger = try logly.Logger.init(allocator);
        defer logger.deinit();

        var config = Config.default();
        config.auto_sink = false;
        config.global_color_display = true;
        logger.configure(config);

        _ = try logger.addSink(.{
            .path = "logs/with_color.log",
            .color = true, // Force colors even for file
        });

        std.debug.print("File will contain ANSI escape codes:\n", .{});
        try logger.info("This file can be viewed with 'less -R' or similar");
        try logger.warning("Useful for tools that support ANSI colors");
        try logger.flush();
    }

    // --- JSON Format (colors typically disabled) ---
    std.debug.print("\n--- 6. JSON Format (colors auto-disabled) ---\n\n", .{});
    {
        const logger = try logly.Logger.init(allocator);
        defer logger.deinit();

        var config = Config.default();
        config.auto_sink = false;
        config.global_color_display = true; // Global is on, but sink overrides
        logger.configure(config);

        _ = try logger.addSink(.{
            .json = true, // JSON format
            .color = false, // JSON shouldn't have ANSI codes
        });

        std.debug.print("JSON output (colors disabled for parsing):\n", .{});
        try logger.info("JSON logs should not contain ANSI codes");
    }

    std.debug.print("\n=== Color Control Example Complete ===\n", .{});
}
