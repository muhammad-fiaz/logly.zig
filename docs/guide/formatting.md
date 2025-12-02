# Formatting

Logly-Zig provides flexible formatting options for your logs.

## Default Format

The default format includes the timestamp, level, module (optional), and message.

```
[2024-03-20 10:30:45] [INFO] [main] Application started
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

## Pretty JSON

For development, you might prefer pretty-printed JSON.

```zig
config.pretty_json = true;
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

## Customizing Output

You can control which fields are displayed using the configuration:

```zig
config.show_time = true;
config.show_module = true;
config.show_function = true;
config.show_filename = true;
config.show_lineno = true;
```

## Colors

Logly-Zig uses ANSI color codes by default. You can customize the colors for each level using callbacks (see [Callbacks](/guide/callbacks)).

To disable colors:

```zig
config.color = false;
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
config.timezone = .UTC;
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
