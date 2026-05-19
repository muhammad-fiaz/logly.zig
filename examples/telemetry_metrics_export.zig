const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var config = logly.TelemetryConfig.development();
    config.metric_format = .json;
    config.metrics_file_path = "telemetry_metrics.jsonl";

    var telemetry = try logly.Telemetry.init(allocator, config);
    defer telemetry.deinit();

    try telemetry.recordCounter("requests.total", 1.0);
    try telemetry.recordGauge("cpu.usage", 42.0);
    try telemetry.exportMetrics();

    std.debug.print("Metrics exported to {s}\n", .{config.metrics_file_path.?});
}
