# Logger API

The `Logger` struct is the central component of the Logly library, orchestrating all logging operations, sink management, configuration, and enterprise features like filtering, sampling, redaction, metrics, and distributed tracing.

## Quick Reference: Method Aliases

| Full Method | Alias(es) | Description |
|-------------|-----------|-------------|
| `addSink()` | `add()` | Add a new sink |
| `removeSink()` | `remove()` | Remove a sink by ID |
| `removeAllSinks()` | `removeAll()`, `clear()` | Remove all sinks |
| `getSinkCount()` | `count()`, `sinkCount()` | Get number of sinks |
| `warning()` | `warn()` | Log at WARNING level |
| `warningf()` | `warnf()` | Formatted WARNING log |
| `critical()` | `crit()` | Log at CRITICAL level |
| `criticalf()` | `critf()` | Formatted CRITICAL log |
| `errf()` | `errorf()` | Formatted ERROR log |

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
- **Alias**: `add()`

```zig
// Both are equivalent
_ = try logger.addSink(.{ .path = "app.log" });
_ = try logger.add(.{ .path = "app.log" });
```

### `removeSink(id: usize) void`

Removes a sink by its ID.

- **Alias**: `remove()`

### `removeAllSinks() usize`

Removes all sinks and returns the count of removed sinks.

- **Aliases**: `removeAll()`, `clear()`

### `enableSink(id: usize) void`

Enables a specific sink by its ID, allowing it to process log records.

### `disableSink(id: usize) void`

Disables a specific sink by its ID, preventing it from processing log records.

### `getSinkCount() usize`

Returns the current number of sinks.

- **Aliases**: `count()`, `sinkCount()`

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

### `custom(level_name: []const u8, message: []const u8, src: ?std.builtin.SourceLocation) !void`

Logs using a registered custom level. The entire line is colored:

```zig
try logger.addCustomLevel("audit", 35, "35;1"); // Bold magenta
try logger.custom("audit", "User login detected", @src());
// Output: [2024-01-15 10:30:45] [AUDIT] myfile.zig:42:0: User login detected (bold magenta)
```

### `customf(level_name: []const u8, comptime fmt: []const u8, args: anytype, src: ?std.builtin.SourceLocation) !void`

Formatted logging with custom levels:

```zig
try logger.customf("audit", "User {s} logged in from {s}", .{ "alice", "10.0.0.1" }, @src());
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

### `logSystemDiagnostics(src: ?std.builtin.SourceLocation) !void`

Collects OS/CPU/memory (and optional per-drive storage) and logs them as a single `info` record. Honors `config.include_drive_diagnostics` and uses the logger's scratch allocator.

```zig
var cfg = logly.Config.default();
cfg.include_drive_diagnostics = true;

const logger = try logly.Logger.initWithConfig(allocator, cfg);
try logger.logSystemDiagnostics(@src());
```

## Logging Methods

All logging methods accept an optional source location parameter. Pass `@src()` to enable clickable file:line:column output in terminal, or `null` if source location is not needed.

### Source Location Parameter

The `src` parameter is **optional** (type `?std.builtin.SourceLocation`):

| Value | Result |
|-------|--------|
| `@src()` | Includes file:line:column in output (when enabled in config) |
| `null` | No source location in output |

```zig
// With source location - recommended for debugging
try logger.info(@src(), "Application started", .{});

// Without source location - useful for high-volume logging
try logger.debug(null, "Processing item", .{});
```

### `trace(src: ?std.builtin.SourceLocation, message: []const u8, args: anytype) !void`

Logs a message at the **TRACE** level (Priority 5).

```zig
try logger.trace(@src(), "Detailed trace info", .{});  // With source location
try logger.trace(null, "Trace without location", .{}); // Without source location
```

### `debug(src: ?std.builtin.SourceLocation, message: []const u8, args: anytype) !void`

Logs a message at the **DEBUG** level (Priority 10).

### `info(src: ?std.builtin.SourceLocation, message: []const u8, args: anytype) !void`

Logs a message at the **INFO** level (Priority 20).

### `success(src: ?std.builtin.SourceLocation, message: []const u8, args: anytype) !void`

Logs a message at the **SUCCESS** level (Priority 25).

### `warning(src: ?std.builtin.SourceLocation, message: []const u8, args: anytype) !void`

Logs a message at the **WARNING** level (Priority 30).

- **Alias**: `warn()`

### `err(src: ?std.builtin.SourceLocation, message: []const u8, args: anytype) !void`

Logs a message at the **ERROR** level (Priority 40).

- **Alias**: `@"error"()` (Zig keyword escape)

### `fail(src: ?std.builtin.SourceLocation, message: []const u8, args: anytype) !void`

Logs a message at the **FAIL** level (Priority 45).

### `critical(src: ?std.builtin.SourceLocation, message: []const u8, args: anytype) !void`

Logs a message at the **CRITICAL** level (Priority 50).

- **Alias**: `crit()`

### `custom(level_name: []const u8, src: ?std.builtin.SourceLocation, message: []const u8, args: anytype) !void`

Logs a message using a user-defined custom level. The level must be registered first.

```zig
try logger.addCustomLevel("audit", 35, "35;1");
try logger.custom("audit", @src(), "User login detected", .{});
```

## Formatted Logging

> **Note**: The main logging methods (`info`, `debug`, etc.) now directly support format strings and arguments. The `f` suffix variants are maintained for backward compatibility.

All logging methods accept a format string and arguments in the same call:

```zig
// Recommended: Use main method with format string
try logger.info(@src(), "User {s} connected from {s}", .{ "alice", "10.0.0.1" });
try logger.warn(@src(), "Request took {d}ms", .{elapsed_ms});
try logger.crit(@src(), "Failed after {d} retries: {s}", .{ retry_count, error_msg });
```

### Legacy Format Methods (f-suffix)

These methods are maintained for backward compatibility:

### `tracef(comptime fmt: []const u8, args: anytype, src: ?std.builtin.SourceLocation) !void`

### `debugf(comptime fmt: []const u8, args: anytype, src: ?std.builtin.SourceLocation) !void`

### `infof(comptime fmt: []const u8, args: anytype, src: ?std.builtin.SourceLocation) !void`

```zig
// Legacy style (still works)
try logger.infof("User {s} connected from {s}", .{ "alice", "10.0.0.1" }, @src());
```

### `successf(comptime fmt: []const u8, args: anytype, src: ?std.builtin.SourceLocation) !void`

### `warningf(comptime fmt: []const u8, args: anytype, src: ?std.builtin.SourceLocation) !void`

- **Alias**: `warnf()`

### `errf(comptime fmt: []const u8, args: anytype, src: ?std.builtin.SourceLocation) !void`

- **Alias**: `errorf()`

### `failf(comptime fmt: []const u8, args: anytype, src: ?std.builtin.SourceLocation) !void`

### `criticalf(comptime fmt: []const u8, args: anytype, src: ?std.builtin.SourceLocation) !void`

- **Alias**: `critf()`

### `customf(level_name: []const u8, comptime fmt: []const u8, args: anytype, src: ?std.builtin.SourceLocation) !void`

## Source Location Display

When you enable `show_filename` and `show_lineno` in the configuration and pass `@src()` to logging calls, the output includes clickable file:line:column information:

```zig
var config = logly.Config.default();
config.show_filename = true;
config.show_lineno = true;
logger.configure(config);

try logger.info(@src(), "This message has source location", .{});
// Output: [2024-01-15 10:30:45] [INFO] myfile.zig:42:0: This message has source location
```

The format `file:line:column:` is compatible with most terminals and IDEs, allowing you to click on it to jump directly to the source location.

## Utility Methods

### `logError(message: []const u8, err_val: anyerror) !void`

Logs an error with automatic error name resolution.

### `logTimed(level: Level, message: []const u8, start_time: i128) !i128`

Logs a message with elapsed time calculation.

### `getRecordCount() u64`

Returns the total number of log records processed.

### `getUptime() i64`

Returns the logger uptime in seconds.
