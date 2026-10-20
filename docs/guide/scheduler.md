---
title: Logging Scheduler
description: Automate log maintenance with the Logly.zig scheduler. Schedule cleanup, compression, rotation, and custom tasks.
head:
  - - meta
    - name: keywords
      content: scheduler, log maintenance, automatic cleanup, log compression, rotation task, health check, background tasks
  - - meta
    - property: og:title
      content: Logging Scheduler | Logly.zig
  - - meta
    - property: og:image
      content: https://muhammad-fiaz.github.io/logly.zig/cover.png
---

# Scheduler Guide

The scheduler runs log-maintenance tasks on interval, daily, cron-style, or one-shot schedules. Typical tasks remove old files, compress logs, rotate files, flush sinks, and run application-defined callbacks.

## Configuration

The centralized `Config.SchedulerConfig` stores defaults used by `Logger` and task presets:

```zig
var config = logly.Config.default();
config.scheduler = .{
    .enabled = true,
    .cleanupMaxAgeDays = 7,
    .maxFiles = 10,
    .compressBeforeCleanup = true,
    .filePattern = "*.log",
};
```

`Config.default().withScheduler(...)` applies the same settings without mutating an existing configuration.

### SchedulerConfig fields

| Field | Type | Default | Purpose |
|---|---|---|---|
| `enabled` | `bool` | `false` | Enables scheduler integration |
| `cleanupMaxAgeDays` | `u64` | `7` | Default cleanup age |
| `maxFiles` | `?usize` | `null` | Maximum retained files |
| `compressBeforeCleanup` | `bool` | `false` | Compress before deletion |
| `filePattern` | `[]const u8` | `"*.log"` | Default file pattern |
| `archiveRootDir` | `?[]const u8` | `null` | Archive destination root |
| `createDateSubdirs` | `bool` | `false` | Create `YYYY/MM/DD` archive paths |
| `compressionAlgorithm` | `CompressionAlgorithm` | `.gzip` | Archive compression format |
| `compressionLevel` | `CompressionLevel` | `.default` | Compression level |
| `keepOriginals` | `bool` | `false` | Retain originals after compression |
| `archiveFilePrefix` | `?[]const u8` | `null` | Archive filename prefix |
| `archiveFileSuffix` | `?[]const u8` | `null` | Archive filename suffix |
| `preserveDirStructure` | `bool` | `true` | Mirror source paths under the archive root |
| `cleanEmptyDirs` | `bool` | `false` | Remove empty directories after cleanup |
| `minAgeDaysForCompression` | `u64` | `1` | Minimum age before compression |
| `maxConcurrentCompressions` | `usize` | `2` | Concurrent compression limit |
| `io` | `?std.Io` | `null` | Explicit I/O handle |

## Quick Start

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const scheduler = try logly.Scheduler.init(allocator);
    defer scheduler.deinit();

    _ = try scheduler.addTask(
        "daily_cleanup",
        .cleanup,
        .{ .daily = .{ .hour = 2, .minute = 0 } },
        .{
            .path = "logs",
            .maxAgeSeconds = 30 * 24 * 60 * 60,
            .filePattern = "*.log",
        },
    );

    try scheduler.start();
    defer scheduler.stop();
}
```

## Schedule Types

`logly.Scheduler.Schedule` is a tagged union. All interval values are milliseconds.

### Interval

```zig
.schedule = .{ .interval = 60 * 1000 },      // every minute
.schedule = .{ .interval = 5 * 60 * 1000 },  // every five minutes
.schedule = .{ .interval = 2 * 60 * 60 * 1000 } // every two hours
```

### Daily

```zig
.schedule = .{ .daily = .{ .hour = 2, .minute = 30 } },
```

### Cron-Style

Unset fields match any value. Supported fields are minute, hour, day of month, month, and day of week (`0` = Sunday).

```zig
// Sundays at 03:00
.schedule = .{ .cron = .{ .dayOfWeek = 0, .hour = 3, .minute = 0 } },

// First day of each month at midnight
.schedule = .{ .cron = .{ .dayOfMonth = 1, .hour = 0, .minute = 0 } },
```

### One-Shot

```zig
// Run once after a five-second delay
.schedule = .{ .once = 5000 },
```

## Adding Tasks

### Generic Tasks

```zig
const index = try scheduler.addTask(
    "log_cleanup",
    .cleanup,
    .{ .interval = 60 * 60 * 1000 },
    .{
        .path = "logs",
        .maxAgeSeconds = 7 * 24 * 60 * 60,
        .filePattern = "*.log",
        .maxFiles = 20,
        .compressBeforeDelete = true,
        .skipAlreadyCompressed = true,
    },
);
```

### Cleanup and Compression Helpers

```zig
_ = try scheduler.addCleanupTask(
    "log_cleanup",
    "logs",
    30,
    logly.SchedulerPresets.dailyAt(3, 0),
);

_ = try scheduler.addCompressionTask(
    "log_compression",
    "logs",
    logly.SchedulerPresets.hourlyCompression(),
);
```

### Custom Tasks

```zig
fn runMaintenance(_: *logly.Scheduler.ScheduledTask) anyerror!void {
    // Application-defined work.
}

_ = try scheduler.addCustomTask(
    "maintenance",
    .{ .interval = 15 * 60 * 1000 },
    runMaintenance,
);
```

Use `addCustomTaskWithConfig` when the task needs a `TaskConfig` with retry, dependency, or path settings.

### TaskConfig fields

| Field | Type | Default | Purpose |
|---|---|---|---|
| `path` | `?[]const u8` | `null` | Working directory |
| `maxAgeSeconds` | `u64` | scheduler default | Cleanup age threshold |
| `maxFiles` | `?usize` | `null` | Maximum files to retain |
| `maxTotalSize` | `?u64` | `null` | Maximum retained bytes |
| `minAgeSeconds` | `u64` | `0` | Minimum age before processing |
| `maxRetries` | `u32` | `0` | Retry attempts |
| `retryBackoffMs` | `u64` | `0` | Delay between retries |
| `filePattern` | `?[]const u8` | `null` | Glob pattern |
| `compressBeforeDelete` | `bool` | `false` | Compress then delete |
| `compressAndKeep` | `bool` | `false` | Compress and retain the original |
| `compressOnly` | `bool` | `false` | Compress without deleting |
| `skipAlreadyCompressed` | `bool` | `true` | Skip `.gz`, `.lgz`, `.zst` files |
| `recursive` | `bool` | `false` | Traverse subdirectories |
| `triggerDiskUsagePercent` | `?u8` | `null` | Run only above disk usage |
| `minFreeSpaceBytes` | `?u64` | `null` | Run only above free-space threshold |

## Presets

`logly.SchedulerPresets` provides schedule and task-config helpers:

| Preset | Return type |
|---|---|
| `dailyCleanup(path, maxAgeDays)` | `TaskConfig` |
| `weeklyCleanup()` | `Schedule` |
| `hourlyCompression()` | `Schedule` |
| `everyMinutes(n)` | `Schedule` |
| `dailyAt(hour, minute)` | `Schedule` |
| `dailyMidnight()` | `Schedule` |
| `dailyMaintenance()` | `Schedule` |
| `every30Minutes()` | `Schedule` |
| `every6Hours()` | `Schedule` |
| `every12Hours()` | `Schedule` |
| `weeklyCleanupConfig(path, maxAgeDays)` | `TaskConfig` |
| `compressThenDelete(path, minAgeDays)` | `TaskConfig` |
| `compressAndKeep(path, minAgeDays)` | `TaskConfig` |
| `compressOnly(path, minAgeDays)` | `TaskConfig` |
| `archiveOldLogs(path, compressAfterDays, deleteAfterDays)` | `TaskConfig` |
| `aggressiveCleanup(path, maxAgeDays, maxFiles)` | `TaskConfig` |
| `createScheduledSink(filePath, rotation)` | `SinkConfig` |

## Task Management

```zig
const index = scheduler.taskIndexByName("log_cleanup").?;

scheduler.setTaskEnabled(index, false);
scheduler.setTaskEnabledByName("log_cleanup", true);

if (scheduler.setTaskSchedule(index, .{ .interval = 30 * 60 * 1000 })) {
    _ = scheduler.rescheduleNow(index);
}

try scheduler.runNow(index);
_ = try scheduler.runNowByName("log_compression");

scheduler.removeTask(index);
_ = scheduler.removeTaskByName("log_compression");
```

Inspection methods include `getTasks()`, `taskCount()`, `hasTaskNamed()`, `enabledTaskCount()`, `runningTaskCount()`, `readyTaskCount()`, `getTaskSnapshot()`, `getTaskSnapshotByName()`, and `nextRunInMsByName()`.

Call `try scheduler.validateDependencies()` after configuring dependencies to reject missing names and cycles before the scheduler starts.

## Callbacks

```zig
fn onStarted(name: []const u8, index: u64) void {
    std.debug.print("task {s} ({d}) started\n", .{ name, index });
}

fn onCompleted(name: []const u8, elapsed_ms: u64) void {
    std.debug.print("task {s} completed in {d}ms\n", .{ name, elapsed_ms });
}

fn onFailed(name: []const u8, message: []const u8) void {
    std.debug.print("task {s} failed: {s}\n", .{ name, message });
}

scheduler.setTaskStartedCallback(onStarted);
scheduler.setTaskCompletedCallback(onCompleted);
scheduler.setTaskErrorCallback(onFailed);
```

Additional hooks: `setScheduleTickCallback`, `setHealthCheckCallback`, `setHealthCallback`, and `setMetricsCallback`.

## Statistics

```zig
const stats = scheduler.getStats();

std.debug.print("executed: {d}\n", .{stats.getExecuted()});
std.debug.print("failed: {d}\n", .{stats.getFailed()});
std.debug.print("cleaned: {d}\n", .{stats.getFilesCleaned()});
std.debug.print("freed: {d} bytes\n", .{stats.getBytesFreed()});
std.debug.print("success rate: {d:.2}%\n", .{stats.successRate() * 100});
```

`resetStats()` clears counters. `pause()` and `unpause()` control scheduling without removing tasks; read the `isPaused` atomic field to check the current state.

## Operations

- Keep task callbacks short and non-blocking; long-running work delays other tasks.
- Use dependencies (`setTaskDependency` and `validateDependencies`) instead of fixed ordering assumptions.
- Enable compression only when the additional CPU and I/O cost is acceptable for your workload.
- Configure retries per task with `setTaskRetryPolicy`; failed tasks remain registered.
- Shut down with `stop()` before `deinit()` to join the scheduling thread.

## See Also

- [Scheduler API](/api/scheduler)
- [Compression](/guide/compression)
- [Rotation](/guide/rotation)
