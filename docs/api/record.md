# Record API

The `Record` struct represents a single log event.

## Core Fields

### `level: Level`

The log level (trace, debug, info, success, warning, err, fail, critical).

### `message: []const u8`

The log message content.

### `timestamp: i64`

Unix timestamp in nanoseconds when the log was created.

## Location Fields

### `module: ?[]const u8`

The module name where the log occurred. Default: `null`.

### `function: ?[]const u8`

The function name where the log occurred. Default: `null`.

### `filename: ?[]const u8`

The source filename where the log occurred. Default: `null`.

### `line: ?u32`

The line number where the log occurred. Default: `null`.

### `column: ?u32`

The column number where the log occurred. Default: `null`.

## Tracing Fields

### `trace_id: ?[]const u8`

Distributed trace ID for request tracking across services. Default: `null`.

```zig
record.trace_id = "abc123-def456";
```

### `span_id: ?[]const u8`

Span ID within a trace for nested operation tracking. Default: `null`.

```zig
record.span_id = "span-001";
```

### `correlation_id: ?[]const u8`

Correlation ID for linking related logs. Default: `null`.

```zig
record.correlation_id = "request-789";
```

### `parent_span_id: ?[]const u8`

Parent span ID for hierarchical tracing. Default: `null`.

## Error Fields

### `error_info: ?ErrorInfo`

Structured error information. Default: `null`.

```zig
pub const ErrorInfo = struct {
    name: ?[]const u8 = null,
    message: ?[]const u8 = null,
    stack_trace: ?[]const u8 = null,
    code: ?i32 = null,
};
```

## Timing Fields

### `duration_ns: ?u64`

Duration of the operation in nanoseconds. Useful for performance logging. Default: `null`.

```zig
const start = std.time.nanoTimestamp();
// ... operation ...
record.duration_ns = @as(u64, @intCast(std.time.nanoTimestamp() - start));
```

## Context

### `context: std.StringHashMap(std.json.Value)`

Bound context variables for structured logging.

```zig
try record.context.put("user_id", .{ .string = "12345" });
try record.context.put("request_count", .{ .integer = 42 });
```

## Methods

### `init(allocator, level, message) Record`

Creates a new Record with the given level and message.

```zig
var record = Record.init(allocator, .info, "User logged in");
defer record.deinit();
```

### `initCustom(allocator, level, message, custom_name, custom_color) Record`

Creates a new Record with custom level name and color.

```zig
var record = Record.initCustom(
    allocator,
    .info,
    "Security audit event",
    "AUDIT",   // Custom level name
    "35"       // Magenta color code
);
defer record.deinit();
```

### `deinit(self)`

Releases resources associated with the record.

### `clone(self, allocator) !Record`

Creates a copy of the record.

```zig
const copy = try record.clone(allocator);
defer copy.deinit();
```

### `levelName(self) []const u8`

Returns the level name for display. Returns custom level name if set, otherwise the standard level name.

```zig
var record = Record.initCustom(allocator, .info, "msg", "AUDIT", "35");
const name = record.levelName(); // Returns "AUDIT"

var standard = Record.init(allocator, .warning, "msg");
const std_name = standard.levelName(); // Returns "WARNING"
```

### `levelColor(self) []const u8`

Returns the color code for the level. Returns custom color if set, otherwise the standard level color.

```zig
var record = Record.initCustom(allocator, .info, "msg", "AUDIT", "35");
const color = record.levelColor(); // Returns "35" (magenta)

var standard = Record.init(allocator, .warning, "msg");
const std_color = standard.levelColor(); // Returns "33" (yellow)
```

### `generateSpanId(allocator) ![]u8`

Generates a unique span ID (16 hex characters).

```zig
const span_id = try Record.generateSpanId(allocator);
defer allocator.free(span_id);
// span_id: "a1b2c3d4e5f67890"
```

## Custom Level Fields

### `custom_level_name: ?[]const u8`

Custom name for non-standard levels (e.g., "AUDIT", "ALERT", "NOTICE"). Used by `levelName()`.

### `custom_level_color: ?[]const u8`

Custom ANSI color code for custom levels (e.g., "35", "31;1", "36;4"). Used by `levelColor()`.

## Example Usage

```zig
const logly = @import("logly");
const Record = logly.Record;

// Standard record
var record = Record.init(allocator, .info, "Request processed");
defer record.deinit();

// Add tracing info
record.trace_id = "trace-abc123";
record.span_id = "span-001";

// Add timing
record.duration_ns = 1500000; // 1.5ms

// Add context
try record.context.put("user_id", .{ .string = "user123" });
try record.context.put("status_code", .{ .integer = 200 });

// Custom level record
var audit_record = Record.initCustom(
    allocator,
    .info,
    "Security event",
    "AUDIT",
    "35;1"  // Bold magenta
);
defer audit_record.deinit();

// The formatter uses levelName() and levelColor() automatically
// Output: [2024-01-15 10:30:45] [AUDIT] Security event (in bold magenta)
```
