# Logger API

The `Logger` struct is the main entry point for the library.

## Methods

### `init(allocator: std.mem.Allocator) !*Logger`

Initializes a new logger instance.

### `deinit() void`

Deinitializes the logger and frees resources.

### `configure(config: Config) void`

Updates the logger configuration.

### `addSink(config: SinkConfig) !usize`

Adds a new sink with the specified configuration. Returns the sink ID.

### `enableSink(id: usize) void`

Enables a specific sink by ID.

### `disableSink(id: usize) void`

Disables a specific sink by ID.

### `bind(key: []const u8, value: std.json.Value) !void`

Binds a context variable to the logger.

### `unbind(key: []const u8) void`

Removes a bound context variable.

### `log(level: Level, message: []const u8) !void`

Logs a message at the specified level.

### `trace(message: []const u8) !void`

Logs a message at TRACE level.

### `debug(message: []const u8) !void`

Logs a message at DEBUG level.

### `info(message: []const u8) !void`

Logs a message at INFO level.

### `success(message: []const u8) !void`

Logs a message at SUCCESS level.

### `warning(message: []const u8) !void`

Logs a message at WARNING level.

### `err(message: []const u8) !void`

Logs a message at ERROR level.

### `fail(message: []const u8) !void`

Logs a message at FAIL level.

### `critical(message: []const u8) !void`

Logs a message at CRITICAL level.

### `custom(level_name: []const u8, message: []const u8) !void`

Logs a message at a custom level.

### `flush() !void`

Flushes all sinks.
