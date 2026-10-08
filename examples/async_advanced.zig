const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\nLogly Advanced Async Example\n\n", .{});

    // Example 1: Async presets
    std.debug.print("1. Async Configuration Presets\n", .{});
    std.debug.print("\n", .{});

    const highThroughput = logly.AsyncPresets.highThroughput();
    std.debug.print("   High Throughput:\n", .{});
    std.debug.print("     Buffer size: {d}\n", .{highThroughput.bufferSize});
    std.debug.print("     Flush interval: {d}ms\n", .{highThroughput.flushIntervalMs});
    std.debug.print("     Min flush interval: {d}ms\n", .{highThroughput.minFlushIntervalMs});
    std.debug.print("     Max latency: {d}ms\n", .{highThroughput.maxLatencyMs});
    std.debug.print("     Batch size: {d}\n", .{highThroughput.batchSize});
    std.debug.print("     Overflow policy: {s}\n", .{@tagName(highThroughput.overflowPolicy)});
    std.debug.print("     Background worker: {s}\n\n", .{if (highThroughput.backgroundWorker) "yes" else "no"});

    const lowLatency = logly.AsyncPresets.lowLatency();
    std.debug.print("   Low Latency:\n", .{});
    std.debug.print("     Buffer size: {d}\n", .{lowLatency.bufferSize});
    std.debug.print("     Flush interval: {d}ms\n", .{lowLatency.flushIntervalMs});
    std.debug.print("     Min flush interval: {d}ms\n", .{lowLatency.minFlushIntervalMs});
    std.debug.print("     Max latency: {d}ms\n", .{lowLatency.maxLatencyMs});
    std.debug.print("     Batch size: {d}\n", .{lowLatency.batchSize});
    std.debug.print("     Background worker: {s}\n\n", .{if (lowLatency.backgroundWorker) "yes" else "no"});

    const balanced = logly.AsyncPresets.balanced();
    std.debug.print("   Balanced:\n", .{});
    std.debug.print("     Buffer size: {d}\n", .{balanced.bufferSize});
    std.debug.print("     Flush interval: {d}ms\n", .{balanced.flushIntervalMs});
    std.debug.print("     Min flush interval: {d}ms\n", .{balanced.minFlushIntervalMs});
    std.debug.print("     Max latency: {d}ms\n", .{balanced.maxLatencyMs});
    std.debug.print("     Batch size: {d}\n", .{balanced.batchSize});
    std.debug.print("     Background worker: {s}\n\n", .{if (balanced.backgroundWorker) "yes" else "no"});

    const noDrop = logly.AsyncPresets.noDrop();
    std.debug.print("   No-Drop:\n", .{});
    std.debug.print("     Buffer size: {d}\n", .{noDrop.bufferSize});
    std.debug.print("     Overflow policy: {s}\n\n", .{@tagName(noDrop.overflowPolicy)});

    // Example 2: Ring buffer operations
    std.debug.print("2. Ring Buffer Operations\n", .{});
    std.debug.print("\n", .{});

    var rb = try logly.AsyncLogger.RingBuffer.init(allocator, 100);
    defer rb.deinit();

    std.debug.print("   Buffer capacity: {d}\n", .{rb.capacity});
    std.debug.print("   Initial size: {d}\n", .{rb.size()});
    std.debug.print("   Is empty: {s}\n", .{if (rb.isEmpty()) "yes" else "no"});

    // Push some entries
    for (0..10) |i| {
        _ = rb.push(.{
            .timestamp = logly.Utils.currentMillis(),
            .formattedMessage = "Test message",
            .levelPriority = 20,
            .queuedAt = @intCast(i),
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
    std.debug.print("\n", .{});

    var stats = logly.AsyncLogger.AsyncStats{};
    _ = stats.recordsQueued.fetchAdd(1000, .monotonic);
    _ = stats.recordsWritten.fetchAdd(990, .monotonic);
    _ = stats.recordsDropped.fetchAdd(10, .monotonic);
    _ = stats.totalLatencyNs.fetchAdd(5000000, .monotonic);

    std.debug.print("   Records queued: {d}\n", .{stats.getQueued()});
    std.debug.print("   Records written: {d}\n", .{stats.getWritten()});
    std.debug.print("   Records dropped: {d}\n", .{stats.getDropped()});
    std.debug.print("   Drop rate: {d:.2}%\n", .{stats.dropRate() * 100});
    std.debug.print("   Avg latency: {d} ns\n\n", .{stats.averageLatencyNs()});

    // Example 4: Overflow policies
    std.debug.print("4. Overflow Policies\n", .{});
    std.debug.print("\n", .{});

    const policies = [_]logly.AsyncLogger.OverflowPolicy{
        .dropOldest,
        .dropNewest,
        .block,
    };

    for (policies) |policy| {
        std.debug.print("   {s}: ", .{@tagName(policy)});
        switch (policy) {
            .dropOldest => std.debug.print("Remove oldest entries to make room\n", .{}),
            .dropNewest => std.debug.print("Drop new entries when full\n", .{}),
            .block => std.debug.print("Block until space available\n", .{}),
        }
    }

    std.debug.print("\nAdvanced Async Example Complete\n", .{});
}
