---
title: Scheduler Example
description: Example of automatic log maintenance with the Logly.zig scheduler. Configure cleanup, compression, rotation, cron expressions, and custom tasks.
head:
  - - meta
    - name: keywords
      content: scheduler example, automatic cleanup, log maintenance, cron scheduler, periodic tasks, log rotation
  - - meta
    - property: og:title
      content: Scheduler Example | Logly.zig
---

# Scheduler Example

This example registers cleanup, compression, and custom tasks with the Logly scheduler, then inspects task state and statistics.

## Configuration

`SchedulerConfig` holds defaults used by the logger and by task presets:

```zig
const logly = @import("logly");

var config = logly.Config.default();
config.scheduler = .{
    .enabled = true,
    .cleanupMaxAgeDays = 7,
    .maxFiles = 10,
    .compressBeforeCleanup = true,
    .filePattern = "*.log",
};
```

The same settings can be applied with `logly.Config.default().withScheduler(...)`.

## Core Usage

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const scheduler = try logly.Scheduler.init(allocator);
    defer scheduler.deinit();

    const cleanup_index = try scheduler.addTask(
        "log_cleanup",
        .cleanup,
        .{ .interval = 60 * 60 * 1000 },
        .{
            .path = "logs",
            .maxAgeSeconds = 7 * 24 * 60 * 60,
            .filePattern = "*.log",
        },
    );

    _ = try scheduler.addTask(
        "log_compression",
        .compression,
        logly.SchedulerPresets.dailyAt(3, 0),
        .{
            .path = "logs",
            .filePattern = "*.log",
        },
    );

    const Maintenance = struct {
        fn run(_: *logly.Scheduler.ScheduledTask) anyerror!void {
            // Application-defined work.
        }
    };

    _ = try scheduler.addCustomTask(
        "oneshot_maintenance",
        .{ .once = 1 },
        Maintenance.run,
    );

    scheduler.setTaskEnabled(cleanup_index, false);
    scheduler.setTaskEnabled(cleanup_index, true);

    for (scheduler.getTasks(), 0..) |task, index| {
        std.debug.print("task {d}: {s} ({s})\n", .{
            index,
            task.name,
            @tagName(task.taskType),
        });
    }

    const stats = scheduler.getStats();
    std.debug.print("executed: {d}, failed: {d}\n", .{
        stats.getExecuted(),
        stats.getFailed(),
    });
}
```

## Running the Example

```bash
zig build run-scheduler
```

## Key Concepts

### Schedule Types

```zig
// Fixed interval, in milliseconds
.schedule = .{ .interval = 60 * 1000 },

// Daily at a specific local time
.schedule = .{ .daily = .{ .hour = 2, .minute = 30 } },

// Cron-style: Sunday at 03:00
.schedule = .{ .cron = .{ .dayOfWeek = 0, .hour = 3, .minute = 0 } },

// One-shot after a delay, in milliseconds
.schedule = .{ .once = 5000 },
```

### Task Types

`TaskType` values are `cleanup`, `compression`, `rotation`, `flush`, `custom`, `healthCheck`, and `metricsSnapshot`.

### TaskConfig

`TaskConfig` is a flat struct shared by all task types:

```zig
_ = try scheduler.addTask(
    "archive_logs",
    .compression,
    logly.SchedulerPresets.dailyAt(4, 0),
    .{
        .path = "logs",
        .filePattern = "*.log",
        .minAgeSeconds = 24 * 60 * 60,
        .compressAndKeep = true,
        .skipAlreadyCompressed = true,
    },
);
```

Compression modes:

```zig
// Compress and delete the original
.{ .path = "logs", .filePattern = "*.log", .compressBeforeDelete = true },

// Compress and keep both files
.{ .path = "logs", .filePattern = "*.log", .compressAndKeep = true },

// Compress only, never delete
.{ .path = "logs", .filePattern = "*.log", .compressOnly = true },
```

### Presets

`SchedulerPresets` returns either a `Schedule` or a `TaskConfig`, depending on the helper:

```zig
// Schedules
const daily = logly.SchedulerPresets.dailyAt(2, 0);
const hourly = logly.SchedulerPresets.hourlyCompression();
const weekly = logly.SchedulerPresets.weeklyCleanup();
const every_five = logly.SchedulerPresets.everyMinutes(5);

// Task configurations
const cleanup = logly.SchedulerPresets.dailyCleanup("logs", 30);
const archive = logly.SchedulerPresets.compressThenDelete("logs", 7);
const backup = logly.SchedulerPresets.compressAndKeep("logs", 3);
const pure_archive = logly.SchedulerPresets.compressOnly("logs", 1);
const tiered = logly.SchedulerPresets.archiveOldLogs("logs", 7, 30);
const aggressive = logly.SchedulerPresets.aggressiveCleanup("logs", 30, 100);
```

### Task Management

```zig
scheduler.setTaskEnabled(index, false);
scheduler.setTaskEnabledByName("log_cleanup", true);

try scheduler.runNow(index);
_ = try scheduler.runNowByName("log_cleanup");

scheduler.removeTask(index);
_ = scheduler.removeTaskByName("log_cleanup");

_ = scheduler.setTaskSchedule(index, .{ .interval = 30 * 60 * 1000 });
_ = scheduler.rescheduleNow(index);
```

### Statistics

```zig
const stats = scheduler.getStats();

std.debug.print("executed: {d}\n", .{stats.getExecuted()});
std.debug.print("failed: {d}\n", .{stats.getFailed()});
std.debug.print("files cleaned: {d}\n", .{stats.getFilesCleaned()});
std.debug.print("bytes freed: {d}\n", .{stats.getBytesFreed()});
std.debug.print("bytes saved: {d}\n", .{stats.getBytesSaved()});
```

## See Also

- [Scheduler API](/api/scheduler)
- [Scheduler Guide](/guide/scheduler)
- [Compression Example](/examples/compression)
