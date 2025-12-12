# Sinks

Sinks are destinations where log messages are written. Logly-Zig supports multiple sinks, allowing you to send logs to the console, files, or custom destinations simultaneously.

## Console Sink

A console sink is automatically added when you initialize the logger, unless `auto_sink` is disabled in the config.

```zig
// Add a console sink manually (both methods are equivalent)
_ = try logger.addSink(.{});
_ = try logger.add(.{});  // Short alias
```

## File Sink

File sinks write logs to a file. You can configure rotation, retention, and specific log levels for each sink.

```zig
_ = try logger.add(.{
    .path = "logs/app.log",
});
```

## Dynamic File Paths

You can use placeholders in the file path to automatically include date and time information. This is useful for organizing logs by date or creating unique log files per session.

Supported placeholders:
- `{date}`: Current date (YYYY-MM-DD)
- `{time}`: Current time (HH-mm-ss)
- Custom formats: `{YYYY}`, `{MM}`, `{DD}`, `{HH}`, `{mm}`, `{ss}`

```zig
// Create a log file in a date-stamped directory
_ = try logger.addSink(.{
    .path = "logs/{date}/app.log", // e.g., logs/2025-12-08/app.log
});

// Create a unique log file with full timestamp
_ = try logger.addSink(.{
    .path = "logs/session-{YYYY}-{MM}-{DD}_{HH}-{mm}-{ss}.log",
});

// Use custom separators
_ = try logger.addSink(.{
    .path = "logs/{YYYY}/{MM}/{DD}/app.log",
});
```

## Network Sinks

Logly supports sending logs over the network via TCP or UDP. This is useful for centralized logging, log aggregation services (like Logstash, Fluentd), or remote debugging.

### TCP Sink

TCP sinks provide reliable, connection-oriented logging. If the connection is lost, the sink will attempt to reconnect.

```zig
// TCP Sink with standard text format
_ = try logger.addSink(.{
    .path = "tcp://localhost:8080",
});

// TCP Sink with JSON format (recommended for aggregators)
_ = try logger.addSink(.{
    .path = "tcp://localhost:8080",
    .json = true,
});
```

### UDP Sink

UDP sinks provide "fire-and-forget" logging. They are faster and have less overhead but do not guarantee delivery.

```zig
// UDP Sink
_ = try logger.addSink(.{
    .path = "udp://localhost:9090",
    .json = true,
});
```

### Network Compression

You can enable compression for network sinks to reduce bandwidth usage. This uses the DEFLATE algorithm to compress log batches before sending.

```zig
var sink_config = logly.SinkConfig.network("tcp://localhost:8080");
sink_config.compression = .{
    .enabled = true,
    .algorithm = .deflate,
    .level = .best_compression,
};
_ = try logger.addSink(sink_config);
```

## System Event Log

You can enable logging to the system event log (Windows Event Log or Syslog).

```zig
_ = try logger.addSink(.{
    .event_log = true,
    .level = .err, // Typically used for critical errors
});
```

## Multiple Sinks

You can add as many sinks as you need.

```zig
// Console
_ = try logger.add(.{});

// Application logs
_ = try logger.add(.{
    .path = "logs/app.log",
    .rotation = "daily",
    .retention = 7,
});

// Error-only file
_ = try logger.add(.{
    .path = "logs/errors.log",
    .level = .err, // Only ERROR and above
});
```

## Sink Management

```zig
// Add sinks
const sink_id = try logger.add(.{ .path = "app.log" });

// Get sink count
const count = logger.count();  // or logger.getSinkCount()

// Remove specific sink
logger.remove(sink_id);  // or logger.removeSink(sink_id)

// Remove all sinks
_ = logger.clear();  // or logger.removeAll() or logger.removeAllSinks()
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
| ERROR | Red | 31 |
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
