---
title: Distributed Tracing Example
description: Example of distributed tracing with Logly.zig. Track requests across microservices with trace IDs, span IDs, correlation IDs, and OpenTelemetry compatibility.
head:
  - - meta
    - name: keywords
      content: tracing example, distributed tracing, trace id, span id, microservices, opentelemetry, request tracking
  - - meta
    - property: og:title
      content: Distributed Tracing Example | Logly.zig
---

# Tracing Example

Distributed tracing support for tracking requests across services.

## Distributed Configuration

To enable service identification and distributed features:

```zig
var config = logly.Config.production();
config.distributed = .{
    .enabled = true,
    .service_name = "payment-service",
    .environment = "production",
    .region = "us-east-1",
};
const logger = try logly.Logger.initWithConfig(allocator, config);
```

## Trace Propagation (Recommended)

In concurrent environments, use request-scoped `DistributedLogger` handles (`withTraceparent(...)` or `withTrace(...)`) instead of mutating global context.

```zig
const std = @import("std");
const logly = @import("logly");
const Config = logly.Config;

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Configure Service
    var config = Config.default();
    config.distributed = .{
        .enabled = true,
        .service_name = "tracing-example",
    };

    const logger = try logly.Logger.initWithConfig(allocator, config);
    defer logger.deinit();

    // Simulate incoming traceparent from upstream service
    const incoming = "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01";

    // Create scoped logger for this request
    var req_logger = try logger.withTraceparent(incoming);
    req_logger = req_logger.inModule("http.request");

    // Logs automatically include service metadata + trace context
    try req_logger.info("Processing request", @src());
    try req_logger.warn("Simulated latency", @src());

    // Child span for nested operation
    const db_logger = req_logger.child("7a085853722dc6d2").inModule("database");
    try db_logger.debug("Executing SQL query", @src());
}
```

## Legacy Trace Context (Global)

For single-threaded scripts or tools:

```zig
    // Set trace context for distributed tracing globally
    try logger.setTraceContext("trace-legacy-global", "span-global");
    
    // All logs will now include trace info
    try logger.info("Processing request", @src());
    try logger.debug("Validating input", @src());
    
    // Clear trace context
    logger.clearTraceContext();
```

## Child Spans

```zig
// Create child spans for nested operations
try logger.setTraceContext("trace-main", "span-root");

// External service call
{
    var span = try logger.startSpan("external-api");
    
    try logger.info("Calling external API", @src());
    try logger.debug("Sending request", @src());
    try logger.info("Response received", @src());
    
    try span.end(null); // End with optional message
}

// Database operation
{
    var db_span = try logger.startSpan("database");
    
    try logger.info("Executing query", @src());
    try logger.success("Query complete", @src());
    
    try db_span.end("database operation done");
}
```

## Context Binding

```zig
// Add service metadata as context
try logger.bind("service", .{ .string = "user-service" });
try logger.bind("version", .{ .string = "1.2.3" });
try logger.bind("environment", .{ .string = "production" });

// All logs will include this context
try logger.info("Service ready", @src());

// Remove context
logger.unbind("version");
```

## W3C Trace Context Propagation

When receiving requests from other services:

```zig
pub fn handleRequest(req: Request, logger: *logly.Logger) !void {
    const traceparent = req.getHeader("traceparent") orelse return error.MissingTraceparent;

    // Prefer request-scoped logger over global mutation
    const req_logger = try logger.withTraceparent(traceparent);
    try req_logger.info("Request received", @src());
    // ...
}
```

When calling other services:

```zig
pub fn callExternalService(logger: *logly.Logger, allocator: std.mem.Allocator) !void {
    var headers = std.StringHashMap([]const u8).init(allocator);
    defer headers.deinit();

    if (try logger.getTraceparentHeader(allocator)) |traceparent| {
        defer allocator.free(traceparent);
        try headers.put("traceparent", traceparent);
    }

    // Make request with propagated context
}
```

## JSON Output with Tracing

```zig
var config = logly.Config.default();
config.json = true;

try logger.setTraceContextFromTraceparent(
    "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01",
);

// Output:
// {
//   "timestamp": "2024-01-15T10:30:00Z",
//   "level": "info",
//   "message": "Request processed",
//   "trace_id": "trace-abc123",
//   "span_id": "span-001",
//   "correlation_id": "request-789"
// }
```

## OpenTelemetry Compatibility

Logly's tracing is compatible with OpenTelemetry concepts:

| Logly | OpenTelemetry |
|-------|---------------|
| `trace_id` | Trace ID |
| `span_id` | Span ID |
| `correlation_id` | Baggage item |
| Context binding | Attributes |

## Use Cases

- **Microservices**: Track requests across service boundaries
- **Debugging**: Follow a single request through the system
- **Performance**: Measure time spent in each component
- **Error tracking**: Correlate errors with specific requests

## Best Practices

1. **Generate trace IDs at entry** - Create at the edge of your system
2. **Propagate always** - Include trace IDs in all inter-service calls
3. **Use meaningful span names** - Name spans by operation, not function
4. **Include correlation IDs** - Link logs to business transactions
5. **Clean up context** - Clear trace context between requests
