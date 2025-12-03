# Tracing Example

Distributed tracing support for tracking requests across services.

## Basic Trace Context

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const logger = try logly.Logger.init(allocator);
    defer logger.deinit();

    // Set trace context for distributed tracing
    try logger.setTraceContext("trace-abc123", "span-001");
    try logger.setCorrelationId("request-789");

    // All logs will now include trace info
    try logger.info("Processing request");
    try logger.debug("Validating input");
    try logger.info("Request completed");

    // Clear trace context
    logger.clearTraceContext();
}
```

## Child Spans

```zig
// Create child spans for nested operations
try logger.setTraceContext("trace-main", "span-root");

// External service call
{
    var span = try logger.startSpan("external-api");
    
    try logger.info("Calling external API");
    try logger.debug("Sending request");
    try logger.info("Response received");
    
    try span.end(null); // End with optional message
}

// Database operation
{
    var db_span = try logger.startSpan("database");
    
    try logger.info("Executing query");
    try logger.success("Query complete");
    
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
try logger.info("Service ready");

// Remove context
logger.unbind("version");
```

## Trace ID Propagation

When receiving requests from other services:

```zig
pub fn handleRequest(req: Request, logger: *logly.Logger) !void {
    // Extract trace ID from incoming request headers
    const trace_id = req.getHeader("X-Trace-ID") orelse 
                     try generateTraceId();
    const parent_span = req.getHeader("X-Span-ID");
    
    // Set trace context
    try logger.setTraceContext(trace_id, null);
    
    // Create new span for this service
    var span = try logger.startSpan("handle-request");
    defer span.end(null) catch {};
    
    // Process request
    try logger.info("Request received");
    // ...
}
```

When calling other services:

```zig
// Note: trace_id and span_id are internal fields on the logger
// You can access them by extracting from the log record context
// or pass them explicitly through your application

pub fn callExternalService(trace_id: []const u8, span_id: []const u8) !void {
    // Include trace headers in outgoing request
    var headers = std.StringHashMap([]const u8).init(allocator);
    defer headers.deinit();
    
    try headers.put("X-Trace-ID", trace_id);
    try headers.put("X-Span-ID", span_id);
    
    // Make request with trace context
    // ...
}
```

## JSON Output with Tracing

```zig
var config = logly.Config.default();
config.json = true;
config.include_trace_id = true;

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
