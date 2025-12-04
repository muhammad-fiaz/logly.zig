# Advanced Configuration

This example demonstrates how to leverage advanced configuration options including custom log formats, timestamps, timezone settings, colors, and enterprise features.

## Centralized Configuration Types

Logly now provides centralized configuration for all modules:

```zig
const logly = @import("logly");

// Access all config types from logly namespace
const ThreadPoolConfig = logly.ThreadPoolConfig;
const SchedulerConfig = logly.SchedulerConfig;
const CompressionConfig = logly.CompressionConfig;
const AsyncConfig = logly.AsyncConfig;

// Build comprehensive config using helper methods
var config = logly.Config.default()
    .withThreadPool(.{ .worker_count = 4 })
    .withScheduler(.{ .max_tasks = 256 })
    .withCompression(.{ .level = 6 })
    .withAsync(.{ .buffer_size = 4096 });
```

## Code Example

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Enable ANSI colors on Windows
    _ = logly.Terminal.enableAnsiColors();

    // Initialize logger
    const logger = try logly.Logger.init(allocator);
    defer logger.deinit();

    // ============================================
    // SECTION 1: Custom Log Format
    // ============================================
    var config = logly.Config.default();
    
    // Available placeholders:
    // {time}, {level}, {message}, {module}, {function}, {file}, {line}, {trace_id}, {span_id}
    config.log_format = "{time} | {level} | {message}";
    config.time_format = "YYYY-MM-DD HH:mm:ss";
    config.timezone = .utc;
    
    logger.configure(config);
    
    try logger.info("Custom format with pipe separators", @src());
    try logger.warn("Notice the UTC timestamp", @src());  // Short alias for warning

    // ============================================
    // SECTION 2: Unix Timestamp Format
    // ============================================
    config.time_format = "unix";
    logger.configure(config);
    
    try logger.info("Now using Unix timestamp", @src());

    // ============================================
    // SECTION 3: Clickable File Links
    // ============================================
    config.time_format = "YYYY-MM-DD HH:mm:ss";
    config.show_filename = true;
    config.show_lineno = true;
    config.log_format = null;  // Use default format to show file:line
    logger.configure(config);
    
    try logger.debug("This shows file:line for VS Code clickable links", @src());

    // ============================================
    // SECTION 4: Color Configuration
    // ============================================
    
    // Global color control
    config.global_color_display = true;  // Master switch for all colors
    config.color = true;                  // Enable ANSI color codes
    logger.configure(config);
    
    try logger.info("Colors enabled globally", @src());
    try logger.success("Green success message", @src());
    try logger.err("Red error message", @src());

    // Disable colors
    config.global_color_display = false;
    logger.configure(config);
    
    try logger.info("Colors now disabled", @src());

    // Re-enable for remaining examples
    config.global_color_display = true;
    logger.configure(config);

    // ============================================
    // SECTION 5: Custom Levels with Colors
    // ============================================
    
    // Define custom levels with ANSI color codes
    try logger.addCustomLevel("AUDIT", 35, "35");       // Magenta (priority 35)
    try logger.addCustomLevel("NOTICE", 22, "36;1");   // Bold Cyan (priority 22)
    try logger.addCustomLevel("ALERT", 48, "31;1");    // Bold Red (priority 48)
    try logger.addCustomLevel("SECURITY", 55, "91;4"); // Underline Bright Red
    
    try logger.custom("AUDIT", "User login event", @src());
    try logger.custom("NOTICE", "System maintenance scheduled", @src());
    try logger.custom("ALERT", "High memory usage detected", @src());
    try logger.customf("SECURITY", "Failed login from IP: {s}", .{"192.168.1.100"}, @src());

    // ============================================
    // SECTION 6: JSON Configuration
    // ============================================
    
    config.json = true;
    config.pretty_json = true;
    config.global_color_display = false;  // Colors don't apply to JSON structure
    logger.configure(config);
    
    try logger.info("JSON formatted output", @src());
    try logger.custom("AUDIT", "JSON with custom level name", @src());

    // ============================================
    // SECTION 7: Multiple Sinks with Different Settings
    // ============================================
    
    // Reset to text format
    config.json = false;
    config.global_color_display = true;
    config.auto_sink = false;  // Disable default console sink
    logger.configure(config);
    
    // Console sink with colors (using add() alias)
    _ = try logger.add(.{
        .color = true,
    });
    
    // File sink without colors
    _ = try logger.add(.{
        .path = "logs/app.log",
        .color = false,
    });
    
    // JSON file sink
    _ = try logger.add(.{
        .path = "logs/app.json",
        .json = true,
        .pretty_json = false,
        .color = false,
    });
    
    // Error-only file sink
    _ = try logger.add(.{
        .path = "logs/errors.log",
        .level = .err,
        .color = false,
    });

    try logger.info("This goes to console (colored) and app.log (no color)", @src());
    try logger.err("This goes to all sinks including errors.log", @src());

    try logger.flush();
    std.debug.print("\nAdvanced configuration example completed!\n", .{});
}
```

## Custom Log Format Placeholders

| Placeholder | Description | Example Output |
|-------------|-------------|----------------|
| `{time}` | Timestamp | `2024-01-15 10:30:45.000` |
| `{level}` | Log level | `INFO`, `WARNING`, `AUDIT` |
| `{message}` | Log message | `Application started` |
| `{module}` | Module name | `database`, `http` |
| `{function}` | Function name | `handleRequest` |
| `{file}` | Source filename | `src/main.zig` |
| `{line}` | Line number | `42` |
| `{trace_id}` | Distributed trace ID | `trace-abc-123` |
| `{span_id}` | Span ID | `span-xyz-789` |

## Format Examples

```zig
// Pipe-separated format
config.log_format = "{time} | {level} | {message}";
// Output: 2024-01-15 10:30:45 | INFO | Hello

// Compact format
config.log_format = "[{level}] {message}";
// Output: [INFO] Hello

// With source location
config.log_format = "{time} [{level}] {file}:{line} - {message}";
// Output: 2024-01-15 10:30:45 [INFO] src/main.zig:42 - Hello

// With tracing
config.log_format = "[{trace_id}:{span_id}] {level}: {message}";
// Output: [trace-abc:span-123] INFO: Hello
```

## Color Code Reference

| Color | Code | Bright | Modifier |
|-------|------|--------|----------|
| Black | 30 | 90 | Bold: `;1` |
| Red | 31 | 91 | Underline: `;4` |
| Green | 32 | 92 | Reverse: `;7` |
| Yellow | 33 | 93 | |
| Blue | 34 | 94 | |
| Magenta | 35 | 95 | |
| Cyan | 36 | 96 | |
| White | 37 | 97 | |

## Expected Output

```text
2024-01-15 10:30:45 | INFO | Custom format with pipe separators
2024-01-15 10:30:45 | WARNING | Notice the UTC timestamp
1705315845000 | INFO | Now using Unix timestamp
[2024-01-15 10:30:45] [DEBUG] [src/main.zig:42] This shows file:line...
[2024-01-15 10:30:45] [INFO] Colors enabled globally
[2024-01-15 10:30:45] [SUCCESS] Green success message
[2024-01-15 10:30:45] [ERROR] Red error message
[2024-01-15 10:30:45] [INFO] Colors now disabled
[2024-01-15 10:30:45] [AUDIT] User login event
[2024-01-15 10:30:45] [NOTICE] System maintenance scheduled
{
  "timestamp": "2024-01-15 10:30:45.000",
  "level": "INFO",
  "message": "JSON formatted output"
}
{
  "timestamp": "2024-01-15 10:30:45.000",
  "level": "AUDIT",
  "message": "JSON with custom level name"
}
```
