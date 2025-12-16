const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Enable ANSI colors
    _ = logly.Terminal.enableAnsiColors();

    std.debug.print("=== Testing Configuration Modes ===\n\n", .{});

    // Test 1: Log-Only Mode (no console display, only file storage)
    std.debug.print("1. Log-Only Mode (files only, no console)\n", .{});
    {
        const config = logly.Config.logOnly();
        const logger = try logly.Logger.initWithConfig(allocator, config);
        defer logger.deinit();

        // Add a file sink
        _ = try logger.addSink(logly.SinkConfig.file("test_log_only.log"));

        // These should only go to the file, not console
        try logger.info("This message goes to file only", @src());
        try logger.warn("Warning message in file only", @src());
        try logger.flush();
    }
    std.debug.print("   ✓ Log-only mode completed (check test_log_only.log)\n\n", .{});

    // Test 2: Display-Only Mode (console display, no file storage)
    std.debug.print("2. Display-Only Mode (console only, no files)\n", .{});
    {
        const config = logly.Config.displayOnly();
        const logger = try logly.Logger.initWithConfig(allocator, config);
        defer logger.deinit();

        // Try to add a file sink - it should be ignored due to global_file_storage = false
        _ = try logger.addSink(logly.SinkConfig.file("test_display_only.log"));

        // These should only appear in console
        try logger.info("This message appears in console only", @src());
        try logger.success("Success message in console only", @src());
        try logger.flush();
    }
    std.debug.print("   ✓ Display-only mode completed\n\n", .{});

    // Test 3: Custom Display/Storage Settings
    std.debug.print("3. Custom Display/Storage Settings\n", .{});
    {
        // Both console and file enabled
        const config = logly.Config.withDisplayStorage(true, true, true);
        const logger = try logly.Logger.initWithConfig(allocator, config);
        defer logger.deinit();

        // Add a file sink
        _ = try logger.addSink(logly.SinkConfig.file("test_both.log"));

        // These should appear in both console and file
        try logger.info("This message appears in both console and file", @src());
        try logger.err("Error message in both outputs", @src());
        try logger.flush();
    }
    std.debug.print("   ✓ Custom mode completed (check test_both.log)\n\n", .{});

    // Test 4: Silent Mode (no output anywhere)
    std.debug.print("4. Silent Mode (no output anywhere)\n", .{});
    {
        const config = logly.Config.withDisplayStorage(false, false, false);
        const logger = try logly.Logger.initWithConfig(allocator, config);
        defer logger.deinit();

        // Try to add sinks - they should be ignored
        _ = try logger.addSink(logly.SinkConfig.file("test_silent.log"));

        // These should not appear anywhere
        try logger.info("This message should not appear anywhere", @src());
        try logger.crit("Critical message that should be silent", @src());
        try logger.flush();
    }
    std.debug.print("   ✓ Silent mode completed (no output expected)\n\n", .{});

    // Test 5: Runtime Configuration Changes
    std.debug.print("5. Runtime Configuration Changes\n", .{});
    {
        const logger = try logly.Logger.init(allocator);
        defer logger.deinit();

        // Start with default (both console and file enabled)
        try logger.info("Initial message with default config", @src());

        // Switch to log-only mode
        var config = logly.Config.logOnly();
        logger.configure(config);
        _ = try logger.addSink(logly.SinkConfig.file("test_runtime.log"));

        try logger.info("This should only go to file after config change", @src());

        // Switch to display-only mode
        config = logly.Config.displayOnly();
        logger.configure(config);

        try logger.info("This should only appear in console after second config change", @src());
        try logger.flush();
    }
    std.debug.print("   ✓ Runtime configuration changes completed\n\n", .{});

    std.debug.print("=== All Configuration Mode Tests Completed ===\n", .{});
}