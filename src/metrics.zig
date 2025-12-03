const std = @import("std");
const Level = @import("level.zig").Level;

/// Metrics collection for logging system observability.
///
/// Tracks various statistics about logging operations including
/// record counts, throughput, latency, and error rates.
pub const Metrics = struct {
    mutex: std.Thread.Mutex = .{},

    total_records: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    total_bytes: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    dropped_records: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    error_count: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),

    level_counts: [8]std.atomic.Value(u64) = [_]std.atomic.Value(u64){std.atomic.Value(u64).init(0)} ** 8,

    start_time: i64,
    last_record_time: std.atomic.Value(i64) = std.atomic.Value(i64).init(0),

    sink_metrics: std.ArrayList(SinkMetrics),
    allocator: std.mem.Allocator,

    /// Per-sink metrics.
    pub const SinkMetrics = struct {
        name: []const u8,
        records_written: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
        bytes_written: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
        write_errors: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
        flush_count: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    };

    /// Snapshot of current metrics.
    pub const Snapshot = struct {
        total_records: u64,
        total_bytes: u64,
        dropped_records: u64,
        error_count: u64,
        uptime_ms: i64,
        records_per_second: f64,
        bytes_per_second: f64,
        level_counts: [8]u64,
    };

    /// Level index mapping for metrics array.
    pub const LevelIndex = enum(u3) {
        trace = 0,
        debug = 1,
        info = 2,
        success = 3,
        warning = 4,
        err = 5,
        fail = 6,
        critical = 7,
    };

    /// Initializes a new Metrics instance.
    ///
    /// Arguments:
    ///     allocator: Memory allocator for internal storage.
    ///
    /// Returns:
    ///     A new Metrics instance.
    pub fn init(allocator: std.mem.Allocator) Metrics {
        return .{
            .start_time = std.time.milliTimestamp(),
            .sink_metrics = .empty,
            .allocator = allocator,
        };
    }

    /// Releases all resources associated with the metrics.
    pub fn deinit(self: *Metrics) void {
        for (self.sink_metrics.items) |metric| {
            self.allocator.free(metric.name);
        }
        self.sink_metrics.deinit(self.allocator);
    }

    /// Records a new log record.
    ///
    /// Arguments:
    ///     level: The level of the logged record.
    ///     bytes: The size of the formatted record in bytes.
    pub fn recordLog(self: *Metrics, level: Level, bytes: u64) void {
        _ = self.total_records.fetchAdd(1, .monotonic);
        _ = self.total_bytes.fetchAdd(bytes, .monotonic);
        const level_index: u3 = @truncate(@intFromEnum(level));
        _ = self.level_counts[level_index].fetchAdd(1, .monotonic);
        self.last_record_time.store(std.time.milliTimestamp(), .monotonic);
    }

    /// Records a dropped log record.
    pub fn recordDrop(self: *Metrics) void {
        _ = self.dropped_records.fetchAdd(1, .monotonic);
    }

    /// Records an error.
    pub fn recordError(self: *Metrics) void {
        _ = self.error_count.fetchAdd(1, .monotonic);
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
            _ = self.sink_metrics.items[sink_index].records_written.fetchAdd(1, .monotonic);
            _ = self.sink_metrics.items[sink_index].bytes_written.fetchAdd(bytes, .monotonic);
        }
    }

    /// Records a write error on a sink.
    ///
    /// Arguments:
    ///     sink_index: The index of the sink.
    pub fn recordSinkError(self: *Metrics, sink_index: usize) void {
        if (sink_index < self.sink_metrics.items.len) {
            _ = self.sink_metrics.items[sink_index].write_errors.fetchAdd(1, .monotonic);
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

        const total_records = self.total_records.load(.monotonic);
        const total_bytes = self.total_bytes.load(.monotonic);

        var level_counts: [8]u64 = undefined;
        for (0..8) |i| {
            level_counts[i] = self.level_counts[i].load(.monotonic);
        }

        return .{
            .total_records = total_records,
            .total_bytes = total_bytes,
            .dropped_records = self.dropped_records.load(.monotonic),
            .error_count = self.error_count.load(.monotonic),
            .uptime_ms = uptime_ms,
            .records_per_second = if (uptime_sec > 0) @as(f64, @floatFromInt(total_records)) / uptime_sec else 0,
            .bytes_per_second = if (uptime_sec > 0) @as(f64, @floatFromInt(total_bytes)) / uptime_sec else 0,
            .level_counts = level_counts,
        };
    }

    /// Resets all metrics to zero.
    pub fn reset(self: *Metrics) void {
        self.total_records.store(0, .monotonic);
        self.total_bytes.store(0, .monotonic);
        self.dropped_records.store(0, .monotonic);
        self.error_count.store(0, .monotonic);
        self.start_time = std.time.milliTimestamp();

        for (0..8) |i| {
            self.level_counts[i].store(0, .monotonic);
        }

        for (self.sink_metrics.items) |*metric| {
            metric.records_written.store(0, .monotonic);
            metric.bytes_written.store(0, .monotonic);
            metric.write_errors.store(0, .monotonic);
            metric.flush_count.store(0, .monotonic);
        }
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
};

test "metrics basic" {
    var metrics = Metrics.init(std.testing.allocator);
    defer metrics.deinit();

    metrics.recordLog(.info, 100);
    metrics.recordLog(.info, 150);
    metrics.recordError();

    const snapshot = metrics.getSnapshot();
    try std.testing.expectEqual(@as(u64, 2), snapshot.total_records);
    try std.testing.expectEqual(@as(u64, 250), snapshot.total_bytes);
    try std.testing.expectEqual(@as(u64, 1), snapshot.error_count);
}
