---
title: Scheduler API
description: API reference for scheduled log maintenance in Logly.zig.
head:
  - - meta
    - name: keywords
      content: scheduler api, cleanup, compression, schedule, task management, maintenance
  - - meta
    - property: og:title
      content: Scheduler API | Logly.zig
  - - meta
    - property: og:image
      content: https://muhammad-fiaz.github.io/logly.zig/cover.png
---

# Scheduler API

The `Scheduler` type runs log-maintenance tasks on interval, daily, cron-style, or one-shot schedules.

## Overview

```zig
const logly = @import("logly");

const scheduler = try logly.Scheduler.init(allocator);
defer scheduler.deinit();

_ = try scheduler.addTask(
    "cleanup",
    .cleanup,
    .{ .daily = .{ .hour = 2, .minute = 0 } },
    .{ .path = "logs", .maxAgeSeconds = 7 * 24 * 60 * 60 },
);

try scheduler.start();
defer scheduler.stop();
```

`start()` spawns the scheduling thread. `stop()` joins it. `deinit()` calls `stop()` and releases all task storage.

## Types

### Scheduler

```zig
pub const Scheduler = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    tasks: std.ArrayList(*ScheduledTask),
    running: std.atomic.Value(bool),
    isPaused: std.atomic.Value(bool),
    thread: ?std.Thread,
    // ...
};
```

Read `isPaused` with `scheduler.isPaused.load(.acquire)`; use `pause()` and `unpause()` to change it safely.

### SchedulerConfig

`logly.SchedulerConfig` is `Config.SchedulerConfig`.

```zig
pub const SchedulerConfig = struct {
    io: ?std.Io = null,
    enabled: bool = false,
    cleanupMaxAgeDays: u64 = 7,
    maxFiles: ?usize = null,
    compressBeforeCleanup: bool = false,
    filePattern: []const u8 = "*.log",
    archiveRootDir: ?[]const u8 = null,
    createDateSubdirs: bool = false,
    compressionAlgorithm: CompressionAlgorithm = .gzip,
    compressionLevel: CompressionLevel = .default,
    keepOriginals: bool = false,
    archiveFilePrefix: ?[]const u8 = null,
    archiveFileSuffix: ?[]const u8 = null,
    preserveDirStructure: bool = true,
    cleanEmptyDirs: bool = false,
    minAgeDaysForCompression: u64 = 1,
    maxConcurrentCompressions: usize = 2,
};
```

Methods: `maintenance(logsPath)`, `withCleanupDays(days)`, `withMaxFiles(count)`, and `withCompression(algorithm)` return modified copies with `enabled = true`.

### ScheduledTask

```zig
pub const ScheduledTask = struct {
    name: []const u8,
    taskType: TaskType,
    schedule: Schedule,
    callback: ?*const fn (*ScheduledTask) anyerror!void = null,
    lastRun: i64 = 0,
    nextRun: i64 = 0,
    runCount: u64 = 0,
    errorCount: u64 = 0,
    retriesRemaining: u32 = 0,
    enabled: bool = true,
    running: std.atomic.Value(bool),
    removed: bool = false,
    priority: Priority = .normal,
    retryPolicy: RetryPolicy = .{},
    dependsOn: ?[]const u8 = null,
    config: TaskConfig = .{},
};
```

`Priority` values: `low`, `normal`, `high`, `critical`.

`RetryPolicy` fields: `maxRetries` (default `3`), `intervalMs` (default `5000`), and `backoffMultiplier` (default `1.5`).

### TaskType

```zig
pub const TaskType = enum {
    cleanup,
    rotation,
    compression,
    flush,
    custom,
    healthCheck,
    metricsSnapshot,
};
```

### TaskConfig

```zig
pub const TaskConfig = struct {
    path: ?[]const u8 = null,
    maxAgeSeconds: u64 = 604800,
    maxFiles: ?usize = null,
    maxTotalSize: ?u64 = null,
    minAgeSeconds: u64 = 0,
    maxRetries: u32 = 0,
    retryBackoffMs: u64 = 0,
    filePattern: ?[]const u8 = null,
    compressBeforeDelete: bool = false,
    compressAndKeep: bool = false,
    compressOnly: bool = false,
    skipAlreadyCompressed: bool = true,
    recursive: bool = false,
    triggerDiskUsagePercent: ?u8 = null,
    minFreeSpaceBytes: ?u64 = null,
};
```

Helpers: `fromCentralized(SchedulerConfig)`, `withPath(path)`, `withMaxAgeDays(days)`, and `withFilePattern(pattern)` return modified copies.

### Schedule

```zig
pub const Schedule = union(enum) {
    once: u64,          // delay in milliseconds
    interval: u64,      // period in milliseconds
    daily: DailySchedule,
    cron: CronSchedule,

    pub const DailySchedule = struct {
        hour: u8 = 0,
        minute: u8 = 0,
    };

    pub const CronSchedule = struct {
        minute: ?u8 = null,
        hour: ?u8 = null,
        dayOfMonth: ?u8 = null,
        month: ?u8 = null,
        dayOfWeek: ?u8 = null, // 0 = Sunday
    };
};
```

`nextRunTime(fromTime)` returns the next timestamp in milliseconds. Unset cron fields match any value.

### TaskSnapshot

```zig
pub const TaskSnapshot = struct {
    name: []const u8,
    taskType: TaskType,
    enabled: bool,
    running: bool,
    nextRun: i64,
    lastRun: i64,
    runCount: u64,
    errorCount: u64,
    retriesRemaining: u32,
};
```

### SchedulerStats

```zig
pub const SchedulerStats = struct {
    tasksExecuted: std.atomic.Value(u64),
    tasksFailed: std.atomic.Value(u64),
    filesCleaned: std.atomic.Value(u64),
    filesCompressed: std.atomic.Value(u64),
    bytesFreed: std.atomic.Value(u64),
    bytesSaved: std.atomic.Value(u64),
    lastRunTime: std.atomic.Value(i64),
    startTime: std.atomic.Value(i64),
};
```

Methods: `successRate()`, `failureRate()`, `hasFailures()`, `getExecuted()`, `getFailed()`, `getFilesCleaned()`, `getFilesCompressed()`, `getBytesFreed()`, `getBytesSaved()`, `uptimeSeconds()`, `tasksPerHour()`, and `compressionRatio()`.

### HealthStatus and MetricsSnapshot

```zig
pub const HealthStatus = struct {
    healthy: bool = true,
    diskSpaceOk: bool = true,
    memoryOk: bool = true,
    writeLatencyMs: u64 = 0,
    message: ?[]const u8 = null,
};

pub const MetricsSnapshot = struct {
    timestamp: i64 = 0,
    logCount: u64 = 0,
    bytesWritten: u64 = 0,
    errorCount: u64 = 0,
    avgLatencyMs: f64 = 0,
};
```

## Lifecycle

### init

```zig
pub fn init(allocator: std.mem.Allocator) !*Scheduler
```

Creates a scheduler using the default single-threaded I/O handle.

### initWithIo

```zig
pub fn initWithIo(allocator: std.mem.Allocator, io_handle: std.Io) !*Scheduler
```

Creates a scheduler with an explicit I/O handle.

### initWithThreadPool

```zig
pub fn initWithThreadPool(allocator: std.mem.Allocator, threadPool: *ThreadPool) !*Scheduler
```

Creates a scheduler that dispatches tasks through an existing thread pool.

### initFromConfig

```zig
pub fn initFromConfig(
    allocator: std.mem.Allocator,
    config: SchedulerConfig,
    logsPath: ?[]const u8,
) !*Scheduler
```

Creates a scheduler from centralized configuration. When `config.enabled` is true and `logsPath` is set, an `auto_cleanup` task is registered for 02:00 daily using `TaskConfig.fromCentralized(config)`.

### deinit

```zig
pub fn deinit(self: *Scheduler) void
```

Stops the scheduler, destroys all tasks, and releases owned memory.

### start

```zig
pub fn start(self: *Scheduler) !void
```

Starts the scheduling thread. Calling `start()` while already running is a no-op.

### stop

```zig
pub fn stop(self: *Scheduler) void
```

Stops the scheduling thread and joins it. Calling `stop()` while stopped is a no-op.

### pause / unpause

```zig
pub fn pause(self: *Scheduler) void
pub fn unpause(self: *Scheduler) void
```

Pauses and resumes task execution without removing tasks.

### isRunning / hasTasks

```zig
pub fn isRunning(self: *const Scheduler) bool
pub fn hasTasks(self: *const Scheduler) bool
```

## Task Creation

### addTask

```zig
pub fn addTask(
    self: *Scheduler,
    name: []const u8,
    taskType: TaskType,
    schedule: Schedule,
    config: ScheduledTask.TaskConfig,
) !usize
```

Registers a task and returns its index. The scheduler copies `name`, `config.path`, and `config.filePattern`.

### addCleanupTask

```zig
pub fn addCleanupTask(
    self: *Scheduler,
    name: []const u8,
    path: []const u8,
    maxAgeDays: u64,
    schedule: Schedule,
) !usize
```

Registers a `.cleanup` task with a `*.log` pattern.

### addCompressionTask

```zig
pub fn addCompressionTask(
    self: *Scheduler,
    name: []const u8,
    path: []const u8,
    schedule: Schedule,
) !usize
```

Registers a `.compression` task with a `*.log` pattern.

### addCustomTask

```zig
pub fn addCustomTask(
    self: *Scheduler,
    name: []const u8,
    schedule: Schedule,
    callback: *const fn (*ScheduledTask) anyerror!void,
) !usize
```

Registers a `.custom` task with a callback.

### addCustomTaskWithConfig

```zig
pub fn addCustomTaskWithConfig(
    self: *Scheduler,
    name: []const u8,
    schedule: Schedule,
    callback: *const fn (*ScheduledTask) anyerror!void,
    config: ScheduledTask.TaskConfig,
) !usize
```

Registers a `.custom` task with callback and task configuration.

## Task Configuration

### setTaskPriority

```zig
pub fn setTaskPriority(self: *Scheduler, index: usize, priority: ScheduledTask.Priority) void
```

### setTaskRetryPolicy

```zig
pub fn setTaskRetryPolicy(self: *Scheduler, index: usize, policy: ScheduledTask.RetryPolicy) void
```

### setTaskDependency

```zig
pub fn setTaskDependency(self: *Scheduler, index: usize, dependencyName: []const u8) !void
```

Copies `dependencyName`. The dependency must exist in the same scheduler.

### validateDependencies

```zig
pub fn validateDependencies(self: *Scheduler) !void
```

Returns an error if a dependency name is missing or if dependencies form a cycle.

### setTaskSchedule

```zig
pub fn setTaskSchedule(self: *Scheduler, index: usize, schedule: Schedule) bool
```

Updates the schedule and returns `false` when `index` is out of range.

### rescheduleNow

```zig
pub fn rescheduleNow(self: *Scheduler, index: usize) bool
```

Makes the task runnable immediately and returns `false` when `index` is out of range.

## Task Control

### setTaskEnabled

```zig
pub fn setTaskEnabled(self: *Scheduler, index: usize, enabled: bool) void
```

### setTaskEnabledByName

```zig
pub fn setTaskEnabledByName(self: *Scheduler, name: []const u8, enabled: bool) bool
```

Returns `false` when no task has that name.

### removeTask

```zig
pub fn removeTask(self: *Scheduler, index: usize) void
```

### removeTaskByName

```zig
pub fn removeTaskByName(self: *Scheduler, name: []const u8) bool
```

Returns `true` when a task was removed.

### runNow

```zig
pub fn runNow(self: *Scheduler, index: usize) !void
```

Runs a task immediately. Returns an error when `index` is out of range.

### runNowByName

```zig
pub fn runNowByName(self: *Scheduler, name: []const u8) !bool
```

Runs the named task immediately. Returns `false` when the task does not exist.

### runPending

```zig
pub fn runPending(self: *Scheduler) void
```

Runs all tasks whose next run time has elapsed.

### taskIndexByName

```zig
pub fn taskIndexByName(self: *Scheduler, name: []const u8) ?usize
```

### hasTaskNamed

```zig
pub fn hasTaskNamed(self: *Scheduler, name: []const u8) bool
```

## Inspection

### getTasks / taskCount

```zig
pub fn getTasks(self: *const Scheduler) []const *ScheduledTask
pub fn taskCount(self: *const Scheduler) usize
```

`getTasks()` returns borrowed pointers. Do not free them or retain them after the task is removed or the scheduler is deinitialized.

### getTaskSnapshot / getTaskSnapshotByName

```zig
pub fn getTaskSnapshot(self: *Scheduler, index: usize) ?TaskSnapshot
pub fn getTaskSnapshotByName(self: *Scheduler, name: []const u8) ?TaskSnapshot
```

Returns an immutable copy of task state.

### Counts

```zig
pub fn enabledTaskCount(self: *Scheduler) usize
pub fn runningTaskCount(self: *Scheduler) usize
pub fn readyTaskCount(self: *Scheduler) usize
```

### nextRunInMs / nextRunInMsByName

```zig
pub fn nextRunInMs(self: *Scheduler, index: usize) ?i64
pub fn nextRunInMsByName(self: *Scheduler, name: []const u8) ?i64
```

Returns the remaining delay in milliseconds, or `null` when the task does not exist.

## Callbacks

```zig
pub fn setTaskStartedCallback(self: *Scheduler, callback: *const fn ([]const u8, u64) void) void
pub fn setTaskCompletedCallback(self: *Scheduler, callback: *const fn ([]const u8, u64) void) void
pub fn setTaskErrorCallback(self: *Scheduler, callback: *const fn ([]const u8, []const u8) void) void
pub fn setScheduleTickCallback(self: *Scheduler, callback: *const fn (u32, u32) void) void
pub fn setHealthCheckCallback(self: *Scheduler, callback: *const fn (*const HealthStatus) void) void
pub fn setHealthCallback(self: *Scheduler, callback: *const fn () HealthStatus) void
pub fn setMetricsCallback(self: *Scheduler, callback: *const fn () MetricsSnapshot) void
```

Started and completed callbacks receive the task name and an index or elapsed milliseconds. Error callbacks receive the task name and error message. Tick callbacks receive executed and pending counts.

## Health and Metrics

```zig
pub fn getHealthStatus(self: *Scheduler) HealthStatus
pub fn getMetrics(self: *Scheduler) MetricsSnapshot
```

Without a callback, `getHealthStatus()` performs a basic disk-space check on the working directory and `getMetrics()` returns a snapshot derived from scheduler state.

## Statistics and Telemetry

```zig
pub fn getStats(self: *const Scheduler) SchedulerStats
pub fn resetStats(self: *Scheduler) void
pub fn setTelemetry(self: *Scheduler, telemetry: *Telemetry) void
pub fn clearTelemetry(self: *Scheduler) void
```

When telemetry is attached, task executions emit spans and metrics through the scheduler's telemetry integration.

## SchedulerPresets

### Schedule presets

```zig
pub fn weeklyCleanup() Schedule
pub fn hourlyCompression() Schedule
pub fn everyMinutes(n: u64) Schedule
pub fn dailyAt(hour: u8, minute: u8) Schedule
pub fn every30Minutes() Schedule
pub fn every6Hours() Schedule
pub fn every12Hours() Schedule
pub fn dailyMidnight() Schedule
pub fn dailyMaintenance() Schedule
pub fn every15Minutes() Schedule
pub fn onceAfter(seconds: u64) Schedule
pub fn healthCheckSchedule() Schedule
pub fn metricsSchedule() Schedule
```

### TaskConfig presets

```zig
pub fn dailyCleanup(path: []const u8, maxAgeDays: u64) TaskConfig
pub fn createScheduledSink(filePath: []const u8, rotation: []const u8) SinkConfig
pub fn weeklyCleanupConfig(path: []const u8, maxAgeDays: u64) TaskConfig
pub fn compressThenDelete(path: []const u8, minAgeDays: u64) TaskConfig
pub fn compressAndKeep(path: []const u8, minAgeDays: u64) TaskConfig
pub fn compressOnly(path: []const u8, minAgeDays: u64) TaskConfig
pub fn archiveOldLogs(path: []const u8, compressAfterDays: u64, deleteAfterDays: u64) TaskConfig
pub fn aggressiveCleanup(path: []const u8, maxAgeDays: u64, maxFiles: usize) TaskConfig
pub fn hourlyArchive(path: []const u8) TaskConfig
pub fn compressOnRotation(path: []const u8) TaskConfig
pub fn sizeBasedCompression(path: []const u8, maxTotalBytes: u64) TaskConfig
pub fn diskUsageTriggered(path: []const u8, diskUsagePercent: u8) TaskConfig
pub fn lowDiskSpaceTriggered(path: []const u8, minFreeBytes: u64) TaskConfig
pub fn recursiveCompression(path: []const u8, minAgeDays: u64) TaskConfig
```

## See Also

- [Scheduler Guide](/guide/scheduler)
- [Scheduler Example](/examples/scheduler)
- [Compression API](/api/compression)
