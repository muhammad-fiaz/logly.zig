const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== Logly v0.2.0 Metrics Collection Example ===\n\n", .{});

    // Create logger with metrics enabled
    var config = logly.Config.default();
    config.metrics.enabled = true;
    config.metrics.track_levels = true;
    config.metrics.track_latency = true;
    config.metrics.enable_histogram = true;

    const logger = try logly.Logger.initWithConfig(allocator, config);
    defer logger.deinit();

    // Enable metrics on the logger
    logger.enableMetrics();

    std.debug.print("--- Logging messages to collect metrics ---\n\n", .{});

    // Log various messages at different levels
    try logger.trace("Trace message for metrics", @src());
    try logger.debug("Debug message for metrics", @src());
    try logger.info("Info message 1", @src());
    try logger.info("Info message 2", @src());
    try logger.info("Info message 3", @src());
    try logger.warning("Warning message 1", @src());
    try logger.err("Error message 1", @src());
    try logger.critical("Critical message 1", @src());

    std.debug.print("\n--- Basic Metrics Snapshot ---\n\n", .{});

    // Get metrics snapshot from logger
    if (logger.getMetrics()) |snapshot| {
        std.debug.print("Total Records:      {d}\n", .{snapshot.total_records});
        std.debug.print("Total Bytes:        {d}\n", .{snapshot.total_bytes});
        std.debug.print("Dropped Records:    {d}\n", .{snapshot.dropped_records});
        std.debug.print("Error Count:        {d}\n", .{snapshot.error_count});
        std.debug.print("Uptime (ms):        {d}\n", .{snapshot.uptime_ms});
        std.debug.print("Records/second:     {d:.2}\n", .{snapshot.records_per_second});
        std.debug.print("Bytes/second:       {d:.2}\n", .{snapshot.bytes_per_second});

        std.debug.print("\n--- Level Breakdown ---\n\n", .{});
        const level_names = [_][]const u8{ "Trace", "Debug", "Info", "Notice", "Success", "Warning", "Error", "Fail", "Critical", "Fatal" };
        for (snapshot.level_counts, 0..) |count, i| {
            if (i < level_names.len) {
                std.debug.print("{s:<10} {d}\n", .{ level_names[i], count });
            }
        }
    } else {
        std.debug.print("Metrics not enabled\n", .{});
    }

    // --- Prometheus Export Demo ---
    std.debug.print("\n--- Prometheus Text Export ---\n\n", .{});
    {
        var metrics = logly.Metrics.initWithConfig(allocator, .{
            .enabled = true,
            .track_levels = true,
            .enable_histogram = true,
            .export_format = .prometheus,
            .export_level_breakdown = true,
            .metric_prefix = "logly",
        });
        defer metrics.deinit();

        // Record some sample data
        metrics.recordLog(.info, 128);
        metrics.recordLog(.warning, 64);
        metrics.recordLog(.err, 256);
        metrics.recordLogWithLatency(.info, 100, 15_000);
        metrics.recordLogWithLatency(.info, 80, 25_000);

        const prom_output = try metrics.exportPrometheus(allocator);
        defer allocator.free(prom_output);
        std.debug.print("{s}\n", .{prom_output});
    }

    // --- StatsD Export Demo ---
    std.debug.print("--- StatsD Export ---\n\n", .{});
    {
        var metrics = logly.Metrics.initWithConfig(allocator, .{
            .enabled = true,
            .export_format = .statsd,
            .metric_prefix = "logly",
        });
        defer metrics.deinit();

        metrics.recordLog(.info, 100);
        metrics.recordLog(.err, 200);
        metrics.recordDrop();

        const statsd_output = try metrics.exportStatsd(allocator);
        defer allocator.free(statsd_output);
        std.debug.print("{s}\n", .{statsd_output});
    }

    // --- P95/P99 Latency Demo ---
    std.debug.print("--- P95/P99 Latency Calculation ---\n\n", .{});
    {
        var metrics = logly.Metrics.initWithConfig(allocator, .{
            .enabled = true,
            .track_latency = true,
            .enable_histogram = true,
        });
        defer metrics.deinit();

        // Record latencies: 1µs, 5µs, 10µs, 50µs, 100µs, 500µs, 1ms
        const latencies = [_]u64{ 1_000, 5_000, 10_000, 50_000, 100_000, 500_000, 1_000_000 };
        for (latencies) |lat| {
            metrics.recordLogWithLatency(.info, 64, lat);
        }

        const latency = metrics.getLatencySummary();
        std.debug.print("Latency Summary ({d} samples):\n", .{latency.samples});
        std.debug.print("  Min:  {d} ns\n", .{latency.min_ns});
        std.debug.print("  P50:  {d} ns\n", .{latency.p50_ns});
        std.debug.print("  P95:  {d} ns\n", .{latency.p95_ns});
        std.debug.print("  P99:  {d} ns\n", .{latency.p99_ns});
        std.debug.print("  Max:  {d} ns\n", .{latency.max_ns});
        std.debug.print("  Avg:  {d} ns\n", .{latency.avg_ns});
    }

    // --- Metrics Reset Demo ---
    std.debug.print("\n--- Metrics Reset ---\n\n", .{});
    {
        var metrics = logly.Metrics.init(allocator);
        defer metrics.deinit();

        metrics.recordLog(.info, 100);
        metrics.recordLog(.warning, 50);

        const snap1 = metrics.getSnapshot();
        std.debug.print("Before reset: {d} records\n", .{snap1.total_records});

        metrics.reset();

        const snap2 = metrics.getSnapshot();
        std.debug.print("After reset:  {d} records\n", .{snap2.total_records});
    }

    std.debug.print("\n=== Metrics Example Complete ===\n", .{});
}
