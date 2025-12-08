const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
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

    // Create sink with append mode (default)
    var sink_config_append = logly.SinkConfig.file("append_mode.log");
    sink_config_append.overwrite_mode = false; // Append mode (default)

    _ = try logger_append.addSink(sink_config_append);

    try logger_append.info("First run - appended to file", @src());
    try logger_append.info("Second entry - also appended", @src());
    try logger_append.warning("Previous logs are preserved", @src());

    std.debug.print("   Logs appended to ./logs/append_mode.log\n\n", .{});

    // Example 2: Overwrite Mode
    std.debug.print("2. Overwrite Mode (New Feature)\n", .{});
    std.debug.print("   Logs overwrite existing files\n\n", .{});

    var config_overwrite = logly.Config.default();
    config_overwrite.logs_root_path = "./logs";

    const logger_overwrite = try logly.Logger.initWithConfig(allocator, config_overwrite);
    defer logger_overwrite.deinit();

    // Create sink with overwrite mode
    var sink_config_overwrite = logly.SinkConfig.file("overwrite_mode.log");
    sink_config_overwrite.overwrite_mode = true; // Enable overwrite mode

    _ = try logger_overwrite.addSink(sink_config_overwrite);

    try logger_overwrite.info("This will be the ONLY content in the file", @src());
    try logger_overwrite.info("Previous runs are discarded", @src());
    try logger_overwrite.warning("Starting fresh each time", @src());

    std.debug.print("   Logs overwrote ./logs/overwrite_mode.log\n\n", .{});

    // Example 3: Multiple Sinks with Different Modes
    std.debug.print("3. Mixed Write Modes\n", .{});
    std.debug.print("   Different sinks use different write modes\n\n", .{});

    var config_mixed = logly.Config.default();
    config_mixed.logs_root_path = "./logs";

    const logger_mixed = try logly.Logger.initWithConfig(allocator, config_mixed);
    defer logger_mixed.deinit();

    // Sink 1: Append mode for persistent logging
    var sink_persistent = logly.SinkConfig.file("persistent.log");
    sink_persistent.overwrite_mode = false; // Append - keep all history

    // Sink 2: Overwrite mode for current session only
    var sink_session = logly.SinkConfig.file("session.log");
    sink_session.overwrite_mode = true; // Overwrite - fresh start each run

    _ = try logger_mixed.addSink(sink_persistent);
    _ = try logger_mixed.addSink(sink_session);

    try logger_mixed.info("Logged to both persistent.log and session.log", @src());
    try logger_mixed.info("persistent.log keeps all entries", @src());
    try logger_mixed.info("session.log shows only current run", @src());

    std.debug.print("   persistent.log (append): accumulates logs\n", .{});
    std.debug.print("   session.log (overwrite): shows current session only\n\n", .{});

    // Example 4: JSON Output with Overwrite
    std.debug.print("4. JSON Output with Write Modes\n", .{});
    std.debug.print("   JSON sinks also respect overwrite_mode\n\n", .{});

    var config_json = logly.Config.default();
    config_json.logs_root_path = "./logs";

    const logger_json = try logly.Logger.initWithConfig(allocator, config_json);
    defer logger_json.deinit();

    // JSON append sink
    var sink_json_append = logly.SinkConfig.file("logs.json");
    sink_json_append.json = true;
    sink_json_append.pretty_json = true;
    sink_json_append.overwrite_mode = false; // Append JSON

    _ = try logger_json.addSink(sink_json_append);

    try logger_json.info("First JSON entry", @src());
    try logger_json.warning("Second JSON entry", @src());
    try logger_json.err("Third JSON entry", @src());

    std.debug.print("   logs.json contains all entries (array format)\n\n", .{});

    std.debug.print("Write Mode Examples Completed!\n", .{});
    std.debug.print("Check ./logs for:\n", .{});
    std.debug.print("  - append_mode.log (growing file)\n", .{});
    std.debug.print("  - overwrite_mode.log (fresh each run)\n", .{});
    std.debug.print("  - persistent.log (all history)\n", .{});
    std.debug.print("  - session.log (current run only)\n", .{});
    std.debug.print("  - logs.json (JSON array)\n", .{});
}
