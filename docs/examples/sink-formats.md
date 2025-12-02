# Sink Formats

This example demonstrates how to configure different output formats for different sinks, including plain text, JSON, and pretty-printed JSON. It also shows how to customize date formatting and enable clickable file links.

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const logger = try logly.Logger.init(allocator);
    defer logger.deinit();

    // Disable auto console sink to configure everything manually
    var config = logly.Config.default();
    config.auto_sink = false;

    // Enable filename and line number display (Clickable in VS Code)
    config.show_filename = true;
    config.show_lineno = true;

    // Custom date format (YYYY-MM-DD HH:MM:SS.mmm)
    config.time_format = "default";

    logger.configure(config);

    // 1. Standard Console Sink (with colors)
    _ = try logger.addSink(.{});

    // 2. Plain Text File Sink (no colors)
    _ = try logger.addSink(.{
        .path = "logs/plain.txt",
        .color = false,
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

    try logger.info("This message goes to all sinks in different formats!");
    try logger.err("Error at specific line (try clicking the filename in console)");
}
```
