# Sink API

The `Sink` struct represents a destination for log messages.

## SinkConfig

Configuration for a sink.

### Fields

- `path: ?[]const u8`: Path to log file (null for console)
- `rotation: ?[]const u8`: Rotation interval
- `size_limit: ?u64`: Max file size
- `size_limit_str: ?[]const u8`: Max file size as string
- `retention: ?usize`: Number of files to keep
- `level: ?Level`: Minimum log level
- `async_write: bool`: Enable async writing
- `buffer_size: usize`: Buffer size
- `json: bool`: Force JSON output
- `enabled: bool`: Enable/disable sink initially

## Methods

### `init(allocator: std.mem.Allocator, config: SinkConfig) !*Sink`

Initializes a new sink.

### `deinit() void`

Deinitializes the sink.

### `write(record: *const Record, global_config: Config) !void`

Writes a log record to the sink.

### `flush() !void`

Flushes the sink buffer.
