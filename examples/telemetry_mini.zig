const std = @import("std");
const logly = @import("logly");

var threaded = std.Io.Threaded.init_single_threaded;
const io = threaded.io();

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var config = logly.TelemetryConfig.file("telemetry_test.jsonl");
    config.serviceName = "test-app";
    config.enabled = true;

    var telemetry = try logly.Telemetry.init(allocator, config);
    defer telemetry.deinit();

    std.debug.print("Telemetry Mini Example\n\n", .{});

    {
        var span = try telemetry.startSpan("process_data", .{});
        defer span.deinit();
        defer {
            span.end();
            telemetry.endSpan(&span) catch {};
        }

        try span.setAttribute("items.count", .{ .integer = 42 });
        try span.addEvent("started", null);
        _ = io.sleep(std.Io.Duration.fromMilliseconds(10), .awake) catch {};
        try span.addEvent("finished", null);
    }

    try telemetry.exportSpans();

    std.debug.print("Telemetry exported to telemetry_test.jsonl\n", .{});
}
