# Scheduler Example

This example demonstrates automatic log maintenance using Logly's scheduler.

## Centralized Configuration

```zig
const logly = @import("logly");

var config = logly.Config.default();
config.scheduler = logly.SchedulerConfig{
    .max_tasks = 512,
    .timer_resolution_ms = 10,
    .thread_pool_size = 4,
    .enable_persistence = true,
    .persistence_path = "scheduler.state",
};

// Or use helper method
var config2 = logly.Config.default().withScheduler(.{
    .max_tasks = 256,
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
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create scheduler with centralized config
    var scheduler = try logly.Scheduler.init(allocator, .{
        .check_interval_ms = 60000,
        .auto_start = false,
    });
    defer scheduler.deinit();

    // Add daily cleanup task
    _ = try scheduler.addTask(.{
        .name = "log_cleanup",
        .task_type = .cleanup,
        .schedule = logly.Schedule.daily(2, 30),
        .config = .{ .cleanup = .{
            .path = "logs",
            .max_age_days = 30,
            .pattern = "*.log",
        }},
    });

    // Add hourly compression task
    _ = try scheduler.addTask(.{
        .name = "log_compression",
        .task_type = .compression,
        .schedule = logly.Schedule.everyHours(1),
        .config = .{ .compression = .{
            .path = "logs",
            .min_age_days = 1,
        }},
    });

    // Start scheduler
    try scheduler.start();
    defer scheduler.stop();

    // List tasks
    const tasks = scheduler.listTasks();
    for (tasks, 0..) |task, i| {
        std.debug.print("Task {d}: {s} ({s})\n", .{
            i,
            task.name,
            @tagName(task.task_type),
        });
    }
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
.task_type = .cleanup,      // Remove old logs
.task_type = .compression,  // Compress logs
.task_type = .rotation,     // Force rotation
.task_type = .custom,       // Custom function
.task_type = .flush,        // Flush buffers
.task_type = .health_check, // Health check
```

### Cleanup Configuration

```zig
.config = .{ .cleanup = .{
    .path = "logs",
    .max_age_days = 30,
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
    .min_age_days = 1,
    .delete_originals = true,
}},
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
    stats.tasks_executed.load(.monotonic),
});
std.debug.print("Files cleaned: {d}\n", .{
    stats.files_cleaned.load(.monotonic),
});
std.debug.print("Bytes freed: {d}\n", .{
    stats.bytes_freed.load(.monotonic),
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

