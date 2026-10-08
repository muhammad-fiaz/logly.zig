//! OpenTelemetry support.
//!
//! Distributed tracing spans, metrics, W3C propagation, and OTLP-style export.
const std = @import("std");
const utils = @import("utils.zig");
const Utils = utils;
const configModule = @import("config.zig");
const Network = @import("network.zig");
const Constants = @import("constants.zig");
const Version = @import("version.zig");

/// Re-export TelemetryConfig from config module for convenience
pub const TelemetryConfig = configModule.TelemetryConfig;

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
    asyncBuffer,
    /// Batch export with configurable size
    batch,
    /// Network export (TCP/UDP)
    network,
};

/// Exporter statistics for monitoring export performance
pub const ExporterStats = struct {
    spansExported: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
    metricsExported: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
    exportErrors: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
    bytesSent: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
    lastExportTimeNs: std.atomic.Value(Constants.AtomicSigned) = std.atomic.Value(Constants.AtomicSigned).init(0),
    batchExports: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
    networkExports: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),

    pub fn recordExport(self: *ExporterStats, spans: u64, bytes: u64) void {
        _ = self.spansExported.fetchAdd(@truncate(spans), .monotonic);
        _ = self.bytesSent.fetchAdd(@truncate(bytes), .monotonic);

        if (Constants.AtomicSigned == i32) {
            // Use seconds for 32-bit systems to avoid overflow (valid until 2038)
            self.lastExportTimeNs.store(@truncate(utils.currentSeconds()), .monotonic);
        } else {
            self.lastExportTimeNs.store(@truncate(utils.currentNanos()), .monotonic);
        }
    }

    pub fn recordBatchExport(self: *ExporterStats) void {
        _ = self.batchExports.fetchAdd(1, .monotonic);
    }

    pub fn recordNetworkExport(self: *ExporterStats) void {
        _ = self.networkExports.fetchAdd(1, .monotonic);
    }

    pub fn recordError(self: *ExporterStats) void {
        _ = self.exportErrors.fetchAdd(1, .monotonic);
    }

    pub fn recordMetricExport(self: *ExporterStats, count: u64) void {
        _ = self.metricsExported.fetchAdd(@truncate(count), .monotonic);
    }

    pub fn getSpansExported(self: *const ExporterStats) u64 {
        return self.spansExported.load(.monotonic);
    }

    pub fn getMetricsExported(self: *const ExporterStats) u64 {
        return self.metricsExported.load(.monotonic);
    }

    pub fn getExportErrors(self: *const ExporterStats) u64 {
        return self.exportErrors.load(.monotonic);
    }

    pub fn getBytesExported(self: *const ExporterStats) u64 {
        return self.bytesSent.load(.monotonic);
    }

    pub fn getBatchExports(self: *const ExporterStats) u64 {
        return self.batchExports.load(.monotonic);
    }

    pub fn getNetworkExports(self: *const ExporterStats) u64 {
        return self.networkExports.load(.monotonic);
    }

    pub fn getLastExportTimeNs(self: *const ExporterStats) i64 {
        const val = self.lastExportTimeNs.load(.monotonic);
        if (Constants.AtomicSigned == i32) {
            return @as(i64, val) * @as(i64, @intCast(Constants.TimeConstants.nsPerSecond));
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
    pub fn throughputBytesPerSecond(self: *const ExporterStats, elapsedSeconds: f64) f64 {
        return utils.safeFloatDiv(
            @as(f64, @floatFromInt(self.getBytesExported())),
            elapsedSeconds,
        );
    }

    /// Calculate total exports (batch + network).
    pub fn getTotalExports(self: *const ExporterStats) u64 {
        return self.getBatchExports() + self.getNetworkExports();
    }

    /// Reset all statistics to initial state.
    pub fn reset(self: *ExporterStats) void {
        self.spansExported.store(0, .monotonic);
        self.metricsExported.store(0, .monotonic);
        self.exportErrors.store(0, .monotonic);
        self.bytesSent.store(0, .monotonic);
        self.lastExportTimeNs.store(0, .monotonic);
        self.batchExports.store(0, .monotonic);
        self.networkExports.store(0, .monotonic);
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
    /// Snapshot of the currently active sampling configuration.
    pub const SamplingSnapshot = struct {
        strategy: TelemetryConfig.SamplingStrategy,
        rate: f64,
    };

    /// Runtime context propagation header names.
    pub const ContextHeaders = struct {
        traceHeader: []const u8,
        baggageHeader: []const u8,
    };

    /// Input payload for batch metric recording.
    pub const MetricInput = struct {
        name: []const u8,
        value: f64,
        options: MetricOptions = .{},
    };

    /// Input payload for batch log recording.
    pub const TelemetryLog = struct {
        timeNs: i64,
        dataJson: []const u8,
    };

    allocator: std.mem.Allocator,
    config: TelemetryConfig,
    enabled: bool,

    // Span storage using ArrayList for actual storage
    spans: std.ArrayList(Span),
    completedSpans: std.ArrayList(Span),

    // Metrics storage
    metrics: std.ArrayList(Metric),

    // Logs storage
    logs: std.ArrayList(TelemetryLog),

    // Span counts
    activeSpanCount: usize = 0,
    completedSpanCount: usize = 0,
    metricCount: usize = 0,

    // Resource information
    resource: Resource,

    // Sampler instance
    sampler: TelemetrySampler,

    // Thread safety
    mutex: std.Io.Mutex = std.Io.Mutex.init,

    // Statistics
    totalSpansCreated: u64 = 0,
    totalSpansExported: u64 = 0,
    totalMetricsRecorded: u64 = 0,

    // Exporter stats (advanced stats with utils helpers)
    exporterStats: ExporterStats = .{},

    // Callbacks (from config)
    onSpanStart: ?*const fn ([]const u8, []const u8) void,
    onSpanEnd: ?*const fn ([]const u8, u64) void,
    onMetricRecorded: ?*const fn ([]const u8, f64) void,
    onError: ?*const fn ([]const u8) void,

    // Network connection for network export mode
    networkSocket: ?std.Io.net.Socket = null,
    networkAddress: ?std.Io.net.IpAddress = null,

    // Batch buffer for batch export mode
    batchBuffer: std.ArrayList(u8),
    lastBatchExport: i64 = 0,
    lastLogExport: i64 = 0,

    /// Initializes OpenTelemetry telemetry system
    pub fn init(allocator: std.mem.Allocator, config: TelemetryConfig) !Telemetry {
        var telemetry = Telemetry{
            .allocator = allocator,
            .config = config,
            .enabled = config.enabled,
            .spans = .empty,
            .completedSpans = .empty,
            .metrics = .empty,
            .logs = .empty,
            .batchBuffer = .empty,
            .resource = Resource.fromConfig(config),
            .sampler = TelemetrySampler.init(config),
            .onSpanStart = config.onSpanStart,
            .onSpanEnd = config.onSpanEnd,
            .onMetricRecorded = config.onMetricRecorded,
            .onError = config.onError,
        };

        // Initialize ArrayLists with proper allocator
        telemetry.spans = std.ArrayList(Span).initCapacity(allocator, 32) catch .empty;
        telemetry.completedSpans = std.ArrayList(Span).initCapacity(allocator, 32) catch .empty;
        telemetry.metrics = std.ArrayList(Metric).initCapacity(allocator, 32) catch .empty;
        telemetry.logs = std.ArrayList(TelemetryLog).initCapacity(allocator, 32) catch .empty;
        telemetry.batchBuffer = std.ArrayList(u8).initCapacity(allocator, Constants.BufferSizes.telemetry) catch .empty;

        // Initialize network connection if using network export
        if (config.enabled and config.exporterEndpoint != null) {
            telemetry.initNetworkExport() catch {
                if (config.onError) |callback| {
                    callback("Failed to initialize network export");
                }
            };
        }

        return telemetry;
    }

    /// Initialize network export connection using Network module
    fn initNetworkExport(self: *Telemetry) !void {
        const endpoint = self.config.exporterEndpoint orelse return;

        // Check if TCP or UDP based on endpoint prefix
        if (std.mem.startsWith(u8, endpoint, "tcp://")) {
            // TCP connection handled on-demand
        } else if (std.mem.startsWith(u8, endpoint, "udp://")) {
            const result = try Network.createUdpSocket(self.allocator, endpoint);
            self.networkSocket = result.socket;
            self.networkAddress = result.address;
        }
    }

    /// Cleans up resources
    pub fn deinit(self: *Telemetry) void {
        // Close network socket if open
        if (self.networkSocket) |socket| {
            socket.close(Utils.io());
            self.networkSocket = null;
        }

        self.mutex.lockUncancelable(utils.io());
        defer self.mutex.unlock(utils.io());

        // Free all active spans
        for (self.spans.items) |*span| {
            span.deinit();
        }
        self.spans.deinit(self.allocator);

        // Free all completed spans
        for (self.completedSpans.items) |*span| {
            span.deinit();
        }
        self.completedSpans.deinit(self.allocator);

        // Free all metrics
        for (self.metrics.items) |metric| {
            self.allocator.free(metric.name);
        }
        self.metrics.deinit(self.allocator);

        // Free all logs
        for (self.logs.items) |log| {
            self.allocator.free(log.dataJson);
        }
        self.logs.deinit(self.allocator);

        // Free batch buffer
        self.batchBuffer.deinit(self.allocator);

        // Reset counters
        self.activeSpanCount = 0;
        self.completedSpanCount = 0;
        self.metricCount = 0;
    }

    /// Starts a new span
    pub fn startSpan(self: *Telemetry, name: []const u8, opts: SpanOptions) !Span {
        if (!self.enabled) return Span.empty(self.allocator);

        self.mutex.lockUncancelable(utils.io());
        defer self.mutex.unlock(utils.io());

        // Generate IDs using utils
        const spanId = try utils.generateSpanId(self.allocator);
        const traceId = if (opts.traceId) |tid|
            try self.allocator.dupe(u8, tid)
        else
            try utils.generateTraceId(self.allocator);

        // Check sampling decision using utils
        if (!self.sampler.shouldSample(traceId)) {
            self.allocator.free(spanId);
            self.allocator.free(traceId);
            return Span.empty(self.allocator);
        }

        self.activeSpanCount += 1;
        self.totalSpansCreated += 1;

        const span = Span{
            .allocator = self.allocator,
            .spanId = spanId,
            .traceId = traceId,
            .parentSpanId = if (opts.parentSpanId) |pid| try self.allocator.dupe(u8, pid) else null,
            .name = try self.allocator.dupe(u8, name),
            .startTime = utils.currentNanos(),
            .kind = opts.kind orelse .internal,
        };

        // Invoke callback
        if (self.onSpanStart) |callback| {
            callback(spanId, name);
        }

        return span;
    }

    /// Ends a span and marks it for export.
    /// Takes ownership of the span's allocated resources to safely batch them.
    /// The input span becomes empty after this call.
    pub fn endSpan(self: *Telemetry, span: *Span) !void {
        if (!self.enabled or span.isEmpty()) return;

        self.mutex.lockUncancelable(utils.io());
        defer self.mutex.unlock(utils.io());

        span.endTime = utils.currentNanos();

        // Calculate duration using utils helper
        const durationNs = utils.durationSinceNs(span.startTime);

        // Add to completed spans list for export
        try self.completedSpans.append(self.allocator, span.*);

        // Use the span in the list for callback to ensure it's still valid
        const storedSpanId = self.completedSpans.items[self.completedSpans.items.len - 1].spanId;

        // Nullify original span so caller's deinit() is safe (no double-free)
        // We moved ownership of the strings and lists to Telemetry
        const originalAllocator = span.allocator;
        span.* = Span.empty(originalAllocator);

        if (self.activeSpanCount > 0) {
            self.activeSpanCount -= 1;
        }
        self.completedSpanCount += 1;

        // Invoke callback
        if (self.onSpanEnd) |callback| {
            callback(storedSpanId, durationNs);
        }

        // Handle export strategy: only trigger batch export automatically when using the batch processor.
        // In 'simple' mode spans are kept pending until an explicit export/flush is requested by the user.
        if (self.config.spanProcessorType == .batch and self.completedSpanCount >= self.config.batchSize) {
            self.triggerBatchExport() catch {};
        }
    }

    /// Trigger batch export based on config
    fn triggerBatchExport(self: *Telemetry) !void {
        const now = utils.currentSeconds();
        const elapsedMs: u64 = if (now > self.lastBatchExport)
            @intCast(now - self.lastBatchExport)
        else
            0;

        if (elapsedMs >= self.config.batchTimeoutMs or
            self.completedSpanCount >= self.config.batchSize)
        {
            try self.exportSpansInternal();
            self.lastBatchExport = now;
            self.exporterStats.recordBatchExport();
        }
    }

    /// Start a child span using parent context
    pub fn startSpanWithContext(self: *Telemetry, name: []const u8, parent: *const Span, opts: SpanOptions) !Span {
        var newOpts = opts;
        newOpts.parentSpanId = parent.spanId;
        newOpts.traceId = parent.traceId;
        return self.startSpan(name, newOpts);
    }

    /// Records a metric value
    pub fn recordMetric(self: *Telemetry, name: []const u8, value: f64, opts: MetricOptions) !void {
        if (!self.enabled) return;

        self.mutex.lockUncancelable(utils.io());
        defer self.mutex.unlock(utils.io());

        // Store metric in ArrayList
        try self.metrics.append(self.allocator, .{
            .name = try self.allocator.dupe(u8, name),
            .kind = opts.kind orelse .gauge,
            .value = value,
            .unit = opts.unit,
            .description = opts.description,
            .timestamp = utils.currentNanos(),
        });

        self.metricCount += 1;
        self.totalMetricsRecorded += 1;

        // Invoke callback
        if (self.onMetricRecorded) |callback| {
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

    /// Records multiple metrics in one call.
    ///
    /// Takes the lock once for the whole batch (instead of once per
    /// metric) and stamps every metric with the same timestamp instead of
    /// reading the clock per metric.
    ///
    /// Returns number of successfully recorded metric inputs.
    pub fn recordMetricsBatch(self: *Telemetry, metrics: []const MetricInput) !usize {
        if (!self.enabled) return 0;

        self.mutex.lockUncancelable(utils.io());
        defer self.mutex.unlock(utils.io());

        const batchTimestamp = utils.currentNanos();
        try self.metrics.ensureTotalCapacity(self.allocator, self.metrics.items.len + metrics.len);
        var recorded: usize = 0;
        for (metrics) |metric| {
            const ownedName = try self.allocator.dupe(u8, metric.name);
            errdefer self.allocator.free(ownedName);
            try self.metrics.append(self.allocator, .{
                .name = ownedName,
                .kind = metric.options.kind orelse .gauge,
                .value = metric.value,
                .unit = metric.options.unit,
                .description = metric.options.description,
                .timestamp = batchTimestamp,
            });
            recorded += 1;
            if (self.onMetricRecorded) |callback| {
                callback(metric.name, metric.value);
            }
        }
        self.metricCount += recorded;
        self.totalMetricsRecorded += recorded;
        return recorded;
    }

    /// Internal span export implementation
    fn exportSpansInternal(self: *Telemetry) !void {
        if (self.completedSpanCount == 0) return;

        // Export based on provider
        const result = switch (self.config.provider) {
            .file => self.exportToFile(),
            .generic => self.exportToOtlp(),
            .jaeger => self.exportToJaeger(),
            .zipkin => self.exportToZipkin(),
            .datadog => self.exportToDatadog(),
            .googleCloud => self.exportToGoogleCloud(),
            .googleAnalytics => self.exportToGoogleAnalytics(),
            .googleTagManager => self.exportToGoogleTagManager(),
            .awsXray => self.exportToAwsXray(),
            .azure => self.exportToAzure(),
            .custom => if (self.config.customExporterFn) |exportFn| exportFn() else {},
            .none => {},
        };

        if (result) |_| {} else |err| {
            std.debug.print("ERROR IN EXPORT: {s}\n", .{@errorName(err)});
            if (self.config.onError) |callback| {
                callback(@errorName(err));
            }
            self.exporterStats.recordError();
        }

        self.totalSpansExported += self.completedSpanCount;

        // Deep cleanup of all exported spans
        for (self.completedSpans.items) |*span| {
            span.deinit();
        }
        self.completedSpans.clearRetainingCapacity();
        self.completedSpanCount = 0;
    }

    /// Adds a log to the internal buffer for batching
    pub fn addLog(self: *Telemetry, timeNs: i64, dataJson: []const u8) !void {
        if (!self.enabled) return;
        self.mutex.lockUncancelable(utils.io());
        defer self.mutex.unlock(utils.io());

        try self.logs.append(self.allocator, .{
            .timeNs = timeNs,
            .dataJson = try self.allocator.dupe(u8, dataJson),
        });

        const now = utils.currentMillis();
        const elapsedMs: u64 = if (now > self.lastLogExport)
            @intCast(now - self.lastLogExport)
        else
            0;

        if (self.config.flushIntervalMs > 0 and elapsedMs >= self.config.flushIntervalMs) {
            try self.exportLogsInternal();
            self.lastLogExport = now;
        } else if (self.logs.items.len >= self.config.batchSize) {
            try self.exportLogsInternal();
            self.lastLogExport = now;
        }
    }

    /// Exports batched logs
    fn exportLogsInternal(self: *Telemetry) !void {
        if (self.logs.items.len == 0) return;

        switch (self.config.exportFormat) {
            .honeycomb => try self.exportLogsToHoneycomb(),
            .json => try self.exportLogsToJson(),
        }

        // Clean up
        for (self.logs.items) |log| {
            self.allocator.free(log.dataJson);
        }
        self.logs.clearRetainingCapacity();
    }

    fn exportLogsToHoneycomb(self: *Telemetry) !void {
        self.batchBuffer.clearRetainingCapacity();
        var batchWriter = Utils.ArrayListWriter.init(&self.batchBuffer, self.allocator);
        const writer = &batchWriter.writer;

        try writer.writeByte('[');
        for (self.logs.items, 0..) |log, i| {
            if (i > 0) try writer.writeByte(',');
            try writer.writeAll("{\"time\":");
            const timeMs = utils.safeToUnsigned(u64, log.timeNs) / Constants.TimeConstants.nsPerMs;
            try utils.writeInt(writer, timeMs);
            try writer.writeAll(",\"data\":");
            try writer.writeAll(log.dataJson);
            try writer.writeAll("}");
        }
        try writer.writeByte(']');

        try self.sendToEndpoint();
    }

    fn exportLogsToJson(self: *Telemetry) !void {
        self.batchBuffer.clearRetainingCapacity();
        var batchWriter = Utils.ArrayListWriter.init(&self.batchBuffer, self.allocator);
        const writer = &batchWriter.writer;

        try writer.writeByte('[');
        for (self.logs.items, 0..) |log, i| {
            if (i > 0) try writer.writeByte(',');
            try writer.writeAll(log.dataJson);
        }
        try writer.writeByte(']');

        try self.sendToEndpoint();
    }

    /// Export spans in OTLP JSON format (OpenTelemetry Protocol)
    /// Compatible with OpenTelemetry Collector and OTLP-compatible backends
    fn exportToOtlp(self: *Telemetry) !void {
        self.batchBuffer.clearRetainingCapacity();
        var batchWriter = Utils.ArrayListWriter.init(&self.batchBuffer, self.allocator);
        const writer = &batchWriter.writer;

        try self.writeOtlpSpans(writer);

        // Export via network if socket available, otherwise to file
        if (self.networkSocket != null and self.networkAddress != null) {
            try Network.sendUdp(self.networkSocket.?, self.networkAddress.?, self.batchBuffer.items);
            self.exporterStats.recordNetworkExport();
        } else if (self.config.exporterFilePath) |path| {
            const file = try std.Io.Dir.cwd().createFile(Utils.io(), path, .{ .read = true, .truncate = false });
            defer file.close(Utils.io());
            var fileBuffer: [Constants.BufferSizes.telemetry]u8 = undefined;
            var fileWriter = file.writer(Utils.io(), &fileBuffer);
            try fileWriter.seekTo(try file.length(Utils.io()));
            try fileWriter.interface.writeAll(self.batchBuffer.items);
            try fileWriter.interface.writeAll("\n");
            try fileWriter.flush();
        }

        self.exporterStats.recordExport(self.completedSpans.items.len, self.batchBuffer.items.len);
    }

    /// Write spans in OTLP JSON format
    fn writeOtlpSpans(self: *Telemetry, writer: anytype) !void {
        try writer.writeAll("{\"resourceSpans\":[{");

        // Resource section
        try writer.writeAll("\"resource\":{\"attributes\":[");
        var firstAttr = true;
        if (self.resource.serviceName) |name| {
            try self.writeOtlpAttribute(writer, "service.name", .{ .string = name }, &firstAttr);
        }
        if (self.resource.serviceVersion) |ver| {
            try self.writeOtlpAttribute(writer, "service.version", .{ .string = ver }, &firstAttr);
        }
        if (self.resource.environment) |env| {
            try self.writeOtlpAttribute(writer, "deployment.environment", .{ .string = env }, &firstAttr);
        }
        if (self.resource.datacenter) |dc| {
            try self.writeOtlpAttribute(writer, "cloud.availability_zone", .{ .string = dc }, &firstAttr);
        }
        try writer.writeAll("]},");

        // Scope spans section
        try writer.writeAll("\"scopeSpans\":[{\"scope\":{\"name\":\"logly.telemetry\",\"version\":\"");
        try writer.writeAll(Version.version);
        try writer.writeAll("\"},\"spans\":[");

        for (self.completedSpans.items, 0..) |span, i| {
            if (i > 0) try writer.writeByte(',');
            try self.writeOtlpSpan(writer, span);
        }

        try writer.writeAll("]}]}]}");
    }

    /// Write a single span in OTLP format
    fn writeOtlpSpan(self: *Telemetry, writer: anytype, span: Span) !void {
        try writer.writeAll("{\"traceId\":\"");
        try writer.writeAll(span.traceId);
        try writer.writeAll("\",\"spanId\":\"");
        try writer.writeAll(span.spanId);
        try writer.writeAll("\",\"name\":\"");
        try utils.escapeJsonString(writer, span.name);
        try writer.writeAll("\",\"kind\":");
        const kindNum: u8 = switch (span.kind) {
            .internal => 1,
            .server => 2,
            .client => 3,
            .producer => 4,
            .consumer => 5,
        };
        try utils.writeInt(writer, kindNum);
        try writer.writeAll(",\"startTimeUnixNano\":");
        try utils.writeInt(writer, utils.safeToUnsigned(u64, span.startTime));
        if (span.endTime > 0) {
            try writer.writeAll(",\"endTimeUnixNano\":");
            try utils.writeInt(writer, utils.safeToUnsigned(u64, span.endTime));
        }
        if (span.parentSpanId) |pid| {
            try writer.writeAll(",\"parentSpanId\":\"");
            try writer.writeAll(pid);
            try writer.writeByte('"');
        }

        // Attributes
        if (span.hasAttributes) {
            try writer.writeAll(",\"attributes\":[");
            var it = span.attributes.iterator();
            var firstAttr = true;
            while (it.next()) |entry| {
                try self.writeOtlpAttribute(writer, entry.key_ptr.*, entry.value_ptr.*, &firstAttr);
            }
            try writer.writeByte(']');
        }

        // Status
        try writer.writeAll(",\"status\":{\"code\":");
        const statusCode: u8 = switch (span.status) {
            .unset => 0,
            .ok => 1,
            .err => 2,
        };
        try utils.writeInt(writer, statusCode);
        try writer.writeAll("}}");
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
                try writer.print("{d}", .{i});
            },
            .float => |f| {
                try writer.writeAll("\"doubleValue\":");
                try writer.print("{d:.6}", .{f});
            },
            .boolean => |b| {
                try writer.writeAll("\"boolValue\":");
                try writer.writeAll(if (b) "true" else "false");
            },
            .stringArray => |arr| {
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
        self.batchBuffer.clearRetainingCapacity();
        var batchWriter = Utils.ArrayListWriter.init(&self.batchBuffer, self.allocator);
        const writer = &batchWriter.writer;

        try writer.writeAll("{\"data\":[{\"traceID\":\"");
        if (self.completedSpans.items.len > 0) {
            try writer.writeAll(self.completedSpans.items[0].traceId);
        }
        try writer.writeAll("\",\"spans\":[");

        for (self.completedSpans.items, 0..) |span, i| {
            if (i > 0) try writer.writeByte(',');
            try self.writeJaegerSpan(writer, span);
        }

        try writer.writeAll("],\"processes\":{\"p1\":{\"serviceName\":\"");
        try writer.writeAll(self.resource.serviceName orelse "unknown");
        try writer.writeAll("\"}}}]}");

        try self.sendToEndpoint();
    }

    /// Write Jaeger span format
    fn writeJaegerSpan(self: *Telemetry, writer: anytype, span: Span) !void {
        _ = self;
        try writer.writeAll("{\"traceID\":\"");
        try writer.writeAll(span.traceId);
        try writer.writeAll("\",\"spanID\":\"");
        try writer.writeAll(span.spanId);
        try writer.writeAll("\",\"operationName\":\"");
        try utils.escapeJsonString(writer, span.name);
        try writer.writeAll("\",\"startTime\":");
        const startUs = utils.safeToUnsigned(u64, span.startTime) / Constants.TimeConstants.nsPerUs;
        try utils.writeInt(writer, startUs);
        if (span.endTime > 0) {
            try writer.writeAll(",\"duration\":");
            const durationUs = utils.safeToUnsigned(u64, span.endTime - span.startTime) / Constants.TimeConstants.nsPerUs;
            try utils.writeInt(writer, durationUs);
        }
        try writer.writeAll(",\"processID\":\"p1\"}");
    }

    /// Export to Zipkin format
    fn exportToZipkin(self: *Telemetry) !void {
        self.batchBuffer.clearRetainingCapacity();
        var batchWriter = Utils.ArrayListWriter.init(&self.batchBuffer, self.allocator);
        const writer = &batchWriter.writer;

        try writer.writeByte('[');
        for (self.completedSpans.items, 0..) |span, i| {
            if (i > 0) try writer.writeByte(',');
            try self.writeZipkinSpan(writer, span);
        }
        try writer.writeByte(']');

        try self.sendToEndpoint();
    }

    /// Write Zipkin span format
    fn writeZipkinSpan(self: *Telemetry, writer: anytype, span: Span) !void {
        try writer.writeAll("{\"traceId\":\"");
        try writer.writeAll(span.traceId);
        try writer.writeAll("\",\"id\":\"");
        try writer.writeAll(span.spanId);
        try writer.writeAll("\",\"name\":\"");
        try utils.escapeJsonString(writer, span.name);
        try writer.writeAll("\",\"timestamp\":");
        const startUs = utils.safeToUnsigned(u64, span.startTime) / Constants.TimeConstants.nsPerUs;
        try utils.writeInt(writer, startUs);
        if (span.endTime > 0) {
            try writer.writeAll(",\"duration\":");
            const durationUs = utils.safeToUnsigned(u64, span.endTime - span.startTime) / Constants.TimeConstants.nsPerUs;
            try utils.writeInt(writer, durationUs);
        }
        try writer.writeAll(",\"localEndpoint\":{\"serviceName\":\"");
        try writer.writeAll(self.resource.serviceName orelse "unknown");
        try writer.writeAll("\"}}");
    }

    /// Export to Datadog APM format
    fn exportToDatadog(self: *Telemetry) !void {
        self.batchBuffer.clearRetainingCapacity();
        var batchWriter = Utils.ArrayListWriter.init(&self.batchBuffer, self.allocator);
        const writer = &batchWriter.writer;

        try writer.writeAll("[[");
        for (self.completedSpans.items, 0..) |span, i| {
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
        try writer.writeAll(self.resource.serviceName orelse "unknown");
        try writer.writeAll("\",\"resource\":\"");
        try utils.escapeJsonString(writer, span.name);
        try writer.writeAll("\",\"trace_id\":");
        // Datadog uses numeric trace IDs
        try writer.writeAll("0");
        try writer.writeAll(",\"span_id\":");
        try writer.writeAll("0");
        try writer.writeAll(",\"start\":");
        try utils.writeInt(writer, utils.safeToUnsigned(u64, span.startTime));
        if (span.endTime > 0) {
            try writer.writeAll(",\"duration\":");
            try utils.writeInt(writer, utils.safeToUnsigned(u64, span.endTime - span.startTime));
        }
        try writer.writeByte('}');
    }

    /// Export to Google Cloud Trace format
    fn exportToGoogleCloud(self: *Telemetry) !void {
        try self.exportToOtlp(); // Google Cloud accepts OTLP
    }

    /// Export to Google Analytics 4 Measurement Protocol
    fn exportToGoogleAnalytics(self: *Telemetry) !void {
        self.batchBuffer.clearRetainingCapacity();
        var batchWriter = Utils.ArrayListWriter.init(&self.batchBuffer, self.allocator);
        const writer = &batchWriter.writer;

        try writer.writeAll("{\"client_id\":\"logly_");
        if (self.completedSpans.items.len > 0) {
            try writer.writeAll(self.completedSpans.items[0].traceId[0..8]);
        } else {
            try writer.writeAll("unknown");
        }
        try writer.writeAll("\",\"events\":[");

        for (self.completedSpans.items, 0..) |span, i| {
            if (i > 0) try writer.writeByte(',');
            try writer.writeAll("{\"name\":\"span_completed\",\"params\":{");
            try writer.writeAll("\"span_name\":\"");
            try utils.escapeJsonString(writer, span.name);
            try writer.writeAll("\",\"trace_id\":\"");
            try writer.writeAll(span.traceId);
            try writer.writeAll("\",\"duration_ms\":");
            if (span.endTime > 0) {
                const durationMs = utils.safeToUnsigned(u64, span.endTime - span.startTime) / 1_000_000;
                try utils.writeInt(writer, durationMs);
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
        self.batchBuffer.clearRetainingCapacity();
        var batchWriter = Utils.ArrayListWriter.init(&self.batchBuffer, self.allocator);
        const writer = &batchWriter.writer;

        for (self.completedSpans.items, 0..) |span, i| {
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
        try writer.writeAll(span.spanId[0..@min(16, span.spanId.len)]);
        try writer.writeAll("\",\"trace_id\":\"1-");
        // X-Ray format: 1-{hex timestamp}-{hex random}
        try writer.writeAll(span.traceId[0..8]);
        try writer.writeAll("-");
        try writer.writeAll(span.traceId[8..@min(32, span.traceId.len)]);
        try writer.writeAll("\",\"start_time\":");
        const nsPerSecF = @as(f64, @floatFromInt(Constants.TimeConstants.nsPerSecond));
        const startSec = @as(f64, @floatFromInt(utils.safeToUnsigned(u64, span.startTime))) / nsPerSecF;
        try writer.print("{d:.6}", .{startSec});
        if (span.endTime > 0) {
            try writer.writeAll(",\"end_time\":");
            const nsPerSecEndF = @as(f64, @floatFromInt(Constants.TimeConstants.nsPerSecond));
            const endSec = @as(f64, @floatFromInt(utils.safeToUnsigned(u64, span.endTime))) / nsPerSecEndF;
            try writer.print("{d:.6}", .{endSec});
        }
        try writer.writeAll(",\"origin\":\"");
        try writer.writeAll(self.resource.serviceName orelse "unknown");
        try writer.writeAll("\"}");
    }

    /// Export to Azure Application Insights format
    fn exportToAzure(self: *Telemetry) !void {
        self.batchBuffer.clearRetainingCapacity();
        var batchWriter = Utils.ArrayListWriter.init(&self.batchBuffer, self.allocator);
        const writer = &batchWriter.writer;

        try writer.writeByte('[');
        for (self.completedSpans.items, 0..) |span, i| {
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
        const timestampNs = utils.safeToUnsigned(u64, span.startTime);
        const timestampSec = timestampNs / Constants.TimeConstants.nsPerSecond;
        try writer.print("{d}", .{timestampSec});
        try writer.writeAll("\",\"data\":{\"baseType\":\"RequestData\",\"baseData\":{");
        try writer.writeAll("\"id\":\"");
        try writer.writeAll(span.spanId);
        try writer.writeAll("\",\"name\":\"");
        try utils.escapeJsonString(writer, span.name);
        try writer.writeAll("\",\"success\":");
        try writer.writeAll(if (span.status != .err) "true" else "false");
        if (span.endTime > 0) {
            try writer.writeAll(",\"duration\":\"");
            const durationMs = utils.safeToUnsigned(u64, span.endTime - span.startTime) / 1_000_000;
            const hours = durationMs / 3_600_000;
            const minutes = (durationMs % 3_600_000) / 60_000;
            const seconds = (durationMs % 60_000) / 1_000;
            const ms = durationMs % 1_000;
            try writer.print("{d:0>2}:{d:0>2}:{d:0>2}.{d:0>3}", .{ hours, minutes, seconds, ms });
            try writer.writeByte('"');
        }
        try writer.writeAll("}},\"iKey\":\"");
        try writer.writeAll(self.config.connectionString orelse "");
        try writer.writeAll("\"}");
    }

    /// Send buffer to configured endpoint
    fn sendToEndpoint(self: *Telemetry) !void {
        if (self.networkSocket != null and self.networkAddress != null) {
            try Network.sendUdp(self.networkSocket.?, self.networkAddress.?, self.batchBuffer.items);
            self.exporterStats.recordNetworkExport();
        }
        self.exporterStats.recordExport(self.completedSpans.items.len, self.batchBuffer.items.len);
    }

    /// Export spans to file (JSONL format)
    fn exportToFile(self: *Telemetry) !void {
        const path = self.config.exporterFilePath orelse return;

        const file = try std.Io.Dir.cwd().createFile(Utils.io(), path, .{ .read = true, .truncate = false });
        defer file.close(Utils.io());

        var fileBuffer: [Constants.BufferSizes.telemetry]u8 = undefined;
        var fileWriter = file.writer(Utils.io(), &fileBuffer);
        try fileWriter.seekTo(try file.length(Utils.io()));
        for (self.completedSpans.items) |span| {
            self.batchBuffer.clearRetainingCapacity();
            var batchWriter = Utils.ArrayListWriter.init(&self.batchBuffer, self.allocator);
            const writer = &batchWriter.writer;
            try self.writeSpanJson(writer, span);
            try writer.writeByte('\n');
            try fileWriter.interface.writeAll(self.batchBuffer.items);
        }
        try fileWriter.flush();
    }

    /// Export spans to network (TCP/UDP) using Network module
    fn exportToNetwork(self: *Telemetry) !void {
        if (self.networkSocket == null or self.networkAddress == null) return;

        // Build JSON batch
        self.batchBuffer.clearRetainingCapacity();
        var batchWriter = Utils.ArrayListWriter.init(&self.batchBuffer, self.allocator);
        const writer = &batchWriter.writer;

        try writer.writeAll("{\"spans\":[");
        for (self.completedSpans.items, 0..) |span, i| {
            if (i > 0) try writer.writeByte(',');
            try self.writeSpanJson(writer, span);
        }
        try writer.writeAll("]}");

        // Send via UDP using Network module
        try Network.sendUdp(self.networkSocket.?, self.networkAddress.?, self.batchBuffer.items);
        self.exporterStats.recordExport(self.completedSpans.items.len, self.batchBuffer.items.len);
        self.exporterStats.recordNetworkExport();
    }

    /// Write span as JSON using utils helpers
    fn writeSpanJson(self: *Telemetry, writer: anytype, span: Span) !void {
        _ = self;
        try writer.writeAll("{\"trace_id\":\"");
        try writer.writeAll(span.traceId);
        try writer.writeAll("\",\"span_id\":\"");
        try writer.writeAll(span.spanId);
        try writer.writeAll("\",\"name\":\"");
        try utils.escapeJsonString(writer, span.name);
        try writer.writeAll("\",\"kind\":\"");
        try writer.writeAll(@tagName(span.kind));
        try writer.writeAll("\",\"status\":\"");
        try writer.writeAll(@tagName(span.status));
        try writer.writeAll("\",\"start_time\":");
        try utils.writeInt(writer, utils.safeToUnsigned(u64, span.startTime));
        if (span.endTime > 0) {
            try writer.writeAll(",\"end_time\":");
            try utils.writeInt(writer, utils.safeToUnsigned(u64, span.endTime));
            try writer.writeAll(",\"duration_ns\":");
            const duration = span.endTime - span.startTime;
            try utils.writeInt(writer, utils.safeToUnsigned(u64, duration));
        }
        if (span.parentSpanId) |pid| {
            try writer.writeAll(",\"parent_span_id\":\"");
            try writer.writeAll(pid);
            try writer.writeByte('"');
        }

        if (span.hasAttributes) {
            try writer.writeAll(",\"attributes\":{");
            var it = span.attributes.iterator();
            var first = true;
            while (it.next()) |entry| {
                if (!first) try writer.writeByte(',');
                try writer.writeByte('"');
                try writer.writeAll(entry.key_ptr.*);
                try writer.writeAll("\":");
                switch (entry.value_ptr.*) {
                    .string => |s| {
                        try writer.writeByte('"');
                        try utils.escapeJsonString(writer, s);
                        try writer.writeByte('"');
                    },
                    .integer => |i| try utils.writeInt(writer, i),
                    .float => |f| try writer.print("{d:.6}", .{f}),
                    .boolean => |b| try writer.writeAll(if (b) "true" else "false"),
                    .stringArray => |arr| {
                        try writer.writeByte('[');
                        for (arr, 0..) |s, j| {
                            if (j > 0) try writer.writeByte(',');
                            try writer.writeByte('"');
                            try utils.escapeJsonString(writer, s);
                            try writer.writeByte('"');
                        }
                        try writer.writeByte(']');
                    },
                }
                first = false;
            }
            try writer.writeByte('}');
        }

        try writer.writeByte('}');
    }

    /// Exports all completed spans (placeholder for actual export logic)
    pub fn exportSpans(self: *Telemetry) !void {
        if (!self.enabled) return;

        self.mutex.lockUncancelable(utils.io());
        defer self.mutex.unlock(utils.io());

        try self.exportSpansInternal();
    }

    /// Exports all metrics using the configured exporter.
    pub fn exportMetrics(self: *Telemetry) !void {
        if (!self.enabled) return;

        self.mutex.lockUncancelable(utils.io());
        defer self.mutex.unlock(utils.io());

        if (self.metricCount == 0) return;

        const exportResult: anyerror!void = switch (self.config.metricFormat) {
            .json => self.exportMetricsJson(),
            .prometheus => self.exportMetricsPrometheus(),
            .otlp => {},
        };

        if (exportResult) |_| {
            self.exporterStats.recordMetricExport(self.metricCount);
        } else |err| {
            if (self.config.onError) |callback| {
                callback(@errorName(err));
            }
            self.exporterStats.recordError();
        }

        // Clear metrics after export
        for (self.metrics.items) |metric| {
            self.allocator.free(metric.name);
        }
        self.metrics.clearRetainingCapacity();
        self.metricCount = 0;
    }

    /// Export metrics as JSON lines to the configured metrics path.
    fn exportMetricsJson(self: *Telemetry) !void {
        const path = self.config.metricsFilePath orelse self.config.exporterFilePath orelse return;

        const file = try std.Io.Dir.cwd().createFile(Utils.io(), path, .{ .read = true, .truncate = false });
        defer file.close(Utils.io());

        var fileBuffer: [Constants.BufferSizes.telemetry]u8 = undefined;
        var fileWriter = file.writer(Utils.io(), &fileBuffer);
        try fileWriter.seekTo(try file.length(Utils.io()));

        for (self.metrics.items) |metric| {
            self.batchBuffer.clearRetainingCapacity();
            var batchWriter = Utils.ArrayListWriter.init(&self.batchBuffer, self.allocator);
            const writer = &batchWriter.writer;
            try self.writeMetricJson(writer, metric);
            try writer.writeByte('\n');
            try fileWriter.interface.writeAll(self.batchBuffer.items);
        }
        try fileWriter.flush();
    }

    /// Export metrics in Prometheus text format to the configured metrics path.
    fn exportMetricsPrometheus(self: *Telemetry) !void {
        const path = self.config.metricsFilePath orelse self.config.exporterFilePath orelse return;

        const file = try std.Io.Dir.cwd().createFile(Utils.io(), path, .{ .read = true, .truncate = false });
        defer file.close(Utils.io());

        var fileBuffer: [Constants.BufferSizes.telemetry]u8 = undefined;
        var fileWriter = file.writer(Utils.io(), &fileBuffer);
        try fileWriter.seekTo(try file.length(Utils.io()));

        for (self.metrics.items) |metric| {
            self.batchBuffer.clearRetainingCapacity();
            var batchWriter = Utils.ArrayListWriter.init(&self.batchBuffer, self.allocator);
            const writer = &batchWriter.writer;
            try self.writeMetricPrometheus(writer, metric);
            try fileWriter.interface.writeAll(self.batchBuffer.items);
        }
        try fileWriter.flush();
    }

    /// Write a single metric as a JSON object.
    fn writeMetricJson(self: *Telemetry, writer: anytype, metric: Metric) !void {
        try writer.writeAll("{\"name\":\"");
        try utils.writeTelemetryMetricName(
            writer,
            self.config.metricPrefix,
            self.config.metricPrefixSeparator,
            metric.name,
            self.config.sanitizeMetricNames,
        );
        try writer.writeAll("\",\"kind\":\"");
        try writer.writeAll(@tagName(metric.kind));
        try writer.writeAll("\",\"value\":");
        try writer.print("{d}", .{metric.value});

        if (metric.unit) |unit| {
            try writer.writeAll(",\"unit\":\"");
            try utils.escapeJsonString(writer, unit);
            try writer.writeByte('"');
        }

        if (metric.description) |desc| {
            try writer.writeAll(",\"description\":\"");
            try utils.escapeJsonString(writer, desc);
            try writer.writeByte('"');
        }

        try writer.writeAll(",\"timestamp\":");
        try utils.writeInt(writer, utils.safeToUnsigned(u64, metric.timestamp));
        try writer.writeByte('}');
    }

    /// Write a single metric in Prometheus text format.
    fn writeMetricPrometheus(self: *Telemetry, writer: anytype, metric: Metric) !void {
        try writer.writeAll("# TYPE ");
        try utils.writeTelemetryMetricName(
            writer,
            self.config.metricPrefix,
            self.config.metricPrefixSeparator,
            metric.name,
            self.config.sanitizeMetricNames,
        );
        try writer.writeByte(' ');
        try writer.writeAll(@tagName(metric.kind));
        try writer.writeByte('\n');
        try utils.writeTelemetryMetricName(
            writer,
            self.config.metricPrefix,
            self.config.metricPrefixSeparator,
            metric.name,
            self.config.sanitizeMetricNames,
        );
        try writer.writeByte(' ');
        try writer.print("{d}\n", .{metric.value});
    }

    /// Flushes all data (spans and metrics)
    pub fn flush(self: *Telemetry) !void {
        try self.exportSpans();
        try self.exportMetrics();
    }

    /// Returns the number of active spans
    pub fn getActiveSpanCount(self: *Telemetry) usize {
        self.mutex.lockUncancelable(utils.io());
        defer self.mutex.unlock(utils.io());
        return self.activeSpanCount;
    }

    /// Returns the number of completed spans awaiting export
    pub fn getCompletedSpanCount(self: *Telemetry) usize {
        self.mutex.lockUncancelable(utils.io());
        defer self.mutex.unlock(utils.io());
        return self.completedSpanCount;
    }

    /// Returns the current metric count
    pub fn getMetricCount(self: *Telemetry) usize {
        self.mutex.lockUncancelable(utils.io());
        defer self.mutex.unlock(utils.io());
        return self.metricCount;
    }

    /// Returns telemetry statistics
    pub fn getStats(self: *Telemetry) TelemetryStats {
        self.mutex.lockUncancelable(utils.io());
        defer self.mutex.unlock(utils.io());
        return .{
            .totalSpansCreated = self.totalSpansCreated,
            .totalSpansExported = self.totalSpansExported,
            .totalMetricsRecorded = self.totalMetricsRecorded,
            .activeSpans = self.activeSpanCount,
            .pendingSpans = self.completedSpanCount,
        };
    }

    /// Returns exporter statistics
    pub fn getExporterStats(self: *Telemetry) ExporterStats {
        return self.exporterStats;
    }

    /// Generate W3C traceparent header value
    pub fn getTraceparentHeader(self: *Telemetry, span: *const Span) ![]const u8 {
        return utils.formatTraceparentHeader(self.allocator, span.traceId, span.spanId, true);
    }

    /// Parse W3C traceparent header and extract trace context
    pub fn parseTraceparentHeader(header: []const u8) ?TraceContext {
        const parsed = utils.parseTraceparentHeader(header) orelse return null;

        return TraceContext{
            .traceId = parsed.traceId,
            .spanId = parsed.spanId,
            .sampled = parsed.sampled,
        };
    }

    /// Enable/disable telemetry at runtime
    pub fn setEnabled(self: *Telemetry, enabled: bool) void {
        self.mutex.lockUncancelable(utils.io());
        defer self.mutex.unlock(utils.io());
        self.enabled = enabled;
    }

    fn clampSamplingRate(inputRate: f64) f64 {
        if (std.math.isNan(inputRate)) return 0.0;
        return std.math.clamp(inputRate, 0.0, 1.0);
    }

    /// Updates telemetry sampling strategy and effective sampling rate.
    pub fn setSampling(self: *Telemetry, strategy: TelemetryConfig.SamplingStrategy, samplingRate: f64) void {
        self.mutex.lockUncancelable(utils.io());
        defer self.mutex.unlock(utils.io());

        const clampedRate = clampSamplingRate(samplingRate);

        self.config.samplingStrategy = strategy;
        self.config.samplingRate = clampedRate;
        self.sampler = .{
            .strategy = strategy,
            .samplingRate = clampedRate,
        };
    }

    /// Returns current telemetry sampling configuration.
    pub fn getSampling(self: *Telemetry) SamplingSnapshot {
        self.mutex.lockUncancelable(utils.io());
        defer self.mutex.unlock(utils.io());

        return .{
            .strategy = self.config.samplingStrategy,
            .rate = self.config.samplingRate,
        };
    }

    /// Sets context propagation header names at runtime.
    pub fn setContextHeaders(self: *Telemetry, traceHeader: []const u8, baggageHeader: []const u8) void {
        self.mutex.lockUncancelable(utils.io());
        defer self.mutex.unlock(utils.io());

        self.config.traceHeader = traceHeader;
        self.config.baggageHeader = baggageHeader;
    }

    /// Returns currently configured context propagation headers.
    pub fn getContextHeaders(self: *Telemetry) ContextHeaders {
        self.mutex.lockUncancelable(utils.io());
        defer self.mutex.unlock(utils.io());

        return .{
            .traceHeader = self.config.traceHeader,
            .baggageHeader = self.config.baggageHeader,
        };
    }

    /// Returns true when spans or metrics are waiting to be exported.
    pub fn hasPendingData(self: *Telemetry) bool {
        self.mutex.lockUncancelable(utils.io());
        defer self.mutex.unlock(utils.io());

        return self.completedSpanCount > 0 or self.metricCount > 0;
    }

    /// Returns total number of pending spans + metrics.
    pub fn pendingItemCount(self: *Telemetry) usize {
        self.mutex.lockUncancelable(utils.io());
        defer self.mutex.unlock(utils.io());

        return self.completedSpanCount + self.metricCount;
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
        self.mutex.lockUncancelable(utils.io());
        defer self.mutex.unlock(utils.io());
        self.resource = resource;
    }

    /// Reset all statistics counters
    pub fn resetStats(self: *Telemetry) void {
        self.mutex.lockUncancelable(utils.io());
        defer self.mutex.unlock(utils.io());
        self.totalSpansCreated = 0;
        self.totalSpansExported = 0;
        self.totalMetricsRecorded = 0;
        self.exporterStats = .{};
    }

    /// Get span by trace_id (for distributed trace continuation)
    pub fn findSpanByTraceId(self: *Telemetry, traceId: []const u8) ?*const Span {
        self.mutex.lockUncancelable(utils.io());
        defer self.mutex.unlock(utils.io());

        for (self.spans.items) |*span| {
            if (std.mem.eql(u8, span.traceId, traceId)) {
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
        var newOpts = opts;
        newOpts.traceId = ctx.traceId;
        newOpts.parentSpanId = ctx.spanId;

        return self.startSpan(name, newOpts);
    }
};

/// Trace context for W3C propagation
pub const TraceContext = struct {
    traceId: []const u8,
    spanId: []const u8,
    sampled: bool = true,
};

/// Telemetry statistics
pub const TelemetryStats = struct {
    totalSpansCreated: u64,
    totalSpansExported: u64,
    totalMetricsRecorded: u64,
    activeSpans: usize,
    pendingSpans: usize,
};

/// Span represents a single unit of work in a trace
pub const Span = struct {
    /// Key-value pair used by `setAttributes` for batch updates.
    pub const AttributeEntry = struct {
        key: []const u8,
        value: SpanAttribute,
    };

    allocator: std.mem.Allocator,
    spanId: []const u8,
    traceId: []const u8,
    parentSpanId: ?[]const u8 = null,
    name: []const u8,
    startTime: i128,
    endTime: i128 = 0,
    status: SpanStatus = .unset,
    kind: SpanKind = .internal,

    // Attributes storage
    attributes: std.StringHashMap(SpanAttribute) = undefined,
    hasAttributes: bool = false,

    // Events storage
    events: std.ArrayList(SpanEvent) = undefined,
    hasEvents: bool = false,

    /// Creates an empty/no-op span (when telemetry is disabled or not sampled)
    pub fn empty(allocator: std.mem.Allocator) Span {
        return Span{
            .allocator = allocator,
            .spanId = "",
            .traceId = "",
            .name = "",
            .startTime = 0,
        };
    }

    /// Check if this is an empty/no-op span
    pub fn isEmpty(self: Span) bool {
        return self.spanId.len == 0;
    }

    /// Adds an attribute to the span
    pub fn setAttribute(self: *Span, key: []const u8, value: SpanAttribute) !void {
        if (self.spanId.len == 0) return; // No-op for empty spans

        if (!self.hasAttributes) {
            self.attributes = std.StringHashMap(SpanAttribute).init(self.allocator);
            self.hasAttributes = true;
        }

        const keyCopy = try self.allocator.dupe(u8, key);
        try self.attributes.put(keyCopy, value);
    }

    /// Adds multiple attributes in a single call.
    ///
    /// Returns number of attributes applied.
    pub fn setAttributes(self: *Span, attrs: []const AttributeEntry) !usize {
        if (self.spanId.len == 0) return 0;

        var applied: usize = 0;
        for (attrs) |entry| {
            try self.setAttribute(entry.key, entry.value);
            applied += 1;
        }
        return applied;
    }

    /// Adds an event to the span
    pub fn addEvent(self: *Span, name: []const u8, attrs: ?*const anyopaque) !void {
        if (self.spanId.len == 0) return; // No-op for empty spans
        _ = attrs;

        if (!self.hasEvents) {
            self.events = try std.ArrayList(SpanEvent).initCapacity(self.allocator, 8);
            self.hasEvents = true;
        }

        try self.events.append(self.allocator, .{
            .name = try self.allocator.dupe(u8, name),
            .timestamp = utils.currentNanos(),
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
        if (self.endTime == 0) {
            self.endTime = utils.currentNanos();
        }
    }

    /// Gets span duration in nanoseconds
    pub fn getDuration(self: Span) u64 {
        if (self.endTime == 0 or self.startTime == 0) return 0;
        return utils.durationSinceNs(self.startTime);
    }

    /// Gets span duration in milliseconds
    pub fn getDurationMs(self: Span) f64 {
        const ns = self.getDuration();
        return @as(f64, @floatFromInt(ns)) / 1_000_000.0;
    }

    /// Cleans up span resources
    pub fn deinit(self: *Span) void {
        if (self.spanId.len > 0) {
            self.allocator.free(self.spanId);
        }
        if (self.traceId.len > 0) {
            self.allocator.free(self.traceId);
        }
        if (self.parentSpanId) |pid| {
            if (pid.len > 0) {
                self.allocator.free(pid);
            }
        }
        if (self.name.len > 0) {
            self.allocator.free(@constCast(self.name));
        }

        // Clean up attributes
        if (self.hasAttributes) {
            var it = self.attributes.iterator();
            while (it.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
            }
            self.attributes.deinit();
        }

        // Clean up events
        if (self.hasEvents) {
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
    stringArray: []const []const u8,
};

/// Span event
pub const SpanEvent = struct {
    name: []const u8,
    timestamp: i128,
};

/// Span options for creation
pub const SpanOptions = struct {
    traceId: ?[]const u8 = null,
    parentSpanId: ?[]const u8 = null,
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
    serviceName: ?[]const u8,
    serviceVersion: ?[]const u8,
    environment: ?[]const u8,
    datacenter: ?[]const u8,

    /// Creates Resource from TelemetryConfig
    pub fn fromConfig(config: TelemetryConfig) Resource {
        return .{
            .serviceName = config.serviceName,
            .serviceVersion = config.serviceVersion,
            .environment = config.environment,
            .datacenter = config.datacenter,
        };
    }
};

/// Sampler for controlling trace sampling
pub const TelemetrySampler = struct {
    strategy: TelemetryConfig.SamplingStrategy,
    samplingRate: f64,

    /// Initialize sampler from config
    pub fn init(config: TelemetryConfig) TelemetrySampler {
        return .{
            .strategy = config.samplingStrategy,
            .samplingRate = config.samplingRate,
        };
    }

    /// Determines if a trace should be sampled
    pub fn shouldSample(self: TelemetrySampler, traceId: []const u8) bool {
        _ = traceId;
        return switch (self.strategy) {
            .alwaysOn => true,
            .alwaysOff => false,
            .traceIdRatio => utils.shouldSample(self.samplingRate),
            .parentBased => true, // Simplified: always sample if parent-based
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

    /// Creates an empty baggage container.
    pub fn init(allocator: std.mem.Allocator) Baggage {
        return .{
            .allocator = allocator,
            .items = std.StringHashMap([]const u8).init(allocator),
        };
    }

    /// Releases all baggage storage.
    pub fn deinit(self: *Baggage) void {
        var it = self.items.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.items.deinit();
    }

    /// Sets or replaces a baggage item.
    pub fn set(self: *Baggage, key: []const u8, value: []const u8) !void {
        const keyCopy = try self.allocator.dupe(u8, key);
        errdefer self.allocator.free(keyCopy);
        const valueCopy = try self.allocator.dupe(u8, value);
        errdefer self.allocator.free(valueCopy);

        if (self.items.getEntry(key)) |entry| {
            self.allocator.free(entry.value_ptr.*);
            entry.value_ptr.* = valueCopy;
            self.allocator.free(keyCopy);
            return;
        }

        try self.items.put(keyCopy, valueCopy);
    }

    /// Retrieves a baggage value by key.
    pub fn get(self: *Baggage, key: []const u8) ?[]const u8 {
        return self.items.get(key);
    }

    /// Removes a baggage value by key.
    pub fn remove(self: *Baggage, key: []const u8) void {
        if (self.items.fetchRemove(key)) |entry| {
            self.allocator.free(entry.key);
            self.allocator.free(entry.value);
        }
    }

    /// Format as W3C baggage header value
    pub fn toHeaderValue(self: *Baggage, allocator: std.mem.Allocator) ![]const u8 {
        var result = std.Io.Writer.Allocating.initCapacity(allocator, Constants.TelemetryDefaults.headerInitialCapacity) catch return "";
        errdefer result.deinit();
        const writer = &result.writer;

        var it = self.items.iterator();
        var first = true;
        while (it.next()) |entry| {
            if (!first) try writer.writeByte(',');
            try writer.writeAll(entry.key_ptr.*);
            try writer.writeByte('=');
            try writer.writeAll(entry.value_ptr.*);
            first = false;
        }

        return result.toOwnedSlice();
    }

    /// Parse W3C baggage header value
    pub fn fromHeaderValue(allocator: std.mem.Allocator, header: []const u8) !Baggage {
        var baggage = Baggage.init(allocator);
        errdefer baggage.deinit();

        var pairs = std.mem.splitScalar(u8, header, ',');
        while (pairs.next()) |pair| {
            const trimmed = std.mem.trim(u8, pair, " ");
            if (std.mem.indexOfScalar(u8, trimmed, '=')) |eqIdx| {
                const key = std.mem.trim(u8, trimmed[0..eqIdx], " ");
                const value = std.mem.trim(u8, trimmed[eqIdx + 1 ..], " ");
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
    const defaultConfig = TelemetryConfig.default();
    try std.testing.expect(!defaultConfig.enabled);
    try std.testing.expectEqual(defaultConfig.provider, .none);

    // Test Jaeger preset
    const jaegerConfig = TelemetryConfig.jaeger();
    try std.testing.expect(jaegerConfig.enabled);
    try std.testing.expectEqual(jaegerConfig.provider, .jaeger);
    try std.testing.expect(jaegerConfig.exporterEndpoint != null);

    // Test Zipkin preset
    const zipkinConfig = TelemetryConfig.zipkin();
    try std.testing.expect(zipkinConfig.enabled);
    try std.testing.expectEqual(zipkinConfig.provider, .zipkin);

    // Test file preset
    const fileConfig = TelemetryConfig.file("test.jsonl");
    try std.testing.expect(fileConfig.enabled);
    try std.testing.expectEqual(fileConfig.provider, .file);
    try std.testing.expectEqualStrings("test.jsonl", fileConfig.exporterFilePath.?);

    // Test development preset
    const devConfig = TelemetryConfig.development();
    try std.testing.expect(devConfig.enabled);
    try std.testing.expectEqual(devConfig.samplingStrategy, .alwaysOn);

    // Test high throughput preset
    const htConfig = TelemetryConfig.highThroughput();
    try std.testing.expect(htConfig.enabled);
    try std.testing.expectEqual(htConfig.samplingStrategy, .traceIdRatio);
    try std.testing.expect(htConfig.samplingRate < 0.1);
}

test "Telemetry init and deinit" {
    const allocator = std.testing.allocator;

    // Test with disabled config
    const config = TelemetryConfig.default();
    var telemetry = try Telemetry.init(allocator, config);
    defer telemetry.deinit();

    try std.testing.expect(!telemetry.enabled);
    try std.testing.expectEqual(@as(usize, 0), telemetry.activeSpanCount);
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

    try std.testing.expect(span.spanId.len > 0);
    try std.testing.expect(span.traceId.len > 0);
    try std.testing.expectEqualStrings("test_operation", span.name);
    try std.testing.expect(span.startTime > 0);

    // Check counters
    try std.testing.expectEqual(@as(usize, 1), telemetry.activeSpanCount);

    // End span
    span.end();
    try telemetry.endSpan(&span);

    // Check counters updated
    try std.testing.expectEqual(@as(usize, 0), telemetry.activeSpanCount);
    try std.testing.expectEqual(@as(usize, 1), telemetry.completedSpanCount);
}

test "File exporter writes spans" {
    const allocator = std.testing.allocator;
    const path = "telemetry_spans_test.jsonl";

    std.Io.Dir.cwd().deleteFile(Utils.io(), path) catch {};
    defer std.Io.Dir.cwd().deleteFile(Utils.io(), path) catch {};

    var config = TelemetryConfig.file(path);
    config.samplingStrategy = .alwaysOn;

    var telemetry = try Telemetry.init(allocator, config);
    defer telemetry.deinit();

    var span = try telemetry.startSpan("file_export_test", .{});
    defer span.deinit();

    span.end();
    try telemetry.endSpan(&span);
    try telemetry.exportSpans();

    const file = try std.Io.Dir.cwd().openFile(Utils.io(), path, .{});
    defer file.close(Utils.io());

    const stat = try file.stat(Utils.io());
    try std.testing.expect(stat.size > 0);
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
        .parentSpanId = parent.spanId,
        .traceId = parent.traceId,
    });
    defer child.deinit();

    try std.testing.expect(child.parentSpanId != null);
    try std.testing.expectEqualStrings(parent.spanId, child.parentSpanId.?);
    try std.testing.expectEqualStrings(parent.traceId, child.traceId);
}

test "Span disabled telemetry" {
    const allocator = std.testing.allocator;

    const config = TelemetryConfig.default(); // disabled by default
    var telemetry = try Telemetry.init(allocator, config);
    defer telemetry.deinit();

    // Should return empty span when disabled
    const span = try telemetry.startSpan("test", .{});
    // Empty span has empty strings
    try std.testing.expectEqual(@as(usize, 0), span.spanId.len);
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

    try std.testing.expectEqual(@as(usize, 3), telemetry.metricCount);
    try std.testing.expectEqual(@as(u64, 3), telemetry.totalMetricsRecorded);

    // Export metrics
    try telemetry.exportMetrics();
    try std.testing.expectEqual(@as(usize, 0), telemetry.metricCount);
}

test "TelemetrySampler strategies" {
    // Always on
    const alwaysOn = TelemetrySampler{
        .strategy = .alwaysOn,
        .samplingRate = 1.0,
    };
    try std.testing.expect(alwaysOn.shouldSample("trace123"));

    // Always off
    const alwaysOff = TelemetrySampler{
        .strategy = .alwaysOff,
        .samplingRate = 0.0,
    };
    try std.testing.expect(!alwaysOff.shouldSample("trace123"));

    // Trace ID ratio with 100% rate
    const ratio100 = TelemetrySampler{
        .strategy = .traceIdRatio,
        .samplingRate = 1.0,
    };
    try std.testing.expect(ratio100.shouldSample("trace123"));

    // Trace ID ratio with 0% rate
    const ratio0 = TelemetrySampler{
        .strategy = .traceIdRatio,
        .samplingRate = 0.0,
    };
    try std.testing.expect(!ratio0.shouldSample("trace123"));
}

test "Resource from config" {
    var config = TelemetryConfig.jaeger();
    config.serviceName = "test-service";
    config.serviceVersion = "1.0.0";
    config.environment = "testing";
    config.datacenter = "us-west-1";

    const resource = Resource.fromConfig(config);

    try std.testing.expectEqualStrings("test-service", resource.serviceName.?);
    try std.testing.expectEqualStrings("1.0.0", resource.serviceVersion.?);
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
    try std.testing.expectEqual(@as(u64, 2), stats.totalSpansCreated);
    try std.testing.expectEqual(@as(usize, 2), stats.pendingSpans);
    try std.testing.expectEqual(@as(u64, 1), stats.totalMetricsRecorded);

    // Export
    try telemetry.exportSpans();
    const stats2 = telemetry.getStats();
    try std.testing.expectEqual(@as(u64, 2), stats2.totalSpansExported);
    try std.testing.expectEqual(@as(usize, 0), stats2.pendingSpans);
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

    try std.testing.expect(telemetry.completedSpanCount > 0);
    try std.testing.expect(telemetry.metricCount > 0);

    // Flush
    try telemetry.flush();

    try std.testing.expectEqual(@as(usize, 0), telemetry.completedSpanCount);
    try std.testing.expectEqual(@as(usize, 0), telemetry.metricCount);
}

test "Provider configurations" {
    // Google Cloud
    const gcp = TelemetryConfig.googleCloud("my-project", "api-key");
    try std.testing.expectEqual(gcp.provider, .googleCloud);
    try std.testing.expectEqualStrings("my-project", gcp.projectId.?);

    // Google Analytics
    const ga4 = TelemetryConfig.googleAnalytics("G-XXXXXXXXXX", "api_secret_123");
    try std.testing.expectEqual(ga4.provider, .googleAnalytics);
    try std.testing.expectEqualStrings("G-XXXXXXXXXX", ga4.projectId.?);
    try std.testing.expectEqualStrings("api_secret_123", ga4.apiKey.?);
    try std.testing.expectEqualStrings("https://www.google-analytics.com/mp/collect", ga4.exporterEndpoint.?);
    try std.testing.expectEqual(@as(usize, 25), ga4.batchSize);

    // Google Tag Manager
    const gtm = TelemetryConfig.googleTagManager("https://gtm.example.com/collect", "gtm-api-key");
    try std.testing.expectEqual(gtm.provider, .googleTagManager);
    try std.testing.expectEqualStrings("https://gtm.example.com/collect", gtm.exporterEndpoint.?);
    try std.testing.expectEqualStrings("gtm-api-key", gtm.apiKey.?);

    // Google Tag Manager without API key
    const gtmNoKey = TelemetryConfig.googleTagManager("https://gtm.example.com/collect", null);
    try std.testing.expectEqual(gtmNoKey.provider, .googleTagManager);
    try std.testing.expect(gtmNoKey.apiKey == null);

    // AWS X-Ray
    const xray = TelemetryConfig.awsXray("us-east-1");
    try std.testing.expectEqual(xray.provider, .awsXray);
    try std.testing.expectEqualStrings("us-east-1", xray.region.?);

    // Azure
    const azure = TelemetryConfig.azure("InstrumentationKey=xxx");
    try std.testing.expectEqual(azure.provider, .azure);

    // Datadog
    const dd = TelemetryConfig.datadog("dd-api-key");
    try std.testing.expectEqual(dd.provider, .datadog);
    try std.testing.expectEqualStrings("dd-api-key", dd.apiKey.?);

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

    try std.testing.expect(child.parentSpanId != null);
    try std.testing.expectEqualStrings(parent.spanId, child.parentSpanId.?);
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
    Utils.io().sleep(.fromMilliseconds(1), .awake) catch {}; // 1ms

    span.end();

    const durationNs = span.getDuration();
    const durationMs = span.getDurationMs();

    try std.testing.expect(durationNs > 0);
    try std.testing.expect(durationMs > 0.0);
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

test "Baggage set replaces existing key" {
    const allocator = std.testing.allocator;

    var baggage = Baggage.init(allocator);
    defer baggage.deinit();

    try baggage.set("user_id", "123");
    try std.testing.expectEqual(@as(usize, 1), baggage.count());

    try baggage.set("user_id", "456");
    try std.testing.expectEqual(@as(usize, 1), baggage.count());
    try std.testing.expectEqualStrings("456", baggage.get("user_id").?);
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
    try std.testing.expectEqualStrings("4bf92f3577b34da6a3ce929d0e0e4736", ctx.?.traceId);
    try std.testing.expectEqualStrings("00f067aa0ba902b7", ctx.?.spanId);
    try std.testing.expect(ctx.?.sampled);

    // Invalid version
    const invalid = Telemetry.parseTraceparentHeader("01-trace-span-01");
    try std.testing.expect(invalid == null);

    // Not sampled
    const notSampled = Telemetry.parseTraceparentHeader("00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-00");
    try std.testing.expect(notSampled != null);
    try std.testing.expect(!notSampled.?.sampled);
}

test "Exporter stats" {
    var stats = ExporterStats{};

    stats.recordExport(10, Constants.SizeConstants.bytesPerKb);
    stats.recordExport(5, Constants.SizeConstants.bytesPerKb / 2);
    stats.recordError();
    stats.recordBatchExport();
    stats.recordNetworkExport();

    try std.testing.expectEqual(@as(u64, 15), stats.getSpansExported());
    try std.testing.expectEqual(@as(u64, 1), stats.getExportErrors());
    try std.testing.expectEqual(@as(u64, Constants.SizeConstants.bytesPerKb + (Constants.SizeConstants.bytesPerKb / 2)), stats.getBytesExported());
}

test "Metric helpers" {
    const allocator = std.testing.allocator;

    const config = TelemetryConfig.development();
    var telemetry = try Telemetry.init(allocator, config);
    defer telemetry.deinit();

    try telemetry.recordCounter("requests", 100.0);
    try telemetry.recordGauge("cpu", 45.5);
    try telemetry.recordHistogram("latency", 123.4);

    try std.testing.expectEqual(@as(usize, 3), telemetry.metricCount);
}

fn testCustomCallback() anyerror!void {
    // Test custom export logic
}

test "Custom provider configuration" {
    const config = TelemetryConfig.custom(&testCustomCallback);
    try std.testing.expectEqual(config.provider, .custom);
    try std.testing.expect(config.customExporterFn != null);
    try std.testing.expect(config.enabled);
}

test "High-throughput configuration" {
    const config = TelemetryConfig.highThroughput();
    try std.testing.expect(config.enabled);
    try std.testing.expectEqual(config.provider, .jaeger);
    try std.testing.expectEqual(config.batchSize, Constants.TelemetryDefaults.highThroughputBatchSize);
    try std.testing.expectEqual(config.batchTimeoutMs, Constants.TelemetryDefaults.highThroughputBatchTimeoutMs);
    try std.testing.expectEqual(config.samplingStrategy, .traceIdRatio);
    try std.testing.expect(config.samplingRate < 0.1); // 1% sampling
}

test "Development configuration" {
    const config = TelemetryConfig.development();
    try std.testing.expect(config.enabled);
    try std.testing.expectEqual(config.provider, .file);
    try std.testing.expectEqual(config.samplingStrategy, .alwaysOn);
    try std.testing.expect(config.exporterFilePath != null);
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
    try std.testing.expectEqual(@as(u64, 2), stats.totalSpansCreated);
    try std.testing.expectEqual(@as(u64, 1), stats.totalMetricsRecorded);
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

    try std.testing.expect(span.hasAttributes);
}

test "Span setAttributes batch helper" {
    const allocator = std.testing.allocator;

    const config = TelemetryConfig.development();
    var telemetry = try Telemetry.init(allocator, config);
    defer telemetry.deinit();

    var span = try telemetry.startSpan("batch_attrs", .{});
    defer span.deinit();

    const attrs = [_]Span.AttributeEntry{
        .{ .key = "http.method", .value = .{ .string = "GET" } },
        .{ .key = "http.status_code", .value = .{ .integer = 200 } },
        .{ .key = "cache.hit", .value = .{ .boolean = true } },
    };

    const applied = try span.setAttributes(attrs[0..]);
    try std.testing.expectEqual(@as(usize, 3), applied);
    try std.testing.expect(span.hasAttributes);
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

    try std.testing.expect(span.hasEvents);
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
    try std.testing.expectEqual(ExportMode.asyncBuffer, .asyncBuffer);
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

    const errorRate = stats.getErrorRate();
    try std.testing.expect(errorRate > 0.19 and errorRate < 0.21);
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
    try std.testing.expectEqualStrings(span.traceId, parsed.?.traceId);
    try std.testing.expectEqualStrings(span.spanId, parsed.?.spanId);
}

test "Sampler strategies" {
    // Always on
    var alwaysOn = TelemetrySampler{ .strategy = .alwaysOn, .samplingRate = 0.0 };
    try std.testing.expect(alwaysOn.shouldSample("any_trace_id"));

    // Always off
    var alwaysOff = TelemetrySampler{ .strategy = .alwaysOff, .samplingRate = 1.0 };
    try std.testing.expect(!alwaysOff.shouldSample("any_trace_id"));

    // Parent based (simplified)
    var parentBased = TelemetrySampler{ .strategy = .parentBased, .samplingRate = 0.5 };
    try std.testing.expect(parentBased.shouldSample("any_trace_id"));
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

    try std.testing.expectEqual(@as(usize, 4), telemetry.metricCount);
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

    try std.testing.expect(telemetry.completedSpanCount > 0);
    try std.testing.expect(telemetry.metricCount > 0);

    // Flush should clear pending data
    try telemetry.flush();

    try std.testing.expectEqual(@as(usize, 0), telemetry.completedSpanCount);
    try std.testing.expectEqual(@as(usize, 0), telemetry.metricCount);
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

    try std.testing.expect(telemetry.totalSpansCreated > 0);

    // Reset stats
    telemetry.resetStats();

    try std.testing.expectEqual(@as(u64, 0), telemetry.totalSpansCreated);
    try std.testing.expectEqual(@as(u64, 0), telemetry.totalSpansExported);
    try std.testing.expectEqual(@as(u64, 0), telemetry.totalMetricsRecorded);
}

test "Telemetry getResource and setResource" {
    const allocator = std.testing.allocator;

    var config = TelemetryConfig.development();
    config.serviceName = "test-service";
    var telemetry = try Telemetry.init(allocator, config);
    defer telemetry.deinit();

    const resource = telemetry.getResource();
    try std.testing.expectEqualStrings("test-service", resource.serviceName.?);

    const newResource = Resource{
        .serviceName = "updated-service",
        .serviceVersion = "2.0.0",
        .environment = "staging",
        .datacenter = "us-west-2",
    };
    telemetry.setResource(newResource);

    const updated = telemetry.getResource();
    try std.testing.expectEqualStrings("updated-service", updated.serviceName.?);
    try std.testing.expectEqualStrings("2.0.0", updated.serviceVersion.?);
}

test "Telemetry sampling and context header helpers" {
    const allocator = std.testing.allocator;

    const config = TelemetryConfig.development();
    var telemetry = try Telemetry.init(allocator, config);
    defer telemetry.deinit();

    telemetry.setSampling(.traceIdRatio, 1.5);
    const sampling = telemetry.getSampling();
    try std.testing.expectEqual(TelemetryConfig.SamplingStrategy.traceIdRatio, sampling.strategy);
    try std.testing.expectEqual(@as(f64, 1.0), sampling.rate);

    telemetry.setContextHeaders("x-trace-id", "x-baggage");
    const headers = telemetry.getContextHeaders();
    try std.testing.expectEqualStrings("x-trace-id", headers.traceHeader);
    try std.testing.expectEqualStrings("x-baggage", headers.baggageHeader);

    try std.testing.expect(!telemetry.hasPendingData());

    var span = try telemetry.startSpan("pending_span", .{});
    defer span.deinit();
    span.end();
    try telemetry.endSpan(&span);
    try std.testing.expect(telemetry.hasPendingData());
    try std.testing.expect(telemetry.pendingItemCount() >= 1);

    try telemetry.flush();
    try std.testing.expect(!telemetry.hasPendingData());
}

test "Telemetry metric batch helper" {
    const allocator = std.testing.allocator;

    const config = TelemetryConfig.development();
    var telemetry = try Telemetry.init(allocator, config);
    defer telemetry.deinit();

    const metrics = [_]Telemetry.MetricInput{
        .{ .name = "requests.total", .value = 10.0, .options = .{ .kind = .counter } },
        .{ .name = "cpu.usage", .value = 55.0, .options = .{ .kind = .gauge, .unit = "%" } },
        .{ .name = "latency.ms", .value = 12.5, .options = .{ .kind = .histogram, .unit = "ms" } },
    };

    const recorded = try telemetry.recordMetricsBatch(metrics[0..]);
    try std.testing.expectEqual(@as(usize, 3), recorded);
    try std.testing.expectEqual(@as(usize, 3), telemetry.getMetricCount());
}

test "Telemetry metrics export formats" {
    const allocator = std.testing.allocator;
    const jsonPath = "telemetry-metrics-test.jsonl";
    const promPath = "telemetry-metrics-test.prom";

    defer std.Io.Dir.cwd().deleteFile(Utils.io(), jsonPath) catch {};
    defer std.Io.Dir.cwd().deleteFile(Utils.io(), promPath) catch {};

    var jsonConfig = TelemetryConfig.development();
    jsonConfig.metricFormat = .json;
    jsonConfig.metricsFilePath = jsonPath;

    var telemetryJson = try Telemetry.init(allocator, jsonConfig);
    defer telemetryJson.deinit();

    try telemetryJson.recordCounter("requests.total", 2.0);
    try telemetryJson.exportMetrics();

    const jsonFile = try std.Io.Dir.cwd().openFile(Utils.io(), jsonPath, .{});
    defer jsonFile.close(Utils.io());
    try std.testing.expect((try jsonFile.length(Utils.io())) > 0);

    var promConfig = TelemetryConfig.development();
    promConfig.metricFormat = .prometheus;
    promConfig.metricsFilePath = promPath;

    var telemetryProm = try Telemetry.init(allocator, promConfig);
    defer telemetryProm.deinit();

    try telemetryProm.recordGauge("cpu.usage", 12.5);
    try telemetryProm.exportMetrics();

    const promFile = try std.Io.Dir.cwd().openFile(Utils.io(), promPath, .{});
    defer promFile.close(Utils.io());
    try std.testing.expect((try promFile.length(Utils.io())) > 0);
}

test "Telemetry metric export applies prefix and sanitization" {
    const allocator = std.testing.allocator;
    const path = "telemetry-metrics-prefixed.prom";

    defer std.Io.Dir.cwd().deleteFile(Utils.io(), path) catch {};

    var config = TelemetryConfig.development()
        .withPrometheusMetrics(path)
        .withMetricPrefix("api.v1");
    config.metricPrefixSeparator = ":";

    var telemetry = try Telemetry.init(allocator, config);
    defer telemetry.deinit();

    try telemetry.recordCounter("requests.total", 5.0);
    try telemetry.exportMetrics();

    const body = try std.Io.Dir.cwd().readFileAlloc(Utils.io(), path, allocator, .limited(Constants.BufferSizes.fileRead));
    defer allocator.free(body);

    try std.testing.expect(std.mem.indexOf(u8, body, "api_v1:requests_total") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "requests.total") == null);
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
    try std.testing.expect(span.parentSpanId != null);

    // Test with invalid traceparent (should create root span)
    var rootSpan = try telemetry.startSpanFromTraceparent(
        "root_operation",
        "invalid-header",
        .{},
    );
    defer rootSpan.deinit();

    try std.testing.expect(!rootSpan.isEmpty());
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
