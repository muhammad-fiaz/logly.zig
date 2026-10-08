const std = @import("std");
const logly = @import("logly");
const Config = logly.Config;
const SinkConfig = logly.SinkConfig;

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Enable ANSI colors on Windows (no-op on Linux/macOS)
    // This is essential for colors to display correctly on Windows terminals
    _ = logly.Terminal.enableAnsiColors();

    std.debug.print("Color Control Example\n", .{});
    std.debug.print("Note: Entire log lines are colored, not just the level tag!\n\n", .{});

    // Global Color Disable
    std.debug.print("1. Global Color Disabled\n\n", .{});
    {
        const logger = try logly.Logger.init(allocator);
        defer logger.deinit();

        var config = Config.default();
        config.globalColorDisplay = false; // Disable colors globally
        config.color = false; // Also disable at config level
        logger.configure(config);

        std.debug.print("All logs below have colors DISABLED globally:\n", .{});
        try logger.info("Info message (no color)", @src());
        try logger.success("Success message (no color)", @src());
        try logger.warning("Warning message (no color)", @src());
        try logger.err("Error message (no color)", @src());
    }

    // Global Color Enable (default)
    std.debug.print("\n2. Global Color Enabled (Default)\n\n", .{});
    {
        const logger = try logly.Logger.init(allocator);
        defer logger.deinit();

        var config = Config.default();
        config.globalColorDisplay = true; // Enable colors globally (default)
        config.color = true; // Enable at config level
        logger.configure(config);

        std.debug.print("All logs below have colors ENABLED:\n", .{});
        try logger.info("Info message (with color)", @src());
        try logger.success("Success message (with color)", @src());
        try logger.warning("Warning message (with color)", @src());
        try logger.err("Error message (with color)", @src());
    }

    // Per-Sink Color Control
    std.debug.print("\n3. Per-Sink Color Control\n\n", .{});
    {
        // Use initWithConfig to disable auto_sink from the start
        var config = Config.default();
        config.autoSink = false; // We're providing our own sinks
        config.globalColorDisplay = true;

        const logger = try logly.Logger.initWithConfig(allocator, config);
        defer logger.deinit();

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
        try logger.info("This appears colored on stdout, plain in file", @src());
        try logger.warning("Warning with different formats per sink", @src());
        try logger.flush();
    }

    // Auto-Detection for Files
    std.debug.print("\n4. Auto-Detection (null = auto)\n\n", .{});
    {
        // Use initWithConfig to disable auto_sink from the start
        var config = Config.default();
        config.autoSink = false;
        config.globalColorDisplay = true;

        const logger = try logly.Logger.initWithConfig(allocator, config);
        defer logger.deinit();

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
        try logger.info("Color auto-detected based on output type", @src());
        try logger.success("Files automatically get no ANSI codes", @src());
        try logger.flush();
    }

    // Force Colors for File (e.g., for ANSI-aware viewers)
    std.debug.print("\n5. Force Colors in File (for ANSI viewers)\n\n", .{});
    {
        // Use initWithConfig to disable auto_sink from the start
        var config = Config.default();
        config.autoSink = false;
        config.globalColorDisplay = true;

        const logger = try logly.Logger.initWithConfig(allocator, config);
        defer logger.deinit();

        _ = try logger.addSink(.{
            .path = "logs/with_color.log",
            .color = true, // Force colors even for file
        });

        std.debug.print("File will contain ANSI escape codes:\n", .{});
        try logger.info("This file can be viewed with 'less -R' or similar", @src());
        try logger.warning("Useful for tools that support ANSI colors", @src());
        try logger.flush();
    }

    // JSON Format (colors typically disabled)
    std.debug.print("\n6. JSON Format (colors auto-disabled)\n\n", .{});
    {
        // Use initWithConfig to disable auto_sink from the start
        var config = Config.default();
        config.autoSink = false;
        config.globalColorDisplay = true; // Global is on, but sink overrides

        const logger = try logly.Logger.initWithConfig(allocator, config);
        defer logger.deinit();

        _ = try logger.addSink(.{
            .format = .json, // JSON format
            .color = false, // JSON shouldn't have ANSI codes
        });

        std.debug.print("JSON output (colors disabled for parsing):\n", .{});
        try logger.info("JSON logs should not contain ANSI codes", @src());
    }

    // JSON terminal presentation (forced color wraps the whole line)
    std.debug.print("\n7. JSON Presentation Color (forced, terminal only)\n\n", .{});
    {
        // Use initWithConfig to disable auto_sink from the start
        var config = Config.default();
        config.autoSink = false;
        config.globalColorDisplay = true;

        const logger = try logly.Logger.initWithConfig(allocator, config);
        defer logger.deinit();

        _ = try logger.addSink(.{
            .format = .json, // JSON format
            .color = true, // Forced: whole serialized line wrapped in level color
        });

        std.debug.print("JSON stays valid; color wraps the presentation:\n", .{});
        try logger.info("Presentation-wrapped JSON line", @src());
        try logger.flush();
    }

    std.debug.print("\nColor Control Example Complete\n", .{});
}
