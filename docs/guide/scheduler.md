# Scheduler Guide

This guide covers automatic log maintenance in Logly using the scheduler, including cleanup, compression, rotation tasks, and custom scheduled operations.

## Overview

The scheduler module provides automatic log maintenance by running tasks on configurable schedules. This includes cleaning up old logs, compressing files, rotating logs, and running custom maintenance tasks.

## Logger Configuration

Enable scheduler through the Config struct:

```zig
const logly = @import("logly");

var config = logly.Config.default();
config.scheduler = .{
    .enabled = true,              // Enable scheduler
    .cleanup_max_age_days = 7,    // Delete logs older than 7 days
    .max_files = 10,              // Keep max 10 rotated files
    .compress_before_cleanup = true, // Compress before deleting
    .file_pattern = "*.log",      // Pattern for log files
};

// Or use helper method
var config2 = logly.Config.default().withScheduler(.{ .cleanup_max_age_days = 7 });
```

## Quick Start

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create scheduler
    var scheduler = try logly.Scheduler.init(allocator);
    defer scheduler.deinit();

    // Add a cleanup task
    _ = try scheduler.addTask(.{
        .name = "daily_cleanup",
        .task_type = .cleanup,
        .schedule = .{ .daily = .{ .hour = 2, .minute = 0 } },
        .config = .{
            .path = "logs",
            .max_age_seconds = 30 * 24 * 60 * 60, // 30 days
        },
    });

    // Start scheduler
    try scheduler.start();
    defer scheduler.stop();
}
```

## Schedule Types

### Interval

Run at fixed intervals:

```zig
// Every 60 seconds
.schedule = .{ .interval = 60 * 1000 },

// Every 5 minutes  
.schedule = .{ .interval = 5 * 60 * 1000 },

// Every 2 hours
.schedule = .{ .interval = 2 * 60 * 60 * 1000 },
```

### Daily

Run once per day at a specific time:

```zig
// At 2:30 AM
.schedule = logly.Schedule.daily(2, 30),

// At midnight
.schedule = logly.Schedule.daily(0, 0),

// At 6 PM
.schedule = logly.Schedule.daily(18, 0),
```

### Weekly

Run once per week:

```zig
// Sunday at 3 AM
.schedule = logly.Schedule.weekly(0, 3, 0),

// Monday at 9 AM
.schedule = logly.Schedule.weekly(1, 9, 0),

// Friday at 5 PM
.schedule = logly.Schedule.weekly(5, 17, 0),
```

### One-Time

Run once at a specific timestamp:

```zig
.schedule = .{
    .type = .once,
    .timestamp = future_timestamp,
},
```

## Task Types

### Cleanup Tasks

Remove old log files:

```zig
_ = try scheduler.addTask(.{
    .name = "log_cleanup",
    .task_type = .cleanup,
    .schedule = logly.Schedule.daily(3, 0),
    .config = .{ .cleanup = .{
        .path = "logs",
        .max_age_days = 30,
        .pattern = "*.log",
        .include_compressed = true,
        .min_files_to_keep = 5,
        .dry_run = false,
    }},
});
```

#### Cleanup Configuration

| Option | Default | Description |
|--------|---------|-------------|
| `path` | required | Directory to clean |
| `max_age_days` | 30 | Maximum file age |
| `pattern` | "*.log" | Glob pattern |
| `include_compressed` | true | Include .gz files |
| `min_files_to_keep` | 5 | Keep at least N files |
| `dry_run` | false | Don't actually delete |

### Compression Tasks

Compress old log files:

```zig
_ = try scheduler.addTask(.{
    .name = "log_compression",
    .task_type = .compression,
    .schedule = logly.Schedule.everyHours(1),
    .config = .{ .compression = .{
        .path = "logs",
        .pattern = "*.log",
        .min_age_days = 1,
        .delete_originals = true,
        .skip_compressed = true,
    }},
});
```

#### Compression Configuration

| Option | Default | Description |
|--------|---------|-------------|
| `path` | required | Directory to compress |
| `pattern` | "*.log" | File pattern |
| `min_age_days` | 1 | Minimum age to compress |
| `delete_originals` | true | Delete after compression |
| `skip_compressed` | true | Skip .gz files |

### Rotation Tasks

Force log rotation:

```zig
_ = try scheduler.addTask(.{
    .name = "forced_rotation",
    .task_type = .rotation,
    .schedule = logly.Schedule.daily(0, 0), // Midnight
    .config = .{ .rotation = .{
        .path = "logs/app.log",
        .force = true,
    }},
});
```

### Custom Tasks

Run custom maintenance functions:

```zig
_ = try scheduler.addTask(.{
    .name = "custom_maintenance",
    .task_type = .custom,
    .schedule = logly.Schedule.everyMinutes(30),
    .config = .{ .custom = .{
        .callback = myMaintenanceFunction,
        .context = @ptrCast(&my_data),
    }},
});

fn myMaintenanceFunction(ctx: *anyopaque) void {
    // Custom maintenance logic
    const data: *MyData = @alignCast(@ptrCast(ctx));
    // ...
}
```

### Flush Tasks

Flush all log buffers:

```zig
_ = try scheduler.addTask(.{
    .name = "periodic_flush",
    .task_type = .flush,
    .schedule = logly.Schedule.everyMinutes(5),
    .config = .{ .none = {} },
});
```

### Health Check Tasks

Run periodic health checks:

```zig
_ = try scheduler.addTask(.{
    .name = "health_check",
    .task_type = .health_check,
    .schedule = logly.Schedule.interval(300), // 5 minutes
    .config = .{ .none = {} },
});
```

## Task Management

### Adding Tasks

```zig
const task_index = try scheduler.addTask(.{
    .name = "my_task",
    // ...
});
```

### Removing Tasks

```zig
try scheduler.removeTask(task_index);
```

### Enabling/Disabling Tasks

```zig
// Disable temporarily
scheduler.disableTask(task_index);

// Re-enable
scheduler.enableTask(task_index);
```

### Running Tasks Manually

```zig
// Execute immediately, regardless of schedule
try scheduler.runTaskNow(task_index);
```

### Listing Tasks

```zig
const tasks = scheduler.listTasks();
for (tasks, 0..) |task, i| {
    std.debug.print("Task {d}: {s} ({s})\n", .{
        i,
        task.name,
        @tagName(task.task_type),
    });
}
```

## Presets

Use built-in presets for common scenarios:

```zig
// Daily cleanup at 2 AM, keep 30 days
_ = try scheduler.addTask(
    logly.SchedulerPresets.dailyCleanup("logs"),
);

// Hourly compression
_ = try scheduler.addTask(
    logly.SchedulerPresets.hourlyCompression("logs"),
);

// Weekly deep clean on Sunday 3 AM
_ = try scheduler.addTask(
    logly.SchedulerPresets.weeklyDeepClean("logs"),
);
```

## Statistics

Monitor scheduler performance:

```zig
const stats = scheduler.getStats();

std.debug.print("Tasks executed: {d}\n", .{
    stats.tasks_executed.load(.monotonic),
});
std.debug.print("Tasks failed: {d}\n", .{
    stats.tasks_failed.load(.monotonic),
});
std.debug.print("Files cleaned: {d}\n", .{
    stats.files_cleaned.load(.monotonic),
});
std.debug.print("Bytes freed: {d}\n", .{
    stats.bytes_freed.load(.monotonic),
});
```

## Configuration

### Scheduler Configuration

```zig
var scheduler = try logly.Scheduler.init(allocator, .{
    .check_interval_ms = 60000,     // Check every minute
    .auto_start = false,            // Manual start
    .timezone_offset = -5,          // EST (UTC-5)
    .max_concurrent_tasks = 4,      // Parallel tasks
    .retry_failed = true,           // Retry on failure
    .max_retries = 3,               // Retry attempts
    .retry_delay_ms = 5000,         // Delay between retries
    .log_executions = true,         // Log task runs
    .shutdown_timeout_ms = 10000,   // Graceful shutdown
});
```

### Timezone Handling

```zig
// UTC
.timezone_offset = 0

// Eastern Time (EST)
.timezone_offset = -5

// Central European Time (CET)
.timezone_offset = 1

// Pacific Time (PST)
.timezone_offset = -8
```

## Error Handling

### Retry Configuration

```zig
.retry_failed = true,
.max_retries = 3,
.retry_delay_ms = 5000,
```

### Task Failure Handling

When a task fails:
1. Error is logged (if `log_executions` is true)
2. `failure_count` is incremented
3. If `retry_failed` is true, retry is scheduled
4. After `max_retries`, task remains enabled but marked as failed

### Monitoring Failures

```zig
const tasks = scheduler.listTasks();
for (tasks) |task| {
    if (task.failure_count > 0) {
        std.debug.print("Task '{s}' failed {d} times\n", .{
            task.name,
            task.failure_count,
        });
    }
}
```

## Integration with Other Modules

### With Compression Module

```zig
var compression = logly.Compression.init(allocator, .{
    .mode = .scheduled,
});

// Compression triggered by scheduler
_ = try scheduler.addTask(.{
    .task_type = .compression,
    .config = .{ .compression = .{
        .path = "logs",
    }},
});
```

### With Rotation

```zig
// Daily rotation at midnight
_ = try scheduler.addTask(.{
    .name = "daily_rotation",
    .task_type = .rotation,
    .schedule = logly.Schedule.daily(0, 0),
    .config = .{ .rotation = .{
        .path = "logs/app.log",
    }},
});
```

## Best Practices

### 1. Schedule Non-Peak Hours

```zig
// Run cleanup during low-traffic hours
.schedule = logly.Schedule.daily(3, 0), // 3 AM
```

### 2. Stagger Tasks

```zig
// Don't run all tasks at the same time
_ = scheduler.addTask(.{ .schedule = logly.Schedule.daily(2, 0) });  // Cleanup
_ = scheduler.addTask(.{ .schedule = logly.Schedule.daily(3, 0) });  // Compression
_ = scheduler.addTask(.{ .schedule = logly.Schedule.daily(4, 0) });  // Health check
```

### 3. Use Dry Run for Testing

```zig
.config = .{ .cleanup = .{
    .dry_run = true, // Test without deleting
}},
```

### 4. Set Minimum Files

```zig
// Always keep some logs for debugging
.config = .{ .cleanup = .{
    .min_files_to_keep = 10,
}},
```

### 5. Monitor Statistics

Regularly check statistics to ensure tasks are running:

```zig
const stats = scheduler.getStats();
if (stats.tasks_failed.load(.monotonic) > 0) {
    // Alert on failures
}
```

## Example: Production Setup

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Production scheduler config
    var scheduler = try logly.Scheduler.init(allocator, .{
        .check_interval_ms = 60000,
        .timezone_offset = -5, // EST
        .max_concurrent_tasks = 2,
        .retry_failed = true,
        .max_retries = 3,
    });
    defer scheduler.deinit();

    // Daily cleanup at 2 AM - remove logs older than 30 days
    _ = try scheduler.addTask(.{
        .name = "daily_cleanup",
        .task_type = .cleanup,
        .schedule = logly.Schedule.daily(2, 0),
        .config = .{ .cleanup = .{
            .path = "logs",
            .max_age_days = 30,
            .min_files_to_keep = 10,
        }},
    });

    // Hourly compression - compress logs older than 1 day
    _ = try scheduler.addTask(.{
        .name = "hourly_compression",
        .task_type = .compression,
        .schedule = logly.Schedule.everyHours(1),
        .config = .{ .compression = .{
            .path = "logs",
            .min_age_days = 1,
        }},
    });

    // Weekly deep clean on Sunday
    _ = try scheduler.addTask(.{
        .name = "weekly_deep_clean",
        .task_type = .cleanup,
        .schedule = logly.Schedule.weekly(0, 3, 0),
        .config = .{ .cleanup = .{
            .path = "logs",
            .max_age_days = 7,
            .include_compressed = true,
        }},
    });

    // Start scheduler
    try scheduler.start();

    // ... application runs ...

    // Graceful shutdown
    scheduler.stop();
}
```

## See Also

- [Scheduler API Reference](../api/scheduler.md)
- [Compression Guide](compression.md)
- [Rotation Guide](rotation.md)
