const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Configure Logger with Thread Pool and Arena Allocation
    var config = logly.Config.default();

    // Enable Thread Pool
    config.thread_pool = .{
        .enabled = true,
        .thread_count = 4, // Use 4 worker threads
        .queue_size = 1000,
        .work_stealing = true,
        // Enable per-worker arena for efficient memory usage during formatting
        .enable_arena = true,
    };

    // Enable Arena Allocation for the main logger (initial record creation)
    config.use_arena_allocator = true;

    // Show Thread ID in logs
    config.show_thread_id = true;

    // Initialize Logger
    const logger = try logly.Logger.initWithConfig(allocator, config);
    defer logger.deinit();

    // Add a file sink to see the output
    _ = try logger.add(logly.SinkConfig.file("logs/thread_pool_arena.log"));

    std.debug.print("Starting parallel logging demo with Arena Allocation...\n", .{});
    std.debug.print("Arena allocation enabled: {s}\n", .{if (config.thread_pool.enable_arena) "yes" else "no"});
    std.debug.print("Thread pool size: {d}\n", .{config.thread_pool.thread_count});
    std.debug.print("Main Thread ID: {d}\n", .{std.Thread.getCurrentId()});

    // Log some messages
    try logger.info("Application started with Thread Pool and Arena Allocation", @src());

    // Simulate high throughput
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        try logger.infof("Processing item {d} on thread pool", .{i}, @src());

        if (i % 10 == 0) {
            try logger.warn("Periodic warning message", @src());
        }
    }
    try logger.success("Finished processing items", @src());

    // Wait a bit for async logs to flush (since main exits immediately)
    // Using explicit cast to u64 to avoid integer overflow
    std.Thread.sleep(@as(u64, 100) * std.time.ns_per_ms);

    std.debug.print("Done! Check logs/thread_pool_arena.log\n", .{});
}
