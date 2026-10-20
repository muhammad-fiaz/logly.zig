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

## Formatter

The `Formatter` is typically managed internally by sinks, but can be customized via callbacks and themes.

### Methods

#### `init(allocator: std.mem.Allocator) Formatter`

Initializes a new Formatter and pre-fetches system metadata (hostname, PID).

#### `initWithIo(allocator: std.mem.Allocator, io_handle: std.Io) Formatter`

Initializes a new Formatter with an explicit I/O handle and pre-fetches system metadata.

#### `format(record: *const Record, config: anytype) ![]u8`

Formats a log record into a string. The `config` can be `Config` or `SinkConfig`. Uses the internal allocator for string building.

#### `formatWithAllocator(record: *const Record, config: anytype, scratchAllocator: ?std.mem.Allocator) ![]u8`

Formats a log record using an optional scratch allocator. If provided, temporary allocations use this allocator. If null, falls back to the internal allocator.

**Example:**
```zig
const formatted = try formatter.formatWithAllocator(record, config, logger.scratchAllocator());
```

#### `formatJson(record: *const Record, config: anytype) ![]u8`

Formats a log record into a JSON string. Automatically includes cached hostname and PID if enabled in config. Uses the internal allocator.

#### `formatJsonWithAllocator(record: *const Record, config: anytype, scratchAllocator: ?std.mem.Allocator) ![]u8`

Formats a log record as JSON using an optional scratch allocator.

**Example:**
```zig
const json = try formatter.formatJsonWithAllocator(record, config, logger.scratchAllocator());
```

#### `formatLogfmt(record: *const Record, config: anytype) ![]u8`

Formats a log record in `logfmt` style (`key=value` pairs). Ideal for ingestion into Grafana Loki and Splunk.

#### `formatSyslog(record: *const Record, config: anytype) ![]u8`

Formats a log record as RFC5424 syslog with UTC RFC3339 timestamps. No ANSI colors are emitted.

#### `formatSyslog3164(record: *const Record, config: anytype) ![]u8`

Formats a log record as RFC3164 (BSD) syslog. No ANSI colors are emitted.

#### `formatMsgpackWithAllocator(record: *const Record, config: anytype, scratchAllocator: ?std.mem.Allocator) ![]u8`

Formats a log record into MessagePack (`msgpack`) binary format. It packs all standard attributes (timestamp, level, message, module, context, etc.) into a highly compact binary array, suitable for high-volume network and storage sinks.

#### `formatJsonToWriter(writer: anytype, record: *const Record, config: anytype) !void`

Writes a log record as JSON directly to a writer without intermediate allocation.

#### `formatTimestamp(timestampMs: i64, config: anytype) ![]u8`

Formats a standalone timestamp string using the same logic as record formatting.

- Honors `Config.timeFormat` and timezone behavior.
- Useful when callers need consistent timestamp serialization outside full record formatting.

#### `formatTimestampWithAllocator(timestampMs: i64, config: anytype, scratchAllocator: ?std.mem.Allocator) ![]u8`

Allocator-aware variant of `formatTimestamp(...)`.

- Uses `scratchAllocator` when provided.
- Falls back to formatter allocator when null.

### Timestamp Timezone Behavior

Timestamp formatting behavior depends on `Config.timezone`:

- `.utc`: `ISO8601` emits `Z`, and `RFC3339` emits `+00:00`.
- `.local`: uses process/system local timezone when available and emits `+/-HH:MM` for `ISO8601` and `RFC3339`.

For custom `timeFormat` patterns, timezone tokens are also available:
- `ZZZ` => `+HH:MM`
- `ZZ` => `+HHMM`

`timeFormat = "default"` resolves to the canonical default pattern (`YYYY-MM-DD HH:mm:ss.SSS`).

`unix` and `unixMs` formats remain numeric and timezone-agnostic, including JSON output.

Why `ZZZ` and `ZZ` are needed:
- Custom date/time layouts are often required by legacy parsers and SIEM pipelines.
- Including explicit offsets prevents ambiguous timestamps when logs are aggregated across timezones.

#### `setTheme(theme: Theme) void`

Sets a custom color theme for the formatter.

#### `getSnapshot(allocator: std.mem.Allocator) !Formatter.Snapshot`

Takes a mutex-protected snapshot of formatter statistics and configuration. The snapshot owns a copy of the hostname and must be released with `freeSnapshot()` or `snapshot.deinit()`.

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
| `throughputBytesPerSecond(elapsedSeconds)` | `f64` | Calculate throughput (bytes per second) |

> [!TIP]
> As of v0.1.8, `totalBytesFormatted` captures the exact length of each formatted message, replacing previous estimations.

#### Reset

| Method | Description |
|--------|-------------|
| `reset()` | Reset all statistics to initial state |

### System Metadata

The Formatter caches system metadata during initialization to improve performance:

- **Hostname**: Retrieved via `GetComputerNameW` (Windows) or `gethostname` (POSIX).
- **PID**: Retrieved via `GetCurrentProcessId` (Windows) or `getpid` (POSIX).

These values are automatically included in JSON output when `includeHostname` or `includePid` are enabled in the configuration.

### Callbacks

#### `setFormatCompleteCallback(callback: *const fn (u32, u64) void) void`

Sets the callback for format completion.
- Parameters: `format_type` (u32), `outputSize` (u64)

#### `setJsonFormatCallback(callback: *const fn (*const Record, u64) void) void`

Sets the callback for JSON formatting.
- Parameters: `record` (*const Record), `outputSize` (u64)

#### `setCustomFormatCallback(callback: *const fn ([]const u8, u64) void) void`

Sets the callback for custom formatting.
- Parameters: `format_string` ([]const u8), `outputSize` (u64)

#### `setErrorCallback(callback: *const fn ([]const u8) void) void`

Sets the callback for format errors.
- Parameters: `errorMsg` ([]const u8)

## Theme

The `Theme` struct defines custom ANSI color codes for each log level.

### Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `trace` | `Color.Color` | ANSI cyan | Color for TRACE level |
| `debug` | `Color.Color` | ANSI blue | Color for DEBUG level |
| `info` | `Color.Color` | ANSI white | Color for INFO level |
| `notice` | `Color.Color` | ANSI bright cyan | Color for NOTICE level |
| `success` | `Color.Color` | ANSI green | Color for SUCCESS level |
| `warning` | `Color.Color` | ANSI yellow | Color for WARNING level |
| `err` | `Color.Color` | ANSI red | Color for ERROR level |
| `fail` | `Color.Color` | ANSI magenta | Color for FAIL level |
| `critical` | `Color.Color` | ANSI bright red | Color for CRITICAL level |
| `fatal` | `Color.Color` | ANSI bright white | Color for FATAL level |

### Basic Usage

```zig
var theme = logly.Formatter.Theme{};
theme.info = logly.Color.parse("32").?; // Change INFO to Green
theme.err = logly.Color.parse("1;31").?; // Change ERROR to Bold Red

// Apply to a sink
logger.sinks.items[0].formatter.setTheme(theme);
```

### Theme Presets (v0.1.8)

```zig
const Theme = logly.Formatter.Theme;

// Built-in theme presets
const default_theme = Theme{};              // Standard colors
const bright = Theme.bright();              // Bold/bright colors
const dim = Theme.dim();                    // Dim colors
const minimal = Theme.minimal();            // Subtle grays
const neon = Theme.neon();                  // Vivid 256-colors
const pastel = Theme.pastel();              // Soft colors
const dark = Theme.dark();                  // Dark terminal optimized
const light = Theme.light();                // Light terminal optimized

// Apply preset to formatter
var formatter = logly.Formatter.init(allocator);
formatter.setTheme(Theme.neon());
```

### Custom RGB Theme (v0.1.8)

```zig
// Create a theme from RGB values
const custom = Theme.fromRgb(
    .{ .r = 0, .g = 255, .b = 255 },    // trace (cyan)
    .{ .r = 0, .g = 128, .b = 255 },    // debug (blue)
    .{ .r = 240, .g = 240, .b = 240 },  // info (white)
    .{ .r = 255, .g = 200, .b = 0 },    // warning (orange)
    .{ .r = 255, .g = 64, .b = 64 },    // error (red)
);
```

## ColorStyle (v0.1.8)

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
| `totalRecordsFormatted` | `atomic.Value(u64)` | Total records formatted |
| `jsonFormats` | `atomic.Value(u64)` | Number of JSON formats |
| `customFormats` | `atomic.Value(u64)` | Number of custom formats |
| `formatErrors` | `atomic.Value(u64)` | Number of format errors |
| `totalBytesFormatted` | `atomic.Value(u64)` | Total bytes formatted |

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
| `throughputBytesPerSecond(elapsedSeconds)` | `f64` | Calculate bytes per second throughput |

### Reset

| Method | Description |
|--------|-------------|
| `reset()` | Reset all statistics to initial state |

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
