# Record API

The `Record` struct represents a single log event.

## Fields

### `level: Level`

The log level.

### `message: []const u8`

The log message.

### `timestamp: i64`

Unix timestamp in milliseconds.

### `module: []const u8`

The module name where the log occurred.

### `function: []const u8`

The function name where the log occurred.

### `file: []const u8`

The filename where the log occurred.

### `line: usize`

The line number where the log occurred.

### `context: std.StringHashMap(std.json.Value)`

Bound context variables.
