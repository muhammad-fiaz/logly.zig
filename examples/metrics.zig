const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== Metrics Collection Example ===\n\n", .{});

    // Create logger
    const logger = try logly.Logger.init(allocator);
    defer logger.deinit();

    // Enable metrics collection on the logger
    logger.enableMetrics();

    std.debug.print("--- Logging messages to collect metrics ---\n\n", .{});

    // Log various messages
    try logger.trace("Trace message 1");
    try logger.debug("Debug message 1");
    try logger.debug("Debug message 2");
    try logger.info("Info message 1");
    try logger.info("Info message 2");
    try logger.info("Info message 3");
    try logger.warning("Warning message 1");
    try logger.err("Error message 1");
    try logger.critical("Critical message 1");

    std.debug.print("\n--- Metrics Snapshot ---\n\n", .{});

    // Get metrics snapshot from logger
    if (logger.getMetrics()) |snapshot| {
        std.debug.print("Total Records:      {d}\n", .{snapshot.total_records});
        std.debug.print("Total Bytes:        {d}\n", .{snapshot.total_bytes});
        std.debug.print("Dropped Records:    {d}\n", .{snapshot.dropped_records});
        std.debug.print("Error Count:        {d}\n", .{snapshot.error_count});
        std.debug.print("Uptime (ms):        {d}\n", .{snapshot.uptime_ms});
        std.debug.print("Records/second:     {d:.2}\n", .{snapshot.records_per_second});
        std.debug.print("Bytes/second:       {d:.2}\n", .{snapshot.bytes_per_second});

        std.debug.print("\n--- Level Breakdown ---\n\n", .{});

        std.debug.print("Trace:    {d}\n", .{snapshot.level_counts[0]});
        std.debug.print("Debug:    {d}\n", .{snapshot.level_counts[1]});
        std.debug.print("Info:     {d}\n", .{snapshot.level_counts[2]});
        std.debug.print("Success:  {d}\n", .{snapshot.level_counts[3]});
        std.debug.print("Warning:  {d}\n", .{snapshot.level_counts[4]});
        std.debug.print("Error:    {d}\n", .{snapshot.level_counts[5]});
        std.debug.print("Fail:     {d}\n", .{snapshot.level_counts[6]});
        std.debug.print("Critical: {d}\n", .{snapshot.level_counts[7]});
    } else {
        std.debug.print("Metrics not enabled\n", .{});
    }

    std.debug.print("\n=== Metrics Example Complete ===\n", .{});
}
