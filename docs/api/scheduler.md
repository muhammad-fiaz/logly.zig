# Scheduler API

The scheduler module provides automatic log maintenance with scheduled cleanup, compression, rotation, and custom tasks.

## Overview

```zig
const logly = @import("logly");
const Scheduler = logly.Scheduler;
const SchedulerPresets = logly.SchedulerPresets;
```

## Centralized Configuration

Scheduler can be enabled through the central `Config` struct:

```zig
var config = logly.Config.default();
config.scheduler = .{
    .enabled = true,
    .cleanup_max_age_days = 14,
    .max_files = 100,
    .compress_before_cleanup = true,
    .file_pattern = "*.log",
};
const logger = try logly.Logger.initWithConfig(allocator, config);
```

Or use the fluent API:

```zig
const config = logly.Config.default().withScheduler(.{});
```

## Types

### Scheduler

The main scheduler struct for managing scheduled tasks.

```zig
pub const Scheduler = struct {
    allocator: std.mem.Allocator,
    tasks: std.ArrayList(ScheduledTask),
    stats: SchedulerStats,
    compression: Compression,  // Integrated compression support
    running: std.atomic.Value(bool),
    worker_thread: ?std.Thread,
};
```

### SchedulerConfig (Centralized)

Configuration available through `Config.SchedulerConfig`:

```zig
pub const SchedulerConfig = struct {
    /// Enable the scheduler.
    enabled: bool = false,
    /// Default cleanup max age in days.
    cleanup_max_age_days: u64 = 7,
    /// Default max files to keep.
    max_files: ?usize = null,
    /// Enable compression before cleanup.
    compress_before_cleanup: bool = false,
    /// Default file pattern for cleanup.
    file_pattern: []const u8 = "*.log",
};
```

### ScheduledTask

A scheduled task configuration.

```zig
pub const ScheduledTask = struct {
    /// Unique task name
    name: []const u8,
    /// Task type
    task_type: TaskType,
    /// Schedule configuration
    schedule: Schedule,
    /// Task-specific configuration
    config: TaskConfig,
    /// Whether task is enabled
    enabled: bool = true,
    /// Last execution timestamp
    last_run: i64 = 0,
    /// Next scheduled execution
    next_run: i64 = 0,
    /// Number of executions
    run_count: u64 = 0,
    /// Number of failures
    error_count: u64 = 0,
};
```

### TaskType

Types of scheduled tasks.

```zig
pub const TaskType = enum {
    /// Clean up old log files
    cleanup,
    /// Rotate log files
    rotation,
    /// Compress log files
    compression,
    /// Flush all buffers
    flush,
    /// Health check
    health_check,
    /// Custom user-defined task
    custom,
};
```
};
```

### Schedule

Schedule configuration.

```zig
pub const Schedule = struct {
    /// Schedule type
    type: ScheduleType,
    /// Interval in seconds (for interval type)
    interval_seconds: u64 = 0,
    /// Cron expression (for cron type)
    cron: ?[]const u8 = null,
    /// Hour of day (for daily type, 0-23)
    hour: u8 = 0,
    /// Minute (for daily/weekly type, 0-59)
    minute: u8 = 0,
    /// Day of week (for weekly type, 0=Sunday)
    day_of_week: u8 = 0,
};
```

### ScheduleType

Types of schedules.

```zig
pub const ScheduleType = enum {
    /// Run at fixed intervals
    interval,
    /// Cron-style schedule
    cron,
    /// Run once daily at specific time
    daily,
    /// Run once weekly at specific time
    weekly,
    /// Run once at specific timestamp
    once,
};
```

### TaskConfig

Configuration specific to task types.

```zig
pub const TaskConfig = union(enum) {
    cleanup: CleanupConfig,
    compression: CompressionTaskConfig,
    rotation: RotationConfig,
    custom: CustomTaskConfig,
    none: void,
};
```

### CleanupConfig

Configuration for cleanup tasks.

```zig
pub const CleanupConfig = struct {
    /// Directory to clean
    path: []const u8,
    /// Maximum age in days
    max_age_days: u32 = 30,
    /// File pattern to match (glob)
    pattern: []const u8 = "*.log",
    /// Include compressed files
    include_compressed: bool = true,
    /// Minimum files to keep
    min_files_to_keep: u32 = 5,
    /// Dry run (don't actually delete)
    dry_run: bool = false,
};
```

### CompressionTaskConfig

Configuration for compression tasks.

```zig
pub const CompressionTaskConfig = struct {
    /// Directory containing files to compress
    path: []const u8,
    /// File pattern to match
    pattern: []const u8 = "*.log",
    /// Minimum file age before compressing (days)
    min_age_days: u32 = 1,
    /// Delete originals after compression
    delete_originals: bool = true,
    /// Skip already compressed files
    skip_compressed: bool = true,
};
```

### SchedulerStats

Statistics for scheduled operations.

```zig
pub const SchedulerStats = struct {
    // Note: Atomic counters are architecture-dependent (u64 on 64-bit targets, u32 on 32-bit targets)
    tasks_executed: std.atomic.Value(/* architecture-dependent */),
    tasks_failed: std.atomic.Value(/* architecture-dependent */),
    files_cleaned: std.atomic.Value(/* architecture-dependent */),
    files_compressed: std.atomic.Value(/* architecture-dependent */),
    bytes_freed: std.atomic.Value(/* architecture-dependent */),
    last_run_timestamp: std.atomic.Value(/* signed architecture-dependent */),
    total_runtime_ns: std.atomic.Value(/* architecture-dependent */),
};
```

## Methods

### init

Create a new scheduler.

```zig
pub fn init(allocator: std.mem.Allocator, config: SchedulerConfig) !Scheduler
```

**Parameters:**
- `allocator`: Memory allocator
- `config`: Scheduler configuration

**Returns:** A new `Scheduler` instance

### deinit

Clean up resources and stop the scheduler.

```zig
pub fn deinit(self: *Scheduler) void
```

### start

Start the scheduler worker thread.

```zig
pub fn start(self: *Scheduler) !void
```

### stop

Stop the scheduler gracefully.

```zig
pub fn stop(self: *Scheduler) void
```

### addTask

Add a scheduled task.

```zig
pub fn addTask(self: *Scheduler, task: ScheduledTask) !usize
```

**Parameters:**
- `task`: The task to add

**Returns:** Index of the added task

### removeTask

Remove a task by index.

```zig
pub fn removeTask(self: *Scheduler, index: usize) !void
```

### enableTask

Enable a task by index.

```zig
pub fn enableTask(self: *Scheduler, index: usize) void
```

### disableTask

Disable a task by index.

```zig
pub fn disableTask(self: *Scheduler, index: usize) void
```

### runTaskNow

Execute a task immediately.

```zig
pub fn runTaskNow(self: *Scheduler, index: usize) !void
```

### getStats

Get current scheduler statistics.

```zig
pub fn getStats(self: *const Scheduler) SchedulerStats
```

### listTasks

Get list of all scheduled tasks.

```zig
pub fn listTasks(self: *const Scheduler) []const ScheduledTask
```

## Schedule Helpers

### interval

Create an interval schedule.

```zig
pub fn interval(seconds: u64) Schedule {
    return .{
        .type = .interval,
        .interval_seconds = seconds,
    };
}
```

### daily

Create a daily schedule.

```zig
pub fn daily(hour: u8, minute: u8) Schedule {
    return .{
        .type = .daily,
        .hour = hour,
        .minute = minute,
    };
}
```

### weekly

Create a weekly schedule.

```zig
pub fn weekly(day_of_week: u8, hour: u8, minute: u8) Schedule {
    return .{
        .type = .weekly,
        .day_of_week = day_of_week,
        .hour = hour,
        .minute = minute,
    };
}
```

### everyMinutes

Create a schedule for every N minutes.

```zig
pub fn everyMinutes(minutes: u64) Schedule {
    return interval(minutes * 60);
}
```

### everyHours

Create a schedule for every N hours.

```zig
pub fn everyHours(hours: u64) Schedule {
    return interval(hours * 3600);
}
```

## Presets

### dailyCleanup

Daily cleanup at 2 AM.

```zig
pub fn dailyCleanup(path: []const u8) ScheduledTask {
    return .{
        .name = "daily_cleanup",
        .task_type = .cleanup,
        .schedule = Schedule.daily(2, 0),
        .config = .{ .cleanup = .{
            .path = path,
            .max_age_days = 30,
            .pattern = "*.log",
        }},
    };
}
```

### hourlyCompression

Hourly log compression.

```zig
pub fn hourlyCompression(path: []const u8) ScheduledTask {
    return .{
        .name = "hourly_compression",
        .task_type = .compression,
        .schedule = Schedule.everyHours(1),
        .config = .{ .compression = .{
            .path = path,
            .min_age_days = 0,
        }},
    };
}
```

### weeklyDeepClean

Weekly deep cleanup.

```zig
pub fn weeklyDeepClean(path: []const u8) ScheduledTask {
    return .{
        .name = "weekly_deep_clean",
        .task_type = .cleanup,
        .schedule = Schedule.weekly(0, 3, 0), // Sunday 3 AM
        .config = .{ .cleanup = .{
            .path = path,
            .max_age_days = 7,
            .include_compressed = true,
        }},
    };
}
```

## Usage Example

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create scheduler
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

    // Add hourly compression
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

    // Check stats periodically
    const stats = scheduler.getStats();
    std.debug.print("Tasks executed: {d}\n", .{
        stats.tasks_executed.load(.monotonic),
    });
}
```

## See Also

- [Compression API](compression.md) - Log compression
- [Rotation Guide](../guide/rotation.md) - Log rotation
- [Configuration Guide](../guide/configuration.md) - Full configuration options
