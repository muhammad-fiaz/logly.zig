const std = @import("std");
const logly = @import("logly");

const Scheduler = logly.Scheduler;
const SchedulerPresets = logly.SchedulerPresets;

/// Custom task callback for demonstration.
fn customMetricsTask(task: *Scheduler.ScheduledTask) anyerror!void {
    std.debug.print("  [METRICS] Custom metrics task: {s} (run #{d})\n", .{ task.name, task.run_count + 1 });
}

/// Demonstrates the scheduler with real task implementations.
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n", .{});
    std.debug.print("========================================\n", .{});
    std.debug.print("  Logly Scheduler Demo - Automated Tasks\n", .{});
    std.debug.print("========================================\n\n", .{});

    // Create logs directory for testing
    std.fs.cwd().makePath("logs_scheduler_test") catch {};

    // Create some test log files
    std.debug.print("--- Creating Test Log Files ---\n", .{});
    for (0..5) |i| {
        const filename = try std.fmt.allocPrint(allocator, "logs_scheduler_test/app_{d}.log", .{i});
        defer allocator.free(filename);

        const file = try std.fs.cwd().createFile(filename, .{});
        defer file.close();

        // Write some log content
        const content = try std.fmt.allocPrint(allocator, "[{d}] Log entry {d}: Application running smoothly\n", .{ std.time.timestamp(), i });
        defer allocator.free(content);

        // Write it multiple times to make the file larger
        for (0..100) |_| {
            try file.writeAll(content);
        }

        std.debug.print("  Created: {s} ({d} bytes)\n", .{ filename, content.len * 100 });
    }

    // Initialize scheduler
    std.debug.print("\n--- Initializing Scheduler ---\n", .{});
    const scheduler = try Scheduler.init(allocator);
    defer scheduler.deinit();

    // Add various tasks

    // 1. Cleanup task - runs every 2 seconds for demo
    _ = try scheduler.addTask(
        "cleanup-old-logs",
        .cleanup,
        .{ .interval = 2000 }, // Every 2 seconds
        .{
            .path = "logs_scheduler_test",
            .max_age_seconds = 1, // Very short for demo
            .file_pattern = "*.log",
            .max_files = 3, // Keep only 3 newest
        },
    );
    std.debug.print("  + Added cleanup task (every 2s, max 3 files)\n", .{});

    // 2. Compression task - runs every 3 seconds for demo
    _ = try scheduler.addTask(
        "compress-logs",
        .compression,
        .{ .interval = 3000 }, // Every 3 seconds
        .{
            .path = "logs_scheduler_test",
            .file_pattern = "*.log",
        },
    );
    std.debug.print("  + Added compression task (every 3s)\n", .{});

    // 3. Health check task - runs every second
    _ = try scheduler.addTask(
        "health-check",
        .health_check,
        .{ .interval = 1000 },
        .{},
    );
    std.debug.print("  + Added health check task (every 1s)\n", .{});

    // 4. Custom metrics task
    _ = try scheduler.addCustomTask(
        "custom-metrics",
        .{ .interval = 1500 },
        customMetricsTask,
    );
    std.debug.print("  + Added custom metrics task (every 1.5s)\n", .{});

    // Display task list
    std.debug.print("\n--- Scheduled Tasks ---\n", .{});
    for (scheduler.getTasks(), 0..) |task, i| {
        std.debug.print("  [{d}] {s} - Type: {s}, Enabled: {}\n", .{
            i,
            task.name,
            @tagName(task.task_type),
            task.enabled,
        });
    }

    // Run scheduler manually (for demo purposes)
    std.debug.print("\n--- Running Scheduler Manually ---\n", .{});
    std.debug.print("  (Running 5 iterations with 1 second delay)\n\n", .{});

    for (0..5) |iteration| {
        std.debug.print("-- Iteration {d} --\n", .{iteration + 1});

        // Manually trigger pending tasks
        scheduler.runPending();

        // Show current stats
        const stats = scheduler.getStats();
        std.debug.print("  Stats: {d} tasks executed, {d} failed, {d} files cleaned, {d} bytes freed\n", .{
            stats.tasks_executed,
            stats.tasks_failed,
            stats.files_cleaned,
            stats.bytes_freed,
        });

        // Check health
        const health = scheduler.getHealthStatus();
        std.debug.print("  Health: {s}\n", .{if (health.healthy) "OK" else "NOT OK"});

        std.Thread.sleep(1 * std.time.ns_per_s);
    }

    // Show final stats
    std.debug.print("\n--- Final Statistics ---\n", .{});
    const final_stats = scheduler.getStats();
    std.debug.print("  Total tasks executed:  {d}\n", .{final_stats.tasks_executed});
    std.debug.print("  Total tasks failed:    {d}\n", .{final_stats.tasks_failed});
    std.debug.print("  Total files cleaned:   {d}\n", .{final_stats.files_cleaned});
    std.debug.print("  Total bytes freed:     {d}\n", .{final_stats.bytes_freed});

    // Show remaining files in test directory
    std.debug.print("\n--- Remaining Test Files ---\n", .{});
    var dir = std.fs.cwd().openDir("logs_scheduler_test", .{ .iterate = true }) catch {
        std.debug.print("  (directory cleaned up or not accessible)\n", .{});
        return;
    };
    defer dir.close();

    var file_count: usize = 0;
    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        std.debug.print("  - {s}\n", .{entry.name});
        file_count += 1;
    }
    if (file_count == 0) {
        std.debug.print("  (no files remaining)\n", .{});
    }

    // Cleanup test directory
    std.debug.print("\n--- Cleanup ---\n", .{});
    std.fs.cwd().deleteTree("logs_scheduler_test") catch {};
    std.debug.print("  Removed test directory\n", .{});

    std.debug.print("\n========================================\n", .{});
    std.debug.print("  Scheduler Demo Complete!\n", .{});
    std.debug.print("========================================\n", .{});
}
