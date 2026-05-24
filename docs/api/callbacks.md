# Callback API

The Callback API allows you to hook into the logging lifecycle for monitoring, tracing, and custom extensions.

## Quick Reference: Method Aliases

| Full Method | Alias(es) | Description |
|-------------|-----------|-------------|
| `setLogCallback()` | - | Set log callback |
| `setColorCallback()` | - | Set color callback |
| `setLoggedCallback()` | - | Set logged callback |
| `setFilteredCallback()` | - | Set filtered callback |
| `setSinkErrorCallback()` | - | Set sink error callback |
| `setInitializedCallback()` | - | Set initialized callback |
| `setDestroyedCallback()` | - | Set destroyed callback |
| `setCrashCallback()` | `onCrash()` | Set crash callback |
| `setUpdateCallback()` | - | Set update-check callback |
| `setThreadStartCallback()` | `onThreadStart()` | Set thread pool start callback |
| `setThreadStopCallback()` | `onThreadStop()` | Set thread pool stop callback |
| `setTaskSubmittedCallback()` | `onTaskSubmitted()` | Set task submitted callback |
| `setTaskDequeuedCallback()` | `onTaskDequeued()` | Set task dequeued callback |
| `setTaskExecutedCallback()` | `onTaskExecuted()` | Set task executed callback |
| `setWorkStolenCallback()` | `onWorkStolen()` | Set work stolen callback |
| `setQueueOverflowCallback()` | `onQueueOverflow()` | Set queue overflow callback |
| `setWriteCallback()` | `onWrite()` | Set write callback (Sink) |
| `setFlushCallback()` | `onFlush()` | Set flush callback (Sink) |
| `setErrorCallback()` | `onError()` | Set error callback (Sink) |
| `setRotationCallback()` | `onRotation()` | Set rotation callback (Sink) |
| `setStateChangeCallback()` | `onStateChange()` | Set state change callback (Sink) |
| `setCompressionStartCallback()` | `onCompressionStart()` | Set compression start callback (Compression) |
| `setCompressionCompleteCallback()` | `onCompressionComplete()` | Set compression complete callback (Compression) |
| `setCompressionErrorCallback()` | `onCompressionError()` | Set compression error callback (Compression) |
| `setDecompressionCompleteCallback()` | `onDecompressionComplete()` | Set decompression complete callback (Compression) |
| `setArchiveDeletedCallback()` | `onArchiveDeleted()` | Set archive deleted callback (Compression) |

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

### `on_crash_callback`

Invoked immediately when a panic, Windows VEH exception, or POSIX signal occurs.

```zig
callback: *const fn(message: []const u8) void
```

### `on_update_result`

Invoked after the update checker compares the current version against the latest release.

```zig
callback: *const fn(status: UpdateCheckStatus, latest_tag: []const u8, current_version: []const u8) void
```

### `on_thread_pool_callback`

Invoked by the thread pool for worker lifecycle and queue events:

- `setThreadStartCallback(thread_id)`
- `setThreadStopCallback(thread_id, tasks_processed, uptime_ms)`
- `setTaskSubmittedCallback(priority, queue_depth)`
- `setTaskDequeuedCallback(priority, wait_time_us)`
- `setTaskExecutedCallback(execution_time_us, success)`
- `setWorkStolenCallback(victim_thread, thief_thread)`
- `setQueueOverflowCallback(queue_size, capacity)`
