# Logger API

The `Logger` struct is the central component of the Logly library, orchestrating all logging operations, sink management, and configuration.

## Lifecycle Methods

### `init(allocator: std.mem.Allocator) !*Logger`

Initializes a new `Logger` instance.

- **allocator**: The memory allocator used for internal structures.
- **Returns**: A pointer to the initialized `Logger` or an error.

### `deinit() void`

Deinitializes the logger, freeing all allocated resources including sinks, context maps, and custom levels.

### `configure(config: Config) void`

Updates the global configuration of the logger in a thread-safe manner.

## Sink Management

### `addSink(config: SinkConfig) !usize`

Adds a new output sink (e.g., console, file) with the specified configuration.

- **Returns**: The unique ID of the added sink.

### `enableSink(id: usize) void`

Enables a specific sink by its ID, allowing it to process log records.

### `disableSink(id: usize) void`

Disables a specific sink by its ID, preventing it from processing log records.

## Context Management

### `bind(key: []const u8, value: std.json.Value) !void`

Binds a structured context variable to the logger. These variables are included in every log record (especially useful for JSON output).

### `unbind(key: []const u8) void`

Removes a previously bound context variable.

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

### `flush() !void`

Flushes all sinks.
