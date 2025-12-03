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

    // Configure JSON logging with extra fields and colors
    var config = logly.Config.default();
    config.json = true;
    config.pretty_json = true;
    config.color = true; // Enable colors for JSON output
    config.include_hostname = true;
    config.include_pid = true;
    config.time_format = "default"; // Use formatted time

    logger.configure(config);

    // Add a file sink for JSON output
    _ = try logger.addSink(.{
        .path = "logs/extended.json",
        .json = true,
        .pretty_json = true,
    });

    try logger.info("This JSON log includes hostname and PID");
    try logger.warning("And also uses formatted timestamp");
}
