---
title: Logging Scheduler
description: Automate log maintenance with the Logly.zig scheduler. Schedule cleanup, compression, rotation, and health checks to keep your logs managed and efficient.
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

This guide covers automatic log maintenance in Logly using the scheduler, including cleanup, compression, rotation tasks, and custom scheduled operations.

## Overview

The scheduler module provides automatic log maintenance by running tasks on configurable schedules. This includes cleaning up old logs, compressing files, rotating logs, and running custom maintenance tasks.

Use `Scheduler.validateDependencies()` after wiring tasks together to catch missing dependency names and dependency cycles early.

## Logger Configuration

Enable scheduler through the Config struct:

```zig
const logly = @import("logly");

var config = logly.Config.default();
config.scheduler = .{
    .enabled = true,              // Enable scheduler
    .cleanupMaxAgeDays = 7,    // Delete logs older than 7 days
    .maxFiles = 10,              // Keep max 10 rotated files
    .compressBeforeCleanup = true, // Compress before deleting
    .filePattern = "*.log",      // Pattern for log files
};

// Or use helper method
var config2 = logly.Config.default().withScheduler(.{ .cleanupMaxAgeDays = 7 });
```

### Advanced Configuration

```zig
var config = logly.Config.default();
config.scheduler = .{
    .enabled = true,
    .cleanupMaxAgeDays = 7,
    .compressBeforeCleanup = true,
    // Archive root directory for all compressed files
    .archiveRootDir = "logs/archive",
    .createDateSubdirs = true,        // Organize by YYYY/MM/DD
    // Compression settings
    .compressionAlgorithm = .gzip,
    .compressionLevel = .best,
    .keepOriginals = false,
    // File naming customization
    .archiveFilePrefix = "archived_",
    .archiveFileSuffix = "_v1",
    .preserveDirStructure = true,
    // Cleanup settings
    .cleanEmptyDirs = true,
    .minAgeDaysForCompression = 1,
    .maxConcurrentCompressions = 4,
};
```

### Scheduler Configuration Options

| Option | Type | Default | Description |
|---|---|---|---|
| `enabled` | `bool` | `false` | Enable the scheduler |
| `cleanupMaxAgeDays` | `u64` | `7` | Max age for cleanup tasks |
| `maxFiles` | `?usize` | `null` | Max files to retain |
| `compressBeforeCleanup` | `bool` | `false` | Compress before deleting |
| `filePattern` | `[]const u8` | `"*.log"` | File pattern for tasks |
| `archiveRootDir` | `?[]const u8` | `null` | Root directory for archives |
| `createDateSubdirs` | `bool` | `false` | Create YYYY/MM/DD structure |
| `compressionAlgorithm` | `CompressionAlgorithm` | `.gzip` | Compression algorithm (gzip, zlib, deflate, zstd, lzma, lzma2, xz, zip, tar.gz, lz4) |
| `compressionLevel` | `CompressionLevel` | `.default` | Compression level |
| `keepOriginals` | `bool` | `false` | Keep original files |
| `archiveFilePrefix` | `?[]const u8` | `null` | Prefix for file names |
| `archiveFileSuffix` | `?[]const u8` | `null` | Suffix for file names |
| `preserveDirStructure` | `bool` | `true` | Preserve directory structure |
| `cleanEmptyDirs` | `bool` | `false` | Remove empty directories |
| `minAgeDaysForCompression` | `u64` | `1` | Min age before compression |
| `maxConcurrentCompressions` | `usize` | `2` | Max parallel compressions |

## Quick Start

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create scheduler
    var scheduler = try logly.Scheduler.init(allocator);
    defer scheduler.deinit();

    // Add a cleanup task
     _ = try scheduler.addTask(.{
        .name = "daily_cleanup",
        .taskType = .cleanup,
        .schedule = .{ .daily = .{ .hour = 2, .minute = 0 } },
        .config = .{
            .path = "logs",
            .maxAgeSeconds = 30 * 24 * 60 * 60, // 30 days
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

### Jitter

Add optional random delay (jitter) to prevent thundering herd when multiple tasks are scheduled at the same time:

```zig
.schedule = .{
    .interval = 60 * 1000,
    .jitter_ms = 5000, // ±5 seconds random delay
},
```

## Task Types

### Cleanup Tasks

Remove old log files:

```zig
 _ = try scheduler.addTask(.{
    .name = "log_cleanup",
    .taskType = .cleanup,
    .schedule = logly.Schedule.daily(3, 0),
    .config = .{ .cleanup = .{
        .path = "logs",
        .maxAgeDays = 30,
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
| `maxAgeDays` | 30 | Maximum file age |
| `pattern` | "*.log" | Glob pattern |
| `include_compressed` | true | Include .gz files |
| `min_files_to_keep` | 5 | Keep at least N files |
| `dry_run` | false | Don't actually delete |

### Compression Tasks

Compress old log files:

```zig
 _ = try scheduler.addTask(.{
    .name = "log_compression",
    .taskType = .compression,
    .schedule = logly.Schedule.everyHours(1),
    .config = .{ .compression = .{
        .path = "logs",
        .pattern = "*.log",
        .minAgeDays = 1,
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
| `minAgeDays` | 1 | Minimum age to compress |
| `delete_originals` | true | Delete after compression |
| `skip_compressed` | true | Skip .gz files |

#### Compression Modes

The scheduler supports multiple compression strategies:

| Mode | Field | Behavior |
|------|-------|----------|
| **Compress & Delete** | `compressBeforeDelete = true` | Compress file, then delete original |
| **Compress & Keep** | `compressAndKeep = true` | Compress file, keep both versions |
| **Compress Only** | `compressOnly = true` | Compress file, never delete anything |

**Example: Compress and Keep Both**
```zig
 _ = try scheduler.addTask(.{
    .name = "archive_logs",
    .taskType = .cleanup,
    .schedule = logly.Schedule.daily(2, 0),
    .config = .{
        .path = "logs",
        .filePattern = "*.log",
        .minAgeSeconds = 24 * 60 * 60, // 1 day
        .compressAndKeep = true,       // Keep both original and compressed
        .skipAlreadyCompressed = true,
    },
});
```

**Example: Compress Only (No Deletion)**
```zig
 _ = try scheduler.addTask(.{
    .name = "pure_archive",
    .taskType = .cleanup,
    .schedule = logly.Schedule.daily(3, 0),
    .config = .{
        .path = "logs",
        .filePattern = "*.log",
        .compressOnly = true,           // Only compress, never delete
        .skipAlreadyCompressed = true,
    },
});
```

### Rotation Tasks

Force log rotation:

```zig
 _ = try scheduler.addTask(.{
    .name = "forced_rotation",
    .taskType = .rotation,
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
    .taskType = .custom,
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
    .taskType = .flush,
    .schedule = logly.Schedule.everyMinutes(5),
    .config = .{ .none = {} },
});
```

### Health Check Tasks

Run periodic health checks:

```zig
 _ = try scheduler.addTask(.{
    .name = "health_check",
    .taskType = .healthCheck,
    .schedule = logly.Schedule.interval(300), // 5 minutes
    .config = .{ .none = {} },
});
```

## Task Management

### Adding Tasks

```zig
const taskIndex = try scheduler.addTask(.{
    .name = "my_task",
    // ...
});
```

### Removing Tasks

```zig
try scheduler.removeTask(taskIndex);
```

### Enabling/Disabling Tasks

```zig
// Disable temporarily
scheduler.disableTask(taskIndex);

// Re-enable
scheduler.enableTask(taskIndex);
```

### Global Pause and Resume

You can temporarily pause all background execution of tasks:

```zig
scheduler.pause();
// ... no tasks will execute ...
scheduler.unpause();
```

### Running Tasks Manually

```zig
// Execute immediately, regardless of schedule
try scheduler.runTaskNow(taskIndex);
```

### Listing Tasks

```zig
const tasks = scheduler.listTasks();
for (tasks, 0..) |task, i| {
    std.debug.print("Task {d}: {s} ({s})\n", .{
        i,
        task.name,
        @tagName(task.taskType),
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

### Compression Presets

```zig
const Presets = logly.SchedulerPresets;

// Compress then delete originals (files older than 7 days)
const archive_config = Presets.compressThenDelete("logs", 7);

// Compress and keep both versions (files older than 3 days)
const backup_config = Presets.compressAndKeep("logs", 3);

// Only compress, never delete anything (files older than 1 day)
const pure_archive = Presets.compressOnly("logs", 1);

// Archive old logs: compress after 7 days, delete after 30 days
const tiered_config = Presets.archiveOldLogs("logs", 7, 30);

// Aggressive cleanup: compress & delete, max 100 files
const aggressive_config = Presets.aggressiveCleanup("logs", 30, 100);
```

### Preset Summary

| Preset | Compress | Delete | Keep Both | Use Case |
|---|---|---|---|---|
| `compressThenDelete` | ✓ | ✓ | ✗ | Standard archival |
| `compressAndKeep` | ✓ | ✗ | ✓ | Redundant backup |
| `compressOnly` | ✓ | ✗ | ✗ | Pure archival |
| `archiveOldLogs` | ✓ | ✓ (aged) | ✗ | Tiered retention |
| `aggressiveCleanup` | ✓ | ✓ | ✗ | Space-constrained |

## Statistics

Monitor scheduler performance with atomic stats and helper methods:

```zig
const stats = scheduler.getStats();

// Use helper methods for easy access
std.debug.print("Tasks executed: {d}\n", .{stats.getExecuted()});
std.debug.print("Tasks failed: {d}\n", .{stats.getFailed()});
std.debug.print("Files cleaned: {d}\n", .{stats.getFilesCleaned()});
std.debug.print("Files compressed: {d}\n", .{stats.getFilesCompressed()});
std.debug.print("Bytes freed: {d}\n", .{stats.getBytesFreed()});
std.debug.print("Bytes saved: {d}\n", .{stats.getBytesSaved()});

// Rate calculations
std.debug.print("Success rate: {d:.1}%\n", .{stats.successRate() * 100});
std.debug.print("Failure rate: {d:.1}%\n", .{stats.failureRate() * 100});

// Uptime info
std.debug.print("Uptime: {d} seconds\n", .{stats.uptimeSeconds()});
std.debug.print("Tasks per hour: {d:.2}\n", .{stats.tasksPerHour()});

// Check for failures
if (stats.hasFailures()) {
    std.log.warn("Scheduler has failed tasks!", .{});
}
```

### SchedulerStats Methods

| Method | Returns | Description |
|---|---|---|
| `getExecuted()` | `u64` | Total successful executions |
| `getFailed()` | `u64` | Total failed executions |
| `getFilesCleaned()` | `u64` | Total files cleaned |
| `getFilesCompressed()` | `u64` | Total files compressed |
| `getBytesFreed()` | `u64` | Total bytes freed |
| `getBytesSaved()` | `u64` | Total bytes saved by compression |
| `successRate()` | `f64` | Success rate (0.0 - 1.0) |
| `failureRate()` | `f64` | Failure rate (0.0 - 1.0) |
| `hasFailures()` | `bool` | Check if any failures occurred |
| `uptimeSeconds()` | `i64` | Scheduler uptime in seconds |
| `tasksPerHour()` | `f64` | Average tasks per hour |
| `compressionRatio()` | `f64` | Compression savings ratio |

## Configuration

### Scheduler Configuration

```zig
var scheduler = try logly.Scheduler.init(allocator, .{
    .check_interval_ms = 60000,     // Check every minute
    .auto_start = false,            // Manual start
    .timezone_offset = -5,          // EST (UTC-5)
    .max_concurrent_tasks = 4,      // Parallel tasks
    .retry_failed = true,           // Retry on failure
    .maxRetries = 3,               // Retry attempts
    .retryDelayMs = 5000,         // Delay between retries
    .log_executions = true,         // Log task runs
    .shutdownTimeoutMs = 10000,   // Graceful shutdown
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
.maxRetries = 3,
.retryDelayMs = 5000,
```

### Task Failure Handling & Retries

When a task fails (its callback returns an error):
1. Error is logged (if `log_executions` is true)
2. `failure_count` is incremented
3. If `maxRetries` is configured, the task is retried with exponential backoff: `delay = retryBackoffMs * (2 ^ attempt)`
4. After `maxRetries` attempts, the task remains enabled but marked as failed until the next scheduled interval

```zig
 _ = try scheduler.addTask(.{
    .name = "my_task",
    .taskType = .custom,
    .schedule = logly.Schedule.daily(2, 0),
    .config = .{
        .maxRetries = 3,         // Retry up to 3 times
        .retryBackoffMs = 1000, // Starts at 1s, then 2s, then 4s
    },
});
```

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
    .taskType = .compression,
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
    .taskType = .rotation,
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

// Check for failures using helper method
if (stats.hasFailures()) {
    std.log.warn("Scheduler has {d} failed tasks", .{stats.getFailed()});
    // Alert on failures
}

// Monitor efficiency
const rate = stats.successRate();
if (rate < 0.95) {
    std.log.warn("Task success rate below 95%: {d:.1}%", .{rate * 100});
}

// Check uptime and throughput
std.log.info("Running for {d}s, {d:.2} tasks/hour", .{
    stats.uptimeSeconds(),
    stats.tasksPerHour(),
});
```

## Example: Production Setup

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Production scheduler config
    var scheduler = try logly.Scheduler.init(allocator, .{
        .check_interval_ms = 60000,
        .timezone_offset = -5, // EST
        .max_concurrent_tasks = 2,
        .retry_failed = true,
        .maxRetries = 3,
    });
    defer scheduler.deinit();

    // Daily cleanup at 2 AM - remove logs older than 30 days
     _ = try scheduler.addTask(.{
        .name = "daily_cleanup",
        .taskType = .cleanup,
        .schedule = logly.Schedule.daily(2, 0),
        .config = .{ .cleanup = .{
            .path = "logs",
            .maxAgeDays = 30,
            .min_files_to_keep = 10,
        }},
    });

    // Hourly compression - compress logs older than 1 day
     _ = try scheduler.addTask(.{
        .name = "hourly_compression",
        .taskType = .compression,
        .schedule = logly.Schedule.everyHours(1),
        .config = .{ .compression = .{
            .path = "logs",
            .minAgeDays = 1,
        }},
    });

    // Weekly deep clean on Sunday
     _ = try scheduler.addTask(.{
        .name = "weekly_deep_clean",
        .taskType = .cleanup,
        .schedule = logly.Schedule.weekly(0, 3, 0),
        .config = .{ .cleanup = .{
            .path = "logs",
            .maxAgeDays = 7,
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
- [Telemetry Guide](telemetry.md)

## Telemetry Integration

The scheduler supports optional telemetry integration for distributed tracing and observability. When enabled, each task execution creates a span with task-specific attributes.

### Basic Setup

```zig
const logly = @import("logly");

// Create telemetry instance
var telemetry = try logly.Telemetry.init(allocator, .{
    .provider = .file,
    .exporterFilePath = "scheduler_telemetry.jsonl",
});
defer telemetry.deinit();

// Create and configure scheduler
var scheduler = try logly.Scheduler.init(allocator);
defer scheduler.deinit();

// Enable telemetry
scheduler.setTelemetry(&telemetry);

// Add tasks and start
 _ = try scheduler.addTask(.{
    .name = "daily_cleanup",
    .taskType = .cleanup,
    .schedule = logly.Schedule.daily(2, 0),
    .config = .{
        .path = "logs",
        .maxAgeSeconds = 30 * 24 * 60 * 60,
    },
});

try scheduler.start();
```

### Span Attributes

Task execution spans include:

| Attribute | Task Types | Description |
|-----------|------------|-------------|
| `task.type` | All | Task type name |
| `task.priority` | All | Task priority |
| `task.durationMs` | All | Execution time |
| `cleanup.filesDeleted` | cleanup | Files deleted |
| `cleanup.bytesFreed` | cleanup | Bytes freed |
| `compression.files` | compression | Files compressed |
| `compression.bytesSaved` | compression | Space saved |
| `health.healthy` | healthCheck | Health status |

### Export to External Systems

```zig
// Export to Jaeger
var telemetry = try logly.Telemetry.init(allocator, .{
    .provider = .jaeger,
    .endpoint = "http://jaeger:14268/api/traces",
});

// Export to Zipkin
var telemetry = try logly.Telemetry.init(allocator, .{
    .provider = .zipkin,
    .endpoint = "http://zipkin:9411/api/v2/spans",
});
```

### Disabling Telemetry

```zig
// Disable telemetry when not needed
scheduler.clearTelemetry();
```

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
| `taskCount` | `count` |
| `isRunning` | `running` |
| `hasTasks` | `hasScheduledTasks` |

