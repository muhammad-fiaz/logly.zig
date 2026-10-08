//! Metrics collection.
//!
//! Atomic counters for records, throughput, latency, and errors, with text/JSON/Prometheus/StatsD export.
const std = @import("std");
const Config = @import("config.zig").Config;
const Level = @import("level.zig").Level;
const Constants = @import("constants.zig");
const Utils = @import("utils.zig");

/// Metrics collection for logging system observability and performance monitoring.
///
/// Tracks various statistics about logging operations including record counts,
/// throughput, latency, and per-sink metrics.
pub const Metrics = struct {
    /// Metric types for threshold notifications.
    pub const MetricType = enum {
        /// Total records logged.
        totalRecords,
        /// Total bytes written.
        totalBytes,
        /// Records dropped due to overflow.
        droppedRecords,
        /// Total error count.
        errorCount,
        /// Records per second throughput.
        recordsPerSecond,
        /// Bytes per second throughput.
        bytesPerSecond,
    };

    /// Error event types for callbacks.
    pub const ErrorEvent = enum {
        /// Records dropped due to capacity.
        recordsDropped,
        /// Sink write failure.
        sinkWriteError,
        /// Buffer overflow occurred.
        bufferOverflow,
        /// Record dropped by sampling.
        samplingDrop,
    };

    /// Per-sink metrics for fine-grained observability.
    pub const SinkMetrics = struct {
        /// Sink name identifier.
        name: []const u8,
        /// Total records written to this sink.
        recordsWritten: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        /// Total bytes written to this sink.
        bytesWritten: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        /// Number of write errors for this sink.
        writeErrors: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        /// Number of flush operations for this sink.
        flushCount: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),

        /// Get total records written.
        pub fn getRecordsWritten(self: *const SinkMetrics) u64 {
            return Utils.atomicLoadU64(&self.recordsWritten);
        }

        /// Get total bytes written.
        pub fn getBytesWritten(self: *const SinkMetrics) u64 {
            return Utils.atomicLoadU64(&self.bytesWritten);
        }

        /// Get write errors count.
        pub fn getWriteErrors(self: *const SinkMetrics) u64 {
            return Utils.atomicLoadU64(&self.writeErrors);
        }

        /// Get flush count.
        pub fn getFlushCount(self: *const SinkMetrics) u64 {
            return Utils.atomicLoadU64(&self.flushCount);
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
                Utils.atomicLoadU64(&self.writeErrors),
                Utils.atomicLoadU64(&self.recordsWritten),
            );
        }

        /// Get success rate (0.0 - 1.0).
        pub fn getSuccessRate(self: *const SinkMetrics) f64 {
            return 1.0 - self.getErrorRate();
        }

        /// Get average bytes per record.
        pub fn avgBytesPerRecord(self: *const SinkMetrics) f64 {
            return Utils.calculateAverage(
                Utils.atomicLoadU64(&self.bytesWritten),
                Utils.atomicLoadU64(&self.recordsWritten),
            );
        }

        /// Get average records per flush.
        pub fn avgRecordsPerFlush(self: *const SinkMetrics) f64 {
            return Utils.calculateAverage(
                Utils.atomicLoadU64(&self.recordsWritten),
                Utils.atomicLoadU64(&self.flushCount),
            );
        }

        /// Calculate throughput (bytes per second).
        pub fn throughputBytesPerSecond(self: *const SinkMetrics, elapsedSeconds: f64) f64 {
            return Utils.safeFloatDiv(
                @as(f64, @floatFromInt(Utils.atomicLoadU64(&self.bytesWritten))),
                elapsedSeconds,
            );
        }

        /// Reset all statistics to initial state.
        pub fn reset(self: *SinkMetrics) void {
            self.recordsWritten.store(0, .monotonic);
            self.bytesWritten.store(0, .monotonic);
            self.writeErrors.store(0, .monotonic);
            self.flushCount.store(0, .monotonic);
        }
    };

    /// Snapshot of current metrics for reporting.
    pub const Snapshot = struct {
        /// Total records logged.
        totalRecords: u64,
        /// Total bytes written.
        totalBytes: u64,
        /// Records dropped due to overflow.
        droppedRecords: u64,
        /// Total error count.
        errorCount: u64,
        /// Time since metrics start in milliseconds.
        uptimeMs: i64,
        /// Current records per second.
        recordsPerSecond: f64,
        /// Current bytes per second.
        bytesPerSecond: f64,
        /// Record counts per level (indexed by LevelIndex).
        levelCounts: [Constants.LevelConstants.count]u64,

        /// Get drop rate (0.0 - 1.0).
        pub fn getDropRate(self: *const Snapshot) f64 {
            return Utils.calculateRate(self.droppedRecords, self.totalRecords);
        }
    };

    /// Aggregated latency view built from raw counters and histogram buckets.
    pub const LatencySummary = struct {
        /// Total latency samples available in histogram buckets.
        samples: u64,
        /// Minimum observed latency in nanoseconds.
        minNs: u64,
        /// Maximum observed latency in nanoseconds.
        maxNs: u64,
        /// Average latency in nanoseconds.
        avgNs: u64,
        /// 50th percentile latency in nanoseconds.
        p50Ns: u64,
        /// 95th percentile latency in nanoseconds.
        p95Ns: u64,
        /// 99th percentile latency in nanoseconds.
        p99Ns: u64,

        /// Returns true when at least one latency sample is present.
        pub fn hasSamples(self: *const LatencySummary) bool {
            return self.samples > 0;
        }
    };

    /// Level index mapping for metrics array.
    /// Re-exported from Constants.LevelConstants.LevelIndex for consistency.
    pub const LevelIndex = Constants.LevelConstants.LevelIndex;

    /// Re-export MetricsConfig from global config.
    pub const MetricsConfig = Config.MetricsConfig;

    /// Mutual exclusion for thread-safe operations.
    mutex: std.Io.Mutex = std.Io.Mutex.init,
    /// Metrics configuration.
    config: MetricsConfig = .{},

    /// Total records logged.
    totalRecords: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
    /// Total bytes written.
    totalBytes: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
    /// Records dropped due to overflow.
    droppedRecords: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
    /// Total error count.
    totalErrors: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),

    /// Per-level record counts.
    levelCounts: [Constants.LevelConstants.count]std.atomic.Value(Constants.AtomicUnsigned) = @splat(std.atomic.Value(Constants.AtomicUnsigned).init(0)),

    /// Metrics collection start time.
    startTime: i64,
    /// Timestamp of last record logged.
    lastRecordTime: std.atomic.Value(Constants.AtomicSigned) = std.atomic.Value(Constants.AtomicSigned).init(0),

    /// Total latency in nanoseconds (for average calculation).
    totalLatencyNs: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
    /// Minimum latency observed in nanoseconds.
    latencyMinNs: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(std.math.maxInt(Constants.AtomicUnsigned)),
    /// Maximum latency observed in nanoseconds.
    latencyMaxNs: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),

    /// Histogram buckets for latency distribution.
    histogram: [Constants.MetricsConstants.histogramBoundaries.len]std.atomic.Value(Constants.AtomicUnsigned) = @splat(std.atomic.Value(Constants.AtomicUnsigned).init(0)),

    /// Histogram buckets for latency distribution per log level.
    levelHistograms: [Constants.LevelConstants.count][Constants.MetricsConstants.histogramBoundaries.len]std.atomic.Value(Constants.AtomicUnsigned) = @splat(@splat(std.atomic.Value(Constants.AtomicUnsigned).init(0))),

    /// Snapshot history for trend analysis.
    history: std.ArrayList(Snapshot),

    /// Per-sink metrics list.
    sinkMetrics: std.ArrayList(SinkMetrics),
    /// Memory allocator.
    allocator: std.mem.Allocator,

    /// Callback invoked when a record is logged.
    onRecordLogged: ?*const fn (Level, u64) void = null,

    /// Callback invoked when metrics snapshot is taken.
    onMetricsSnapshot: ?*const fn (*const Snapshot) void = null,

    /// Callback invoked when metrics exceed thresholds.
    onThresholdExceeded: ?*const fn (MetricType, u64, u64) void = null,

    /// Callback invoked when errors or dropped records detected.
    onErrorDetected: ?*const fn (ErrorEvent, u64) void = null,

    /// Maps a Level enum value to a LevelIndex for the metrics array.
    fn levelToIndex(level: Level) u4 {
        const LI = LevelIndex;
        return switch (level) {
            .trace => @backingInt(LI.trace),
            .debug => @backingInt(LI.debug),
            .info => @backingInt(LI.info),
            .notice => @backingInt(LI.notice),
            .success => @backingInt(LI.success),
            .warning => @backingInt(LI.warning),
            .err => @backingInt(LI.err),
            .fail => @backingInt(LI.fail),
            .critical => @backingInt(LI.critical),
            .fatal => @backingInt(LI.fatal),
        };
    }

    /// Maps an index back to a histogram bucket boundary (in nanoseconds).
    fn histogramBucketBoundary(bucket: usize) u64 {
        return if (bucket < Constants.MetricsConstants.histogramBoundaries.len) Constants.MetricsConstants.histogramBoundaries[bucket] else std.math.maxInt(u64);
    }

    /// Returns the total number of histogram samples.
    fn histogramSampleCount(self: *const Metrics) u64 {
        var total: u64 = 0;
        for (0..self.histogram.len) |i| {
            total += @as(u64, self.histogram[i].load(.monotonic));
        }
        return total;
    }

    /// Maps a LevelIndex back to a Level name string.
    pub fn indexToLevelName(index: usize) []const u8 {
        return if (index < Constants.MetricsConstants.levelNames.len) Constants.MetricsConstants.levelNames[index] else "UNKNOWN";
    }

    /// Initializes a new Metrics instance with default configuration.
    pub fn init(allocator: std.mem.Allocator) Metrics {
        return initWithConfig(allocator, .{});
    }

    /// Initializes a new Metrics instance with custom configuration.
    pub fn initWithConfig(allocator: std.mem.Allocator, config: MetricsConfig) Metrics {
        return .{
            .startTime = Utils.monotonicMillis(),
            .sinkMetrics = .empty,
            .history = .empty,
            .allocator = allocator,
            .config = config,
        };
    }

    /// Releases all resources associated with the metrics.
    pub fn deinit(self: *Metrics) void {
        for (self.sinkMetrics.items) |metric| {
            self.allocator.free(metric.name);
        }
        self.sinkMetrics.deinit(self.allocator);
        self.history.deinit(self.allocator);
    }

    /// Sets the callback for record logged events.
    pub fn setRecordLoggedCallback(self: *Metrics, callback: *const fn (Level, u64) void) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        self.onRecordLogged = callback;
    }

    /// Sets the callback for metrics snapshot events.
    pub fn setSnapshotCallback(self: *Metrics, callback: *const fn (*const Snapshot) void) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        self.onMetricsSnapshot = callback;
    }

    /// Sets the callback for threshold exceeded events.
    pub fn setThresholdCallback(self: *Metrics, callback: *const fn (MetricType, u64, u64) void) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        self.onThresholdExceeded = callback;
    }

    /// Sets the callback for error detected events.
    pub fn setErrorCallback(self: *Metrics, callback: *const fn (ErrorEvent, u64) void) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        self.onErrorDetected = callback;
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
        self.recordLogAt(level, bytes, Utils.currentMillis());
    }

    /// Records a log with an explicit wall-clock timestamp in milliseconds.
    ///
    /// Prefer this on the logging hot path when the caller already captured
    /// the current time, so the timestamp is generated once per record
    /// instead of once each in the logger, the record, and metrics.
    pub fn recordLogAt(self: *Metrics, level: Level, bytes: u64, timestampMs: i64) void {
        _ = self.totalRecords.fetchAdd(1, .monotonic);
        _ = self.totalBytes.fetchAdd(@truncate(bytes), .monotonic);

        if (self.config.trackLevels) {
            const levelIndex = levelToIndex(level);
            _ = self.levelCounts[levelIndex].fetchAdd(1, .monotonic);
        }

        self.lastRecordTime.store(@truncate(timestampMs), .monotonic);

        // Advanced features only when enabled
        if (self.config.enabled) {
            // Check thresholds
            self.checkThresholds();

            // Invoke callback if set
            if (self.onRecordLogged) |callback| {
                callback(level, bytes);
            }
        }
    }

    /// Records a log with latency measurement.
    pub fn recordLogWithLatency(self: *Metrics, level: Level, bytes: u64, latencyNs: u64) void {
        self.recordLog(level, bytes);

        if (!self.config.trackLatency) return;

        _ = self.totalLatencyNs.fetchAdd(@truncate(latencyNs), .monotonic);

        // Update min latency
        var currentMin = self.latencyMinNs.load(.monotonic);
        while (latencyNs < currentMin) {
            const result = self.latencyMinNs.cmpxchgWeak(currentMin, @truncate(latencyNs), .monotonic, .monotonic);
            if (result) |newCurrent| {
                currentMin = newCurrent;
            } else {
                break;
            }
        }

        // Update max latency
        var currentMax = self.latencyMaxNs.load(.monotonic);
        while (latencyNs > currentMax) {
            const result = self.latencyMaxNs.cmpxchgWeak(currentMax, @truncate(latencyNs), .monotonic, .monotonic);
            if (result) |newCurrent| {
                currentMax = newCurrent;
            } else {
                break;
            }
        }

        // Update histogram if enabled
        if (self.config.enableHistogram) {
            const bucket = self.getHistogramBucket(latencyNs);
            if (bucket < self.histogram.len) {
                _ = self.histogram[bucket].fetchAdd(1, .monotonic);
                const levelIndex = levelToIndex(level);
                _ = self.levelHistograms[levelIndex][bucket].fetchAdd(1, .monotonic);
            }
        }
    }

    /// Get histogram bucket for a latency value (binary search, boundaries ascending).
    fn getHistogramBucket(self: *const Metrics, latencyNs: u64) usize {
        _ = self;
        const bounds = Constants.MetricsConstants.histogramBoundaries;
        var lo: usize = 0;
        var hi: usize = bounds.len;
        while (lo < hi) {
            const mid = lo + (hi - lo) / 2;
            if (latencyNs <= bounds[mid]) {
                hi = mid;
            } else {
                lo = mid + 1;
            }
        }
        if (lo >= bounds.len) return bounds.len - 1;
        return lo;
    }

    /// Check thresholds and invoke callback if exceeded.
    fn checkThresholds(self: *Metrics) void {
        if (self.onThresholdExceeded == null) return;

        const callback = self.onThresholdExceeded.?;

        // Check error rate threshold
        if (self.config.errorRateThreshold > 0) {
            const errRate = self.errorRate();
            if (errRate > self.config.errorRateThreshold) {
                callback(.errorCount, self.errorCount(), @intFromFloat(self.config.errorRateThreshold * 100));
            }
        }

        // Check drop rate threshold
        if (self.config.dropRateThreshold > 0) {
            const dropRateVal = self.dropRate();
            if (dropRateVal > self.config.dropRateThreshold) {
                callback(.droppedRecords, self.droppedCount(), @intFromFloat(self.config.dropRateThreshold * 100));
            }
        }

        // Check max records per second
        if (self.config.maxRecordsPerSecond > 0) {
            const rps = self.rate();
            if (rps > @as(f64, @floatFromInt(self.config.maxRecordsPerSecond))) {
                callback(.recordsPerSecond, @intFromFloat(rps), self.config.maxRecordsPerSecond);
            }
        }
    }

    /// Records a dropped log record.
    pub fn recordDrop(self: *Metrics) void {
        _ = self.droppedRecords.fetchAdd(1, .monotonic);
        if (self.onErrorDetected) |callback| {
            callback(.recordsDropped, self.droppedCount());
        }
    }

    /// Records an error.
    pub fn recordError(self: *Metrics) void {
        _ = self.totalErrors.fetchAdd(1, .monotonic);
        if (self.onErrorDetected) |callback| {
            callback(.sinkWriteError, self.errorCount());
        }
    }

    /// Adds a sink to track.
    pub fn addSink(self: *Metrics, name: []const u8) !usize {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());

        const ownedName = try self.allocator.dupe(u8, name);
        try self.sinkMetrics.append(self.allocator, .{ .name = ownedName });
        return self.sinkMetrics.items.len - 1;
    }

    /// Records a successful write to a sink.
    pub fn recordSinkWrite(self: *Metrics, sinkIndex: usize, bytes: u64) void {
        if (sinkIndex < self.sinkMetrics.items.len) {
            _ = self.sinkMetrics.items[sinkIndex].recordsWritten.fetchAdd(@as(Constants.AtomicUnsigned, 1), .monotonic);
            _ = self.sinkMetrics.items[sinkIndex].bytesWritten.fetchAdd(@truncate(bytes), .monotonic);
        }
    }

    /// Records a write error on a sink.
    pub fn recordSinkError(self: *Metrics, sinkIndex: usize) void {
        if (sinkIndex < self.sinkMetrics.items.len) {
            _ = self.sinkMetrics.items[sinkIndex].writeErrors.fetchAdd(@as(Constants.AtomicUnsigned, 1), .monotonic);
        }
    }

    /// Gets a snapshot of current metrics.
    pub fn getSnapshot(self: *Metrics) Snapshot {
        const uptimeMs = Utils.elapsedMs(self.startTime);

        const totalRecords = Utils.atomicLoadU64(&self.totalRecords);
        const totalBytes = Utils.atomicLoadU64(&self.totalBytes);

        var levelCounts: [10]u64 = undefined;
        for (0..10) |i| {
            levelCounts[i] = Utils.atomicLoadU64(&self.levelCounts[i]);
        }

        return .{
            .totalRecords = totalRecords,
            .totalBytes = totalBytes,
            .droppedRecords = Utils.atomicLoadU64(&self.droppedRecords),
            .errorCount = Utils.atomicLoadU64(&self.totalErrors),
            .uptimeMs = @as(i64, @intCast(uptimeMs)),
            .recordsPerSecond = Utils.calculateThroughputMs(totalRecords, @as(i64, @intCast(uptimeMs))),
            .bytesPerSecond = Utils.calculateThroughputMs(totalBytes, @as(i64, @intCast(uptimeMs))),
            .levelCounts = levelCounts,
        };
    }

    /// Takes a snapshot and optionally stores in history.
    pub fn takeSnapshot(self: *Metrics) !Snapshot {
        const snapshot = self.getSnapshot();

        // Store in history if configured
        if (self.config.historySize > 0) {
            self.mutex.lockUncancelable(Utils.io());
            defer self.mutex.unlock(Utils.io());

            // Remove oldest if at capacity
            if (self.history.items.len >= self.config.historySize) {
                _ = self.history.orderedRemove(0);
            }

            try self.history.append(self.allocator, snapshot);
        }

        // Invoke callback
        if (self.onMetricsSnapshot) |callback| {
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
        self.totalRecords.store(@as(Constants.AtomicUnsigned, 0), .monotonic);
        self.totalBytes.store(@as(Constants.AtomicUnsigned, 0), .monotonic);
        self.droppedRecords.store(@as(Constants.AtomicUnsigned, 0), .monotonic);
        self.totalErrors.store(@as(Constants.AtomicUnsigned, 0), .monotonic);
        self.startTime = Utils.monotonicMillis();

        // Reset latency
        self.totalLatencyNs.store(@as(Constants.AtomicUnsigned, 0), .monotonic);
        self.latencyMinNs.store(std.math.maxInt(Constants.AtomicUnsigned), .monotonic);
        self.latencyMaxNs.store(@as(Constants.AtomicUnsigned, 0), .monotonic);

        // Reset histogram
        for (0..Constants.MetricsConstants.histogramBoundaries.len) |i| {
            self.histogram[i].store(@as(Constants.AtomicUnsigned, 0), .monotonic);
        }

        // Reset level histograms
        for (0..Constants.LevelConstants.count) |l| {
            for (0..Constants.MetricsConstants.histogramBoundaries.len) |i| {
                self.levelHistograms[l][i].store(@as(Constants.AtomicUnsigned, 0), .monotonic);
            }
        }

        for (0..Constants.LevelConstants.count) |i| {
            self.levelCounts[i].store(@as(Constants.AtomicUnsigned, 0), .monotonic);
        }

        for (self.sinkMetrics.items) |*metric| {
            metric.recordsWritten.store(@as(Constants.AtomicUnsigned, 0), .monotonic);
            metric.bytesWritten.store(@as(Constants.AtomicUnsigned, 0), .monotonic);
            metric.writeErrors.store(@as(Constants.AtomicUnsigned, 0), .monotonic);
            metric.flushCount.store(@as(Constants.AtomicUnsigned, 0), .monotonic);
        }

        // Clear history
        self.history.clearRetainingCapacity();
    }

    /// Export metrics in configured format.
    pub fn exportMetrics(self: *Metrics, allocator: std.mem.Allocator) ![]u8 {
        return switch (self.config.exportFormat) {
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
            snapshot.totalRecords,
            snapshot.totalBytes,
            snapshot.droppedRecords,
            snapshot.errorCount,
            snapshot.uptimeMs,
            snapshot.recordsPerSecond,
            snapshot.bytesPerSecond,
        });
    }

    fn writePrometheusMetricName(self: *const Metrics, writer: anytype, name: []const u8) !void {
        try Utils.writeTelemetryMetricName(
            writer,
            self.config.metricPrefix,
            self.config.metricSeparator,
            name,
            self.config.sanitizeNames,
        );
    }

    fn writeStatsdMetricName(self: *const Metrics, writer: anytype, name: []const u8) !void {
        try Utils.writeTelemetryMetricName(
            writer,
            self.config.metricPrefix,
            self.config.statsdSeparator,
            name,
            self.config.sanitizeNames,
        );
    }

    fn writePrometheusHeader(self: *const Metrics, writer: anytype, name: []const u8, help: []const u8, metricType: []const u8) !void {
        try writer.writeAll("# HELP ");
        try self.writePrometheusMetricName(writer, name);
        try writer.writeByte(' ');
        try writer.writeAll(help);
        try writer.writeByte('\n');
        try writer.writeAll("# TYPE ");
        try self.writePrometheusMetricName(writer, name);
        try writer.writeByte(' ');
        try writer.writeAll(metricType);
        try writer.writeByte('\n');
    }

    fn writePrometheusUnsigned(self: *const Metrics, writer: anytype, name: []const u8, help: []const u8, metricType: []const u8, value: u64) !void {
        try self.writePrometheusHeader(writer, name, help, metricType);
        try self.writePrometheusMetricName(writer, name);
        try writer.writeByte(' ');
        try Utils.writeInt(writer, value);
        try writer.writeByte('\n');
    }

    /// Export as Prometheus format.
    pub fn exportPrometheus(self: *Metrics, allocator: std.mem.Allocator) ![]u8 {
        const snapshot = self.getSnapshot();
        var buf: std.ArrayList(u8) = .empty;
        errdefer buf.deinit(allocator);
        var listWriter = Utils.ArrayListWriter.init(&buf, allocator);
        const writer = &listWriter.writer;

        try self.writePrometheusUnsigned(writer, "records_total", "Total log records", "counter", snapshot.totalRecords);
        try self.writePrometheusUnsigned(writer, "bytes_total", "Total bytes logged", "counter", snapshot.totalBytes);
        try self.writePrometheusUnsigned(writer, "dropped_total", "Dropped records", "counter", snapshot.droppedRecords);
        try self.writePrometheusUnsigned(writer, "errors_total", "Error count", "counter", snapshot.errorCount);

        try self.writePrometheusHeader(writer, "records_per_second", "Records per second", "gauge");
        try self.writePrometheusMetricName(writer, "records_per_second");
        try writer.writeByte(' ');
        try writer.print("{d:.2}", .{snapshot.recordsPerSecond});
        try writer.writeByte('\n');

        if (self.config.exportLevelBreakdown) {
            try self.writePrometheusHeader(writer, "level_records_total", "Log records by level", "counter");
            for (snapshot.levelCounts, 0..) |count, i| {
                if (count == 0) continue;
                try self.writePrometheusMetricName(writer, "level_records_total");
                try writer.writeAll("{level=");
                try Utils.writePrometheusLabelValue(writer, indexToLevelName(i));
                try writer.writeAll("} ");
                try Utils.writeInt(writer, count);
                try writer.writeByte('\n');
            }
        }

        if (self.config.exportSinkBreakdown) {
            try self.writePrometheusHeader(writer, "sink_records_total", "Log records by sink", "counter");
            try self.writePrometheusHeader(writer, "sink_errors_total", "Sink write errors", "counter");
            for (self.sinkMetrics.items) |metric| {
                try self.writePrometheusMetricName(writer, "sink_records_total");
                try writer.writeAll("{sink=");
                try Utils.writePrometheusLabelValue(writer, metric.name);
                try writer.writeAll("} ");
                try Utils.writeInt(writer, metric.getRecordsWritten());
                try writer.writeByte('\n');

                try self.writePrometheusMetricName(writer, "sink_errors_total");
                try writer.writeAll("{sink=");
                try Utils.writePrometheusLabelValue(writer, metric.name);
                try writer.writeAll("} ");
                try Utils.writeInt(writer, metric.getWriteErrors());
                try writer.writeByte('\n');
            }
        }

        return buf.toOwnedSlice(allocator);
    }

    /// Export as StatsD format.
    pub fn exportStatsd(self: *Metrics, allocator: std.mem.Allocator) ![]u8 {
        const snapshot = self.getSnapshot();
        var buf: std.ArrayList(u8) = .empty;
        errdefer buf.deinit(allocator);
        var listWriter = Utils.ArrayListWriter.init(&buf, allocator);
        const writer = &listWriter.writer;

        try self.writeStatsdMetricName(writer, "records.total");
        try writer.print(":{d}|c\n", .{snapshot.totalRecords});
        try self.writeStatsdMetricName(writer, "bytes.total");
        try writer.print(":{d}|c\n", .{snapshot.totalBytes});
        try self.writeStatsdMetricName(writer, "dropped.total");
        try writer.print(":{d}|c\n", .{snapshot.droppedRecords});
        try self.writeStatsdMetricName(writer, "errors.total");
        try writer.print(":{d}|c\n", .{snapshot.errorCount});
        try self.writeStatsdMetricName(writer, "rps");
        try writer.print(":{d:.2}|g\n", .{snapshot.recordsPerSecond});

        return buf.toOwnedSlice(allocator);
    }

    /// Get average latency in nanoseconds.
    pub fn avgLatencyNs(self: *const Metrics) u64 {
        const total = Utils.atomicLoadU64(&self.totalRecords);
        const latency = Utils.atomicLoadU64(&self.totalLatencyNs);
        return if (total == 0) 0 else latency / total;
    }

    /// Get min latency in nanoseconds.
    pub fn minLatencyNs(self: *const Metrics) u64 {
        const min = self.latencyMinNs.load(.monotonic);
        if (min == std.math.maxInt(Constants.AtomicUnsigned)) return 0;
        return @as(u64, min);
    }

    /// Get max latency in nanoseconds.
    pub fn maxLatencyNs(self: *const Metrics) u64 {
        return @as(u64, self.latencyMaxNs.load(.monotonic));
    }

    /// Get histogram data.
    pub fn getHistogram(self: *const Metrics) [20]u64 {
        var result: [20]u64 = undefined;
        for (0..20) |i| {
            result[i] = @as(u64, self.histogram[i].load(.monotonic));
        }
        return result;
    }

    /// Get histogram data for a specific level.
    pub fn getLevelHistogram(self: *const Metrics, level: Level) [20]u64 {
        const levelIndex = levelToIndex(level);
        var result: [20]u64 = undefined;
        for (0..20) |i| {
            result[i] = @as(u64, self.levelHistograms[levelIndex][i].load(.monotonic));
        }
        return result;
    }

    /// Estimate latency at a percentile using histogram bucket boundaries.
    ///
    /// Percentile values are clamped to [0, 100].
    pub fn latencyPercentileNs(self: *const Metrics, percentile: f64) u64 {
        const clamped = if (percentile < 0.0)
            0.0
        else if (percentile > 100.0)
            100.0
        else
            percentile;

        if (clamped <= 0.0) return self.minLatencyNs();
        if (clamped >= 100.0) return self.maxLatencyNs();

        const totalSamples = self.histogramSampleCount();
        if (totalSamples == 0) return self.avgLatencyNs();

        const rankF = (clamped / 100.0) * @as(f64, @floatFromInt(totalSamples));
        const rank = @max(@as(u64, 1), @as(u64, @intFromFloat(@ceil(rankF))));

        var cumulative: u64 = 0;
        for (0..self.histogram.len) |i| {
            const bucketCount = @as(u64, self.histogram[i].load(.monotonic));
            if (bucketCount == 0) continue;

            cumulative += bucketCount;
            if (cumulative >= rank) {
                const boundary = histogramBucketBoundary(i);
                return if (boundary == std.math.maxInt(u64)) self.maxLatencyNs() else boundary;
            }
        }

        return self.maxLatencyNs();
    }

    /// Estimate latency at a percentile in milliseconds.
    pub fn latencyPercentileMs(self: *const Metrics, percentile: f64) f64 {
        return @as(f64, @floatFromInt(self.latencyPercentileNs(percentile))) / @as(f64, @floatFromInt(Constants.TimeConstants.nsPerMs));
    }

    /// Returns an aggregated latency summary.
    pub fn getLatencySummary(self: *const Metrics) LatencySummary {
        return .{
            .samples = self.histogramSampleCount(),
            .minNs = self.minLatencyNs(),
            .maxNs = self.maxLatencyNs(),
            .avgNs = self.avgLatencyNs(),
            .p50Ns = self.latencyPercentileNs(50.0),
            .p95Ns = self.latencyPercentileNs(95.0),
            .p99Ns = self.latencyPercentileNs(99.0),
        };
    }

    /// Returns total sink write errors across all tracked sinks.
    pub fn totalSinkErrors(self: *const Metrics) u64 {
        var total: u64 = 0;
        for (self.sinkMetrics.items) |metric| {
            total += metric.getWriteErrors();
        }
        return total;
    }

    /// Returns total sink flush count across all tracked sinks.
    pub fn totalSinkFlushes(self: *const Metrics) u64 {
        var total: u64 = 0;
        for (self.sinkMetrics.items) |metric| {
            total += metric.getFlushCount();
        }
        return total;
    }

    /// Returns age in milliseconds since the last recorded log entry.
    ///
    /// Returns null when no record has been logged yet.
    pub fn lastRecordAgeMs(self: *const Metrics) ?i64 {
        const last = @as(i64, self.lastRecordTime.load(.monotonic));
        if (last <= 0) return null;

        const age = Utils.currentMillis() - last;
        return if (age < 0) 0 else age;
    }

    /// Formats metrics as a human-readable string.
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
            snapshot.totalRecords,
            snapshot.totalBytes,
            snapshot.droppedRecords,
            snapshot.errorCount,
            snapshot.uptimeMs,
            snapshot.recordsPerSecond,
            snapshot.bytesPerSecond,
        });
    }

    /// Formats level breakdown as a human-readable string.
    pub fn formatLevelBreakdown(self: *Metrics, allocator: std.mem.Allocator) ![]u8 {
        const snapshot = self.getSnapshot();
        var buf: std.ArrayList(u8) = .empty;
        errdefer buf.deinit(allocator);
        var listWriter = Utils.ArrayListWriter.init(&buf, allocator);
        const writer = &listWriter.writer;

        try writer.writeAll("Level Breakdown:");
        var hasLevels = false;
        for (0..Constants.LevelConstants.count) |i| {
            const count = snapshot.levelCounts[i];
            if (count > 0) {
                if (hasLevels) {
                    try writer.writeAll(",");
                }
                try writer.writeByte(' ');
                try writer.writeAll(indexToLevelName(i));
                try writer.writeByte(':');
                try Utils.writeInt(writer, count);
                hasLevels = true;
            }
        }
        if (!hasLevels) {
            try writer.writeAll(" (none)");
        }

        return buf.toOwnedSlice(allocator);
    }

    /// Records a log for a custom level.
    /// Custom levels use the same total_records and total_bytes counters.
    pub fn recordCustomLog(self: *Metrics, bytes: u64) void {
        _ = self.totalRecords.fetchAdd(1, .monotonic);
        _ = self.totalBytes.fetchAdd(@truncate(bytes), .monotonic);
        self.lastRecordTime.store(@truncate(Utils.currentMillis()), .monotonic);
    }

    /// Returns true if any records have been logged.
    pub fn hasRecords(self: *const Metrics) bool {
        return self.totalRecords.load(.monotonic) > 0;
    }

    /// Returns the total record count.
    pub fn totalRecordCount(self: *const Metrics) u64 {
        return @as(u64, self.totalRecords.load(.monotonic));
    }

    /// Returns the total bytes logged.
    pub fn totalBytesLogged(self: *const Metrics) u64 {
        return @as(u64, self.totalBytes.load(.monotonic));
    }

    /// Returns the uptime in milliseconds.
    pub fn uptime(self: *const Metrics) i64 {
        return Utils.currentMillis() - self.startTime;
    }

    /// Returns records per second rate.
    pub fn rate(self: *Metrics) f64 {
        const snapshotData = self.getSnapshot();
        return snapshotData.recordsPerSecond;
    }

    /// Returns the error count.
    pub fn errorCount(self: *const Metrics) u64 {
        return @as(u64, self.totalErrors.load(.monotonic));
    }

    /// Returns the dropped records count.
    pub fn droppedCount(self: *const Metrics) u64 {
        return @as(u64, self.droppedRecords.load(.monotonic));
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
        return @as(u64, self.levelCounts[idx].load(.monotonic));
    }

    /// Resets the counter for a single log level without affecting other metrics.
    pub fn resetLevelMetrics(self: *Metrics, level: Level) void {
        const idx = levelToIndex(level);
        self.levelCounts[idx].store(@as(Constants.AtomicUnsigned, 0), .monotonic);
    }

    /// Returns the number of sinks being tracked.
    pub fn sinkCount(self: *const Metrics) usize {
        return self.sinkMetrics.items.len;
    }

    /// Returns uptime in seconds.
    pub fn uptimeSeconds(self: *const Metrics) f64 {
        return @as(f64, @floatFromInt(self.uptime())) / @as(f64, Constants.TimeConstants.msPerSecond);
    }

    /// Records a flush operation on a sink.
    pub fn recordSinkFlush(self: *Metrics, sinkIndex: usize) void {
        if (sinkIndex < self.sinkMetrics.items.len) {
            _ = self.sinkMetrics.items[sinkIndex].flushCount.fetchAdd(1, .monotonic);
        }
    }

    /// Get sink metrics by index.
    pub fn getSinkMetrics(self: *const Metrics, sinkIndex: usize) ?SinkMetrics {
        if (sinkIndex < self.sinkMetrics.items.len) {
            return self.sinkMetrics.items[sinkIndex];
        }
        return null;
    }

    /// Get sink metrics by name.
    pub fn getSinkMetricsByName(self: *const Metrics, name: []const u8) ?SinkMetrics {
        for (self.sinkMetrics.items) |metric| {
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
        const snapshotData = self.getSnapshot();
        return snapshotData.bytesPerSecond;
    }
};

/// Pre-built metrics configurations.
pub const MetricsPresets = struct {
    /// Creates a basic metrics instance.
    pub fn basic(allocator: std.mem.Allocator) Metrics {
        return Metrics.init(allocator);
    }

    /// Creates a metrics sink configuration.
    pub fn createMetricsSink(filePath: []const u8) @import("sink.zig").SinkConfig {
        return .{
            .path = filePath,
            .format = .json,
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

    const snapshotData = metrics.getSnapshot();
    try std.testing.expectEqual(@as(u64, 2), snapshotData.totalRecords);
    try std.testing.expectEqual(@as(u64, 250), snapshotData.totalBytes);
    try std.testing.expectEqual(@as(u64, 1), snapshotData.errorCount);
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

test "metrics reset level count" {
    var metrics = Metrics.init(std.testing.allocator);
    defer metrics.deinit();

    metrics.recordLog(.info, 50);
    metrics.recordLog(.err, 100);

    try std.testing.expectEqual(@as(u64, 1), metrics.levelCount(.info));
    try std.testing.expectEqual(@as(u64, 1), metrics.levelCount(.err));

    metrics.resetLevelMetrics(.info);

    try std.testing.expectEqual(@as(u64, 0), metrics.levelCount(.info));
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
    try std.testing.expectEqual(@as(u64, 1), sink.?.recordsWritten.load(.monotonic));
    try std.testing.expectEqual(@as(u64, 100), sink.?.bytesWritten.load(.monotonic));
    try std.testing.expectEqual(@as(u64, 1), sink.?.flushCount.load(.monotonic));
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

    try std.testing.expect(metrics.onRecordLogged != null);
    try std.testing.expect(metrics.onMetricsSnapshot != null);
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

test "metrics latency summary and percentiles" {
    var metrics = Metrics.initWithConfig(std.testing.allocator, .{
        .trackLatency = true,
        .enableHistogram = true,
    });
    defer metrics.deinit();

    metrics.recordLogWithLatency(.info, 100, 1_000_000);
    metrics.recordLogWithLatency(.info, 100, 5_000_000);
    metrics.recordLogWithLatency(.info, 100, 10_000_000);

    const p50 = metrics.latencyPercentileNs(50.0);
    const p95 = metrics.latencyPercentileNs(95.0);
    const summary = metrics.getLatencySummary();

    try std.testing.expect(summary.hasSamples());
    try std.testing.expect(p50 > 0);
    try std.testing.expect(p95 >= p50);
    try std.testing.expect(summary.p99Ns >= summary.p95Ns);
}

test "metrics sink totals and last record age" {
    var metrics = Metrics.init(std.testing.allocator);
    defer metrics.deinit();

    try std.testing.expectEqual(@as(?i64, null), metrics.lastRecordAgeMs());

    const sinkA = try metrics.addSink("sink_a");
    const sinkB = try metrics.addSink("sink_b");

    metrics.recordSinkError(sinkA);
    metrics.recordSinkError(sinkB);
    metrics.recordSinkFlush(sinkA);
    metrics.recordSinkFlush(sinkB);
    metrics.recordSinkFlush(sinkB);

    metrics.recordLog(.info, 42);

    const ageMs = metrics.lastRecordAgeMs();
    try std.testing.expect(ageMs != null);
    try std.testing.expect(ageMs.? >= 0);

    try std.testing.expectEqual(@as(u64, 2), metrics.totalSinkErrors());
    try std.testing.expectEqual(@as(u64, 3), metrics.totalSinkFlushes());
}

test "metrics prometheus export uses configured names and breakdowns" {
    var metrics = Metrics.initWithConfig(std.testing.allocator, Config.MetricsConfig.production().prometheus().withPrefix("svc.api"));
    defer metrics.deinit();

    metrics.recordLog(.info, 100);
    metrics.recordLog(.err, 50);
    const sinkIdx = try metrics.addSink("file\"main");
    metrics.recordSinkWrite(sinkIdx, 150);
    metrics.recordSinkError(sinkIdx);

    const exported = try metrics.exportPrometheus(std.testing.allocator);
    defer std.testing.allocator.free(exported);

    try std.testing.expect(std.mem.indexOf(u8, exported, "svc_api_records_total 2") != null);
    try std.testing.expect(std.mem.indexOf(u8, exported, "svc_api_level_records_total{level=\"INFO\"} 1") != null);
    try std.testing.expect(std.mem.indexOf(u8, exported, "svc_api_sink_errors_total{sink=\"file\\\"main\"} 1") != null);
}

test "metrics statsd export supports configured prefix" {
    var metrics = Metrics.initWithConfig(std.testing.allocator, Config.MetricsConfig.production().statsd().withPrefix("svc.api"));
    defer metrics.deinit();

    metrics.recordLog(.warning, 25);

    const exported = try metrics.exportStatsd(std.testing.allocator);
    defer std.testing.allocator.free(exported);

    try std.testing.expect(std.mem.indexOf(u8, exported, "svc.api.records.total:1|c") != null);
}
