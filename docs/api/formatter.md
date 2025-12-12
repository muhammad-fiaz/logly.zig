# Formatter API

The `Formatter` struct handles the conversion of log records into string output. It supports custom formats, JSON output, and color themes.

## Formatter

The `Formatter` is typically managed internally by sinks, but can be customized via callbacks and themes.

### Methods

#### `init(allocator: std.mem.Allocator) Formatter`

Initializes a new Formatter.

#### `format(record: *const Record, config: anytype) ![]u8`

Formats a log record into a string. The `config` can be `Config` or `SinkConfig`.

#### `setTheme(theme: Theme) void`

Sets a custom color theme for the formatter.

#### `getStats() FormatterStats`

Returns formatter statistics.

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
| `success` | `[]const u8` | `"32"` (Green) | Color for SUCCESS level |
| `warning` | `[]const u8` | `"33"` (Yellow) | Color for WARNING level |
| `err` | `[]const u8` | `"31"` (Red) | Color for ERROR level |
| `fail` | `[]const u8` | `"35"` (Magenta) | Color for FAIL level |
| `critical` | `[]const u8` | `"91"` (Bright Red) | Color for CRITICAL level |

### Usage

```zig
var theme = logly.Formatter.Theme{};
theme.info = "32"; // Change INFO to Green
theme.err = "1;31"; // Change ERROR to Bold Red

// Apply to a sink
logger.sinks.items[0].formatter.setTheme(theme);
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

### Methods

#### `avgFormatSize() f64`

Calculate average format size in bytes.

#### `errorRate() f64`

Calculate error rate (0.0 - 1.0).
