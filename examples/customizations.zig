const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== Logly Customizations Example ===\n\n", .{});

    // Example 1: Global root path for logs
    std.debug.print("1. Global Root Path Configuration\n", .{});
    std.debug.print("   Setting logs to be stored in './logs' directory\n\n", .{});

    var config1 = logly.Config.default();
    config1.logs_root_path = "./logs";
    config1.color = true;
    config1.show_filename = true;
    config1.show_lineno = true;

    const logger1 = try logly.Logger.initWithConfig(allocator, config1);
    defer logger1.deinit();

    // Add file sinks that will be stored relative to logs_root_path
    _ = try logger1.addSink(logly.SinkConfig.file("application.log"));
    _ = try logger1.addSink(logly.SinkConfig.file("errors.log"));

    try logger1.info("Application started - logs stored in ./logs directory", @src());
    try logger1.warning("This warning is saved to ./logs/application.log", @src());
    try logger1.err("This error is saved to ./logs/errors.log", @src());

    std.debug.print("\n2. Format Structure Customization\n", .{});
    std.debug.print("   Customizing log message format with prefix, suffix, and separators\n\n", .{});

    var config2 = logly.Config.default();
    config2.format_structure = .{
        .message_prefix = ">>> ",
        .message_suffix = " <<<",
        .field_separator = " :: ",
        .enable_nesting = true,
        .nesting_indent = "    ",
    };

    const logger2 = try logly.Logger.initWithConfig(allocator, config2);
    defer logger2.deinit();

    try logger2.info("Message with custom format prefix and suffix", @src());
    try logger2.debug("Nested formatting example", @src());

    std.debug.print("\n3. Color Customization Per Level\n", .{});
    std.debug.print("   Setting custom colors for each log level\n\n", .{});

    var config3 = logly.Config.default();
    config3.level_colors = .{
        .info_color = "\x1b[36m", // cyan
        .warning_color = "\x1b[35m", // magenta
        .error_color = "\x1b[31m", // red
        .success_color = "\x1b[32m", // green
        .critical_color = "\x1b[1;31m", // bold red
        .use_rgb = false,
        .support_background = false,
    };

    const logger3 = try logly.Logger.initWithConfig(allocator, config3);
    defer logger3.deinit();

    try logger3.info("Custom cyan info message", @src());
    try logger3.warning("Custom magenta warning", @src());
    try logger3.err("Custom red error message", @src());

    std.debug.print("\n4. Diagnostics Custom Path\n", .{});
    std.debug.print("   Storing diagnostics logs separately in ./diagnostics folder\n\n", .{});

    var config4 = logly.Config.default();
    config4.emit_system_diagnostics_on_init = true;
    config4.diagnostics_output_path = "./diagnostics/system_info.log";
    config4.logs_root_path = "./logs";

    const logger4 = try logly.Logger.initWithConfig(allocator, config4);
    defer logger4.deinit();

    // Manually emit diagnostics to custom path
    try logger4.logSystemDiagnostics(@src());
    try logger4.info("System diagnostics saved to ./diagnostics/system_info.log", @src());

    std.debug.print("\n5. Highlighter Patterns and Alerts\n", .{});
    std.debug.print("   Configuring pattern matching and alerts\n\n", .{});

    var config5 = logly.Config.default();
    config5.highlighters = .{
        .enabled = true,
        .alert_on_match = true,
        .alert_min_severity = .warning,
        .log_matches = true,
        .max_matches_per_message = 5,
    };

    const logger5 = try logly.Logger.initWithConfig(allocator, config5);
    defer logger5.deinit();

    try logger5.info("Normal log message", @src());
    try logger5.warning("Warning: Database connection timeout detected", @src());
    try logger5.err("ERROR: Critical failure in payment processing", @src());

    std.debug.print("\n6. Combined: All Customizations\n", .{});
    std.debug.print("   Using all customization features together\n\n", .{});

    var config_combined = logly.Config.default();
    config_combined.logs_root_path = "./logs";
    config_combined.diagnostics_output_path = "./logs/diagnostics.log";
    config_combined.emit_system_diagnostics_on_init = true;

    config_combined.format_structure = .{
        .message_prefix = "[APP] ",
        .field_separator = " | ",
        .enable_nesting = true,
    };

    config_combined.level_colors = .{
        .info_color = "\x1b[34m", // blue
        .warning_color = "\x1b[33m", // yellow
        .error_color = "\x1b[31m", // red
    };

    config_combined.highlighters = .{
        .enabled = true,
        .alert_on_match = true,
        .log_matches = true,
    };

    const logger_combined = try logly.Logger.initWithConfig(allocator, config_combined);
    defer logger_combined.deinit();

    _ = try logger_combined.addSink(logly.SinkConfig.file("combined.log"));

    try logger_combined.info("Application initialization complete", @src());
    try logger_combined.warning("High memory usage detected", @src());
    try logger_combined.err("Failed to connect to remote service", @src());

    try logger_combined.logSystemDiagnostics(@src());

    std.debug.print("\nAll customization examples completed!\n", .{});
    std.debug.print("Check ./logs directory for generated log files.\n", .{});
}
