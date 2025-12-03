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
|--------|------|---------|-------------|
| `path` | `?[]const u8` | `null` | Path to the log file (null for console) |
| `name` | `?[]const u8` | `null` | Sink identifier for metrics/debugging |
| `rotation` | `?[]const u8` | `null` | Rotation interval ("minutely", "hourly", "daily", "weekly", "monthly", "yearly") |
| `size_limit` | `?u64` | `null` | Max file size in bytes for rotation |
| `size_limit_str` | `?[]const u8` | `null` | Max file size as string (e.g. "10MB", "1GB") |
| `retention` | `?usize` | `null` | Number of rotated files to keep |
| `level` | `?Level` | `null` | Minimum log level for this sink (overrides global) |
| `max_level` | `?Level` | `null` | Maximum log level (creates level range filter) |
| `async_write` | `bool` | `true` | Enable async writing (buffered) |
| `buffer_size` | `usize` | `8192` | Buffer size for async writing |
| `json` | `bool` | `false` | Force JSON output for this sink |
| `pretty_json` | `bool` | `false` | Pretty print JSON output |
| `color` | `?bool` | `null` | Enable/disable colors (null = auto-detect) |
| `enabled` | `bool` | `true` | Enable/disable sink initially |
| `include_timestamp` | `bool` | `true` | Include timestamp in output |
| `include_level` | `bool` | `true` | Include log level in output |
| `include_source` | `bool` | `false` | Include source location |
| `include_trace_id` | `bool` | `false` | Include trace IDs (distributed tracing) |

## Color Control

### Per-Sink Color Control

Each sink can have its own color setting. Colors apply to the **entire log line** (timestamp, level, and message):

```zig
// Console with colors (entire line colored)
_ = try logger.addSink(.{
    .color = true,
});

// File without colors (recommended for files)
_ = try logger.addSink(.{
    .path = "logs/app.log",
    .color = false,
});
```

### Windows Color Support

On Windows, enable ANSI color support at application startup:

```zig
_ = logly.Terminal.enableAnsiColors(); // No-op on Linux/macOS
```

### Auto-Detection

When `color` is `null` (default):
- Console sinks: Colors enabled if terminal supports ANSI
- File sinks: Colors disabled

### Global Color Control

```zig
var config = logly.Config.default();
config.global_color_display = false; // Disable colors globally
logger.configure(config);
```

### Level Colors

| Level | Color | ANSI Code |
|-------|-------|-----------|
| TRACE | Cyan | 36 |
| DEBUG | Blue | 34 |
| INFO | White | 37 |
| SUCCESS | Green | 32 |
| WARNING | Yellow | 33 |
| ERR | Red | 31 |
| FAIL | Magenta | 35 |
| CRITICAL | Bright Red | 91 |

## Runtime Control

You can enable or disable specific sinks at runtime using their ID (returned by `addSink`).

```zig
const sink_id = try logger.addSink(.{ .path = "logs/app.log" });

// Disable sink temporarily
logger.disableSink(sink_id);

// Enable it back
logger.enableSink(sink_id);
```

## Level Range Filtering

Create sinks that only accept a specific range of levels:

```zig
// Only INFO and SUCCESS (no warnings/errors)
_ = try logger.addSink(.{
    .path = "logs/info.log",
    .level = .info,
    .max_level = .success,
});

// Only ERROR, FAIL, CRITICAL
_ = try logger.addSink(.{
    .path = "logs/errors.log",
    .level = .err,
});
```

## JSON Output

Configure JSON output per sink:

```zig
// Pretty JSON for development
_ = try logger.addSink(.{
    .path = "logs/dev.json",
    .json = true,
    .pretty_json = true,
});

// Compact JSON for production
_ = try logger.addSink(.{
    .path = "logs/prod.json",
    .json = true,
    .include_trace_id = true,
});
```

## High-Throughput Configuration

For high-volume logging:

```zig
_ = try logger.addSink(.{
    .path = "logs/high-volume.log",
    .async_write = true,
    .buffer_size = 65536, // 64KB buffer
    .rotation = "hourly",
    .size_limit_str = "500MB",
    .retention = 24,
});
```
