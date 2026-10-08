const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Enable ANSI colors
    _ = logly.Terminal.enableAnsiColors();

    const logger = try logly.Logger.init(allocator);
    defer logger.deinit();

    const Theme = logly.Formatter.Theme;

    std.debug.print("\nTheme Presets\n\n", .{});

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

    std.debug.print("Neon Theme\n\n", .{});
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

    std.debug.print("\nPastel Theme\n\n", .{});
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

    std.debug.print("\nDark Theme\n\n", .{});
    try logger.info("Info in dark theme", @src());
    try logger.warning("Warning in dark theme", @src());
    try logger.err("Error in dark theme", @src());

    std.debug.print("\nCustom Theme\n\n", .{});

    // Define a custom theme manually
    const customTheme = Theme{
        .trace = logly.Color.parse("90").?,
        .debug = logly.Color.parse("35").?,
        .info = logly.Color.parse("36").?,
        .notice = logly.Color.parse("96;1").?,
        .success = logly.Color.parse("92").?,
        .warning = logly.Color.parse("93").?,
        .err = logly.Color.parse("91").?,
        .fail = logly.Color.parse("31;1").?,
        .critical = logly.Color.parse("41;37;1").?,
        .fatal = logly.Color.parse("41;97;1").?,
    };

    if (logger.sinks.items.len > 0) {
        logger.sinks.items[0].formatter.setTheme(customTheme);
    }

    try logger.trace("Trace (Gray)", @src());
    try logger.debug("Debug (Magenta)", @src());
    try logger.info("Info (Cyan)", @src());
    try logger.success("Success (Bright Green)", @src());
    try logger.warning("Warning (Bright Yellow)", @src());
    try logger.err("Error (Bright Red)", @src());
    try logger.fail("Fail (Red Bold)", @src());
    try logger.critical("Critical (White on Red)", @src());

    std.debug.print("\nTheme Colors Reference\n\n", .{});

    const neon = Theme.neon();
    std.debug.print("Neon theme colors:\n", .{});
    std.debug.print("  trace:    {s}sample{s}\n", .{ logly.Color.sequence(neon.trace, .trueColor).slice(), logly.Color.resetAll });
    std.debug.print("  debug:    {s}sample{s}\n", .{ logly.Color.sequence(neon.debug, .trueColor).slice(), logly.Color.resetAll });
    std.debug.print("  info:    {s}sample{s}\n", .{ logly.Color.sequence(neon.info, .trueColor).slice(), logly.Color.resetAll });
    std.debug.print("  success:    {s}sample{s}\n", .{ logly.Color.sequence(neon.success, .trueColor).slice(), logly.Color.resetAll });
    std.debug.print("  warning:    {s}sample{s}\n", .{ logly.Color.sequence(neon.warning, .trueColor).slice(), logly.Color.resetAll });
    std.debug.print("  err:    {s}sample{s}\n", .{ logly.Color.sequence(neon.err, .trueColor).slice(), logly.Color.resetAll });
    std.debug.print("  critical:    {s}sample{s}\n", .{ logly.Color.sequence(neon.critical, .trueColor).slice(), logly.Color.resetAll });
    std.debug.print("  fatal:    {s}sample{s}\n", .{ logly.Color.sequence(neon.fatal, .trueColor).slice(), logly.Color.resetAll });

    std.debug.print("\nCustom Format Example\n\n", .{});

    var config = logly.Config.default();
    config.logFormat = ">>> {time} | {level} | {message} <<<";
    logger.configure(config);

    try logger.info("This uses a custom format", @src());

    config.logFormat = "[{level}] {message} ({file}:{line})";
    logger.configure(config);

    try logger.warning("Minimal format with location", @src());
}
