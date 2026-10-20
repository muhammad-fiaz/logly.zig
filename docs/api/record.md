---
title: Record API Reference
description: API reference for Logly.zig Record struct. Log event representation with message, level, timestamp, source location, context, trace IDs, and metadata fields.
head:
  - - meta
    - name: keywords
      content: record api, log event, log record, structured log, log fields, trace context, source location
  - - meta
    - property: og:title
      content: Record API Reference | Logly.zig
---

# Record API

The `Record` struct represents a single log event.

## Core Fields

### `level: Level`

The log level (trace, debug, info, success, warning, err, fail, critical).

### `message: []const u8`

The log message content.

### `timestamp: i64`

Unix timestamp in milliseconds when the log was created.

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

### `threadId: ?u64`

Thread ID for concurrent logging identification. Default: `null`.

### `requestId: ?[]const u8`

Request ID for HTTP request tracking. Default: `null`.

### `sessionId: ?[]const u8`

Session ID for user session tracking. Default: `null`.

### `userId: ?[]const u8`

User ID for audit logging. Default: `null`.

### `tags: ?[]const []const u8`

Tags for categorization and filtering. Default: `null`.

## Tracing Fields

### `traceId: ?[]const u8`

Distributed trace ID for request tracking across services. Default: `null`.

```zig
record.traceId = "abc123-def456";
```

### `spanId: ?[]const u8`

Span ID within a trace for nested operation tracking. Default: `null`.

```zig
record.spanId = "span-001";
```

### `correlationId: ?[]const u8`

Correlation ID for linking related logs. Default: `null`.

```zig
record.correlationId = "request-789";
```

### `parentSpanId: ?[]const u8`

Parent span ID for hierarchical tracing. Default: `null`.

### `stackTrace: ?*std.builtin.StackTrace`

Captured stack trace for the log event. Populated for `err`, `fail`, `critical`, and `fatal` records when `captureStackTrace` is enabled. Default: `null`.

## Error Fields

### `errorInfo: ?ErrorInfo`

Structured error information. Default: `null`.

```zig
pub const ErrorInfo = struct {
    name: []const u8,
    message: []const u8,
    stackTrace: ?[]const u8 = null,
    code: ?i32 = null,
    errorCategory: ?ErrorCategory = null,
};

pub const ErrorCategory = enum {
    io,
    network,
    logic,
    oom,
    unknown,
};
```

## Timing Fields

### `durationNs: ?u64`

Duration of the operation in nanoseconds. Useful for performance logging. Default: `null`.

```zig
const start = logly.Utils.currentNanos();
// ... operation ...
record.durationNs = @as(u64, @intCast(logly.Utils.currentNanos() - start));
```

## Context

### `context: std.StringHashMap(std.json.Value)`

Bound context variables for structured logging.

```zig
try record.context.put("user_id", .{ .string = "12345" });
try record.context.put("request_count", .{ .integer = 42 });
```

### `invokeMessages: ?[]const InvokeMessage`

Extra messages attached to this record if any triggers matched during evaluation. Default: `null`.

## Methods

### `init(allocator, level, message) Record`

Creates a new Record with the given level and message.

```zig
var record = Record.init(allocator, .info, "User logged in");
defer record.deinit();
```

### `initCustom(allocator, level, customName, customColor, message) Record`

Creates a new Record with a custom level name and `Color.Color` value.

```zig
var record = Record.initCustom(
    allocator,
    .info,
    "AUDIT",                        // Custom level name
    logly.Color.parse("35").?,      // Magenta ANSI color
    "Security audit event",
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
var record = Record.initCustom(allocator, .info, "AUDIT", logly.Color.parse("35").?, "msg");
const name = record.levelName(); // Returns "AUDIT"

var standard = Record.init(allocator, .warning, "msg");
const std_name = standard.levelName(); // Returns "WARNING"
```

### `levelColor(self) Color.Color`

Returns the custom color when set, otherwise the standard level color.

```zig
var record = Record.initCustom(allocator, .info, "AUDIT", logly.Color.parse("35").?, "msg");
const color = record.levelColor(); // Magenta Color value

var standard = Record.init(allocator, .warning, "msg");
const std_color = standard.levelColor(); // Warning color
```

### `generateSpanId(allocator) ![]u8`

Generates a unique span ID (16 hex characters).

```zig
const spanId = try Record.generateSpanId(allocator);
defer allocator.free(spanId);
// span_id: "a1b2c3d4e5f67890"
```

## Serialization

### `toLogfmt(self: *const Record, writer: anytype) !void`

Serializes the record directly into logfmt (`key=value`) string format using the provided writer.

## Custom Level Fields

### `customLevelName: ?[]const u8`

Custom name for non-standard levels (e.g., "AUDIT", "ALERT", "NOTICE"). Used by `levelName()`.

### `customLevelColor: ?Color.Color`

Custom color value for custom levels. Used by `levelColor()`.

## Example Usage

```zig
const logly = @import("logly");
const Record = logly.Record;

// Standard record
var record = Record.init(allocator, .info, "Request processed");
defer record.deinit();

// Add tracing info
record.traceId = "trace-abc123";
record.spanId = "span-001";

// Add timing
record.durationNs = 1500000; // 1.5ms

// Add context
try record.context.put("user_id", .{ .string = "user123" });
try record.context.put("status_code", .{ .integer = 200 });

// Custom level record
var audit_record = Record.initCustom(
    allocator,
    .info,
    "AUDIT",
    logly.Color.parse("35;1").?, // Bold magenta
    "Security event",
);
defer audit_record.deinit();

// The formatter uses levelName() and levelColor() automatically
// Output: [2024-01-15 10:30:45] [AUDIT] Security event (in bold magenta)
```

## Tracing Methods

- `setTraceId(traceId: []const u8) !void` - Set distributed trace ID
- `setSpanId(spanId: []const u8) !void` - Set span ID
- `setParentSpanId(parentId: []const u8) !void` - Set parent span ID for hierarchical tracing
- `setCorrelationId(correlationId: []const u8) !void` - Set correlation ID

## Identification Methods

- `setRequestId(reqId: []const u8) !void` - Set HTTP request ID
- `setSessionId(sessId: []const u8) !void` - Set user session ID
- `setUserId(uid: []const u8) !void` - Set user ID for audit logging

## Context Methods

- `addField(key: []const u8, value: json.Value) !void` - Add a context field
- `addTag(tag: []const u8) !void` - Add a lightweight string tag
- `setError(name, message, stackTrace, code) !void` - Set error information
- `setDuration(durationNs: u64) void` - Set operation duration
- `setDurationSince(startTime: i128) void` - Set duration from timer start

## Query Methods

- `severity() u8` - Get numeric severity (0-100) derived from level priority
- `isHighSeverity(threshold: Level) bool` - Check if the record level is at or above the given level
- `hasTracing() bool` - Check if trace or span ID is set
- `hasCustomLevel() bool` - Check if custom level is set
- `hasContext() bool` - Check if context fields exist
- `hasStackTrace() bool` - Check if stack trace is set
- `hasError() bool` - Check if error info is set
- `hasRequestId() bool` - Check if request ID is set
- `hasSessionId() bool` - Check if session ID is set
- `hasUserId() bool` - Check if user ID is set
- `hasParentSpan() bool` - Check if parent span ID is set
- `contextCount() usize` - Get number of context fields

## Static Methods

- `generateTraceId(allocator) ![]u8` - Generate unique trace ID (32 hex chars)
- `generateSpanId(allocator) ![]u8` - Generate unique span ID (16 hex chars)

## See Also

- [Logger API](logger.md) - Logger methods for creating records
- [Level API](level.md) - Log level definitions
- [Tracing Guide](../guide/tracing.md) - Distributed tracing
- [Context Guide](../guide/context.md) - Context binding
