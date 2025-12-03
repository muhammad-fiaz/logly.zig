const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Enable ANSI colors on Windows
    _ = logly.Terminal.enableAnsiColors();

    std.debug.print("=== Custom Levels Full Feature Test ===\n\n", .{});

    // Test 1: Custom levels with console color output
    try testConsoleWithColor(allocator);

    // Test 2: Custom levels with file output (text format)
    try testFileOutput(allocator);

    // Test 3: Custom levels with JSON console output
    try testJsonConsole(allocator);

    // Test 4: Custom levels with JSON file output
    try testJsonFile(allocator);

    // Test 5: Custom levels with context binding
    try testWithContext(allocator);

    // Test 6: Custom levels with formatted messages
    try testFormatted(allocator);

    std.debug.print("\n=== All Custom Level Tests Completed! ===\n", .{});
}

fn testConsoleWithColor(allocator: std.mem.Allocator) !void {
    std.debug.print("--- Test 1: Console with Color ---\n", .{});

    const logger = try logly.Logger.init(allocator);
    defer logger.deinit();

    // Register custom levels with distinct colors
    try logger.addCustomLevel("AUDIT", 25, "35;1"); // Magenta Bold
    try logger.addCustomLevel("SECURITY", 45, "31;7"); // Red Reverse
    try logger.addCustomLevel("METRIC", 15, "36"); // Cyan

    try logger.info("Standard INFO message");
    try logger.custom("AUDIT", "User login recorded");
    try logger.custom("SECURITY", "Access control check passed");
    try logger.custom("METRIC", "Response time: 42ms");
    try logger.err("Standard ERROR message");

    std.debug.print("\n", .{});
}

fn testFileOutput(allocator: std.mem.Allocator) !void {
    std.debug.print("--- Test 2: File Output (Text) ---\n", .{});

    const logger = try logly.Logger.init(allocator);
    defer logger.deinit();

    // Disable auto console sink
    var config = logly.Config.default();
    config.auto_sink = false;
    logger.configure(config);

    // Add file sink
    _ = try logger.addSink(.{
        .path = "logs/custom_levels.log",
    });

    // Add console sink for verification
    _ = try logger.addSink(.{});

    // Register custom level
    try logger.addCustomLevel("AUDIT", 25, "35");

    try logger.info("Standard info to file");
    try logger.custom("AUDIT", "Custom AUDIT level in file");
    try logger.warning("Standard warning to file");

    try logger.flush();

    std.debug.print("Written to logs/custom_levels.log\n\n", .{});
}

fn testJsonConsole(allocator: std.mem.Allocator) !void {
    std.debug.print("--- Test 3: JSON Console Output ---\n", .{});

    const logger = try logly.Logger.init(allocator);
    defer logger.deinit();

    var config = logly.Config.default();
    config.json = true;
    config.pretty_json = true;
    config.color = true;
    logger.configure(config);

    // Register custom level
    try logger.addCustomLevel("AUDIT", 25, "35");

    try logger.info("Standard JSON info");
    try logger.custom("AUDIT", "Custom AUDIT in JSON format");

    std.debug.print("\n", .{});
}

fn testJsonFile(allocator: std.mem.Allocator) !void {
    std.debug.print("--- Test 4: JSON File Output ---\n", .{});

    const logger = try logly.Logger.init(allocator);
    defer logger.deinit();

    var config = logly.Config.default();
    config.auto_sink = false;
    logger.configure(config);

    // Add JSON file sink
    _ = try logger.addSink(.{
        .path = "logs/custom_levels.json",
        .json = true,
        .pretty_json = true,
    });

    // Add console sink
    _ = try logger.addSink(.{
        .json = true,
        .pretty_json = true,
    });

    // Register custom level
    try logger.addCustomLevel("AUDIT", 25, "35");
    try logger.addCustomLevel("SECURITY", 45, "31");

    try logger.info("JSON file test - standard info");
    try logger.custom("AUDIT", "JSON file test - custom AUDIT");
    try logger.custom("SECURITY", "JSON file test - custom SECURITY");

    try logger.flush();

    std.debug.print("Written to logs/custom_levels.json\n\n", .{});
}

fn testWithContext(allocator: std.mem.Allocator) !void {
    std.debug.print("--- Test 5: Custom Levels with Context ---\n", .{});

    const logger = try logly.Logger.init(allocator);
    defer logger.deinit();

    var config = logly.Config.default();
    config.json = true;
    config.pretty_json = true;
    logger.configure(config);

    // Bind context
    try logger.bind("service", .{ .string = "auth-service" });
    try logger.bind("version", .{ .string = "2.0.0" });

    // Register custom level
    try logger.addCustomLevel("AUDIT", 25, "35");

    try logger.custom("AUDIT", "User authentication successful");

    // Add request context
    try logger.bind("user_id", .{ .string = "user-12345" });
    try logger.bind("session_id", .{ .string = "sess-67890" });

    try logger.custom("AUDIT", "Permission check passed");

    std.debug.print("\n", .{});
}

fn testFormatted(allocator: std.mem.Allocator) !void {
    std.debug.print("--- Test 6: Formatted Custom Level Messages ---\n", .{});

    const logger = try logly.Logger.init(allocator);
    defer logger.deinit();

    // Register custom level
    try logger.addCustomLevel("METRIC", 15, "36");
    try logger.addCustomLevel("AUDIT", 25, "35;1");

    // Formatted messages with custom levels
    try logger.customf("METRIC", "Response time: {d}ms", .{42});
    try logger.customf("METRIC", "Memory usage: {d}MB", .{256});
    try logger.customf("AUDIT", "User {s} logged in from {s}", .{ "john_doe", "192.168.1.100" });

    std.debug.print("\n", .{});
}
