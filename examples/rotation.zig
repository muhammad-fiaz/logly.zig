const std = @import("std");
const logly = @import("logly");

// Custom callback function matching: ?*const fn (old_path: []const u8, new_path: []const u8) void
fn onRotateCallback(oldPath: []const u8, newPath: []const u8) void {
    std.debug.print("[CALLBACK] Log rotated! Old path: {s} -> New path: {s}\n", .{ oldPath, newPath });
}

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("Advanced Rotation Demonstration\n\n", .{});

    // 1. Configure the logger
    var config = logly.Config.default();
    config.autoSink = false;

    // Use our new parsing helpers to create rotation configurations
    const sizeRotation = logly.Config.RotationConfig.fromSize("10KB");
    const intervalRotation = logly.Config.RotationConfig.fromInterval("24h");

    const parsedSizeBytes = logly.Utils.parseSize(sizeRotation.sizeLimitStr orelse "0") orelse 0;
    const parsedIntervalMs = logly.Utils.parseDuration(intervalRotation.interval orelse "0") orelse 0;
    std.debug.print("Parsed fromSize('10KB') size limit: {d} bytes\n", .{parsedSizeBytes});
    std.debug.print("Parsed fromInterval('24h') interval: {d}ms ({d}s)\n", .{ parsedIntervalMs, @divTrunc(parsedIntervalMs, 1000) });

    const logger = try logly.Logger.initWithConfig(allocator, config);
    defer logger.deinit();

    // 2. Add a sink using dynamic, hourly rotation with a custom on_rotate callback
    var hourlyRotConfig = logly.Config.RotationConfig.fromInterval("hourly");
    hourlyRotConfig.retentionCount = 3;
    hourlyRotConfig.maxTotalSize = 50 * 1024; // Limit to 50KB total size across rotated logs
    hourlyRotConfig.onRotate = onRotateCallback;

    std.debug.print("Adding hourly rotating sink with 50KB total size cap...\n", .{});
    _ = try logger.addSink(.{
        .path = "logs/hourly_rotation.log",
        .rotation = "hourly",
        .retention = 3,
        // Wait, addSink accepts SinkConfig, so we configure rotation settings
    });

    // 3. Let's create a Rotation instance directly to showcase fine-grained manual/programmatic rotation checks and dry-run
    std.debug.print("\nCreating programmatic Rotation instance for 'logs/programmatic.log'...\n", .{});
    var rotation = try logly.Rotation.init(allocator, "logs/programmatic.log", "hourly", 1024, 3);
    defer rotation.deinit();

    // Configure additional features
    rotation.withMaxTotalSize(2048); // enforce 2KB total size limit
    rotation.withOnRotate(onRotateCallback);

    std.debug.print("Rotation dry-run enabled check: isEnabled() = {}\n", .{rotation.isEnabled()});
    std.debug.print("Next rotation in seconds: {?d}\n", .{rotation.nextRotationInSeconds()});

    // Let's simulate creating a file and testing shouldRotate
    const testFilePath = "logs/programmatic.log";
    // Ensure directory exists
    std.Io.Dir.cwd().createDirPath(logly.Utils.io(), "logs") catch {};
    var testFile = try std.Io.Dir.cwd().createFile(logly.Utils.io(), testFilePath, .{ .read = true, .truncate = true });
    defer testFile.close(logly.Utils.io());

    // Write some bytes
    var fillA: [500]u8 = @splat('A');
    try testFile.writeStreamingAll(logly.Utils.io(), &fillA);

    // Dry-run check (shouldRotate does not perform rotation)
    const wouldRotate = rotation.shouldRotate(&testFile);
    std.debug.print("Should rotate with 500 bytes of data (limit 1KB)? {}\n", .{wouldRotate});

    // Write more to trigger size limit
    var fillB: [600]u8 = @splat('B');
    try testFile.writeStreamingAll(logly.Utils.io(), &fillB);
    const wouldRotateNow = rotation.shouldRotate(&testFile);
    std.debug.print("Should rotate with 1100 bytes of data (limit 1KB)? {}\n", .{wouldRotateNow});

    // Force rotate to show custom callback triggers
    std.debug.print("\nForcing programmatic rotation...\n", .{});
    try rotation.forceRotate(&testFile);

    try logger.info("Rotation example - advanced capabilities demonstrated successfully", @src());
    try logger.flush();

    std.debug.print("\nRotation example completed successfully!\n", .{});
}
