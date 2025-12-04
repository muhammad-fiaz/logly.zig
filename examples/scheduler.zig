//! Scheduler Example
//!
//! Demonstrates scheduled log maintenance tasks including cleanup,
//! compression, and custom scheduled operations.

const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n=== Logly Scheduler Example ===\n\n", .{});

    // Example 1: Basic scheduler setup
    std.debug.print("1. Basic Scheduler Setup\n", .{});
    std.debug.print("   ----------------------\n", .{});

    const scheduler = try logly.Scheduler.init(allocator);
    defer scheduler.deinit();

    std.debug.print("   Scheduler initialized\n\n", .{});

    // Example 2: Schedule types
    std.debug.print("2. Schedule Types\n", .{});
    std.debug.print("   ---------------\n", .{});

    // Interval-based schedule
    const interval_schedule = logly.Scheduler.Schedule{ .interval = 60000 }; // Every minute
    std.debug.print("   Interval: Every 60 seconds\n", .{});

    // Daily schedule
    const daily_schedule = logly.SchedulerPresets.dailyAt(2, 30);
    std.debug.print("   Daily: At 02:30\n", .{});

    // Every N minutes
    const minutes_schedule = logly.SchedulerPresets.everyMinutes(5);
    std.debug.print("   Every 5 minutes\n\n", .{});

    _ = interval_schedule;
    _ = daily_schedule;
    _ = minutes_schedule;

    // Example 3: Adding tasks
    std.debug.print("3. Adding Scheduled Tasks\n", .{});
    std.debug.print("   -----------------------\n", .{});

    // Cleanup task
    const cleanup_idx = try scheduler.addTask(
        "log_cleanup",
        .cleanup,
        .{ .interval = 3600000 }, // Every hour
        .{
            .path = "logs",
            .max_age_seconds = 7 * 24 * 60 * 60, // 7 days
            .file_pattern = "*.log",
        },
    );
    std.debug.print("   Added cleanup task (index: {d})\n", .{cleanup_idx});

    // Compression task
    const comp_idx = try scheduler.addTask(
        "log_compression",
        .compression,
        logly.SchedulerPresets.dailyAt(3, 0), // 3 AM daily
        .{
            .path = "logs",
            .file_pattern = "*.log",
        },
    );
    std.debug.print("   Added compression task (index: {d})\n", .{comp_idx});

    // Custom task
    const CustomTask = struct {
        fn execute(_: *logly.Scheduler.ScheduledTask) anyerror!void {
            // Custom maintenance logic here
        }
    };

    const custom_idx = try scheduler.addCustomTask(
        "custom_maintenance",
        .{ .interval = 300000 }, // Every 5 minutes
        CustomTask.execute,
    );
    std.debug.print("   Added custom task (index: {d})\n\n", .{custom_idx});

    // Example 4: Task management
    std.debug.print("4. Task Management\n", .{});
    std.debug.print("   ----------------\n", .{});

    const tasks = scheduler.getTasks();
    std.debug.print("   Total tasks: {d}\n", .{tasks.len});

    for (tasks, 0..) |task, i| {
        std.debug.print("   Task {d}: {s} ({s})\n", .{
            i,
            task.name,
            @tagName(task.task_type),
        });
    }

    // Disable a task
    scheduler.setTaskEnabled(0, false);
    std.debug.print("\n   Disabled task 0\n", .{});

    // Re-enable
    scheduler.setTaskEnabled(0, true);
    std.debug.print("   Re-enabled task 0\n\n", .{});

    // Example 5: Scheduler presets
    std.debug.print("5. Scheduler Presets\n", .{});
    std.debug.print("   ------------------\n", .{});

    const daily_cleanup = logly.SchedulerPresets.dailyCleanup("logs", 30);
    std.debug.print("   Daily cleanup config:\n", .{});
    std.debug.print("     Path: {s}\n", .{daily_cleanup.path orelse "none"});
    std.debug.print("     Max age: {d} days\n", .{daily_cleanup.max_age_seconds / (24 * 60 * 60)});
    std.debug.print("     Pattern: {s}\n\n", .{daily_cleanup.file_pattern orelse "*"});

    // Example 6: Statistics
    std.debug.print("6. Scheduler Statistics\n", .{});
    std.debug.print("   ---------------------\n", .{});

    const stats = scheduler.getStats();
    std.debug.print("   Tasks executed: {d}\n", .{stats.tasks_executed});
    std.debug.print("   Tasks failed: {d}\n", .{stats.tasks_failed});
    std.debug.print("   Files cleaned: {d}\n", .{stats.files_cleaned});
    std.debug.print("   Bytes freed: {d}\n\n", .{stats.bytes_freed});

    std.debug.print("=== Scheduler Example Complete ===\n", .{});
}
