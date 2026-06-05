const std = @import("std");
const logly = @import("logly");

// Demonstrates the logly.zig v0.2.1 fast-path JSON formatter. JSON
// output is built with pre-sized ArrayList buffers, bulk-safe
// `escapeJsonString` runs, and an in-place timestamp writer. Use this
// template when you are emitting structured logs at high QPS.

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var config = logly.Config.default();
    config.auto_sink = false;
    config.check_for_updates = false;
    config.global_console_display = false;
    config.json = true;
    config.pretty_json = true;
    config.include_hostname = false;
    config.include_pid = true;

    const logger = try logly.Logger.initWithConfig(allocator, config);
    defer logger.deinit();

    const before = std.Io.Clock.awake.now(logly.Utils.io());
    var i: usize = 0;
    while (i < 10_000) : (i += 1) {
        try logger.infof("request_id={d} user=alice status=ok bytes={d}", .{ i, 1024 + i }, @src());
    }
    const after = std.Io.Clock.awake.now(logly.Utils.io());
    const elapsed_ns: u64 = @intCast(@max(0, after.nanoseconds - before.nanoseconds));
    const ops_per_sec: f64 = if (elapsed_ns == 0)
        0
    else
        @as(f64, @floatFromInt(10_000)) / (@as(f64, @floatFromInt(elapsed_ns)) / 1e9);
    std.debug.print("compact JSON: 10,000 records in {d} ns ({d:.0} ops/sec)\n", .{ elapsed_ns, ops_per_sec });

    config.pretty_json = false;
    const before2 = std.Io.Clock.awake.now(logly.Utils.io());
    i = 0;
    while (i < 10_000) : (i += 1) {
        try logger.infof("request_id={d} user=bob status=ok bytes={d}", .{ i, 2048 + i }, @src());
    }
    const after2 = std.Io.Clock.awake.now(logly.Utils.io());
    const elapsed2: u64 = @intCast(@max(0, after2.nanoseconds - before2.nanoseconds));
    const ops2: f64 = if (elapsed2 == 0)
        0
    else
        @as(f64, @floatFromInt(10_000)) / (@as(f64, @floatFromInt(elapsed2)) / 1e9);
    std.debug.print("pretty  JSON: 10,000 records in {d} ns ({d:.0} ops/sec)\n", .{ elapsed2, ops2 });
}
