---
title: OpenTelemetry Example
description: Comprehensive examples of OpenTelemetry integration with Logly.zig including spans, metrics, context propagation, and custom providers.
head:
  - - meta
    - name: keywords
      content: opentelemetry, distributed tracing, spans, metrics, jaeger, zipkin, datadog, google analytics, custom provider, zig logging
  - - meta
    - property: og:title
      content: OpenTelemetry Example | Logly.zig
  - - meta
    - property: og:image
      content: https://muhammad-fiaz.github.io/logly.zig/cover.png
---

# OpenTelemetry Example

This example demonstrates comprehensive OpenTelemetry support in Logly.zig, including span creation, metrics recording, context propagation, and multiple backend providers.

## Basic Setup

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Disable update checker for production
    logly.UpdateChecker.setEnabled(false);

    // Configure Jaeger backend
    var config = logly.TelemetryConfig.jaeger();
    config.service_name = "my-service";
    config.service_version = "1.0.0";
    config.environment = "production";

    var telemetry = try logly.Telemetry.init(allocator, config);
    defer telemetry.deinit();

    // Create and use spans
    var span = try telemetry.startSpan("http_request", .{ .kind = .server });
    defer span.deinit();
    
    try span.setAttribute("http.method", .{ .string = "POST" });
    try span.setAttribute("http.status_code", .{ .integer = 200 });
    
    span.end();
    try telemetry.endSpan(&span);
    try telemetry.exportSpans();
}
```

## Provider Configurations

### Jaeger

```zig
var config = logly.TelemetryConfig.jaeger();
config.service_name = "user-service";
config.service_version = "2.1.0";
config.sampling_strategy = .trace_id_ratio;
config.sampling_rate = 0.1; // Sample 10% of traces
```

### Zipkin

```zig
var config = logly.TelemetryConfig.zipkin();
config.service_name = "order-service";
```

### Datadog APM

```zig
var config = logly.TelemetryConfig.datadog("your-api-key");
config.service_name = "payment-service";
config.environment = "production";
```

### Google Cloud Trace

```zig
var config = logly.TelemetryConfig.googleCloud("my-project-id", "my-api-key");
config.service_name = "gcp-service";
config.region = "us-central1";
```

### Google Analytics 4

```zig
var config = logly.TelemetryConfig.googleAnalytics("G-XXXXXXXXXX", "api_secret_xxx");
config.service_name = "analytics-service";
```

### Google Tag Manager

```zig
var config = logly.TelemetryConfig.googleTagManager(
    "https://gtm.example.com/collect",
    "gtm-api-key"
);
config.service_name = "gtm-service";
```

### AWS X-Ray

```zig
var config = logly.TelemetryConfig.awsXray("us-east-1");
config.service_name = "lambda-function";
```

### Azure Application Insights

```zig
var config = logly.TelemetryConfig.azure("InstrumentationKey=xxx;IngestionEndpoint=https://...");
config.service_name = "azure-app";
```

### Generic OTEL Collector

```zig
var config = logly.TelemetryConfig.otelCollector("http://localhost:4317");
config.service_name = "otel-client";
```

### File-Based (Development)

```zig
var config = logly.TelemetryConfig.file("telemetry_spans.jsonl");
config.service_name = "dev-app";
```

### Custom Provider

```zig
fn myCustomExporter() anyerror!void {
    // Custom export logic
    std.debug.print("Exporting spans via custom provider\n", .{});
}

var config = logly.TelemetryConfig.custom(&myCustomExporter);
config.service_name = "custom-service";
```

## Span Operations

### Creating Spans

```zig
var span = try telemetry.startSpan("operation_name", .{
    .kind = .server, // .client, .internal, .producer, .consumer
});
defer span.deinit();

// Add attributes
try span.setAttribute("user.id", .{ .string = "user-123" });
try span.setAttribute("http.status_code", .{ .integer = 200 });
try span.setAttribute("cache.hit", .{ .boolean = true });
try span.setAttribute("response.size", .{ .float = 1024.5 });

// Add events
try span.addEvent("request_received", null);
try span.addEvent("database_queried", null);

// Set status
span.setStatus(.ok); // or .error, .unset

// End span
span.end();
try telemetry.endSpan(&span);
```

### Parent-Child Spans

```zig
// Create parent span
var parent = try telemetry.startSpan("http_request", .{ .kind = .server });
defer parent.deinit();

// Create child span with context propagation
var child = try telemetry.startSpanWithContext("database_query", &parent, .{
    .kind = .client,
});
defer child.deinit();

// child.trace_id == parent.trace_id
// child.parent_span_id == parent.span_id
```

## W3C Trace Context

### Generating Headers

```zig
var span = try telemetry.startSpan("outbound_request", .{});
defer span.deinit();

// Generate traceparent header
const traceparent = try telemetry.getTraceparentHeader(&span);
defer allocator.free(traceparent);

// Use in HTTP request: "traceparent: 00-trace_id-span_id-01"
std.debug.print("traceparent: {s}\n", .{traceparent});
```

### Parsing Headers

```zig
const incoming = "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01";
if (logly.Telemetry.parseTraceparentHeader(incoming)) |ctx| {
    std.debug.print("Trace ID: {s}\n", .{ctx.trace_id});
    std.debug.print("Span ID: {s}\n", .{ctx.span_id});
    std.debug.print("Sampled: {}\n", .{ctx.sampled});
}
```

## W3C Baggage

### Creating and Propagating Baggage

```zig
var baggage = logly.Baggage.init(allocator);
defer baggage.deinit();

try baggage.set("user_id", "user-789");
try baggage.set("tenant_id", "tenant-abc");
try baggage.set("request_source", "mobile-app");

// Generate header for downstream services
const header = try baggage.toHeaderValue(allocator);
defer allocator.free(header);
// header = "user_id=user-789,tenant_id=tenant-abc,request_source=mobile-app"
```

### Parsing Incoming Baggage

```zig
const incoming = "user_id=123,session_id=abc";
var baggage = try logly.Baggage.fromHeaderValue(allocator, incoming);
defer baggage.deinit();

if (baggage.get("user_id")) |uid| {
    std.debug.print("User ID: {s}\n", .{uid});
}
```

## Metrics

### Recording Metrics

```zig
// Counter (cumulative)
try telemetry.recordMetric("requests.total", 1.0, .{ .kind = .counter });

// Gauge (instantaneous)
try telemetry.recordMetric("cpu.usage", 45.2, .{
    .kind = .gauge,
    .unit = "%",
    .description = "CPU usage percentage",
});

// Histogram (distribution)
try telemetry.recordMetric("response.latency", 234.5, .{
    .kind = .histogram,
    .unit = "ms",
});

// Convenience methods
try telemetry.recordCounter("errors.total", 1.0);
try telemetry.recordGauge("memory.used_mb", 512.0);
try telemetry.recordHistogram("latency_ms", 45.2);

// Export metrics
try telemetry.exportMetrics();
```

## Custom Callbacks

```zig
fn onSpanStart(span_id: []const u8, name: []const u8) void {
    std.debug.print("Span started: {s} ({s})\n", .{name, span_id});
}

fn onSpanEnd(span_id: []const u8, duration_ns: u64) void {
    const ms = @as(f64, @floatFromInt(duration_ns)) / 1_000_000.0;
    std.debug.print("Span ended: {d:.2}ms\n", .{ms});
}

fn onMetricRecorded(name: []const u8, value: f64) void {
    std.debug.print("Metric: {s} = {d}\n", .{name, value});
}

fn onError(msg: []const u8) void {
    std.debug.print("Error: {s}\n", .{msg});
}

// Configure callbacks
var config = logly.TelemetryConfig.file("spans.jsonl");
config.on_span_start = onSpanStart;
config.on_span_end = onSpanEnd;
config.on_metric_recorded = onMetricRecorded;
config.on_error = onError;
```

## Exporter Statistics

```zig
const stats = telemetry.getExporterStats();

std.debug.print("Spans exported: {}\n", .{stats.getSpansExported()});
std.debug.print("Bytes sent: {}\n", .{stats.getBytesExported()});
std.debug.print("Export errors: {}\n", .{stats.getExportErrors()});
std.debug.print("Error rate: {d:.2}%\n", .{stats.getErrorRate() * 100.0});
```

## Sampling Strategies

```zig
// Always sample all traces (development)
config.sampling_strategy = .always_on;

// Never sample (disabled)
config.sampling_strategy = .always_off;

// Sample percentage of traces (production)
config.sampling_strategy = .trace_id_ratio;
config.sampling_rate = 0.1; // 10%

// Follow parent decision (distributed systems)
config.sampling_strategy = .parent_based;
```

## High-Throughput Configuration

```zig
var config = logly.TelemetryConfig.highThroughput();
config.service_name = "high-volume-service";
// Pre-configured with:
// - batch_size = 1024
// - batch_timeout_ms = 2000
// - sampling_rate = 0.01 (1%)
```

## Full Example

See [examples/telemetry.zig](https://github.com/muhammad-fiaz/logly.zig/blob/main/examples/telemetry.zig) for a complete working example demonstrating all features.

## Running the Example

```bash
# Build and run
zig build run-telemetry

# Or build only
zig build example-telemetry
```
