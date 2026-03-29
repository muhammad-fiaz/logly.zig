---
title: Sink API Reference
description: API reference for Logly.zig Sink struct. Configure log destinations including console, file, network (TCP/UDP), rotation, compression, and custom outputs.
head:
  - - meta
    - name: keywords
      content: sink api, log destination, file sink, console sink, network sink, output configuration
  - - meta
    - property: og:title
      content: Sink API Reference | Logly.zig
---

# Sink API

The `Sink` struct represents a destination for log messages. Sinks can write to console, files, or custom outputs with individual configuration options.

## Quick Reference: Method Aliases

| Full Method | Alias(es) | Description |
|-------------|-----------|-------------|
| `init()` | `create()` | Initialize sink |
| `deinit()` | `destroy()`, `close()` | Deinitialize sink |
| `writeWithAllocator()` | `writeWithAlloc()` | Write with custom allocator |
| `setWriteCallback()` | `onWrite()` | Set write callback |
| `setFlushCallback()` | `onFlush()` | Set flush callback |
| `setErrorCallback()` | `onError()` | Set error callback |
| `setRotationCallback()` | `onRotation()` | Set rotation callback |
| `setStateChangeCallback()` | `onStateChange()` | Set state change callback |
| `getStats()` | `statistics()`, `stats_()` | Get sink statistics |
| `clearBuffer()` | `clear()` | Clear write buffer |
| `flush()` | `sync()` | Flush buffered data |
| `isEnabled()` | `is_enabled()` | Check if sink is enabled |
| `isAsyncEnabled()` | `asyncEnabled()` | Check if async writing is enabled |
| `flushNow()` | `flushImmediate()` | Force immediate flush |
| `getName()` | `name()` | Get sink name |

## SinkConfig

Configuration for a sink.

### Core Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `path` | `?[]const u8` | `null` | Path to log file (null for console). Supports dynamic placeholders like `{date}`, `{time}`. Also supports network schemes `tcp://host:port` and `udp://host:port`. |
| `name` | `?[]const u8` | `null` | Sink identifier for metrics and debugging |
| `enabled` | `bool` | `true` | Enable/disable sink initially |
| `event_log` | `bool` | `false` | Enable system event log output (Windows Event Log on Windows, Syslog on POSIX). See the Windows Event Log mapping below; constants are provided by `Constants.EventLogConstants`. |

### Windows Event Log (Windows only)

When `event_log` is enabled on Windows, log entries are sent to the Windows Event Viewer using the `ReportEventA` API. Logly maps internal log `Level` values to Windows event types as follows:

- Error / Critical / Fail / Fatal -> `EVENTLOG_ERROR_TYPE` (`Constants.EventLogConstants.error_type`)
- Warning -> `EVENTLOG_WARNING_TYPE` (`Constants.EventLogConstants.warning_type`)
- Notice / Info / Success -> `EVENTLOG_INFORMATION_TYPE` (`Constants.EventLogConstants.information_type`)

`EVENTLOG_SUCCESS` (`Constants.EventLogConstants.success`) may be used for success/audit events.

These values are centralized in `src/constants.zig` under `EventLogConstants` and are reused by the sink implementation to ensure consistency across platforms.

### Dynamic Path Formatting

The `path` field supports dynamic placeholders that are resolved when the sink is initialized:
- `{date}`: YYYY-MM-DD
- `{time}`: HH-mm-ss
- `{YYYY}`, `{MM}`, `{DD}`, `{HH}`, `{mm}`, `{ss}`: Custom date/time components.

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
| `theme` | `?Formatter.Theme` | `null` | Custom color theme for this sink |

### Field Inclusion

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `include_timestamp` | `bool` | `true` | Include timestamp in output |
| `include_level` | `bool` | `true` | Include log level in output |
| `include_source` | `bool` | `false` | Include source location |
| `include_trace_id` | `bool` | `false` | Include trace IDs (distributed tracing) |

### File Write Mode

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `overwrite_mode` | `bool` | `false` | **Append mode (default)**: logs appended to existing files. **Overwrite mode**: logs overwrite files on each write (truncate at initialization). |
| `file_mode` | `?u32` | `null` | File permissions for created log files (Unix only). |

### File Rotation

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `rotation` | `?[]const u8` | `null` | Rotation interval: "minutely", "hourly", "daily", "weekly", "monthly", "yearly" |
| `size_limit` | `?u64` | `null` | Max file size in bytes |
| `size_limit_str` | `?[]const u8` | `null` | Max file size as string (e.g., "10MB", "1GB") |
| `retention` | `?usize` | `null` | Number of rotated files to keep |

### Async Writing & Buffering

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `async_write` | `bool` | `true` | Enable async writing with buffering |
| `buffer_size` | `usize` | `8192` | Buffer size for async writing in bytes |
| `max_buffer_records` | `usize` | `1000` | Maximum records to buffer before forcing a flush |
| `flush_interval_ms` | `u64` | `1000` | Flush interval in milliseconds |

### Error Handling

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `on_error` | `ErrorBehavior` | `.log_stderr` | Error handling behavior: `.silent`, `.log_stderr`, `.disable_sink`, `.propagate` |

#### ErrorBehavior semantics

- Applied across direct writes and buffered flush paths (`writeRaw`, `flush`, `flushNow`).
- `.silent`: increments write error stats and suppresses output.
- `.log_stderr`: increments write error stats and emits a compact sink error line to stderr.
- `.disable_sink`: disables the sink after an error and triggers `onStateChange(false)` callback when configured.
- `.propagate`: returns the original write/flush error to the caller.

For TCP sinks, reconnect attempts use centralized retry defaults:

- `Constants.TimeDefaults.max_retries`
- `Constants.TimeDefaults.retry_delay_ms`

### Advanced Options

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `compression` | `CompressionConfig` | `{}` | Compression settings for file and network sinks |
| `filter` | `FilterConfig` | `{}` | Per-sink filter configuration |

## Write Mode Examples

### Append Mode (Default)

Keep a permanent log file that grows over time:

```zig
_ = try logger.addSink(.{
    .path = "logs/app.log",
    .overwrite_mode = false,  // Default: append to existing file
});
```

Every time you run the application, new logs are appended to the file.

### Overwrite Mode

Start fresh each run with only current session logs:

```zig
_ = try logger.addSink(.{
    .path = "logs/session.log",
    .overwrite_mode = true,  // Overwrite file on initialization
});
```

When the sink is initialized, it truncates the file, creating a fresh log for the current session.

### Mixed Approach

Use different modes for different sinks:

```zig
// Persistent history - append mode
_ = try logger.addSink(.{
    .path = "logs/history.log",
    .overwrite_mode = false,  // Keep all logs forever
});

// Current session - overwrite mode
_ = try logger.addSink(.{
    .path = "logs/session.log",
    .overwrite_mode = true,   // Fresh start each time
});

// Error tracking - append mode for permanent record
_ = try logger.addSink(.{
    .path = "logs/errors.log",
    .level = .err,
    .overwrite_mode = false,  // Keep error history
});
```

## Methods

### `init(allocator: std.mem.Allocator, config: SinkConfig) !*Sink`

Initializes a new sink with the specified configuration.

**Alias:** `create`

### `deinit() void`

Deinitializes the sink and frees resources.

**Alias:** `destroy`

### `write(record: *const Record, global_config: Config) !void`

Writes a log record to the sink. Uses the internal allocator for formatting.

### `writeWithAllocator(record: *const Record, global_config: Config, scratch_allocator: ?std.mem.Allocator) !void`

Writes a log record using an optional scratch allocator for formatting.

**Example:**
```zig
try sink.writeWithAllocator(record, config, logger.scratchAllocator());
```

### `writeRaw(data: []const u8) !void`

Writes preformatted data directly to the sink, bypassing record formatting.

- Appends a newline for file/console/network raw writes.
- Updates `SinkStats` and `on_write` callback on success.
- Applies `on_error` behavior consistently on failures.

### `flush() !void`

Flushes buffered sink data to its destination.

- Returns immediately when buffer is empty.
- Uses internal buffered record accounting so stats reflect batch flushes accurately.
- On success updates `SinkStats` (`total_written`, `bytes_written`, `flush_count`).
- Invokes `on_write(record_count, bytes)` and `on_flush(bytes, duration_ns)` callbacks.
- On failure increments `write_errors` and applies configured `on_error` behavior.

### `isAsyncEnabled() bool`

Returns `true` if async writing is enabled for this sink, `false` otherwise.

### `enableAsync() void`

Enables async writing for this sink, allowing buffered writes with periodic flushing.

### `disableAsync() void`

Disables async writing for this sink, forcing immediate synchronous writes and flushing any pending buffer.

### `flushNow() !void`

Manually flushes the sink buffer immediately, regardless of async settings.

Use this in batch checkpoints when async buffering is enabled but immediate durability is required.

## Examples

### Console Sink (Default)

```zig
// Using add() alias (same as addSink())
_ = try logger.add(SinkConfig.default());
```

### File Sink with Rotation

```zig
_ = try logger.add(.{
    .path = "logs/app.log",
    .rotation = "daily",
    .retention = 7,
    .size_limit_str = "100MB",
});
```

### JSON Sink for Structured Logging

```zig
_ = try logger.add(.{
    .path = "logs/app.json",
    .json = true,
    .pretty_json = true,
    .include_trace_id = true,
});
```

### Error-Only File Sink

```zig
_ = try logger.add(.{
    .path = "logs/errors.log",
    .level = .err,           // Minimum: error
    .max_level = .critical,  // Maximum: critical
    .color = false,
});
```

### Console with Color Control

```zig
// Disable colors for console output
_ = try logger.add(.{
    .color = false,  // Override auto-detection
});

// Or use global setting
var config = Config.default();
config.global_color_display = false;
logger.configure(config);
```

### High-Throughput Async Sink

```zig
_ = try logger.add(.{
    .path = "logs/high-volume.log",
    .async_write = true,
    .buffer_size = 65536, // 64KB buffer
});
```

### Manual Flush Control

```zig
var sink = try logly.Sink.init(allocator, .{
    .path = "logs/batch.log",
    .async_write = true,
    .on_error = .propagate,
});
defer sink.deinit();

try sink.writeRaw("batch line 1");
try sink.writeRaw("batch line 2");

// Explicit durability checkpoint
try sink.flushNow();

const stats = sink.getStats();
std.debug.print("flushed records: {}\n", .{stats.getTotalWritten()});
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

## SinkStats

Statistics for monitoring sink performance.

### Getter Methods

| Method | Return | Description |
|--------|--------|-------------|
| `getTotalWritten()` | `u64` | Get total number of records written |
| `getBytesWritten()` | `u64` | Get total bytes written |
| `getWriteErrors()` | `u64` | Get number of write errors |
| `getFlushCount()` | `u64` | Get number of flush operations |
| `getRotationCount()` | `u64` | Get number of file rotations |

### Boolean Checks

| Method | Return | Description |
|--------|--------|-------------|
| `hasWritten()` | `bool` | Check if any records have been written |
| `hasErrors()` | `bool` | Check if any errors have occurred |
| `hasFlushed()` | `bool` | Check if any flushes have occurred |
| `hasRotated()` | `bool` | Check if any rotations have occurred |

### Rate Calculations

| Method | Return | Description |
|--------|--------|-------------|
| `throughputBytesPerSecond(elapsed_seconds)` | `f64` | Calculate bytes per second throughput |
| `throughputRecordsPerSecond(elapsed_seconds)` | `f64` | Calculate records per second throughput |
| `errorRate()` | `f64` | Calculate error rate (0.0 - 1.0) |
| `successRate()` | `f64` | Calculate success rate (0.0 - 1.0) |
| `avgBytesPerWrite()` | `f64` | Calculate average bytes per write |
| `avgFlushesPerRotation()` | `f64` | Calculate average flushes per rotation |

### Reset

| Method | Description |
|--------|-------------|
| `reset()` | Reset all statistics to initial state |

### Example

```zig
const stats = sink.getStats();
std.debug.print("Written: {} records, {} bytes\n", .{
    stats.getTotalWritten(),
    stats.getBytesWritten(),
});
std.debug.print("Error rate: {d:.2}%\n", .{stats.errorRate() * 100});
std.debug.print("Avg bytes/write: {d:.1}\n", .{stats.avgBytesPerWrite()});
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

## Aliases

The Sink module provides convenience aliases:

| Alias | Method | Description |
|-------|--------|-------------|
| `statistics` | `getStats()` | Get sink statistics |
| `stats_` | `getStats()` | Get sink statistics |
| `clear` | `clearBuffer()` | Clear internal buffer |
| `sync` | `flush()` | Synchronize buffer to storage |
| `close` | `deinit()` | Close and cleanup sink |
| `name` | `getName()` | Get sink name |

## New Methods (v0.0.9)

```zig
// State management
const enabled = sink.isEnabled();
sink.enable();
sink.disable();

// Buffer management
sink.clearBuffer();

// Name access
const name = sink.getName();

// Statistics
const stats = sink.getStats();  // or sink.statistics()
```

## Configuration Helpers

Helper methods on `SinkConfig` for common use cases:

```zig
// Usage: logger.addSink(SinkConfig.console());

pub const SinkConfig = struct {
    /// Returns the default sink configuration (Console, async).
    pub fn default() SinkConfig;

    /// Returns a console sink configuration.
    pub fn console() SinkConfig;
    
    /// Returns a file sink configuration.
    pub fn file(path: []const u8) SinkConfig;

    /// Returns a JSON file sink configuration.
    pub fn jsonFile(path: []const u8) SinkConfig;
    
    /// Returns a rotating file sink configuration.
    pub fn rotating(path: []const u8, rotation_interval: []const u8, retention_count: usize) SinkConfig;
    
    /// Returns an error-only sink configuration.
    pub fn errorOnly(path: []const u8) SinkConfig;
    
    /// Returns a network sink configuration.
    pub fn network(uri: []const u8) SinkConfig;
};
```

## See Also

- [Sinks Guide](../guide/sinks.md) - Detailed sink configuration
- [Rotation Guide](../guide/rotation.md) - Log file rotation
- [JSON Guide](../guide/json.md) - JSON output configuration
- [Compression API](compression.md) - Compression options
- [Logger API](logger.md) - Logger sink management

