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

## Config.logsRootPath

Global root directory for all log files.

**Type:** `?[]const u8`  
**Default:** `null`

When set, all file-based sinks have their paths automatically resolved relative to this root directory. If the directory doesn't exist, it's automatically created.

```zig
config.logsRootPath = "./logs";
```

## Config.formatStructure

Customization of log message structure and formatting.

**Type:** `Config.FormatStructureConfig`

### FormatStructureConfig

```zig
pub const FormatStructureConfig = struct {
    messagePrefix: ?[]const u8 = null,
    messageSuffix: ?[]const u8 = null,
    fieldSeparator: []const u8 = " | ",
    enableNesting: bool = false,
    nestingIndent: []const u8 = "  ",
    fieldOrder: ?[]const []const u8 = null,
    includeEmptyFields: bool = false,
    placeholderOpen: []const u8 = "{",
    placeholderClose: []const u8 = "}",
};
```

### Fields

| Field | Type | Default | Purpose |
|-------|------|---------|---------|
| `messagePrefix` | `?[]const u8` | `null` | Text prepended to every message |
| `messageSuffix` | `?[]const u8` | `null` | Text appended to every message |
| `fieldSeparator` | `[]const u8` | `" \| "` | Separator between log fields |
| `enableNesting` | `bool` | `false` | Enable hierarchical log formatting |
| `nestingIndent` | `[]const u8` | `"  "` | Indentation for nested items |
| `fieldOrder` | `?[]const []const u8` | `null` | Custom field ordering |
| `includeEmptyFields` | `bool` | `false` | Include null/empty fields |
| `placeholderOpen` | `[]const u8` | `"{"` | Format placeholder opening |
| `placeholderClose` | `[]const u8` | `"}"` | Format placeholder closing |

## Config.levelColors

Per-level ANSI color code customization with theme presets and individual overrides.

**Type:** `Config.LevelColorConfig`

### LevelColorConfig (v0.1.8)

```zig
pub const LevelColorConfig = struct {
    /// Theme preset for base colors
    themePreset: ThemePreset = .default,
    
    /// Individual level color overrides (take precedence over theme)
    traceColor: ?[]const u8 = null,
    debugColor: ?[]const u8 = null,
    infoColor: ?[]const u8 = null,
    noticeColor: ?[]const u8 = null,
    successColor: ?[]const u8 = null,
    warningColor: ?[]const u8 = null,
    errorColor: ?[]const u8 = null,
    failColor: ?[]const u8 = null,
    criticalColor: ?[]const u8 = null,
    fatalColor: ?[]const u8 = null,
    
    useRgb: bool = false,
    supportBackground: bool = false,
    resetCode: []const u8 = "\x1b[0m",
    
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
| `themePreset` | `ThemePreset` | `.default` | Base theme for all levels |
| `traceColor` | `?[]const u8` | `null` | Override for TRACE level |
| `debugColor` | `?[]const u8` | `null` | Override for DEBUG level |
| `infoColor` | `?[]const u8` | `null` | Override for INFO level |
| `noticeColor` | `?[]const u8` | `null` | Override for NOTICE level |
| `successColor` | `?[]const u8` | `null` | Override for SUCCESS level |
| `warningColor` | `?[]const u8` | `null` | Override for WARNING level |
| `errorColor` | `?[]const u8` | `null` | Override for ERROR level |
| `failColor` | `?[]const u8` | `null` | Override for FAIL level |
| `criticalColor` | `?[]const u8` | `null` | Override for CRITICAL level |
| `fatalColor` | `?[]const u8` | `null` | Override for FATAL level |
| `useRgb` | `bool` | `false` | Enable RGB color mode |
| `supportBackground` | `bool` | `false` | Support background colors |
| `resetCode` | `[]const u8` | `"\x1b[0m"` | Reset code at end |

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
config.levelColors = .{
    .themePreset = .neon,
};
```

### Example: Theme with Overrides

```zig
// Use neon theme but override error color
config.levelColors = .{
    .themePreset = .neon,
    .errorColor = "91;1;4",  // Bright red bold underline
    .fatalColor = "97;41;1", // White on red bold
};
```

### Example: Individual Colors Only

```zig
// Set individual colors (theme_preset = .default)
config.levelColors = .{
    .infoColor = "34",       // Blue
    .warningColor = "33;1",  // Yellow bold
    .errorColor = "91",      // Bright red
    .criticalColor = "91;1;4", // Bright red bold underline
};
```

### Using getColorForLevel()

```zig
const color_config = config.levelColors;
const traceColor = color_config.getColorForLevel(.trace);
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
    alertOnMatch: bool = false,
    alertMinSeverity: AlertSeverity = .warning,
    alertCallback: ?[]const u8 = null,
    maxMatchesPerMessage: usize = 10,
    logMatches: bool = false,
};
```

### Fields

| Field | Type | Default | Purpose |
|-------|------|---------|---------|
| `enabled` | `bool` | `false` | Enable highlighter system |
| `patterns` | `?[]const HighlightPattern` | `null` | Array of patterns to match |
| `alertOnMatch` | `bool` | `false` | Trigger alerts on pattern match |
| `alertMinSeverity` | `AlertSeverity` | `.warning` | Minimum severity to alert |
| `alertCallback` | `?[]const u8` | `null` | Optional callback name |
| `maxMatchesPerMessage` | `usize` | `10` | Max patterns to match per message |
| `logMatches` | `bool` | `false` | Log matches as separate records |

### HighlightPattern

```zig
pub const HighlightPattern = struct {
    name: []const u8,
    pattern: []const u8,
    isRegex: bool = false,
    highlightColor: []const u8 = "\x1b[1;93m",
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
config.logsRootPath = "./logs";

// Customize format
config.formatStructure = .{
    .messagePrefix = "[APP] ",
    .fieldSeparator = " | ",
};

// Set custom colors
config.levelColors = .{
    .warningColor = "\x1b[33m",
    .errorColor = "\x1b[31m",
};

// Configure highlighters
config.highlighters = .{
    .enabled = true,
    .alertOnMatch = true,
    .logMatches = true,
};

const logger = try logly.Logger.initWithConfig(allocator, config);
```

## Builder Pattern

Logly also supports a fluent builder pattern for configuration:

```zig
var config = logly.Config.default()
    .withAsync()
    .withThreadPool(4);

config.logsRootPath = "./logs";

const logger = try logly.Logger.initWithConfig(allocator, config);
```

## See Also

- [Customizations Guide](../guide/customizations.md) - Usage patterns and examples
- [Configuration Guide](../guide/configuration.md) - Full configuration options
- [Colors Guide](../guide/colors.md) - Color customization
- [Formatting Guide](../guide/formatting.md) - Log format customization
- [Config API](config.md) - Full configuration reference

