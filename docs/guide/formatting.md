# Formatting

Logly-Zig provides flexible formatting options for your logs.

## Default Format

The default format includes the timestamp, level, module (optional), and message.

```
[2024-03-20 10:30:45] [INFO] [main] Application started
```

## Whole-Line Coloring

Logly colors the **entire log line** based on the log level, not just the level tag:

```
\x1b[37m[2024-03-20 10:30:45] [INFO] Application started\x1b[0m     <- All white
\x1b[33m[2024-03-20 10:30:45] [WARNING] Low disk space\x1b[0m       <- All yellow
\x1b[31m[2024-03-20 10:30:45] [ERROR] Connection failed\x1b[0m      <- All red
```

This makes it easier to scan logs visually.

## Level Colors

| Level | Color Code | Color |
|-------|------------|-------|
| TRACE | 36 | Cyan |
| DEBUG | 34 | Blue |
| INFO | 37 | White |
| SUCCESS | 32 | Green |
| WARNING | 33 | Yellow |
| ERROR | 31 | Red |
| FAIL | 35 | Magenta |
| CRITICAL | 91 | Bright Red |

## Custom Themes

You can override the default colors for each log level by creating a custom `Theme`.

```zig
const neon_theme = logly.Formatter.Theme{
    .trace = "90", // Bright Black
    .debug = "35", // Magenta
    .info = "36", // Cyan
    .success = "92", // Bright Green
    .warning = "93", // Bright Yellow
    .err = "91", // Bright Red
    .fail = "31;1", // Red Bold
    .critical = "41;37;1", // White on Red Background
};

// Apply to a specific sink (e.g., the console sink)
logger.sinks.items[0].formatter.setTheme(neon_theme);
```

## Enabling Colors on Windows

Windows requires enabling Virtual Terminal Processing:

```zig
const logly = @import("logly");

pub fn main() !void {
    // Enable ANSI colors on Windows (no-op on Linux/macOS)
    _ = logly.Terminal.enableAnsiColors();
    
    // ... rest of initialization
}
```

## Custom Format Strings

You can customize the log output format using the `log_format` option in `Config` or `SinkConfig`.

Supported tags:
- `{time}`: Timestamp
- `{level}`: Log level
- `{message}`: Log message
- `{module}`: Module name
- `{function}`: Function name
- `{file}`: Source filename
- `{line}`: Source line number
- `{thread}`: Thread ID

Example:
```zig
config.log_format = "[{time}] [{level}] [TID:{thread}] {message}";
```

## JSON Formatting

You can enable JSON formatting globally or per-sink.

```zig
var config = logly.Config.default();
config.json = true;
logger.configure(config);
```

Output:

```json
{
  "timestamp": 1710930645000,
  "level": "INFO",
  "module": "main",
  "message": "Application started"
}
```

Custom levels show their actual names in JSON:

```zig
try logger.addCustomLevel("audit", 35, "35");
try logger.custom("audit", "Security event", @src());
```

```json
{
  "timestamp": 1710930645000,
  "level": "AUDIT",
  "message": "Security event"
}
```

## Pretty JSON

For development, you might prefer pretty-printed JSON.

```zig
config.pretty_json = true;
```

## Customizing Output

You can control which fields are displayed using the configuration:

```zig
config.show_time = true;
config.show_module = true;
config.show_function = true;
config.show_filename = true;
config.show_lineno = true;
```

## Disabling Colors

To disable colors (for file output or compatibility):

```zig
config.color = false;
```

Or per-sink:

```zig
_ = try logger.add(.{  // Short alias for addSink()
    .path = "app.log",
    .color = false,  // No colors in file
});
```

## Custom Format Strings

You can define a custom format string to control the exact layout of your log messages.

```zig
config.log_format = "{time} | {level} | {message}";
```

Supported placeholders:

- `{time}`
- `{level}`
- `{message}`
- `{module}`
- `{function}`
- `{file}`
- `{line}`

## Time Formatting

Logly supports flexible timestamp formats with any separator. You can use predefined formats or create custom ones.

### Predefined Formats

```zig
// ISO 8601 format
config.time_format = "ISO8601";
// Output: 2025-12-04T06:39:53.091Z

// RFC 3339 format
config.time_format = "RFC3339";
// Output: 2025-12-04T06:39:53+00:00

// Unix timestamp (seconds)
config.time_format = "unix";
// Output: 1764830393

// Unix timestamp (milliseconds)
config.time_format = "unix_ms";
// Output: 1764830393091
```

### Custom Format Placeholders

Create any format using these placeholders:

| Placeholder | Description | Example |
|-------------|-------------|---------|
| `YYYY` | 4-digit year | 2025 |
| `YY` | 2-digit year | 25 |
| `MM` | 2-digit month (01-12) | 12 |
| `M` | 1-2 digit month (1-12) | 12 |
| `DD` | 2-digit day (01-31) | 04 |
| `D` | 1-2 digit day (1-31) | 4 |
| `HH` | 2-digit hour 24h (00-23) | 14 |
| `hh` | 2-digit hour 12h (01-12) | 02 |
| `mm` | 2-digit minute (00-59) | 30 |
| `ss` | 2-digit second (00-59) | 45 |
| `SSS` | 3-digit millisecond (000-999) | 091 |

Any other characters are output literally (-, /, ., :, space, T, etc.).

### Custom Format Examples

```zig
// Default format with milliseconds
config.time_format = "YYYY-MM-DD HH:mm:ss.SSS";
// Output: 2025-12-04 06:39:53.091

// US date format with slashes
config.time_format = "MM/DD/YYYY HH:mm:ss";
// Output: 12/04/2025 06:39:53

// European date format
config.time_format = "DD-MM-YYYY HH:mm:ss";
// Output: 04-12-2025 06:39:53

// Compact date with dots
config.time_format = "YY.MM.DD HH:mm";
// Output: 25.12.04 06:39

// Time only with milliseconds
config.time_format = "HH:mm:ss.SSS";
// Output: 06:39:53.091

// Date only
config.time_format = "YYYY-MM-DD";
// Output: 2025-12-04

// 12-hour format
config.time_format = "MM/DD/YYYY hh:mm:ss";
// Output: 12/04/2025 06:39:53

// Custom separator and order
config.time_format = "DD/MM/YY - HH:mm";
// Output: 04/12/25 - 06:39
```

### Timezone Configuration

```zig
config.timezone = .utc;    // Use UTC time
config.timezone = .local;  // Use local time (default)
```

## Formatted Logging

Logly-Zig supports `printf`-style formatting using the `f` suffix methods (e.g., `infof`, `debugf`). This allows you to construct log messages dynamically without manual string concatenation.

```zig
// Standard logging
try logger.infof("User {s} logged in from {s}", .{ "Alice", "192.168.1.1" }, @src());

// Debugging with numbers
try logger.debugf("Processed {d} items in {d}ms", .{ 100, 50 }, @src());

// Error details (use errorf or errf)
try logger.errorf("Failed to connect: {s} (Code: {d})", .{ "Connection Refused", 403 }, @src());
```

This feature uses Zig's standard `std.fmt` syntax, so all standard format specifiers are supported.
