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

    // Log at different levels - entire line is colored!
    // Colors: trace=cyan, debug=blue, info=white, success=green,
    //         warning=yellow, error=red, fail=magenta, critical=bright_red
    try logger.info("This is an info message");
    try logger.success("Operation completed successfully!");
    try logger.warning("This is a warning");
    try logger.err("This is an error");
    try logger.fail("Operation failed");
    try logger.critical("Critical system error!");

    std.debug.print("\nBasic logging example completed!\n", .{});
}
