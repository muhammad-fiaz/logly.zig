const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const logger = try logly.Logger.init(allocator);
    defer logger.deinit();

    // Configure to disable auto console sink
    var config = logly.Config.default();
    config.auto_sink = false;
    logger.configure(config);

    // Add file sink
    _ = try logger.addSink(.{
        .path = "logs/app.log",
    });

    // Add console sink
    _ = try logger.addSink(.{});

    try logger.info("Logging to both file and console");
    try logger.success("File created in logs/app.log");

    // Flush to ensure all data is written
    try logger.flush();

    std.debug.print("\nFile logging example completed! Check logs/app.log\n", .{});
}
