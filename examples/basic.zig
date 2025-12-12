const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Enable ANSI colors on Windows (no-op on Linux/macOS)
    // This ensures colors display correctly on all platforms
    _ = logly.Terminal.enableAnsiColors();

    // Create logger (auto-sink enabled by default)
    const logger = try logly.Logger.init(allocator);
    defer logger.deinit();

    // Configure to show filename and line number (clickable in terminals)
    var config = logly.Config.default();
    config.show_filename = true;
    config.show_lineno = true;
    config.capture_stack_trace = true; // Enable stack trace capture
    config.symbolize_stack_trace = true; // Enable symbolization
    logger.configure(config);

    // Log at different levels - entire line is colored!
    // Colors: trace=cyan, debug=blue, info=white, success=green,
    //         warning=yellow, error=red, fail=magenta, critical=bright_red
    // Pass @src() to get clickable file:line:column in terminal output
    try logger.info("This is an info message", @src());
    try logger.success("Operation completed successfully!", @src());
    try logger.warning("This is a warning", @src());
    try logger.err("This is an error", @src());
    try logger.fail("Operation failed", @src());
    try logger.critical("Critical system error!", @src());

    // Without @src(), file/line won't be displayed
    std.debug.print("\n--- Logs without @src() (no file:line) ---\n", .{});
    try logger.info("This log has no source location", null);

    std.debug.print("\nBasic logging example completed!\n", .{});
}
