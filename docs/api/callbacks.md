# Callback API

The Callback API allows you to hook into the logging lifecycle for monitoring, tracing, and custom extensions.

## Core Callbacks

### Log Callback

Invoked when a log record is successfully processed.

```zig
pub const LogCallback = *const fn (record: *const Record) anyerror!void;
```

**Usage:**

```zig
fn myLogCallback(record: *const logly.Record) !void {
    if (record.level == .err) {
        // Handle error...
    }
}

logger.setLogCallback(&myLogCallback);
```

### Color Callback

Invoked when determining the color for a specific log level.

```zig
pub const ColorCallback = *const fn (level: Level, default_color: []const u8) []const u8;
```

**Usage:**

```zig
fn myColorCallback(level: logly.Level, default: []const u8) []const u8 {
    if (level == .info) return "\x1b[35m"; // Magento for Info
    return default;
}

logger.setColorCallback(&myColorCallback);
```

## Lifecycle Callbacks

These callbacks are configured via `Config` or specialized setter methods.

### on_record_filtered

Invoked when a record is dropped due to level filtering or other rules.

```zig
callback: *const fn(context: ?*anyopaque, level: Level) void
```

### on_sink_error

Invoked when a sink fails to write a message.

```zig
callback: *const fn(context: ?*anyopaque, err: anyerror) void
```

### on_logger_initialized

Invoked after the logger is fully initialized.

```zig
callback: *const fn(context: ?*anyopaque) void
```

### on_logger_destroyed

Invoked just before the logger is deinitialized.

```zig
callback: *const fn(context: ?*anyopaque) void
```
