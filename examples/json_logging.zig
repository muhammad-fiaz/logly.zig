const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    // Enable ANSI colors on Windows
    _ = logly.Terminal.enableAnsiColors();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const logger = try logly.Logger.init(allocator);
    defer logger.deinit();

    // Enable JSON output with colors
    var config = logly.Config.default();
    config.json = true;
    config.pretty_json = true;
    config.color = true; // Enable colors for JSON output
    logger.configure(config);

    // Bind context that will appear in all logs
    try logger.bind("app", .{ .string = "myapp" });
    try logger.bind("version", .{ .string = "1.0.0" });
    try logger.bind("environment", .{ .string = "production" });

    try logger.info("Application started");
    try logger.success("All systems operational");

    // Add request-specific context
    try logger.bind("request_id", .{ .string = "req-12345" });
    try logger.bind("user_id", .{ .string = "user-67890" });

    try logger.info("Processing user request");

    // Clean up request context
    logger.unbind("request_id");
    logger.unbind("user_id");

    try logger.info("Request completed");

    std.debug.print("\nJSON logging example completed!\n", .{});
}
