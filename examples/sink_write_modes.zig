const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("Sink Write Mode Example\n\n", .{});

    // Example 1: Append Mode (Default)
    std.debug.print("1. Append Mode (Default Behavior)\n", .{});
    std.debug.print("   Logs are appended to existing files\n\n", .{});

    var configAppend = logly.Config.default();
    configAppend.logsRootPath = "./logs";

    const loggerAppend = try logly.Logger.initWithConfig(allocator, configAppend);
    defer loggerAppend.deinit();

    var sinkConfigAppend = logly.SinkConfig.file("append_mode.log");
    sinkConfigAppend.writeMode = .append; // Append mode (default)

    _ = try loggerAppend.addSink(sinkConfigAppend);

    try loggerAppend.info("First run - appended to file", @src());
    try loggerAppend.info("Second entry - also appended", @src());
    try loggerAppend.warning("Previous logs are preserved", @src());

    std.debug.print("   Logs appended to ./logs/append_mode.log\n\n", .{});

    // Example 2: Overwrite Mode
    std.debug.print("2. Overwrite Mode\n", .{});
    std.debug.print("   Logs overwrite existing files on startup\n\n", .{});

    var configOverwrite = logly.Config.default();
    configOverwrite.logsRootPath = "./logs";

    const loggerOverwrite = try logly.Logger.initWithConfig(allocator, configOverwrite);
    defer loggerOverwrite.deinit();

    var sinkConfigOverwrite = logly.SinkConfig.file("overwrite_mode.log");
    sinkConfigOverwrite.writeMode = .overwrite; // Overwrite mode

    _ = try loggerOverwrite.addSink(sinkConfigOverwrite);

    try loggerOverwrite.info("This will be the ONLY content in the file", @src());
    try loggerOverwrite.info("Previous runs are discarded", @src());
    try loggerOverwrite.warning("Starting fresh each time", @src());

    std.debug.print("   Logs overwrote ./logs/overwrite_mode.log\n\n", .{});

    // Example 3: Append Rotate Mode
    std.debug.print("3. Append Rotate Mode\n", .{});
    std.debug.print("   Appends to file, rotation triggers when configured\n\n", .{});

    var configRotate = logly.Config.default();
    configRotate.logsRootPath = "./logs";

    const loggerRotate = try logly.Logger.initWithConfig(allocator, configRotate);
    defer loggerRotate.deinit();

    var sinkConfigRotate = logly.SinkConfig.file("append_rotate.log");
    sinkConfigRotate.writeMode = .appendRotate; // Append with rotation
    sinkConfigRotate.rotation = "daily"; // Daily rotation
    sinkConfigRotate.retention = 7; // Keep 7 days

    _ = try loggerRotate.addSink(sinkConfigRotate);

    try loggerRotate.info("Logs append to file", @src());
    try loggerRotate.info("Rotation triggers daily", @src());
    try loggerRotate.warning("Old files are archived", @src());

    std.debug.print("   Logs to ./logs/append_rotate.log with daily rotation\n\n", .{});

    // Example 4: Multiple Sinks with Different Modes
    std.debug.print("4. Mixed Write Modes\n", .{});
    std.debug.print("   Different sinks use different write modes\n\n", .{});

    var configMixed = logly.Config.default();
    configMixed.logsRootPath = "./logs";

    const loggerMixed = try logly.Logger.initWithConfig(allocator, configMixed);
    defer loggerMixed.deinit();

    var sinkPersistent = logly.SinkConfig.file("persistent.log");
    sinkPersistent.writeMode = .append; // Append - keep all history

    var sinkSession = logly.SinkConfig.file("session.log");
    sinkSession.writeMode = .overwrite; // Overwrite - fresh start each run

    _ = try loggerMixed.addSink(sinkPersistent);
    _ = try loggerMixed.addSink(sinkSession);

    try loggerMixed.info("Logged to both persistent.log and session.log", @src());
    try loggerMixed.info("persistent.log keeps all entries", @src());
    try loggerMixed.info("session.log shows only current run", @src());

    std.debug.print("   persistent.log (append): accumulates logs\n", .{});
    std.debug.print("   session.log (overwrite): shows current session only\n\n", .{});

    // Example 5: JSON Output with Write Modes
    std.debug.print("5. JSON Output with Write Modes\n", .{});
    std.debug.print("   JSON sinks also respect write_mode\n\n", .{});

    var configJson = logly.Config.default();
    configJson.logsRootPath = "./logs";

    const loggerJson = try logly.Logger.initWithConfig(allocator, configJson);
    defer loggerJson.deinit();

    var sinkJson = logly.SinkConfig.file("logs.json");
    sinkJson.format = .json;
    sinkJson.prettyJson = true;
    sinkJson.writeMode = .append; // Append JSON

    _ = try loggerJson.addSink(sinkJson);

    try loggerJson.info("First JSON entry", @src());
    try loggerJson.warning("Second JSON entry", @src());
    try loggerJson.err("Third JSON entry", @src());

    std.debug.print("   logs.json contains all entries (array format)\n\n", .{});

    // Example 6: Legacy overwrite_mode (still supported)
    std.debug.print("6. Legacy overwrite_mode Field\n", .{});
    std.debug.print("   overwrite_mode = true is equivalent to write_mode = .overwrite\n\n", .{});

    var configLegacy = logly.Config.default();
    configLegacy.logsRootPath = "./logs";

    const loggerLegacy = try logly.Logger.initWithConfig(allocator, configLegacy);
    defer loggerLegacy.deinit();

    var sinkLegacy = logly.SinkConfig.file("legacy_overwrite.log");
    sinkLegacy.overwriteMode = true; // Legacy field still works

    _ = try loggerLegacy.addSink(sinkLegacy);

    try loggerLegacy.info("Using legacy overwrite_mode field", @src());
    try loggerLegacy.warning("This also truncates the file", @src());

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
