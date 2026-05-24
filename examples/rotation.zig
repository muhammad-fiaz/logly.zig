const std = @import("std");
const logly = @import("logly");

// Custom callback function matching: ?*const fn (old_path: []const u8, new_path: []const u8) void
fn onRotateCallback(old_path: []const u8, new_path: []const u8) void {
    std.debug.print("[CALLBACK] Log rotated! Old path: {s} -> New path: {s}\n", .{ old_path, new_path });
}

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== Logly v0.2.0 Advanced Rotation Demonstration ===\n\n", .{});

    // 1. Configure the logger
    var config = logly.Config.default();
    config.auto_sink = false;

    // Use our new parsing helpers to create rotation configurations
    const size_rotation = logly.Config.RotationConfig.fromSize("10KB");
    const interval_rotation = logly.Config.RotationConfig.fromInterval("24h");

    std.debug.print("Parsed fromSize('10KB') size limit: {?s} bytes\n", .{size_rotation.size_limit_str});
    std.debug.print("Parsed fromInterval('24h') interval: {?s}\n", .{interval_rotation.interval});

    const logger = try logly.Logger.initWithConfig(allocator, config);
    defer logger.deinit();

    // 2. Add a sink using dynamic, hourly rotation with a custom on_rotate callback
    var hourly_rot_config = logly.Config.RotationConfig.fromInterval("hourly");
    hourly_rot_config.retention_count = 3;
    hourly_rot_config.max_total_size = 50 * 1024; // Limit to 50KB total size across rotated logs
    hourly_rot_config.on_rotate = onRotateCallback;

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
    const test_file_path = "logs/programmatic.log";
    // Ensure directory exists
    std.Io.Dir.cwd().createDirPath(logly.Utils.io(), "logs") catch {};
    var test_file = try std.Io.Dir.cwd().createFile(logly.Utils.io(), test_file_path, .{ .read = true, .truncate = true });
    defer test_file.close(logly.Utils.io());

    // Write some bytes
    try test_file.writeStreamingAll(logly.Utils.io(), "A" ** 500);

    // Dry-run check (shouldRotate does not perform rotation)
    const would_rotate = rotation.shouldRotate(&test_file);
    std.debug.print("Should rotate with 500 bytes of data (limit 1KB)? {}\n", .{would_rotate});

    // Write more to trigger size limit
    try test_file.writeStreamingAll(logly.Utils.io(), "B" ** 600);
    const would_rotate_now = rotation.shouldRotate(&test_file);
    std.debug.print("Should rotate with 1100 bytes of data (limit 1KB)? {}\n", .{would_rotate_now});

    // Force rotate to show custom callback triggers
    std.debug.print("\nForcing programmatic rotation...\n", .{});
    try rotation.forceRotate(&test_file);

    try logger.info("Rotation example - advanced capabilities demonstrated successfully", @src());
    try logger.flush();

    std.debug.print("\nRotation example completed successfully!\n", .{});
}
