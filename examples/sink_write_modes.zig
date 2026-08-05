const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== Sink Write Mode Example ===\n\n", .{});

    // Example 1: Append Mode (Default)
    std.debug.print("1. Append Mode (Default Behavior)\n", .{});
    std.debug.print("   Logs are appended to existing files\n\n", .{});

    var config_append = logly.Config.default();
    config_append.logs_root_path = "./logs";

    const logger_append = try logly.Logger.initWithConfig(allocator, config_append);
    defer logger_append.deinit();

    var sink_config_append = logly.SinkConfig.file("append_mode.log");
    sink_config_append.write_mode = .append; // Append mode (default)

    _ = try logger_append.addSink(sink_config_append);

    try logger_append.info("First run - appended to file", @src());
    try logger_append.info("Second entry - also appended", @src());
    try logger_append.warning("Previous logs are preserved", @src());

    std.debug.print("   Logs appended to ./logs/append_mode.log\n\n", .{});

    // Example 2: Overwrite Mode
    std.debug.print("2. Overwrite Mode\n", .{});
    std.debug.print("   Logs overwrite existing files on startup\n\n", .{});

    var config_overwrite = logly.Config.default();
    config_overwrite.logs_root_path = "./logs";

    const logger_overwrite = try logly.Logger.initWithConfig(allocator, config_overwrite);
    defer logger_overwrite.deinit();

    var sink_config_overwrite = logly.SinkConfig.file("overwrite_mode.log");
    sink_config_overwrite.write_mode = .overwrite; // Overwrite mode

    _ = try logger_overwrite.addSink(sink_config_overwrite);

    try logger_overwrite.info("This will be the ONLY content in the file", @src());
    try logger_overwrite.info("Previous runs are discarded", @src());
    try logger_overwrite.warning("Starting fresh each time", @src());

    std.debug.print("   Logs overwrote ./logs/overwrite_mode.log\n\n", .{});

    // Example 3: Append Rotate Mode
    std.debug.print("3. Append Rotate Mode\n", .{});
    std.debug.print("   Appends to file, rotation triggers when configured\n\n", .{});

    var config_rotate = logly.Config.default();
    config_rotate.logs_root_path = "./logs";

    const logger_rotate = try logly.Logger.initWithConfig(allocator, config_rotate);
    defer logger_rotate.deinit();

    var sink_config_rotate = logly.SinkConfig.file("append_rotate.log");
    sink_config_rotate.write_mode = .append_rotate; // Append with rotation
    sink_config_rotate.rotation = "daily"; // Daily rotation
    sink_config_rotate.retention = 7; // Keep 7 days

    _ = try logger_rotate.addSink(sink_config_rotate);

    try logger_rotate.info("Logs append to file", @src());
    try logger_rotate.info("Rotation triggers daily", @src());
    try logger_rotate.warning("Old files are archived", @src());

    std.debug.print("   Logs to ./logs/append_rotate.log with daily rotation\n\n", .{});

    // Example 4: Multiple Sinks with Different Modes
    std.debug.print("4. Mixed Write Modes\n", .{});
    std.debug.print("   Different sinks use different write modes\n\n", .{});

    var config_mixed = logly.Config.default();
    config_mixed.logs_root_path = "./logs";

    const logger_mixed = try logly.Logger.initWithConfig(allocator, config_mixed);
    defer logger_mixed.deinit();

    var sink_persistent = logly.SinkConfig.file("persistent.log");
    sink_persistent.write_mode = .append; // Append - keep all history

    var sink_session = logly.SinkConfig.file("session.log");
    sink_session.write_mode = .overwrite; // Overwrite - fresh start each run

    _ = try logger_mixed.addSink(sink_persistent);
    _ = try logger_mixed.addSink(sink_session);

    try logger_mixed.info("Logged to both persistent.log and session.log", @src());
    try logger_mixed.info("persistent.log keeps all entries", @src());
    try logger_mixed.info("session.log shows only current run", @src());

    std.debug.print("   persistent.log (append): accumulates logs\n", .{});
    std.debug.print("   session.log (overwrite): shows current session only\n\n", .{});

    // Example 5: JSON Output with Write Modes
    std.debug.print("5. JSON Output with Write Modes\n", .{});
    std.debug.print("   JSON sinks also respect write_mode\n\n", .{});

    var config_json = logly.Config.default();
    config_json.logs_root_path = "./logs";

    const logger_json = try logly.Logger.initWithConfig(allocator, config_json);
    defer logger_json.deinit();

    var sink_json = logly.SinkConfig.file("logs.json");
    sink_json.json = true;
    sink_json.pretty_json = true;
    sink_json.write_mode = .append; // Append JSON

    _ = try logger_json.addSink(sink_json);

    try logger_json.info("First JSON entry", @src());
    try logger_json.warning("Second JSON entry", @src());
    try logger_json.err("Third JSON entry", @src());

    std.debug.print("   logs.json contains all entries (array format)\n\n", .{});

    // Example 6: Legacy overwrite_mode (still supported)
    std.debug.print("6. Legacy overwrite_mode Field\n", .{});
    std.debug.print("   overwrite_mode = true is equivalent to write_mode = .overwrite\n\n", .{});

    var config_legacy = logly.Config.default();
    config_legacy.logs_root_path = "./logs";

    const logger_legacy = try logly.Logger.initWithConfig(allocator, config_legacy);
    defer logger_legacy.deinit();

    var sink_legacy = logly.SinkConfig.file("legacy_overwrite.log");
    sink_legacy.overwrite_mode = true; // Legacy field still works

    _ = try logger_legacy.addSink(sink_legacy);

    try logger_legacy.info("Using legacy overwrite_mode field", @src());
    try logger_legacy.warning("This also truncates the file", @src());

    std.debug.print("   legacy_overwrite.log uses overwrite_mode = true\n\n", .{});

    std.debug.print("Write Mode Examples Completed!\n", .{});
    std.debug.print("Check ./logs for:\n", .{});
    std.debug.print("  - append_mode.log (growing file)\n", .{});
    std.debug.print("  - overwrite_mode.log (fresh each run)\n", .{});
    std.debug.print("  - append_rotate.log (append + daily rotation)\n", .{});
    std.debug.print("  - persistent.log (all history)\n", .{});
    std.debug.print("  - session.log (current run only)\n", .{});
    std.debug.print("  - logs.json (JSON array)\n", .{});
    std.debug.print("  - legacy_overwrite.log (legacy field)\n", .{});
}
