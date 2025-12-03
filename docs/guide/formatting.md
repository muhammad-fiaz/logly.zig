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
\x1b[31m[2024-03-20 10:30:45] [ERR] Connection failed\x1b[0m        <- All red
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
| ERR | 31 | Red |
| FAIL | 35 | Magenta |
| CRITICAL | 91 | Bright Red |

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

## JSON Format

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
try logger.custom("audit", "Security event");
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
_ = try logger.addSink(.{
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

You can also customize the timestamp format and timezone:

```zig
config.time_format = "unix"; // or default
config.timezone = .utc;      // or .local
```

## Formatted Logging

Logly-Zig supports `printf`-style formatting using the `f` suffix methods (e.g., `infof`, `debugf`). This allows you to construct log messages dynamically without manual string concatenation.

```zig
// Standard logging
try logger.infof("User {s} logged in from {s}", .{ "Alice", "192.168.1.1" });

// Debugging with numbers
try logger.debugf("Processed {d} items in {d}ms", .{ 100, 50 });

// Error details
try logger.errf("Failed to connect: {s} (Code: {d})", .{ "Connection Refused", 403 });
```

This feature uses Zig's standard `std.fmt` syntax, so all standard format specifiers are supported.
