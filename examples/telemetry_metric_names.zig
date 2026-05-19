const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const metrics_path = "telemetry_metric_names.prom";

    var config = logly.TelemetryConfig.development()
        .withPrometheusMetrics(metrics_path)
        .withMetricPrefix("api.v1");
    config.metric_prefix_separator = ":";
    config.sanitize_metric_names = true;

    var telemetry = try logly.Telemetry.init(allocator, config);
    defer telemetry.deinit();

    try telemetry.recordCounter("http.requests-total", 42.0);
    try telemetry.recordGauge("99.cpu.usage", 73.5);
    try telemetry.exportMetrics();

    std.debug.print("Telemetry metric names exported to {s}\n", .{metrics_path});
    std.debug.print("Sanitized examples:\n", .{});
    std.debug.print("  api.v1:http.requests-total -> api_v1:http_requests_total\n", .{});
    std.debug.print("  api.v1:99.cpu.usage       -> api_v1:_99_cpu_usage\n", .{});
}
