//! Scheduler Example
//!
//! Demonstrates scheduled log maintenance tasks including cron expressions,
//! one-shot tasks, task cancellation, and jitter for thundering herd prevention.

const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\nScheduler Example\n\n", .{});

    // Example 1: Basic scheduler setup
    std.debug.print("1. Basic Scheduler Setup\n", .{});
    std.debug.print("\n", .{});

    const scheduler = try logly.Scheduler.init(allocator);
    defer scheduler.deinit();

    std.debug.print("   Scheduler initialized\n\n", .{});

    // Example 2: Cron-like expressions
    std.debug.print("2. Cron-like Schedule Types\n", .{});
    std.debug.print("\n", .{});

    // Interval-based schedule (every 60 seconds)
    const intervalSchedule = logly.Scheduler.Schedule{ .interval = 60000 };
    std.debug.print("   Interval: every 60 seconds\n", .{});
    _ = intervalSchedule;

    // Daily at 02:30 (cron-like)
    const dailySchedule = logly.SchedulerPresets.dailyAt(2, 30);
    std.debug.print("   Daily at 02:30 (cron-like)\n", .{});
    _ = dailySchedule;

    // Every 5 minutes (cron-like)
    const minutesSchedule = logly.SchedulerPresets.everyMinutes(5);
    std.debug.print("   Every 5 minutes (cron-like)\n", .{});
    _ = minutesSchedule;

    // Cron expression: midnight every day (min=0, hour=0)
    const midnightCron = logly.Scheduler.Schedule{ .cron = .{ .minute = 0, .hour = 0 } };
    std.debug.print("   Cron expression: minute=0 hour=0 (midnight)\n\n", .{});
    _ = midnightCron;

    // Example 3: Adding tasks (cron, one-shot, custom)
    std.debug.print("3. Adding Tasks (Cron, One-Shot, Custom)\n", .{});
    std.debug.print("\n", .{});

    // Cleanup task with interval
    const cleanupIdx = try scheduler.addTask(
        "log_cleanup",
        .cleanup,
        .{ .interval = 3600000 },
        .{
            .path = "logs",
            .maxAgeSeconds = 7 * 24 * 60 * 60,
            .filePattern = "*.log",
        },
    );
    std.debug.print("   Added cleanup task (index: {d})\n", .{cleanupIdx});

    // Compression task with daily cron
    const compIdx = try scheduler.addTask(
        "log_compression",
        .compression,
        logly.SchedulerPresets.dailyAt(3, 0),
        .{
            .path = "logs",
            .filePattern = "*.log",
        },
    );
    std.debug.print("   Added compression task at 03:00 daily (index: {d})\n", .{compIdx});

    // Custom one-shot task
    const OneShotTask = struct {
        fn execute(_: *logly.Scheduler.ScheduledTask) anyerror!void {
            std.debug.print("   [One-shot] Maintenance task executed!\n", .{});
        }
    };

    const oneshotIdx = try scheduler.addCustomTask(
        "oneshot_maintenance",
        .{ .interval = 1 }, // run immediately in 1ms
        OneShotTask.execute,
    );
    std.debug.print("   Added one-shot custom task (index: {d})\n\n", .{oneshotIdx});

    // Example 4: Task cancellation
    std.debug.print("4. Task Cancellation\n", .{});
    std.debug.print("\n", .{});

    // Disable (cancel) the cleanup task
    scheduler.setTaskEnabled(cleanupIdx, false);
    std.debug.print("   Cancelled/disabled task {d} (log_cleanup)\n", .{cleanupIdx});

    // Re-enable
    scheduler.setTaskEnabled(cleanupIdx, true);
    std.debug.print("   Re-enabled task {d} (log_cleanup)\n\n", .{cleanupIdx});

    // Example 5: Jitter configuration
    std.debug.print("5. Jitter (Thundering Herd Prevention)\n", .{});
    std.debug.print("\n", .{});

    std.debug.print("   Jitter adds random delay +/-N ms to prevent thundering herd.\n", .{});
    std.debug.print("   Configure via SchedulerConfig.jitterMs in the scheduler config.\n", .{});
    std.debug.print("   Example: jitterMs = 5000 adds +/-5 second random delay.\n\n", .{});

    // Example 6: Task management
    std.debug.print("6. Task Management and History\n", .{});
    std.debug.print("\n", .{});

    const tasks = scheduler.getTasks();
    std.debug.print("   Total tasks: {d}\n", .{tasks.len});

    for (tasks, 0..) |task, i| {
        std.debug.print("   Task {d}: '{s}' type={s} enabled={s}\n", .{
            i,
            task.name,
            @tagName(task.taskType),
            if (task.enabled) "yes" else "no",
        });
    }

    // Example 7: Scheduler presets
    std.debug.print("\n7. Scheduler Presets\n", .{});
    std.debug.print("\n", .{});

    const dailyCleanup = logly.SchedulerPresets.dailyCleanup("logs", 30);
    std.debug.print("   Daily cleanup config:\n", .{});
    std.debug.print("     Path:    {s}\n", .{dailyCleanup.path orelse "none"});
    std.debug.print("     Max age: {d} days\n", .{dailyCleanup.maxAgeSeconds / (24 * 60 * 60)});
    std.debug.print("     Pattern: {s}\n\n", .{dailyCleanup.filePattern orelse "*"});

    // Example 8: Statistics
    std.debug.print("8. Scheduler Statistics\n", .{});
    std.debug.print("\n", .{});

    const stats = scheduler.getStats();
    std.debug.print("   Tasks executed:  {d}\n", .{stats.getExecuted()});
    std.debug.print("   Tasks failed:    {d}\n", .{stats.getFailed()});
    std.debug.print("   Files cleaned:   {d}\n", .{stats.getFilesCleaned()});
    std.debug.print("   Bytes freed:     {d}\n\n", .{stats.getBytesFreed()});

    std.debug.print("Scheduler Example Complete\n", .{});
}
