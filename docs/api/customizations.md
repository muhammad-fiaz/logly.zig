# Customization API Reference

## Config.logs_root_path

Global root directory for all log files.

**Type:** `?[]const u8`  
**Default:** `null`

When set, all file-based sinks have their paths automatically resolved relative to this root directory. If the directory doesn't exist, it's automatically created.

```zig
config.logs_root_path = "./logs";
```

## Config.diagnostics_output_path

Optional custom path for system diagnostics output.

**Type:** `?[]const u8`  
**Default:** `null`

When set, system diagnostics can be routed to a specific file. The path respects `logs_root_path` if configured.

```zig
config.diagnostics_output_path = "./logs/diagnostics.log";
```

## Config.format_structure

Customization of log message structure and formatting.

**Type:** `Config.FormatStructureConfig`

### FormatStructureConfig

```zig
pub const FormatStructureConfig = struct {
    message_prefix: ?[]const u8 = null,
    message_suffix: ?[]const u8 = null,
    field_separator: []const u8 = " | ",
    enable_nesting: bool = false,
    nesting_indent: []const u8 = "  ",
    field_order: ?[]const []const u8 = null,
    include_empty_fields: bool = false,
    placeholder_open: []const u8 = "{",
    placeholder_close: []const u8 = "}",
};
```

### Fields

| Field | Type | Default | Purpose |
|-------|------|---------|---------|
| `message_prefix` | `?[]const u8` | `null` | Text prepended to every message |
| `message_suffix` | `?[]const u8` | `null` | Text appended to every message |
| `field_separator` | `[]const u8` | `" \| "` | Separator between log fields |
| `enable_nesting` | `bool` | `false` | Enable hierarchical log formatting |
| `nesting_indent` | `[]const u8` | `"  "` | Indentation for nested items |
| `field_order` | `?[]const []const u8` | `null` | Custom field ordering |
| `include_empty_fields` | `bool` | `false` | Include null/empty fields |
| `placeholder_open` | `[]const u8` | `"{"` | Format placeholder opening |
| `placeholder_close` | `[]const u8` | `"}"` | Format placeholder closing |

## Config.level_colors

Per-level ANSI color code customization.

**Type:** `Config.LevelColorConfig`

### LevelColorConfig

```zig
pub const LevelColorConfig = struct {
    trace_color: ?[]const u8 = null,
    debug_color: ?[]const u8 = null,
    info_color: ?[]const u8 = null,
    success_color: ?[]const u8 = null,
    warning_color: ?[]const u8 = null,
    error_color: ?[]const u8 = null,
    fail_color: ?[]const u8 = null,
    critical_color: ?[]const u8 = null,
    use_rgb: bool = false,
    support_background: bool = false,
    reset_code: []const u8 = "\x1b[0m",
};
```

### Fields

| Field | Type | Default | Purpose |
|-------|------|---------|---------|
| `trace_color` | `?[]const u8` | `null` | ANSI code for TRACE level |
| `debug_color` | `?[]const u8` | `null` | ANSI code for DEBUG level |
| `info_color` | `?[]const u8` | `null` | ANSI code for INFO level |
| `success_color` | `?[]const u8` | `null` | ANSI code for SUCCESS level |
| `warning_color` | `?[]const u8` | `null` | ANSI code for WARNING level |
| `error_color` | `?[]const u8` | `null` | ANSI code for ERROR level |
| `fail_color` | `?[]const u8` | `null` | ANSI code for FAIL level |
| `critical_color` | `?[]const u8` | `null` | ANSI code for CRITICAL level |
| `use_rgb` | `bool` | `false` | Enable RGB color mode |
| `support_background` | `bool` | `false` | Support background colors |
| `reset_code` | `[]const u8` | `"\x1b[0m"` | Reset code at end of colored output |

### Example

```zig
config.level_colors = .{
    .info_color = "\x1b[34m",      // Blue
    .warning_color = "\x1b[33m",   // Yellow
    .error_color = "\x1b[31m",     // Red
    .critical_color = "\x1b[1;31m", // Bold Red
};
```

## Config.highlighters

Pattern matching and alert configuration.

**Type:** `Config.HighlighterConfig`

### HighlighterConfig

```zig
pub const HighlighterConfig = struct {
    enabled: bool = false,
    patterns: ?[]const HighlightPattern = null,
    alert_on_match: bool = false,
    alert_min_severity: AlertSeverity = .warning,
    alert_callback: ?[]const u8 = null,
    max_matches_per_message: usize = 10,
    log_matches: bool = false,
};
```

### Fields

| Field | Type | Default | Purpose |
|-------|------|---------|---------|
| `enabled` | `bool` | `false` | Enable highlighter system |
| `patterns` | `?[]const HighlightPattern` | `null` | Array of patterns to match |
| `alert_on_match` | `bool` | `false` | Trigger alerts on pattern match |
| `alert_min_severity` | `AlertSeverity` | `.warning` | Minimum severity to alert |
| `alert_callback` | `?[]const u8` | `null` | Optional callback name |
| `max_matches_per_message` | `usize` | `10` | Max patterns to match per message |
| `log_matches` | `bool` | `false` | Log matches as separate records |

### HighlightPattern

```zig
pub const HighlightPattern = struct {
    name: []const u8,
    pattern: []const u8,
    is_regex: bool = false,
    highlight_color: []const u8 = "\x1b[1;93m",
    severity: AlertSeverity = .warning,
    metadata: ?[]const u8 = null,
};
```

### AlertSeverity

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

## Example Configuration

```zig
var config = logly.Config.default();

// Set global logs directory
config.logs_root_path = "./logs";

// Customize format
config.format_structure = .{
    .message_prefix = "[APP] ",
    .field_separator = " | ",
};

// Set custom colors
config.level_colors = .{
    .warning_color = "\x1b[33m",
    .error_color = "\x1b[31m",
};

// Configure highlighters
config.highlighters = .{
    .enabled = true,
    .alert_on_match = true,
    .log_matches = true,
};

const logger = try logly.Logger.initWithConfig(allocator, config);
```

## Builder Pattern

Logly also supports a fluent builder pattern for configuration:

```zig
var config = logly.Config.default()
    .withArenaAllocation()
    .withAsync()
    .withThreadPool(4);

config.logs_root_path = "./logs";

const logger = try logly.Logger.initWithConfig(allocator, config);
```
