//! OpenTelemetry Integration Example
//!
//! Demonstrates comprehensive OpenTelemetry support including:
//! - Span creation and lifecycle management
//! - Trace context propagation (W3C traceparent)
//! - Metrics recording and export
//! - Multiple exporter backends (Jaeger, Zipkin, file, etc.)
//! - Google Analytics and Google Tag Manager integration
//! - Sampling strategies
//! - Resource detection
//! - Custom callbacks
//! - Baggage propagation (W3C Baggage standard)
//! - Batch export with configurable size/timeout
//! - Custom provider implementation
//!
//! Compile: `zig build example-telemetry`
//! Run: `zig build run-telemetry`

const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    // Setup allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Disable update checker for this example
    logly.UpdateChecker.setEnabled(false);

    // Initialize logger
    var logger = try logly.Logger.init(allocator);
    defer logger.deinit();

    try logger.info("=== OpenTelemetry Integration Example ===", null);

    // Example 1: File-based telemetry (development/testing)
    try fileBasedTelemetry(allocator);

    // Example 2: Jaeger integration (production)
    try jaegerTelemetry(allocator);

    // Example 3: Zipkin integration
    try zipkinTelemetry(allocator);

    // Example 4: Google Cloud Trace
    try googleCloudTelemetry(allocator);

    // Example 5: Datadog APM
    try datadogTelemetry(allocator);

    // Example 6: AWS X-Ray
    try awsXRayTelemetry(allocator);

    // Example 7: Azure Application Insights
    try azureTelemetry(allocator);

    // Example 8: Generic OTEL Collector
    try genericOTELTelemetry(allocator);

    // Example 9: Custom callbacks
    try customCallbacksTelemetry(allocator);

    // Example 10: Metrics recording
    try metricsExample(allocator);

    // Example 11: Google Analytics GA4
    try googleAnalyticsTelemetry(allocator);

    // Example 12: Google Tag Manager
    try googleTagManagerTelemetry(allocator);

    // Example 13: W3C Trace Context and Baggage
    try traceContextExample(allocator);

    // Example 14: Parent-child spans
    try parentChildSpansExample(allocator);

    // Example 15: Custom provider
    try customProviderTelemetry(allocator);

    // Example 16: Exporter statistics
    try exporterStatsExample(allocator);

    // Example 17: High-throughput configuration
    try highThroughputExample(allocator);

    try logger.info("=== Example Completed ===", null);
}

/// Example 1: File-based telemetry for development
fn fileBasedTelemetry(allocator: std.mem.Allocator) !void {
    std.debug.print("\n--- Example 1: File-Based Telemetry ---\n", .{});

    var config = logly.TelemetryConfig.file("telemetry_spans.jsonl");
    config.service_name = "example-app";
    config.service_version = "1.0.0";
    config.environment = "development";

    var telemetry = try logly.Telemetry.init(allocator, config);
    defer telemetry.deinit();

    // Create a span
    var span = try telemetry.startSpan("request_processing", .{
        .kind = .server,
    });
    defer span.deinit();
    defer {
        span.end();
        _ = telemetry.endSpan(&span) catch {};
    }

    try span.setAttribute("http.method", logly.SpanAttribute{ .string = "GET" });
    try span.setAttribute("http.url", logly.SpanAttribute{ .string = "/api/users" });
    try span.setAttribute("http.status_code", logly.SpanAttribute{ .integer = 200 });

    try span.addEvent("request_started", null);
    try span.addEvent("database_query", null);
    try span.addEvent("response_sent", null);

    try telemetry.exportSpans();

    std.debug.print("✓ File-based telemetry configured\n", .{});
    std.debug.print("  Spans written to: telemetry_spans.jsonl\n", .{});
}

/// Example 2: Jaeger integration
fn jaegerTelemetry(allocator: std.mem.Allocator) !void {
    std.debug.print("\n--- Example 2: Jaeger Integration ---\n", .{});

    var config = logly.TelemetryConfig.jaeger();
    config.service_name = "user-service";
    config.service_version = "2.1.0";

    var telemetry = try logly.Telemetry.init(allocator, config);
    defer telemetry.deinit();

    var root_span = try telemetry.startSpan("handle_user_request", .{
        .kind = .server,
    });
    defer root_span.deinit();
    defer {
        root_span.end();
        _ = telemetry.endSpan(&root_span) catch {};
    }

    try root_span.setAttribute("user.id", logly.SpanAttribute{ .string = "user-123" });

    try telemetry.exportSpans();

    std.debug.print("✓ Jaeger integration configured\n", .{});
    std.debug.print("  Endpoint: {s}\n", .{config.exporter_endpoint.?});
}

/// Example 3: Zipkin integration
fn zipkinTelemetry(allocator: std.mem.Allocator) !void {
    std.debug.print("\n--- Example 3: Zipkin Integration ---\n", .{});

    var config = logly.TelemetryConfig.zipkin();
    config.service_name = "order-service";

    var telemetry = try logly.Telemetry.init(allocator, config);
    defer telemetry.deinit();

    var span = try telemetry.startSpan("create_order", .{
        .kind = .server,
    });
    defer span.deinit();
    defer {
        span.end();
        _ = telemetry.endSpan(&span) catch {};
    }

    try span.setAttribute("order.id", logly.SpanAttribute{ .string = "order-456" });
    try span.setAttribute("order.amount", logly.SpanAttribute{ .float = 99.99 });

    try telemetry.exportSpans();

    std.debug.print("✓ Zipkin integration configured\n", .{});
    std.debug.print("  Endpoint: {s}\n", .{config.exporter_endpoint.?});
}

/// Example 4: Google Cloud Trace
fn googleCloudTelemetry(allocator: std.mem.Allocator) !void {
    std.debug.print("\n--- Example 4: Google Cloud Trace ---\n", .{});

    var config = logly.TelemetryConfig.googleCloud("my-project", "my-api-key");
    config.service_name = "gcp-service";
    config.region = "us-central1";

    var telemetry = try logly.Telemetry.init(allocator, config);
    defer telemetry.deinit();

    var span = try telemetry.startSpan("cloud_operation", .{});
    defer span.deinit();
    defer {
        span.end();
        _ = telemetry.endSpan(&span) catch {};
    }

    try span.setAttribute("gcp.resource.type", logly.SpanAttribute{ .string = "gae_app" });

    try telemetry.exportSpans();

    std.debug.print("✓ Google Cloud Trace configured\n", .{});
    std.debug.print("  Project: {s}\n", .{config.project_id.?});
}

/// Example 5: Datadog APM
fn datadogTelemetry(allocator: std.mem.Allocator) !void {
    std.debug.print("\n--- Example 5: Datadog APM ---\n", .{});

    var config = logly.TelemetryConfig.datadog("my-datadog-api-key");
    config.service_name = "datadog-service";
    config.environment = "production";

    var telemetry = try logly.Telemetry.init(allocator, config);
    defer telemetry.deinit();

    var span = try telemetry.startSpan("api_request", .{
        .kind = .server,
    });
    defer span.deinit();
    defer {
        span.end();
        _ = telemetry.endSpan(&span) catch {};
    }

    try span.setAttribute("dd.trace_id", logly.SpanAttribute{ .string = span.trace_id });

    try telemetry.exportSpans();

    std.debug.print("✓ Datadog APM configured\n", .{});
    std.debug.print("  Endpoint: {s}\n", .{config.exporter_endpoint.?});
}

/// Example 6: AWS X-Ray
fn awsXRayTelemetry(allocator: std.mem.Allocator) !void {
    std.debug.print("\n--- Example 6: AWS X-Ray ---\n", .{});

    var config = logly.TelemetryConfig.awsXray("us-east-1");
    config.service_name = "aws-lambda-function";
    config.environment = "production";

    var telemetry = try logly.Telemetry.init(allocator, config);
    defer telemetry.deinit();

    var span = try telemetry.startSpan("lambda_handler", .{
        .kind = .server,
    });
    defer span.deinit();
    defer {
        span.end();
        _ = telemetry.endSpan(&span) catch {};
    }

    try span.setAttribute("aws.lambda.function_name", logly.SpanAttribute{ .string = "my-function" });
    try span.setAttribute("aws.region", logly.SpanAttribute{ .string = "us-east-1" });

    try telemetry.exportSpans();

    std.debug.print("✓ AWS X-Ray configured\n", .{});
    std.debug.print("  Region: {s}\n", .{config.region.?});
}

/// Example 7: Azure Application Insights
fn azureTelemetry(allocator: std.mem.Allocator) !void {
    std.debug.print("\n--- Example 7: Azure Application Insights ---\n", .{});

    var config = logly.TelemetryConfig.azure("InstrumentationKey=my-key;IngestionEndpoint=https://...");
    config.service_name = "azure-app-service";
    config.region = "eastus";

    var telemetry = try logly.Telemetry.init(allocator, config);
    defer telemetry.deinit();

    var span = try telemetry.startSpan("azure_operation", .{});
    defer span.deinit();
    defer {
        span.end();
        _ = telemetry.endSpan(&span) catch {};
    }

    try span.setAttribute("azure.resource_group", logly.SpanAttribute{ .string = "my-rg" });

    try telemetry.exportSpans();

    std.debug.print("✓ Azure Application Insights configured\n", .{});
}

/// Example 8: Generic OTEL Collector
fn genericOTELTelemetry(allocator: std.mem.Allocator) !void {
    std.debug.print("\n--- Example 8: Generic OTEL Collector ---\n", .{});

    var config = logly.TelemetryConfig.otelCollector("http://localhost:4317");
    config.service_name = "otel-client";
    config.sampling_strategy = .trace_id_ratio;
    config.sampling_rate = 0.1;

    var telemetry = try logly.Telemetry.init(allocator, config);
    defer telemetry.deinit();

    var span = try telemetry.startSpan("traced_operation", .{});
    defer span.deinit();
    defer {
        span.end();
        _ = telemetry.endSpan(&span) catch {};
    }

    try span.setAttribute("otel.provider", logly.SpanAttribute{ .string = "generic" });

    try telemetry.exportSpans();

    std.debug.print("✓ Generic OTEL Collector configured\n", .{});
    std.debug.print("  Endpoint: {s}\n", .{config.exporter_endpoint.?});
}

/// Example 9: Custom callbacks
fn customCallbacksTelemetry(allocator: std.mem.Allocator) !void {
    std.debug.print("\n--- Example 9: Custom Callbacks ---\n", .{});

    var config = logly.TelemetryConfig.file("telemetry_callbacks.jsonl");

    config.on_span_start = spanStartCallback;
    config.on_span_end = spanEndCallback;
    config.on_metric_recorded = metricRecordedCallback;
    config.on_error = errorCallback;

    var telemetry = try logly.Telemetry.init(allocator, config);
    defer telemetry.deinit();

    var span = try telemetry.startSpan("callback_example", .{});
    defer span.deinit();
    defer {
        span.end();
        _ = telemetry.endSpan(&span) catch {};
    }

    std.debug.print("✓ Custom callbacks registered\n", .{});
}

/// Example 10: Metrics recording
fn metricsExample(allocator: std.mem.Allocator) !void {
    std.debug.print("\n--- Example 10: Metrics Recording ---\n", .{});

    var config = logly.TelemetryConfig.file("telemetry_metrics.jsonl");
    config.metric_format = .json;

    var telemetry = try logly.Telemetry.init(allocator, config);
    defer telemetry.deinit();

    try telemetry.recordMetric("http.request.duration_ms", 123.45, .{
        .kind = .gauge,
        .unit = "ms",
        .description = "HTTP request duration",
    });

    try telemetry.recordMetric("system.cpu.usage", 45.6, .{
        .kind = .gauge,
        .unit = "%",
    });

    try telemetry.recordMetric("process.memory.rss", 1024.0 * 1024.0 * 256.0, .{
        .kind = .gauge,
        .unit = "bytes",
    });

    try telemetry.recordMetric("errors.total", 5.0, .{
        .kind = .counter,
    });

    try telemetry.exportMetrics();

    std.debug.print("✓ Metrics recorded and exported\n", .{});
    std.debug.print("  Metrics: http.request.duration_ms, system.cpu.usage, process.memory.rss, errors.total\n", .{});
}

// Callback functions
fn spanStartCallback(_: []const u8, name: []const u8) void {
    std.debug.print("  [CALLBACK] Span started: {s}\n", .{name});
}

fn spanEndCallback(_: []const u8, duration_ns: u64) void {
    const duration_ms = @as(f64, @floatFromInt(duration_ns)) / 1_000_000.0;
    std.debug.print("  [CALLBACK] Span ended: {d:.2}ms\n", .{duration_ms});
}

fn metricRecordedCallback(name: []const u8, value: f64) void {
    std.debug.print("  [CALLBACK] Metric recorded: {s} = {d}\n", .{ name, value });
}

fn errorCallback(error_msg: []const u8) void {
    std.debug.print("  [CALLBACK] Error: {s}\n", .{error_msg});
}
/// Example 11: Google Analytics GA4
fn googleAnalyticsTelemetry(allocator: std.mem.Allocator) !void {
    std.debug.print("\n--- Example 11: Google Analytics GA4 ---\n", .{});

    // Configure Google Analytics Measurement Protocol
    var config = logly.TelemetryConfig.googleAnalytics("G-XXXXXXXXXX", "api_secret_xxx");
    config.service_name = "analytics-service";

    var telemetry = try logly.Telemetry.init(allocator, config);
    defer telemetry.deinit();

    // Record user engagement as a span
    var span = try telemetry.startSpan("page_view", .{
        .kind = .client,
    });
    defer span.deinit();
    defer {
        span.end();
        _ = telemetry.endSpan(&span) catch {};
    }

    try span.setAttribute("page.url", logly.SpanAttribute{ .string = "/products/item-123" });
    try span.setAttribute("page.title", logly.SpanAttribute{ .string = "Product Details" });
    try span.setAttribute("user.id", logly.SpanAttribute{ .string = "user-456" });

    // Record metrics for analytics
    try telemetry.recordCounter("page_views", 1.0);
    try telemetry.recordGauge("session_duration", 45.5);

    try telemetry.exportSpans();

    std.debug.print("✓ Google Analytics GA4 configured\n", .{});
    std.debug.print("  Measurement ID: {s}\n", .{config.project_id.?});
    std.debug.print("  Batch size: {d}\n", .{config.batch_size});
}

/// Example 12: Google Tag Manager
fn googleTagManagerTelemetry(allocator: std.mem.Allocator) !void {
    std.debug.print("\n--- Example 12: Google Tag Manager ---\n", .{});

    // Configure Google Tag Manager server-side endpoint
    var config = logly.TelemetryConfig.googleTagManager(
        "https://gtm.example.com/collect",
        "gtm-api-key",
    );
    config.service_name = "gtm-service";

    var telemetry = try logly.Telemetry.init(allocator, config);
    defer telemetry.deinit();

    // Track e-commerce event
    var span = try telemetry.startSpan("purchase", .{
        .kind = .producer,
    });
    defer span.deinit();
    defer {
        span.end();
        _ = telemetry.endSpan(&span) catch {};
    }

    try span.setAttribute("transaction.id", logly.SpanAttribute{ .string = "T12345" });
    try span.setAttribute("transaction.revenue", logly.SpanAttribute{ .float = 199.99 });
    try span.setAttribute("currency", logly.SpanAttribute{ .string = "USD" });

    try telemetry.exportSpans();

    std.debug.print("✓ Google Tag Manager configured\n", .{});
    std.debug.print("  Endpoint: {s}\n", .{config.exporter_endpoint.?});
}

/// Example 13: W3C Trace Context and Baggage
fn traceContextExample(allocator: std.mem.Allocator) !void {
    std.debug.print("\n--- Example 13: W3C Trace Context & Baggage ---\n", .{});

    var config = logly.TelemetryConfig.development();
    config.service_name = "context-service";

    var telemetry = try logly.Telemetry.init(allocator, config);
    defer telemetry.deinit();

    // Create a span
    var span = try telemetry.startSpan("distributed_operation", .{
        .kind = .server,
    });
    defer span.deinit();

    // Generate W3C traceparent header for downstream services
    const traceparent = try telemetry.getTraceparentHeader(&span);
    defer allocator.free(traceparent);

    std.debug.print("  Generated traceparent: {s}\n", .{traceparent});

    // Create and populate baggage for context propagation
    var baggage = logly.Baggage.init(allocator);
    defer baggage.deinit();

    try baggage.set("user_id", "user-789");
    try baggage.set("tenant_id", "tenant-abc");
    try baggage.set("request_source", "mobile-app");

    // Generate W3C baggage header
    const baggage_header = try baggage.toHeaderValue(allocator);
    defer allocator.free(baggage_header);

    std.debug.print("  Generated baggage: {s}\n", .{baggage_header});

    // Parse traceparent header (simulating receiving from upstream)
    const parsed = logly.Telemetry.parseTraceparentHeader(traceparent);
    if (parsed) |ctx| {
        std.debug.print("  Parsed trace_id: {s}\n", .{ctx.trace_id});
        std.debug.print("  Parsed span_id: {s}\n", .{ctx.span_id});
        std.debug.print("  Sampled: {}\n", .{ctx.sampled});
    }

    // Parse baggage header
    var parsed_baggage = try logly.Baggage.fromHeaderValue(allocator, "user_id=test,session=abc");
    defer parsed_baggage.deinit();

    span.end();
    try telemetry.endSpan(&span);
    try telemetry.exportSpans();

    std.debug.print("✓ W3C Trace Context and Baggage demonstrated\n", .{});
}

/// Example 14: Parent-child spans with context propagation
fn parentChildSpansExample(allocator: std.mem.Allocator) !void {
    std.debug.print("\n--- Example 14: Parent-Child Spans ---\n", .{});

    var config = logly.TelemetryConfig.development();
    config.service_name = "nested-service";

    var telemetry = try logly.Telemetry.init(allocator, config);
    defer telemetry.deinit();

    // Create parent span
    var parent = try telemetry.startSpan("http_request", .{
        .kind = .server,
    });
    defer parent.deinit();

    try parent.setAttribute("http.method", logly.SpanAttribute{ .string = "POST" });
    try parent.setAttribute("http.url", logly.SpanAttribute{ .string = "/api/orders" });

    // Create child span using helper method
    var child1 = try telemetry.startSpanWithContext("validate_input", &parent, .{
        .kind = .internal,
    });
    defer child1.deinit();
    try child1.addEvent("validation_started", null);
    child1.end();
    try telemetry.endSpan(&child1);

    // Create another child span
    var child2 = try telemetry.startSpanWithContext("database_insert", &parent, .{
        .kind = .client,
    });
    defer child2.deinit();
    try child2.setAttribute("db.system", logly.SpanAttribute{ .string = "postgresql" });
    try child2.setAttribute("db.statement", logly.SpanAttribute{ .string = "INSERT INTO orders..." });
    child2.setStatus(.ok);
    child2.end();
    try telemetry.endSpan(&child2);

    // End parent span
    parent.setStatus(.ok);
    parent.end();
    try telemetry.endSpan(&parent);

    // Get telemetry stats
    const stats = telemetry.getStats();
    std.debug.print("  Total spans created: {d}\n", .{stats.total_spans_created});
    std.debug.print("  Pending spans: {d}\n", .{stats.pending_spans});

    try telemetry.exportSpans();

    std.debug.print("✓ Parent-child spans demonstrated\n", .{});
    std.debug.print("  Parent trace_id: {s}\n", .{parent.trace_id});
}

/// Custom exporter callback function
var custom_export_count: u32 = 0;

fn customExporterCallback() anyerror!void {
    custom_export_count += 1;
    std.debug.print("  [CUSTOM EXPORTER] Export #{d} triggered!\n", .{custom_export_count});
    // In a real implementation, you would:
    // 1. Collect spans/metrics from a buffer
    // 2. Serialize them to your custom format
    // 3. Send to your backend (HTTP, gRPC, etc.)
}

/// Example 15: Custom provider implementation
fn customProviderTelemetry(allocator: std.mem.Allocator) !void {
    std.debug.print("\n--- Example 15: Custom Provider ---\n", .{});

    // Configure custom provider with callback
    var config = logly.TelemetryConfig.custom(&customExporterCallback);
    config.service_name = "custom-backend-service";
    config.service_version = "1.0.0";
    config.batch_size = 50;
    config.batch_timeout_ms = 2000;

    var telemetry = try logly.Telemetry.init(allocator, config);
    defer telemetry.deinit();

    // Create spans that will be exported via custom callback
    var span = try telemetry.startSpan("custom_operation", .{
        .kind = .internal,
    });
    defer span.deinit();

    try span.setAttribute("custom.field", logly.SpanAttribute{ .string = "custom_value" });
    try span.setAttribute("custom.priority", logly.SpanAttribute{ .integer = 1 });

    span.end();
    try telemetry.endSpan(&span);

    // This triggers the custom exporter callback
    try telemetry.exportSpans();

    std.debug.print("✓ Custom provider configured\n", .{});
    std.debug.print("  Provider: custom\n", .{});
    std.debug.print("  Export callback invoked: {d} time(s)\n", .{custom_export_count});
}

/// Example 16: Exporter statistics monitoring
fn exporterStatsExample(allocator: std.mem.Allocator) !void {
    std.debug.print("\n--- Example 16: Exporter Statistics ---\n", .{});

    var config = logly.TelemetryConfig.development();
    config.service_name = "stats-service";

    var telemetry = try logly.Telemetry.init(allocator, config);
    defer telemetry.deinit();

    // Create multiple spans
    var i: u32 = 0;
    while (i < 5) : (i += 1) {
        var span = try telemetry.startSpan("batch_operation", .{});
        defer span.deinit();
        try span.setAttribute("iteration", logly.SpanAttribute{ .integer = @intCast(i) });
        span.end();
        try telemetry.endSpan(&span);
    }

    // Record some metrics
    try telemetry.recordCounter("exports.count", 5.0);
    try telemetry.recordGauge("queue.depth", 100.0);

    // Export spans
    try telemetry.exportSpans();
    try telemetry.exportMetrics();

    // Get exporter statistics
    const stats = telemetry.getExporterStats();
    std.debug.print("  === Exporter Statistics ===\n", .{});
    std.debug.print("  Spans exported: {d}\n", .{stats.getSpansExported()});
    std.debug.print("  Bytes sent: {d}\n", .{stats.getBytesExported()});
    std.debug.print("  Export errors: {d}\n", .{stats.getExportErrors()});
    std.debug.print("  Error rate: {d:.2}%\n", .{stats.getErrorRate() * 100.0});

    // Get telemetry stats
    const telemetry_stats = telemetry.getStats();
    std.debug.print("  === Telemetry Statistics ===\n", .{});
    std.debug.print("  Total spans created: {d}\n", .{telemetry_stats.total_spans_created});
    std.debug.print("  Total spans exported: {d}\n", .{telemetry_stats.total_spans_exported});
    std.debug.print("  Total metrics recorded: {d}\n", .{telemetry_stats.total_metrics_recorded});

    std.debug.print("✓ Exporter statistics demonstrated\n", .{});
}

/// Example 17: High-throughput configuration
fn highThroughputExample(allocator: std.mem.Allocator) !void {
    std.debug.print("\n--- Example 17: High-Throughput Configuration ---\n", .{});

    // Use pre-configured high-throughput settings
    var config = logly.TelemetryConfig.highThroughput();
    config.service_name = "high-volume-service";

    std.debug.print("  Configuration:\n", .{});
    std.debug.print("    Provider: {s}\n", .{@tagName(config.provider)});
    std.debug.print("    Batch size: {d}\n", .{config.batch_size});
    std.debug.print("    Batch timeout: {d}ms\n", .{config.batch_timeout_ms});
    std.debug.print("    Sampling strategy: {s}\n", .{@tagName(config.sampling_strategy)});
    std.debug.print("    Sampling rate: {d:.2}%\n", .{config.sampling_rate * 100.0});

    var telemetry = try logly.Telemetry.init(allocator, config);
    defer telemetry.deinit();

    // Simulate high-throughput span creation
    const start_time = std.time.nanoTimestamp();
    var created: u32 = 0;
    while (created < 100) : (created += 1) {
        var span = try telemetry.startSpan("high_throughput_op", .{});
        defer span.deinit();
        span.end();
        try telemetry.endSpan(&span);
    }
    const elapsed_ns = std.time.nanoTimestamp() - start_time;
    const elapsed_ms = @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000.0;

    try telemetry.exportSpans();

    std.debug.print("  Created {d} spans in {d:.2}ms\n", .{ created, elapsed_ms });
    std.debug.print("  Throughput: {d:.0} spans/sec\n", .{@as(f64, @floatFromInt(created)) / (elapsed_ms / 1000.0)});
    std.debug.print("✓ High-throughput configuration demonstrated\n", .{});
}
