const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    logly.UpdateChecker.setEnabled(false);

    var config = logly.TelemetryConfig.file("telemetry_test.jsonl");
    config.service_name = "test-app";
    config.enabled = true;

    var telemetry = try logly.Telemetry.init(allocator, config);
    defer telemetry.deinit();

    {
        var span = try telemetry.startSpan("process_data", .{});
        defer span.deinit();
        defer {
            span.end();
            telemetry.endSpan(&span) catch {};
        }

        try span.setAttribute("items.count", .{ .integer = 42 });
        try span.addEvent("started", null);
        std.time.sleep(10 * std.time.ns_per_ms);
        try span.addEvent("finished", null);
    }

    try telemetry.exportSpans();

    std.debug.print("Telemetry exported to telemetry_test.jsonl\n", .{});
}
