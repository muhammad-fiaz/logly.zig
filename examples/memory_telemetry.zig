const std = @import("std");
const logly = @import("logly");

// Demonstrates real-time memory/allocator telemetry in logly.zig v0.2.1.
//
// MemoryTracker wraps the user allocator and tracks live bytes, peak
// bytes, allocation count, and deallocation count. Attach it to a
// Logger to read live memory state, set a callback, or release memory
// between workloads.

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const backing = gpa.allocator();

    var tracker = logly.MemoryTracker.init(backing);
    const tracked = tracker.allocator();

    var config = logly.Config.default();
    config.auto_sink = false;
    config.check_for_updates = false;
    config.global_console_display = false;

    const logger = try logly.Logger.initWithConfig(tracked, config);
    logger.attachMemoryTracker(&tracker);
    defer logger.deinit();

    try logger.info("memory tracker attached", @src());

    // Read a live snapshot.
    const initial = logger.getMemoryReport().?;
    std.debug.print(
        "[start] used={d} peak={d} capacity={d} allocs={d}\n",
        .{
            initial.bytes_used,
            initial.bytes_peak,
            initial.bytes_capacity,
            initial.allocation_count,
        },
    );

    // Issue a workload and inspect the resulting snapshot.
    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        try logger.infof("workload iteration {d}", .{i}, @src());
    }

    const after_load = logger.getMemoryReport().?;
    std.debug.print(
        "[after_load] used={d} peak={d} capacity={d} allocs={d} frees={d} live={d}\n",
        .{
            after_load.bytes_used,
            after_load.bytes_peak,
            after_load.bytes_capacity,
            after_load.allocation_count,
            after_load.deallocation_count,
            after_load.live_allocations,
        },
    );

    // Reset counters (peak is now reset to current live usage).
    _ = logger.releaseMemory();
    const after_reset = logger.getMemoryReport().?;
    std.debug.print(
        "[after_reset] used={d} peak={d} allocs={d} frees={d}\n",
        .{
            after_reset.bytes_used,
            after_reset.bytes_peak,
            after_reset.allocation_count,
            after_reset.deallocation_count,
        },
    );

    // OS-level telemetry is always available, even without a tracker.
    const os_available = logly.detectAvailableMemory();
    const os_current = logly.detectCurrentMemoryUsage();
    std.debug.print("[os] available={d} current_rss={d}\n", .{ os_available, os_current });
}
