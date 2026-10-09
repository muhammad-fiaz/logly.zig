const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("Metrics Collection Example\n\n", .{});

    // Create logger with metrics enabled
    var config = logly.Config.default();
    config.metrics.enabled = true;
    config.metrics.trackLevels = true;
    config.metrics.trackLatency = true;
    config.metrics.enableHistogram = true;

    const logger = try logly.Logger.initWithConfig(allocator, config);
    defer logger.deinit();

    // Enable metrics on the logger
    logger.enableMetrics();

    std.debug.print("Logging messages to collect metrics\n\n", .{});

    // Log various messages at different levels
    try logger.trace("Trace message for metrics", @src());
    try logger.debug("Debug message for metrics", @src());
    try logger.info("Info message 1", @src());
    try logger.info("Info message 2", @src());
    try logger.info("Info message 3", @src());
    try logger.warning("Warning message 1", @src());
    try logger.err("Error message 1", @src());
    try logger.critical("Critical message 1", @src());
    // Flush so log lines appear before the metrics summary below
    // (logger writes to stdout, section headers write to stderr).
    try logger.flush();

    std.debug.print("\nBasic Metrics Snapshot\n\n", .{});

    // Get metrics snapshot from logger
    if (logger.getMetrics()) |snapshot| {
        std.debug.print("Total Records:      {d}\n", .{snapshot.totalRecords});
        std.debug.print("Total Bytes:        {d}\n", .{snapshot.totalBytes});
        std.debug.print("Dropped Records:    {d}\n", .{snapshot.droppedRecords});
        std.debug.print("Error Count:        {d}\n", .{snapshot.errorCount});
        std.debug.print("Uptime (ms):        {d}\n", .{snapshot.uptimeMs});
        std.debug.print("Records/second:     {d:.2}\n", .{snapshot.recordsPerSecond});
        std.debug.print("Bytes/second:       {d:.2}\n", .{snapshot.bytesPerSecond});

        std.debug.print("\nLevel Breakdown\n\n", .{});
        const levelNames = [_][]const u8{ "Trace", "Debug", "Info", "Notice", "Success", "Warning", "Error", "Fail", "Critical", "Fatal" };
        for (snapshot.levelCounts, 0..) |count, i| {
            if (i < levelNames.len) {
                std.debug.print("{s:<10} {d}\n", .{ levelNames[i], count });
            }
        }
    } else {
        std.debug.print("Metrics not enabled\n", .{});
    }

    // Prometheus Export Demo
    // NOTE: this uses a fresh Metrics instance with its own synthetic
    // sample data, so its totals intentionally differ from the logger
    // snapshot above (which counted real log records).
    std.debug.print("\nPrometheus Text Export\n\n", .{});
    {
        var metrics = logly.Metrics.initWithConfig(allocator, .{
            .enabled = true,
            .trackLevels = true,
            .enableHistogram = true,
            .exportFormat = .prometheus,
            .exportLevelBreakdown = true,
            .metricPrefix = "logly",
        });
        defer metrics.deinit();

        // Record some sample data
        metrics.recordLog(.info, 128);
        metrics.recordLog(.warning, 64);
        metrics.recordLog(.err, 256);
        metrics.recordLogWithLatency(.info, 100, 15_000);
        metrics.recordLogWithLatency(.info, 80, 25_000);

        const promOutput = try metrics.exportPrometheus(allocator);
        defer allocator.free(promOutput);
        std.debug.print("{s}\n", .{promOutput});
    }

    // StatsD Export Demo
    // NOTE: separate synthetic instance; totals differ from above by design.
    std.debug.print("StatsD Export\n\n", .{});
    {
        var metrics = logly.Metrics.initWithConfig(allocator, .{
            .enabled = true,
            .exportFormat = .statsd,
            .metricPrefix = "logly",
        });
        defer metrics.deinit();

        metrics.recordLog(.info, 100);
        metrics.recordLog(.err, 200);
        metrics.recordDrop();

        const statsdOutput = try metrics.exportStatsd(allocator);
        defer allocator.free(statsdOutput);
        std.debug.print("{s}\n", .{statsdOutput});
    }

    // P95/P99 Latency Demo
    std.debug.print("P95/P99 Latency Calculation\n\n", .{});
    {
        var metrics = logly.Metrics.initWithConfig(allocator, .{
            .enabled = true,
            .trackLatency = true,
            .enableHistogram = true,
        });
        defer metrics.deinit();

        // Record latencies: 1µs, 5µs, 10µs, 50µs, 100µs, 500µs, 1ms
        const latencies = [_]u64{ 1_000, 5_000, 10_000, 50_000, 100_000, 500_000, 1_000_000 };
        for (latencies) |lat| {
            metrics.recordLogWithLatency(.info, 64, lat);
        }

        const latency = metrics.getLatencySummary();
        std.debug.print("Latency Summary ({d} samples):\n", .{latency.samples});
        std.debug.print("  Min:  {d} ns\n", .{latency.minNs});
        std.debug.print("  P50:  {d} ns\n", .{latency.p50Ns});
        std.debug.print("  P95:  {d} ns\n", .{latency.p95Ns});
        std.debug.print("  P99:  {d} ns\n", .{latency.p99Ns});
        std.debug.print("  Max:  {d} ns\n", .{latency.maxNs});
        std.debug.print("  Avg:  {d} ns\n", .{latency.avgNs});
    }

    // Metrics Reset Demo
    std.debug.print("\nMetrics Reset\n\n", .{});
    {
        var metrics = logly.Metrics.init(allocator);
        defer metrics.deinit();

        metrics.recordLog(.info, 100);
        metrics.recordLog(.warning, 50);

        const snap1 = metrics.getSnapshot();
        std.debug.print("Before reset: {d} records\n", .{snap1.totalRecords});

        metrics.reset();

        const snap2 = metrics.getSnapshot();
        std.debug.print("After reset:  {d} records\n", .{snap2.totalRecords});
    }

    std.debug.print("\nMetrics Example Complete\n", .{});
}
