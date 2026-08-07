const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== Logly Pipeline Controls (v0.2.0) ===\n\n", .{});

    const config = logly.Config.default()
        .withHighThroughputPipeline()
        .withObservability("checkout.api")
        .withAsync(logly.AsyncConfig.lowLatency().buffer(256).batch(8).backpressure(0.75))
        .withThreadPool(logly.ThreadPoolConfig.ioBound().threads(4).queue(512))
        .withRotation(logly.Config.RotationConfig.daily(7).withCompression(.zstd))
        .withScheduler(logly.SchedulerConfig.maintenance("logs/archive").cleanupDays(14).retainFiles(100));

    std.debug.print("Async enabled:       {s}\n", .{if (config.async_config.enabled) "yes" else "no"});
    std.debug.print("Async buffer:        {d}\n", .{config.async_config.buffer_size});
    std.debug.print("Async batch:         {d}\n", .{config.async_config.batch_size});
    std.debug.print("Backpressure at:     {d:.2}\n", .{config.async_config.backpressure_threshold});
    std.debug.print("Thread pool enabled: {s}\n", .{if (config.thread_pool.enabled) "yes" else "no"});
    std.debug.print("Thread count:        {d}\n", .{config.thread_pool.thread_count});
    std.debug.print("Metrics format:      {s}\n", .{@tagName(config.metrics.export_format)});
    std.debug.print("Metrics prefix:      {s}\n", .{config.metrics.metric_prefix});
    std.debug.print("Rules enabled:       {s}\n", .{if (config.rules.enabled) "yes" else "no"});
    std.debug.print("Rotation interval:   {s}\n", .{config.rotation.interval orelse "none"});
    std.debug.print("Rotation compression:{s}\n", .{@tagName(config.rotation.compression_algorithm)});
    std.debug.print("Scheduler enabled:   {s}\n\n", .{if (config.scheduler.enabled) "yes" else "no"});

    var metrics = logly.Metrics.initWithConfig(allocator, config.metrics);
    defer metrics.deinit();

    const file_sink = try metrics.addSink("file:application.log");
    metrics.recordLog(.info, 120);
    metrics.recordLogWithLatency(.err, 64, 1_500_000);
    metrics.recordSinkWrite(file_sink, 184);
    metrics.recordSinkFlush(file_sink);

    const prometheus = try metrics.exportPrometheus(allocator);
    defer allocator.free(prometheus);

    std.debug.print("--- Prometheus Export Preview ---\n{s}\n", .{prometheus});

    var async_logger = try logly.AsyncLogger.initWithConfig(allocator, config.async_config);
    defer async_logger.deinit();

    _ = async_logger.queue("queued through async pipeline", @intFromEnum(logly.Level.info));
    _ = async_logger.drainDefault();
    std.debug.print("Async queue drained: {s}\n", .{if (async_logger.isQueueEmpty()) "yes" else "no"});
}
