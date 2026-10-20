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
  Receives the level and its default tint color; returns the color to use.

  ```zig
  pub const ColorCallback = *const fn (level: Level, defaultColor: logly.Color.Color) logly.Color.Color;
  ```

  **Usage:**

  ```zig
  fn myColorCallback(level: logly.Level, default: logly.Color.Color) logly.Color.Color {
      if (level == .info) return logly.Color.parse("magenta").?;
      return default;
  }

  logger.setColorCallback(&myColorCallback);
  ```

## Lifecycle Callbacks

These callbacks are configured via `Config` or specialized setter methods.

### onRecordFiltered

Invoked when a record is dropped by a filter. The first argument is the reason supplied by the filter.

```zig
callback: *const fn(reason: []const u8, record: *const Record) void
```

Set with `setFilteredCallback()`.

### onSinkError

Invoked when a sink fails to write or flush. Arguments are the sink name and `@errorName(err)`.

```zig
callback: *const fn(sinkName: []const u8, errorName: []const u8) void
```

Set with `setSinkErrorCallback()`.

### onLoggerInitialized

Invoked after the logger is fully initialized.

```zig
callback: *const fn(stats: *const LoggerStats) void
```

Set with `setInitializedCallback()`.

### onLoggerDestroyed

Invoked just before the logger is deinitialized.

```zig
callback: *const fn(stats: *const LoggerStats) void
```

Set with `setDestroyedCallback()`.

### `onCrashCallback`

Invoked immediately when a panic, Windows VEH exception, or POSIX signal occurs.

```zig
callback: *const fn(message: []const u8) void
```

### Thread-pool callbacks

The thread pool exposes callbacks for worker lifecycle and queue events:

- `setThreadStartCallback(threadId)`
- `setThreadStopCallback(threadId, tasksProcessed, uptimeMs)`
- `setTaskSubmittedCallback(priority, queueDepth)`
- `setTaskDequeuedCallback(priority, wait_time_us)`
- `setTaskExecutedCallback(execution_time_us, success)`
- `setWorkStolenCallback(victimThread, thiefThread)`
- `setQueueOverflowCallback(queueSize, capacity)`
