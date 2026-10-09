const std = @import("std");
const logly = @import("logly");

var threaded = std.Io.Threaded.init_single_threaded;
const io = threaded.io();

/// Sink rotation callback. Receives the archived and current paths.
fn onRotate(oldPath: []const u8, newPath: []const u8) void {
    std.debug.print("[CALLBACK] rotated: {s} -> {s}\n", .{ oldPath, newPath });
}

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("Rotation demonstration\n\n", .{});

    var config = logly.Config.default();
    config.autoSink = false;
    // Rotation callbacks are a logger-wide setting, so they belong on the
    // rotation config rather than on an individual sink.
    config.rotation.onRotate = onRotate;

    const logger = try logly.Logger.initWithConfig(allocator, config);
    defer logger.deinit();

    // Time-based rotation with a retention count.
    std.debug.print("Adding hourly rotating sink (3 retained files)...\n", .{});
    _ = try logger.addSink(.{
        .name = "hourly",
        .path = "logs/hourly_rotation.log",
        .rotation = "hourly",
        .retention = 3,
    });

    // Size-based rotation: roll the file once it passes 5KB.
    std.debug.print("Adding size-based rotating sink (5KB cap)...\n", .{});
    _ = try logger.addSink(.{
        .name = "size-based",
        .path = "logs/size_rotation.log",
        .sizeLimit = 5 * 1024,
        .retention = 5,
        .overwriteMode = true,
    });

    // Drive the size-based sink past its threshold so rotation is exercised.
    // SinkConfig.sizeLimit is a byte count, so the trigger is a real write,
    // not a simulated size report.
    const payload = "size-based rotation payload: the quick brown fox jumps over the lazy dog, repeatedly, until the file passes its byte threshold and rolls over.";
    var i: usize = 0;
    while (i < 40) : (i += 1) {
        try logger.info(payload, null);
    }
    try logger.flush();

    // A rotating file sink writes one record per line; confirm the file exists
    // and carries content after the run.
    const rotated = try std.Io.Dir.cwd().openFile(io, "logs/size_rotation.log", .{});
    defer rotated.close(io);
    const stat = try rotated.stat(io);
    std.debug.print("size_rotation.log is {d} bytes after writing ~{d} records\n", .{ stat.size, i });

    try logger.info("rotation example completed", null);
    try logger.flush();

    std.debug.print("\nRotation example completed successfully!\n", .{});
}
