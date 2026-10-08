---
title: Source Location Display
description: Enhance logs with source file paths and line numbers in Logly.zig. Learn how to use @src() and custom format strings for effortless debugging.
head:
  - - meta
    - name: keywords
      content: source location, filename, line number, @src, debugging, log formatting, caller info, function name
  - - meta
    - property: og:title
      content: Source Location Display | Logly.zig
  - - meta
    - property: og:image
      content: https://muhammad-fiaz.github.io/logly.zig/cover.png
---

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
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();

    const config = logly.Config{
        .showFilename = true,  // Show source filename
        .showLineno = true,    // Show line number
    };

    const logger = try logly.Logger.initWithConfig(gpa.allocator(), config);
    defer logger.deinit();

    // @src() captures the source location at the call site
    try logger.info("This will show file:line info", @src());
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
// Each level colors the ENTIRE line (timestamp, level, message)
// @src() is optional - enables file:line display when show_filename/show_lineno are true
// Pass null instead of @src() to disable source location
try logger.info("Application started", @src());      // White line
try logger.success("Operation completed!", @src());  // Green line
try logger.warn("Low memory", @src());               // Yellow line (alias for warning)
try logger.err("Connection failed", @src());         // Red line
```

### Without `@src()` (Optional)

```zig
// Pass null if you don't need source location
try logger.info("Message without source location", null);
try logger.debug("Another message", null);
```

When `@src()` is `null`, the filename and line number fields will be empty, even if `showFilename` and `showLineno` are enabled.

## Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `showFilename` | `bool` | `false` | Display the source filename |
| `showLineno` | `bool` | `false` | Display the line number |
| `showFunction` | `bool` | `false` | Display the function name |

## Custom Format with `{file}` and `{line}`

Use the `logFormat` option to customize how source location appears:

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();

    const config = logly.Config{
        .showFilename = true,
        .showLineno = true,
        // Custom format with file and line placeholders
        .logFormat = "[{time}] {level} ({file}:{line}) - {message}",
    };

    const logger = try logly.Logger.initWithConfig(gpa.allocator(), config);
    defer logger.deinit();

    try logger.info("Custom formatted log", @src());
}
```

**Output:**
```
[2025-01-15 10:30:45.123] INFO (main.zig:18) - Custom formatted log
```

## Available Format Placeholders

Use these placeholders in `logFormat`:

| Placeholder | Description | Example |
|-------------|-------------|---------|
| `{time}` | Timestamp | `2025-01-15 10:30:45.123` |
| `{level}` | Log level | `INFO`, `ERROR`, `DEBUG` |
| `{message}` | Log message | `Application started` |
| `{file}` | Source filename | `main.zig` |
| `{line}` | Line number | `42` |
| `{function}` | Function name | `main` |
| `{module}` | Module name | `http.server` |
| `{traceId}` | Distributed trace ID | `abc123...` |
| `{spanId}` | Span ID | `def456...` |
| `{caller}` | Full caller info | `main.zig:42 in main` |
| `{thread}` | Thread ID | `12345` |

## Custom Format Examples

### Compact Format

```zig
const config = logly.Config{
    .showFilename = true,
    .showLineno = true,
    .logFormat = "{level} {file}:{line} {message}",
};
```

**Output:**
```
INFO main.zig:15 Application started
```

### Detailed Format with Function

```zig
const config = logly.Config{
    .showFilename = true,
    .showLineno = true,
    .showFunction = true,
    .logFormat = "[{time}] [{level}] {file}:{line} ({function}) {message}",
};
```

**Output:**
```
[2025-01-15 10:30:45.123] [INFO] main.zig:15 (main) Application started
```

### JSON-Style Format

```zig
const config = logly.Config{
    .showFilename = true,
    .showLineno = true,
    .logFormat = "{{\"time\":\"{time}\",\"level\":\"{level}\",\"file\":\"{file}\",\"line\":{line},\"msg\":\"{message}\"}}",
};
```

### Caller-Focused Format

```zig
const config = logly.Config{
    .showFilename = true,
    .showLineno = true,
    .logFormat = "{message} [{caller}]",
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
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();

    // Base config without source location
    const config = logly.Config{
        .showFilename = false,
        .showLineno = false,
        .autoSink = false, // We'll add sinks manually
    };

    const logger = try logly.Logger.initWithConfig(gpa.allocator(), config);
    defer logger.deinit();

    // Console sink: minimal output
     _ = try logger.add(logly.SinkConfig.default());

    // File sink: detailed output with source location
    var fileConfig = logly.SinkConfig.file("debug.log");
    fileConfig.format = "[{time}] {level} {file}:{line} {message}";
     _ = try logger.add(fileConfig);

    try logger.info("Different format per sink", @src());
}
```

## Complete Example

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();

    // Full source location configuration
    const config = logly.Config{
        .showFilename = true,
        .showLineno = true,
        .showFunction = true,
        .timeFormat = "HH:mm:ss.SSS",
        .logFormat = "[{time}] {level} {file}:{line} ({function}) | {message}",
    };

    const logger = try logly.Logger.initWithConfig(gpa.allocator(), config);
    defer logger.deinit();

    // All logs will show source location
    try logger.debug("Debug information", @src());
    try logger.info("Application starting", @src());
    try logger.warnf("Resource usage high: {d}%", .{85}, @src());
    try logger.err("Connection failed", @src());
    try logger.success("Operation completed", @src());

    // Without @src() - no location info
    try logger.info("Message without source location", null);
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
try logger.info("With source location", @src());
try logger.info("Without source location", null);

// Use @src() when debugging, null for minimal logs
const src_info = if (debugMode) @src() else null;
try logger.info("Conditional source location", src_info);
```

## See Also

- [Formatting Guide](/guide/formatting) - General formatting options
- [JSON Logging](/guide/json) - Structured logging with source info
- [Configuration Guide](/guide/configuration) - All config options
- [Custom Levels](/guide/custom-levels) - Define custom log levels
