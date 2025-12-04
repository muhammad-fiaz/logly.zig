const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Use initWithConfig to disable auto_sink from the start
    var config = logly.Config.default();
    config.auto_sink = false;

    // Enable filename and line number display
    config.show_filename = true;
    config.show_lineno = true;

    // Custom date format
    config.time_format = "default"; // Will use YYYY-MM-DD HH:MM:SS.mmm

    const logger = try logly.Logger.initWithConfig(allocator, config);
    defer logger.deinit();

    // 1. Standard Console Sink (with colors)
    _ = try logger.addSink(.{});

    // 2. Plain Text File Sink (no colors, standard format)
    _ = try logger.addSink(.{
        .path = "logs/plain.txt",
        .color = false, // Explicitly disable colors (though default for files)
    });

    // 3. JSON File Sink
    _ = try logger.addSink(.{
        .path = "logs/data.json",
        .json = true,
    });

    // 4. Pretty JSON File Sink
    _ = try logger.addSink(.{
        .path = "logs/pretty.json",
        .json = true,
        .pretty_json = true,
    });

    // 5. Colored Log File (if you really want ANSI codes in file)
    _ = try logger.addSink(.{
        .path = "logs/colored.log",
        .color = true,
    });

    try logger.info("This message goes to all sinks in different formats!", @src());
    try logger.warning("Check the logs/ directory to see the differences.", @src());

    // Demonstrate clickable links (VS Code terminal format)
    try logger.err("Error at specific line (try clicking the filename in console)", @src());
}
