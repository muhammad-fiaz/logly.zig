---
title: Advanced Customizations
description: Tailor Logly.zig to your needs with advanced customizations. Configure global root paths, format structures, per-level colors, and highlighters.
head:
  - - meta
    - name: keywords
      content: customizations, root path, format structure, level colors, highlighters, alerts, diagnostic path
  - - meta
    - property: og:title
      content: Advanced Customizations | Logly.zig
  - - meta
    - property: og:image
      content: https://muhammad-fiaz.github.io/logly.zig/cover.png
---

# Advanced Customizations Guide

This guide covers Logly's advanced customization features that allow you to tailor logging behavior to your specific needs.

## Global Logs Root Path

The **logs root path** feature allows you to specify a single root directory where all log files will be stored, making it easy to manage logs from multiple sinks.

### Configuration

```zig
var config = logly.Config.default();
config.logsRootPath = "./logs";  // All file sinks will be stored in ./logs

const logger = try logly.Logger.initWithConfig(allocator, config);

// Adding sinks with relative paths
 _ = try logger.addSink(logly.SinkConfig.file("application.log"));
 _ = try logger.addSink(logly.SinkConfig.file("errors.log"));
 _ = try logger.addSink(logly.SinkConfig.file("debug.log"));
```

### Behavior

- **Automatic Directory Creation**: If the root path doesn't exist, it will be automatically created
- **Path Resolution**: File sink paths are automatically prepended with the root path
- **Non-intrusive**: If directory creation fails, logging continues without interruption
- **Optional**: If `logsRootPath` is not set, file sinks use absolute or relative paths as specified

### Example Output

```
./logs/
├── application.log
├── errors.log
└── debug.log
```

## Format Structure Customization

Customize how log messages are formatted and structured using `FormatStructureConfig`.

### Configuration

```zig
var config = logly.Config.default();
config.formatStructure = .{
    .messagePrefix = ">>> ",        // Add prefix to each message
    .messageSuffix = " <<<",        // Add suffix to each message
    .fieldSeparator = " | ",        // Separator between fields
    .enableNesting = true,          // Enable hierarchical formatting
    .nestingIndent = "    ",        // Indentation for nested fields
    .includeEmptyFields = false,   // Skip null/empty fields
    .placeholderOpen = "{",         // Custom placeholder syntax
    .placeholderClose = "}",
};

const logger = try logly.Logger.initWithConfig(allocator, config);
```

### Available Options

| Option | Purpose | Example |
|--------|---------|---------|
| `messagePrefix` | Text prepended to messages | `">>> "` |
| `messageSuffix` | Text appended to messages | `" <<<"` |
| `fieldSeparator` | Separator between log fields | `" \| "` |
| `enableNesting` | Support nested/hierarchical logs | `true` |
| `nestingIndent` | Indentation for nested items | `"  "` (2 spaces) |
| `includeEmptyFields` | Include null fields in output | `false` |
| `placeholderOpen`/`close` | Custom placeholder syntax | `"[["`, `"]]"` |

## Per-Level Color Customization

Define custom ANSI colors for each log level independently.

### Configuration

```zig
var config = logly.Config.default();
config.levelColors = .{
    .traceColor = "\x1b[36m",      // Cyan
    .debugColor = "\x1b[35m",      // Magenta
    .infoColor = "\x1b[34m",       // Blue
    .successColor = "\x1b[32m",    // Green
    .warningColor = "\x1b[33m",    // Yellow
    .errorColor = "\x1b[31m",      // Red
    .failColor = "\x1b[31;1m",     // Bold Red
    .criticalColor = "\x1b[1;31m", // Bold Red
    .useRgb = false,               // Standard ANSI (not RGB)
    .supportBackground = false,    // Text colors only
    .resetCode = "\x1b[0m",        // Reset to default
};

const logger = try logly.Logger.initWithConfig(allocator, config);
```

### Common ANSI Color Codes

**Standard Colors (8-color mode):**
- `"\x1b[30m"` - Black
- `"\x1b[31m"` - Red
- `"\x1b[32m"` - Green
- `"\x1b[33m"` - Yellow
- `"\x1b[34m"` - Blue
- `"\x1b[35m"` - Magenta
- `"\x1b[36m"` - Cyan
- `"\x1b[37m"` - White

**Bright Colors (16-color mode):**
- `"\x1b[90m"` - Bright Black
- `"\x1b[91m"` - Bright Red
- `"\x1b[92m"` - Bright Green
- `"\x1b[93m"` - Bright Yellow
- `"\x1b[94m"` - Bright Blue
- `"\x1b[95m"` - Bright Magenta
- `"\x1b[96m"` - Bright Cyan
- `"\x1b[97m"` - Bright White

**Styles:**
- `"\x1b[1;31m"` - Bold Red
- `"\x1b[2;31m"` - Dim Red
- `"\x1b[4;31m"` - Underline Red
- `"\x1b[5;31m"` - Blinking Red
- `"\x1b[7;31m"` - Inverted Red

## Highlighters and Alerts

Configure pattern matching and alerting for specific log messages.

### Configuration

```zig
var config = logly.Config.default();
config.highlighters = .{
    .enabled = true,
    .alertOnMatch = true,
    .alertMinSeverity = .warning,
    .logMatches = true,
    .maxMatchesPerMessage = 10,
};

const logger = try logly.Logger.initWithConfig(allocator, config);
```

### Options

| Option | Purpose |
|--------|---------|
| `enabled` | Enable/disable highlighter system |
| `alertOnMatch` | Trigger alerts when patterns match |
| `alertMinSeverity` | Minimum severity to trigger alerts |
| `logMatches` | Log pattern matches as separate records |
| `patterns` | Array of `HighlightPattern` structures |
| `maxMatchesPerMessage` | Max patterns to match per message |

### Pattern Definition

```zig
pub const HighlightPattern = struct {
    name: []const u8,              // Pattern identifier
    pattern: []const u8,           // Text or regex to match
    isRegex: bool = false,        // Is this a regex pattern?
    highlightColor: []const u8,   // Color for highlights
    severity: AlertSeverity,       // Severity level
    metadata: ?[]const u8 = null,  // Custom metadata
};
```

### Alert Severity Levels

```zig
pub const AlertSeverity = enum {
    trace,
    debug,
    info,
    success,
    warning,
    err,
    fail,
    critical,
};
```

## Complete Example

Here's a comprehensive example combining all customization features:

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var config = logly.Config.default();

    // Global root path
    config.logsRootPath = "./logs";

    // Format structure
    config.formatStructure = .{
        .messagePrefix = "[APP] ",
        .fieldSeparator = " | ",
        .enableNesting = true,
    };

    // Custom colors
    config.levelColors = .{
        .infoColor = "\x1b[34m",     // Blue
        .warningColor = "\x1b[33m",  // Yellow
        .errorColor = "\x1b[31m",    // Red
    };

    // Highlighters
    config.highlighters = .{
        .enabled = true,
        .alertOnMatch = true,
        .logMatches = true,
    };

    const logger = try logly.Logger.initWithConfig(allocator, config);
    defer logger.deinit();

    // Add sinks (automatically use logs_root_path)
     _ = try logger.addSink(logly.SinkConfig.file("application.log"));
     _ = try logger.addSink(logly.SinkConfig.file("errors.log"));

    // Log messages
    try logger.info("Application started", @src());
    try logger.warning("Resource usage high", @src());
    try logger.err("Connection failed", @src());
}
```

## Combining with Other Features

All customization features work seamlessly with Logly's other capabilities:

- **Thread Pool**: Customizations apply to all threaded log writes
- **Async Logging**: Format customizations work with buffered output
- **Rotation**: Logs are rotated within the configured root path
- **Compression**: Compressed files are stored in the root path
- **Filtering**: Color and format customizations apply to filtered logs
- **JSON Output**: Customizations don't affect JSON structure

## Performance Considerations

- **Format Structure**: Minimal overhead; applies at formatting stage
- **Colors**: ANSI codes add small amounts to output size
- **Highlighters**: Pattern matching has O(n) complexity per message
- **Root Path**: Single directory creation at logger init, no runtime overhead
