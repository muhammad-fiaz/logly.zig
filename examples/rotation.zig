const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Use initWithConfig to disable auto_sink from the start
    var config = logly.Config.default();
    config.auto_sink = false;

    const logger = try logly.Logger.initWithConfig(allocator, config);
    defer logger.deinit();

    // Daily rotation with 7 day retention
    _ = try logger.addSink(.{
        .path = "logs/daily.log",
        .rotation = "daily",
        .retention = 7,
    });

    // Size-based rotation (10MB limit)
    _ = try logger.addSink(.{
        .path = "logs/size_based.log",
        .size_limit = 10 * 1024 * 1024,
        .retention = 5,
    });

    // Combined rotation (daily OR 5MB)
    _ = try logger.addSink(.{
        .path = "logs/combined.log",
        .rotation = "daily",
        .size_limit = 5 * 1024 * 1024,
        .retention = 10,
    });

    try logger.info("Rotation example - files will rotate based on time or size", @src());
    try logger.success("Check logs/ directory for rotated files", @src());

    try logger.flush();

    std.debug.print("\nRotation example completed!\n", .{});
}
