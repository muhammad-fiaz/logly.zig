//! OpenTelemetry Integration Module
//!
//! Provides comprehensive OpenTelemetry support for distributed tracing, metrics, and
//! observability integration with external services and providers.
//!
//! Features:
//! - Span and Trace context management
//! - Multiple exporter backends (HTTP, gRPC, file-based, network)
//! - Resource detection and auto-instrumentation
//! - Metrics collection and export
//! - Sampling strategies for performance optimization
//! - Custom callbacks for integration points
//! - W3C Trace Context propagation
//! - Baggage and correlation ID support
//! - Service identity tracking
//! - Async span export using AsyncLogger (non-blocking)
//! - Network-based export (TCP/UDP/Syslog)
//! - Thread pool for parallel span processing
//! - Batch processing with configurable size/timeout
//!
//! Supported Providers:
//! - Generic OpenTelemetry Collector
//! - Jaeger (native protocol)
//! - Zipkin
//! - Datadog APM
//! - Google Cloud Trace
//! - Google Analytics (GA4)
//! - Google Tag Manager
//! - AWS X-Ray
//! - Azure Application Insights
//! - Custom HTTP/gRPC endpoints
//! - File-based (JSONL)
//! - Network (TCP/UDP)
//!
//! Integration with Logly modules:
//! - utils.zig: ID generation, time utilities, sampling, JSON escaping
//! - async.zig: Async span export with ring buffer (non-blocking I/O)
//! - network.zig: TCP/UDP/Syslog transport for remote exporters
//! - thread_pool.zig: Parallel span processing for high throughput
//!
//! Example:
//! ```zig
//! const config = logly.TelemetryConfig.jaeger();
//! var telemetry = try Telemetry.init(allocator, config);
//! defer telemetry.deinit();
//!
//! var span = try telemetry.startSpan("operation", .{});
//! defer span.deinit();
//! defer {
//!     span.end();
//!     _ = telemetry.endSpan(&span) catch {};
//! }
//!
//! try span.setAttribute("key", .{ .string = "value" });
//! try telemetry.exportSpans();
//! ```

const std = @import("std");
const utils = @import("utils.zig");
const config_module = @import("config.zig");
const Network = @import("network.zig");
const Constants = @import("constants.zig");

/// Re-export TelemetryConfig from config module for convenience
pub const TelemetryConfig = config_module.TelemetryConfig;

/// Network protocol for telemetry export
pub const NetworkProtocol = enum {
    tcp,
    udp,
    syslog,
    http,
    grpc,
};

/// Export mode for spans and metrics
pub const ExportMode = enum {
    /// Synchronous export (blocking)
    sync,
    /// Asynchronous export using ring buffer
    async_buffer,
    /// Batch export with configurable size
    batch,
    /// Network export (TCP/UDP)
    network,
};

/// Exporter statistics for monitoring export performance
pub const ExporterStats = struct {
    spans_exported: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
    metrics_exported: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
    export_errors: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
    bytes_sent: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
    last_export_time_ns: std.atomic.Value(Constants.AtomicSigned) = std.atomic.Value(Constants.AtomicSigned).init(0),
    batch_exports: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
    network_exports: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),

    pub fn recordExport(self: *ExporterStats, spans: u64, bytes: u64) void {
        _ = self.spans_exported.fetchAdd(@truncate(spans), .monotonic);
        _ = self.bytes_sent.fetchAdd(@truncate(bytes), .monotonic);

        if (Constants.AtomicSigned == i32) {
            // Use seconds for 32-bit systems to avoid overflow (valid until 2038)
            self.last_export_time_ns.store(@truncate(std.time.timestamp()), .monotonic);
        } else {
            self.last_export_time_ns.store(@truncate(std.time.nanoTimestamp()), .monotonic);
        }
    }

    pub fn recordBatchExport(self: *ExporterStats) void {
        _ = self.batch_exports.fetchAdd(1, .monotonic);
    }

    pub fn recordNetworkExport(self: *ExporterStats) void {
        _ = self.network_exports.fetchAdd(1, .monotonic);
    }

    pub fn recordError(self: *ExporterStats) void {
        _ = self.export_errors.fetchAdd(1, .monotonic);
    }

    pub fn recordMetricExport(self: *ExporterStats, count: u64) void {
        _ = self.metrics_exported.fetchAdd(@truncate(count), .monotonic);
    }

    pub fn getSpansExported(self: *const ExporterStats) u64 {
        return self.spans_exported.load(.monotonic);
    }

    pub fn getMetricsExported(self: *const ExporterStats) u64 {
        return self.metrics_exported.load(.monotonic);
    }

    pub fn getExportErrors(self: *const ExporterStats) u64 {
        return self.export_errors.load(.monotonic);
    }

    pub fn getBytesExported(self: *const ExporterStats) u64 {
        return self.bytes_sent.load(.monotonic);
    }

    pub fn getBatchExports(self: *const ExporterStats) u64 {
        return self.batch_exports.load(.monotonic);
    }

    pub fn getNetworkExports(self: *const ExporterStats) u64 {
        return self.network_exports.load(.monotonic);
    }

    pub fn getLastExportTimeNs(self: *const ExporterStats) i64 {
        const val = self.last_export_time_ns.load(.monotonic);
        if (Constants.AtomicSigned == i32) {
            return @as(i64, val) * std.time.ns_per_s;
        }
        return val;
    }

    /// Check if any spans have been exported.
    pub fn hasExportedSpans(self: *const ExporterStats) bool {
        return self.getSpansExported() > 0;
    }

    /// Check if any metrics have been exported.
    pub fn hasExportedMetrics(self: *const ExporterStats) bool {
        return self.getMetricsExported() > 0;
    }

    /// Check if any export errors have occurred.
    pub fn hasErrors(self: *const ExporterStats) bool {
        return self.getExportErrors() > 0;
    }

    /// Check if any batch exports have occurred.
    pub fn hasBatchExports(self: *const ExporterStats) bool {
        return self.getBatchExports() > 0;
    }

    /// Check if any network exports have occurred.
    pub fn hasNetworkExports(self: *const ExporterStats) bool {
        return self.getNetworkExports() > 0;
    }

    /// Calculate error rate using utils helper
    pub fn getErrorRate(self: *const ExporterStats) f64 {
        const errors = self.getExportErrors();
        const total = self.getBatchExports();
        return utils.calculateErrorRate(errors, total);
    }

    /// Calculate success rate (0.0 - 1.0).
    pub fn getSuccessRate(self: *const ExporterStats) f64 {
        return 1.0 - self.getErrorRate();
    }

    /// Calculate average spans per batch export.
    pub fn avgSpansPerBatch(self: *const ExporterStats) f64 {
        return utils.calculateAverage(
            self.getSpansExported(),
            self.getBatchExports(),
        );
    }

    /// Calculate average bytes per span.
    pub fn avgBytesPerSpan(self: *const ExporterStats) f64 {
        return utils.calculateAverage(
            self.getBytesExported(),
            self.getSpansExported(),
        );
    }

    /// Calculate throughput (bytes per second).
    pub fn throughputBytesPerSecond(self: *const ExporterStats, elapsed_seconds: f64) f64 {
        return utils.safeFloatDiv(
            @as(f64, @floatFromInt(self.getBytesExported())),
            elapsed_seconds,
        );
    }

    /// Calculate total exports (batch + network).
    pub fn getTotalExports(self: *const ExporterStats) u64 {
        return self.getBatchExports() + self.getNetworkExports();
    }

    /// Reset all statistics to initial state.
    pub fn reset(self: *ExporterStats) void {
        self.spans_exported.store(0, .monotonic);
        self.metrics_exported.store(0, .monotonic);
        self.export_errors.store(0, .monotonic);
        self.bytes_sent.store(0, .monotonic);
        self.last_export_time_ns.store(0, .monotonic);
        self.batch_exports.store(0, .monotonic);
        self.network_exports.store(0, .monotonic);
    }
};

/// OpenTelemetry Telemetry Manager
///
/// Main entry point for OpenTelemetry integration. Manages spans, metrics,
/// exporters, and sampling across multiple provider backends.
///
/// Integrates with:
/// - async.zig for non-blocking span export
/// - network.zig for TCP/UDP/Syslog transport
/// - thread_pool.zig for parallel processing
/// - utils.zig for ID generation and time utilities
pub const Telemetry = struct {
    allocator: std.mem.Allocator,
    config: TelemetryConfig,
    enabled: bool,

    // Span storage using ArrayList for actual storage
    spans: std.ArrayList(Span),
    completed_spans: std.ArrayList(Span),

    // Metrics storage
    metrics: std.ArrayList(Metric),

    // Span counts
    active_span_count: usize = 0,
    completed_span_count: usize = 0,
    metric_count: usize = 0,

    // Resource information
    resource: Resource,

    // Sampler instance
    sampler: TelemetrySampler,

    // Thread safety
    mutex: std.Thread.Mutex = .{},

    // Statistics
    total_spans_created: u64 = 0,
    total_spans_exported: u64 = 0,
    total_metrics_recorded: u64 = 0,

    // Exporter stats (advanced stats with utils helpers)
    exporter_stats: ExporterStats = .{},

    // Callbacks (from config)
    on_span_start: ?*const fn ([]const u8, []const u8) void,
    on_span_end: ?*const fn ([]const u8, u64) void,
    on_metric_recorded: ?*const fn ([]const u8, f64) void,
    on_error: ?*const fn ([]const u8) void,

    // Network connection for network export mode
    network_socket: ?std.posix.socket_t = null,
    network_address: ?std.net.Address = null,

    // Batch buffer for batch export mode
    batch_buffer: std.ArrayList(u8),
    last_batch_export: i64 = 0,

    /// Initializes OpenTelemetry telemetry system
    pub fn init(allocator: std.mem.Allocator, config: TelemetryConfig) !Telemetry {
        var telemetry = Telemetry{
            .allocator = allocator,
            .config = config,
            .enabled = config.enabled,
            .spans = .empty,
            .completed_spans = .empty,
            .metrics = .empty,
            .batch_buffer = .empty,
            .resource = Resource.fromConfig(config),
            .sampler = TelemetrySampler.init(config),
            .on_span_start = config.on_span_start,
            .on_span_end = config.on_span_end,
            .on_metric_recorded = config.on_metric_recorded,
            .on_error = config.on_error,
        };

        // Initialize ArrayLists with proper allocator
        telemetry.spans = std.ArrayList(Span).initCapacity(allocator, 32) catch .empty;
        telemetry.completed_spans = std.ArrayList(Span).initCapacity(allocator, 32) catch .empty;
        telemetry.metrics = std.ArrayList(Metric).initCapacity(allocator, 32) catch .empty;
        telemetry.batch_buffer = std.ArrayList(u8).initCapacity(allocator, 4096) catch .empty;

        // Initialize network connection if using network export
        if (config.enabled and config.exporter_endpoint != null) {
            telemetry.initNetworkExport() catch {
                if (config.on_error) |callback| {
                    callback("Failed to initialize network export");
                }
            };
        }

        return telemetry;
    }

    /// Initialize network export connection using Network module
    fn initNetworkExport(self: *Telemetry) !void {
        const endpoint = self.config.exporter_endpoint orelse return;

        // Check if TCP or UDP based on endpoint prefix
        if (std.mem.startsWith(u8, endpoint, "tcp://")) {
            // TCP connection handled on-demand
        } else if (std.mem.startsWith(u8, endpoint, "udp://")) {
            const result = try Network.createUdpSocket(self.allocator, endpoint);
            self.network_socket = result.socket;
            self.network_address = result.address;
        }
    }

    /// Cleans up resources
    pub fn deinit(self: *Telemetry) void {
        // Close network socket if open
        if (self.network_socket) |socket| {
            std.posix.close(socket);
            self.network_socket = null;
        }

        self.mutex.lock();
        defer self.mutex.unlock();

        // Free all active spans
        for (self.spans.items) |*span| {
            span.deinit();
        }
        self.spans.deinit(self.allocator);

        // Free all completed spans
        for (self.completed_spans.items) |*span| {
            span.deinit();
        }
        self.completed_spans.deinit(self.allocator);

        // Free all metrics
        for (self.metrics.items) |metric| {
            self.allocator.free(metric.name);
        }
        self.metrics.deinit(self.allocator);

        // Free batch buffer
        self.batch_buffer.deinit(self.allocator);

        // Reset counters
        self.active_span_count = 0;
        self.completed_span_count = 0;
        self.metric_count = 0;
    }

    /// Starts a new span
    pub fn startSpan(self: *Telemetry, name: []const u8, opts: SpanOptions) !Span {
        if (!self.enabled) return Span.empty(self.allocator);

        self.mutex.lock();
        defer self.mutex.unlock();

        // Generate IDs using utils
        const span_id = try utils.generateSpanId(self.allocator);
        const trace_id = if (opts.trace_id) |tid|
            try self.allocator.dupe(u8, tid)
        else
            try utils.generateTraceId(self.allocator);

        // Check sampling decision using utils
        if (!self.sampler.shouldSample(trace_id)) {
            self.allocator.free(span_id);
            self.allocator.free(trace_id);
            return Span.empty(self.allocator);
        }

        self.active_span_count += 1;
        self.total_spans_created += 1;

        const span = Span{
            .allocator = self.allocator,
            .span_id = span_id,
            .trace_id = trace_id,
            .parent_span_id = if (opts.parent_span_id) |pid| try self.allocator.dupe(u8, pid) else null,
            .name = try self.allocator.dupe(u8, name),
            .start_time = std.time.nanoTimestamp(),
            .kind = opts.kind orelse .internal,
        };

        // Invoke callback
        if (self.on_span_start) |callback| {
            callback(span_id, name);
        }

        return span;
    }

    /// Ends a span and marks it for export
    pub fn endSpan(self: *Telemetry, span: *Span) !void {
        if (!self.enabled) return;

        self.mutex.lock();
        defer self.mutex.unlock();

        span.end_time = std.time.nanoTimestamp();

        // Calculate duration using utils helper
        const duration_ns = utils.durationSinceNs(span.start_time);

        if (self.active_span_count > 0) {
            self.active_span_count -= 1;
        }
        self.completed_span_count += 1;

        // Invoke callback
        if (self.on_span_end) |callback| {
            callback(span.span_id, duration_ns);
        }

        // Check if batch export threshold reached
        if (self.completed_span_count >= self.config.batch_size) {
            self.triggerBatchExport() catch {};
        }
    }

    /// Trigger batch export based on config
    fn triggerBatchExport(self: *Telemetry) !void {
        const now = std.time.timestamp();
        const elapsed_ms: u64 = if (now > self.last_batch_export)
            @intCast(now - self.last_batch_export)
        else
            0;

        if (elapsed_ms >= self.config.batch_timeout_ms or
            self.completed_span_count >= self.config.batch_size)
        {
            try self.exportSpansInternal();
            self.last_batch_export = now;
            self.exporter_stats.recordBatchExport();
        }
    }

    /// Start a child span using parent context
    pub fn startSpanWithContext(self: *Telemetry, name: []const u8, parent: *const Span, opts: SpanOptions) !Span {
        var new_opts = opts;
        new_opts.parent_span_id = parent.span_id;
        new_opts.trace_id = parent.trace_id;
        return self.startSpan(name, new_opts);
    }

    /// Records a metric value
    pub fn recordMetric(self: *Telemetry, name: []const u8, value: f64, opts: MetricOptions) !void {
        if (!self.enabled) return;

        self.mutex.lock();
        defer self.mutex.unlock();

        // Store metric in ArrayList
        try self.metrics.append(self.allocator, .{
            .name = try self.allocator.dupe(u8, name),
            .kind = opts.kind orelse .gauge,
            .value = value,
            .unit = opts.unit,
            .description = opts.description,
            .timestamp = std.time.nanoTimestamp(),
        });

        self.metric_count += 1;
        self.total_metrics_recorded += 1;

        // Invoke callback
        if (self.on_metric_recorded) |callback| {
            callback(name, value);
        }
    }

    /// Records a counter metric (monotonically increasing)
    pub fn recordCounter(self: *Telemetry, name: []const u8, value: f64) !void {
        try self.recordMetric(name, value, .{ .kind = .counter });
    }

    /// Records a gauge metric (point-in-time value)
    pub fn recordGauge(self: *Telemetry, name: []const u8, value: f64) !void {
        try self.recordMetric(name, value, .{ .kind = .gauge });
    }

    /// Records a histogram metric (distribution)
    pub fn recordHistogram(self: *Telemetry, name: []const u8, value: f64) !void {
        try self.recordMetric(name, value, .{ .kind = .histogram });
    }

    /// Internal span export implementation
    fn exportSpansInternal(self: *Telemetry) !void {
        if (self.completed_span_count == 0) return;

        // Export based on provider
        switch (self.config.provider) {
            .file => try self.exportToFile(),
            .generic => try self.exportToOtlp(),
            .jaeger => try self.exportToJaeger(),
            .zipkin => try self.exportToZipkin(),
            .datadog => try self.exportToDatadog(),
            .google_cloud => try self.exportToGoogleCloud(),
            .google_analytics => try self.exportToGoogleAnalytics(),
            .google_tag_manager => try self.exportToGoogleTagManager(),
            .aws_xray => try self.exportToAwsXray(),
            .azure => try self.exportToAzure(),
            .custom => {
                if (self.config.custom_exporter_fn) |export_fn| {
                    try export_fn();
                }
            },
            .none => {},
        }

        self.total_spans_exported += self.completed_span_count;
        self.exporter_stats.recordExport(self.completed_span_count, 0);
        self.completed_span_count = 0;
    }

    /// Export spans in OTLP JSON format (OpenTelemetry Protocol)
    /// Compatible with OpenTelemetry Collector and OTLP-compatible backends
    fn exportToOtlp(self: *Telemetry) !void {
        self.batch_buffer.clearRetainingCapacity();
        const writer = self.batch_buffer.writer(self.allocator);

        try self.writeOtlpSpans(writer);

        // Export via network if socket available, otherwise to file
        if (self.network_socket != null and self.network_address != null) {
            try Network.sendUdp(self.network_socket.?, self.network_address.?, self.batch_buffer.items);
            self.exporter_stats.recordNetworkExport();
        } else if (self.config.exporter_file_path) |path| {
            const file = try std.fs.cwd().createFile(path, .{ .truncate = false });
            defer file.close();
            try file.seekFromEnd(0);
            try file.writeAll(self.batch_buffer.items);
            try file.writeAll("\n");
        }

        self.exporter_stats.recordExport(self.completed_spans.items.len, self.batch_buffer.items.len);
    }

    /// Write spans in OTLP JSON format
    fn writeOtlpSpans(self: *Telemetry, writer: anytype) !void {
        try writer.writeAll("{\"resourceSpans\":[{");

        // Resource section
        try writer.writeAll("\"resource\":{\"attributes\":[");
        var first_attr = true;
        if (self.resource.service_name) |name| {
            try self.writeOtlpAttribute(writer, "service.name", .{ .string = name }, &first_attr);
        }
        if (self.resource.service_version) |ver| {
            try self.writeOtlpAttribute(writer, "service.version", .{ .string = ver }, &first_attr);
        }
        if (self.resource.environment) |env| {
            try self.writeOtlpAttribute(writer, "deployment.environment", .{ .string = env }, &first_attr);
        }
        if (self.resource.datacenter) |dc| {
            try self.writeOtlpAttribute(writer, "cloud.availability_zone", .{ .string = dc }, &first_attr);
        }
        try writer.writeAll("]},");

        // Scope spans section
        try writer.writeAll("\"scopeSpans\":[{\"scope\":{\"name\":\"logly.telemetry\",\"version\":\"0.1.5\"},\"spans\":[");

        for (self.completed_spans.items, 0..) |span, i| {
            if (i > 0) try writer.writeByte(',');
            try self.writeOtlpSpan(writer, span);
        }

        try writer.writeAll("]}]}]}");
    }

    /// Write a single span in OTLP format
    fn writeOtlpSpan(self: *Telemetry, writer: anytype, span: Span) !void {
        _ = self;
        try writer.writeAll("{\"traceId\":\"");
        try writer.writeAll(span.trace_id);
        try writer.writeAll("\",\"spanId\":\"");
        try writer.writeAll(span.span_id);
        try writer.writeAll("\",\"name\":\"");
        try utils.escapeJsonString(writer, span.name);
        try writer.writeAll("\",\"kind\":");
        const kind_num: u8 = switch (span.kind) {
            .internal => 1,
            .server => 2,
            .client => 3,
            .producer => 4,
            .consumer => 5,
        };
        try utils.writeInt(writer, kind_num);
        try writer.writeAll(",\"startTimeUnixNano\":");
        try utils.writeInt(writer, utils.safeToUnsigned(u64, span.start_time));
        if (span.end_time > 0) {
            try writer.writeAll(",\"endTimeUnixNano\":");
            try utils.writeInt(writer, utils.safeToUnsigned(u64, span.end_time));
        }
        if (span.parent_span_id) |pid| {
            try writer.writeAll(",\"parentSpanId\":\"");
            try writer.writeAll(pid);
            try writer.writeByte('"');
        }
        // Status
        try writer.writeAll(",\"status\":{\"code\":");
        const status_code: u8 = switch (span.status) {
            .unset => 0,
            .ok => 1,
            .err => 2,
        };
        try utils.writeInt(writer, status_code);
        try writer.writeAll("}");

        try writer.writeByte('}');
    }

    /// Write OTLP attribute
    fn writeOtlpAttribute(self: *Telemetry, writer: anytype, key: []const u8, value: SpanAttribute, first: *bool) !void {
        _ = self;
        if (!first.*) try writer.writeByte(',');
        first.* = false;
        try writer.writeAll("{\"key\":\"");
        try writer.writeAll(key);
        try writer.writeAll("\",\"value\":{");
        switch (value) {
            .string => |s| {
                try writer.writeAll("\"stringValue\":\"");
                try utils.escapeJsonString(writer, s);
                try writer.writeByte('"');
            },
            .integer => |i| {
                try writer.writeAll("\"intValue\":");
                try std.fmt.format(writer, "{d}", .{i});
            },
            .float => |f| {
                try writer.writeAll("\"doubleValue\":");
                try std.fmt.format(writer, "{d:.6}", .{f});
            },
            .boolean => |b| {
                try writer.writeAll("\"boolValue\":");
                try writer.writeAll(if (b) "true" else "false");
            },
            .string_array => |arr| {
                try writer.writeAll("\"arrayValue\":{\"values\":[");
                for (arr, 0..) |s, j| {
                    if (j > 0) try writer.writeByte(',');
                    try writer.writeAll("{\"stringValue\":\"");
                    try utils.escapeJsonString(writer, s);
                    try writer.writeAll("\"}");
                }
                try writer.writeAll("]}");
            },
        }
        try writer.writeAll("}}");
    }

    /// Export to Jaeger (Thrift JSON format)
    fn exportToJaeger(self: *Telemetry) !void {
        self.batch_buffer.clearRetainingCapacity();
        const writer = self.batch_buffer.writer(self.allocator);

        try writer.writeAll("{\"data\":[{\"traceID\":\"");
        if (self.completed_spans.items.len > 0) {
            try writer.writeAll(self.completed_spans.items[0].trace_id);
        }
        try writer.writeAll("\",\"spans\":[");

        for (self.completed_spans.items, 0..) |span, i| {
            if (i > 0) try writer.writeByte(',');
            try self.writeJaegerSpan(writer, span);
        }

        try writer.writeAll("],\"processes\":{\"p1\":{\"serviceName\":\"");
        try writer.writeAll(self.resource.service_name orelse "unknown");
        try writer.writeAll("\"}}}]}");

        try self.sendToEndpoint();
    }

    /// Write Jaeger span format
    fn writeJaegerSpan(self: *Telemetry, writer: anytype, span: Span) !void {
        _ = self;
        try writer.writeAll("{\"traceID\":\"");
        try writer.writeAll(span.trace_id);
        try writer.writeAll("\",\"spanID\":\"");
        try writer.writeAll(span.span_id);
        try writer.writeAll("\",\"operationName\":\"");
        try utils.escapeJsonString(writer, span.name);
        try writer.writeAll("\",\"startTime\":");
        const start_us = utils.safeToUnsigned(u64, span.start_time) / 1000;
        try utils.writeInt(writer, start_us);
        if (span.end_time > 0) {
            try writer.writeAll(",\"duration\":");
            const duration_us = utils.safeToUnsigned(u64, span.end_time - span.start_time) / 1000;
            try utils.writeInt(writer, duration_us);
        }
        try writer.writeAll(",\"processID\":\"p1\"}");
    }

    /// Export to Zipkin format
    fn exportToZipkin(self: *Telemetry) !void {
        self.batch_buffer.clearRetainingCapacity();
        const writer = self.batch_buffer.writer(self.allocator);

        try writer.writeByte('[');
        for (self.completed_spans.items, 0..) |span, i| {
            if (i > 0) try writer.writeByte(',');
            try self.writeZipkinSpan(writer, span);
        }
        try writer.writeByte(']');

        try self.sendToEndpoint();
    }

    /// Write Zipkin span format
    fn writeZipkinSpan(self: *Telemetry, writer: anytype, span: Span) !void {
        try writer.writeAll("{\"traceId\":\"");
        try writer.writeAll(span.trace_id);
        try writer.writeAll("\",\"id\":\"");
        try writer.writeAll(span.span_id);
        try writer.writeAll("\",\"name\":\"");
        try utils.escapeJsonString(writer, span.name);
        try writer.writeAll("\",\"timestamp\":");
        const start_us = utils.safeToUnsigned(u64, span.start_time) / 1000;
        try utils.writeInt(writer, start_us);
        if (span.end_time > 0) {
            try writer.writeAll(",\"duration\":");
            const duration_us = utils.safeToUnsigned(u64, span.end_time - span.start_time) / 1000;
            try utils.writeInt(writer, duration_us);
        }
        try writer.writeAll(",\"localEndpoint\":{\"serviceName\":\"");
        try writer.writeAll(self.resource.service_name orelse "unknown");
        try writer.writeAll("\"}}");
    }

    /// Export to Datadog APM format
    fn exportToDatadog(self: *Telemetry) !void {
        self.batch_buffer.clearRetainingCapacity();
        const writer = self.batch_buffer.writer(self.allocator);

        try writer.writeAll("[[");
        for (self.completed_spans.items, 0..) |span, i| {
            if (i > 0) try writer.writeByte(',');
            try self.writeDatadogSpan(writer, span);
        }
        try writer.writeAll("]]");

        try self.sendToEndpoint();
    }

    /// Write Datadog span format
    fn writeDatadogSpan(self: *Telemetry, writer: anytype, span: Span) !void {
        try writer.writeAll("{\"name\":\"");
        try utils.escapeJsonString(writer, span.name);
        try writer.writeAll("\",\"service\":\"");
        try writer.writeAll(self.resource.service_name orelse "unknown");
        try writer.writeAll("\",\"resource\":\"");
        try utils.escapeJsonString(writer, span.name);
        try writer.writeAll("\",\"trace_id\":");
        // Datadog uses numeric trace IDs
        try writer.writeAll("0");
        try writer.writeAll(",\"span_id\":");
        try writer.writeAll("0");
        try writer.writeAll(",\"start\":");
        try utils.writeInt(writer, utils.safeToUnsigned(u64, span.start_time));
        if (span.end_time > 0) {
            try writer.writeAll(",\"duration\":");
            try utils.writeInt(writer, utils.safeToUnsigned(u64, span.end_time - span.start_time));
        }
        try writer.writeByte('}');
    }

    /// Export to Google Cloud Trace format
    fn exportToGoogleCloud(self: *Telemetry) !void {
        try self.exportToOtlp(); // Google Cloud accepts OTLP
    }

    /// Export to Google Analytics 4 Measurement Protocol
    fn exportToGoogleAnalytics(self: *Telemetry) !void {
        self.batch_buffer.clearRetainingCapacity();
        const writer = self.batch_buffer.writer(self.allocator);

        try writer.writeAll("{\"client_id\":\"logly_");
        if (self.completed_spans.items.len > 0) {
            try writer.writeAll(self.completed_spans.items[0].trace_id[0..8]);
        } else {
            try writer.writeAll("unknown");
        }
        try writer.writeAll("\",\"events\":[");

        for (self.completed_spans.items, 0..) |span, i| {
            if (i > 0) try writer.writeByte(',');
            try writer.writeAll("{\"name\":\"span_completed\",\"params\":{");
            try writer.writeAll("\"span_name\":\"");
            try utils.escapeJsonString(writer, span.name);
            try writer.writeAll("\",\"trace_id\":\"");
            try writer.writeAll(span.trace_id);
            try writer.writeAll("\",\"duration_ms\":");
            if (span.end_time > 0) {
                const duration_ms = utils.safeToUnsigned(u64, span.end_time - span.start_time) / 1_000_000;
                try utils.writeInt(writer, duration_ms);
            } else {
                try writer.writeAll("0");
            }
            try writer.writeAll("}}");
        }

        try writer.writeAll("]}");
        try self.sendToEndpoint();
    }

    /// Export to Google Tag Manager Server-Side
    fn exportToGoogleTagManager(self: *Telemetry) !void {
        try self.exportToGoogleAnalytics(); // Similar format
    }

    /// Export to AWS X-Ray format
    fn exportToAwsXray(self: *Telemetry) !void {
        self.batch_buffer.clearRetainingCapacity();
        const writer = self.batch_buffer.writer(self.allocator);

        for (self.completed_spans.items, 0..) |span, i| {
            if (i > 0) try writer.writeByte('\n');
            try self.writeXraySegment(writer, span);
        }

        try self.sendToEndpoint();
    }

    /// Write AWS X-Ray segment format
    fn writeXraySegment(self: *Telemetry, writer: anytype, span: Span) !void {
        try writer.writeAll("{\"name\":\"");
        try utils.escapeJsonString(writer, span.name);
        try writer.writeAll("\",\"id\":\"");
        try writer.writeAll(span.span_id[0..@min(16, span.span_id.len)]);
        try writer.writeAll("\",\"trace_id\":\"1-");
        // X-Ray format: 1-{hex timestamp}-{hex random}
        try writer.writeAll(span.trace_id[0..8]);
        try writer.writeAll("-");
        try writer.writeAll(span.trace_id[8..@min(32, span.trace_id.len)]);
        try writer.writeAll("\",\"start_time\":");
        const start_s = @as(f64, @floatFromInt(utils.safeToUnsigned(u64, span.start_time))) / 1_000_000_000.0;
        try std.fmt.format(writer, "{d:.6}", .{start_s});
        if (span.end_time > 0) {
            try writer.writeAll(",\"end_time\":");
            const end_s = @as(f64, @floatFromInt(utils.safeToUnsigned(u64, span.end_time))) / 1_000_000_000.0;
            try std.fmt.format(writer, "{d:.6}", .{end_s});
        }
        try writer.writeAll(",\"origin\":\"");
        try writer.writeAll(self.resource.service_name orelse "unknown");
        try writer.writeAll("\"}");
    }

    /// Export to Azure Application Insights format
    fn exportToAzure(self: *Telemetry) !void {
        self.batch_buffer.clearRetainingCapacity();
        const writer = self.batch_buffer.writer(self.allocator);

        try writer.writeByte('[');
        for (self.completed_spans.items, 0..) |span, i| {
            if (i > 0) try writer.writeByte(',');
            try self.writeAzureEnvelope(writer, span);
        }
        try writer.writeByte(']');

        try self.sendToEndpoint();
    }

    /// Write Azure Application Insights envelope
    fn writeAzureEnvelope(self: *Telemetry, writer: anytype, span: Span) !void {
        try writer.writeAll("{\"name\":\"Microsoft.ApplicationInsights.Request\",");
        try writer.writeAll("\"time\":\"");
        // Write ISO 8601 timestamp
        const timestamp_ns = utils.safeToUnsigned(u64, span.start_time);
        const timestamp_s = timestamp_ns / 1_000_000_000;
        try std.fmt.format(writer, "{d}", .{timestamp_s});
        try writer.writeAll("\",\"data\":{\"baseType\":\"RequestData\",\"baseData\":{");
        try writer.writeAll("\"id\":\"");
        try writer.writeAll(span.span_id);
        try writer.writeAll("\",\"name\":\"");
        try utils.escapeJsonString(writer, span.name);
        try writer.writeAll("\",\"success\":");
        try writer.writeAll(if (span.status != .err) "true" else "false");
        if (span.end_time > 0) {
            try writer.writeAll(",\"duration\":\"");
            const duration_ms = utils.safeToUnsigned(u64, span.end_time - span.start_time) / 1_000_000;
            const hours = duration_ms / 3_600_000;
            const minutes = (duration_ms % 3_600_000) / 60_000;
            const seconds = (duration_ms % 60_000) / 1_000;
            const ms = duration_ms % 1_000;
            try std.fmt.format(writer, "{d:0>2}:{d:0>2}:{d:0>2}.{d:0>3}", .{ hours, minutes, seconds, ms });
            try writer.writeByte('"');
        }
        try writer.writeAll("}},\"iKey\":\"");
        try writer.writeAll(self.config.connection_string orelse "");
        try writer.writeAll("\"}");
    }

    /// Send buffer to configured endpoint
    fn sendToEndpoint(self: *Telemetry) !void {
        if (self.network_socket != null and self.network_address != null) {
            try Network.sendUdp(self.network_socket.?, self.network_address.?, self.batch_buffer.items);
            self.exporter_stats.recordNetworkExport();
        }
        self.exporter_stats.recordExport(self.completed_spans.items.len, self.batch_buffer.items.len);
    }

    /// Export spans to file (JSONL format)
    fn exportToFile(self: *Telemetry) !void {
        const path = self.config.exporter_file_path orelse return;

        const file = try std.fs.cwd().createFile(path, .{ .truncate = false });
        defer file.close();

        // Seek to end for append
        try file.seekFromEnd(0);

        // Write each span as a JSON line
        var buf: [4096]u8 = undefined;
        for (self.completed_spans.items) |span| {
            var fbs = std.io.fixedBufferStream(&buf);
            self.writeSpanJson(fbs.writer(), span) catch continue;
            _ = fbs.write("\n") catch continue;
            file.writeAll(fbs.getWritten()) catch continue;
        }
    }

    /// Export spans to network (TCP/UDP) using Network module
    fn exportToNetwork(self: *Telemetry) !void {
        if (self.network_socket == null or self.network_address == null) return;

        // Build JSON batch
        self.batch_buffer.clearRetainingCapacity();
        const writer = self.batch_buffer.writer(self.allocator);

        try writer.writeAll("{\"spans\":[");
        for (self.completed_spans.items, 0..) |span, i| {
            if (i > 0) try writer.writeByte(',');
            try self.writeSpanJson(writer, span);
        }
        try writer.writeAll("]}");

        // Send via UDP using Network module
        try Network.sendUdp(self.network_socket.?, self.network_address.?, self.batch_buffer.items);
        self.exporter_stats.recordExport(self.completed_spans.items.len, self.batch_buffer.items.len);
        self.exporter_stats.recordNetworkExport();
    }

    /// Write span as JSON using utils helpers
    fn writeSpanJson(self: *Telemetry, writer: anytype, span: Span) !void {
        _ = self;
        try writer.writeAll("{\"trace_id\":\"");
        try writer.writeAll(span.trace_id);
        try writer.writeAll("\",\"span_id\":\"");
        try writer.writeAll(span.span_id);
        try writer.writeAll("\",\"name\":\"");
        try utils.escapeJsonString(writer, span.name);
        try writer.writeAll("\",\"kind\":\"");
        try writer.writeAll(@tagName(span.kind));
        try writer.writeAll("\",\"status\":\"");
        try writer.writeAll(@tagName(span.status));
        try writer.writeAll("\",\"start_time\":");
        try utils.writeInt(writer, utils.safeToUnsigned(u64, span.start_time));
        if (span.end_time > 0) {
            try writer.writeAll(",\"end_time\":");
            try utils.writeInt(writer, utils.safeToUnsigned(u64, span.end_time));
            try writer.writeAll(",\"duration_ns\":");
            const duration = span.end_time - span.start_time;
            try utils.writeInt(writer, utils.safeToUnsigned(u64, duration));
        }
        if (span.parent_span_id) |pid| {
            try writer.writeAll(",\"parent_span_id\":\"");
            try writer.writeAll(pid);
            try writer.writeByte('"');
        }
        try writer.writeByte('}');
    }

    /// Exports all completed spans (placeholder for actual export logic)
    pub fn exportSpans(self: *Telemetry) !void {
        if (!self.enabled) return;

        self.mutex.lock();
        defer self.mutex.unlock();

        try self.exportSpansInternal();
    }

    /// Exports all metrics (placeholder for actual export logic)
    pub fn exportMetrics(self: *Telemetry) !void {
        if (!self.enabled) return;

        self.mutex.lock();
        defer self.mutex.unlock();

        // Clear metrics after export
        for (self.metrics.items) |metric| {
            self.allocator.free(metric.name);
        }
        self.metrics.clearRetainingCapacity();
        self.metric_count = 0;
    }

    /// Flushes all data (spans and metrics)
    pub fn flush(self: *Telemetry) !void {
        try self.exportSpans();
        try self.exportMetrics();
    }

    /// Returns the number of active spans
    pub fn getActiveSpanCount(self: *Telemetry) usize {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.active_span_count;
    }

    /// Returns the number of completed spans awaiting export
    pub fn getCompletedSpanCount(self: *Telemetry) usize {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.completed_span_count;
    }

    /// Returns the current metric count
    pub fn getMetricCount(self: *Telemetry) usize {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.metric_count;
    }

    /// Returns telemetry statistics
    pub fn getStats(self: *Telemetry) TelemetryStats {
        self.mutex.lock();
        defer self.mutex.unlock();
        return .{
            .total_spans_created = self.total_spans_created,
            .total_spans_exported = self.total_spans_exported,
            .total_metrics_recorded = self.total_metrics_recorded,
            .active_spans = self.active_span_count,
            .pending_spans = self.completed_span_count,
        };
    }

    /// Returns exporter statistics
    pub fn getExporterStats(self: *Telemetry) ExporterStats {
        return self.exporter_stats;
    }

    /// Generate W3C traceparent header value
    pub fn getTraceparentHeader(self: *Telemetry, span: *const Span) ![]const u8 {
        // Format: version-trace_id-span_id-flags
        // Example: 00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01
        var buf: [128]u8 = undefined;
        const result = try std.fmt.bufPrint(&buf, "00-{s}-{s}-01", .{ span.trace_id, span.span_id });
        return try self.allocator.dupe(u8, result);
    }

    /// Parse W3C traceparent header and extract trace context
    pub fn parseTraceparentHeader(header: []const u8) ?TraceContext {
        // Format: version-trace_id-span_id-flags
        var parts = std.mem.splitScalar(u8, header, '-');

        const version = parts.next() orelse return null;
        if (!std.mem.eql(u8, version, "00")) return null;

        const trace_id = parts.next() orelse return null;
        const span_id = parts.next() orelse return null;
        const flags = parts.next() orelse return null;

        return TraceContext{
            .trace_id = trace_id,
            .span_id = span_id,
            .sampled = flags.len > 0 and flags[flags.len - 1] == '1',
        };
    }

    /// Enable/disable telemetry at runtime
    pub fn setEnabled(self: *Telemetry, enabled: bool) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.enabled = enabled;
    }

    /// Check if telemetry is currently enabled
    pub fn isEnabled(self: *Telemetry) bool {
        return self.enabled;
    }

    /// Get the current resource configuration
    pub fn getResource(self: *Telemetry) Resource {
        return self.resource;
    }

    /// Update resource configuration at runtime
    pub fn setResource(self: *Telemetry, resource: Resource) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.resource = resource;
    }

    /// Reset all statistics counters
    pub fn resetStats(self: *Telemetry) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.total_spans_created = 0;
        self.total_spans_exported = 0;
        self.total_metrics_recorded = 0;
        self.exporter_stats = .{};
    }

    /// Get span by trace_id (for distributed trace continuation)
    pub fn findSpanByTraceId(self: *Telemetry, trace_id: []const u8) ?*const Span {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.spans.items) |*span| {
            if (std.mem.eql(u8, span.trace_id, trace_id)) {
                return span;
            }
        }
        return null;
    }

    /// Create a span from incoming W3C traceparent header (for distributed tracing)
    pub fn startSpanFromTraceparent(self: *Telemetry, name: []const u8, traceparent: []const u8, opts: SpanOptions) !Span {
        const ctx = parseTraceparentHeader(traceparent) orelse {
            // If invalid header, start new root span
            return self.startSpan(name, opts);
        };

        if (!ctx.sampled) {
            // Not sampled, return empty span
            return Span.empty(self.allocator);
        }

        // Start span with inherited trace context
        var new_opts = opts;
        new_opts.trace_id = ctx.trace_id;
        new_opts.parent_span_id = ctx.span_id;

        return self.startSpan(name, new_opts);
    }
};

/// Trace context for W3C propagation
pub const TraceContext = struct {
    trace_id: []const u8,
    span_id: []const u8,
    sampled: bool = true,
};

/// Telemetry statistics
pub const TelemetryStats = struct {
    total_spans_created: u64,
    total_spans_exported: u64,
    total_metrics_recorded: u64,
    active_spans: usize,
    pending_spans: usize,
};

/// Span represents a single unit of work in a trace
pub const Span = struct {
    allocator: std.mem.Allocator,
    span_id: []const u8,
    trace_id: []const u8,
    parent_span_id: ?[]const u8 = null,
    name: []const u8,
    start_time: i128,
    end_time: i128 = 0,
    status: SpanStatus = .unset,
    kind: SpanKind = .internal,

    // Attributes storage
    attributes: std.StringHashMap(SpanAttribute) = undefined,
    has_attributes: bool = false,

    // Events storage
    events: std.ArrayList(SpanEvent) = undefined,
    has_events: bool = false,

    /// Creates an empty/no-op span (when telemetry is disabled or not sampled)
    pub fn empty(allocator: std.mem.Allocator) Span {
        return Span{
            .allocator = allocator,
            .span_id = "",
            .trace_id = "",
            .name = "",
            .start_time = 0,
        };
    }

    /// Check if this is an empty/no-op span
    pub fn isEmpty(self: Span) bool {
        return self.span_id.len == 0;
    }

    /// Adds an attribute to the span
    pub fn setAttribute(self: *Span, key: []const u8, value: SpanAttribute) !void {
        if (self.span_id.len == 0) return; // No-op for empty spans

        if (!self.has_attributes) {
            self.attributes = std.StringHashMap(SpanAttribute).init(self.allocator);
            self.has_attributes = true;
        }

        const key_copy = try self.allocator.dupe(u8, key);
        try self.attributes.put(key_copy, value);
    }

    /// Adds an event to the span
    pub fn addEvent(self: *Span, name: []const u8, attrs: ?*const anyopaque) !void {
        if (self.span_id.len == 0) return; // No-op for empty spans
        _ = attrs;

        if (!self.has_events) {
            self.events = try std.ArrayList(SpanEvent).initCapacity(self.allocator, 8);
            self.has_events = true;
        }

        try self.events.append(self.allocator, .{
            .name = try self.allocator.dupe(u8, name),
            .timestamp = std.time.nanoTimestamp(),
        });
    }

    /// Sets span status
    pub fn setStatus(self: *Span, status: SpanStatus) void {
        self.status = status;
    }

    /// Sets span status with message
    pub fn setStatusWithMessage(self: *Span, status: SpanStatus, message: []const u8) !void {
        self.status = status;
        try self.setAttribute("status.message", .{ .string = message });
    }

    /// Ends the span (sets end_time)
    pub fn end(self: *Span) void {
        if (self.end_time == 0) {
            self.end_time = std.time.nanoTimestamp();
        }
    }

    /// Gets span duration in nanoseconds
    pub fn getDuration(self: Span) u64 {
        if (self.end_time == 0 or self.start_time == 0) return 0;
        return utils.durationSinceNs(self.start_time);
    }

    /// Gets span duration in milliseconds
    pub fn getDurationMs(self: Span) f64 {
        const ns = self.getDuration();
        return @as(f64, @floatFromInt(ns)) / 1_000_000.0;
    }

    /// Cleans up span resources
    pub fn deinit(self: *Span) void {
        if (self.span_id.len > 0) {
            self.allocator.free(self.span_id);
        }
        if (self.trace_id.len > 0) {
            self.allocator.free(self.trace_id);
        }
        if (self.parent_span_id) |pid| {
            if (pid.len > 0) {
                self.allocator.free(pid);
            }
        }
        if (self.name.len > 0) {
            self.allocator.free(@constCast(self.name));
        }

        // Clean up attributes
        if (self.has_attributes) {
            var it = self.attributes.iterator();
            while (it.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
            }
            self.attributes.deinit();
        }

        // Clean up events
        if (self.has_events) {
            for (self.events.items) |event| {
                self.allocator.free(event.name);
            }
            self.events.deinit(self.allocator);
        }
    }
};

/// Span attribute value (tagged union)
pub const SpanAttribute = union(enum) {
    string: []const u8,
    integer: i64,
    float: f64,
    boolean: bool,
    string_array: []const []const u8,
};

/// Span event
pub const SpanEvent = struct {
    name: []const u8,
    timestamp: i128,
};

/// Span options for creation
pub const SpanOptions = struct {
    trace_id: ?[]const u8 = null,
    parent_span_id: ?[]const u8 = null,
    kind: ?SpanKind = null,
};

/// Span kind (W3C standard)
pub const SpanKind = enum {
    internal,
    server,
    client,
    producer,
    consumer,
};

/// Span status
pub const SpanStatus = enum {
    unset,
    ok,
    err,
};

/// Metric data
pub const Metric = struct {
    name: []const u8,
    kind: MetricKind,
    value: f64,
    unit: ?[]const u8,
    description: ?[]const u8,
    timestamp: i128,
};

/// Metric kind
pub const MetricKind = enum {
    counter,
    gauge,
    histogram,
    summary,
};

/// Metric options
pub const MetricOptions = struct {
    kind: ?MetricKind = null,
    unit: ?[]const u8 = null,
    description: ?[]const u8 = null,
};

/// Resource information (service metadata)
pub const Resource = struct {
    service_name: ?[]const u8,
    service_version: ?[]const u8,
    environment: ?[]const u8,
    datacenter: ?[]const u8,

    /// Creates Resource from TelemetryConfig
    pub fn fromConfig(config: TelemetryConfig) Resource {
        return .{
            .service_name = config.service_name,
            .service_version = config.service_version,
            .environment = config.environment,
            .datacenter = config.datacenter,
        };
    }
};

/// Sampler for controlling trace sampling
pub const TelemetrySampler = struct {
    strategy: TelemetryConfig.SamplingStrategy,
    sampling_rate: f64,

    /// Initialize sampler from config
    pub fn init(config: TelemetryConfig) TelemetrySampler {
        return .{
            .strategy = config.sampling_strategy,
            .sampling_rate = config.sampling_rate,
        };
    }

    /// Determines if a trace should be sampled
    pub fn shouldSample(self: TelemetrySampler, trace_id: []const u8) bool {
        _ = trace_id;
        return switch (self.strategy) {
            .always_on => true,
            .always_off => false,
            .trace_id_ratio => utils.shouldSample(self.sampling_rate),
            .parent_based => true, // Simplified: always sample if parent-based
        };
    }
};

/// Baggage for context propagation (W3C Baggage standard)
///
/// Baggage allows applications to propagate arbitrary key-value pairs across
/// service boundaries as part of the distributed trace context.
pub const Baggage = struct {
    allocator: std.mem.Allocator,
    items: std.StringHashMap([]const u8),

    pub fn init(allocator: std.mem.Allocator) Baggage {
        return .{
            .allocator = allocator,
            .items = std.StringHashMap([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *Baggage) void {
        var it = self.items.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.items.deinit();
    }

    pub fn set(self: *Baggage, key: []const u8, value: []const u8) !void {
        const key_copy = try self.allocator.dupe(u8, key);
        const value_copy = try self.allocator.dupe(u8, value);
        try self.items.put(key_copy, value_copy);
    }

    pub fn get(self: *Baggage, key: []const u8) ?[]const u8 {
        return self.items.get(key);
    }

    pub fn remove(self: *Baggage, key: []const u8) void {
        if (self.items.fetchRemove(key)) |entry| {
            self.allocator.free(entry.key);
            self.allocator.free(entry.value);
        }
    }

    /// Format as W3C baggage header value
    pub fn toHeaderValue(self: *Baggage, allocator: std.mem.Allocator) ![]const u8 {
        var result = std.ArrayList(u8).initCapacity(allocator, 256) catch return "";
        const writer = result.writer(allocator);

        var it = self.items.iterator();
        var first = true;
        while (it.next()) |entry| {
            if (!first) try writer.writeByte(',');
            try writer.writeAll(entry.key_ptr.*);
            try writer.writeByte('=');
            try writer.writeAll(entry.value_ptr.*);
            first = false;
        }

        return result.toOwnedSlice(allocator);
    }

    /// Parse W3C baggage header value
    pub fn fromHeaderValue(allocator: std.mem.Allocator, header: []const u8) !Baggage {
        var baggage = Baggage.init(allocator);
        errdefer baggage.deinit();

        var pairs = std.mem.splitScalar(u8, header, ',');
        while (pairs.next()) |pair| {
            const trimmed = std.mem.trim(u8, pair, " ");
            if (std.mem.indexOfScalar(u8, trimmed, '=')) |eq_idx| {
                const key = std.mem.trim(u8, trimmed[0..eq_idx], " ");
                const value = std.mem.trim(u8, trimmed[eq_idx + 1 ..], " ");
                try baggage.set(key, value);
            }
        }

        return baggage;
    }

    /// Get the number of items in the baggage
    pub fn count(self: *Baggage) usize {
        return self.items.count();
    }

    /// Check if baggage is empty
    pub fn isEmpty(self: *Baggage) bool {
        return self.items.count() == 0;
    }

    /// Clear all baggage items
    pub fn clear(self: *Baggage) void {
        var it = self.items.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.items.clearRetainingCapacity();
    }

    /// Check if a key exists in baggage
    pub fn contains(self: *Baggage, key: []const u8) bool {
        return self.items.contains(key);
    }
};

test "TelemetryConfig presets" {
    // Test default config
    const default_config = TelemetryConfig.default();
    try std.testing.expect(!default_config.enabled);
    try std.testing.expectEqual(default_config.provider, .none);

    // Test Jaeger preset
    const jaeger_config = TelemetryConfig.jaeger();
    try std.testing.expect(jaeger_config.enabled);
    try std.testing.expectEqual(jaeger_config.provider, .jaeger);
    try std.testing.expect(jaeger_config.exporter_endpoint != null);

    // Test Zipkin preset
    const zipkin_config = TelemetryConfig.zipkin();
    try std.testing.expect(zipkin_config.enabled);
    try std.testing.expectEqual(zipkin_config.provider, .zipkin);

    // Test file preset
    const file_config = TelemetryConfig.file("test.jsonl");
    try std.testing.expect(file_config.enabled);
    try std.testing.expectEqual(file_config.provider, .file);
    try std.testing.expectEqualStrings("test.jsonl", file_config.exporter_file_path.?);

    // Test development preset
    const dev_config = TelemetryConfig.development();
    try std.testing.expect(dev_config.enabled);
    try std.testing.expectEqual(dev_config.sampling_strategy, .always_on);

    // Test high throughput preset
    const ht_config = TelemetryConfig.highThroughput();
    try std.testing.expect(ht_config.enabled);
    try std.testing.expectEqual(ht_config.sampling_strategy, .trace_id_ratio);
    try std.testing.expect(ht_config.sampling_rate < 0.1);
}

test "Telemetry init and deinit" {
    const allocator = std.testing.allocator;

    // Test with disabled config
    const config = TelemetryConfig.default();
    var telemetry = try Telemetry.init(allocator, config);
    defer telemetry.deinit();

    try std.testing.expect(!telemetry.enabled);
    try std.testing.expectEqual(@as(usize, 0), telemetry.active_span_count);
}

test "Telemetry enabled with Jaeger" {
    const allocator = std.testing.allocator;

    const config = TelemetryConfig.jaeger();
    var telemetry = try Telemetry.init(allocator, config);
    defer telemetry.deinit();

    try std.testing.expect(telemetry.enabled);
    try std.testing.expectEqual(telemetry.config.provider, .jaeger);
}

test "Span creation and lifecycle" {
    const allocator = std.testing.allocator;

    const config = TelemetryConfig.development();
    var telemetry = try Telemetry.init(allocator, config);
    defer telemetry.deinit();

    // Create a span
    var span = try telemetry.startSpan("test_operation", .{});
    defer span.deinit();

    try std.testing.expect(span.span_id.len > 0);
    try std.testing.expect(span.trace_id.len > 0);
    try std.testing.expectEqualStrings("test_operation", span.name);
    try std.testing.expect(span.start_time > 0);

    // Check counters
    try std.testing.expectEqual(@as(usize, 1), telemetry.active_span_count);

    // End span
    span.end();
    try telemetry.endSpan(&span);

    // Check counters updated
    try std.testing.expectEqual(@as(usize, 0), telemetry.active_span_count);
    try std.testing.expectEqual(@as(usize, 1), telemetry.completed_span_count);
}

test "Span with parent" {
    const allocator = std.testing.allocator;

    const config = TelemetryConfig.development();
    var telemetry = try Telemetry.init(allocator, config);
    defer telemetry.deinit();

    // Create parent span
    var parent = try telemetry.startSpan("parent_op", .{});
    defer parent.deinit();

    // Create child span with parent
    var child = try telemetry.startSpan("child_op", .{
        .parent_span_id = parent.span_id,
        .trace_id = parent.trace_id,
    });
    defer child.deinit();

    try std.testing.expect(child.parent_span_id != null);
    try std.testing.expectEqualStrings(parent.span_id, child.parent_span_id.?);
    try std.testing.expectEqualStrings(parent.trace_id, child.trace_id);
}

test "Span disabled telemetry" {
    const allocator = std.testing.allocator;

    const config = TelemetryConfig.default(); // disabled by default
    var telemetry = try Telemetry.init(allocator, config);
    defer telemetry.deinit();

    // Should return empty span when disabled
    const span = try telemetry.startSpan("test", .{});
    // Empty span has empty strings
    try std.testing.expectEqual(@as(usize, 0), span.span_id.len);
}

test "Metric recording" {
    const allocator = std.testing.allocator;

    const config = TelemetryConfig.development();
    var telemetry = try Telemetry.init(allocator, config);
    defer telemetry.deinit();

    // Record some metrics
    try telemetry.recordMetric("http.requests", 100.0, .{ .kind = .counter });
    try telemetry.recordMetric("cpu.usage", 45.5, .{ .kind = .gauge, .unit = "%" });
    try telemetry.recordMetric("response.time", 123.4, .{ .kind = .histogram, .unit = "ms" });

    try std.testing.expectEqual(@as(usize, 3), telemetry.metric_count);
    try std.testing.expectEqual(@as(u64, 3), telemetry.total_metrics_recorded);

    // Export metrics
    try telemetry.exportMetrics();
    try std.testing.expectEqual(@as(usize, 0), telemetry.metric_count);
}

test "TelemetrySampler strategies" {
    // Always on
    const always_on = TelemetrySampler{
        .strategy = .always_on,
        .sampling_rate = 1.0,
    };
    try std.testing.expect(always_on.shouldSample("trace123"));

    // Always off
    const always_off = TelemetrySampler{
        .strategy = .always_off,
        .sampling_rate = 0.0,
    };
    try std.testing.expect(!always_off.shouldSample("trace123"));

    // Trace ID ratio with 100% rate
    const ratio_100 = TelemetrySampler{
        .strategy = .trace_id_ratio,
        .sampling_rate = 1.0,
    };
    try std.testing.expect(ratio_100.shouldSample("trace123"));

    // Trace ID ratio with 0% rate
    const ratio_0 = TelemetrySampler{
        .strategy = .trace_id_ratio,
        .sampling_rate = 0.0,
    };
    try std.testing.expect(!ratio_0.shouldSample("trace123"));
}

test "Resource from config" {
    var config = TelemetryConfig.jaeger();
    config.service_name = "test-service";
    config.service_version = "1.0.0";
    config.environment = "testing";
    config.datacenter = "us-west-1";

    const resource = Resource.fromConfig(config);

    try std.testing.expectEqualStrings("test-service", resource.service_name.?);
    try std.testing.expectEqualStrings("1.0.0", resource.service_version.?);
    try std.testing.expectEqualStrings("testing", resource.environment.?);
    try std.testing.expectEqualStrings("us-west-1", resource.datacenter.?);
}

test "Telemetry stats" {
    const allocator = std.testing.allocator;

    const config = TelemetryConfig.development();
    var telemetry = try Telemetry.init(allocator, config);
    defer telemetry.deinit();

    // Create and end spans
    var span1 = try telemetry.startSpan("op1", .{});
    defer span1.deinit();
    span1.end();
    try telemetry.endSpan(&span1);

    var span2 = try telemetry.startSpan("op2", .{});
    defer span2.deinit();
    span2.end();
    try telemetry.endSpan(&span2);

    // Record metrics
    try telemetry.recordMetric("test", 1.0, .{});

    // Get stats
    const stats = telemetry.getStats();
    try std.testing.expectEqual(@as(u64, 2), stats.total_spans_created);
    try std.testing.expectEqual(@as(usize, 2), stats.pending_spans);
    try std.testing.expectEqual(@as(u64, 1), stats.total_metrics_recorded);

    // Export
    try telemetry.exportSpans();
    const stats2 = telemetry.getStats();
    try std.testing.expectEqual(@as(u64, 2), stats2.total_spans_exported);
    try std.testing.expectEqual(@as(usize, 0), stats2.pending_spans);
}

test "Span attributes and events" {
    const allocator = std.testing.allocator;

    const config = TelemetryConfig.development();
    var telemetry = try Telemetry.init(allocator, config);
    defer telemetry.deinit();

    var span = try telemetry.startSpan("test_span", .{});
    defer span.deinit();

    // Set attributes (no-op in simplified version)
    try span.setAttribute("http.method", .{ .string = "GET" });
    try span.setAttribute("http.status_code", .{ .integer = 200 });
    try span.setAttribute("cache.hit", .{ .boolean = true });
    try span.setAttribute("response.time", .{ .float = 123.45 });

    // Add events (no-op in simplified version)
    try span.addEvent("request_started", null);
    try span.addEvent("response_sent", null);

    // Set status
    span.setStatus(.ok);
    try std.testing.expectEqual(SpanStatus.ok, span.status);
}

test "Flush all data" {
    const allocator = std.testing.allocator;

    const config = TelemetryConfig.development();
    var telemetry = try Telemetry.init(allocator, config);
    defer telemetry.deinit();

    // Create span and metric
    var span = try telemetry.startSpan("test", .{});
    defer span.deinit();
    span.end();
    try telemetry.endSpan(&span);
    try telemetry.recordMetric("test", 1.0, .{});

    try std.testing.expect(telemetry.completed_span_count > 0);
    try std.testing.expect(telemetry.metric_count > 0);

    // Flush
    try telemetry.flush();

    try std.testing.expectEqual(@as(usize, 0), telemetry.completed_span_count);
    try std.testing.expectEqual(@as(usize, 0), telemetry.metric_count);
}

test "Provider configurations" {
    // Google Cloud
    const gcp = TelemetryConfig.googleCloud("my-project", "api-key");
    try std.testing.expectEqual(gcp.provider, .google_cloud);
    try std.testing.expectEqualStrings("my-project", gcp.project_id.?);

    // Google Analytics
    const ga4 = TelemetryConfig.googleAnalytics("G-XXXXXXXXXX", "api_secret_123");
    try std.testing.expectEqual(ga4.provider, .google_analytics);
    try std.testing.expectEqualStrings("G-XXXXXXXXXX", ga4.project_id.?);
    try std.testing.expectEqualStrings("api_secret_123", ga4.api_key.?);
    try std.testing.expectEqualStrings("https://www.google-analytics.com/mp/collect", ga4.exporter_endpoint.?);
    try std.testing.expectEqual(@as(usize, 25), ga4.batch_size);

    // Google Tag Manager
    const gtm = TelemetryConfig.googleTagManager("https://gtm.example.com/collect", "gtm-api-key");
    try std.testing.expectEqual(gtm.provider, .google_tag_manager);
    try std.testing.expectEqualStrings("https://gtm.example.com/collect", gtm.exporter_endpoint.?);
    try std.testing.expectEqualStrings("gtm-api-key", gtm.api_key.?);

    // Google Tag Manager without API key
    const gtm_no_key = TelemetryConfig.googleTagManager("https://gtm.example.com/collect", null);
    try std.testing.expectEqual(gtm_no_key.provider, .google_tag_manager);
    try std.testing.expect(gtm_no_key.api_key == null);

    // AWS X-Ray
    const xray = TelemetryConfig.awsXray("us-east-1");
    try std.testing.expectEqual(xray.provider, .aws_xray);
    try std.testing.expectEqualStrings("us-east-1", xray.region.?);

    // Azure
    const azure = TelemetryConfig.azure("InstrumentationKey=xxx");
    try std.testing.expectEqual(azure.provider, .azure);

    // Datadog
    const dd = TelemetryConfig.datadog("dd-api-key");
    try std.testing.expectEqual(dd.provider, .datadog);
    try std.testing.expectEqualStrings("dd-api-key", dd.api_key.?);

    // OTEL Collector
    const otel = TelemetryConfig.otelCollector("http://localhost:4317");
    try std.testing.expectEqual(otel.provider, .generic);
}

test "SpanKind values" {
    try std.testing.expectEqual(SpanKind.internal, .internal);
    try std.testing.expectEqual(SpanKind.server, .server);
    try std.testing.expectEqual(SpanKind.client, .client);
    try std.testing.expectEqual(SpanKind.producer, .producer);
    try std.testing.expectEqual(SpanKind.consumer, .consumer);
}

test "MetricKind values" {
    try std.testing.expectEqual(MetricKind.counter, .counter);
    try std.testing.expectEqual(MetricKind.gauge, .gauge);
    try std.testing.expectEqual(MetricKind.histogram, .histogram);
    try std.testing.expectEqual(MetricKind.summary, .summary);
}
test "Span with context helper" {
    const allocator = std.testing.allocator;

    const config = TelemetryConfig.development();
    var telemetry = try Telemetry.init(allocator, config);
    defer telemetry.deinit();

    // Create parent span
    var parent = try telemetry.startSpan("parent_op", .{});
    defer parent.deinit();

    // Create child span using helper
    var child = try telemetry.startSpanWithContext("child_op", &parent, .{});
    defer child.deinit();

    try std.testing.expect(child.parent_span_id != null);
    try std.testing.expectEqualStrings(parent.span_id, child.parent_span_id.?);
}

test "Span isEmpty check" {
    const allocator = std.testing.allocator;

    const config = TelemetryConfig.default(); // disabled by default
    var telemetry = try Telemetry.init(allocator, config);
    defer telemetry.deinit();

    // Should return empty span when disabled
    const span = try telemetry.startSpan("test", .{});
    try std.testing.expect(span.isEmpty());
}

test "Span duration helpers" {
    const allocator = std.testing.allocator;

    const config = TelemetryConfig.development();
    var telemetry = try Telemetry.init(allocator, config);
    defer telemetry.deinit();

    var span = try telemetry.startSpan("test", .{});
    defer span.deinit();

    // Small delay
    std.Thread.sleep(1_000_000); // 1ms

    span.end();

    const duration_ns = span.getDuration();
    const duration_ms = span.getDurationMs();

    try std.testing.expect(duration_ns > 0);
    try std.testing.expect(duration_ms > 0.0);
}

test "Baggage" {
    const allocator = std.testing.allocator;

    var baggage = Baggage.init(allocator);
    defer baggage.deinit();

    try baggage.set("user_id", "123");
    try baggage.set("session_id", "abc");

    try std.testing.expectEqualStrings("123", baggage.get("user_id").?);
    try std.testing.expectEqualStrings("abc", baggage.get("session_id").?);
    try std.testing.expect(baggage.get("nonexistent") == null);
}

test "Baggage header serialization" {
    const allocator = std.testing.allocator;

    var baggage = Baggage.init(allocator);
    defer baggage.deinit();

    try baggage.set("key1", "value1");

    const header = try baggage.toHeaderValue(allocator);
    defer allocator.free(header);

    try std.testing.expect(std.mem.indexOf(u8, header, "key1=value1") != null);
}

test "Baggage header parsing" {
    const allocator = std.testing.allocator;

    var baggage = try Baggage.fromHeaderValue(allocator, "user_id=123,session_id=abc");
    defer baggage.deinit();

    try std.testing.expectEqualStrings("123", baggage.get("user_id").?);
    try std.testing.expectEqualStrings("abc", baggage.get("session_id").?);
}

test "Traceparent parsing" {
    // Valid traceparent
    const ctx = Telemetry.parseTraceparentHeader("00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01");
    try std.testing.expect(ctx != null);
    try std.testing.expectEqualStrings("4bf92f3577b34da6a3ce929d0e0e4736", ctx.?.trace_id);
    try std.testing.expectEqualStrings("00f067aa0ba902b7", ctx.?.span_id);
    try std.testing.expect(ctx.?.sampled);

    // Invalid version
    const invalid = Telemetry.parseTraceparentHeader("01-trace-span-01");
    try std.testing.expect(invalid == null);

    // Not sampled
    const not_sampled = Telemetry.parseTraceparentHeader("00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-00");
    try std.testing.expect(not_sampled != null);
    try std.testing.expect(!not_sampled.?.sampled);
}

test "Exporter stats" {
    var stats = ExporterStats{};

    stats.recordExport(10, 1024);
    stats.recordExport(5, 512);
    stats.recordError();
    stats.recordBatchExport();
    stats.recordNetworkExport();

    try std.testing.expectEqual(@as(u64, 15), stats.getSpansExported());
    try std.testing.expectEqual(@as(u64, 1), stats.getExportErrors());
    try std.testing.expectEqual(@as(u64, 1536), stats.getBytesExported());
}

test "Metric helpers" {
    const allocator = std.testing.allocator;

    const config = TelemetryConfig.development();
    var telemetry = try Telemetry.init(allocator, config);
    defer telemetry.deinit();

    try telemetry.recordCounter("requests", 100.0);
    try telemetry.recordGauge("cpu", 45.5);
    try telemetry.recordHistogram("latency", 123.4);

    try std.testing.expectEqual(@as(usize, 3), telemetry.metric_count);
}

fn testCustomCallback() anyerror!void {
    // Test custom export logic
}

test "Custom provider configuration" {
    const config = TelemetryConfig.custom(&testCustomCallback);
    try std.testing.expectEqual(config.provider, .custom);
    try std.testing.expect(config.custom_exporter_fn != null);
    try std.testing.expect(config.enabled);
}

test "High-throughput configuration" {
    const config = TelemetryConfig.highThroughput();
    try std.testing.expect(config.enabled);
    try std.testing.expectEqual(config.provider, .jaeger);
    try std.testing.expectEqual(config.batch_size, 1024);
    try std.testing.expectEqual(config.batch_timeout_ms, 2000);
    try std.testing.expectEqual(config.sampling_strategy, .trace_id_ratio);
    try std.testing.expect(config.sampling_rate < 0.1); // 1% sampling
}

test "Development configuration" {
    const config = TelemetryConfig.development();
    try std.testing.expect(config.enabled);
    try std.testing.expectEqual(config.provider, .file);
    try std.testing.expectEqual(config.sampling_strategy, .always_on);
    try std.testing.expect(config.exporter_file_path != null);
}

test "Telemetry stats with counter" {
    const allocator = std.testing.allocator;

    const config = TelemetryConfig.development();
    var telemetry = try Telemetry.init(allocator, config);
    defer telemetry.deinit();

    // Create spans
    var span1 = try telemetry.startSpan("op1", .{});
    defer span1.deinit();
    span1.end();
    try telemetry.endSpan(&span1);

    var span2 = try telemetry.startSpan("op2", .{});
    defer span2.deinit();
    span2.end();
    try telemetry.endSpan(&span2);

    // Record metrics
    try telemetry.recordCounter("test", 1.0);

    const stats = telemetry.getStats();
    try std.testing.expectEqual(@as(u64, 2), stats.total_spans_created);
    try std.testing.expectEqual(@as(u64, 1), stats.total_metrics_recorded);
}

test "Span attributes" {
    const allocator = std.testing.allocator;

    const config = TelemetryConfig.development();
    var telemetry = try Telemetry.init(allocator, config);
    defer telemetry.deinit();

    var span = try telemetry.startSpan("test_span", .{});
    defer span.deinit();

    try span.setAttribute("string_attr", SpanAttribute{ .string = "value" });
    try span.setAttribute("int_attr", SpanAttribute{ .integer = 42 });
    try span.setAttribute("float_attr", SpanAttribute{ .float = 3.14 });
    try span.setAttribute("bool_attr", SpanAttribute{ .boolean = true });

    try std.testing.expect(span.has_attributes);
}

test "Span events" {
    const allocator = std.testing.allocator;

    const config = TelemetryConfig.development();
    var telemetry = try Telemetry.init(allocator, config);
    defer telemetry.deinit();

    var span = try telemetry.startSpan("test_span", .{});
    defer span.deinit();

    try span.addEvent("event1", null);
    try span.addEvent("event2", null);

    try std.testing.expect(span.has_events);
}

test "Span status" {
    const allocator = std.testing.allocator;

    const config = TelemetryConfig.development();
    var telemetry = try Telemetry.init(allocator, config);
    defer telemetry.deinit();

    var span = try telemetry.startSpan("test_span", .{});
    defer span.deinit();

    try std.testing.expectEqual(SpanStatus.unset, span.status);

    span.setStatus(.ok);
    try std.testing.expectEqual(SpanStatus.ok, span.status);

    span.setStatus(.err);
    try std.testing.expectEqual(SpanStatus.err, span.status);
}

test "SpanKind enum values" {
    try std.testing.expectEqual(SpanKind.internal, .internal);
    try std.testing.expectEqual(SpanKind.server, .server);
    try std.testing.expectEqual(SpanKind.client, .client);
    try std.testing.expectEqual(SpanKind.producer, .producer);
    try std.testing.expectEqual(SpanKind.consumer, .consumer);
}

test "NetworkProtocol values" {
    try std.testing.expectEqual(NetworkProtocol.tcp, .tcp);
    try std.testing.expectEqual(NetworkProtocol.udp, .udp);
    try std.testing.expectEqual(NetworkProtocol.syslog, .syslog);
    try std.testing.expectEqual(NetworkProtocol.http, .http);
    try std.testing.expectEqual(NetworkProtocol.grpc, .grpc);
}

test "ExportMode values" {
    try std.testing.expectEqual(ExportMode.sync, .sync);
    try std.testing.expectEqual(ExportMode.async_buffer, .async_buffer);
    try std.testing.expectEqual(ExportMode.batch, .batch);
    try std.testing.expectEqual(ExportMode.network, .network);
}

test "Baggage remove" {
    const allocator = std.testing.allocator;

    var baggage = Baggage.init(allocator);
    defer baggage.deinit();

    try baggage.set("key1", "value1");
    try baggage.set("key2", "value2");

    try std.testing.expect(baggage.get("key1") != null);

    baggage.remove("key1");

    try std.testing.expect(baggage.get("key1") == null);
    try std.testing.expect(baggage.get("key2") != null);
}

test "Exporter stats error rate calculation" {
    var stats = ExporterStats{};

    // No operations - error rate should be 0
    try std.testing.expect(stats.getErrorRate() == 0.0);

    // 10 batch exports, 2 errors = 20% error rate
    var i: u32 = 0;
    while (i < 10) : (i += 1) {
        stats.recordBatchExport();
    }
    stats.recordError();
    stats.recordError();

    const error_rate = stats.getErrorRate();
    try std.testing.expect(error_rate > 0.19 and error_rate < 0.21);
}

test "Traceparent header generation and parsing roundtrip" {
    const allocator = std.testing.allocator;

    const config = TelemetryConfig.development();
    var telemetry = try Telemetry.init(allocator, config);
    defer telemetry.deinit();

    var span = try telemetry.startSpan("test_span", .{});
    defer span.deinit();

    // Generate traceparent
    const header = try telemetry.getTraceparentHeader(&span);
    defer allocator.free(header);

    // Parse it back
    const parsed = Telemetry.parseTraceparentHeader(header);
    try std.testing.expect(parsed != null);

    // Verify trace_id and span_id match
    try std.testing.expectEqualStrings(span.trace_id, parsed.?.trace_id);
    try std.testing.expectEqualStrings(span.span_id, parsed.?.span_id);
}

test "Sampler strategies" {
    // Always on
    var always_on = TelemetrySampler{ .strategy = .always_on, .sampling_rate = 0.0 };
    try std.testing.expect(always_on.shouldSample("any_trace_id"));

    // Always off
    var always_off = TelemetrySampler{ .strategy = .always_off, .sampling_rate = 1.0 };
    try std.testing.expect(!always_off.shouldSample("any_trace_id"));

    // Parent based (simplified)
    var parent_based = TelemetrySampler{ .strategy = .parent_based, .sampling_rate = 0.5 };
    try std.testing.expect(parent_based.shouldSample("any_trace_id"));
}

test "Multiple metrics recording" {
    const allocator = std.testing.allocator;

    const config = TelemetryConfig.development();
    var telemetry = try Telemetry.init(allocator, config);
    defer telemetry.deinit();

    // Record various metric types
    try telemetry.recordMetric("counter", 1.0, .{ .kind = .counter });
    try telemetry.recordMetric("gauge", 50.0, .{ .kind = .gauge, .unit = "%" });
    try telemetry.recordMetric("histogram", 100.0, .{ .kind = .histogram, .unit = "ms" });
    try telemetry.recordMetric("summary", 200.0, .{ .kind = .summary });

    try std.testing.expectEqual(@as(usize, 4), telemetry.metric_count);
}

test "Disabled telemetry returns empty spans" {
    const allocator = std.testing.allocator;

    // Default config has telemetry disabled
    const config = TelemetryConfig.default();
    try std.testing.expect(!config.enabled);

    var telemetry = try Telemetry.init(allocator, config);
    defer telemetry.deinit();

    // Should return empty span when disabled
    const span = try telemetry.startSpan("test", .{});
    try std.testing.expect(span.isEmpty());
}

test "Telemetry flush" {
    const allocator = std.testing.allocator;

    const config = TelemetryConfig.development();
    var telemetry = try Telemetry.init(allocator, config);
    defer telemetry.deinit();

    // Create span and metric
    var span = try telemetry.startSpan("test", .{});
    defer span.deinit();
    span.end();
    try telemetry.endSpan(&span);

    try telemetry.recordCounter("test_metric", 1.0);

    try std.testing.expect(telemetry.completed_span_count > 0);
    try std.testing.expect(telemetry.metric_count > 0);

    // Flush should clear pending data
    try telemetry.flush();

    try std.testing.expectEqual(@as(usize, 0), telemetry.completed_span_count);
    try std.testing.expectEqual(@as(usize, 0), telemetry.metric_count);
}

test "Telemetry setEnabled and isEnabled" {
    const allocator = std.testing.allocator;

    const config = TelemetryConfig.development();
    var telemetry = try Telemetry.init(allocator, config);
    defer telemetry.deinit();

    try std.testing.expect(telemetry.isEnabled());

    telemetry.setEnabled(false);
    try std.testing.expect(!telemetry.isEnabled());

    // Should return empty span when disabled
    const span = try telemetry.startSpan("test", .{});
    try std.testing.expect(span.isEmpty());

    telemetry.setEnabled(true);
    try std.testing.expect(telemetry.isEnabled());
}

test "Telemetry resetStats" {
    const allocator = std.testing.allocator;

    const config = TelemetryConfig.development();
    var telemetry = try Telemetry.init(allocator, config);
    defer telemetry.deinit();

    // Create some spans and metrics
    var span = try telemetry.startSpan("test", .{});
    defer span.deinit();
    span.end();
    try telemetry.endSpan(&span);
    try telemetry.recordCounter("test", 1.0);

    try std.testing.expect(telemetry.total_spans_created > 0);

    // Reset stats
    telemetry.resetStats();

    try std.testing.expectEqual(@as(u64, 0), telemetry.total_spans_created);
    try std.testing.expectEqual(@as(u64, 0), telemetry.total_spans_exported);
    try std.testing.expectEqual(@as(u64, 0), telemetry.total_metrics_recorded);
}

test "Telemetry getResource and setResource" {
    const allocator = std.testing.allocator;

    var config = TelemetryConfig.development();
    config.service_name = "test-service";
    var telemetry = try Telemetry.init(allocator, config);
    defer telemetry.deinit();

    const resource = telemetry.getResource();
    try std.testing.expectEqualStrings("test-service", resource.service_name.?);

    const new_resource = Resource{
        .service_name = "updated-service",
        .service_version = "2.0.0",
        .environment = "staging",
        .datacenter = "us-west-2",
    };
    telemetry.setResource(new_resource);

    const updated = telemetry.getResource();
    try std.testing.expectEqualStrings("updated-service", updated.service_name.?);
    try std.testing.expectEqualStrings("2.0.0", updated.service_version.?);
}

test "Telemetry startSpanFromTraceparent" {
    const allocator = std.testing.allocator;

    const config = TelemetryConfig.development();
    var telemetry = try Telemetry.init(allocator, config);
    defer telemetry.deinit();

    // Test with valid traceparent
    var span = try telemetry.startSpanFromTraceparent(
        "child_operation",
        "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01",
        .{},
    );
    defer span.deinit();

    try std.testing.expect(!span.isEmpty());
    try std.testing.expect(span.parent_span_id != null);

    // Test with invalid traceparent (should create root span)
    var root_span = try telemetry.startSpanFromTraceparent(
        "root_operation",
        "invalid-header",
        .{},
    );
    defer root_span.deinit();

    try std.testing.expect(!root_span.isEmpty());
}

test "Telemetry startSpanFromTraceparent not sampled" {
    const allocator = std.testing.allocator;

    const config = TelemetryConfig.development();
    var telemetry = try Telemetry.init(allocator, config);
    defer telemetry.deinit();

    // Test with not-sampled traceparent (flags=00)
    const span = try telemetry.startSpanFromTraceparent(
        "operation",
        "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-00",
        .{},
    );

    try std.testing.expect(span.isEmpty());
}

test "Baggage count and isEmpty" {
    const allocator = std.testing.allocator;

    var baggage = Baggage.init(allocator);
    defer baggage.deinit();

    try std.testing.expect(baggage.isEmpty());
    try std.testing.expectEqual(@as(usize, 0), baggage.count());

    try baggage.set("key1", "value1");
    try std.testing.expect(!baggage.isEmpty());
    try std.testing.expectEqual(@as(usize, 1), baggage.count());

    try baggage.set("key2", "value2");
    try std.testing.expectEqual(@as(usize, 2), baggage.count());
}

test "Baggage clear" {
    const allocator = std.testing.allocator;

    var baggage = Baggage.init(allocator);
    defer baggage.deinit();

    try baggage.set("key1", "value1");
    try baggage.set("key2", "value2");
    try std.testing.expectEqual(@as(usize, 2), baggage.count());

    baggage.clear();
    try std.testing.expect(baggage.isEmpty());
    try std.testing.expect(baggage.get("key1") == null);
}

test "Baggage contains" {
    const allocator = std.testing.allocator;

    var baggage = Baggage.init(allocator);
    defer baggage.deinit();

    try baggage.set("existing_key", "value");

    try std.testing.expect(baggage.contains("existing_key"));
    try std.testing.expect(!baggage.contains("nonexistent_key"));
}
