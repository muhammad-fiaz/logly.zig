# Sink API

The `Sink` struct represents a destination for log messages. Sinks can write to console, files, or custom outputs with individual configuration options.

## SinkConfig

Configuration for a sink.

### Core Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `path` | `?[]const u8` | `null` | Path to log file (null for console) |
| `name` | `?[]const u8` | `null` | Sink identifier for metrics/debugging |
| `enabled` | `bool` | `true` | Enable/disable sink initially |

### Level Filtering

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `level` | `?Level` | `null` | Minimum log level for this sink |
| `max_level` | `?Level` | `null` | Maximum log level (creates level range) |

### Output Formatting

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `json` | `bool` | `false` | Force JSON output for this sink |
| `pretty_json` | `bool` | `false` | Pretty print JSON with indentation |
| `color` | `?bool` | `null` | Enable/disable colors (null = auto-detect) |
| `log_format` | `?[]const u8` | `null` | Custom log format string |
| `time_format` | `?[]const u8` | `null` | Custom time format for this sink |

### Field Inclusion

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `include_timestamp` | `bool` | `true` | Include timestamp in output |
| `include_level` | `bool` | `true` | Include log level in output |
| `include_source` | `bool` | `false` | Include source location |
| `include_trace_id` | `bool` | `false` | Include trace IDs (distributed tracing) |

### File Rotation

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `rotation` | `?[]const u8` | `null` | Rotation interval: "minutely", "hourly", "daily", "weekly", "monthly", "yearly" |
| `size_limit` | `?u64` | `null` | Max file size in bytes |
| `size_limit_str` | `?[]const u8` | `null` | Max file size as string (e.g., "10MB", "1GB") |
| `retention` | `?usize` | `null` | Number of rotated files to keep |

### Async Writing

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `async_write` | `bool` | `true` | Enable async writing with buffering |
| `buffer_size` | `usize` | `8192` | Buffer size for async writing in bytes |

### Advanced Options

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `compression` | `CompressionConfig` | `{}` | Compression settings for file sinks |
| `filter` | `FilterConfig` | `{}` | Per-sink filter configuration |

## Methods

### `init(allocator: std.mem.Allocator, config: SinkConfig) !*Sink`

Initializes a new sink with the specified configuration.

### `deinit() void`

Deinitializes the sink and frees resources.

### `write(record: *const Record, global_config: Config) !void`

Writes a log record to the sink.

### `flush() !void`

Flushes the sink buffer to ensure all data is written.

## Examples

### Console Sink (Default)

```zig
_ = try logger.addSink(SinkConfig.default());
```

### File Sink with Rotation

```zig
_ = try logger.addSink(.{
    .path = "logs/app.log",
    .rotation = "daily",
    .retention = 7,
    .size_limit_str = "100MB",
});
```

### JSON Sink for Structured Logging

```zig
_ = try logger.addSink(.{
    .path = "logs/app.json",
    .json = true,
    .pretty_json = true,
    .include_trace_id = true,
});
```

### Error-Only File Sink

```zig
_ = try logger.addSink(.{
    .path = "logs/errors.log",
    .level = .err,           // Minimum: error
    .max_level = .critical,  // Maximum: critical
    .color = false,
});
```

### Console with Color Control

```zig
// Disable colors for console output
_ = try logger.addSink(.{
    .color = false,  // Override auto-detection
});

// Or use global setting
var config = Config.default();
config.global_color_display = false;
logger.configure(config);
```

### High-Throughput Async Sink

```zig
_ = try logger.addSink(.{
    .path = "logs/high-volume.log",
    .async_write = true,
    .buffer_size = 65536, // 64KB buffer
});
```

### Multiple Sinks with Different Levels

```zig
// Console: info and above
_ = try logger.addSink(.{
    .level = .info,
});

// File: all levels
_ = try logger.addSink(.{
    .path = "logs/debug.log",
    .level = .trace,
});

// Errors file: errors only
_ = try logger.addSink(.{
    .path = "logs/errors.log",
    .level = .err,
});
```

## Color Auto-Detection

When `color` is `null` (default), the sink auto-detects:
- **Console sinks**: Colors enabled if terminal supports ANSI
- **File sinks**: Colors disabled

Override with explicit `true` or `false`:

```zig
// Force colors off for console
_ = try logger.addSink(.{ .color = false });

// Force colors on for file (e.g., for viewing with `less -R`)
_ = try logger.addSink(.{
    .path = "logs/colored.log",
    .color = true,
});
```

## Compression Configuration

```zig
_ = try logger.addSink(.{
    .path = "logs/app.log",
    .compression = .{
        .enabled = true,
        .algorithm = .gzip,
        .level = 6,
    },
});
```

## Per-Sink Filtering

```zig
_ = try logger.addSink(.{
    .path = "logs/filtered.log",
    .filter = .{
        .include_modules = &.{"database", "http"},
        .exclude_modules = &.{"health_check"},
        .include_messages = &.{"important"},
        .exclude_messages = &.{"debug"},
    },
});
```
