const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Enable ANSI colors on Windows (no-op on Linux/macOS)
    // This ensures colors display correctly on all platforms
    _ = logly.Terminal.enableAnsiColors();

    const logger = try logly.Logger.init(allocator);
    defer logger.deinit();

    // Define custom colors for levels
    // Format: "FG;BG;STYLE" or just "FG"
    // Colors: 30=Black, 31=Red, 32=Green, 33=Yellow, 34=Blue, 35=Magenta, 36=Cyan, 37=White
    // Bright: 90-97 for bright versions (e.g., 91=Bright Red)
    // Styles: 1=Bold, 4=Underline, 7=Reverse
    // Background: 40-47, 100-107 for bright backgrounds

    // Add custom levels with specific colors
    // The ENTIRE log line will be colored (timestamp, level, and message)
    try logger.addCustomLevel("NOTICE", 22, "36;1"); // Cyan Bold
    try logger.addCustomLevel("ALERT", 42, "31;4"); // Red Underline
    try logger.addCustomLevel("HIGHLIGHT", 52, "33;1;7"); // Yellow Bold Reverse

    // Standard levels with their colors (entire line colored):
    // TRACE:    36 (Cyan)
    // DEBUG:    34 (Blue)
    // INFO:     37 (White)
    // SUCCESS:  32 (Green)
    // WARNING:  33 (Yellow)
    // ERROR:    31 (Red)
    // FAIL:     35 (Magenta)
    // CRITICAL: 91 (Bright Red)

    std.debug.print("=== Whole-Line Color Demo ===\n\n", .{});

    try logger.info("Standard Info - entire line is white");
    try logger.success("Success message - entire line is green");
    try logger.warning("Warning message - entire line is yellow");
    try logger.err("Error message - entire line is red");
    try logger.critical("Critical message - entire line is bright red");

    std.debug.print("\n=== Custom Level Colors ===\n\n", .{});

    try logger.custom("NOTICE", "This is a notice (Cyan Bold) - entire line colored");
    try logger.custom("ALERT", "This is an alert (Red Underline) - entire line colored");
    try logger.custom("HIGHLIGHT", "This is highlighted (Yellow Bold Reverse)");

    std.debug.print("\n=== Platform Support ===\n", .{});
    std.debug.print("Colors work on: Linux, macOS, Windows 10+, VS Code Terminal, etc.\n", .{});
    std.debug.print("For Windows, Terminal.enableAnsiColors() enables Virtual Terminal Processing.\n\n", .{});

    std.debug.print("Custom colors example completed!\n", .{});
}
