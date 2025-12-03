# JSON Logging

This example demonstrates how to enable JSON logging with colors and use context binding. JSON logging is essential for modern log aggregation systems like ELK, Datadog, or CloudWatch.

## Code Example

```zig
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

    // Enable JSON output with colors
    var config = logly.Config.default();
    config.json = true;
    config.pretty_json = true;
    config.color = true;  // Enable colors for JSON output
    logger.configure(config);

    // Bind context that will appear in all logs
    try logger.bind("app", .{ .string = "myapp" });
    try logger.bind("version", .{ .string = "1.0.0" });
    try logger.bind("environment", .{ .string = "production" });

    try logger.info("Application started");
    try logger.success("All systems operational");
    try logger.warning("Connection pool near capacity");
    try logger.err("Database connection failed");

    std.debug.print("\nJSON logging example completed!\n", .{});
}
```

## JSON with Colors

JSON output now supports ANSI colors based on log level, just like console output:

- **INFO** - White text
- **SUCCESS** - Green text  
- **WARNING** - Yellow text
- **ERROR** - Red text
- **DEBUG** - Blue text
- **CRITICAL** - Bright red text

To enable JSON colors:

```zig
var config = logly.Config.default();
config.json = true;
config.color = true;  // Enable colors for JSON
logger.configure(config);
```

## Expected Output

With colors enabled, the entire JSON block will be colored based on the log level:

```json
{
  "timestamp": "2024-01-15 10:30:45.+000",
  "level": "INFO",
  "message": "Application started",
  "app": "myapp",
  "version": "1.0.0",
  "environment": "production"
}
```

## JSON File Output (Valid JSON Array)

When logging JSON to files, Logly automatically formats the output as a valid JSON array with proper comma separators:

```zig
// Add a JSON file sink
_ = try logger.addSink(.{
    .path = "logs/app.json",
    .json = true,
    .pretty_json = true,
});

try logger.info("First message");
try logger.warning("Second message");
try logger.err("Third message");
```

**File output (`logs/app.json`):**
```json
[
{
  "timestamp": "2024-01-15 10:30:45.+000",
  "level": "INFO",
  "message": "First message"
},
{
  "timestamp": "2024-01-15 10:30:45.+001",
  "level": "WARNING",
  "message": "Second message"
},
{
  "timestamp": "2024-01-15 10:30:45.+002",
  "level": "ERROR",
  "message": "Third message"
}
]
```

This ensures the JSON file is always valid and can be parsed by any JSON parser.

## Console vs File JSON

| Feature | Console Output | File Output |
|---------|---------------|-------------|
| Format | Individual JSON objects | JSON array `[...]` |
| Separators | Newline between objects | Comma `,` between objects |
| Colors | Supported (ANSI codes) | No colors (plain text) |
| Valid JSON | Each line is valid | Entire file is valid |

## Disable JSON Colors

To output plain JSON without ANSI codes (for file storage or log aggregation):

```zig
var config = logly.Config.default();
config.json = true;
config.color = false;  // No colors in JSON
logger.configure(config);
```

## Custom Levels in JSON

Custom levels display their actual names and colors in JSON:

```zig
try logger.addCustomLevel("AUDIT", 35, "35");  // Magenta
try logger.custom("AUDIT", "User login event");
```

Output (colored in magenta):
```json
{
  "timestamp": "2024-01-15 10:30:45.+000",
  "level": "AUDIT",
  "message": "User login event"
}
```
