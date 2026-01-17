const std = @import("std");
const logly = @import("logly");

const Scheduler = logly.Scheduler;
const SchedulerPresets = logly.SchedulerPresets;

/// Custom task callback for demonstration.
fn customMetricsTask(task: *Scheduler.ScheduledTask) anyerror!void {
    std.debug.print("  [METRICS] Custom metrics task: {s} (run #{d})\n", .{ task.name, task.run_count + 1 });
}

/// Demonstrates the scheduler with comprehensive task implementations and presets.
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n", .{});
    std.debug.print("Logly Scheduler Demo v0.1.5\n", .{});
    std.debug.print("Automated Tasks with Compression Integration\n\n", .{});

    // Create logs directory for testing
    std.fs.cwd().makePath("logs_scheduler_test") catch {};

    // Create some test log files
    std.debug.print("Creating Test Log Files\n", .{});
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
    std.debug.print("\nInitializing Scheduler\n", .{});
    const scheduler = try Scheduler.init(allocator);
    defer scheduler.deinit();

    // Add various tasks

    // 1. Cleanup task using daily cleanup preset
    _ = try scheduler.addTask(
        "cleanup-old-logs",
        .cleanup,
        .{ .interval = 2000 }, // Every 2 seconds for demo
        SchedulerPresets.dailyCleanup("logs_scheduler_test", 1), // Keep files 1 day old
    );
    std.debug.print("  + Added cleanup task (every 2s, using dailyCleanup preset)\n", .{});

    // 2. Compression task using compress-only preset
    _ = try scheduler.addTask(
        "compress-logs",
        .compression,
        .{ .interval = 3000 }, // Every 3 seconds for demo
        SchedulerPresets.compressOnly("logs_scheduler_test", 0), // Compress immediately
    );
    std.debug.print("  + Added compression task (every 3s, using compressOnly preset)\n", .{});

    // 3. Archive task using compress-then-delete preset
    _ = try scheduler.addTask(
        "archive-logs",
        .cleanup,
        .{ .interval = 4000 }, // Every 4 seconds for demo
        SchedulerPresets.compressThenDelete("logs_scheduler_test", 0), // Compress before delete
    );
    std.debug.print("  + Added archive task (every 4s, using compressThenDelete preset)\n", .{});

    // 4. Health check task
    _ = try scheduler.addTask(
        "health-check",
        .health_check,
        SchedulerPresets.healthCheckSchedule(), // Every 5 minutes (overridden for demo)
        .{},
    );
    std.debug.print("  + Added health check task (using healthCheckSchedule preset)\n", .{});

    // 5. Custom metrics task
    _ = try scheduler.addCustomTask(
        "custom-metrics",
        SchedulerPresets.metricsSchedule(), // Every minute (overridden for demo)
        customMetricsTask,
    );
    std.debug.print("  + Added custom metrics task (using metricsSchedule preset)\n", .{});

    // Display available schedule presets
    std.debug.print("\nAvailable Schedule Presets:\n", .{});
    std.debug.print("  - dailyCleanup(path, max_age_days)\n", .{});
    std.debug.print("  - weeklyCleanup()\n", .{});
    std.debug.print("  - hourlyCompression()\n", .{});
    std.debug.print("  - everyMinutes(n)\n", .{});
    std.debug.print("  - every15Minutes()\n", .{});
    std.debug.print("  - every30Minutes()\n", .{});
    std.debug.print("  - every6Hours()\n", .{});
    std.debug.print("  - every12Hours()\n", .{});
    std.debug.print("  - dailyAt(hour, minute)\n", .{});
    std.debug.print("  - dailyMidnight()\n", .{});
    std.debug.print("  - dailyMaintenance()\n", .{});
    std.debug.print("  - onceAfter(seconds)\n", .{});
    std.debug.print("  - healthCheckSchedule()\n", .{});
    std.debug.print("  - metricsSchedule()\n", .{});

    // Display available config presets
    std.debug.print("\nAvailable Config Presets:\n", .{});
    std.debug.print("  - compressThenDelete(path, min_age_days)\n", .{});
    std.debug.print("  - compressAndKeep(path, min_age_days)\n", .{});
    std.debug.print("  - compressOnly(path, min_age_days)\n", .{});
    std.debug.print("  - archiveOldLogs(path, compress_days, delete_days)\n", .{});
    std.debug.print("  - aggressiveCleanup(path, max_age_days, max_files)\n", .{});
    std.debug.print("  - hourlyArchive(path)\n", .{});
    std.debug.print("  - compressOnRotation(path)\n", .{});
    std.debug.print("  - sizeBasedCompression(path, max_total_bytes)\n", .{});
    std.debug.print("  - diskUsageTriggered(path, disk_usage_percent)\n", .{});
    std.debug.print("  - lowDiskSpaceTriggered(path, min_free_bytes)\n", .{});
    std.debug.print("  - recursiveCompression(path, min_age_days)\n", .{});

    // Display task list
    std.debug.print("\nScheduled Tasks\n", .{});
    for (scheduler.getTasks(), 0..) |task, i| {
        std.debug.print("  [{d}] {s} - Type: {s}, Enabled: {}\n", .{
            i,
            task.name,
            @tagName(task.task_type),
            task.enabled,
        });
    }

    // Run scheduler manually (for demo purposes)
    std.debug.print("\nRunning Scheduler Manually\n", .{});
    std.debug.print("  (Running 5 iterations with 1 second delay)\n\n", .{});

    for (0..5) |iteration| {
        std.debug.print("Iteration {d}\n", .{iteration + 1});

        // Manually trigger pending tasks
        scheduler.runPending();

        // Show current stats
        const stats = scheduler.getStats();
        std.debug.print("  Tasks: {d} executed, {d} failed\n", .{
            stats.getExecuted(),
            stats.getFailed(),
        });
        std.debug.print("  Files: {d} cleaned, {d} compressed\n", .{
            stats.getFilesCleaned(),
            stats.getFilesCompressed(),
        });
        std.debug.print("  Bytes: {d} freed, {d} saved by compression\n", .{
            stats.getBytesFreed(),
            stats.getBytesSaved(),
        });

        // Check health
        const health = scheduler.getHealthStatus();
        std.debug.print("  Health: {s}\n", .{if (health.healthy) "OK" else "NOT OK"});

        std.Thread.sleep(1 * std.time.ns_per_s);
    }

    // Show final stats
    std.debug.print("\nFinal Statistics\n", .{});
    const final_stats = scheduler.getStats();
    std.debug.print("  Tasks executed:     {d}\n", .{final_stats.getExecuted()});
    std.debug.print("  Tasks failed:       {d}\n", .{final_stats.getFailed()});
    std.debug.print("  Success rate:       {d:.1}%\n", .{final_stats.successRate() * 100});
    std.debug.print("  Files cleaned:      {d}\n", .{final_stats.getFilesCleaned()});
    std.debug.print("  Files compressed:   {d}\n", .{final_stats.getFilesCompressed()});
    std.debug.print("  Bytes freed:        {d}\n", .{final_stats.getBytesFreed()});
    std.debug.print("  Bytes saved:        {d}\n", .{final_stats.getBytesSaved()});
    std.debug.print("  Compression ratio:  {d:.1}%\n", .{final_stats.compressionRatio() * 100});

    // Show remaining files in test directory
    std.debug.print("\nRemaining Test Files\n", .{});
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
    std.debug.print("\nCleanup\n", .{});
    std.fs.cwd().deleteTree("logs_scheduler_test") catch {};
    std.debug.print("  Removed test directory\n", .{});

    std.debug.print("\nScheduler Demo Complete!\n", .{});
}
