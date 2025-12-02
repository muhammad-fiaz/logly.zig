# Sinks

Sinks are destinations where log messages are written. Logly-Zig supports multiple sinks, allowing you to send logs to the console, files, or custom destinations simultaneously.

## Console Sink

A console sink is automatically added when you initialize the logger, unless `auto_sink` is disabled in the config.

```zig
// Add a console sink manually
_ = try logger.addSink(.{});
```

## File Sink

File sinks write logs to a file. You can configure rotation, retention, and specific log levels for each sink.

```zig
_ = try logger.addSink(.{
    .path = "logs/app.log",
});
```

## Multiple Sinks

You can add as many sinks as you need.

```zig
// Console
_ = try logger.addSink(.{});

// Application logs
_ = try logger.addSink(.{
    .path = "logs/app.log",
    .rotation = "daily",
    .retention = 7,
});

// Error-only file
_ = try logger.addSink(.{
    .path = "logs/errors.log",
    .level = .err, // Only ERROR and above
});
```

## Sink Configuration

| Option | Type | Default | Description |
| ~ | ~ | ~ | ~ |
| `path` | `?[]const u8` | `null` | Path to the log file (null for console) |
| `rotation` | `?[]const u8` | `null` | Rotation interval ("hourly", "daily", etc.) |
| `size_limit` | `?u64` | `null` | Max file size in bytes for rotation |
| `size_limit_str` | `?[]const u8` | `null` | Max file size as string (e.g. "10MB") |
| `retention` | `?usize` | `null` | Number of rotated files to keep |
| `level` | `?Level` | `null` | Minimum log level for this sink (overrides global) |
| `async_write` | `bool` | `true` | Enable async writing (buffered) |
| `buffer_size` | `usize` | `8192` | Buffer size for async writing |
| `json` | `bool` | `false` | Force JSON output for this sink |
| `pretty_json` | `bool` | `false` | Pretty print JSON output |
| `color` | `?bool` | `null` | Enable/disable colors (defaults to false for files) |
| `enabled` | `bool` | `true` | Enable/disable sink initially |

## Runtime Control

You can enable or disable specific sinks at runtime using their ID (returned by `addSink`).

```zig
const sink_id = try logger.addSink(.{ ... });

// Disable sink temporarily
logger.disableSink(sink_id);

// Enable it back
logger.enableSink(sink_id);
```
