const std = @import("std");
const logly = @import("logly");

fn runDefaultAllocatorExample(allocator: std.mem.Allocator) !void {
    var config = logly.Config.default();
    config.check_for_updates = false;

    const logger = try logly.Logger.initWithConfig(allocator, config);
    defer logger.deinit();

    try logger.info("Default strategy: logger uses the allocator passed to init (GPA in this example)", @src());
    try logger.info("Arena allocation is disabled by default", @src());
}

fn runArenaAllocatorExample(allocator: std.mem.Allocator) !void {
    var config = logly.Config.default();
    config.use_arena_allocator = true;
    config.check_for_updates = false;
    config.arena_reset_threshold = 64 * 1024;

    const logger = try logly.Logger.initWithConfig(allocator, config);
    defer logger.deinit();

    try logger.info("Arena strategy: temporary record/format allocations use logger scratch arena", @src());

    var i: usize = 0;
    while (i < 10) : (i += 1) {
        try logger.infof("Arena batch item {d}", .{i}, @src());
    }

    // Optional explicit reset for known batch boundaries.
    logger.resetArena();
    try logger.success("Arena reset completed for current batch", @src());
}

fn runArenaAllocatorAliasExample(allocator: std.mem.Allocator) !void {
    var config = logly.Config.default().withArenaAllocator();
    config.check_for_updates = false;
    config.arena_reset_threshold = 64 * 1024;

    const logger = try logly.Logger.initWithConfig(allocator, config);
    defer logger.deinit();

    try logger.info("Alias strategy: withArenaAllocator() is equivalent to use_arena_allocator=true", @src());
}

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    _ = logly.Terminal.enableAnsiColors();

    std.debug.print("\n=== Allocator Strategies Demo ===\n", .{});
    std.debug.print("1) Default allocator path (GPA)\n", .{});
    try runDefaultAllocatorExample(allocator);

    std.debug.print("\n2) Optional arena allocator path\n", .{});
    try runArenaAllocatorExample(allocator);

    std.debug.print("\n3) Optional arena allocator alias path\n", .{});
    try runArenaAllocatorAliasExample(allocator);

    std.debug.print("\nDone.\n", .{});
}
