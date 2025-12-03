# Logger API

The `Logger` struct is the central component of the Logly library, orchestrating all logging operations, sink management, configuration, and enterprise features like filtering, sampling, redaction, metrics, and distributed tracing.

## Lifecycle Methods

### `init(allocator: std.mem.Allocator) !*Logger`

Initializes a new `Logger` instance with default configuration.

- **allocator**: The memory allocator used for internal structures.
- **Returns**: A pointer to the initialized `Logger` or an error.

### `initWithConfig(allocator: std.mem.Allocator, config: Config) !*Logger`

Initializes a new `Logger` instance with a specific configuration preset.

- **allocator**: The memory allocator used for internal structures.
- **config**: The configuration to use (e.g., `ConfigPresets.production()`).
- **Returns**: A pointer to the initialized `Logger` or an error.

### `deinit() void`

Deinitializes the logger, freeing all allocated resources including sinks, context maps, custom levels, and enterprise components.

### `configure(config: Config) void`

Updates the global configuration of the logger in a thread-safe manner.

## Sink Management

### `addSink(config: SinkConfig) !usize`

Adds a new output sink (e.g., console, file) with the specified configuration.

- **Returns**: The unique ID of the added sink.

### `removeSink(id: usize) void`

Removes a sink by its ID.

### `removeAllSinks() usize`

Removes all sinks and returns the count of removed sinks.

### `enableSink(id: usize) void`

Enables a specific sink by its ID, allowing it to process log records.

### `disableSink(id: usize) void`

Disables a specific sink by its ID, preventing it from processing log records.

### `getSinkCount() usize`

Returns the current number of sinks.

## Context Management

### `bind(key: []const u8, value: std.json.Value) !void`

Binds a structured context variable to the logger. These variables are included in every log record (especially useful for JSON output).

```zig
try logger.bind("user_id", .{ .string = "usr_12345" });
try logger.bind("request_id", .{ .string = "req_abc" });
```

### `unbind(key: []const u8) void`

Removes a previously bound context variable.

### `clearBindings() void`

Removes all bound context variables.

## Enterprise Features

### Filtering

#### `setFilter(filter: *Filter) void`

Sets a filter for rule-based log filtering. Allows filtering by level, message patterns, modules, and more.

```zig
var filter = logly.Filter.init(allocator);
defer filter.deinit();
try filter.addMinLevel(.warning);
logger.setFilter(&filter);
```

### Sampling

#### `setSampler(sampler: *Sampler) void`

Sets a sampler for log sampling and rate limiting. Useful for high-volume logging scenarios.

```zig
var sampler = logly.Sampler.init(allocator, logly.SamplerPresets.sample10Percent());
defer sampler.deinit();
logger.setSampler(&sampler);
```

### Redaction

#### `setRedactor(redactor: *Redactor) void`

Sets a redactor for sensitive data masking in log messages.

```zig
var redactor = logly.Redactor.init(allocator);
defer redactor.deinit();
try redactor.addPattern("password", .keyword, "password", "[REDACTED]");
logger.setRedactor(&redactor);
```

### Metrics

#### `enableMetrics() void`

Enables metrics collection for logging performance monitoring.

```zig
logger.enableMetrics();
```

#### `getMetrics() ?Metrics.Snapshot`

Returns a snapshot of current logging metrics, or null if metrics are not enabled.

```zig
if (logger.getMetrics()) |metrics| {
    std.debug.print("Total records: {}\n", .{metrics.total_records});
    std.debug.print("Errors: {}\n", .{metrics.error_count});
}
```

## Distributed Tracing

### `setTraceContext(trace_id: []const u8, span_id: ?[]const u8) !void`

Sets the trace context for distributed tracing. All subsequent log records will include these IDs.

```zig
try logger.setTraceContext("trace-abc-123", "span-xyz-789");
```

### `setCorrelationId(correlation_id: []const u8) !void`

Sets a correlation ID for request correlation across services.

```zig
try logger.setCorrelationId("corr-12345");
```

### `clearTraceContext() void`

Clears all trace context (trace_id, span_id, correlation_id).

### `startSpan(name: []const u8) !SpanContext`

Creates a new span for tracing. The span automatically generates a span ID and tracks duration.

```zig
const span = try logger.startSpan("database_query");
defer span.end(null) catch {};

// Your operation here
try logger.info("Executing query");
```

## Module-Level Logging

### `setModuleLevel(module: []const u8, level: Level) !void`

Sets a log level filter for a specific module.

```zig
try logger.setModuleLevel("database", .debug);
try logger.setModuleLevel("http.server", .info);
```

### `getModuleLevel(module: []const u8) ?Level`

Gets the log level for a specific module, or null if not set.

### `scoped(module: []const u8) ScopedLogger`

Returns a scoped logger for a specific module.

```zig
const db_logger = logger.scoped("database");
try db_logger.info("Connection established");
```

## Custom Levels

### `addCustomLevel(name: []const u8, priority: u8, color: []const u8) !void`

Registers a custom log level with a name, priority, and ANSI color code.

```zig
// Color code only (no \x1b[ prefix needed)
try logger.addCustomLevel("audit", 35, "35");     // Magenta
try logger.addCustomLevel("security", 55, "91");  // Bright red
try logger.addCustomLevel("notice", 22, "36;1");  // Bold cyan
try logger.addCustomLevel("alert", 42, "31;4");   // Underline red
```

**Color Code Reference:**

| Code | Color | Code | Color |
|------|-------|------|-------|
| `31` | Red | `91` | Bright Red |
| `32` | Green | `92` | Bright Green |
| `33` | Yellow | `93` | Bright Yellow |
| `34` | Blue | `94` | Bright Blue |
| `35` | Magenta | `95` | Bright Magenta |
| `36` | Cyan | `96` | Bright Cyan |
| `37` | White | `97` | Bright White |

**Modifiers:** Add with semicolon: `31;1` (bold), `34;4` (underline), `32;7` (reverse)

### `removeCustomLevel(name: []const u8) void`

Removes a previously registered custom level.

### `custom(level_name: []const u8, message: []const u8) !void`

Logs using a registered custom level. The entire line is colored:

```zig
try logger.addCustomLevel("audit", 35, "35;1"); // Bold magenta
try logger.custom("audit", "User login detected");
// Output: [2024-01-15 10:30:45] [AUDIT] User login detected (bold magenta)
```

### `customf(level_name: []const u8, comptime fmt: []const u8, args: anytype) !void`

Formatted logging with custom levels:

```zig
try logger.customf("audit", "User {s} logged in from {s}", .{ "alice", "10.0.0.1" });
```

## Callbacks

### `setLogCallback(callback: *const fn (*const Record) anyerror!void) void`

Sets a callback function that is invoked for each log record. Useful for integration with external systems.

### `setColorCallback(callback: *const fn (Level, []const u8) []const u8) void`

Sets a custom color callback for overriding default level colors.

## Control Methods

### `enable() void`

Enables the logger (logging is enabled by default).

### `disable() void`

Temporarily disables all logging.

### `flush() !void`

Flushes all sinks, ensuring all buffered data is written.

## Logging Methods

### `log(level: Level, message: []const u8) !void`

Logs a raw message at the specified level.

### `trace(message: []const u8) !void`

Logs a message at the **TRACE** level (Priority 5).

### `debug(message: []const u8) !void`

Logs a message at the **DEBUG** level (Priority 10).

### `info(message: []const u8) !void`

Logs a message at the **INFO** level (Priority 20).

### `success(message: []const u8) !void`

Logs a message at the **SUCCESS** level (Priority 25).

### `warning(message: []const u8) !void`

Logs a message at the **WARNING** level (Priority 30).

### `err(message: []const u8) !void`

Logs a message at the **ERROR** level (Priority 40).

### `fail(message: []const u8) !void`

Logs a message at the **FAIL** level (Priority 45).

### `critical(message: []const u8) !void`

Logs a message at the **CRITICAL** level (Priority 50).

### `custom(level_name: []const u8, message: []const u8) !void`

Logs a message using a user-defined custom level. The level must be registered first.

## Formatted Logging

All standard logging methods have a corresponding `f` suffix variant (e.g., `infof`, `debugf`) that accepts a format string and arguments, similar to `std.log` or `printf`.

### `tracef(comptime fmt: []const u8, args: anytype) !void`

### `debugf(comptime fmt: []const u8, args: anytype) !void`

### `infof(comptime fmt: []const u8, args: anytype) !void`

### `successf(comptime fmt: []const u8, args: anytype) !void`

### `warningf(comptime fmt: []const u8, args: anytype) !void`

### `errf(comptime fmt: []const u8, args: anytype) !void`

### `failf(comptime fmt: []const u8, args: anytype) !void`

### `criticalf(comptime fmt: []const u8, args: anytype) !void`

### `customf(level_name: []const u8, comptime fmt: []const u8, args: anytype) !void`

## Utility Methods

### `logError(message: []const u8, err_val: anyerror) !void`

Logs an error with automatic error name resolution.

### `logTimed(level: Level, message: []const u8, start_time: i128) !i128`

Logs a message with elapsed time calculation.

### `getRecordCount() u64`

Returns the total number of log records processed.

### `getUptime() i64`

Returns the logger uptime in seconds.
