//! Thread Pool Example
//!
//! Demonstrates parallel logging with thread pools for high-throughput scenarios.

const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n=== Logly Thread Pool Example ===\n\n", .{});

    // Example 1: Basic thread pool
    std.debug.print("1. Basic Thread Pool Setup\n", .{});
    std.debug.print("   ------------------------\n", .{});

    const pool = try logly.ThreadPool.initWithConfig(allocator, .{
        .num_threads = 4,
        .queue_size = 1024,
        .work_stealing = true,
    });
    defer pool.deinit();

    std.debug.print("   Created pool with {d} threads\n", .{pool.workers.len});
    std.debug.print("   Queue size: {d}\n", .{pool.config.queue_size});
    std.debug.print("   Work stealing: {s}\n\n", .{if (pool.config.work_stealing) "enabled" else "disabled"});

    // Example 2: Thread pool presets
    std.debug.print("2. Thread Pool Presets\n", .{});
    std.debug.print("   --------------------\n", .{});

    const single = logly.ThreadPoolPresets.singleThread();
    std.debug.print("   Single thread - threads: {d}, stealing: {s}\n", .{
        single.num_threads,
        if (single.work_stealing) "yes" else "no",
    });

    const cpu_bound = logly.ThreadPoolPresets.cpuBound();
    std.debug.print("   CPU bound - threads: auto ({d} cores), stealing: {s}\n", .{
        std.Thread.getCpuCount() catch 4,
        if (cpu_bound.work_stealing) "yes" else "no",
    });

    const io_bound = logly.ThreadPoolPresets.ioBound();
    std.debug.print("   I/O bound - threads: {d}, queue: {d}\n", .{
        io_bound.num_threads,
        io_bound.queue_size,
    });

    const high_throughput = logly.ThreadPoolPresets.highThroughput();
    std.debug.print("   High throughput - queue: {d}\n\n", .{high_throughput.queue_size});

    // Example 3: Submit tasks
    std.debug.print("3. Task Submission\n", .{});
    std.debug.print("   ----------------\n", .{});

    try pool.start();

    var counter: std.atomic.Value(u32) = std.atomic.Value(u32).init(0);
    const num_tasks: u32 = 100;

    const TestTask = struct {
        fn increment(ctx: *anyopaque, maybe_allocator: ?std.mem.Allocator) void {
            _ = maybe_allocator;
            const c: *std.atomic.Value(u32) = @ptrCast(@alignCast(ctx));
            _ = c.fetchAdd(1, .monotonic);
        }
    };

    // Submit tasks
    for (0..num_tasks) |_| {
        _ = pool.submitCallback(TestTask.increment, @ptrCast(&counter));
    }

    std.debug.print("   Submitted {d} tasks\n", .{num_tasks});
    std.debug.print("   Waiting for completion...\n", .{});

    pool.waitAll();

    std.debug.print("   Completed! Counter value: {d}\n\n", .{counter.load(.monotonic)});

    // Example 4: Statistics
    std.debug.print("4. Pool Statistics\n", .{});
    std.debug.print("   ----------------\n", .{});

    const stats = pool.getStats();
    std.debug.print("   Tasks submitted: {d}\n", .{stats.tasks_submitted.load(.monotonic)});
    std.debug.print("   Tasks completed: {d}\n", .{stats.tasks_completed.load(.monotonic)});
    std.debug.print("   Tasks dropped: {d}\n", .{stats.tasks_dropped.load(.monotonic)});
    std.debug.print("   Tasks stolen: {d}\n", .{stats.tasks_stolen.load(.monotonic)});
    std.debug.print("   Avg wait time: {d} ns\n", .{stats.avgWaitTimeNs()});
    std.debug.print("   Avg exec time: {d} ns\n", .{stats.avgExecTimeNs()});
    std.debug.print("   Throughput: {d:.2} tasks/sec\n\n", .{stats.throughput()});

    std.debug.print("=== Thread Pool Example Complete ===\n", .{});
}
