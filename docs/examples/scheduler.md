---
title: Scheduler Example
description: Example of automatic log maintenance with Logly.zig scheduler. Configure cleanup, compression, rotation, cron expressions, and custom periodic tasks.
head:
  - - meta
    - name: keywords
      content: scheduler example, automatic cleanup, log maintenance, cron scheduler, periodic tasks, log rotation
  - - meta
    - property: og:title
      content: Scheduler Example | Logly.zig
---

# Scheduler Example

This example demonstrates automatic log maintenance using Logly's scheduler.

## Centralized Configuration

```zig
const logly = @import("logly");

var config = logly.Config.default();
config.scheduler = logly.SchedulerConfig{
    .maxTasks = 512,
    .timer_resolution_ms = 10,
    .thread_pool_size = 4,
    .enable_persistence = true,
    .persistence_path = "scheduler.state",
};

// Or use helper method
var config2 = logly.Config.default().withScheduler(.{
    .maxTasks = 256,
    .timer_resolution_ms = 50,
});
```

## Source Code

```zig
//! Scheduler Example
//!
//! Demonstrates scheduled log maintenance tasks.

const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 1. Basic Scheduler Setup
    const scheduler = try logly.Scheduler.init(allocator);
    defer scheduler.deinit();

    // 2. Add interval-based cleanup task
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

    // 3. Add compression task with cron-like preset
    const compIdx = try scheduler.addTask(
        "log_compression",
        .compression,
        logly.SchedulerPresets.dailyAt(3, 0),
        .{
            .path = "logs",
            .filePattern = "*.log",
        },
    );
    _ = compIdx;

    // 4. Add one-shot custom task
    const OneShotTask = struct {
        fn execute(_: *logly.Scheduler.ScheduledTask) anyerror!void {
            std.debug.print("Maintenance task executed!\n", .{});
        }
    };
    _ = try scheduler.addCustomTask("oneshot_task", .{ .interval = 1 }, OneShotTask.execute);

    // 5. Task management and control
    scheduler.setTaskEnabled(cleanupIdx, false); // Cancel / disable
    scheduler.setTaskEnabled(cleanupIdx, true);  // Re-enable

    // 6. Inspect registered tasks
    const tasks = scheduler.getTasks();
    for (tasks, 0..) |task, i| {
        std.debug.print("Task {d}: '{s}' type={s} enabled={s}\n", .{
            i,
            task.name,
            @tagName(task.taskType),
            if (task.enabled) "yes" else "no",
        });
    }

    // 7. Check statistics
    const stats = scheduler.getStats();
    std.debug.print("Tasks executed: {d}, Files cleaned: {d}\n", .{
        stats.getExecuted(),
        stats.getFilesCleaned(),
    });
}
```

## Running the Example

```bash
zig build run-scheduler-demo
```

## Expected Output

```
Task 0: log_cleanup (cleanup)
Task 1: log_compression (compression)
```

## Key Concepts

### Schedule Types

```zig
// Fixed interval
.schedule = logly.Schedule.interval(60), // Every 60 seconds

// Daily at specific time
.schedule = logly.Schedule.daily(2, 30), // 2:30 AM

// Weekly
.schedule = logly.Schedule.weekly(0, 3, 0), // Sunday 3 AM

// Convenience methods
.schedule = logly.Schedule.everyMinutes(5),
.schedule = logly.Schedule.everyHours(1),
```

### Task Types

```zig
.taskType = .cleanup,      // Remove old logs
.taskType = .compression,  // Compress logs
.taskType = .rotation,     // Force rotation
.taskType = .custom,       // Custom function
.taskType = .flush,        // Flush buffers
.taskType = .healthCheck, // Health check
```

### Cleanup Configuration

```zig
.config = .{ .cleanup = .{
    .path = "logs",
    .maxAgeDays = 30,
    .pattern = "*.log",
    .include_compressed = true,
    .min_files_to_keep = 5,
}},
```

### Compression Configuration

```zig
.config = .{ .compression = .{
    .path = "logs",
    .pattern = "*.log",
    .minAgeDays = 1,
    .delete_originals = true,
}},
```

### Compression Modes

```zig
// Mode 1: Compress then delete original
.config = .{
    .path = "logs",
    .filePattern = "*.log",
    .compressBeforeDelete = true,
    .skipAlreadyCompressed = true,
},

// Mode 2: Compress and keep both versions
.config = .{
    .path = "logs",
    .filePattern = "*.log",
    .compressAndKeep = true,
    .skipAlreadyCompressed = true,
},

// Mode 3: Only compress, never delete
.config = .{
    .path = "logs",
    .filePattern = "*.log",
    .compressOnly = true,
    .skipAlreadyCompressed = true,
},
```

### Using Presets

```zig
// Daily cleanup at 2 AM
 _ = try scheduler.addTask(
    logly.SchedulerPresets.dailyCleanup("logs"),
);

// Hourly compression
 _ = try scheduler.addTask(
    logly.SchedulerPresets.hourlyCompression("logs"),
);

// Weekly deep clean
 _ = try scheduler.addTask(
    logly.SchedulerPresets.weeklyDeepClean("logs"),
);
```

### Compression Presets

```zig
const Presets = logly.SchedulerPresets;

// Compress files older than 7 days, then delete originals
const archive = Presets.compressThenDelete("logs", 7);

// Compress files older than 3 days, keep both versions
const backup = Presets.compressAndKeep("logs", 3);

// Only compress, never delete anything
const pure_archive = Presets.compressOnly("logs", 1);

// Archive: compress after 7 days, delete after 30 days
const tiered = Presets.archiveOldLogs("logs", 7, 30);

// Aggressive: compress & delete, max 100 files
const aggressive = Presets.aggressiveCleanup("logs", 30, 100);
```

### Task Management

```zig
// Disable a task
scheduler.disableTask(0);

// Enable a task
scheduler.enableTask(0);

// Run immediately
try scheduler.runTaskNow(0);

// Remove a task
try scheduler.removeTask(0);
```

### Statistics

```zig
const stats = scheduler.getStats();
std.debug.print("Tasks executed: {d}\n", .{
    stats.getExecuted(),
});
std.debug.print("Files cleaned: {d}\n", .{
    stats.getFilesCleaned(),
});
std.debug.print("Bytes freed: {d}\n", .{
    stats.getBytesFreed(),
});
```

## See Also

- [Scheduler API](../api/scheduler.md)
- [Scheduler Guide](../guide/scheduler.md)
- [Compression Example](compression.md)

## New Presets (v0.0.9)

```zig
const SchedulerPresets = logly.SchedulerPresets;

// Every N minutes presets
var every_5 = SchedulerPresets.every5Minutes();
var every_15 = SchedulerPresets.every15Minutes();
var every_30 = SchedulerPresets.every30Minutes();

// Hourly presets
var every_hour = SchedulerPresets.everyHour();
var every_6 = SchedulerPresets.every6Hours();
var every_12 = SchedulerPresets.every12Hours();

// Daily presets
var midnight = SchedulerPresets.dailyMidnight();
var maintenance = SchedulerPresets.dailyMaintenance();  // 2 AM
var at_time = SchedulerPresets.dailyAt(9, 30);  // 9:30 AM

// Task configs
var cleanup = SchedulerPresets.dailyCleanup("logs", 30);
var compress = SchedulerPresets.hourlyCompression("logs");
var weekly = SchedulerPresets.weeklyCleanupConfig("logs", 90);
```

## Aliases

| Alias | Method |
|-------|--------|
| `begin` | `start` |
| `end` | `stop` |
| `halt` | `stop` |
| `statistics` | `getStats` |

