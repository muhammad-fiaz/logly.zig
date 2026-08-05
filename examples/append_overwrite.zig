const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== Append/Overwrite Modes with Rotation ===\n\n", .{});

    // Example 1: Append Mode + Daily Rotation
    std.debug.print("1. Append Mode + Daily Rotation\n", .{});
    std.debug.print("   Logs append to file, rotation triggers daily\n\n", .{});

    var config1 = logly.Config.default();
    config1.logs_root_path = "./logs";

    const logger1 = try logly.Logger.initWithConfig(allocator, config1);
    defer logger1.deinit();

    var sink1 = logly.SinkConfig.file("append_rotate_daily.log");
    sink1.write_mode = .append;
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
    config2.logs_root_path = "./logs";

    const logger2 = try logly.Logger.initWithConfig(allocator, config2);
    defer logger2.deinit();

    var sink2 = logly.SinkConfig.file("overwrite_rotate_size.log");
    sink2.write_mode = .overwrite;
    sink2.rotation = "daily";
    sink2.size_limit = 1024 * 1024; // 1MB
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
    config3.logs_root_path = "./logs";

    const logger3 = try logly.Logger.initWithConfig(allocator, config3);
    defer logger3.deinit();

    var sink3 = logly.SinkConfig.file("append_rotate_explicit.log");
    sink3.write_mode = .append_rotate;
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
    config4.logs_root_path = "./logs";

    const logger4 = try logly.Logger.initWithConfig(allocator, config4);
    defer logger4.deinit();

    // Sink A: Append only (no rotation)
    var sink_a = logly.SinkConfig.file("append_no_rotation.log");
    sink_a.write_mode = .append;
    // No rotation configured - file grows indefinitely

    // Sink B: Overwrite with rotation
    var sink_b = logly.SinkConfig.file("overwrite_with_rotation.log");
    sink_b.write_mode = .overwrite;
    sink_b.rotation = "daily";
    sink_b.retention = 3;

    // Sink C: Append with rotation
    var sink_c = logly.SinkConfig.file("append_with_rotation.log");
    sink_c.write_mode = .append;
    sink_c.rotation = "daily";
    sink_c.retention = 5;

    _ = try logger4.addSink(sink_a);
    _ = try logger4.addSink(sink_b);
    _ = try logger4.addSink(sink_c);

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
    config5.logs_root_path = "./logs";

    const logger5 = try logly.Logger.initWithConfig(allocator, config5);
    defer logger5.deinit();

    var sink5_json = logly.SinkConfig.file("json_append.json");
    sink5_json.json = true;
    sink5_json.pretty_json = true;
    sink5_json.write_mode = .append;
    sink5_json.rotation = "daily";
    sink5_json.retention = 7;

    _ = try logger5.addSink(sink5_json);

    try logger5.info("JSON append mode with rotation", @src());
    try logger5.warning("JSON files rotate daily", @src());
    try logger5.err("Errors also captured", @src());

    std.debug.print("   json_append.json - JSON append with daily rotation\n\n", .{});

    std.debug.print("=== Summary ===\n", .{});
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
