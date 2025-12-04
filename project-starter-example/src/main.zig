const std = @import("std");
const logly = @import("logly");

// I hope you love logly.zig ^-^
// Don't forget to give https://github.com/muhammad-fiaz/logly.zig a star on GitHub!

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    _ = logly.Terminal.enableAnsiColors();

    std.debug.print("\n", .{});
    std.debug.print("=================================================================\n", .{});
    std.debug.print("           LOGLY STARTER EXAMPLE - Zig Logging Demo\n", .{});
    std.debug.print("=================================================================\n", .{});
    std.debug.print("\n", .{});

    // Create Logger
    const logger = try logly.Logger.init(allocator);
    defer logger.deinit();

    // Configure Logger
    var config = logly.Config.default();
    config.auto_sink = false;
    config.show_time = true;
    config.show_module = true;
    config.show_function = true;
    config.show_filename = true;
    config.show_lineno = true;
    logger.configure(config);

    // Create logs directory
    std.debug.print("[SETUP] Creating logs directory...\n", .{});
    std.fs.cwd().makeDir("logs") catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    // Add Sinks
    std.debug.print("[SINK] Console (colored)\n", .{});
    _ = try logger.add(.{});

    std.debug.print("[SINK] logs/app.log (plain text)\n", .{});
    _ = try logger.add(.{ .path = "logs/app.log" });

    std.debug.print("[SINK] logs/daily.log (daily rotation, 7 days)\n", .{});
    _ = try logger.add(.{ .path = "logs/daily.log", .rotation = "daily", .retention = 7 });

    std.debug.print("[SINK] logs/size_rotated.log (1MB limit, 5 files)\n", .{});
    _ = try logger.add(.{ .path = "logs/size_rotated.log", .size_limit = 1024 * 1024, .retention = 5 });

    std.debug.print("[SINK] logs/errors.log (error-level only)\n", .{});
    _ = try logger.add(.{ .path = "logs/errors.log", .level = .err });

    std.debug.print("\n-----------------------------------------------------------------\n", .{});
    std.debug.print("                       LOGGING EXAMPLES\n", .{});
    std.debug.print("-----------------------------------------------------------------\n\n", .{});

    // Example 1: Context Binding
    std.debug.print(">>> Example 1: Context Binding\n", .{});
    try logger.bind("app", .{ .string = "logly-starter" });
    try logger.bind("version", .{ .string = "1.0.0" });
    try logger.bind("environment", .{ .string = "development" });

    // Example 2: All Log Levels
    std.debug.print("\n>>> Example 2: All Log Levels\n", .{});
    try logger.trace("TRACE - Very detailed debugging information", @src());
    try logger.debug("DEBUG - Debugging information for developers", @src());
    try logger.info("INFO - General information about application state", @src());
    try logger.success("SUCCESS - Operation completed successfully!", @src());
    try logger.warn("WARNING - Something to be aware of", @src());
    try logger.err("ERROR - An error occurred but app continues", @src());
    try logger.fail("FAIL - Operation failed", @src());
    try logger.crit("CRITICAL - Critical system error!", @src());

    // Example 3: Formatted Logging
    std.debug.print("\n>>> Example 3: Formatted Logging\n", .{});
    const username = "Alice";
    const user_id: u32 = 12345;
    const ip_address = "192.168.1.100";

    try logger.infof("User '{s}' (ID: {d}) logged in from {s}", .{ username, user_id, ip_address }, @src());
    try logger.debugf("Processing {d} items in the queue", .{@as(u32, 42)}, @src());
    try logger.warnf("Memory usage at {d}% - consider optimization", .{@as(u32, 85)}, @src());
    try logger.errf("Failed to connect to database after {d} attempts", .{@as(u32, 3)}, @src());

    // Example 4: Request-Specific Context
    std.debug.print("\n>>> Example 4: Request-Specific Context\n", .{});
    try logger.bind("request_id", .{ .string = "req-abc-123" });
    try logger.bind("user_id", .{ .string = "user-456" });

    try logger.info("Processing user request", @src());
    try logger.debug("Validating request parameters", @src());
    try logger.success("Request processed successfully", @src());

    logger.unbind("request_id");
    logger.unbind("user_id");

    // Example 5: Custom Log Levels
    std.debug.print("\n>>> Example 5: Custom Log Levels\n", .{});
    try logger.addCustomLevel("NOTICE", 35, "96");
    try logger.addCustomLevel("AUDIT", 25, "35;1");

    try logger.custom("NOTICE", "This is a custom NOTICE level message", @src());
    try logger.custom("AUDIT", "User action recorded for compliance", @src());
    try logger.customf("AUDIT", "User {s} performed action: {s}", .{ username, "file_download" }, @src());

    // Example 6: Metrics
    std.debug.print("\n>>> Example 6: Metrics Collection\n", .{});
    logger.enableMetrics();
    if (logger.getMetrics()) |metrics| {
        std.debug.print("  Total records: {d}, Errors: {d}\n", .{ metrics.total_records, metrics.error_count });
    }

    // Flush logs
    std.debug.print("\n[FLUSH] Writing all logs to disk...\n", .{});
    try logger.flush();

    // JSON Logging
    std.debug.print("\n>>> Bonus: JSON Formatted Logging\n", .{});
    const json_logger = try logly.Logger.init(allocator);
    defer json_logger.deinit();

    var json_config = logly.Config.default();
    json_config.auto_sink = false;
    json_config.json = true;
    json_config.pretty_json = true;
    json_logger.configure(json_config);

    _ = try json_logger.add(.{ .path = "logs/app.json" });
    try json_logger.bind("app", .{ .string = "logly-starter" });
    try json_logger.bind("version", .{ .string = "1.0.0" });

    try json_logger.info("JSON formatted log entry", @src());
    try json_logger.warn("JSON warning message", @src());
    try json_logger.err("JSON error message", @src());
    try json_logger.flush();

    // Done
    std.debug.print("\n", .{});
    std.debug.print("=================================================================\n", .{});
    std.debug.print("                       DEMO COMPLETED!\n", .{});
    std.debug.print("-----------------------------------------------------------------\n", .{});
    std.debug.print("  Generated Log Files:\n", .{});
    std.debug.print("    - logs/app.log          (Plain text)\n", .{});
    std.debug.print("    - logs/app.json         (JSON format)\n", .{});
    std.debug.print("    - logs/daily.log        (Daily rotation)\n", .{});
    std.debug.print("    - logs/size_rotated.log (Size-based rotation)\n", .{});
    std.debug.print("    - logs/errors.log       (Error-level only)\n", .{});
    std.debug.print("=================================================================\n", .{});
    std.debug.print("\n", .{});
}
