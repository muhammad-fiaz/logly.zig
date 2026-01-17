---
title: Formatter API Reference
description: API reference for Logly.zig Formatter struct. Custom log formats, JSON output, color themes, and template placeholders for timestamps, levels, and messages.
head:
  - - meta
    - name: keywords
      content: formatter api, log format, json formatter, color themes, custom format, template placeholders
  - - meta
    - property: og:title
      content: Formatter API Reference | Logly.zig
---

# Formatter API

The `Formatter` struct handles the conversion of log records into string output. It supports custom formats, JSON output, and color themes.

## Quick Reference: Method Aliases

| Full Method | Alias(es) | Description |
|-------------|-----------|-------------|
| `init()` | `create()` | Initialize formatter |
| `deinit()` | `destroy()` | Deinitialize formatter |

## Formatter

The `Formatter` is typically managed internally by sinks, but can be customized via callbacks and themes.

### Methods

#### `init(allocator: std.mem.Allocator) Formatter`

Initializes a new Formatter and pre-fetches system metadata (hostname, PID).

#### `format(record: *const Record, config: anytype) ![]u8`

Formats a log record into a string. The `config` can be `Config` or `SinkConfig`. Uses the internal allocator for string building.

#### `formatWithAllocator(record: *const Record, config: anytype, scratch_allocator: ?std.mem.Allocator) ![]u8`

Formats a log record using an optional scratch allocator. If provided, temporary allocations use this allocator. If null, falls back to the internal allocator.

**Example:**
```zig
const formatted = try formatter.formatWithAllocator(record, config, logger.scratchAllocator());
```

#### `formatJson(record: *const Record, config: anytype) ![]u8`

Formats a log record into a JSON string. Automatically includes cached hostname and PID if enabled in config. Uses the internal allocator.

#### `formatJsonWithAllocator(record: *const Record, config: anytype, scratch_allocator: ?std.mem.Allocator) ![]u8`

Formats a log record as JSON using an optional scratch allocator.

**Example:**
```zig
const json = try formatter.formatJsonWithAllocator(record, config, logger.scratchAllocator());
```

#### `formatJsonToWriter(writer: anytype, record: *const Record, config: anytype) !void`

Writes a log record as JSON directly to a writer without intermediate allocation.

#### `setTheme(theme: Theme) void`

Sets a custom color theme for the formatter.

#### `getStats() FormatterStats`

Returns formatter statistics.

### FormatterStats

Statistics for formatter performance.

#### Getter Methods

| Method | Return | Description |
|--------|--------|-------------|
| `getTotalFormatted()` | `u64` | Get total records formatted |
| `getJsonFormats()` | `u64` | Get total JSON formats |
| `getCustomFormats()` | `u64` | Get total custom formats |
| `getFormatErrors()` | `u64` | Get total format errors |
| `getTotalBytesFormatted()` | `u64` | Get total bytes formatted |
| `getPlainFormats()` | `u64` | Get plain text formats (total - json - custom) |

#### Boolean Checks

| Method | Return | Description |
|--------|--------|-------------|
| `hasFormatted()` | `bool` | Check if any records have been formatted |
| `hasJsonFormats()` | `bool` | Check if any JSON formats have been used |
| `hasCustomFormats()` | `bool` | Check if any custom formats have been used |
| `hasErrors()` | `bool` | Check if any format errors have occurred |

#### Rate Calculations

| Method | Return | Description |
|--------|--------|-------------|
| `jsonUsageRate()` | `f64` | Calculate JSON format usage rate (0.0 - 1.0) |
| `customUsageRate()` | `f64` | Calculate custom format usage rate (0.0 - 1.0) |
| `avgFormatSize()` | `f64` | Calculate average format size |
| `errorRate()` | `f64` | Calculate error rate (0.0 - 1.0) |
| `successRate()` | `f64` | Calculate success rate (0.0 - 1.0) |
| `throughputBytesPerSecond(elapsed_seconds)` | `f64` | Calculate throughput (bytes per second) |

::: tip Precise Byte Tracking
As of v0.1.5, `total_bytes_formatted` captures the exact length of each formatted message, replacing previous estimations.
:::

#### Reset

| Method | Description |
|--------|-------------|
| `reset()` | Reset all statistics to initial state |

### System Metadata

The Formatter caches system metadata during initialization to improve performance:

- **Hostname**: Retrieved via `GetComputerNameW` (Windows) or `gethostname` (POSIX).
- **PID**: Retrieved via `GetCurrentProcessId` (Windows) or `getpid` (POSIX).

These values are automatically included in JSON output when `include_hostname` or `include_pid` are enabled in the configuration.

### Callbacks

#### `setFormatCompleteCallback(callback: *const fn (u32, u64) void) void`

Sets the callback for format completion.
- Parameters: `format_type` (u32), `output_size` (u64)

#### `setJsonFormatCallback(callback: *const fn (*const Record, u64) void) void`

Sets the callback for JSON formatting.
- Parameters: `record` (*const Record), `output_size` (u64)

#### `setCustomFormatCallback(callback: *const fn ([]const u8, u64) void) void`

Sets the callback for custom formatting.
- Parameters: `format_string` ([]const u8), `output_size` (u64)

#### `setErrorCallback(callback: *const fn ([]const u8) void) void`

Sets the callback for format errors.
- Parameters: `error_msg` ([]const u8)

## Theme

The `Theme` struct defines custom ANSI color codes for each log level.

### Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `trace` | `[]const u8` | `"36"` (Cyan) | Color for TRACE level |
| `debug` | `[]const u8` | `"34"` (Blue) | Color for DEBUG level |
| `info` | `[]const u8` | `"37"` (White) | Color for INFO level |
| `notice` | `[]const u8` | `"96"` (Bright Cyan) | Color for NOTICE level (v0.1.5) |
| `success` | `[]const u8` | `"32"` (Green) | Color for SUCCESS level |
| `warning` | `[]const u8` | `"33"` (Yellow) | Color for WARNING level |
| `err` | `[]const u8` | `"31"` (Red) | Color for ERROR level |
| `fail` | `[]const u8` | `"35"` (Magenta) | Color for FAIL level |
| `critical` | `[]const u8` | `"91"` (Bright Red) | Color for CRITICAL level |
| `fatal` | `[]const u8` | `"91;1"` (Bright Red Bold) | Color for FATAL level (v0.1.5) |

### Basic Usage

```zig
var theme = logly.Formatter.Theme{};
theme.info = "32"; // Change INFO to Green
theme.err = "1;31"; // Change ERROR to Bold Red

// Apply to a sink
logger.sinks.items[0].formatter.setTheme(theme);
```

### Theme Presets (v0.1.5)

```zig
const Theme = logly.Formatter.Theme;

// Built-in theme presets
const default_theme = Theme{};              // Standard colors
const bright = Theme.bright();              // Bold/bright colors
const dim = Theme.dim();                    // Dim colors
const underlined = Theme.underlined();      // Underlined colors (v0.1.5)
const minimal = Theme.minimal();            // Subtle grays
const neon = Theme.neon();                  // Vivid 256-colors
const pastel = Theme.pastel();              // Soft colors
const dark = Theme.dark();                  // Dark terminal optimized
const light = Theme.light();                // Light terminal optimized

// Apply preset to formatter
var formatter = logly.Formatter.init(allocator);
formatter.setTheme(Theme.neon());
```

### Theme Preset Details

| Preset | Trace | Debug | Info | Success | Warning | Error | Critical |
|--------|-------|-------|------|---------|---------|-------|----------|
| `default` | 36 | 34 | 37 | 32 | 33 | 31 | 91 |
| `bright()` | 96;1 | 94;1 | 97;1 | 92;1 | 93;1 | 91;1 | 91;1;4 |
| `dim()` | 36;2 | 34;2 | 37;2 | 32;2 | 33;2 | 31;2 | 91;2 |
| `underlined()` | 36;4 | 34;4 | 37;4 | 32;4 | 33;4 | 31;4 | 91;4 |
| `minimal()` | 90 | 90 | 37 | 32 | 33 | 31 | 91 |
| `neon()` | 38;5;51 | 38;5;33 | 38;5;252 | 38;5;46 | 38;5;226 | 38;5;196 | 38;5;196;1 |
| `pastel()` | 38;5;152 | 38;5;111 | 38;5;253 | 38;5;157 | 38;5;228 | 38;5;210 | 38;5;203 |
| `dark()` | 38;5;37 | 38;5;33 | 38;5;245 | 38;5;34 | 38;5;214 | 38;5;160 | 38;5;196 |
| `light()` | 38;5;30 | 38;5;27 | 38;5;238 | 38;5;28 | 38;5;172 | 38;5;124 | 38;5;160 |

### Custom RGB Theme (v0.1.5)

```zig
// Create a theme from RGB values
const custom = Theme.fromRgb(
    .{ 0, 255, 255 },    // trace (cyan)
    .{ 0, 128, 255 },    // debug (blue)
    .{ 240, 240, 240 },  // info (white)
    .{ 0, 255, 128 },    // success (green)
    .{ 255, 200, 0 },    // warning (orange)
    .{ 255, 64, 64 },    // error (red)
    .{ 255, 0, 0 },      // critical (bright red)
);
```

## ColorStyle (v0.1.5)

The `ColorStyle` enum controls which color variant to use:

```zig
pub const ColorStyle = enum {
    default,     // Standard ANSI colors (30-37, 90-97)
    bright,      // Bold/bright variants
    dim,         // Dim variants
    color256,    // 256-color palette
    minimal,     // Minimal styling
    neon,        // Vivid neon colors
    pastel,      // Soft pastel colors
    dark,        // Optimized for dark terminals
    light,       // Optimized for light terminals
};
```

## FormatterStats

Statistics for the formatter.

| Field | Type | Description |
|-------|------|-------------|
| `total_records_formatted` | `atomic.Value(u64)` | Total records formatted |
| `json_formats` | `atomic.Value(u64)` | Number of JSON formats |
| `custom_formats` | `atomic.Value(u64)` | Number of custom formats |
| `format_errors` | `atomic.Value(u64)` | Number of format errors |
| `total_bytes_formatted` | `atomic.Value(u64)` | Total bytes formatted |

### Getter Methods

| Method | Return | Description |
|--------|--------|-------------|
| `getTotalFormatted()` | `u64` | Get total records formatted |
| `getJsonFormats()` | `u64` | Get total JSON formats |
| `getCustomFormats()` | `u64` | Get total custom formats |
| `getFormatErrors()` | `u64` | Get total format errors |
| `getTotalBytesFormatted()` | `u64` | Get total bytes formatted |
| `getPlainFormats()` | `u64` | Get plain text formats (total - json - custom) |

### Boolean Checks

| Method | Return | Description |
|--------|--------|-------------|
| `hasFormatted()` | `bool` | Check if any records have been formatted |
| `hasJsonFormats()` | `bool` | Check if any JSON formats have been used |
| `hasCustomFormats()` | `bool` | Check if any custom formats have been used |
| `hasErrors()` | `bool` | Check if any format errors have occurred |

### Rate Calculations

| Method | Return | Description |
|--------|--------|-------------|
| `jsonUsageRate()` | `f64` | Calculate JSON format usage rate (0.0 - 1.0) |
| `customUsageRate()` | `f64` | Calculate custom format usage rate (0.0 - 1.0) |
| `avgFormatSize()` | `f64` | Calculate average format size in bytes |
| `errorRate()` | `f64` | Calculate error rate (0.0 - 1.0) |
| `successRate()` | `f64` | Calculate success rate (0.0 - 1.0) |
| `throughputBytesPerSecond(elapsed_seconds)` | `f64` | Calculate bytes per second throughput |

### Reset

| Method | Description |
|--------|-------------|
| `reset()` | Reset all statistics to initial state |

## Aliases

The Formatter module provides convenience aliases:

| Alias | Method |
|-------|--------|
| `render` | `format` |
| `output` | `format` |
| `renderToWriter` | `formatToWriter` |
| `writeFormatted` | `formatToWriter` |
| `json` | `formatJson` |
| `toJson` | `formatJson` |
| `jsonToWriter` | `formatJsonToWriter` |
| `writeJson` | `formatJsonToWriter` |
| `statistics` | `getStats` |
| `colors` | `setTheme` |

## Additional Methods

- `hasTheme() bool` - Returns true if a custom theme is set
- `resetStats() void` - Resets all formatter statistics

## FormatterPresets

Pre-configured formatter options:

```zig
pub const FormatterPresets = struct {
    /// Plain formatter (no colors).
    pub fn plain() FormatterConfig {
        return .{ .color = false };
    }
    
    /// Dark theme formatter.
    pub fn dark() FormatterConfig {
        return .{
            .color = true,
            .theme = .dark,
        };
    }
    
    /// Light theme formatter.
    pub fn light() FormatterConfig {
        return .{
            .color = true,
            .theme = .light,
        };
    }
};
```

## See Also

- [Formatting Guide](../guide/formatting.md) - Custom format strings
- [Colors Guide](../guide/colors.md) - ANSI color configuration
- [Config API](config.md) - Configuration options

