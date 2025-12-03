const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const logger = try logly.Logger.init(allocator);
    defer logger.deinit();

    var config = logly.Config.default();

    // Example 1: Default format
    logger.configure(config);
    try logger.info("Default time format");

    // Example 2: Custom time format
    config.time_format = "HH:mm:ss";
    logger.configure(config);
    try logger.info("Short time format");

    // Example 3: UTC timezone
    config.timezone = .utc;
    logger.configure(config);
    try logger.info("UTC time");
}
