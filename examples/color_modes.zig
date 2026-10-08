const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    _ = logly.Terminal.enableAnsiColors();

    std.debug.print("Color Modes\n\n", .{});

    // 1. Horizontal (default): whole line in level color.
    {
        var config = logly.Config.default();
        config.colorMode = .horizontal;
        const logger = try logly.Logger.initWithConfig(allocator, config);
        defer logger.deinit();
        std.debug.print("Horizontal (whole line)\n", .{});
        try logger.info("Horizontal info", @src());
        try logger.err("Horizontal error", @src());
    }

    // 2. Vertical: per-column colors.
    {
        var config = logly.Config.default();
        config.colorMode = .vertical;
        config.columnColors.timestamp = logly.Color.Tint.color.ansi4.blue;
        config.columnColors.message = logly.Color.Tint.color.ansi4.yellow;
        const logger = try logly.Logger.initWithConfig(allocator, config);
        defer logger.deinit();
        std.debug.print("Vertical (timestamp blue, level default, message yellow)\n", .{});
        try logger.info("Vertical info", @src());
        try logger.err("Vertical error", @src());
    }

    // 3. None: no colors.
    {
        var config = logly.Config.default();
        config.colorMode = .none;
        const logger = try logly.Logger.initWithConfig(allocator, config);
        defer logger.deinit();
        std.debug.print("None (plain)\n", .{});
        try logger.info("Plain info", @src());
    }

    std.debug.print("\nColor modes example completed!\n", .{});
}
