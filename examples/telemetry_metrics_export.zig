const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var config = logly.TelemetryConfig.development();
    config.metricFormat = .json;
    config.metricsFilePath = "telemetry_metrics.jsonl";

    var telemetry = try logly.Telemetry.init(allocator, config);
    defer telemetry.deinit();

    std.debug.print("Telemetry Metrics Export Example\n\n", .{});

    try telemetry.recordCounter("requests.total", 1.0);
    try telemetry.recordGauge("cpu.usage", 42.0);
    try telemetry.exportMetrics();

    std.debug.print("Metrics exported to {s}\n", .{config.metricsFilePath.?});
}
