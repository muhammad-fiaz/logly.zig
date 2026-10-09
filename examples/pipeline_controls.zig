const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("Pipeline Controls\n\n", .{});

    const config = logly.Config.default()
        .withHighThroughputPipeline()
        .withObservability("checkout.api")
        .withAsync(logly.AsyncConfig.lowLatency().withBufferSize(256).withBatchSize(8).withBackpressureThreshold(0.75))
        .withThreadPool(logly.ThreadPoolConfig.ioBound().withThreadCount(4).withQueueSize(512))
        .withRotation(logly.Config.RotationConfig.daily(7).withCompression(.zstd))
        .withScheduler(logly.SchedulerConfig.maintenance("logs/archive").withCleanupDays(14).withMaxFiles(100));

    std.debug.print("Async enabled:       {s}\n", .{if (config.asyncConfig.enabled) "yes" else "no"});
    std.debug.print("Async buffer:        {d}\n", .{config.asyncConfig.bufferSize});
    std.debug.print("Async batch:         {d}\n", .{config.asyncConfig.batchSize});
    std.debug.print("Backpressure at:     {d:.2}\n", .{config.asyncConfig.backpressureThreshold});
    std.debug.print("Thread pool enabled: {s}\n", .{if (config.threadPool.enabled) "yes" else "no"});
    std.debug.print("Thread count:        {d}\n", .{config.threadPool.threadCount});
    std.debug.print("Metrics format:      {s}\n", .{@tagName(config.metrics.exportFormat)});
    std.debug.print("Metrics prefix:      {s}\n", .{config.metrics.metricPrefix});
    std.debug.print("Rules enabled:       {s}\n", .{if (config.rules.enabled) "yes" else "no"});
    std.debug.print("Rotation interval:   {s}\n", .{config.rotation.interval orelse "none"});
    std.debug.print("Rotation compression:{s}\n", .{@tagName(config.rotation.compressionAlgorithm)});
    std.debug.print("Scheduler enabled:   {s}\n\n", .{if (config.scheduler.enabled) "yes" else "no"});

    var metrics = logly.Metrics.initWithConfig(allocator, config.metrics);
    defer metrics.deinit();

    const fileSink = try metrics.addSink("file:application.log");
    metrics.recordLog(.info, 120);
    metrics.recordLogWithLatency(.err, 64, 1_500_000);
    metrics.recordSinkWrite(fileSink, 184);
    metrics.recordSinkFlush(fileSink);

    const prometheus = try metrics.exportPrometheus(allocator);
    defer allocator.free(prometheus);

    std.debug.print("Prometheus Export Preview\n{s}\n", .{prometheus});

    var asyncLogger = try logly.AsyncLogger.initWithConfig(allocator, config.asyncConfig);
    defer asyncLogger.deinit();

    _ = asyncLogger.queue("queued through async pipeline", @backingInt(logly.Level.info));
    _ = asyncLogger.waitUntilDrainedDefault();
    std.debug.print("Async queue drained: {s}\n", .{if (asyncLogger.isQueueEmpty()) "yes" else "no"});
}
