# Source Location Display

Logly.zig supports displaying source file paths and line numbers in your log output. This feature is invaluable for debugging and tracing log messages back to their origin in your codebase.

## Overview

Source location display shows:
- **Filename**: The source file where the log was called (e.g., `main.zig`)
- **Line number**: The exact line number of the log call (e.g., `42`)

## Enabling Source Location Display

Configure source location display using these config options:

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const config = logly.Config{
        .show_filename = true,  // Show source filename
        .show_lineno = true,    // Show line number
    };

    const logger = try logly.Logger.initWithConfig(gpa.allocator(), config);
    defer logger.deinit();

    // @src() captures the source location at the call site
    try logger.info(@src(), "This will show file:line info", .{});
}
```

**Output:**
```
2025-01-15 10:30:45.123 [INFO] main.zig:15 This will show file:line info
```

## The `@src()` Parameter

The `@src()` builtin is a Zig compile-time function that captures source location information. It's **optional** in Logly.zig - you can pass `null` if you don't want source location tracking.

### With `@src()` (Recommended)

```zig
// @src() captures file, line, function info at compile time
try logger.info(@src(), "Message with source location", .{});
try logger.warn(@src(), "Warning at {s}:{d}", .{@src().file, @src().line});
try logger.err(@src(), "Error occurred", .{});
```

### Without `@src()` (Optional)

```zig
// Pass null if you don't need source location
try logger.info(null, "Message without source location", .{});
try logger.debug(null, "Another message", .{});
```

When `@src()` is `null`, the filename and line number fields will be empty, even if `show_filename` and `show_lineno` are enabled.

## Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `show_filename` | `bool` | `false` | Display the source filename |
| `show_lineno` | `bool` | `false` | Display the line number |
| `show_function` | `bool` | `false` | Display the function name |

## Custom Format with `{file}` and `{line}`

Use the `log_format` option to customize how source location appears:

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const config = logly.Config{
        .show_filename = true,
        .show_lineno = true,
        // Custom format with file and line placeholders
        .log_format = "[{time}] {level} ({file}:{line}) - {message}",
    };

    const logger = try logly.Logger.initWithConfig(gpa.allocator(), config);
    defer logger.deinit();

    try logger.info(@src(), "Custom formatted log", .{});
}
```

**Output:**
```
[2025-01-15 10:30:45.123] INFO (main.zig:18) - Custom formatted log
```

## Available Format Placeholders

Use these placeholders in `log_format`:

| Placeholder | Description | Example |
|-------------|-------------|---------|
| `{time}` | Timestamp | `2025-01-15 10:30:45.123` |
| `{level}` | Log level | `INFO`, `ERROR`, `DEBUG` |
| `{message}` | Log message | `Application started` |
| `{file}` | Source filename | `main.zig` |
| `{line}` | Line number | `42` |
| `{function}` | Function name | `main` |
| `{module}` | Module name | `http.server` |
| `{trace_id}` | Distributed trace ID | `abc123...` |
| `{span_id}` | Span ID | `def456...` |
| `{caller}` | Full caller info | `main.zig:42 in main` |
| `{thread}` | Thread ID | `12345` |

## Custom Format Examples

### Compact Format

```zig
const config = logly.Config{
    .show_filename = true,
    .show_lineno = true,
    .log_format = "{level} {file}:{line} {message}",
};
```

**Output:**
```
INFO main.zig:15 Application started
```

### Detailed Format with Function

```zig
const config = logly.Config{
    .show_filename = true,
    .show_lineno = true,
    .show_function = true,
    .log_format = "[{time}] [{level}] {file}:{line} ({function}) {message}",
};
```

**Output:**
```
[2025-01-15 10:30:45.123] [INFO] main.zig:15 (main) Application started
```

### JSON-Style Format

```zig
const config = logly.Config{
    .show_filename = true,
    .show_lineno = true,
    .log_format = "{{\"time\":\"{time}\",\"level\":\"{level}\",\"file\":\"{file}\",\"line\":{line},\"msg\":\"{message}\"}}",
};
```

### Caller-Focused Format

```zig
const config = logly.Config{
    .show_filename = true,
    .show_lineno = true,
    .log_format = "{message} [{caller}]",
};
```

**Output:**
```
Application started [main.zig:15 in main]
```

## Per-Sink Source Location

You can also configure source location display per-sink:

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    // Base config without source location
    const config = logly.Config{
        .show_filename = false,
        .show_lineno = false,
        .auto_sink = false, // We'll add sinks manually
    };

    const logger = try logly.Logger.initWithConfig(gpa.allocator(), config);
    defer logger.deinit();

    // Console sink: minimal output
    _ = try logger.add(logly.SinkConfig.default());

    // File sink: detailed output with source location
    var file_config = logly.SinkConfig.file("debug.log");
    file_config.format = "[{time}] {level} {file}:{line} {message}";
    _ = try logger.add(file_config);

    try logger.info(@src(), "Different format per sink", .{});
}
```

## Complete Example

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    // Full source location configuration
    const config = logly.Config{
        .show_filename = true,
        .show_lineno = true,
        .show_function = true,
        .time_format = "HH:mm:ss.SSS",
        .log_format = "[{time}] {level} {file}:{line} ({function}) | {message}",
    };

    const logger = try logly.Logger.initWithConfig(gpa.allocator(), config);
    defer logger.deinit();

    // All logs will show source location
    try logger.debug(@src(), "Debug information", .{});
    try logger.info(@src(), "Application starting", .{});
    try logger.warn(@src(), "Resource usage high: {d}%", .{85});
    try logger.err(@src(), "Connection failed", .{});
    try logger.success(@src(), "Operation completed", .{});

    // Without @src() - no location info
    try logger.info(null, "Message without source location", .{});
}
```

**Output:**
```
[10:30:45.123] DEBUG main.zig:23 (main) | Debug information
[10:30:45.124] INFO main.zig:24 (main) | Application starting
[10:30:45.124] WARN main.zig:25 (main) | Resource usage high: 85%
[10:30:45.125] ERROR main.zig:26 (main) | Connection failed
[10:30:45.125] SUCCESS main.zig:27 (main) | Operation completed
[10:30:45.126] INFO | Message without source location
```

## Best Practices

1. **Always use `@src()` in development**: Makes debugging much easier
2. **Consider disabling in production**: Slightly reduces binary size
3. **Use custom formats for readability**: Tailor output to your workflow
4. **Combine with JSON logging**: Full source info in structured logs

## @src() Is Optional

Remember that `@src()` is completely optional:

```zig
// All of these are valid:
try logger.info(@src(), "With source location", .{});
try logger.info(null, "Without source location", .{});

// Use @src() when debugging, null for minimal logs
const src_info = if (debug_mode) @src() else null;
try logger.info(src_info, "Conditional source location", .{});
```

## See Also

- [Formatting Guide](/guide/formatting) - General formatting options
- [JSON Logging](/guide/json) - Structured logging with source info
- [Configuration Guide](/guide/configuration) - All config options
- [Custom Levels](/guide/custom-levels) - Define custom log levels
