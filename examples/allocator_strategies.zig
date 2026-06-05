const std = @import("std");
const logly = @import("logly");

fn runDebugAllocatorExample(allocator: std.mem.Allocator) !void {
    var config = logly.Config.default();
    config.check_for_updates = false;

    const logger = try logly.Logger.initWithConfig(allocator, config);
    defer logger.deinit();

    try logger.info("DebugAllocator: production-safe default with leak + double-free detection", @src());
}

fn runUserArenaExample(parent: std.mem.Allocator) !void {
    var arena = std.heap.ArenaAllocator.init(parent);
    defer arena.deinit();

    var config = logly.Config.default();
    config.check_for_updates = false;

    const logger = try logly.Logger.initWithConfig(arena.allocator(), config);
    defer logger.deinit();

    try logger.info("User arena: logger allocates through the user-wrapped arena", @src());

    var i: usize = 0;
    while (i < 10) : (i += 1) {
        try logger.infof("Arena batch item {d}", .{i}, @src());
    }

    try logger.success("All temporary allocations reclaimed by the arena", @src());
}

fn runPageAllocatorExample() !void {
    var config = logly.Config.default();
    config.check_for_updates = false;

    const logger = try logly.Logger.initWithConfig(std.heap.page_allocator, config);
    defer logger.deinit();

    try logger.info("Page allocator: fastest in benchmarks, no per-allocation frees", @src());
}

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    _ = logly.Terminal.enableAnsiColors();

    std.debug.print("\n=== Allocator Strategies Demo (v0.2.1) ===\n", .{});

    std.debug.print("\n1) DebugAllocator (recommended default)\n", .{});
    try runDebugAllocatorExample(allocator);

    std.debug.print("\n2) User-wrapped ArenaAllocator (high-throughput)\n", .{});
    try runUserArenaExample(allocator);

    std.debug.print("\n3) page_allocator (short-lived utilities, benchmarks)\n", .{});
    try runPageAllocatorExample();

    std.debug.print("\nDone.\n", .{});
}
