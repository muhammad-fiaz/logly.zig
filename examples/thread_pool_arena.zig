const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();

    // Wrap an arena around the user allocator for high-throughput temporary churn.
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();
    const allocator = arena.allocator();

    // Configure Logger with a Thread Pool for parallel log processing.
    var config = logly.Config.default();

    config.thread_pool = .{
        .enabled = true,
        .thread_count = 4, // Use 4 worker threads
        .queue_size = 1000,
        .work_stealing = true,
    };

    config.show_thread_id = true;

    const logger = try logly.Logger.initWithConfig(allocator, config);
    defer logger.deinit();

    _ = try logger.add(logly.SinkConfig.file("logs/thread_pool_user_arena.log"));

    std.debug.print("Starting parallel logging demo with user-wrapped arena...\n", .{});
    std.debug.print("Thread pool size: {d}\n", .{config.thread_pool.thread_count});
    std.debug.print("Main Thread ID: {d}\n", .{std.Thread.getCurrentId()});

    try logger.info("Application started with Thread Pool and user-wrapped arena", @src());

    var i: usize = 0;
    while (i < 100) : (i += 1) {
        try logger.infof("Processing item {d} on thread pool", .{i}, @src());

        if (i % 10 == 0) {
            try logger.warn("Periodic warning message", @src());
        }
    }
    try logger.success("Finished processing items", @src());

    // Allow async logs to flush.
    logly.Utils.sleepMs(100);

    std.debug.print("Done! Check logs/thread_pool_user_arena.log\n", .{});
}
