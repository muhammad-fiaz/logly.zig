const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("Append/Overwrite Modes with Rotation\n\n", .{});

    // Example 1: Append Mode + Daily Rotation
    std.debug.print("1. Append Mode + Daily Rotation\n", .{});
    std.debug.print("   Logs append to file, rotation triggers daily\n\n", .{});

    var config1 = logly.Config.default();
    config1.logsRootPath = "./logs";

    const logger1 = try logly.Logger.initWithConfig(allocator, config1);
    defer logger1.deinit();

    var sink1 = logly.SinkConfig.file("append_rotate_daily.log");
    sink1.writeMode = .append;
    sink1.rotation = "daily";
    sink1.retention = 7;

    _ = try logger1.addSink(sink1);

    try logger1.info("Append mode with daily rotation", @src());
    try logger1.info("Previous logs preserved after rotation", @src());
    try logger1.warning("Rotation creates new file daily", @src());

    std.debug.print("   File: append_rotate_daily.log\n\n", .{});

    // Example 2: Overwrite Mode + Size Rotation
    std.debug.print("2. Overwrite Mode + Size Rotation\n", .{});
    std.debug.print("   File truncated on startup, rotates at 1MB\n\n", .{});

    var config2 = logly.Config.default();
    config2.logsRootPath = "./logs";

    const logger2 = try logly.Logger.initWithConfig(allocator, config2);
    defer logger2.deinit();

    var sink2 = logly.SinkConfig.file("overwrite_rotate_size.log");
    sink2.writeMode = .overwrite;
    sink2.rotation = "daily";
    sink2.sizeLimit = 1024 * 1024; // 1MB
    sink2.retention = 3;

    _ = try logger2.addSink(sink2);

    try logger2.info("Overwrite mode - fresh start each run", @src());
    try logger2.info("Rotates when file exceeds 1MB", @src());
    try logger2.warning("Old files archived with retention", @src());

    std.debug.print("   File: overwrite_rotate_size.log\n\n", .{});

    // Example 3: Append Rotate Mode
    std.debug.print("3. Append Rotate Mode (append_rotate)\n", .{});
    std.debug.print("   Explicit append with rotation trigger\n\n", .{});

    var config3 = logly.Config.default();
    config3.logsRootPath = "./logs";

    const logger3 = try logly.Logger.initWithConfig(allocator, config3);
    defer logger3.deinit();

    var sink3 = logly.SinkConfig.file("append_rotate_explicit.log");
    sink3.writeMode = .appendRotate;
    sink3.rotation = "daily";
    sink3.retention = 5;

    _ = try logger3.addSink(sink3);

    try logger3.info("Append rotate mode - append with rotation", @src());
    try logger3.info("Rotation triggers based on config", @src());
    try logger3.warning("Same as append but explicit rotation", @src());

    std.debug.print("   File: append_rotate_explicit.log\n\n", .{});

    // Example 4: Mixed Modes - Different Sinks
    std.debug.print("4. Mixed Modes - Different Sinks, Different Behavior\n", .{});
    std.debug.print("   Each sink can use different write modes\n\n", .{});

    var config4 = logly.Config.default();
    config4.logsRootPath = "./logs";

    const logger4 = try logly.Logger.initWithConfig(allocator, config4);
    defer logger4.deinit();

    // Sink A: Append only (no rotation)
    var sinkA = logly.SinkConfig.file("append_no_rotation.log");
    sinkA.writeMode = .append;
    // No rotation configured - file grows indefinitely

    // Sink B: Overwrite with rotation
    var sinkB = logly.SinkConfig.file("overwrite_with_rotation.log");
    sinkB.writeMode = .overwrite;
    sinkB.rotation = "daily";
    sinkB.retention = 3;

    // Sink C: Append with rotation
    var sinkC = logly.SinkConfig.file("append_with_rotation.log");
    sinkC.writeMode = .append;
    sinkC.rotation = "daily";
    sinkC.retention = 5;

    _ = try logger4.addSink(sinkA);
    _ = try logger4.addSink(sinkB);
    _ = try logger4.addSink(sinkC);

    try logger4.info("Logged to all three sinks", @src());
    try logger4.info("Each sink has different write mode", @src());
    try logger4.info("Rotation behavior varies per sink", @src());

    std.debug.print("   append_no_rotation.log - append, no rotation\n", .{});
    std.debug.print("   overwrite_with_rotation.log - overwrite, daily rotation\n", .{});
    std.debug.print("   append_with_rotation.log - append, daily rotation\n\n", .{});

    // Example 5: JSON with Write Modes
    std.debug.print("5. JSON Output with Write Modes\n", .{});
    std.debug.print("   JSON sinks also respect write_mode\n\n", .{});

    var config5 = logly.Config.default();
    config5.logsRootPath = "./logs";

    const logger5 = try logly.Logger.initWithConfig(allocator, config5);
    defer logger5.deinit();

    var sink5Json = logly.SinkConfig.file("json_append.json");
    sink5Json.format = .json;
    sink5Json.prettyJson = true;
    sink5Json.writeMode = .append;
    sink5Json.rotation = "daily";
    sink5Json.retention = 7;

    _ = try logger5.addSink(sink5Json);

    try logger5.info("JSON append mode with rotation", @src());
    try logger5.warning("JSON files rotate daily", @src());
    try logger5.err("Errors also captured", @src());

    std.debug.print("   json_append.json - JSON append with daily rotation\n\n", .{});

    std.debug.print("Summary\n", .{});
    std.debug.print("Write Modes:\n", .{});
    std.debug.print("  .append         - Append to existing file (default)\n", .{});
    std.debug.print("  .overwrite      - Truncate file on startup\n", .{});
    std.debug.print("  .append_rotate  - Append with explicit rotation trigger\n", .{});
    std.debug.print("\nRotation:\n", .{});
    std.debug.print("  .rotation = \"daily\"   - Rotate daily\n", .{});
    std.debug.print("  .rotation = \"hourly\"  - Rotate hourly\n", .{});
    std.debug.print("  .size_limit = N       - Rotate when file exceeds N bytes\n", .{});
    std.debug.print("  .retention = N        - Keep N rotated files\n", .{});
    std.debug.print("\nAll modes work correctly with rotation.\n", .{});
}
