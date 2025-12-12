//! Advanced Async Logging Example
//!
//! Demonstrates async logging with buffering, background threads,
//! and high-throughput configurations.

const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n=== Logly Advanced Async Example ===\n\n", .{});

    // Example 1: Async presets
    std.debug.print("1. Async Configuration Presets\n", .{});
    std.debug.print("   ----------------------------\n", .{});

    const high_throughput = logly.AsyncPresets.highThroughput();
    std.debug.print("   High Throughput:\n", .{});
    std.debug.print("     Buffer size: {d}\n", .{high_throughput.buffer_size});
    std.debug.print("     Flush interval: {d}ms\n", .{high_throughput.flush_interval_ms});
    std.debug.print("     Min flush interval: {d}ms\n", .{high_throughput.min_flush_interval_ms});
    std.debug.print("     Max latency: {d}ms\n", .{high_throughput.max_latency_ms});
    std.debug.print("     Batch size: {d}\n", .{high_throughput.batch_size});
    std.debug.print("     Overflow policy: {s}\n", .{@tagName(high_throughput.overflow_policy)});
    std.debug.print("     Background worker: {s}\n\n", .{if (high_throughput.background_worker) "yes" else "no"});

    const low_latency = logly.AsyncPresets.lowLatency();
    std.debug.print("   Low Latency:\n", .{});
    std.debug.print("     Buffer size: {d}\n", .{low_latency.buffer_size});
    std.debug.print("     Flush interval: {d}ms\n", .{low_latency.flush_interval_ms});
    std.debug.print("     Min flush interval: {d}ms\n", .{low_latency.min_flush_interval_ms});
    std.debug.print("     Max latency: {d}ms\n", .{low_latency.max_latency_ms});
    std.debug.print("     Batch size: {d}\n", .{low_latency.batch_size});
    std.debug.print("     Background worker: {s}\n\n", .{if (low_latency.background_worker) "yes" else "no"});

    const balanced = logly.AsyncPresets.balanced();
    std.debug.print("   Balanced:\n", .{});
    std.debug.print("     Buffer size: {d}\n", .{balanced.buffer_size});
    std.debug.print("     Flush interval: {d}ms\n", .{balanced.flush_interval_ms});
    std.debug.print("     Min flush interval: {d}ms\n", .{balanced.min_flush_interval_ms});
    std.debug.print("     Max latency: {d}ms\n", .{balanced.max_latency_ms});
    std.debug.print("     Batch size: {d}\n", .{balanced.batch_size});
    std.debug.print("     Background worker: {s}\n\n", .{if (balanced.background_worker) "yes" else "no"});

    const no_drop = logly.AsyncPresets.noDrop();
    std.debug.print("   No-Drop:\n", .{});
    std.debug.print("     Buffer size: {d}\n", .{no_drop.buffer_size});
    std.debug.print("     Overflow policy: {s}\n\n", .{@tagName(no_drop.overflow_policy)});

    // Example 2: Ring buffer operations
    std.debug.print("2. Ring Buffer Operations\n", .{});
    std.debug.print("   -----------------------\n", .{});

    var rb = try logly.AsyncLogger.RingBuffer.init(allocator, 100);
    defer rb.deinit();

    std.debug.print("   Buffer capacity: {d}\n", .{rb.capacity});
    std.debug.print("   Initial size: {d}\n", .{rb.size()});
    std.debug.print("   Is empty: {s}\n", .{if (rb.isEmpty()) "yes" else "no"});

    // Push some entries
    for (0..10) |i| {
        _ = rb.push(.{
            .timestamp = std.time.milliTimestamp(),
            .formatted_message = "Test message",
            .level_priority = 20,
            .queued_at = @intCast(i),
        });
    }

    std.debug.print("   After pushing 10 entries:\n", .{});
    std.debug.print("     Size: {d}\n", .{rb.size()});
    std.debug.print("     Is empty: {s}\n", .{if (rb.isEmpty()) "yes" else "no"});
    std.debug.print("     Is full: {s}\n\n", .{if (rb.isFull()) "yes" else "no"});

    // Pop entries
    var popped: usize = 0;
    while (rb.pop()) |_| {
        popped += 1;
    }
    std.debug.print("   Popped {d} entries\n", .{popped});
    std.debug.print("   Size after pop: {d}\n\n", .{rb.size()});

    // Example 3: Async statistics
    std.debug.print("3. Async Statistics Structure\n", .{});
    std.debug.print("   ---------------------------\n", .{});

    var stats = logly.AsyncLogger.AsyncStats{};
    _ = stats.records_queued.fetchAdd(1000, .monotonic);
    _ = stats.records_written.fetchAdd(990, .monotonic);
    _ = stats.records_dropped.fetchAdd(10, .monotonic);
    _ = stats.total_latency_ns.fetchAdd(5000000, .monotonic);

    std.debug.print("   Records queued: {d}\n", .{stats.records_queued.load(.monotonic)});
    std.debug.print("   Records written: {d}\n", .{stats.records_written.load(.monotonic)});
    std.debug.print("   Records dropped: {d}\n", .{stats.records_dropped.load(.monotonic)});
    std.debug.print("   Drop rate: {d:.2}%\n", .{stats.dropRate() * 100});
    std.debug.print("   Avg latency: {d} ns\n\n", .{stats.averageLatencyNs()});

    // Example 4: Overflow policies
    std.debug.print("4. Overflow Policies\n", .{});
    std.debug.print("   ------------------\n", .{});

    const policies = [_]logly.AsyncLogger.OverflowPolicy{
        .drop_oldest,
        .drop_newest,
        .block,
    };

    for (policies) |policy| {
        std.debug.print("   {s}: ", .{@tagName(policy)});
        switch (policy) {
            .drop_oldest => std.debug.print("Remove oldest entries to make room\n", .{}),
            .drop_newest => std.debug.print("Drop new entries when full\n", .{}),
            .block => std.debug.print("Block until space available\n", .{}),
        }
    }

    std.debug.print("\n=== Advanced Async Example Complete ===\n", .{});
}
