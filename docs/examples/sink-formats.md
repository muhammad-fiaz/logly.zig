# Sink Formats

This example demonstrates how to configure different output formats for different sinks. You can have one sink writing plain text to the console, another writing raw JSON to a file for ingestion, and a third writing pretty-printed JSON for debugging.

## Code Example

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Enable colors on Windows
    _ = logly.Terminal.enableAnsiColors();

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

    // 1. Standard Console Sink (with colors) - using add() alias
    _ = try logger.add(.{});

    // 2. Plain Text File Sink (no colors)
    _ = try logger.add(.{
        .path = "logs/plain.txt",
        .color = false,
    });

    // 3. JSON File Sink
    _ = try logger.add(.{
        .path = "logs/data.json",
        .json = true,
    });

    // 4. Pretty JSON File Sink
    _ = try logger.add(.{
        .path = "logs/pretty.json",
        .json = true,
        .pretty_json = true,
    });

    try logger.info("This message goes to all sinks in different formats!", @src());
    try logger.err("Error at specific line (try clicking the filename in console)", @src());
}
```

## Expected Output

**Console**:

```text
[INFO] This message goes to all sinks in different formats! (src/main.zig:52)
[ERROR] Error at specific line (try clicking the filename in console) (src/main.zig:53)
```

**logs/data.json**:

```json
{
  "level": "INFO",
  "message": "This message goes to all sinks in different formats!",
  "timestamp": 1717286400000,
  "filename": "src/main.zig",
  "line": 52
}
```

**logs/pretty.json**:

```json
{
  "level": "INFO",
  "message": "This message goes to all sinks in different formats!",
  "timestamp": 1717286400000,
  "filename": "src/main.zig",
  "line": 52
}
```
