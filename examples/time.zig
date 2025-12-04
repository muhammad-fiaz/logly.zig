const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const logger = try logly.Logger.init(allocator);
    defer logger.deinit();

    var config = logly.Config.default();

    // Example 1: Default format (YYYY-MM-DD HH:mm:ss.SSS)
    logger.configure(config);
    try logger.info("Default time format", @src());

    // Example 2: US date format with slashes
    config.time_format = "MM/DD/YYYY HH:mm:ss";
    logger.configure(config);
    try logger.info("US date format (MM/DD/YYYY)", @src());

    // Example 3: European date format
    config.time_format = "DD-MM-YYYY HH:mm:ss";
    logger.configure(config);
    try logger.info("European date format (DD-MM-YYYY)", @src());

    // Example 4: Compact with dots
    config.time_format = "YY.MM.DD HH:mm";
    logger.configure(config);
    try logger.info("Compact format (YY.MM.DD)", @src());

    // Example 5: Time only with milliseconds
    config.time_format = "HH:mm:ss.SSS";
    logger.configure(config);
    try logger.info("Time with milliseconds", @src());

    // Example 6: Date only
    config.time_format = "YYYY-MM-DD";
    logger.configure(config);
    try logger.info("Date only", @src());

    // Example 7: ISO8601 format
    config.time_format = "ISO8601";
    logger.configure(config);
    try logger.info("ISO8601 format", @src());

    // Example 8: Unix timestamp
    config.time_format = "unix";
    logger.configure(config);
    try logger.info("Unix timestamp", @src());

    // Example 9: Custom separator and order
    config.time_format = "DD/MM/YY - HH:mm";
    logger.configure(config);
    try logger.info("Custom separator", @src());
}
