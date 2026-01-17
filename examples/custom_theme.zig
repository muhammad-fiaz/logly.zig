const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Enable ANSI colors
    _ = logly.Terminal.enableAnsiColors();

    const logger = try logly.Logger.init(allocator);
    defer logger.deinit();

    const Theme = logly.Formatter.Theme;

    std.debug.print("\n=== Theme Presets (v0.1.5) ===\n\n", .{});

    // Built-in theme presets
    std.debug.print("Available presets:\n", .{});
    std.debug.print("  Theme.bright()  - Bold/bright colors\n", .{});
    std.debug.print("  Theme.dim()     - Dim colors\n", .{});
    std.debug.print("  Theme.minimal() - Subtle grays\n", .{});
    std.debug.print("  Theme.neon()    - Vivid 256-colors\n", .{});
    std.debug.print("  Theme.pastel()  - Soft colors\n", .{});
    std.debug.print("  Theme.dark()    - Dark terminal\n", .{});
    std.debug.print("  Theme.light()   - Light terminal\n\n", .{});

    // Apply neon theme preset
    if (logger.sinks.items.len > 0) {
        logger.sinks.items[0].formatter.setTheme(Theme.neon());
    }

    std.debug.print("=== Neon Theme ===\n\n", .{});
    try logger.trace("Trace - neon cyan", @src());
    try logger.debug("Debug - neon blue", @src());
    try logger.info("Info - light gray", @src());
    try logger.success("Success - neon green", @src());
    try logger.warning("Warning - neon yellow", @src());
    try logger.err("Error - neon red", @src());
    try logger.critical("Critical - bold red", @src());

    // Switch to pastel theme
    if (logger.sinks.items.len > 0) {
        logger.sinks.items[0].formatter.setTheme(Theme.pastel());
    }

    std.debug.print("\n=== Pastel Theme ===\n\n", .{});
    try logger.trace("Trace - soft cyan", @src());
    try logger.debug("Debug - soft blue", @src());
    try logger.info("Info - light", @src());
    try logger.success("Success - soft green", @src());
    try logger.warning("Warning - soft yellow", @src());
    try logger.err("Error - soft red", @src());

    // Switch to dark theme
    if (logger.sinks.items.len > 0) {
        logger.sinks.items[0].formatter.setTheme(Theme.dark());
    }

    std.debug.print("\n=== Dark Theme ===\n\n", .{});
    try logger.info("Info in dark theme", @src());
    try logger.warning("Warning in dark theme", @src());
    try logger.err("Error in dark theme", @src());

    std.debug.print("\n=== Custom Theme ===\n\n", .{});

    // Define a custom theme manually
    const custom_theme = Theme{
        .trace = "90",
        .debug = "35",
        .info = "36",
        .notice = "96;1",
        .success = "92",
        .warning = "93",
        .err = "91",
        .fail = "31;1",
        .critical = "41;37;1",
        .fatal = "41;97;1",
    };

    if (logger.sinks.items.len > 0) {
        logger.sinks.items[0].formatter.setTheme(custom_theme);
    }

    try logger.trace("Trace (Gray)", @src());
    try logger.debug("Debug (Magenta)", @src());
    try logger.info("Info (Cyan)", @src());
    try logger.success("Success (Bright Green)", @src());
    try logger.warning("Warning (Bright Yellow)", @src());
    try logger.err("Error (Bright Red)", @src());
    try logger.fail("Fail (Red Bold)", @src());
    try logger.critical("Critical (White on Red)", @src());

    std.debug.print("\n=== Theme Colors Reference ===\n\n", .{});

    const neon = Theme.neon();
    std.debug.print("Neon theme colors:\n", .{});
    std.debug.print("  trace:    {s}\n", .{neon.trace});
    std.debug.print("  debug:    {s}\n", .{neon.debug});
    std.debug.print("  info:     {s}\n", .{neon.info});
    std.debug.print("  success:  {s}\n", .{neon.success});
    std.debug.print("  warning:  {s}\n", .{neon.warning});
    std.debug.print("  err:      {s}\n", .{neon.err});
    std.debug.print("  critical: {s}\n", .{neon.critical});
    std.debug.print("  fatal:    {s}\n", .{neon.fatal});

    std.debug.print("\n=== Custom Format Example ===\n\n", .{});

    var config = logly.Config.default();
    config.log_format = ">>> {time} | {level} | {message} <<<";
    logger.configure(config);

    try logger.info("This uses a custom format", @src());

    config.log_format = "[{level}] {message} ({file}:{line})";
    logger.configure(config);

    try logger.warning("Minimal format with location", @src());
}
