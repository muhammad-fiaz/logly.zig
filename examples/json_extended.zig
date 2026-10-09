const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    // Enable ANSI colors on Windows
    _ = logly.Terminal.enableAnsiColors();

    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const logger = try logly.Logger.init(allocator);
    defer logger.deinit();

    // Configure JSON logging with extra fields and colors
    var config = logly.Config.default();
    config.format = .json;
    config.prettyJson = true;
    config.color = true; // Enable colors for JSON output
    config.includeHostname = true;
    config.includePid = true;
    config.timeFormat = logly.Config.TimeFormat.defaultPattern;

    logger.configure(config);

    // Add a file sink for JSON output
    _ = try logger.addSink(.{
        .path = "logs/extended.json",
        .format = .json,
        .prettyJson = true,
    });

    try logger.info("This JSON log includes hostname and PID", @src());
    try logger.warning("And also uses formatted timestamp", @src());
    try logger.flush();
}
