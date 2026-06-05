const std = @import("std");
const logly = @import("logly");

// Demonstrates logly.zig v0.2.1 thread-pool auto-scaling and dynamic
// sizing helpers.

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Auto-detect: pass 0 to use the maximum available cores.
    const max = logly.ThreadPool.getMaxThreads();
    std.debug.print("Detected max threads: {d}\n", .{max});

    var pool = try logly.ThreadPool.initWithConfig(allocator, .{
        .thread_count = 0, // auto-detect
    });
    defer pool.deinit();

    try pool.start();
    std.debug.print("Pool started with {d} workers\n", .{pool.threadCount()});

    // Submit a batch of small tasks in a single lock acquisition.
    const Task = logly.ThreadPool.Task;
    const Work = struct {
        counter: *std.atomic.Value(usize),
        fn run(raw_ctx: *anyopaque, _: ?std.mem.Allocator) void {
            const self: *@This() = @ptrCast(@alignCast(raw_ctx));
            _ = self.counter.fetchAdd(1, .monotonic);
        }
    };

    var counter = std.atomic.Value(usize).init(0);
    var contexts: [64]Work = undefined;
    var tasks: [64]Task = undefined;
    for (&contexts, &tasks) |*ctx, *t| {
        ctx.* = .{ .counter = &counter };
        t.* = .{ .callback = .{ .func = Work.run, .context = ctx } };
    }
    const accepted = pool.submitBatch(&tasks, .normal);
    std.debug.print("Batch accepted: {d}/{d}\n", .{ accepted, tasks.len });

    pool.waitAll();
    std.debug.print("Counter after waitAll: {d}\n", .{counter.load(.monotonic)});

    // Dynamically request a different thread count. The change takes
    // effect on the next start()/shutdown() cycle.
    const old = pool.setThreadCount(max * 2);
    std.debug.print("Requested thread_count change: {d} -> {d}\n", .{ old, pool.config.thread_count });

    // Register a worker-start hook (id only) and a worker-stop hook.
    const StartCb = struct {
        fn run(worker_id: usize) void {
            std.debug.print("worker started: {d}\n", .{worker_id});
        }
    };
    const StopCb = struct {
        fn run(worker_id: usize, worker_processed: u64, pool_processed: u64) void {
            std.debug.print(
                "worker stopped: id={d} processed={d} pool_processed={d}\n",
                .{ worker_id, worker_processed, pool_processed },
            );
        }
    };

    pool.shutdown();
    pool.setWorkerStartCallback(StartCb.run);
    pool.setWorkerStopCallback(StopCb.run);
    try pool.start();
    pool.shutdown();
}
