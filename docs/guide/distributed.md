---
title: Distributed Systems Guide
description: Build distributed logging architectures with Logly.zig. Learn how to propagate context across microservices, configure service identity, and integrate with centralized log aggregators.
head:
  - - meta
    - name: keywords
      content: distributed logging, microservices logging, distributed tracing, log aggregation, service context, correlation id
---

# Distributed Systems

In a microservices or distributed architecture, logging requires more than just writing text to a file. You need to verify **service identity**, follow requests across boundaries with **trace propagation**, and send logs to a **centralized aggregator**.

## The Challenges

1.  **Correlation**: How do I find all logs related to a single user request that touched 5 different services?
2.  **Identity**: Which service instance produced this error? Was it staging or prod? US or EU?
3.  **Aggregation**: How do I get logs from ephemeral containers into a searchable database?

Logly.zig addresses these with its `DistributedConfig` and `DistributedLogger`.

## 1. Service Identity

Every log should carry metadata about where it came from. Instead of manually adding `"service": "auth"` to every log message, configure it globally.

```zig
var config = logly.Config.production();
config.distributed = .{
    .enabled = true,
    .serviceName = "auth-service",
    .serviceVersion = "2.1.0",
    .environment = getEnv("APP_ENV") orelse "local",
    .region = "us-east-1",
    .instanceId = getEnv("HOSTNAME"), // e.g., pod name
};
```

When enabled, these fields are automatically added to your JSON output:

```json
{
  "timestamp": "...",
  "level": "ERROR",
  "message": "Database connection failed",
  "service": "auth-service",
  "version": "2.1.0",
  "env": "production",
  "region": "us-east-1"
}
```

## 2. Trace Propagation

To solve the correlation problem, Logly uses **Trace IDs** and **Span IDs**.

### The `withTrace()` Pattern

In a concurrent web server (like zap or http.zig), avoid setting global state. Instead, create a lightweight logger handle for the request scope.

```zig
fn handleRequest(req: Request, global_logger: *logly.Logger) !void {
    // 1. Extract headers from upstream
    const traceId = req.headers.get("X-Trace-ID") orelse newUuid();
    const spanId = req.headers.get("X-Span-ID");

    // 2. Create scoped logger
    const logger = global_logger.withTrace(traceId, spanId);

    // 3. Log normally - context is auto-injected
    try logger.info("Handling login request"); 
    // -> { "trace_id": "uuid...", "span_id": "...", "message": "Handling..." }
}
```

## 3. Centralized Aggregation

For distributed systems, do not log to local files (which disappear when containers restart). Use **Network Sinks**.

### TCP/UDP Logging

Send logs directly to Logstash, Fluentd, or Vector.

```zig
// Send JSON logs to Vector agent sidecar
 _ = try logger.addSink(.{
    .path = "tcp://localhost:9000",
    .format = .json,
});
```

The combination of **JSON output** + **Distributed Config** + **Network Sink** ensures your logs arrive at your observability platform fully structured and correlated.

## 4. Callbacks

You can hook into distributed events for metrics, auditing, or custom behavior. This allows you to react instantly when a new trace context is initialized within the application.

```zig
const std = @import("std");
const logly = @import("logly");

fn onTraceStarted(traceId: []const u8) void {
    // Example: Increment a metrics counter or log to stdout
    std.debug.print("[Metrics] New trace initiated: {s}\n", .{traceId});
}

fn onSpanStarted(spanId: []const u8, name: []const u8) void {
    std.debug.print("[Metrics] Span '{s}' started: {s}\n", .{name, spanId});
}

pub fn main() !void {
    var allocator = std.heap.page_allocator;
    var logger = try logly.Logger.init(allocator);
    defer logger.deinit();

    var config = logly.Config.default();
    config.distributed.enabled = true;
    
    // Register the callbacks
    config.distributed.onTraceCreated = onTraceStarted;
    config.distributed.onSpanCreated = onSpanStarted;
    
    logger.configure(config);

    // This will trigger 'onTraceStarted'
    try logger.setTraceContext("trace-uuid-12345", null);
    
    // This will trigger 'onSpanStarted'
    var span = try logger.startSpan("database_query");
    defer span.end();

    try logger.info("Request processing started", .{});
}
```

## Best Practices

*   **Always enable JSON** for distributed environments. Text logs are hard to parse at scale.
*   **Use `withTrace()`** for request logic. It's thread-safe and zero-allocation (uses pointers to the main logger).
*   **Standardize Headers**: Ensure all your services use the same trace headers. You can customize these in `config.distributed` (e.g., `traceHeader`, `spanHeader`, `baggageHeader`).

## Configuration Reference

See the [Distributed Config API](../api/distributed.md) for full configuration options including `serviceName`, `environment`, `region`, and custom header mapping.
