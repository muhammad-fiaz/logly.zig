const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create logger
    const logger = try logly.Logger.init(allocator);
    defer logger.deinit();

    std.debug.print("=== Log Filtering Example ===\n\n", .{});

    // Create a filter that only allows warnings and above
    var filter = logly.Filter.init(allocator);
    defer filter.deinit();

    // Add minimum level filter
    try filter.addMinLevel(.warning);

    // Set the filter on the logger
    logger.setFilter(&filter);

    std.debug.print("Filter set to minimum level: WARNING\n", .{});
    std.debug.print("Attempting to log at various levels:\n\n", .{});

    // These should be filtered out
    try logger.trace("This trace message will be filtered");
    try logger.debug("This debug message will be filtered");
    try logger.info("This info message will be filtered");

    // These should pass through
    try logger.warning("This warning will be displayed");
    try logger.err("This error will be displayed");
    try logger.critical("This critical message will be displayed");

    std.debug.print("\n--- Using Filter Presets ---\n\n", .{});

    // Use a preset filter for errors only
    var error_filter = try logly.FilterPresets.errorsOnly(allocator);
    defer error_filter.deinit();

    // Create new logger for errors only
    const error_logger = try logly.Logger.init(allocator);
    defer error_logger.deinit();
    error_logger.setFilter(&error_filter);

    std.debug.print("Error-only filter applied:\n", .{});
    try error_logger.warning("Warning - will be filtered");
    try error_logger.err("Error - will be displayed");
    try error_logger.critical("Critical - will be displayed");

    std.debug.print("\n=== Filtering Example Complete ===\n", .{});
}
