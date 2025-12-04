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

    // Add a file sink with async writing enabled (default)
    _ = try logger.addSink(.{
        .path = "logs/async.log",
        .async_write = true,
        .buffer_size = 4096, // 4KB buffer
    });

    // Add a console sink
    _ = try logger.addSink(.{});

    try logger.info("Starting async logging test...", @src());

    // Log many messages quickly
    const start = std.time.milliTimestamp();
    for (0..1000) |i| {
        const msg = try std.fmt.allocPrint(allocator, "Async log message #{d}", .{i});
        defer allocator.free(msg);
        try logger.info(msg, @src());
    }
    const end = std.time.milliTimestamp();

    try logger.info("Finished logging 1000 messages", @src());

    // Flush is important for async sinks before exit
    try logger.flush();

    std.debug.print("Logged 1000 messages in {d}ms\n", .{end - start});
}
