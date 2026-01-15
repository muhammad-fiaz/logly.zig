//! Metrics Collection Module
//!
//! Provides observability and performance monitoring for the logging system.
//! Tracks record counts, throughput, latency, and error rates.
//!
//! Tracked Metrics:
//! - Record Counts: Total, per-level, dropped, errors
//! - Throughput: Records/bytes per second
//! - Latency: Min/max/average processing time
//! - Per-Sink: Individual sink statistics
//!
//! Export Formats:
//! - Text: Human-readable format
//! - JSON: Structured JSON output
//! - Prometheus: Prometheus exposition format
//! - StatsD: StatsD metric format
//!
//! Features:
//! - Lock-free atomic counters for hot paths
//! - Configurable history retention
//! - Threshold-based alerting callbacks
//! - Histogram for latency distribution
//!
//! Performance:
//! - Minimal overhead (1-2% CPU for enabled metrics)
//! - Atomic operations for thread safety

const std = @import("std");
const Config = @import("config.zig").Config;
const Level = @import("level.zig").Level;
const Constants = @import("constants.zig");
const Utils = @import("utils.zig");

/// Metrics collection for logging system observability and performance monitoring.
/// Metrics collection for logging system observability and performance monitoring.
///
/// Tracks various statistics about logging operations including record counts,
/// throughput, latency, and per-sink metrics.
pub const Metrics = struct {
    /// Metric types for threshold notifications.
    pub const MetricType = enum {
        /// Total records logged.
        total_records,
        /// Total bytes written.
        total_bytes,
        /// Records dropped due to overflow.
        dropped_records,
        /// Total error count.
        error_count,
        /// Records per second throughput.
        records_per_second,
        /// Bytes per second throughput.
        bytes_per_second,
    };

    /// Error event types for callbacks.
    pub const ErrorEvent = enum {
        /// Records dropped due to capacity.
        records_dropped,
        /// Sink write failure.
        sink_write_error,
        /// Buffer overflow occurred.
        buffer_overflow,
        /// Record dropped by sampling.
        sampling_drop,
    };

    /// Per-sink metrics for fine-grained observability.
    pub const SinkMetrics = struct {
        /// Sink name identifier.
        name: []const u8,
        /// Total records written to this sink.
        records_written: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        /// Total bytes written to this sink.
        bytes_written: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        /// Number of write errors for this sink.
        write_errors: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        /// Number of flush operations for this sink.
        flush_count: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),

        /// Get total records written.
        pub fn getRecordsWritten(self: *const SinkMetrics) u64 {
            return Utils.atomicLoadU64(&self.records_written);
        }

        /// Get total bytes written.
        pub fn getBytesWritten(self: *const SinkMetrics) u64 {
            return Utils.atomicLoadU64(&self.bytes_written);
        }

        /// Get write errors count.
        pub fn getWriteErrors(self: *const SinkMetrics) u64 {
            return Utils.atomicLoadU64(&self.write_errors);
        }

        /// Get flush count.
        pub fn getFlushCount(self: *const SinkMetrics) u64 {
            return Utils.atomicLoadU64(&self.flush_count);
        }

        /// Check if any records have been written.
        pub fn hasWritten(self: *const SinkMetrics) bool {
            return self.getRecordsWritten() > 0;
        }

        /// Check if any errors have occurred.
        pub fn hasErrors(self: *const SinkMetrics) bool {
            return self.getWriteErrors() > 0;
        }

        /// Get write error rate for this sink.
        pub fn getErrorRate(self: *const SinkMetrics) f64 {
            return Utils.calculateErrorRate(
                self.getWriteErrors(),
                self.getRecordsWritten(),
            );
        }

        /// Get success rate (0.0 - 1.0).
        pub fn getSuccessRate(self: *const SinkMetrics) f64 {
            return 1.0 - self.getErrorRate();
        }

        /// Get average bytes per record.
        pub fn avgBytesPerRecord(self: *const SinkMetrics) f64 {
            return Utils.calculateAverage(
                self.getBytesWritten(),
                self.getRecordsWritten(),
            );
        }

        /// Get average records per flush.
        pub fn avgRecordsPerFlush(self: *const SinkMetrics) f64 {
            return Utils.calculateAverage(
                self.getRecordsWritten(),
                self.getFlushCount(),
            );
        }

        /// Calculate throughput (bytes per second).
        pub fn throughputBytesPerSecond(self: *const SinkMetrics, elapsed_seconds: f64) f64 {
            return Utils.safeFloatDiv(
                @as(f64, @floatFromInt(self.getBytesWritten())),
                elapsed_seconds,
            );
        }

        /// Reset all statistics to initial state.
        pub fn reset(self: *SinkMetrics) void {
            self.records_written.store(0, .monotonic);
            self.bytes_written.store(0, .monotonic);
            self.write_errors.store(0, .monotonic);
            self.flush_count.store(0, .monotonic);
        }
    };

    /// Snapshot of current metrics for reporting.
    pub const Snapshot = struct {
        /// Total records logged.
        total_records: u64,
        /// Total bytes written.
        total_bytes: u64,
        /// Records dropped due to overflow.
        dropped_records: u64,
        /// Total error count.
        error_count: u64,
        /// Time since metrics start in milliseconds.
        uptime_ms: i64,
        /// Current records per second.
        records_per_second: f64,
        /// Current bytes per second.
        bytes_per_second: f64,
        /// Record counts per level (indexed by LevelIndex).
        level_counts: [10]u64,

        /// Get drop rate (0.0 - 1.0).
        pub fn getDropRate(self: *const Snapshot) f64 {
            if (self.total_records == 0) return 0;
            return @as(f64, @floatFromInt(self.dropped_records)) / @as(f64, @floatFromInt(self.total_records));
        }
    };

    /// Level index mapping for metrics array.
    pub const LevelIndex = enum(u4) {
        trace = 0,
        debug = 1,
        info = 2,
        notice = 3,
        success = 4,
        warning = 5,
        err = 6,
        fail = 7,
        critical = 8,
        fatal = 9,
    };

    /// Re-export MetricsConfig from global config.
    pub const MetricsConfig = Config.MetricsConfig;

    /// Mutex for thread-safe operations.
    mutex: std.Thread.Mutex = .{},
    /// Metrics configuration.
    config: MetricsConfig = .{},

    /// Total records logged.
    total_records: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
    /// Total bytes written.
    total_bytes: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
    /// Records dropped due to overflow.
    dropped_records: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
    /// Total error count.
    error_count: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),

    /// Per-level record counts.
    level_counts: [10]std.atomic.Value(Constants.AtomicUnsigned) = [_]std.atomic.Value(Constants.AtomicUnsigned){std.atomic.Value(Constants.AtomicUnsigned).init(0)} ** 10,

    /// Metrics collection start time.
    start_time: i64,
    /// Timestamp of last record logged.
    last_record_time: std.atomic.Value(Constants.AtomicSigned) = std.atomic.Value(Constants.AtomicSigned).init(0),

    /// Total latency in nanoseconds (for average calculation).
    total_latency_ns: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
    /// Minimum latency observed in nanoseconds.
    min_latency_ns: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(std.math.maxInt(Constants.AtomicUnsigned)),
    /// Maximum latency observed in nanoseconds.
    max_latency_ns: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),

    /// Histogram buckets for latency distribution.
    histogram: [20]std.atomic.Value(Constants.AtomicUnsigned) = [_]std.atomic.Value(Constants.AtomicUnsigned){std.atomic.Value(Constants.AtomicUnsigned).init(0)} ** 20,

    /// Snapshot history for trend analysis.
    history: std.ArrayList(Snapshot),

    /// Per-sink metrics list.
    sink_metrics: std.ArrayList(SinkMetrics),
    /// Memory allocator.
    allocator: std.mem.Allocator,

    /// Callback invoked when a record is logged.
    /// Parameters: (level: Level, bytes: u64)
    on_record_logged: ?*const fn (Level, u64) void = null,

    /// Callback invoked when metrics snapshot is taken.
    /// Parameters: (snapshot: *const Snapshot)
    on_metrics_snapshot: ?*const fn (*const Snapshot) void = null,

    /// Callback invoked when metrics exceed thresholds.
    /// Parameters: (metric: MetricType, value: u64, threshold: u64)
    on_threshold_exceeded: ?*const fn (MetricType, u64, u64) void = null,

    /// Callback invoked when errors or dropped records detected.
    /// Parameters: (event_type: ErrorEvent, count: u64)
    on_error_detected: ?*const fn (ErrorEvent, u64) void = null,

    /// Maps a Level enum value to a LevelIndex for the metrics array.
    /// Performance: O(1) - direct switch without allocations
    fn levelToIndex(level: Level) u4 {
        return switch (level) {
            .trace => 0,
            .debug => 1,
            .info => 2,
            .notice => 3,
            .success => 4,
            .warning => 5,
            .err => 6,
            .fail => 7,
            .critical => 8,
            .fatal => 9,
        };
    }

    /// Maps an index back to a histogram bucket boundary (in nanoseconds).
    fn histogramBucketBoundary(bucket: usize) u64 {
        // Exponential buckets: 1us, 10us, 100us, 1ms, 10ms, 100ms, 1s, etc.
        const boundaries = [_]u64{
            1_000,         2_000,                5_000,     10_000,     20_000,     50_000,     100_000,     200_000,     500_000,
            1_000_000,     2_000_000,            5_000_000, 10_000_000, 20_000_000, 50_000_000, 100_000_000, 200_000_000, 500_000_000,
            1_000_000_000, std.math.maxInt(u64),
        };
        return if (bucket < boundaries.len) boundaries[bucket] else std.math.maxInt(u64);
    }

    /// Maps a LevelIndex back to a Level name string.
    pub fn indexToLevelName(index: usize) []const u8 {
        return switch (index) {
            0 => "TRACE",
            1 => "DEBUG",
            2 => "INFO",
            3 => "NOTICE",
            4 => "SUCCESS",
            5 => "WARNING",
            6 => "ERROR",
            7 => "FAIL",
            8 => "CRITICAL",
            9 => "FATAL",
            else => "UNKNOWN",
        };
    }

    /// Initializes a new Metrics instance with default configuration.
    pub fn init(allocator: std.mem.Allocator) Metrics {
        return initWithConfig(allocator, .{});
    }

    /// Alias for init().
    pub const create = init;

    /// Initializes a new Metrics instance with custom configuration.
    pub fn initWithConfig(allocator: std.mem.Allocator, config: MetricsConfig) Metrics {
        return .{
            .start_time = std.time.milliTimestamp(),
            .sink_metrics = .empty,
            .history = .empty,
            .allocator = allocator,
            .config = config,
        };
    }

    /// Releases all resources associated with the metrics.
    pub fn deinit(self: *Metrics) void {
        for (self.sink_metrics.items) |metric| {
            self.allocator.free(metric.name);
        }
        self.sink_metrics.deinit(self.allocator);
        self.history.deinit(self.allocator);
    }

    /// Alias for deinit().
    pub const destroy = deinit;

    /// Sets the callback for record logged events.
    pub fn setRecordLoggedCallback(self: *Metrics, callback: *const fn (Level, u64) void) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.on_record_logged = callback;
    }

    /// Sets the callback for metrics snapshot events.
    pub fn setSnapshotCallback(self: *Metrics, callback: *const fn (*const Snapshot) void) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.on_metrics_snapshot = callback;
    }

    /// Sets the callback for threshold exceeded events.
    pub fn setThresholdCallback(self: *Metrics, callback: *const fn (MetricType, u64, u64) void) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.on_threshold_exceeded = callback;
    }

    /// Sets the callback for error detected events.
    pub fn setErrorCallback(self: *Metrics, callback: *const fn (ErrorEvent, u64) void) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.on_error_detected = callback;
    }

    /// Returns the current configuration.
    pub fn getConfig(self: *const Metrics) MetricsConfig {
        return self.config;
    }

    /// Checks if metrics collection is enabled.
    pub fn isEnabled(self: *const Metrics) bool {
        return self.config.enabled;
    }

    /// Records a new log record.
    /// Basic counting always works; advanced features (thresholds, callbacks) require config.enabled = true.
    pub fn recordLog(self: *Metrics, level: Level, bytes: u64) void {
        _ = self.total_records.fetchAdd(1, .monotonic);
        _ = self.total_bytes.fetchAdd(@truncate(bytes), .monotonic);

        if (self.config.track_levels) {
            const level_index = levelToIndex(level);
            _ = self.level_counts[level_index].fetchAdd(1, .monotonic);
        }

        self.last_record_time.store(@truncate(std.time.milliTimestamp()), .monotonic);

        // Advanced features only when enabled
        if (self.config.enabled) {
            // Check thresholds
            self.checkThresholds();

            // Invoke callback if set
            if (self.on_record_logged) |callback| {
                callback(level, bytes);
            }
        }
    }

    /// Records a log with latency measurement.
    pub fn recordLogWithLatency(self: *Metrics, level: Level, bytes: u64, latency_ns: u64) void {
        self.recordLog(level, bytes);

        if (!self.config.track_latency) return;

        _ = self.total_latency_ns.fetchAdd(@truncate(latency_ns), .monotonic);

        // Update min latency
        var current_min = self.min_latency_ns.load(.monotonic);
        while (latency_ns < current_min) {
            const result = self.min_latency_ns.cmpxchgWeak(current_min, @truncate(latency_ns), .monotonic, .monotonic);
            if (result) |new_current| {
                current_min = new_current;
            } else {
                break;
            }
        }

        // Update max latency
        var current_max = self.max_latency_ns.load(.monotonic);
        while (latency_ns > current_max) {
            const result = self.max_latency_ns.cmpxchgWeak(current_max, @truncate(latency_ns), .monotonic, .monotonic);
            if (result) |new_current| {
                current_max = new_current;
            } else {
                break;
            }
        }

        // Update histogram if enabled
        if (self.config.enable_histogram) {
            const bucket = self.getHistogramBucket(latency_ns);
            if (bucket < self.histogram.len) {
                _ = self.histogram[bucket].fetchAdd(1, .monotonic);
            }
        }
    }

    /// Get histogram bucket for a latency value.
    fn getHistogramBucket(self: *const Metrics, latency_ns: u64) usize {
        _ = self;
        var bucket: usize = 0;
        while (bucket < 20) : (bucket += 1) {
            if (latency_ns <= histogramBucketBoundary(bucket)) {
                return bucket;
            }
        }
        return 19;
    }

    /// Check thresholds and invoke callback if exceeded.
    fn checkThresholds(self: *Metrics) void {
        if (self.on_threshold_exceeded == null) return;

        const callback = self.on_threshold_exceeded.?;

        // Check error rate threshold
        if (self.config.error_rate_threshold > 0) {
            const err_rate = self.errorRate();
            if (err_rate > self.config.error_rate_threshold) {
                callback(.error_count, self.errorCount(), @intFromFloat(self.config.error_rate_threshold * 100));
            }
        }

        // Check drop rate threshold
        if (self.config.drop_rate_threshold > 0) {
            const drop_rate_val = self.dropRate();
            if (drop_rate_val > self.config.drop_rate_threshold) {
                callback(.dropped_records, self.droppedCount(), @intFromFloat(self.config.drop_rate_threshold * 100));
            }
        }

        // Check max records per second
        if (self.config.max_records_per_second > 0) {
            const rps = self.rate();
            if (rps > @as(f64, @floatFromInt(self.config.max_records_per_second))) {
                callback(.records_per_second, @intFromFloat(rps), self.config.max_records_per_second);
            }
        }
    }

    /// Records a dropped log record.
    pub fn recordDrop(self: *Metrics) void {
        _ = self.dropped_records.fetchAdd(1, .monotonic);
        if (self.on_error_detected) |callback| {
            callback(.records_dropped, self.droppedCount());
        }
    }

    /// Records an error.
    pub fn recordError(self: *Metrics) void {
        _ = self.error_count.fetchAdd(1, .monotonic);
        if (self.on_error_detected) |callback| {
            callback(.sink_write_error, self.errorCount());
        }
    }

    /// Adds a sink to track.
    ///
    /// Arguments:
    ///     name: The name of the sink.
    ///
    /// Returns:
    ///     The index of the sink in the metrics array.
    pub fn addSink(self: *Metrics, name: []const u8) !usize {
        self.mutex.lock();
        defer self.mutex.unlock();

        const owned_name = try self.allocator.dupe(u8, name);
        try self.sink_metrics.append(self.allocator, .{ .name = owned_name });
        return self.sink_metrics.items.len - 1;
    }

    /// Records a successful write to a sink.
    ///
    /// Arguments:
    ///     sink_index: The index of the sink.
    ///     bytes: The number of bytes written.
    pub fn recordSinkWrite(self: *Metrics, sink_index: usize, bytes: u64) void {
        if (sink_index < self.sink_metrics.items.len) {
            _ = self.sink_metrics.items[sink_index].records_written.fetchAdd(@as(Constants.AtomicUnsigned, 1), .monotonic);
            _ = self.sink_metrics.items[sink_index].bytes_written.fetchAdd(@truncate(bytes), .monotonic);
        }
    }

    /// Records a write error on a sink.
    ///
    /// Arguments:
    ///     sink_index: The index of the sink.
    pub fn recordSinkError(self: *Metrics, sink_index: usize) void {
        if (sink_index < self.sink_metrics.items.len) {
            _ = self.sink_metrics.items[sink_index].write_errors.fetchAdd(@as(Constants.AtomicUnsigned, 1), .monotonic);
        }
    }

    /// Gets a snapshot of current metrics.
    ///
    /// Returns:
    ///     A snapshot of the current metrics state.
    pub fn getSnapshot(self: *Metrics) Snapshot {
        const now = std.time.milliTimestamp();
        const uptime_ms = now - self.start_time;
        const uptime_sec = @as(f64, @floatFromInt(uptime_ms)) / 1000.0;

        const total_records = @as(u64, self.total_records.load(.monotonic));
        const total_bytes = @as(u64, self.total_bytes.load(.monotonic));

        var level_counts: [10]u64 = undefined;
        for (0..10) |i| {
            level_counts[i] = @as(u64, self.level_counts[i].load(.monotonic));
        }

        return .{
            .total_records = total_records,
            .total_bytes = total_bytes,
            .dropped_records = @as(u64, self.dropped_records.load(.monotonic)),
            .error_count = @as(u64, self.error_count.load(.monotonic)),
            .uptime_ms = uptime_ms,
            .records_per_second = if (uptime_sec > 0) @as(f64, @floatFromInt(total_records)) / uptime_sec else 0,
            .bytes_per_second = if (uptime_sec > 0) @as(f64, @floatFromInt(total_bytes)) / uptime_sec else 0,
            .level_counts = level_counts,
        };
    }

    /// Takes a snapshot and optionally stores in history.
    pub fn takeSnapshot(self: *Metrics) !Snapshot {
        const snapshot = self.getSnapshot();

        // Store in history if configured
        if (self.config.history_size > 0) {
            self.mutex.lock();
            defer self.mutex.unlock();

            // Remove oldest if at capacity
            if (self.history.items.len >= self.config.history_size) {
                _ = self.history.orderedRemove(0);
            }

            try self.history.append(self.allocator, snapshot);
        }

        // Invoke callback
        if (self.on_metrics_snapshot) |callback| {
            callback(&snapshot);
        }

        return snapshot;
    }

    /// Get snapshot history.
    pub fn getHistory(self: *const Metrics) []const Snapshot {
        return self.history.items;
    }

    /// Resets all metrics to zero.
    pub fn reset(self: *Metrics) void {
        self.total_records.store(@as(Constants.AtomicUnsigned, 0), .monotonic);
        self.total_bytes.store(@as(Constants.AtomicUnsigned, 0), .monotonic);
        self.dropped_records.store(@as(Constants.AtomicUnsigned, 0), .monotonic);
        self.error_count.store(@as(Constants.AtomicUnsigned, 0), .monotonic);
        self.start_time = std.time.milliTimestamp();

        // Reset latency
        self.total_latency_ns.store(@as(Constants.AtomicUnsigned, 0), .monotonic);
        self.min_latency_ns.store(std.math.maxInt(Constants.AtomicUnsigned), .monotonic);
        self.max_latency_ns.store(@as(Constants.AtomicUnsigned, 0), .monotonic);

        // Reset histogram
        for (0..20) |i| {
            self.histogram[i].store(@as(Constants.AtomicUnsigned, 0), .monotonic);
        }

        for (0..10) |i| {
            self.level_counts[i].store(@as(Constants.AtomicUnsigned, 0), .monotonic);
        }

        for (self.sink_metrics.items) |*metric| {
            metric.records_written.store(@as(Constants.AtomicUnsigned, 0), .monotonic);
            metric.bytes_written.store(@as(Constants.AtomicUnsigned, 0), .monotonic);
            metric.write_errors.store(@as(Constants.AtomicUnsigned, 0), .monotonic);
            metric.flush_count.store(@as(Constants.AtomicUnsigned, 0), .monotonic);
        }

        // Clear history
        self.history.clearRetainingCapacity();
    }

    /// Export metrics in configured format.
    pub fn exportMetrics(self: *Metrics, allocator: std.mem.Allocator) ![]u8 {
        return switch (self.config.export_format) {
            .text => self.format(allocator),
            .json => self.exportJson(allocator),
            .prometheus => self.exportPrometheus(allocator),
            .statsd => self.exportStatsd(allocator),
        };
    }

    /// Export as JSON format.
    pub fn exportJson(self: *Metrics, allocator: std.mem.Allocator) ![]u8 {
        const snapshot = self.getSnapshot();
        return try std.fmt.allocPrint(allocator,
            \\{{"total_records":{d},"total_bytes":{d},"dropped":{d},"errors":{d},"uptime_ms":{d},"rps":{d:.2},"bps":{d:.2}}}
        , .{
            snapshot.total_records,
            snapshot.total_bytes,
            snapshot.dropped_records,
            snapshot.error_count,
            snapshot.uptime_ms,
            snapshot.records_per_second,
            snapshot.bytes_per_second,
        });
    }

    /// Export as Prometheus format.
    pub fn exportPrometheus(self: *Metrics, allocator: std.mem.Allocator) ![]u8 {
        const snapshot = self.getSnapshot();
        var buf: std.ArrayList(u8) = .empty;
        errdefer buf.deinit(allocator);
        const writer = buf.writer(allocator);

        try writer.writeAll("# HELP logly_records_total Total log records\n");
        try writer.writeAll("# TYPE logly_records_total counter\n");
        try writer.writeAll("logly_records_total ");
        try Utils.writeInt(writer, snapshot.total_records);
        try writer.writeByte('\n');

        try writer.writeAll("# HELP logly_bytes_total Total bytes logged\n");
        try writer.writeAll("# TYPE logly_bytes_total counter\n");
        try writer.writeAll("logly_bytes_total ");
        try Utils.writeInt(writer, snapshot.total_bytes);
        try writer.writeByte('\n');

        try writer.writeAll("# HELP logly_dropped_total Dropped records\n");
        try writer.writeAll("# TYPE logly_dropped_total counter\n");
        try writer.writeAll("logly_dropped_total ");
        try Utils.writeInt(writer, snapshot.dropped_records);
        try writer.writeByte('\n');

        try writer.writeAll("# HELP logly_errors_total Error count\n");
        try writer.writeAll("# TYPE logly_errors_total counter\n");
        try writer.writeAll("logly_errors_total ");
        try Utils.writeInt(writer, snapshot.error_count);
        try writer.writeByte('\n');

        try writer.writeAll("# HELP logly_records_per_second Records per second\n");
        try writer.writeAll("# TYPE logly_records_per_second gauge\n");
        try writer.writeAll("logly_records_per_second ");
        try writer.print("{d:.2}", .{snapshot.records_per_second});
        try writer.writeByte('\n');

        return buf.toOwnedSlice(allocator);
    }

    /// Export as StatsD format.
    pub fn exportStatsd(self: *Metrics, allocator: std.mem.Allocator) ![]u8 {
        const snapshot = self.getSnapshot();
        return try std.fmt.allocPrint(allocator,
            \\logly.records.total:{d}|c
            \\logly.bytes.total:{d}|c
            \\logly.dropped.total:{d}|c
            \\logly.errors.total:{d}|c
            \\logly.rps:{d:.2}|g
        , .{
            snapshot.total_records,
            snapshot.total_bytes,
            snapshot.dropped_records,
            snapshot.error_count,
            snapshot.records_per_second,
        });
    }

    /// Get average latency in nanoseconds.
    pub fn avgLatencyNs(self: *const Metrics) u64 {
        const total = @as(u64, self.total_records.load(.monotonic));
        if (total == 0) return 0;
        const latency = @as(u64, self.total_latency_ns.load(.monotonic));
        return latency / total;
    }

    /// Get min latency in nanoseconds.
    pub fn minLatencyNs(self: *const Metrics) u64 {
        const min = self.min_latency_ns.load(.monotonic);
        if (min == std.math.maxInt(Constants.AtomicUnsigned)) return 0;
        return @as(u64, min);
    }

    /// Get max latency in nanoseconds.
    pub fn maxLatencyNs(self: *const Metrics) u64 {
        return @as(u64, self.max_latency_ns.load(.monotonic));
    }

    /// Get histogram data.
    pub fn getHistogram(self: *const Metrics) [20]u64 {
        var result: [20]u64 = undefined;
        for (0..20) |i| {
            result[i] = @as(u64, self.histogram[i].load(.monotonic));
        }
        return result;
    }

    /// Formats metrics as a human-readable string.
    ///
    /// Arguments:
    ///     allocator: Allocator for the result string.
    ///
    /// Returns:
    ///     A formatted string describing the metrics (caller must free).
    pub fn format(self: *Metrics, allocator: std.mem.Allocator) ![]u8 {
        const snapshot = self.getSnapshot();
        return try std.fmt.allocPrint(allocator,
            \\Logly Metrics
            \\  Total Records: {d}
            \\  Total Bytes: {d}
            \\  Dropped: {d}
            \\  Errors: {d}
            \\  Uptime: {d}ms
            \\  Rate: {d:.2} records/sec
            \\  Throughput: {d:.2} bytes/sec
        , .{
            snapshot.total_records,
            snapshot.total_bytes,
            snapshot.dropped_records,
            snapshot.error_count,
            snapshot.uptime_ms,
            snapshot.records_per_second,
            snapshot.bytes_per_second,
        });
    }

    /// Formats level breakdown as a human-readable string.
    ///
    /// Arguments:
    ///     allocator: Allocator for the result string.
    ///
    /// Returns:
    ///     A formatted string describing levels with counts > 0 (caller must free).
    pub fn formatLevelBreakdown(self: *Metrics, allocator: std.mem.Allocator) ![]u8 {
        const snapshot = self.getSnapshot();
        var buf: std.ArrayList(u8) = .empty;
        errdefer buf.deinit(allocator);
        const writer = buf.writer(allocator);

        try writer.writeAll("Level Breakdown:");
        var has_levels = false;
        for (0..10) |i| {
            const count = snapshot.level_counts[i];
            if (count > 0) {
                if (has_levels) {
                    try writer.writeAll(",");
                }
                try writer.writeByte(' ');
                try writer.writeAll(indexToLevelName(i));
                try writer.writeByte(':');
                try Utils.writeInt(writer, count);
                has_levels = true;
            }
        }
        if (!has_levels) {
            try writer.writeAll(" (none)");
        }

        return buf.toOwnedSlice(allocator);
    }

    /// Records a log for a custom level.
    /// Custom levels use the same total_records and total_bytes counters.
    pub fn recordCustomLog(self: *Metrics, bytes: u64) void {
        _ = self.total_records.fetchAdd(1, .monotonic);
        _ = self.total_bytes.fetchAdd(@truncate(bytes), .monotonic);
        self.last_record_time.store(@truncate(std.time.milliTimestamp()), .monotonic);
    }

    /// Alias for recordLog
    pub const record = recordLog;
    pub const log = recordLog;

    /// Alias for recordDrop
    pub const drop = recordDrop;
    pub const dropped = recordDrop;

    /// Alias for recordError
    pub const recordErr = recordError;

    /// Alias for getSnapshot
    pub const metricsSnapshot = getSnapshot;

    /// Alias for formatLevelBreakdown
    pub const levels = formatLevelBreakdown;
    pub const breakdown = formatLevelBreakdown;

    /// Returns true if any records have been logged.
    pub fn hasRecords(self: *const Metrics) bool {
        return self.total_records.load(.monotonic) > 0;
    }

    /// Returns the total record count.
    pub fn totalRecordCount(self: *const Metrics) u64 {
        return @as(u64, self.total_records.load(.monotonic));
    }

    /// Returns the total bytes logged.
    pub fn totalBytesLogged(self: *const Metrics) u64 {
        return @as(u64, self.total_bytes.load(.monotonic));
    }

    /// Returns the uptime in milliseconds.
    pub fn uptime(self: *const Metrics) i64 {
        return std.time.milliTimestamp() - self.start_time;
    }

    /// Returns records per second rate.
    pub fn rate(self: *Metrics) f64 {
        const snapshot_data = self.getSnapshot();
        return snapshot_data.records_per_second;
    }

    /// Returns the error count.
    pub fn errorCount(self: *const Metrics) u64 {
        return @as(u64, self.error_count.load(.monotonic));
    }

    /// Returns the dropped records count.
    pub fn droppedCount(self: *const Metrics) u64 {
        return @as(u64, self.dropped_records.load(.monotonic));
    }

    /// Returns the error rate (0.0 - 1.0).
    pub fn errorRate(self: *const Metrics) f64 {
        const total = self.totalRecordCount();
        if (total == 0) return 0;
        const errors = self.errorCount();
        return @as(f64, @floatFromInt(errors)) / @as(f64, @floatFromInt(total));
    }

    /// Returns the drop rate (0.0 - 1.0).
    pub fn dropRate(self: *const Metrics) f64 {
        const total = self.totalRecordCount();
        if (total == 0) return 0;
        const drops = self.droppedCount();
        return @as(f64, @floatFromInt(drops)) / @as(f64, @floatFromInt(total));
    }

    /// Returns true if error rate exceeds threshold.
    pub fn hasHighErrorRate(self: *const Metrics, threshold: f64) bool {
        return self.errorRate() > threshold;
    }

    /// Returns true if drop rate exceeds threshold.
    pub fn hasHighDropRate(self: *const Metrics, threshold: f64) bool {
        return self.dropRate() > threshold;
    }

    /// Returns count for specific level.
    pub fn levelCount(self: *const Metrics, level: Level) u64 {
        const idx = levelToIndex(level);
        return @as(u64, self.level_counts[idx].load(.monotonic));
    }

    /// Returns the number of sinks being tracked.
    pub fn sinkCount(self: *const Metrics) usize {
        return self.sink_metrics.items.len;
    }

    /// Returns uptime in seconds.
    pub fn uptimeSeconds(self: *const Metrics) f64 {
        return @as(f64, @floatFromInt(self.uptime())) / 1000.0;
    }

    /// Records a flush operation on a sink.
    pub fn recordSinkFlush(self: *Metrics, sink_index: usize) void {
        if (sink_index < self.sink_metrics.items.len) {
            _ = self.sink_metrics.items[sink_index].flush_count.fetchAdd(1, .monotonic);
        }
    }

    /// Get sink metrics by index.
    pub fn getSinkMetrics(self: *const Metrics, sink_index: usize) ?SinkMetrics {
        if (sink_index < self.sink_metrics.items.len) {
            return self.sink_metrics.items[sink_index];
        }
        return null;
    }

    /// Get sink metrics by name.
    pub fn getSinkMetricsByName(self: *const Metrics, name: []const u8) ?SinkMetrics {
        for (self.sink_metrics.items) |metric| {
            if (std.mem.eql(u8, metric.name, name)) {
                return metric;
            }
        }
        return null;
    }

    /// Returns true if any errors have occurred.
    pub fn hasErrors(self: *const Metrics) bool {
        return self.errorCount() > 0;
    }

    /// Returns true if any records have been dropped.
    pub fn hasDropped(self: *const Metrics) bool {
        return self.droppedCount() > 0;
    }

    /// Get bytes per second throughput.
    pub fn bytesPerSecond(self: *Metrics) f64 {
        const snapshot_data = self.getSnapshot();
        return snapshot_data.bytes_per_second;
    }

    /// Alias for reset
    pub const clear = reset;

    /// Alias for uptimeSeconds
    pub const uptimeSec = uptimeSeconds;

    /// Alias for bytesPerSecond
    pub const throughput = bytesPerSecond;
};

/// Pre-built metrics configurations.
pub const MetricsPresets = struct {
    /// Creates a basic metrics instance.
    pub fn basic(allocator: std.mem.Allocator) Metrics {
        return Metrics.init(allocator);
    }

    /// Creates a metrics sink configuration.
    pub fn createMetricsSink(file_path: []const u8) @import("sink.zig").SinkConfig {
        return .{
            .path = file_path,
            .json = true,
            .color = false,
        };
    }
};

test "metrics basic" {
    var metrics = Metrics.init(std.testing.allocator);
    defer metrics.deinit();

    metrics.recordLog(.info, 100);
    metrics.recordLog(.info, 150);
    metrics.recordError();

    const snapshot_data = metrics.getSnapshot();
    try std.testing.expectEqual(@as(u64, 2), snapshot_data.total_records);
    try std.testing.expectEqual(@as(u64, 250), snapshot_data.total_bytes);
    try std.testing.expectEqual(@as(u64, 1), snapshot_data.error_count);
}

test "metrics rates" {
    var metrics = Metrics.init(std.testing.allocator);
    defer metrics.deinit();

    metrics.recordLog(.info, 100);
    metrics.recordError();
    metrics.recordDrop();

    try std.testing.expect(metrics.errorRate() > 0);
    try std.testing.expect(metrics.dropRate() > 0);
}

test "metrics level count" {
    var metrics = Metrics.init(std.testing.allocator);
    defer metrics.deinit();

    metrics.recordLog(.info, 50);
    metrics.recordLog(.info, 50);
    metrics.recordLog(.err, 100);

    try std.testing.expectEqual(@as(u64, 2), metrics.levelCount(.info));
    try std.testing.expectEqual(@as(u64, 1), metrics.levelCount(.err));
}

test "metrics reset" {
    var metrics = Metrics.init(std.testing.allocator);
    defer metrics.deinit();

    metrics.recordLog(.info, 100);
    try std.testing.expect(metrics.hasRecords());

    metrics.reset();
    try std.testing.expect(!metrics.hasRecords());
}

test "metrics sink tracking" {
    var metrics = Metrics.init(std.testing.allocator);
    defer metrics.deinit();

    const idx = try metrics.addSink("test_sink");
    metrics.recordSinkWrite(idx, 100);
    metrics.recordSinkFlush(idx);

    const sink = metrics.getSinkMetrics(idx);
    try std.testing.expect(sink != null);
    try std.testing.expectEqual(@as(u64, 1), sink.?.records_written.load(.monotonic));
    try std.testing.expectEqual(@as(u64, 100), sink.?.bytes_written.load(.monotonic));
    try std.testing.expectEqual(@as(u64, 1), sink.?.flush_count.load(.monotonic));
}

test "metrics callback setters" {
    var metrics = Metrics.init(std.testing.allocator);
    defer metrics.deinit();

    // Test that setters don't crash
    const S = struct {
        fn logCallback(_: Level, _: u64) void {}
        fn snapshotCallback(_: *const Metrics.Snapshot) void {}
        fn thresholdCallback(_: Metrics.MetricType, _: u64, _: u64) void {}
        fn errorCallback(_: Metrics.ErrorEvent, _: u64) void {}
    };

    metrics.setRecordLoggedCallback(S.logCallback);
    metrics.setSnapshotCallback(S.snapshotCallback);
    metrics.setThresholdCallback(S.thresholdCallback);
    metrics.setErrorCallback(S.errorCallback);

    try std.testing.expect(metrics.on_record_logged != null);
    try std.testing.expect(metrics.on_metrics_snapshot != null);
}

test "metrics helper methods" {
    var metrics = Metrics.init(std.testing.allocator);
    defer metrics.deinit();

    metrics.recordLog(.info, 100);
    metrics.recordError();
    metrics.recordDrop();

    try std.testing.expect(metrics.hasErrors());
    try std.testing.expect(metrics.hasDropped());
    try std.testing.expect(metrics.isEnabled() == false); // default config has enabled = false
}
