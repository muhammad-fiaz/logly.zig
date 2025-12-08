const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const logger = try logly.Logger.init(allocator);
    defer logger.deinit();

    // Add a sink with dynamic path
    // We use a test directory to avoid cluttering
    _ = try logger.addSink(.{
        .path = "logs_dynamic/{date}/test-{HH}-{mm}-{ss}.log",
        .json = false,
    });

    try logger.info("This log should be in a date-stamped folder", null);

    // Flush to ensure data is written
    try logger.flush();

    std.debug.print("Check logs_dynamic/ directory for the generated file.\n", .{});
}
