# OpenTelemetry API Reference

Complete reference for the OpenTelemetry integration in Logly.

## Overview

Logly provides comprehensive OpenTelemetry (OTEL) support for distributed tracing, metrics collection, and span context propagation. Features include:

- **Multiple Provider Support**: Jaeger, Zipkin, Datadog, Google Cloud Trace, Google Analytics 4, Google Tag Manager, AWS X-Ray, Azure Application Insights, generic OTEL Collector, file-based, and custom implementations
- **Distributed Tracing**: Full W3C Trace Context specification support with parent-child span relationships
- **W3C Baggage**: Context propagation for arbitrary key-value pairs across service boundaries
- **Metrics Collection**: Counter, gauge, histogram, and summary metrics with configurable export formats
- **Network Export**: UDP/TCP/HTTP/gRPC transport protocols for span and metric export
- **Export Modes**: Synchronous, async buffered, batch, and network export modes
- **Exporter Statistics**: Real-time monitoring of export performance with atomic counters
- **Resource Detection**: Automatic detection of service metadata and resource attributes
- **Sampling Strategies**: Four sampling algorithms (always_on, always_off, trace_id_ratio, parent_based)
- **Custom Callbacks**: User-defined handlers for span lifecycle and metric events
- **Thread Safety**: Mutex-protected concurrent access to spans and metrics
- **Utils Integration**: Leverages utils.zig for ID generation, time calculations, and JSON escaping

## Core Types

### Telemetry

Main entry point for OpenTelemetry integration.

```zig
pub const Telemetry = struct {
    allocator: std.mem.Allocator,
    config: TelemetryConfig,
    enabled: bool,
    spans: std.ArrayList(Span),
    completed_spans: std.ArrayList(Span),
    metrics: std.ArrayList(Metric),
    active_span_count: usize,
    completed_span_count: usize,
    metric_count: usize,
    resource: Resource,
    sampler: TelemetrySampler,
    mutex: std.Thread.Mutex,
    total_spans_created: u64,
    total_spans_exported: u64,
    total_metrics_recorded: u64,
    exporter_stats: ExporterStats,
    on_span_start: ?*const fn ([]const u8, []const u8) void,
    on_span_end: ?*const fn ([]const u8, u64) void,
    on_metric_recorded: ?*const fn ([]const u8, f64) void,
    on_error: ?*const fn ([]const u8) void,
    network_socket: ?std.posix.socket_t,
    network_address: ?std.net.Address,
    batch_buffer: std.ArrayList(u8),
    last_batch_export: i64,
    
    pub fn init(allocator: std.mem.Allocator, config: TelemetryConfig) !Telemetry
    pub fn deinit(self: *Telemetry) void
    pub fn startSpan(self: *Telemetry, name: []const u8, options: SpanOptions) !Span
    pub fn startSpanWithContext(self: *Telemetry, name: []const u8, parent: *const Span, opts: SpanOptions) !Span
    pub fn startSpanFromTraceparent(self: *Telemetry, name: []const u8, traceparent: []const u8, opts: SpanOptions) !Span
    pub fn endSpan(self: *Telemetry, span: *Span) !void
    pub fn recordMetric(self: *Telemetry, name: []const u8, value: f64, options: MetricOptions) !void
    pub fn recordCounter(self: *Telemetry, name: []const u8, value: f64) !void
    pub fn recordGauge(self: *Telemetry, name: []const u8, value: f64) !void
    pub fn recordHistogram(self: *Telemetry, name: []const u8, value: f64) !void
    pub fn exportSpans(self: *Telemetry) !void
    pub fn exportMetrics(self: *Telemetry) !void
    pub fn flush(self: *Telemetry) !void
    pub fn getActiveSpanCount(self: *Telemetry) usize
    pub fn getCompletedSpanCount(self: *Telemetry) usize
    pub fn getMetricCount(self: *Telemetry) usize
    pub fn getStats(self: *Telemetry) TelemetryStats
    pub fn getExporterStats(self: *Telemetry) ExporterStats
    pub fn getTraceparentHeader(self: *Telemetry, span: *const Span) ![]const u8
    pub fn parseTraceparentHeader(header: []const u8) ?TraceContext
    pub fn setEnabled(self: *Telemetry, enabled: bool) void
    pub fn isEnabled(self: *Telemetry) bool
    pub fn getResource(self: *Telemetry) Resource
    pub fn setResource(self: *Telemetry, resource: Resource) void
    pub fn resetStats(self: *Telemetry) void
    pub fn findSpanByTraceId(self: *Telemetry, trace_id: []const u8) ?*const Span
};
```

### ExporterStats

Statistics for monitoring export performance.

#### Getter Methods

| Method | Return | Description |
|--------|--------|-------------|
| `getSpansExported()` | `u64` | Get total spans exported |
| `getMetricsExported()` | `u64` | Get total metrics exported |
| `getExportErrors()` | `u64` | Get total export errors |
| `getBytesExported()` | `u64` | Get total bytes exported |
| `getBatchExports()` | `u64` | Get total batch exports |
| `getNetworkExports()` | `u64` | Get total network exports |
| `getLastExportTimeNs()` | `i64` | Get last export time in nanoseconds |
| `getTotalExports()` | `u64` | Get total exports (batch + network) |

#### Boolean Checks

| Method | Return | Description |
|--------|--------|-------------|
| `hasExportedSpans()` | `bool` | Check if any spans have been exported |
| `hasExportedMetrics()` | `bool` | Check if any metrics have been exported |
| `hasErrors()` | `bool` | Check if any export errors have occurred |
| `hasBatchExports()` | `bool` | Check if any batch exports have occurred |
| `hasNetworkExports()` | `bool` | Check if any network exports have occurred |

#### Rate Calculations

| Method | Return | Description |
|--------|--------|-------------|
| `getErrorRate()` | `f64` | Calculate error rate (0.0 - 1.0) |
| `getSuccessRate()` | `f64` | Calculate success rate (0.0 - 1.0) |
| `avgSpansPerBatch()` | `f64` | Calculate average spans per batch export |
| `avgBytesPerSpan()` | `f64` | Calculate average bytes per span |
| `throughputBytesPerSecond(elapsed_seconds)` | `f64` | Calculate throughput (bytes per second) |

#### Reset

| Method | Description |
|--------|-------------|
| `reset()` | Reset all statistics to initial state |

#### Methods

##### `init(allocator, config) -> Telemetry`

Initializes the telemetry system with the specified configuration.

**Parameters:**
- `allocator`: Memory allocator for span/metric storage
- `config`: TelemetryConfig with provider and options

**Returns:** Initialized Telemetry struct

**Example:**
```zig
var config = logly.TelemetryConfig.jaeger();
config.service_name = "my-service";
var telemetry = try logly.Telemetry.init(allocator, config);
defer telemetry.deinit();
```

##### `startSpan(name, options) -> Span`

Creates and starts a new span.

**Parameters:**
- `name`: Human-readable span name
- `options`: SpanOptions struct with kind, parent_span_id, etc.

**Returns:** Active Span struct

**Example:**
```zig
var span = try telemetry.startSpan("request_processing", .{
    .kind = .server,
});
defer {
    span.end();
    _ = telemetry.endSpan(&span) catch {};
}
```

##### `startSpanWithContext(name, parent, options) -> Span`

Creates a child span that inherits trace context from a parent span.

**Parameters:**
- `name`: Human-readable span name
- `parent`: Pointer to the parent Span (inherits trace_id)
- `options`: SpanOptions struct with kind, etc.

**Returns:** Active Span struct with parent context

**Example:**
```zig
var parent_span = try telemetry.startSpan("http_request", .{ .kind = .server });
defer parent_span.deinit();

var child_span = try telemetry.startSpanWithContext("database_query", &parent_span, .{
    .kind = .client,
});
defer child_span.deinit();

// child_span.trace_id == parent_span.trace_id
// child_span.parent_span_id == parent_span.span_id
```

##### `endSpan(span) -> void`

Finalizes and exports a completed span.

**Parameters:**
- `span`: Pointer to the Span to end

**Returns:** void (error set anyerror)

##### `recordMetric(name, value, options) -> void`

Records a metric value.

**Parameters:**
- `name`: Metric name
- `value`: Numeric metric value
- `options`: MetricOptions with kind, unit, description

**Returns:** void (error set anyerror)

**Example:**
```zig
try telemetry.recordMetric("http.request.duration_ms", 123.45, .{
    .kind = .gauge,
    .unit = "ms",
    .description = "HTTP request duration",
});
```

##### `recordCounter(name, value) -> void`

Convenience method to record a counter metric.

**Parameters:**
- `name`: Metric name
- `value`: Counter value (cumulative)

**Example:**
```zig
try telemetry.recordCounter("requests.total", 1.0);
```

##### `recordGauge(name, value) -> void`

Convenience method to record a gauge metric.

**Parameters:**
- `name`: Metric name
- `value`: Instantaneous measurement value

**Example:**
```zig
try telemetry.recordGauge("cpu.usage", 45.5);
```

##### `recordHistogram(name, value) -> void`

Convenience method to record a histogram metric.

**Parameters:**
- `name`: Metric name
- `value`: Value for distribution tracking

**Example:**
```zig
try telemetry.recordHistogram("response.latency_ms", 123.4);
```

##### `getExporterStats() -> ExporterStats`

Returns real-time exporter statistics.

**Returns:** ExporterStats struct with atomic counters

**Example:**
```zig
const stats = telemetry.getExporterStats();
std.debug.print("Spans exported: {}\n", .{stats.getSpansExported()});
std.debug.print("Error rate: {d:.2}%\n", .{stats.getErrorRate() * 100});
```

##### `getTraceparentHeader(span) -> []const u8`

Generates a W3C traceparent header value for distributed tracing.

**Parameters:**
- `span`: Pointer to the Span

**Returns:** W3C traceparent header string (e.g., "00-trace_id-span_id-01")

**Example:**
```zig
const traceparent = try telemetry.getTraceparentHeader(&span);
defer allocator.free(traceparent);
// Use in HTTP header: "traceparent: 00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"
```

##### `parseTraceparentHeader(header) -> ?TraceContext`

Parses a W3C traceparent header to extract trace context.

**Parameters:**
- `header`: W3C traceparent header string

**Returns:** Optional TraceContext struct, or null if invalid

**Example:**
```zig
const ctx = Telemetry.parseTraceparentHeader("00-4bf92f3577b34da6a-00f067aa0ba902b7-01");
if (ctx) |trace_ctx| {
    std.debug.print("Trace ID: {s}, Sampled: {}\n", .{ trace_ctx.trace_id, trace_ctx.sampled });
}
```

##### `exportSpans() -> void`

Flushes and exports all completed spans.

##### `exportMetrics() -> void`

Flushes and exports all recorded metrics.

##### `setEnabled(enabled: bool) -> void`

Enable or disable telemetry at runtime.

**Parameters:**
- `enabled`: Boolean to enable/disable telemetry

**Example:**
```zig
// Disable telemetry temporarily
telemetry.setEnabled(false);

// Re-enable telemetry
telemetry.setEnabled(true);
```

##### `isEnabled() -> bool`

Check if telemetry is currently enabled.

**Returns:** Boolean indicating if telemetry is enabled

##### `getResource() -> Resource`

Get the current resource configuration.

**Returns:** Resource struct with service metadata

##### `setResource(resource: Resource) -> void`

Update resource configuration at runtime.

**Parameters:**
- `resource`: New Resource configuration

**Example:**
```zig
telemetry.setResource(.{
    .service_name = "updated-service",
    .service_version = "2.0.0",
    .environment = "staging",
    .datacenter = "us-west-2",
});
```

##### `resetStats() -> void`

Reset all statistics counters to zero.

##### `findSpanByTraceId(trace_id: []const u8) -> ?*const Span`

Find an active span by trace ID for distributed trace continuation.

**Parameters:**
- `trace_id`: Trace ID to search for

**Returns:** Optional pointer to the Span, or null if not found

##### `startSpanFromTraceparent(name, traceparent, opts) -> Span`

Create a span from an incoming W3C traceparent header for distributed tracing.

**Parameters:**
- `name`: Span name
- `traceparent`: W3C traceparent header string
- `opts`: SpanOptions

**Returns:** New Span with inherited trace context, or root span if header is invalid

**Example:**
```zig
// Create child span from incoming HTTP request header
var span = try telemetry.startSpanFromTraceparent(
    "handle_request",
    request.getHeader("traceparent") orelse "",
    .{ .kind = .server },
);
defer span.deinit();
```

---

### Span

Represents a single unit of work in a trace.

```zig
pub const Span = struct {
    span_id: [32]u8,
    trace_id: [32]u8,
    parent_span_id: ?[32]u8,
    name: []const u8,
    kind: SpanKind,
    status: SpanStatus,
    start_time: i64,
    end_time: ?i64,
    attributes: std.StringHashMap(SpanAttribute),
    events: std.ArrayList(SpanEvent),
    
    pub fn setAttribute(self: *Span, key: []const u8, value: SpanAttribute) !void
    pub fn addEvent(self: *Span, name: []const u8, attributes: ?std.StringHashMap(SpanAttribute)) !void
    pub fn setStatus(self: *Span, status: SpanStatus) void
    pub fn end(self: *Span) void
};
```

#### Fields

- `span_id`: Unique 16-byte identifier (rendered as hex string)
- `trace_id`: Trace context identifier (shared by parent and child spans)
- `parent_span_id`: Optional parent span identifier for relationship tracking
- `name`: Human-readable operation name
- `kind`: SpanKind enum (server, client, internal, producer, consumer)
- `status`: SpanStatus (unset, ok, error)
- `start_time`: Creation timestamp in nanoseconds
- `end_time`: Completion timestamp, set by `end()`
- `attributes`: Key-value metadata (strings, numbers, booleans, arrays)
- `events`: Timestamped events during span lifetime

#### Methods

##### `setAttribute(key, value) -> void`

Adds or updates a span attribute.

**Parameters:**
- `key`: Attribute name
- `value`: SpanAttribute union (string, integer, float, boolean, array)

**Example:**
```zig
try span.setAttribute("http.method", logly.SpanAttribute{ .string = "POST" });
try span.setAttribute("http.status_code", logly.SpanAttribute{ .integer = 200 });
try span.setAttribute("cache.hit", logly.SpanAttribute{ .boolean = true });
```

##### `addEvent(name, attributes) -> void`

Records an event within the span lifecycle.

**Parameters:**
- `name`: Event name
- `attributes`: Optional event-specific attributes

**Example:**
```zig
try span.addEvent("database_query_completed", null);
try span.addEvent("cache_miss", null);
```

##### `setStatus(status) -> void`

Sets the final span status (ok or error).

##### `end() -> void`

Marks span end time. Must be called before `telemetry.endSpan()`.

---

### SpanAttribute

Tagged union for span attribute values.

```zig
pub const SpanAttribute = union(enum) {
    string: []const u8,
    integer: i64,
    float: f64,
    boolean: bool,
    array: []SpanAttribute,
};
```

Supports:
- **string**: Text values
- **integer**: Whole numbers
- **float**: Decimal values
- **boolean**: True/false flags
- **array**: Collections of attributes

---

### Metric

Represents a measured value.

```zig
pub const Metric = struct {
    name: []const u8,
    value: f64,
    kind: MetricKind,
    unit: ?[]const u8,
    description: ?[]const u8,
    timestamp: i64,
    labels: std.StringHashMap([]const u8),
};

pub const MetricKind = enum {
    counter,      // Monotonically increasing value
    gauge,        // Instantaneous measurement
    histogram,    // Distribution of values
    summary,      // Aggregated statistics
};
```

---

### ExporterStats

Real-time statistics for monitoring export performance using atomic counters.

```zig
pub const ExporterStats = struct {
    spans_exported: std.atomic.Value(u64),
    metrics_exported: std.atomic.Value(u64),
    export_errors: std.atomic.Value(u64),
    bytes_sent: std.atomic.Value(u64),
    last_export_time_ns: std.atomic.Value(i64),
    batch_exports: std.atomic.Value(u64),
    network_exports: std.atomic.Value(u64),
};
```

#### Recording Methods

| Method | Description |
|--------|-------------|
| `recordExport(spans, bytes)` | Records a successful export with span count and bytes |
| `recordBatchExport()` | Increments batch export counter |
| `recordNetworkExport()` | Increments network export counter |
| `recordError()` | Increments error counter |
| `recordMetricExport(count)` | Records metric export count |

#### Getter Methods

| Method | Return | Description |
|--------|--------|-------------|
| `getSpansExported()` | `u64` | Get total spans exported |
| `getMetricsExported()` | `u64` | Get total metrics exported |
| `getExportErrors()` | `u64` | Get total export errors |
| `getBytesExported()` | `u64` | Get total bytes sent |
| `getBatchExports()` | `u64` | Get total batch exports |
| `getNetworkExports()` | `u64` | Get total network exports |
| `getLastExportTimeNs()` | `i64` | Get last export timestamp (ns) |
| `getTotalExports()` | `u64` | Get total exports (batch + network) |

#### Boolean Checks

| Method | Return | Description |
|--------|--------|-------------|
| `hasExportedSpans()` | `bool` | Check if any spans have been exported |
| `hasExportedMetrics()` | `bool` | Check if any metrics have been exported |
| `hasErrors()` | `bool` | Check if any errors have occurred |
| `hasBatchExports()` | `bool` | Check if any batch exports have occurred |
| `hasNetworkExports()` | `bool` | Check if any network exports have occurred |

#### Rate Calculations

| Method | Return | Description |
|--------|--------|-------------|
| `getErrorRate()` | `f64` | Calculate error rate (0.0 - 1.0) |
| `getSuccessRate()` | `f64` | Calculate success rate (0.0 - 1.0) |
| `avgSpansPerBatch()` | `f64` | Calculate average spans per batch export |
| `avgBytesPerSpan()` | `f64` | Calculate average bytes per span |
| `throughputBytesPerSecond(elapsed_seconds)` | `f64` | Calculate bytes per second throughput |

#### Reset

| Method | Description |
|--------|-------------|
| `reset()` | Reset all statistics to initial state |

---

### NetworkProtocol

Network protocol for telemetry export.

```zig
pub const NetworkProtocol = enum {
    tcp,      // TCP transport
    udp,      // UDP transport (recommended for high throughput)
    syslog,   // Syslog protocol
    http,     // HTTP/HTTPS transport
    grpc,     // gRPC transport (OTLP native)
};
```

---

### ExportMode

Export mode for spans and metrics.

```zig
pub const ExportMode = enum {
    sync,          // Synchronous export (blocking)
    async_buffer,  // Asynchronous export using ring buffer
    batch,         // Batch export with configurable size
    network,       // Network export (TCP/UDP)
};
```

---

### TraceContext

Trace context for W3C propagation.

```zig
pub const TraceContext = struct {
    trace_id: []const u8,
    span_id: []const u8,
    sampled: bool = true,
};
```

**Example:**
```zig
// Parse incoming traceparent header
const ctx = Telemetry.parseTraceparentHeader("00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01");
if (ctx) |trace_ctx| {
    // Use trace_ctx.trace_id to continue the distributed trace
}
```

---

### Baggage

W3C Baggage for context propagation across service boundaries.

```zig
pub const Baggage = struct {
    allocator: std.mem.Allocator,
    items: std.StringHashMap([]const u8),
    
    pub fn init(allocator: std.mem.Allocator) Baggage
    pub fn deinit(self: *Baggage) void
    pub fn set(self: *Baggage, key: []const u8, value: []const u8) !void
    pub fn get(self: *Baggage, key: []const u8) ?[]const u8
    pub fn remove(self: *Baggage, key: []const u8) void
    pub fn toHeaderValue(self: *Baggage, allocator: std.mem.Allocator) ![]const u8
    pub fn fromHeaderValue(allocator: std.mem.Allocator, header: []const u8) !Baggage
    pub fn count(self: *Baggage) usize
    pub fn isEmpty(self: *Baggage) bool
    pub fn clear(self: *Baggage) void
    pub fn contains(self: *Baggage, key: []const u8) bool
};
```

#### Methods

##### `set(key, value) -> void`

Sets a baggage item.

**Example:**
```zig
var baggage = logly.Baggage.init(allocator);
defer baggage.deinit();
try baggage.set("user.id", "user123");
try baggage.set("session.id", "sess456");
```

##### `get(key) -> ?[]const u8`

Retrieves a baggage item value.

**Example:**
```zig
if (baggage.get("user.id")) |user_id| {
    std.debug.print("User: {s}\n", .{user_id});
}
```

##### `toHeaderValue(allocator) -> []const u8`

Formats baggage as W3C baggage header value.

**Example:**
```zig
const header = try baggage.toHeaderValue(allocator);
defer allocator.free(header);
// header = "user.id=user123,session.id=sess456"
```

##### `fromHeaderValue(allocator, header) -> Baggage`

Parses W3C baggage header value.

**Example:**
```zig
var baggage = try logly.Baggage.fromHeaderValue(allocator, "user.id=user123,session.id=sess456");
defer baggage.deinit();
```

---

### Resource

Service and environment metadata.

```zig
pub const Resource = struct {
    service_name: []const u8,
    service_version: ?[]const u8,
    environment: ?[]const u8,
    attributes: std.StringHashMap([]const u8),
};
```

---

### TelemetrySampler

Controls trace sampling decision.

```zig
pub const TelemetrySampler = struct {
    strategy: SamplingStrategy,
    sampling_rate: f64,
    
    pub fn shouldSample(self: TelemetrySampler, trace_id: []const u8) bool
};

pub const SamplingStrategy = enum {
    always_on,        // Sample all traces
    always_off,       // Sample no traces
    trace_id_ratio,   // Sample based on trace ID hash
    parent_based,     // Follow parent span decision
};
```

#### Strategies

- **always_on**: All traces sampled (high overhead, development only)
- **always_off**: No traces sampled (zero overhead)
- **trace_id_ratio**: Statistically sample X% of traces (configurable via `sampling_rate`)
- **parent_based**: Inherit parent span's sampling decision (distributed tracing)

---

## TelemetryConfig

Configuration structure for OpenTelemetry initialization.

```zig
pub const TelemetryConfig = struct {
    enabled: bool = false,
    provider: Provider = .none,
    exporter_endpoint: ?[]const u8 = null,
    api_key: ?[]const u8 = null,
    connection_string: ?[]const u8 = null,
    project_id: ?[]const u8 = null,
    region: ?[]const u8 = null,
    exporter_file_path: ?[]const u8 = null,
    batch_size: usize = 256,
    batch_timeout_ms: u64 = 5000,
    sampling_strategy: SamplingStrategy = .always_on,
    sampling_rate: f64 = 1.0,
    service_name: ?[]const u8 = null,
    service_version: ?[]const u8 = null,
    environment: ?[]const u8 = null,
    datacenter: ?[]const u8 = null,
    span_processor_type: SpanProcessorType = .simple,
    metric_format: MetricFormat = .otlp,
    compress_exports: bool = false,
    custom_exporter_fn: ?*const fn () anyerror!void = null,
    on_span_start: ?*const fn ([]const u8, []const u8) void = null,
    on_span_end: ?*const fn ([]const u8, u64) void = null,
    on_metric_recorded: ?*const fn ([]const u8, f64) void = null,
    on_error: ?*const fn ([]const u8) void = null,
    auto_context_propagation: bool = true,
    trace_header: []const u8 = "traceparent",
    baggage_header: []const u8 = "baggage",
};

pub const Provider = enum {
    none,
    jaeger,
    zipkin,
    datadog,
    google_cloud,
    google_analytics,   // Google Analytics 4 (Measurement Protocol)
    google_tag_manager, // Google Tag Manager (Server-Side)
    aws_xray,
    azure,
    generic,
    file,
    custom,
};

pub const SamplingStrategy = enum {
    always_on,
    always_off,
    trace_id_ratio,
    parent_based,
};

pub const MetricFormat = enum {
    otlp,
    prometheus,
    json,
};

pub const SpanProcessorType = enum {
    simple,
    batch,
};
```

### Configuration Presets

Logly provides factory functions for common deployment scenarios:

#### `TelemetryConfig.jaeger() -> TelemetryConfig`

Jaeger distributed tracing backend.

**Default Settings:**
- Endpoint: `http://localhost:6831` (Jaeger Agent UDP)
- Batch Size: 256
- Processor: Batch
- Sampling: trace_id_ratio at 10%

**Example:**
```zig
var config = logly.TelemetryConfig.jaeger();
config.service_name = "user-service";
```

#### `TelemetryConfig.zipkin() -> TelemetryConfig`

Zipkin distributed tracing.

**Default Settings:**
- Endpoint: `http://localhost:9411/api/v2/spans`
- Format: JSON
- Batch Size: 512

#### `TelemetryConfig.datadog(api_key: []const u8) -> TelemetryConfig`

Datadog APM integration.

**Parameters:**
- `api_key`: Datadog API key (required)

**Example:**
```zig
var config = logly.TelemetryConfig.datadog("dd_api_key_here");
config.environment = "production";
```

#### `TelemetryConfig.googleCloud(project_id: []const u8, api_key: []const u8) -> TelemetryConfig`

Google Cloud Trace integration.

**Parameters:**
- `project_id`: GCP project ID
- `api_key`: GCP API key

#### `TelemetryConfig.googleAnalytics(measurement_id: []const u8, api_secret: []const u8) -> TelemetryConfig`

Google Analytics 4 (GA4) Measurement Protocol integration.

**Parameters:**
- `measurement_id`: GA4 Measurement ID (e.g., "G-XXXXXXXXXX")
- `api_secret`: GA4 Measurement Protocol API secret

**Default Settings:**
- Endpoint: `https://www.google-analytics.com/mp/collect`
- Batch Size: 25 (GA4 limit per request)

**Example:**
```zig
var config = logly.TelemetryConfig.googleAnalytics("G-ABC123XYZ", "my_api_secret");
config.service_name = "analytics-service";
```

#### `TelemetryConfig.googleTagManager(container_url: []const u8, api_key: ?[]const u8) -> TelemetryConfig`

Google Tag Manager Server-Side container integration.

**Parameters:**
- `container_url`: Server-side GTM container URL
- `api_key`: Optional API key for authentication (can be null)

**Example:**
```zig
// With API key
var config = logly.TelemetryConfig.googleTagManager("https://gtm.example.com/collect", "my_api_key");

// Without API key
var config = logly.TelemetryConfig.googleTagManager("https://gtm.example.com/collect", null);
```

#### `TelemetryConfig.awsXray(region: []const u8) -> TelemetryConfig`

AWS X-Ray integration.

**Parameters:**
- `region`: AWS region (e.g., "us-east-1")

#### `TelemetryConfig.azure(connection_string: []const u8) -> TelemetryConfig`

Azure Application Insights integration.

**Parameters:**
- `connection_string`: Application Insights connection string

#### `TelemetryConfig.otelCollector(endpoint: []const u8) -> TelemetryConfig`

Generic OpenTelemetry Collector endpoint.

**Parameters:**
- `endpoint`: Collector gRPC endpoint (e.g., `http://localhost:4317`)

#### `TelemetryConfig.file(path: []const u8) -> TelemetryConfig`

File-based exporter (development/testing).

**Parameters:**
- `path`: Output file path (JSON Lines format)

**Example:**
```zig
var config = logly.TelemetryConfig.file("traces.jsonl");
```

#### `TelemetryConfig.custom(exporter_fn: *const fn () anyerror!void) -> TelemetryConfig`

Custom exporter implementation using a callback function.

**Parameters:**
- `exporter_fn`: Pointer to custom exporter callback function

**Example:**
```zig
fn myCustomExporter() anyerror!void {
    // Custom export logic here
    std.debug.print("Custom export triggered\n", .{});
}

var config = logly.TelemetryConfig.custom(&myCustomExporter);
config.service_name = "custom-service";
```

#### `TelemetryConfig.highThroughput() -> TelemetryConfig`

Pre-configured for high-throughput scenarios.

**Settings:**
- Provider: Jaeger
- Endpoint: `http://localhost:6831`
- Batch Size: 1024
- Batch Timeout: 2000ms
- Sampling: trace_id_ratio at 1%

#### `TelemetryConfig.development() -> TelemetryConfig`

Pre-configured for development.

**Settings:**
- Provider: File-based
- Output: `telemetry_spans.jsonl`
- Processor: Simple (immediate export)
- Sampling: always_on

---

## Usage Examples

### Basic Span Creation

```zig
var config = logly.TelemetryConfig.jaeger();
config.service_name = "my-app";

var telemetry = try logly.Telemetry.init(allocator, config);
defer telemetry.deinit();

var span = try telemetry.startSpan("process_request", .{
    .kind = .server,
});
defer {
    span.end();
    _ = telemetry.endSpan(&span) catch {};
}

try span.setAttribute("request.id", logly.SpanAttribute{ .string = "req-123" });
try span.addEvent("processing_started", null);
```

### Distributed Tracing

```zig
// Parent span
var parent = try telemetry.startSpan("http_request", .{});
defer {
    parent.end();
    _ = telemetry.endSpan(&parent) catch {};
}

// Child span (automatic trace propagation)
var child = try telemetry.startSpan("database_query", .{
    .parent_span_id = parent.span_id,
    .kind = .client,
});
defer {
    child.end();
    _ = telemetry.endSpan(&child) catch {};
}
```

### W3C Trace Context Propagation

```zig
// Generate traceparent header for outgoing request
var span = try telemetry.startSpan("outbound_call", .{});
defer span.deinit();

const traceparent = try telemetry.getTraceparentHeader(&span);
defer allocator.free(traceparent);
// Add to HTTP request: "traceparent: 00-trace_id-span_id-01"

// Parse incoming traceparent header
const incoming = "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01";
if (logly.Telemetry.parseTraceparentHeader(incoming)) |ctx| {
    std.debug.print("Continuing trace: {s}\n", .{ctx.trace_id});
}
```

### Baggage Context Propagation

```zig
// Create baggage for cross-service context
var baggage = logly.Baggage.init(allocator);
defer baggage.deinit();

try baggage.set("user.id", "user123");
try baggage.set("tenant.id", "tenant456");
try baggage.set("request.id", "req789");

// Convert to HTTP header for outgoing request
const header = try baggage.toHeaderValue(allocator);
defer allocator.free(header);
// header = "user.id=user123,tenant.id=tenant456,request.id=req789"

// Parse incoming baggage header
const incoming_baggage = "user.id=user123,session.id=sess456";
var parsed = try logly.Baggage.fromHeaderValue(allocator, incoming_baggage);
defer parsed.deinit();

if (parsed.get("user.id")) |uid| {
    std.debug.print("User ID from upstream: {s}\n", .{uid});
}
```

### Parent-Child Spans with Context

```zig
// Create parent span (inherits new trace)
var root_span = try telemetry.startSpan("http_handler", .{ .kind = .server });
defer root_span.deinit();

// Create child span using context helper (inherits trace_id, sets parent_span_id)
var db_span = try telemetry.startSpanWithContext("database_query", &root_span, .{ .kind = .client });
defer db_span.deinit();

// Create grandchild span
var cache_span = try telemetry.startSpanWithContext("cache_lookup", &db_span, .{ .kind = .internal });
defer cache_span.deinit();

// All spans share the same trace_id but have proper parent relationships
```

### Metrics Collection

```zig
// Counter (cumulative)
try telemetry.recordMetric("errors.total", 1.0, .{
    .kind = .counter,
});

// Gauge (instantaneous)
try telemetry.recordMetric("cpu.usage", 45.2, .{
    .kind = .gauge,
    .unit = "%",
});

// Histogram (distribution)
try telemetry.recordMetric("response_time", 234.5, .{
    .kind = .histogram,
    .unit = "ms",
});

// Convenience methods
try telemetry.recordCounter("requests.total", 1.0);
try telemetry.recordGauge("memory.used_mb", 512.0);
try telemetry.recordHistogram("latency_ms", 45.2);
```

### Exporter Statistics

```zig
// Monitor export performance in real-time
const stats = telemetry.getExporterStats();

std.debug.print("=== Export Statistics ===\n", .{});
std.debug.print("Spans exported: {}\n", .{stats.getSpansExported()});
std.debug.print("Bytes sent: {}\n", .{stats.getBytesExported()});
std.debug.print("Export errors: {}\n", .{stats.getExportErrors()});
std.debug.print("Error rate: {d:.2}%\n", .{stats.getErrorRate() * 100.0});
```

### Custom Callbacks

```zig
var config = logly.TelemetryConfig.file("traces.jsonl");
config.on_span_start = onSpanStart;
config.on_span_end = onSpanEnd;
config.on_error = onTelemetryError;

var telemetry = try logly.Telemetry.init(allocator, config);

fn onSpanStart(span_id: []const u8, name: []const u8) void {
    std.debug.print("Span started: {s}\n", .{name});
}

fn onSpanEnd(span_id: []const u8, duration_ns: u64) void {
    const ms = @as(f64, @floatFromInt(duration_ns)) / 1_000_000.0;
    std.debug.print("Span ended: {d}ms\n", .{ms});
}

fn onTelemetryError(error_msg: []const u8) void {
    std.debug.print("Telemetry error: {s}\n", .{error_msg});
}
```

### Sampling Strategies

```zig
// Trace all requests (development)
var config = logly.TelemetryConfig.development();

// Sample 10% of traces (production)
var config = logly.TelemetryConfig.highThroughput();
config.sampling_rate = 0.1;

// Intelligent sampling based on parent
config.sampling_strategy = .parent_based;
```

---

## Disabling Update Checker

When using Logly in production or testing, you may want to disable the automatic update checker. This can be done globally for your entire project:

```zig
const logly = @import("logly");

pub fn main() !void {
    // Disable update checker at the start of your application
    // This affects ALL subsequent logger initializations in the project
    logly.UpdateChecker.setEnabled(false);

    // Now create loggers - none will perform update checks
    var logger = try logly.Logger.init(.{ .allocator = allocator });
    defer logger.deinit();

    // ... your application code
}
```

**Note:** Once disabled with `setEnabled(false)`, the update checker remains disabled for all subsequent logger imports and initializations within the same process. This is a project-wide setting.

---

## Thread Safety

All Telemetry operations are thread-safe:

- Span creation/completion protected by `spans_mutex`
- Metric recording protected by `metrics_mutex`
- Atomic operations for statistics counters
- Safe concurrent access from multiple threads

```zig
// Safe from multiple threads
var span = try telemetry.startSpan("concurrent_operation", .{});
defer {
    span.end();
    _ = telemetry.endSpan(&span) catch {};
}
```

---

## Error Handling

The Telemetry API uses Zig's error union pattern:

```zig
var span = try telemetry.startSpan("risky_operation", .{}) catch |err| {
    std.debug.print("Failed to start span: {}\n", .{err});
    return err;
};
```

Common errors:
- `OutOfMemory`: Span allocation failed
- `InvalidArgument`: Invalid configuration or span parameters
- `ExportFailed`: Exporter connection or serialization error

---

## Performance Considerations

1. **Sampling**: Use `trace_id_ratio` strategy for production to reduce overhead
2. **Batch Size**: Increase batch_size for high-throughput scenarios
3. **Metrics Granularity**: Avoid recording high-cardinality metrics
4. **Memory**: Completed spans stored in ArrayList; consider periodic clearing for long-running processes

---

## Compatibility

- Zig: 0.15.2+
- OpenTelemetry: Specification 1.0+
- Platforms: Linux, macOS, Windows (x86_64, aarch64, x86)

---

## See Also

- [Span Attributes Guide](./span-attributes.md)
- [Metrics API](./metrics.md)
- [Provider Configuration](./providers.md)
- [Examples](../examples/telemetry.zig)
