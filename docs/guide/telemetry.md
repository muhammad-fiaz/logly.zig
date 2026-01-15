---
title: OpenTelemetry Integration
description: Complete guide to OpenTelemetry integration in Logly.zig for distributed tracing, metrics, and observability.
head:
  - - meta
    - name: keywords
      content: opentelemetry, otel, distributed tracing, spans, metrics, jaeger, zipkin, observability, zig logging
  - - meta
    - property: og:title
      content: OpenTelemetry Integration | Logly.zig
  - - meta
    - property: og:image
      content: https://muhammad-fiaz.github.io/logly.zig/cover.png
---

# OpenTelemetry Integration

Logly.zig provides comprehensive OpenTelemetry (OTEL) support for distributed tracing, metrics collection, and observability integration with external monitoring systems.

## Overview

OpenTelemetry is a collection of tools, APIs, and SDKs used to instrument, generate, collect, and export telemetry data (metrics, logs, and traces) to help you analyze your software's performance and behavior.

Logly's telemetry module integrates with:
- **utils.zig**: ID generation, time utilities, sampling, JSON escaping
- **async.zig**: Non-blocking span export with ring buffer
- **network.zig**: TCP/UDP/Syslog transport for remote exporters
- **thread_pool.zig**: Parallel span processing for high throughput

## Key Features

| Feature | Description |
|---------|-------------|
| **Multiple Providers** | Jaeger, Zipkin, Datadog, Google Cloud, AWS X-Ray, Azure, and more |
| **W3C Trace Context** | Full W3C traceparent/tracestate header support |
| **W3C Baggage** | Context propagation across service boundaries |
| **Metrics Collection** | Counter, gauge, histogram, and summary metrics |
| **Export Modes** | Sync, async buffer, batch, and network export |
| **Custom Providers** | Build your own exporter with callback interface |
| **Sampling Strategies** | always_on, always_off, trace_id_ratio, parent_based |
| **Thread Safety** | Mutex-protected concurrent span/metric access |

## Getting Started

### Basic Setup

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Disable update checker
    logly.UpdateChecker.setEnabled(false);

    // Configure telemetry with Jaeger
    var config = logly.TelemetryConfig.jaeger();
    config.service_name = "my-service";
    config.service_version = "1.0.0";
    config.environment = "production";

    var telemetry = try logly.Telemetry.init(allocator, config);
    defer telemetry.deinit();

    // Your tracing code here
}
```

### Creating Spans

Spans represent a single unit of work in a distributed trace:

```zig
var span = try telemetry.startSpan("operation_name", .{
    .kind = .server, // .client, .internal, .producer, .consumer
});
defer span.deinit();

// Add attributes
try span.setAttribute("http.method", .{ .string = "POST" });
try span.setAttribute("http.status_code", .{ .integer = 200 });

// Add events (timestamped annotations)
try span.addEvent("validation_completed", null);

// Set final status
span.setStatus(.ok);

// End and export span
span.end();
try telemetry.endSpan(&span);
try telemetry.exportSpans();
```

## Supported Providers

### Built-in Providers

| Provider | Factory Function | Default Endpoint |
|----------|------------------|------------------|
| **Jaeger** | `TelemetryConfig.jaeger()` | `http://localhost:6831` |
| **Zipkin** | `TelemetryConfig.zipkin()` | `http://localhost:9411/api/v2/spans` |
| **Datadog** | `TelemetryConfig.datadog(api_key)` | `http://localhost:8126/v0.3/traces` |
| **Google Cloud** | `TelemetryConfig.googleCloud(project, key)` | `https://cloudtrace.googleapis.com/v2` |
| **Google Analytics 4** | `TelemetryConfig.googleAnalytics(id, secret)` | `https://www.google-analytics.com/mp/collect` |
| **Google Tag Manager** | `TelemetryConfig.googleTagManager(url, key)` | Custom GTM endpoint |
| **AWS X-Ray** | `TelemetryConfig.awsXray(region)` | `http://localhost:2000` |
| **Azure** | `TelemetryConfig.azure(connection_string)` | Application Insights endpoint |
| **OTEL Collector** | `TelemetryConfig.otelCollector(endpoint)` | Custom endpoint |
| **File** | `TelemetryConfig.file(path)` | Local JSONL file |

### Custom Provider

Create your own exporter implementation:

```zig
fn myCustomExporter() anyerror!void {
    // Custom export logic - send to your own backend
    std.debug.print("Custom export triggered\n", .{});
    
    // Example: Send to custom HTTP endpoint
    // const client = try std.http.Client.init(allocator);
    // defer client.deinit();
    // ...
}

var config = logly.TelemetryConfig.custom(&myCustomExporter);
config.service_name = "custom-service";
config.batch_size = 100;
config.batch_timeout_ms = 5000;
```

## W3C Standards

### Trace Context (traceparent)

Generate and parse W3C traceparent headers:

```zig
// Generate header for outgoing request
var span = try telemetry.startSpan("outbound_call", .{});
const traceparent = try telemetry.getTraceparentHeader(&span);
defer allocator.free(traceparent);
// Format: 00-{trace_id}-{span_id}-{flags}
// Example: 00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01

// Parse incoming header
const incoming = "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01";
if (logly.Telemetry.parseTraceparentHeader(incoming)) |ctx| {
    // ctx.trace_id, ctx.span_id, ctx.sampled
}
```

### Baggage

Propagate arbitrary context across services:

```zig
var baggage = logly.Baggage.init(allocator);
defer baggage.deinit();

try baggage.set("user_id", "user-123");
try baggage.set("tenant_id", "tenant-456");

// Serialize for HTTP header
const header = try baggage.toHeaderValue(allocator);
defer allocator.free(header);
// Output: "user_id=user-123,tenant_id=tenant-456"

// Parse incoming baggage
var parsed = try logly.Baggage.fromHeaderValue(allocator, header);
defer parsed.deinit();
```

## Parent-Child Relationships

Create nested spans with automatic context propagation:

```zig
// Parent span (creates new trace)
var parent = try telemetry.startSpan("http_handler", .{ .kind = .server });
defer parent.deinit();

// Child span (inherits trace_id from parent)
var child = try telemetry.startSpanWithContext("database_query", &parent, .{
    .kind = .client,
});
defer child.deinit();

// Grandchild span
var grandchild = try telemetry.startSpanWithContext("cache_lookup", &child, .{
    .kind = .internal,
});
defer grandchild.deinit();

// All spans share the same trace_id
// child.parent_span_id == parent.span_id
// grandchild.parent_span_id == child.span_id
```

## Metrics

### Recording Metrics

```zig
// Full API with options
try telemetry.recordMetric("http.request.duration_ms", 123.45, .{
    .kind = .gauge,
    .unit = "ms",
    .description = "HTTP request duration",
});

// Convenience methods
try telemetry.recordCounter("requests.total", 1.0);
try telemetry.recordGauge("cpu.usage", 45.5);
try telemetry.recordHistogram("response.latency", 123.4);

// Export metrics
try telemetry.exportMetrics();
```

### Metric Kinds

| Kind | Description | Use Case |
|------|-------------|----------|
| `counter` | Monotonically increasing | Request counts, errors |
| `gauge` | Point-in-time value | CPU usage, memory |
| `histogram` | Value distribution | Response times |
| `summary` | Aggregated statistics | Percentiles |

## Sampling Strategies

Control which traces are recorded:

```zig
// Always sample (development)
config.sampling_strategy = .always_on;

// Never sample (disabled)
config.sampling_strategy = .always_off;

// Sample percentage (production)
config.sampling_strategy = .trace_id_ratio;
config.sampling_rate = 0.1; // 10% of traces

// Follow parent's decision (distributed)
config.sampling_strategy = .parent_based;
```

## Callbacks

Monitor telemetry events:

```zig
var config = logly.TelemetryConfig.file("spans.jsonl");

config.on_span_start = struct {
    fn callback(span_id: []const u8, name: []const u8) void {
        std.debug.print("Span started: {s}\n", .{name});
    }
}.callback;

config.on_span_end = struct {
    fn callback(span_id: []const u8, duration_ns: u64) void {
        const ms = @as(f64, @floatFromInt(duration_ns)) / 1_000_000.0;
        std.debug.print("Span ended: {d:.2}ms\n", .{ms});
    }
}.callback;

config.on_metric_recorded = struct {
    fn callback(name: []const u8, value: f64) void {
        std.debug.print("Metric: {s} = {d}\n", .{name, value});
    }
}.callback;

config.on_error = struct {
    fn callback(msg: []const u8) void {
        std.debug.print("Error: {s}\n", .{msg});
    }
}.callback;
```

## Export Statistics

Monitor exporter performance:

```zig
const stats = telemetry.getExporterStats();

std.debug.print("Spans exported: {}\n", .{stats.getSpansExported()});
std.debug.print("Bytes sent: {}\n", .{stats.getBytesExported()});
std.debug.print("Export errors: {}\n", .{stats.getExportErrors()});
std.debug.print("Error rate: {d:.2}%\n", .{stats.getErrorRate() * 100.0});
```

## Runtime Control

Control telemetry behavior at runtime without reinitializing:

### Enable/Disable Telemetry

```zig
// Check current state
if (telemetry.isEnabled()) {
    std.debug.print("Telemetry is active\n", .{});
}

// Disable temporarily
telemetry.setEnabled(false);

// Spans created while disabled are no-ops
const span = try telemetry.startSpan("test", .{});
std.debug.assert(span.isEmpty()); // true

// Re-enable
telemetry.setEnabled(true);
```

### Update Resource Configuration

```zig
// Get current resource
const resource = telemetry.getResource();

// Update at runtime
telemetry.setResource(.{
    .service_name = "updated-service",
    .service_version = "2.0.0",
    .environment = "staging",
    .datacenter = "us-west-2",
});
```

### Reset Statistics

```zig
// Clear all counters
telemetry.resetStats();
```

## Distributed Trace Continuation

Create spans from incoming W3C traceparent headers:

```zig
// Create child span from incoming HTTP request
var span = try telemetry.startSpanFromTraceparent(
    "handle_request",
    request.getHeader("traceparent") orelse "",
    .{ .kind = .server },
);
defer span.deinit();

// If traceparent is invalid, creates a new root span
// If not sampled (flags=00), returns empty span
```

## Best Practices

1. **Always set service identity**: Configure `service_name`, `service_version`, and `environment`
2. **Use sampling in production**: Set `sampling_rate` to 0.01-0.1 for high-throughput services
3. **Propagate context**: Use W3C traceparent/baggage headers for cross-service tracing
4. **Handle span cleanup**: Always use `defer span.deinit()` to avoid memory leaks
5. **Export regularly**: Call `exportSpans()` periodically or at request boundaries
6. **Monitor export stats**: Check `getExporterStats()` to detect export issues

## Configuration Reference

See [API Reference: Telemetry](/api/telemetry) for complete configuration options.

## Examples

See [examples/telemetry.zig](https://github.com/muhammad-fiaz/logly.zig/blob/main/examples/telemetry.zig) for a complete working example.
