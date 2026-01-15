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

## Quick Reference: Method Aliases

| Full Method | Alias(es) | Description |
|-------------|-----------|-------------|
| `init()` | `create()` | Initialize record |
| `deinit()` | `destroy()` | Deinitialize record |

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

### `thread_id: ?u64`

Thread ID for concurrent logging identification. Default: `null`.

### `request_id: ?[]const u8`

Request ID for HTTP request tracking. Default: `null`.

### `session_id: ?[]const u8`

Session ID for user session tracking. Default: `null`.

### `user_id: ?[]const u8`

User ID for audit logging. Default: `null`.

### `tags: ?[]const []const u8`

Tags for categorization and filtering. Default: `null`.

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

### `stack_trace: ?*std.builtin.StackTrace`

Captured stack trace for the log event. Automatically populated for `Error` and `Critical` levels. Default: `null`.

## Error Fields

### `error_info: ?ErrorInfo`

Structured error information. Default: `null`.

```zig
pub const ErrorInfo = struct {
    name: []const u8,
    message: []const u8,
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

### `rule_messages: ?[]const RuleMessage`

Rule messages attached to this record if any rules matched during evaluation. Default: `null`.

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

## Aliases

The Record module provides convenience aliases:

| Alias | Method |
|-------|--------|
| `setField` | `addField` |
| `put` | `addField` |
| `trace` | `setTraceId` |
| `span` | `setSpanId` |
| `correlate` | `setCorrelationId` |
| `parentSpan` | `setParentSpanId` |
| `request` | `setRequestId` |
| `session` | `setSessionId` |
| `user` | `setUserId` |
| `duplicate` | `clone` |
| `copy` | `clone` |

## Tracing Methods

- `setTraceId(trace_id: []const u8) !void` - Set distributed trace ID
- `setSpanId(span_id: []const u8) !void` - Set span ID
- `setParentSpanId(parent_id: []const u8) !void` - Set parent span ID for hierarchical tracing
- `setCorrelationId(correlation_id: []const u8) !void` - Set correlation ID

## Identification Methods

- `setRequestId(req_id: []const u8) !void` - Set HTTP request ID
- `setSessionId(sess_id: []const u8) !void` - Set user session ID
- `setUserId(uid: []const u8) !void` - Set user ID for audit logging

## Context Methods

- `addField(key: []const u8, value: json.Value) !void` - Add a context field
- `setError(name, message, stack_trace, code) !void` - Set error information
- `setDuration(duration_ns: u64) void` - Set operation duration
- `setDurationSince(start_time: i128) void` - Set duration from timer start

## Query Methods

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

