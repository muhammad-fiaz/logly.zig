# Advanced Customizations Guide

This guide covers Logly's advanced customization features that allow you to tailor logging behavior to your specific needs.

## Global Logs Root Path

The **logs root path** feature allows you to specify a single root directory where all log files will be stored, making it easy to manage logs from multiple sinks.

### Configuration

```zig
var config = logly.Config.default();
config.logs_root_path = "./logs";  // All file sinks will be stored in ./logs

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
- **Optional**: If `logs_root_path` is not set, file sinks use absolute or relative paths as specified

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
config.format_structure = .{
    .message_prefix = ">>> ",        // Add prefix to each message
    .message_suffix = " <<<",        // Add suffix to each message
    .field_separator = " | ",        // Separator between fields
    .enable_nesting = true,          // Enable hierarchical formatting
    .nesting_indent = "    ",        // Indentation for nested fields
    .include_empty_fields = false,   // Skip null/empty fields
    .placeholder_open = "{",         // Custom placeholder syntax
    .placeholder_close = "}",
};

const logger = try logly.Logger.initWithConfig(allocator, config);
```

### Available Options

| Option | Purpose | Example |
|--------|---------|---------|
| `message_prefix` | Text prepended to messages | `">>> "` |
| `message_suffix` | Text appended to messages | `" <<<"` |
| `field_separator` | Separator between log fields | `" \| "` |
| `enable_nesting` | Support nested/hierarchical logs | `true` |
| `nesting_indent` | Indentation for nested items | `"  "` (2 spaces) |
| `include_empty_fields` | Include null fields in output | `false` |
| `placeholder_open`/`close` | Custom placeholder syntax | `"[["`, `"]]"` |

## Per-Level Color Customization

Define custom ANSI colors for each log level independently.

### Configuration

```zig
var config = logly.Config.default();
config.level_colors = .{
    .trace_color = "\x1b[36m",      // Cyan
    .debug_color = "\x1b[35m",      // Magenta
    .info_color = "\x1b[34m",       // Blue
    .success_color = "\x1b[32m",    // Green
    .warning_color = "\x1b[33m",    // Yellow
    .error_color = "\x1b[31m",      // Red
    .fail_color = "\x1b[31;1m",     // Bold Red
    .critical_color = "\x1b[1;31m", // Bold Red
    .use_rgb = false,               // Standard ANSI (not RGB)
    .support_background = false,    // Text colors only
    .reset_code = "\x1b[0m",        // Reset to default
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
    .alert_on_match = true,
    .alert_min_severity = .warning,
    .log_matches = true,
    .max_matches_per_message = 10,
};

const logger = try logly.Logger.initWithConfig(allocator, config);
```

### Options

| Option | Purpose |
|--------|---------|
| `enabled` | Enable/disable highlighter system |
| `alert_on_match` | Trigger alerts when patterns match |
| `alert_min_severity` | Minimum severity to trigger alerts |
| `log_matches` | Log pattern matches as separate records |
| `patterns` | Array of `HighlightPattern` structures |
| `max_matches_per_message` | Max patterns to match per message |

### Pattern Definition

```zig
pub const HighlightPattern = struct {
    name: []const u8,              // Pattern identifier
    pattern: []const u8,           // Text or regex to match
    is_regex: bool = false,        // Is this a regex pattern?
    highlight_color: []const u8,   // Color for highlights
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

## Diagnostics Custom Path

Store system diagnostics in a separate file from regular logs.

### Configuration

```zig
var config = logly.Config.default();
config.diagnostics_output_path = "./logs/diagnostics.log";
config.logs_root_path = "./logs";
config.emit_system_diagnostics_on_init = true;

const logger = try logly.Logger.initWithConfig(allocator, config);
```

### Behavior

- Diagnostics are emitted at logger initialization if configured
- Structured context fields (`diag.os`, `diag.cpu`, etc.) are available for custom formatting
- Use the standard `logSystemDiagnostics()` method to emit on demand

### Available Diagnostics Fields

When using custom log formats, these fields are available:

- `{diag.os}` - Operating system name (windows, linux, macos)
- `{diag.arch}` - Architecture (x86_64, aarch64, etc.)
- `{diag.cpu}` - CPU model name
- `{diag.cores}` - Number of logical cores
- `{diag.ram_total_mb}` - Total RAM in megabytes
- `{diag.ram_avail_mb}` - Available RAM in megabytes

### Example with Custom Format

```zig
var config = logly.Config.default();
config.log_format = "[{level}] {message} | CPU={diag.cpu} ({diag.cores} cores)";
config.emit_system_diagnostics_on_init = true;

const logger = try logly.Logger.initWithConfig(allocator, config);
try logger.logSystemDiagnostics(@src());

// Output:
// [INFO] [DIAGNOSTICS] os=windows arch=x86_64 cpu=rocketlake cores=16 ... | 
//   CPU=rocketlake (16 cores)
```

## Complete Example

Here's a comprehensive example combining all customization features:

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var config = logly.Config.default();

    // Global root path
    config.logs_root_path = "./logs";

    // Format structure
    config.format_structure = .{
        .message_prefix = "[APP] ",
        .field_separator = " | ",
        .enable_nesting = true,
    };

    // Custom colors
    config.level_colors = .{
        .info_color = "\x1b[34m",     // Blue
        .warning_color = "\x1b[33m",  // Yellow
        .error_color = "\x1b[31m",    // Red
    };

    // Highlighters
    config.highlighters = .{
        .enabled = true,
        .alert_on_match = true,
        .log_matches = true,
    };

    // Diagnostics
    config.emit_system_diagnostics_on_init = true;

    const logger = try logly.Logger.initWithConfig(allocator, config);
    defer logger.deinit();

    // Add sinks (automatically use logs_root_path)
    _ = try logger.addSink(logly.SinkConfig.file("application.log"));
    _ = try logger.addSink(logly.SinkConfig.file("errors.log"));

    // Log messages
    try logger.info("Application started", @src());
    try logger.warning("Resource usage high", @src());
    try logger.err("Connection failed", @src());

    // Emit diagnostics
    try logger.logSystemDiagnostics(@src());
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
