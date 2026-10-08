---
title: Distributed Tracing Guide
description: Implement distributed tracing with Logly.zig using OpenTelemetry-compatible trace and span IDs. Correlate logs across microservices and track request flows through your system.
head:
  - - meta
    - name: keywords
      content: distributed tracing, trace id, span id, correlation id, opentelemetry, microservices logging, request tracking, APM
---

# Distributed Tracing

Logly.zig provides built-in support for distributed tracing, enabling you to correlate logs across microservices and track request flows through your system.

## Overview

The tracing module enables you to:
- Propagate trace context across services
- Generate unique trace and span IDs
- Create hierarchical spans for operations
- Correlate logs with request IDs
- Include trace context in JSON output

## Basic Concepts

### Trace ID
A unique identifier for an entire request flow across all services.

### Span ID
A unique identifier for a single operation within a trace.

### Correlation ID
A business-level identifier for grouping related requests.

## Configuration

To enable distributed features, configure `DistributedConfig` in your global configuration:

```zig
var config = logly.Config.production();
config.distributed = .{
    .enabled = true,
    .serviceName = "payment-service",
    .region = "us-east-1",
    .environment = "production",
};
const logger = try logly.Logger.init(allocator, config);
```

## Trace Propagation (Recommended)

In concurrent applications (like web servers), use `withTrace()` to create a lightweight, context-aware logger for each request.

```zig
// In your request handler
const traceId = request.headers.get("X-Trace-ID") orelse "generated-id";
const spanId = request.headers.get("X-Span-ID");

// Create a scoped logger
const reqLogger = logger.withTrace(traceId, spanId);

// Logs will include trace_id, span_id, and service context
try reqLogger.info("Processing payment"); 
```

## Legacy Usage (Global State)

For single-threaded scripts, you can set global context:

```zig
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var logger = try logly.Logger.init(allocator);
    defer logger.deinit();

    // Set trace context (e.g., from incoming request)
    try logger.setTraceContext("trace-abc-123", "span-parent-456");

    // All subsequent logs include the trace context
    try logger.info("Processing request");
    try logger.debug("Validating input");
    try logger.info("Request completed");

    // Clear context when done
    logger.clearTraceContext();
}
```

## Setting Trace Context

### From Incoming Request

```zig
// In HTTP handler
fn handleRequest(req: *Request, logger: *logly.Logger) !void {
    // Extract trace context from headers
    const traceId = req.getHeader("X-Trace-ID") orelse generateTraceId();
    const spanId = req.getHeader("X-Span-ID");

    try logger.setTraceContext(traceId, spanId);
    defer logger.clearTraceContext();

    try logger.info("Handling request");
    // ... process request ...
}
```

### Setting Correlation ID

```zig
// Set correlation ID for business context
try logger.setCorrelationId("order-12345");

try logger.info("Processing order");
try logger.info("Validating inventory");
try logger.info("Charging payment");
```

## Working with Spans

Spans represent individual operations within a trace:

```zig
const logly = @import("logly");

pub fn processOrder(logger: *logly.Logger, order_id: []const u8) !void {
    // Create a span for this operation
    const span = try logger.startSpan("process_order");
    defer span.end(null) catch {};

    try logger.infof("Processing order: {s}", .{order_id});

    // Nested span for database operation
    {
        const db_span = try logger.startSpan("database_query");
        defer db_span.end(null) catch {};

        try logger.info("Querying order from database");
        // ... database operation ...
    }

    // Nested span for payment
    {
        const payment_span = try logger.startSpan("payment_processing");
        defer payment_span.end(null) catch {};

        try logger.info("Processing payment");
        // ... payment operation ...
    }

    try logger.info("Order processing complete");
}
```

## JSON Output with Tracing

Enable trace IDs in JSON output:

```zig
var config = logly.Config.default();
config.format = .json;
logger.configure(config);

 _ = try logger.addSink(.{
    .format = .json,
    .includeTraceId = true,
});

try logger.setTraceContext("trace-123", "span-456");
try logger.info("Processing request");

// Output:
// {
//   "timestamp": "2024-01-15T10:30:00Z",
//   "level": "info",
//   "message": "Processing request",
//   "trace_id": "trace-123",
//   "span_id": "span-456"
// }
```

## Production Example

```zig
const std = @import("std");
const logly = @import("logly");

// Simulated HTTP request context
const RequestContext = struct {
    traceId: []const u8,
    spanId: ?[]const u8,
    correlationId: ?[]const u8,
};

pub fn handleHttpRequest(
    logger: *logly.Logger,
    ctx: RequestContext,
) !void {
    // Set trace context from request
    try logger.setTraceContext(ctx.traceId, ctx.spanId);
    if (ctx.correlationId) |corr_id| {
        try logger.setCorrelationId(corr_id);
    }
    defer logger.clearTraceContext();

    // Create span for this handler
    const span = try logger.startSpan("http_handler");
    defer span.end(null) catch {};

    try logger.info("Request received");

    // Call downstream service
    {
        const service_span = try logger.startSpan("downstream_call");
        defer service_span.end(null) catch {};

        try logger.info("Calling downstream service");
        // Pass trace context to downstream service
        // downstream.call(ctx.trace_id, service_span.span_id);
    }

    try logger.info("Request completed");
}

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    const allocator = gpa.allocator();

    var logger = try logly.Logger.init(allocator);
    defer logger.deinit();

    // JSON sink with trace IDs
     _ = try logger.addSink(.{
        .format = .json,
        .includeTraceId = true,
    });

    // Simulate incoming request
    const ctx = RequestContext{
        .traceId = "trace-abc-123-def-456",
        .spanId = "span-parent-789",
        .correlationId = "user-request-001",
    };

    try handleHttpRequest(logger, ctx);
}
```

## Span Context

The `SpanContext` returned by `startSpan` contains:

```zig
pub const SpanContext = struct {
    logger: *Logger,
    parentSpanId: ?[]const u8,  // Previous span to restore on end
    startTime: i128,

    /// End the span and log duration with optional message
    pub fn end(self: *SpanContext, message: ?[]const u8) !void {
        // Calculates duration and restores parent span
    }

    /// End the span without logging
    pub fn endSilent(self: *SpanContext) void {
        // Just restores parent span, no logging
    }
};
```

## Context Binding with Tracing

Combine tracing with context binding:

```zig
// Set trace context
try logger.setTraceContext("trace-123", null);

// Bind additional context
try logger.bind("user_id", .{ .string = "user-456" });
try logger.bind("request_path", .{ .string = "/api/orders" });

// All logs include trace ID and bound context
try logger.info("Processing user request");
```

## Best Practices

1. **Generate IDs at entry points**: Create trace IDs when requests enter your system
2. **Propagate context**: Pass trace context to downstream services
3. **Use meaningful span names**: Name spans after the operation (e.g., "database_query", "http_call")
4. **Keep spans short**: Create spans for significant operations, not every function
5. **Clear context when done**: Always clear trace context at request boundaries
6. **Enable in JSON output**: Include trace IDs in structured logs for analysis

## OpenTelemetry Compatibility

Logly-Zig's trace IDs are compatible with OpenTelemetry format:
- Trace ID: 32 hex characters (128 bits)
- Span ID: 16 hex characters (64 bits)

```zig
// Logly generates compatible IDs
const span = try logger.startSpan("operation");
// span.span_id is a 16-character hex string
```

## Integration with APM Tools

Export trace IDs to integrate with APM tools:

```zig
// Include trace ID in error reports
if (logger.traceId) |traceId| {
    error_reporter.setContext("trace_id", traceId);
}

// Include in API responses for debugging
response.setHeader("X-Trace-ID", logger.traceId orelse "none");
```

## See Also

- [Metrics](/guide/metrics) - Logging metrics collection
- [JSON Logging](/guide/json) - Structured JSON output
- [Configuration](/guide/configuration) - Global configuration options
- [Context](/guide/context) - Structured context binding
