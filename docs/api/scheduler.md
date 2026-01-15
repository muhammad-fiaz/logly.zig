---
title: Scheduler API Reference
description: API reference for Logly.zig Scheduler module. Automatic log maintenance with scheduled cleanup, compression, rotation, cron expressions, and custom periodic tasks.
head:
  - - meta
    - name: keywords
      content: scheduler api, log maintenance, automatic cleanup, cron scheduler, periodic tasks, log rotation scheduler
  - - meta
    - property: og:title
      content: Scheduler API Reference | Logly.zig
---

# Scheduler API

The scheduler module provides automatic log maintenance with scheduled cleanup, compression, rotation, and custom tasks. It runs in the background using either a dedicated worker thread or by submitting tasks to a shared `ThreadPool`.

## Quick Reference: Method Aliases

| Full Method | Alias(es) | Description |
|-------------|-----------|-------------|
| `init()` | `create()` | Initialize scheduler |
| `deinit()` | `destroy()` | Deinitialize scheduler |

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

The main scheduler struct for managing scheduled tasks with optional telemetry integration.

```zig
pub const Scheduler = struct {
    allocator: std.mem.Allocator,
    tasks: std.ArrayList(ScheduledTask),
    stats: SchedulerStats,
    compression: Compression,  // Integrated compression support
    running: std.atomic.Value(bool),
    worker_thread: ?std.Thread,
    telemetry: ?*Telemetry,    // Optional telemetry for distributed tracing
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
    /// Root directory for compressed/archived files.
    archive_root_dir: ?[]const u8 = null,
    /// Create date-based subdirectories (YYYY/MM/DD).
    create_date_subdirs: bool = false,
    /// Compression algorithm for scheduled compression tasks.
    compression_algorithm: CompressionConfig.CompressionAlgorithm = .gzip,
    /// Compression level for scheduled tasks.
    compression_level: CompressionConfig.CompressionLevel = .default,
    /// Keep original files after scheduled compression.
    keep_originals: bool = false,
    /// Custom prefix for archived file names.
    archive_file_prefix: ?[]const u8 = null,
    /// Custom suffix for archived file names.
    archive_file_suffix: ?[]const u8 = null,
    /// Preserve directory structure in archive root.
    preserve_dir_structure: bool = true,
    /// Delete empty directories after cleanup.
    clean_empty_dirs: bool = false,
    /// Minimum file age in days before compression.
    min_age_days_for_compression: u64 = 1,
    /// Maximum concurrent compression tasks.
    max_concurrent_compressions: usize = 2,
};
```

### SchedulerConfig Field Reference

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `enabled` | `bool` | `false` | Enable the scheduler |
| `cleanup_max_age_days` | `u64` | `7` | Max age for cleanup tasks |
| `max_files` | `?usize` | `null` | Max files to retain |
| `compress_before_cleanup` | `bool` | `false` | Compress before deleting |
| `file_pattern` | `[]const u8` | `"*.log"` | File pattern for tasks |
| `archive_root_dir` | `?[]const u8` | `null` | Centralized archive location |
| `create_date_subdirs` | `bool` | `false` | Create YYYY/MM/DD subdirs |
| `compression_algorithm` | `CompressionAlgorithm` | `.gzip` | Algorithm for compression |
| `compression_level` | `CompressionLevel` | `.default` | Compression level |
| `keep_originals` | `bool` | `false` | Keep originals after compression |
| `archive_file_prefix` | `?[]const u8` | `null` | Prefix for archived files |
| `archive_file_suffix` | `?[]const u8` | `null` | Suffix for archived files |
| `preserve_dir_structure` | `bool` | `true` | Keep directory structure |
| `clean_empty_dirs` | `bool` | `false` | Remove empty directories |
| `min_age_days_for_compression` | `u64` | `1` | Min age before compression |
| `max_concurrent_compressions` | `usize` | `2` | Max parallel compressions |

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
    /// Task execution callback (for custom tasks)
    callback: ?*const fn (*ScheduledTask) anyerror!void = null,
    /// Whether task is enabled
    enabled: bool = true,
    /// Whether task is currently running
    running: bool = false,
    /// Task execution priority
    priority: Priority = .normal,
    /// Retry policy for failed tasks
    retry_policy: RetryPolicy = .{},
    /// Name of another task that must complete successfully before this one runs
    depends_on: ?[]const u8 = null,
    /// Last execution timestamp
    last_run: i64 = 0,
    /// Next scheduled execution
    next_run: i64 = 0,
    /// Number of executions
    run_count: u64 = 0,
    /// Number of failures
    error_count: u64 = 0,
    /// Retries remaining for current failure
    retries_remaining: u32 = 0,

    pub const Priority = enum {
        low,
        normal,
        high,
        critical,
    };

    pub const RetryPolicy = struct {
        max_retries: u32 = 3,
        interval_ms: u32 = 5000,
        backoff_multiplier: f32 = 1.5,
    };
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
    /// Custom user-defined task
    custom,
    /// Health check
    health_check,
    /// Metrics collection
    metrics_snapshot,
};
```

### TaskConfig

Configuration specific to tasks.

```zig
pub const TaskConfig = struct {
    /// Path for file-based tasks
    path: ?[]const u8 = null,
    /// Maximum age in seconds for cleanup
    max_age_seconds: u64 = 7 * 24 * 60 * 60,
    /// Maximum files to keep
    max_files: ?usize = null,
    /// Maximum total size in bytes
    max_total_size: ?u64 = null,
    /// Minimum age in seconds (useful for compression)
    min_age_seconds: u64 = 0,
    /// File pattern to match (e.g., "*.log")
    file_pattern: ?[]const u8 = null,
    /// Compress files before cleanup (compress then delete)
    compress_before_delete: bool = false,
    /// Compress files and keep both original and compressed (archive mode)
    compress_and_keep: bool = false,
    /// Only compress files, don't delete any (pure archival)
    compress_only: bool = false,
    /// Skip files that are already compressed (.gz, .lgz, .zst)
    skip_already_compressed: bool = true,
    /// Recursive directory processing
    recursive: bool = false,
    /// Trigger task only if disk usage exceeds this percentage (0-100)
    trigger_disk_usage_percent: ?u8 = null,
    /// Required free space in bytes before running task
    min_free_space_bytes: ?u64 = null,
};
```

#### TaskConfig Compression Modes

| Field | Behavior |
|-------|----------|
| `compress_before_delete` | Compress file, then delete original |
| `compress_and_keep` | Compress file, keep both versions |
| `compress_only` | Compress file, never delete anything |

### Schedule

Schedule configuration.

```zig
pub const Schedule = union(enum) {
    /// Run once after delay (in milliseconds)
    once: u64,
    /// Run at fixed intervals (in milliseconds)
    interval: u64,
    /// Run at specific time of day
    daily: DailySchedule,
    /// Cron-like schedule
    cron: CronSchedule,

    pub const DailySchedule = struct {
        hour: u8 = 0,
        minute: u8 = 0,
    };

    pub const CronSchedule = struct {
        minute: ?u8 = null,
        hour: ?u8 = null,
        day_of_month: ?u8 = null,
        month: ?u8 = null,
        day_of_week: ?u8 = null,
    };
};
```

### SchedulerStats

Thread-safe statistics for scheduled operations using atomic counters. Works correctly on both 32-bit and 64-bit architectures.

```zig
pub const SchedulerStats = struct {
    /// Total tasks executed successfully (atomic).
    tasks_executed: std.atomic.Value(Constants.AtomicUnsigned),
    /// Total tasks that failed (atomic).
    tasks_failed: std.atomic.Value(Constants.AtomicUnsigned),
    /// Total files cleaned up (atomic).
    files_cleaned: std.atomic.Value(Constants.AtomicUnsigned),
    /// Total files compressed (atomic).
    files_compressed: std.atomic.Value(Constants.AtomicUnsigned),
    /// Total bytes freed by cleanup operations (atomic).
    bytes_freed: std.atomic.Value(Constants.AtomicUnsigned),
    /// Total bytes saved by compression (atomic).
    bytes_saved: std.atomic.Value(Constants.AtomicUnsigned),
    /// Last run time in milliseconds (atomic).
    last_run_time: std.atomic.Value(i64),
    /// Scheduler start time for uptime calculation (atomic).
    start_time: std.atomic.Value(i64),
};
```

#### SchedulerStats Helper Methods

| Method | Return Type | Description |
|--------|-------------|-------------|
| `successRate()` | `f64` | Task success rate (0.0 - 1.0) |
| `failureRate()` | `f64` | Task failure rate (0.0 - 1.0) |
| `hasFailures()` | `bool` | Returns `true` if any tasks have failed |
| `getExecuted()` | `u64` | Total tasks executed as u64 |
| `getFailed()` | `u64` | Total tasks failed as u64 |
| `getFilesCleaned()` | `u64` | Total files cleaned as u64 |
| `getFilesCompressed()` | `u64` | Total files compressed as u64 |
| `getBytesFreed()` | `u64` | Total bytes freed as u64 |
| `getBytesSaved()` | `u64` | Total bytes saved by compression as u64 |
| `uptimeSeconds()` | `i64` | Uptime in seconds since scheduler started |
| `tasksPerHour()` | `f64` | Average tasks executed per hour |
| `compressionRatio()` | `f64` | Compression savings ratio (bytes saved / total) |

#### Usage Example

```zig
const stats = scheduler.getStats();

// Check success/failure rates
const success = stats.successRate();  // e.g., 0.95 (95%)
const failure = stats.failureRate();  // e.g., 0.05 (5%)

// Check for failures
if (stats.hasFailures()) {
    std.log.warn("Scheduler has {d} failed tasks", .{stats.getFailed()});
}

// Get uptime info
const uptime = stats.uptimeSeconds();
const rate = stats.tasksPerHour();
std.log.info("Running for {d}s, {d:.2} tasks/hour", .{uptime, rate});

// Check cleanup efficiency
const freed = stats.getBytesFreed();
const saved = stats.getBytesSaved();
const ratio = stats.compressionRatio();
std.log.info("Freed {d} bytes, saved {d} bytes ({d:.1}% compression)", .{
    freed, saved, ratio * 100.0
});
```

## Methods

### init

Create a new scheduler.

**Alias:** `create`

```zig
pub fn init(allocator: std.mem.Allocator) !*Scheduler
```

### initWithThreadPool

Create a new scheduler that uses a thread pool for task execution.

```zig
pub fn initWithThreadPool(allocator: std.mem.Allocator, thread_pool: *ThreadPool) !*Scheduler
```

**Parameters:**
- `allocator`: Memory allocator
- `thread_pool`: Shared thread pool instance

### initFromConfig

Create a scheduler from global configuration.

```zig
pub fn initFromConfig(allocator: std.mem.Allocator, config: SchedulerConfig, logs_path: ?[]const u8) !*Scheduler
```

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

Stop the scheduler gracefully, waiting for pending tasks to complete (with timeout).

```zig
pub fn stop(self: *Scheduler) void
```

### addTask

Add a scheduled task.

```zig
pub fn addTask(self: *Scheduler, name: []const u8, task_type: TaskType, schedule: Schedule, config: ScheduledTask.TaskConfig) !usize
```

**Parameters:**
- `name`: Unique task identifier
- `task_type`: Type of task
- `schedule`: Execution schedule
- `config`: Task configuration

**Returns:** Index of the added task

### setTaskPriority

Set the execution priority for a task.

```zig
pub fn setTaskPriority(self: *Scheduler, index: usize, priority: ScheduledTask.Priority) void
```

### setTaskRetryPolicy

Configure retry behavior for a task.

```zig
pub fn setTaskRetryPolicy(self: *Scheduler, index: usize, policy: ScheduledTask.RetryPolicy) void
```

### setTaskDependency

Set a dependency for a task (it will only run if the dependency is running).

```zig
pub fn setTaskDependency(self: *Scheduler, index: usize, dependency_name: []const u8) !void
```

### getDiskUsage

Get current disk usage percentage for a path.

```zig
pub fn getDiskUsage(self: *Scheduler, path: []const u8) !u8
```

### getFreeSpace

Get free space in bytes for a path.

```zig
pub fn getFreeSpace(self: *Scheduler, path: []const u8) !u64
```

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

### resetStats

Reset all scheduler statistics to zero.

```zig
pub fn resetStats(self: *Scheduler) void
```

### setTelemetry

Set the telemetry instance for distributed tracing. When enabled, task executions create spans for observability.

```zig
pub fn setTelemetry(self: *Scheduler, telemetry: *Telemetry) void
```

**Parameters:**
- `telemetry`: Telemetry instance for tracing

### clearTelemetry

Disable telemetry tracing.

```zig
pub fn clearTelemetry(self: *Scheduler) void
```

### listTasks

Get list of all scheduled tasks.

```zig
pub fn listTasks(self: *const Scheduler) []const ScheduledTask
```

## Usage Example

```zig
const std = @import("std");
const logly = @import("logly");
const Scheduler = logly.Scheduler;
const SchedulerPresets = logly.SchedulerPresets;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create scheduler
    var scheduler = try Scheduler.init(allocator);
    defer scheduler.deinit();

    // Add daily cleanup task using Presets
    _ = try scheduler.addTask(
        "log_cleanup",
        .cleanup,
        SchedulerPresets.dailyAt(2, 30), // Daily at 2:30 AM
        SchedulerPresets.dailyCleanup("logs", 30), // Config helper
    );

    // Add hourly compression manually
    _ = try scheduler.addTask(
        "log_compression",
        .compression,
        .{ .interval = 3600 * 1000 }, // Every hour (ms)
        .{
            .path = "logs",
            .min_age_seconds = 3600, // Compress files older than 1 hour
            .file_pattern = "*.log",
        },
    );

    // Start scheduler
    try scheduler.start();
    defer scheduler.stop();

    // Check stats periodically
    const stats = scheduler.getStats();
    std.debug.print("Tasks executed: {d}\n", .{
        stats.tasks_executed,
    });
}
```

## Aliases

The Scheduler module provides convenience aliases:

| Alias | Method |
|-------|--------|
| `begin` | `start` |
| `end` | `stop` |
| `halt` | `stop` |
| `statistics` | `getStats` |

## Additional State Methods

- `taskCount() usize` - Returns number of scheduled tasks
- `isRunning() bool` - Returns true if scheduler is running
- `hasTasks() bool` - Returns true if any tasks are scheduled

## SchedulerPresets

Helper functions for creating common schedules and task configurations.

```zig
pub const SchedulerPresets = struct {
    // Schedules
    pub fn hourlyCompression() Schedule;
    pub fn everyMinutes(n: u64) Schedule;
    pub fn dailyAt(hour: u8, minute: u8) Schedule;
    pub fn every30Minutes() Schedule;
    pub fn every6Hours() Schedule;
    pub fn every12Hours() Schedule;
    pub fn dailyMidnight() Schedule;
    pub fn dailyMaintenance() Schedule;

    // Task Configurations
    pub fn dailyCleanup(path: []const u8, max_age_days: u64) TaskConfig;
};
```

## See Also

- [Compression API](compression.md) - Log compression
- [Rotation Guide](../guide/rotation.md) - Log rotation
- [Configuration Guide](../guide/configuration.md) - Full configuration options
- [Telemetry API](telemetry.md) - Distributed tracing integration

## Telemetry Integration

The scheduler supports optional telemetry integration for distributed tracing. When enabled, each task execution creates a span with relevant attributes.

### Setup

```zig
const logly = @import("logly");

// Create telemetry instance
var telemetry = try logly.Telemetry.init(allocator, .{
    .provider = .file,
    .exporter_file_path = "telemetry_spans.jsonl",
});
defer telemetry.deinit();

// Create scheduler with telemetry
var scheduler = try logly.Scheduler.init(allocator);
defer scheduler.deinit();

scheduler.setTelemetry(&telemetry);
```

### Span Attributes

Task execution spans include the following attributes:

| Attribute | Type | Description |
|-----------|------|-------------|
| `task.type` | string | Task type (cleanup, compression, etc.) |
| `task.priority` | string | Task priority level |
| `task.duration_ms` | integer | Execution duration in milliseconds |
| `cleanup.files_deleted` | integer | Files deleted (cleanup tasks) |
| `cleanup.bytes_freed` | integer | Bytes freed (cleanup tasks) |
| `compression.files` | integer | Files compressed (compression tasks) |
| `compression.bytes_saved` | integer | Bytes saved (compression tasks) |
| `health.healthy` | boolean | Health status (health_check tasks) |
| `metrics.log_count` | integer | Log count (metrics_snapshot tasks) |
| `metrics.error_count` | integer | Error count (metrics_snapshot tasks) |

### Telemetry Metrics

The scheduler also records counter and gauge metrics:

- `scheduler.tasks_executed` (counter): Incremented for each task execution
- `scheduler.task_duration_ms` (gauge): Task execution duration

### Example Output

```json
{
  "trace_id": "abc123...",
  "span_id": "def456...",
  "name": "log_cleanup",
  "kind": "internal",
  "status": "ok",
  "start_time": 1704067200000000000,
  "end_time": 1704067200500000000,
  "attributes": {
    "task.type": "cleanup",
    "task.priority": "normal",
    "task.duration_ms": 500,
    "cleanup.files_deleted": 5,
    "cleanup.bytes_freed": 1048576
  }
}
```

