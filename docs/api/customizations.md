---
title: Customization API Reference
description: API reference for Logly.zig customization options. Configure logs root path, custom levels, color themes, format templates, and extend logger behavior.
head:
  - - meta
    - name: keywords
      content: customization api, custom levels, color themes, format templates, logger extension, configuration options
  - - meta
    - property: og:title
      content: Customization API Reference | Logly.zig
---

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

Per-level ANSI color code customization with theme presets and individual overrides.

**Type:** `Config.LevelColorConfig`

### LevelColorConfig (v0.1.5)

```zig
pub const LevelColorConfig = struct {
    /// Theme preset for base colors
    theme_preset: ThemePreset = .default,
    
    /// Individual level color overrides (take precedence over theme)
    trace_color: ?[]const u8 = null,
    debug_color: ?[]const u8 = null,
    info_color: ?[]const u8 = null,
    notice_color: ?[]const u8 = null,
    success_color: ?[]const u8 = null,
    warning_color: ?[]const u8 = null,
    error_color: ?[]const u8 = null,
    fail_color: ?[]const u8 = null,
    critical_color: ?[]const u8 = null,
    fatal_color: ?[]const u8 = null,
    
    use_rgb: bool = false,
    support_background: bool = false,
    reset_code: []const u8 = "\x1b[0m",
    
    pub const ThemePreset = enum {
        default,   // Standard ANSI colors
        bright,    // Bold/bright variants
        dim,       // Dim variants
        minimal,   // Gray-scale theme
        neon,      // Vivid 256-colors
        pastel,    // Soft colors
        dark,      // Dark terminal optimized
        light,     // Light terminal optimized
        none,      // No colors (plain text)
    };
    
    /// Get effective color for a level (override or theme)
    pub fn getColorForLevel(self: LevelColorConfig, level: Level) []const u8;
};
```

### Fields

| Field | Type | Default | Purpose |
|-------|------|---------|---------|
| `theme_preset` | `ThemePreset` | `.default` | Base theme for all levels |
| `trace_color` | `?[]const u8` | `null` | Override for TRACE level |
| `debug_color` | `?[]const u8` | `null` | Override for DEBUG level |
| `info_color` | `?[]const u8` | `null` | Override for INFO level |
| `notice_color` | `?[]const u8` | `null` | Override for NOTICE level |
| `success_color` | `?[]const u8` | `null` | Override for SUCCESS level |
| `warning_color` | `?[]const u8` | `null` | Override for WARNING level |
| `error_color` | `?[]const u8` | `null` | Override for ERROR level |
| `fail_color` | `?[]const u8` | `null` | Override for FAIL level |
| `critical_color` | `?[]const u8` | `null` | Override for CRITICAL level |
| `fatal_color` | `?[]const u8` | `null` | Override for FATAL level |
| `use_rgb` | `bool` | `false` | Enable RGB color mode |
| `support_background` | `bool` | `false` | Support background colors |
| `reset_code` | `[]const u8` | `"\x1b[0m"` | Reset code at end |

### Theme Presets

| Preset | Description | Example Colors |
|--------|-------------|----------------|
| `default` | Standard ANSI colors | trace=36, debug=34, err=31 |
| `bright` | Bold/bright variants | trace=96;1, debug=94;1, err=91;1 |
| `dim` | Dim variants | trace=36;2, debug=34;2, err=31;2 |
| `minimal` | Gray-scale theme | trace=90, debug=90, err=31 |
| `neon` | Vivid 256-colors | trace=38;5;51, debug=38;5;33 |
| `pastel` | Soft colors | trace=38;5;159, debug=38;5;117 |
| `dark` | Dark terminal optimized | 256-color palette |
| `light` | Light terminal optimized | 256-color palette |
| `none` | No colors (plain text) | All empty strings |

### Example: Theme-Based

```zig
// Use neon theme for all levels
config.level_colors = .{
    .theme_preset = .neon,
};
```

### Example: Theme with Overrides

```zig
// Use neon theme but override error color
config.level_colors = .{
    .theme_preset = .neon,
    .error_color = "91;1;4",  // Bright red bold underline
    .fatal_color = "97;41;1", // White on red bold
};
```

### Example: Individual Colors Only

```zig
// Set individual colors (theme_preset = .default)
config.level_colors = .{
    .info_color = "34",       // Blue
    .warning_color = "33;1",  // Yellow bold
    .error_color = "91",      // Bright red
    .critical_color = "91;1;4", // Bright red bold underline
};
```

### Using getColorForLevel()

```zig
const color_config = config.level_colors;
const trace_color = color_config.getColorForLevel(.trace);
const err_color = color_config.getColorForLevel(.err);
// Returns override if set, otherwise theme color
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

## See Also

- [Customizations Guide](../guide/customizations.md) - Usage patterns and examples
- [Configuration Guide](../guide/configuration.md) - Full configuration options
- [Colors Guide](../guide/colors.md) - Color customization
- [Formatting Guide](../guide/formatting.md) - Log format customization
- [Config API](config.md) - Full configuration reference

