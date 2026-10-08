const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("Rotation Helpers Example\n\n", .{});

    var config = logly.Config.default();
    config.autoSink = false;

    const logger = try logly.Logger.initWithConfig(allocator, config);
    defer logger.deinit();

    // Hourly rotation is declared per sink; the interval and retention are the
    // public knobs. There is no separate Rotation object to manage.
    _ = try logger.addSink(.{
        .name = "hourly",
        .path = "logs/app.log",
        .rotation = "hourly",
        .retention = 7,
    });

    // Size limits accept either a byte count or a human-readable string.
    _ = try logger.addSink(.{
        .name = "capped",
        .path = "logs/capped.log",
        .sizeLimitStr = "10MB",
        .retention = 3,
        .overwriteMode = true,
    });

    try logger.info("rotation helpers: both sinks configured", null);
    try logger.flush();

    std.debug.print("hourly sink: interval \"hourly\", retention 7\n", .{});
    std.debug.print("capped sink: sizeLimitStr \"10MB\", retention 3\n", .{});
    std.debug.print("\nRotation helpers example completed!\n", .{});
}
