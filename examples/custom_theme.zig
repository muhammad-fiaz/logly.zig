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

    std.debug.print("\n=== Custom Theme Example ===\n", .{});

    // 1. Define a custom theme
    // This overrides the default colors for standard levels
    const neon_theme = logly.Formatter.Theme{
        .trace = "90", // Bright Black (Gray)
        .debug = "35", // Magenta
        .info = "36", // Cyan
        .success = "92", // Bright Green
        .warning = "93", // Bright Yellow
        .err = "91", // Bright Red
        .fail = "31;1", // Red Bold
        .critical = "41;37;1", // White on Red Background
    };

    // Apply the theme to the console sink (first sink)
    if (logger.sinks.items.len > 0) {
        logger.sinks.items[0].formatter.setTheme(neon_theme);
    }

    try logger.trace("Trace message (Gray)", @src());
    try logger.debug("Debug message (Magenta)", @src());
    try logger.info("Info message (Cyan)", @src());
    try logger.success("Success message (Bright Green)", @src());
    try logger.warning("Warning message (Bright Yellow)", @src());
    try logger.err("Error message (Bright Red)", @src());
    try logger.fail("Fail message (Red Bold)", @src());
    try logger.critical("Critical message (White on Red)", @src());

    std.debug.print("\n=== Custom Format Example ===\n", .{});

    // 2. Custom Log Format
    // You can customize the output format using a template string
    var config = logly.Config.default();

    // Available placeholders:
    // {time}     - Timestamp
    // {level}    - Log level name
    // {message}  - The log message
    // {module}   - Module name
    // {function} - Function name
    // {file}     - Filename
    // {line}     - Line number
    // {thread}   - Thread ID

    config.log_format = ">>> {time} | {level} | {message} <<<";
    logger.configure(config);

    try logger.info("This uses a custom format", @src());

    // Another format style
    config.log_format = "[{level}] {message} ({file}:{line})";
    logger.configure(config);

    try logger.warning("Minimal format with location", @src());
}
