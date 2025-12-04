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

    // Add file sink
    _ = try logger.addSink(.{
        .path = "logs/app.log",
    });

    // Add console sink
    _ = try logger.addSink(.{});

    try logger.info("Logging to both file and console", @src());
    try logger.success("File created in logs/app.log", @src());

    // Flush to ensure all data is written
    try logger.flush();

    std.debug.print("\nFile logging example completed! Check logs/app.log\n", .{});
}
