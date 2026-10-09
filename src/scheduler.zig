//! Task scheduler.
//!
//! Runs maintenance (cleanup, rotation, compression) on interval, daily, or cron schedules.
const std = @import("std");
const Config = @import("config.zig").Config;
const Compression = @import("compression.zig").Compression;
const SinkConfig = @import("sink.zig").SinkConfig;
const ThreadPool = @import("thread_pool.zig").ThreadPool;
const Constants = @import("constants.zig");
const Utils = @import("utils.zig");
const Telemetry = @import("telemetry.zig").Telemetry;
const Span = @import("telemetry.zig").Span;
const SpanKind = @import("telemetry.zig").SpanKind;
const SpanAttribute = @import("telemetry.zig").SpanAttribute;

/// Scheduler for automated log maintenance tasks.
///
/// Provides scheduled execution of tasks like log cleanup, rotation,
/// compression, and custom maintenance operations. Supports multiple
/// schedule types including one-time, interval, daily, and cron-like.
pub const Scheduler = struct {
    /// Memory allocator for internal operations.
    allocator: std.mem.Allocator,
    /// Explicit I/O handle.
    io: std.Io = Utils.defaultIo(),
    /// List of scheduled tasks.
    tasks: std.ArrayList(ScheduledTask),
    /// Whether the scheduler is currently running.
    running: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    /// Whether the scheduler is paused.
    isPaused: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    /// Background worker thread for task execution.
    workerThread: ?std.Thread = null,
    /// Mutex for thread-safe access to tasks.
    mutex: std.Io.Mutex = std.Io.Mutex.init,
    /// Condition variable for worker thread signaling.
    condition: std.Io.Condition = .init,
    /// Wakeup generation bumped on every schedule mutation so the worker
    /// loop re-evaluates deadlines instead of sleeping through them.
    wakeGeneration: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    /// Scheduler statistics (tasks executed, failed, etc.).
    stats: SchedulerStats,
    /// Compression utility for compression tasks.
    compression: Compression,
    /// Whether compression has been initialized.
    compressionInitialized: bool = false,
    /// Optional thread pool for parallel task execution.
    threadPool: ?*ThreadPool = null,
    /// Callback for health status checks.
    healthCallback: ?*const fn () HealthStatus = null,
    /// Callback for metrics collection.
    metricsCallback: ?*const fn () MetricsSnapshot = null,

    /// Callback invoked when a task starts execution.
    onTaskStarted: ?*const fn ([]const u8, u64) void = null,

    /// Callback invoked when a task completes successfully.
    onTaskCompleted: ?*const fn ([]const u8, u64) void = null,

    /// Callback invoked when a task encounters an error.
    onTaskError: ?*const fn ([]const u8, []const u8) void = null,

    /// Callback invoked on each scheduler cycle.
    onScheduleTick: ?*const fn (u32, u32) void = null,

    /// Callback invoked during health checks.
    onHealthCheck: ?*const fn (*const HealthStatus) void = null,

    /// Optional telemetry instance for distributed tracing.
    /// When enabled, task executions create spans for observability.
    telemetry: ?*Telemetry = null,

    /// Centralized scheduler configuration.
    /// Re-exports centralized config for convenience.
    pub const SchedulerConfig = Config.SchedulerConfig;

    /// Health status returned by health checks.
    pub const HealthStatus = struct {
        healthy: bool = true,
        diskSpaceOk: bool = true,
        memoryOk: bool = true,
        writeLatencyMs: u64 = 0,
        message: ?[]const u8 = null,
    };

    /// Metrics snapshot for monitoring.
    pub const MetricsSnapshot = struct {
        timestamp: i64 = 0,
        logCount: u64 = 0,
        bytesWritten: u64 = 0,
        errorCount: u64 = 0,
        avgLatencyMs: f64 = 0,
    };

    /// A scheduled task configuration.
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
        running: bool = false,
        priority: Priority = .normal,
        retryPolicy: RetryPolicy = .{},
        dependsOn: ?[]const u8 = null,
        config: TaskConfig = .{},

        /// Task execution priority.
        pub const Priority = enum {
            /// Lowest priority task.
            low,
            /// Default task priority.
            normal,
            /// High priority task.
            high,
            /// Critical priority task.
            critical,
        };

        /// Retry behavior for failed task executions.
        pub const RetryPolicy = struct {
            maxRetries: u32 = 3,
            intervalMs: u32 = Constants.SchedulerDefaults.retryIntervalMs,
            backoffMultiplier: f32 = 1.5,
        };

        /// Task-specific configuration.
        pub const TaskConfig = struct {
            /// Path for file-based tasks
            path: ?[]const u8 = null,
            /// Maximum age in seconds for cleanup
            maxAgeSeconds: u64 = Constants.SchedulerDefaults.maxAgeSeconds,
            /// Maximum files to keep
            maxFiles: ?usize = null,
            /// Maximum total size in bytes
            maxTotalSize: ?u64 = null,
            /// Minimum age in seconds (useful for compression - e.g. compress files older than 1 day)
            minAgeSeconds: u64 = 0,
            /// Maximum number of retries
            maxRetries: u32 = 0,
            /// Retry backoff time in milliseconds
            retryBackoffMs: u64 = 0,
            /// File pattern to match (e.g., "*.log")
            filePattern: ?[]const u8 = null,
            /// Compress files before cleanup (compress then delete)
            compressBeforeDelete: bool = false,
            /// Compress files and keep both original and compressed (archive mode)
            compressAndKeep: bool = false,
            /// Only compress files, don't delete any (pure archival)
            compressOnly: bool = false,
            /// Skip files that are already compressed (.gz, .lgz, .zst)
            skipAlreadyCompressed: bool = true,
            /// Recursive directory processing
            recursive: bool = false,
            /// Trigger task only if disk usage exceeds this percentage (0-100, null to disable)
            triggerDiskUsagePercent: ?u8 = null,
            /// Required free space in bytes before running task
            minFreeSpaceBytes: ?u64 = null,

            /// Create from centralized Config.SchedulerConfig.
            pub fn fromCentralized(cfg: SchedulerConfig) TaskConfig {
                return .{
                    .maxAgeSeconds = cfg.cleanupMaxAgeDays * Constants.TimeConstants.secondsPerDay,
                    .maxFiles = cfg.maxFiles,
                    .filePattern = cfg.filePattern,
                    .compressBeforeDelete = cfg.compressBeforeCleanup,
                };
            }

            /// Returns a copy with the specified path.
            pub fn withPath(self: TaskConfig, path: []const u8) TaskConfig {
                var result = self;
                result.path = path;
                return result;
            }

            /// Returns a copy with the specified max age in days.
            pub fn withMaxAgeDays(self: TaskConfig, days: u64) TaskConfig {
                var result = self;
                result.maxAgeSeconds = days * Constants.TimeConstants.secondsPerDay;
                return result;
            }

            /// Returns a copy with the specified file pattern.
            pub fn withFilePattern(self: TaskConfig, pattern: []const u8) TaskConfig {
                var result = self;
                result.filePattern = pattern;
                return result;
            }
        };
    };

    /// Immutable task state snapshot for introspection APIs.
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

    /// Types of scheduled tasks.
    pub const TaskType = enum {
        /// Clean up old log files
        cleanup,
        /// Rotate log files
        rotation,
        /// Compress log files
        compression,
        /// Flush all sinks
        flush,
        /// Custom user-defined task
        custom,
        /// Health check
        healthCheck,
        /// Metrics collection
        metricsSnapshot,
    };

    /// Schedule configuration.
    pub const Schedule = union(enum) {
        /// Run once after delay (in milliseconds)
        once: u64,
        /// Run at fixed intervals (in milliseconds)
        interval: u64,
        /// Run at specific time of day (hours, minutes)
        daily: DailySchedule,
        /// Cron-like schedule
        cron: CronSchedule,

        /// Daily trigger schedule.
        pub const DailySchedule = struct {
            hour: u8 = 0,
            minute: u8 = 0,
        };

        /// Cron-style trigger schedule.
        pub const CronSchedule = struct {
            minute: ?u8 = null, // 0-59 or null for any
            hour: ?u8 = null, // 0-23 or null for any
            dayOfMonth: ?u8 = null, // 1-31 or null for any
            month: ?u8 = null, // 1-12 or null for any
            dayOfWeek: ?u8 = null, // 0-6 (Sunday=0) or null for any
        };

        /// Calculates the next run time from now.
        pub fn nextRunTime(self: Schedule, fromTime: i64) i64 {
            const nowMs = fromTime;
            return switch (self) {
                .once => |delay| nowMs + @as(i64, @intCast(delay)),
                .interval => |interval| nowMs + @as(i64, @intCast(interval)),
                .daily => |daily| blk: {
                    const nowSec = Utils.currentSeconds();
                    const epoch = std.time.epoch.EpochSeconds{ .secs = @intCast(nowSec) };
                    const daySeconds = epoch.getDaySeconds();

                    const targetSeconds = @as(u64, daily.hour) * @as(u64, Constants.TimeConstants.secondsPerHour) + @as(u64, daily.minute) * @as(u64, Constants.TimeConstants.secondsPerMinute);
                    const currentSeconds = daySeconds.secs;

                    if (currentSeconds < targetSeconds) {
                        // Today
                        break :blk nowMs + @as(i64, @intCast((targetSeconds - currentSeconds) * @as(u64, Constants.TimeConstants.msPerSecond)));
                    } else {
                        // Tomorrow
                        break :blk nowMs + @as(i64, @intCast((@as(u64, Constants.TimeConstants.secondsPerDay) - currentSeconds + targetSeconds) * @as(u64, Constants.TimeConstants.msPerSecond)));
                    }
                },
                .cron => |cron| blk: {
                    var checkTime = nowMs + Constants.SchedulerDefaults.cronFallbackIntervalMs;
                    // Find closest match within the next 30 days
                    const limit = nowMs + @as(i64, @intCast(30 * @as(u64, Constants.TimeConstants.secondsPerDay) * @as(u64, Constants.TimeConstants.msPerSecond)));
                    while (checkTime < limit) : (checkTime += @as(i64, @intCast(@as(u64, Constants.TimeConstants.secondsPerMinute) * @as(u64, Constants.TimeConstants.msPerSecond)))) {
                        const sec = @divFloor(checkTime, @as(i64, @intCast(Constants.TimeConstants.msPerSecond)));
                        const epoch = std.time.epoch.EpochSeconds{ .secs = @intCast(sec) };
                        const day = epoch.getEpochDay();
                        const yearDay = day.calculateYearDay();
                        const monthDay = yearDay.calculateMonthDay();
                        const daySec = epoch.getDaySeconds();

                        const minute = @divFloor(daySec.secs % @as(u64, Constants.TimeConstants.secondsPerHour), @as(u64, Constants.TimeConstants.secondsPerMinute));
                        const hour = @divFloor(daySec.secs, @as(u64, Constants.TimeConstants.secondsPerHour));
                        const month = monthDay.month.numeric();
                        const mday = monthDay.day_index + 1;
                        // Unix epoch (Jan 1, 1970) was a Thursday (4)
                        const wday = @as(u8, @intCast((day.day + 4) % 7));

                        if (cron.minute != null and cron.minute.? != minute) continue;
                        if (cron.hour != null and cron.hour.? != hour) continue;
                        if (cron.month != null and cron.month.? != month) continue;
                        if (cron.dayOfMonth != null and cron.dayOfMonth.? != mday) continue;
                        if (cron.dayOfWeek != null and cron.dayOfWeek.? != wday) continue;

                        break :blk checkTime;
                    }
                    break :blk nowMs + Constants.SchedulerDefaults.cronFallbackIntervalMs; // Fallback
                },
            };
        }
    };

    /// Statistics for scheduler operations with atomic counters for thread safety.
    pub const SchedulerStats = struct {
        /// Total tasks executed successfully.
        tasksExecuted: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        /// Total tasks that failed.
        tasksFailed: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        /// Total files cleaned up.
        filesCleaned: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        /// Total files compressed.
        filesCompressed: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        /// Total bytes freed by cleanup operations.
        bytesFreed: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        /// Total bytes saved by compression.
        bytesSaved: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        /// Last run time in milliseconds (uses AtomicSigned for 32-bit platform compatibility).
        lastRunTime: std.atomic.Value(Constants.AtomicSigned) = std.atomic.Value(Constants.AtomicSigned).init(0),
        /// Scheduler start time for uptime calculation (uses AtomicSigned for 32-bit platform compatibility).
        startTime: std.atomic.Value(Constants.AtomicSigned) = std.atomic.Value(Constants.AtomicSigned).init(0),

        /// Calculate task success rate (0.0 - 1.0).
        pub fn successRate(self: *const SchedulerStats) f64 {
            const executed = Utils.atomicLoadU64(&self.tasksExecuted);
            const failed = Utils.atomicLoadU64(&self.tasksFailed);
            const total = executed + failed;
            return Utils.calculateRate(executed, total);
        }

        /// Calculate task failure rate (0.0 - 1.0).
        pub fn failureRate(self: *const SchedulerStats) f64 {
            const executed = Utils.atomicLoadU64(&self.tasksExecuted);
            const failed = Utils.atomicLoadU64(&self.tasksFailed);
            return Utils.calculateErrorRate(failed, executed + failed);
        }

        /// Returns true if any tasks have failed.
        pub fn hasFailures(self: *const SchedulerStats) bool {
            return Utils.atomicLoadU64(&self.tasksFailed) > 0;
        }

        /// Returns total tasks executed as u64.
        pub fn getExecuted(self: *const SchedulerStats) u64 {
            return Utils.atomicLoadU64(&self.tasksExecuted);
        }

        /// Returns total tasks failed as u64.
        pub fn getFailed(self: *const SchedulerStats) u64 {
            return Utils.atomicLoadU64(&self.tasksFailed);
        }

        /// Returns total files cleaned as u64.
        pub fn getFilesCleaned(self: *const SchedulerStats) u64 {
            return Utils.atomicLoadU64(&self.filesCleaned);
        }

        /// Returns total files compressed as u64.
        pub fn getFilesCompressed(self: *const SchedulerStats) u64 {
            return Utils.atomicLoadU64(&self.filesCompressed);
        }

        /// Returns total bytes freed as u64.
        pub fn getBytesFreed(self: *const SchedulerStats) u64 {
            return Utils.atomicLoadU64(&self.bytesFreed);
        }

        /// Returns total bytes saved by compression as u64.
        pub fn getBytesSaved(self: *const SchedulerStats) u64 {
            return Utils.atomicLoadU64(&self.bytesSaved);
        }

        /// Returns uptime in seconds since scheduler started.
        pub fn uptimeSeconds(self: *const SchedulerStats) i64 {
            const startTs = self.startTime.load(.monotonic);
            if (startTs == 0) return 0;
            return @intCast(Utils.elapsedSeconds(startTs));
        }

        /// Returns average tasks per hour.
        pub fn tasksPerHour(self: *const SchedulerStats) f64 {
            const uptime = self.uptimeSeconds();
            if (uptime <= 0) return 0;
            const executed = Utils.atomicLoadU64(&self.tasksExecuted);
            const hours = @as(f64, @floatFromInt(uptime)) / 3600.0;
            return Utils.safeFloatDiv(@as(f64, @floatFromInt(executed)), hours);
        }

        /// Calculate compression ratio (bytes saved / total bytes).
        pub fn compressionRatio(self: *const SchedulerStats) f64 {
            const saved = Utils.atomicLoadU64(&self.bytesSaved);
            const freed = Utils.atomicLoadU64(&self.bytesFreed);
            return Utils.calculateRate(saved, saved + freed);
        }
    };

    /// Cleanup result information.
    pub const CleanupResult = struct {
        filesDeleted: usize = 0,
        filesCompressed: usize = 0,
        bytesFreed: u64 = 0,
        errors: usize = 0,
    };

    /// Initializes a new Scheduler using default I/O.
    pub fn init(allocator: std.mem.Allocator) !*Scheduler {
        return initWithIo(allocator, Utils.defaultIo());
    }

    /// Initializes a new Scheduler with an explicit I/O handle.
    pub fn initWithIo(allocator: std.mem.Allocator, io_handle: std.Io) !*Scheduler {
        const self = try allocator.create(Scheduler);
        self.* = .{
            .allocator = allocator,
            .io = io_handle,
            .tasks = .empty,
            .stats = .{},
            .compression = Compression.init(allocator),
            .compressionInitialized = true,
            .healthCallback = null,
            .metricsCallback = null,
        };

        return self;
    }

    /// Initializes a new Scheduler with a ThreadPool.
    pub fn initWithThreadPool(allocator: std.mem.Allocator, threadPool: *ThreadPool) !*Scheduler {
        const self = try initWithIo(allocator, threadPool.io);
        self.threadPool = threadPool;
        return self;
    }

    /// Initializes a Scheduler from global Config.SchedulerConfig.
    pub fn initFromConfig(allocator: std.mem.Allocator, config: SchedulerConfig, logsPath: ?[]const u8) !*Scheduler {
        const io_handle = config.io orelse Utils.defaultIo();
        const self = try initWithIo(allocator, io_handle);
        errdefer self.deinit();

        // If scheduler is enabled and path is provided, auto-setup default cleanup task
        if (config.enabled) {
            if (logsPath) |path| {
                _ = try self.addTask(
                    "auto_cleanup",
                    .cleanup,
                    .{ .daily = .{ .hour = 2, .minute = 0 } }, // Run at 2 AM daily
                    ScheduledTask.TaskConfig.fromCentralized(config).withPath(path),
                );
            }
        }

        return self;
    }

    /// Releases all resources.
    pub fn deinit(self: *Scheduler) void {
        self.stop();

        // Deinit compression if initialized
        if (self.compressionInitialized) {
            self.compression.deinit();
        }

        for (self.tasks.items) |*task| {
            self.allocator.free(task.name);
            if (task.config.path) |p| self.allocator.free(p);
            if (task.config.filePattern) |p| self.allocator.free(p);
            if (task.dependsOn) |p| self.allocator.free(p);
        }
        self.tasks.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    /// Sets health check callback.
    pub fn setHealthCallback(self: *Scheduler, callback: *const fn () HealthStatus) void {
        self.healthCallback = callback;
    }

    /// Sets metrics callback.
    pub fn setMetricsCallback(self: *Scheduler, callback: *const fn () MetricsSnapshot) void {
        self.metricsCallback = callback;
    }

    /// Gets current health status.
    pub fn getHealthStatus(self: *Scheduler) HealthStatus {
        if (self.healthCallback) |cb| {
            return cb();
        }
        // Default health check - check disk space on current directory
        return self.performBasicHealthCheck();
    }

    /// Gets current metrics snapshot.
    pub fn getMetrics(self: *Scheduler) MetricsSnapshot {
        if (self.metricsCallback) |cb| {
            return cb();
        }
        return .{
            .timestamp = Utils.currentMillis(),
            .logCount = self.stats.getExecuted(),
            .errorCount = self.stats.getFailed(),
        };
    }

    fn performBasicHealthCheck(self: *Scheduler) HealthStatus {
        var status = HealthStatus{};

        // Check if we can write to current directory
        const testFile = std.Io.Dir.cwd().createFile(self.io, ".health_check_temp", .{}) catch {
            status.healthy = false;
            status.message = "Cannot write to disk";
            return status;
        };
        testFile.close(self.io);
        std.Io.Dir.cwd().deleteFile(self.io, ".health_check_temp") catch {};

        return status;
    }

    /// Adds a scheduled task.
    pub fn addTask(
        self: *Scheduler,
        name: []const u8,
        taskType: TaskType,
        schedule: Schedule,
        config: ScheduledTask.TaskConfig,
    ) !usize {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);

        const ownedName = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(ownedName);

        var ownedConfig = config;
        if (config.path) |p| {
            ownedConfig.path = try self.allocator.dupe(u8, p);
        }
        errdefer if (ownedConfig.path) |p| self.allocator.free(p);

        if (config.filePattern) |p| {
            ownedConfig.filePattern = try self.allocator.dupe(u8, p);
        }
        errdefer if (ownedConfig.filePattern) |p| self.allocator.free(p);

        const now = Utils.currentMillis();
        const task = ScheduledTask{
            .name = ownedName,
            .taskType = taskType,
            .schedule = schedule,
            .nextRun = schedule.nextRunTime(now),
            .config = ownedConfig,
            .retriesRemaining = if (ownedConfig.maxRetries > 0) ownedConfig.maxRetries else 3,
            .retryPolicy = if (ownedConfig.maxRetries > 0) .{
                .maxRetries = ownedConfig.maxRetries,
                .intervalMs = @as(u32, @intCast(ownedConfig.retryBackoffMs)),
            } else .{},
        };

        try self.tasks.append(self.allocator, task);
        self.kick();
        return self.tasks.items.len - 1;
    }

    /// Configures priority for a specific task.
    pub fn setTaskPriority(self: *Scheduler, index: usize, priority: ScheduledTask.Priority) void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (index < self.tasks.items.len) {
            self.tasks.items[index].priority = priority;
        }
    }

    /// Configures retry policy for a specific task.
    pub fn setTaskRetryPolicy(self: *Scheduler, index: usize, policy: ScheduledTask.RetryPolicy) void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (index < self.tasks.items.len) {
            self.tasks.items[index].retryPolicy = policy;
            self.tasks.items[index].retriesRemaining = policy.maxRetries;
        }
    }

    /// Sets a dependency for a task.
    pub fn setTaskDependency(self: *Scheduler, index: usize, dependencyName: []const u8) !void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (index < self.tasks.items.len) {
            if (self.tasks.items[index].dependsOn) |p| self.allocator.free(p);
            self.tasks.items[index].dependsOn = try self.allocator.dupe(u8, dependencyName);
        }
    }

    /// Validates that every task dependency resolves and that no dependency cycle exists.
    ///
    /// Returns an error if a dependency name cannot be resolved or if following the
    /// dependency chain revisits a task.
    pub fn validateDependencies(self: *Scheduler) !void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);

        for (self.tasks.items, 0..) |task, startIndex| {
            _ = task;
            var currentIndex: usize = startIndex;
            var hops: usize = 0;

            while (true) {
                if (hops > self.tasks.items.len) return error.DependencyCycle;

                const currentTask = self.tasks.items[currentIndex];
                const depName = currentTask.dependsOn orelse break;

                var nextIndex: ?usize = null;
                for (self.tasks.items, 0..) |candidate, candidateIndex| {
                    if (std.mem.eql(u8, candidate.name, depName)) {
                        nextIndex = candidateIndex;
                        break;
                    }
                }

                const resolvedIndex = nextIndex orelse return error.MissingDependency;
                if (resolvedIndex == startIndex) return error.DependencyCycle;

                currentIndex = resolvedIndex;
                hops += 1;
            }
        }
    }

    /// Adds a cleanup task for old log files.
    pub fn addCleanupTask(
        self: *Scheduler,
        name: []const u8,
        path: []const u8,
        maxAgeDays: u64,
        schedule: Schedule,
    ) !usize {
        return self.addTask(name, .cleanup, schedule, .{
            .path = path,
            .maxAgeSeconds = maxAgeDays * Constants.TimeConstants.secondsPerDay,
            .filePattern = "*.log",
        });
    }

    /// Adds a compression task for log files.
    pub fn addCompressionTask(
        self: *Scheduler,
        name: []const u8,
        path: []const u8,
        schedule: Schedule,
    ) !usize {
        return self.addTask(name, .compression, schedule, .{
            .path = path,
            .filePattern = "*.log",
        });
    }

    /// Adds a custom callback task.
    pub fn addCustomTask(
        self: *Scheduler,
        name: []const u8,
        schedule: Schedule,
        callback: *const fn (*ScheduledTask) anyerror!void,
    ) !usize {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);

        const ownedName = try self.allocator.dupe(u8, name);
        const now = Utils.currentMillis();

        const task = ScheduledTask{
            .name = ownedName,
            .taskType = .custom,
            .schedule = schedule,
            .callback = callback,
            .nextRun = schedule.nextRunTime(now),
        };

        try self.tasks.append(self.allocator, task);
        return self.tasks.items.len - 1;
    }

    /// Adds a custom callback task with full configuration.
    pub fn addCustomTaskWithConfig(
        self: *Scheduler,
        name: []const u8,
        schedule: Schedule,
        callback: *const fn (*ScheduledTask) anyerror!void,
        config: ScheduledTask.TaskConfig,
    ) !usize {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);

        const ownedName = try self.allocator.dupe(u8, name);
        const now = Utils.currentMillis();

        const task = ScheduledTask{
            .name = ownedName,
            .taskType = .custom,
            .schedule = schedule,
            .callback = callback,
            .nextRun = schedule.nextRunTime(now),
            .config = config,
            .retriesRemaining = if (config.maxRetries > 0) config.maxRetries else 3,
            .retryPolicy = if (config.maxRetries > 0) .{
                .maxRetries = config.maxRetries,
                .intervalMs = @as(u32, @intCast(config.retryBackoffMs)),
            } else .{},
        };

        try self.tasks.append(self.allocator, task);
        return self.tasks.items.len - 1;
    }

    /// Enables or disables a task.
    pub fn setTaskEnabled(self: *Scheduler, index: usize, enabled: bool) void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (index < self.tasks.items.len) {
            self.tasks.items[index].enabled = enabled;
        }
        self.kick();
    }

    /// Removes a task by index.
    pub fn removeTask(self: *Scheduler, index: usize) void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (index < self.tasks.items.len) {
            const task = self.tasks.orderedRemove(index);
            self.allocator.free(task.name);
            if (task.config.path) |p| self.allocator.free(p);
            if (task.config.filePattern) |p| self.allocator.free(p);
            if (task.dependsOn) |p| self.allocator.free(p);
        }
        self.kick();
    }

    /// Finds a task index by name.
    pub fn taskIndexByName(self: *Scheduler, name: []const u8) ?usize {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);

        for (self.tasks.items, 0..) |task, i| {
            if (std.mem.eql(u8, task.name, name)) return i;
        }
        return null;
    }

    /// Returns task snapshot by index.
    pub fn getTaskSnapshot(self: *Scheduler, index: usize) ?TaskSnapshot {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);

        if (index >= self.tasks.items.len) return null;
        const task = self.tasks.items[index];
        return .{
            .name = task.name,
            .taskType = task.taskType,
            .enabled = task.enabled,
            .running = task.running,
            .nextRun = task.nextRun,
            .lastRun = task.lastRun,
            .runCount = task.runCount,
            .errorCount = task.errorCount,
            .retriesRemaining = task.retriesRemaining,
        };
    }

    /// Returns task snapshot by name.
    pub fn getTaskSnapshotByName(self: *Scheduler, name: []const u8) ?TaskSnapshot {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);

        for (self.tasks.items) |task| {
            if (std.mem.eql(u8, task.name, name)) {
                return .{
                    .name = task.name,
                    .taskType = task.taskType,
                    .enabled = task.enabled,
                    .running = task.running,
                    .nextRun = task.nextRun,
                    .lastRun = task.lastRun,
                    .runCount = task.runCount,
                    .errorCount = task.errorCount,
                    .retriesRemaining = task.retriesRemaining,
                };
            }
        }
        return null;
    }

    /// Returns true when a task with this name exists.
    pub fn hasTaskNamed(self: *Scheduler, name: []const u8) bool {
        return self.taskIndexByName(name) != null;
    }

    /// Enables or disables a task by task name.
    ///
    /// Returns true when task exists and was updated.
    pub fn setTaskEnabledByName(self: *Scheduler, name: []const u8, enabled: bool) bool {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);

        for (self.tasks.items) |*task| {
            if (std.mem.eql(u8, task.name, name)) {
                task.enabled = enabled;
                self.kick();
                return true;
            }
        }

        return false;
    }

    /// Removes a task by name.
    ///
    /// Returns true when a task was removed.
    pub fn removeTaskByName(self: *Scheduler, name: []const u8) bool {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);

        for (self.tasks.items, 0..) |task, i| {
            if (std.mem.eql(u8, task.name, name)) {
                const removed = self.tasks.orderedRemove(i);
                self.allocator.free(removed.name);
                if (removed.config.path) |p| self.allocator.free(p);
                if (removed.config.filePattern) |p| self.allocator.free(p);
                if (removed.dependsOn) |p| self.allocator.free(p);
                self.kick();
                return true;
            }
        }

        return false;
    }

    /// Returns enabled task count.
    pub fn enabledTaskCount(self: *Scheduler) usize {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);

        var enabledTotal: usize = 0;
        for (self.tasks.items) |task| {
            if (task.enabled) enabledTotal += 1;
        }
        return enabledTotal;
    }

    /// Returns running task count.
    pub fn runningTaskCount(self: *Scheduler) usize {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);

        var runningTotal: usize = 0;
        for (self.tasks.items) |task| {
            if (task.running) runningTotal += 1;
        }
        return runningTotal;
    }

    /// Returns milliseconds until task next run.
    pub fn nextRunInMs(self: *Scheduler, index: usize) ?i64 {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);

        if (index >= self.tasks.items.len) return null;
        const delta = self.tasks.items[index].nextRun - Utils.currentMillis();
        return if (delta > 0) delta else 0;
    }

    /// Returns milliseconds until task next run by task name.
    pub fn nextRunInMsByName(self: *Scheduler, name: []const u8) ?i64 {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);

        for (self.tasks.items) |task| {
            if (std.mem.eql(u8, task.name, name)) {
                const delta = task.nextRun - Utils.currentMillis();
                return if (delta > 0) delta else 0;
            }
        }

        return null;
    }

    /// Updates schedule for a task and recalculates next run.
    pub fn setTaskSchedule(self: *Scheduler, index: usize, schedule: Schedule) bool {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);

        if (index >= self.tasks.items.len) return false;

        self.tasks.items[index].schedule = schedule;
        self.tasks.items[index].nextRun = schedule.nextRunTime(Utils.currentMillis());
        self.kick();
        return true;
    }

    /// Forces a task to become runnable on next scheduler pass.
    pub fn rescheduleNow(self: *Scheduler, index: usize) bool {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);

        if (index >= self.tasks.items.len) return false;

        self.tasks.items[index].nextRun = Utils.currentMillis();
        self.tasks.items[index].retriesRemaining = self.tasks.items[index].retryPolicy.maxRetries;
        self.kick();
        return true;
    }

    /// Sets the callback for task started events.
    pub fn setTaskStartedCallback(self: *Scheduler, callback: *const fn ([]const u8, u64) void) void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        self.onTaskStarted = callback;
    }

    /// Sets the callback for task completed events.
    pub fn setTaskCompletedCallback(self: *Scheduler, callback: *const fn ([]const u8, u64) void) void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        self.onTaskCompleted = callback;
    }

    /// Sets the callback for task error events.
    pub fn setTaskErrorCallback(self: *Scheduler, callback: *const fn ([]const u8, []const u8) void) void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        self.onTaskError = callback;
    }

    /// Sets the callback for schedule tick events.
    pub fn setScheduleTickCallback(self: *Scheduler, callback: *const fn (u32, u32) void) void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        self.onScheduleTick = callback;
    }

    /// Sets the callback for health check events.
    pub fn setHealthCheckCallback(self: *Scheduler, callback: *const fn (*const HealthStatus) void) void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        self.onHealthCheck = callback;
    }

    /// Starts the scheduler.
    pub fn start(self: *Scheduler) !void {
        if (self.running.load(.acquire)) return;

        // Record start time with the monotonic clock: uptimeSeconds() feeds
        // it to Utils.elapsedSeconds(), which requires monotonic input.
        self.stats.startTime.store(@truncate(Utils.monotonicMillis()), .monotonic);

        self.running.store(true, .release);
        self.isPaused.store(false, .release);
        self.workerThread = try std.Thread.spawn(.{}, schedulerLoop, .{self});
    }

    /// Pauses the scheduler.
    pub fn pause(self: *Scheduler) void {
        self.isPaused.store(true, .release);
    }

    /// Resumes the scheduler.
    pub fn unpause(self: *Scheduler) void {
        self.isPaused.store(false, .release);
        self.kick();
    }

    /// Wake the worker loop so it re-evaluates task deadlines immediately.
    fn kick(self: *Scheduler) void {
        _ = self.wakeGeneration.fetchAdd(1, .monotonic);
        self.condition.broadcast(self.io);
    }

    /// Stops the scheduler.
    /// Stops the scheduler and waits for pending tasks.
    pub fn stop(self: *Scheduler) void {
        if (!self.running.load(.acquire)) return;

        self.running.store(false, .release);
        self.kick();

        // Join the worker loop thread
        if (self.workerThread) |thread| {
            thread.join();
            self.workerThread = null;
        }

        // Wait for running tasks to complete (with a 5-second graceful shutdown timeout)
        var waitLoops: u8 = 0;
        while (waitLoops < 50) : (waitLoops += 1) { // 5 second max wait
            var anyRunning = false;
            self.mutex.lockUncancelable(self.io);
            for (self.tasks.items) |task| {
                if (task.running) {
                    anyRunning = true;
                    break;
                }
            }
            self.mutex.unlock(self.io);

            if (!anyRunning) break;
            Utils.sleepMs(100);
        }
    }

    /// Runs a task immediately regardless of schedule.
    pub fn runNow(self: *Scheduler, index: usize) !void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);

        if (index >= self.tasks.items.len) return;
        try self.executeTask(&self.tasks.items[index]);
    }

    /// Runs a task immediately by task name.
    ///
    /// Returns true when task exists and was executed.
    pub fn runNowByName(self: *Scheduler, name: []const u8) !bool {
        const index = self.taskIndexByName(name) orelse return false;
        try self.runNow(index);
        return true;
    }

    fn dependenciesSatisfiedLocked(self: *Scheduler, task: *const ScheduledTask) bool {
        if (task.dependsOn) |depName| {
            for (self.tasks.items) |t| {
                if (std.mem.eql(u8, t.name, depName) and t.running) {
                    return false;
                }
            }
        }
        return true;
    }

    fn resourceThresholdsSatisfied(task: *const ScheduledTask, scheduler: *Scheduler) bool {
        if (task.config.triggerDiskUsagePercent) |threshold| {
            const usage = scheduler.getDiskUsage(task.config.path orelse ".") catch return false;
            if (usage < threshold) return false;
        }

        if (task.config.minFreeSpaceBytes) |minFree| {
            const free = scheduler.getFreeSpace(task.config.path orelse ".") catch return false;
            if (free < minFree) return false;
        }

        return true;
    }

    fn isTimeReadyLocked(self: *Scheduler, task: *const ScheduledTask, now: i64) bool {
        if (!task.enabled or task.running or task.nextRun > now) return false;
        return self.dependenciesSatisfiedLocked(task);
    }

    fn isTaskReadyLocked(self: *Scheduler, task: *const ScheduledTask, now: i64) bool {
        if (!self.isTimeReadyLocked(task, now)) return false;
        return resourceThresholdsSatisfied(task, self);
    }

    /// Returns number of tasks currently ready to run.
    pub fn readyTaskCount(self: *Scheduler) usize {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);

        const now = Utils.currentMillis();
        var readyTotal: usize = 0;
        for (self.tasks.items) |task| {
            if (self.isTaskReadyLocked(&task, now)) readyTotal += 1;
        }
        return readyTotal;
    }

    /// Runs all pending tasks.
    ///
    /// The precheck pass uses only the time gate (no filesystem I/O), so
    /// idle ticks cost a single clock read plus integer compares. Disk
    /// usage gates run at most once per time-ready task in the execute pass.
    pub fn runPending(self: *Scheduler) void {
        var tickCb: ?*const fn (u32, u32) void = null;
        var readyCount: u32 = 0;
        var totalCount: u32 = 0;

        self.mutex.lockUncancelable(self.io);
        const now = Utils.currentMillis();
        totalCount = @as(u32, @intCast(@min(self.tasks.items.len, std.math.maxInt(u32))));
        for (self.tasks.items) |task| {
            if (self.isTimeReadyLocked(&task, now)) {
                readyCount += 1;
            }
        }
        tickCb = self.onScheduleTick;
        self.mutex.unlock(self.io);

        if (tickCb) |cb| cb(readyCount, totalCount);

        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);

        for (self.tasks.items, 0..) |*task, i| {
            if (self.isTaskReadyLocked(task, now)) {
                if (self.threadPool) |tp| {
                    task.running = true;
                    const TaskCtx = struct {
                        scheduler: *Scheduler,
                        taskIndex: usize,

                        fn run(ctxPtr: *anyopaque, _: ?std.mem.Allocator) void {
                            const ctx = @as(*@This(), @ptrCast(@alignCast(ctxPtr)));
                            defer ctx.scheduler.allocator.destroy(ctx);

                            ctx.scheduler.runTaskByIndex(ctx.taskIndex) catch |err| {
                                ctx.scheduler.handleTaskError(ctx.taskIndex, err);
                            };
                        }

                        fn drop(ctxPtr: ?*anyopaque) void {
                            const ctx = @as(*@This(), @ptrCast(@alignCast(ctxPtr.?)));
                            ctx.scheduler.allocator.destroy(ctx);
                        }
                    };

                    const ctx = self.allocator.create(TaskCtx) catch continue;
                    ctx.* = .{
                        .scheduler = self,
                        .taskIndex = i,
                    };

                    const tpPrio: ThreadPool.WorkItem.Priority = switch (task.priority) {
                        .low => .low,
                        .normal => .normal,
                        .high => .high,
                        .critical => .critical,
                    };

                    if (!tp.submitWithDrop(.{ .callback = .{ .func = TaskCtx.run, .context = ctx } }, tpPrio, TaskCtx.drop).isValid()) {
                        self.allocator.destroy(ctx);
                        self.executeTask(task) catch |err| {
                            self.handleTaskErrorLocked(i, err);
                        };
                        task.running = false;
                    }
                } else {
                    self.executeTask(task) catch |err| {
                        self.handleTaskErrorLocked(i, err);
                    };
                }
            }
        }
    }

    fn handleTaskError(self: *Scheduler, index: usize, err: anyerror) void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);

        self.handleTaskErrorLocked(index, err);
    }

    fn handleTaskErrorLocked(self: *Scheduler, index: usize, err: anyerror) void {
        if (index >= self.tasks.items.len) return;
        const task = &self.tasks.items[index];

        task.errorCount += 1;
        _ = self.stats.tasksFailed.fetchAdd(1, .monotonic);

        if (task.retriesRemaining > 0) {
            task.retriesRemaining -= 1;
            const delay = @as(u64, @intFromFloat(@as(f32, @floatFromInt(task.retryPolicy.intervalMs)) * std.math.pow(f32, task.retryPolicy.backoffMultiplier, @floatFromInt(task.retryPolicy.maxRetries - task.retriesRemaining))));
            task.nextRun = Utils.currentMillis() + @as(i64, @intCast(delay));

            std.log.warn("Scheduled task '{s}' failed ({s}), retrying in {d}ms ({d} retries left)", .{ task.name, @errorName(err), delay, task.retriesRemaining });
        } else {
            if (self.onTaskError) |cb| {
                cb(task.name, @errorName(err));
            } else {
                std.log.err("Scheduled task '{s}' failed: {s}", .{ task.name, @errorName(err) });
            }
        }
    }

    fn runTaskByIndex(self: *Scheduler, index: usize) !void {
        self.mutex.lockUncancelable(self.io);
        if (index >= self.tasks.items.len) {
            self.mutex.unlock(self.io);
            return;
        }
        const task = &self.tasks.items[index];
        self.mutex.unlock(self.io);

        defer {
            self.mutex.lockUncancelable(self.io);
            task.running = false;
            self.mutex.unlock(self.io);
        }

        try self.executeTask(task);
    }

    fn schedulerLoop(self: *Scheduler) void {
        while (self.running.load(.acquire)) {
            if (!self.isPaused.load(.acquire)) {
                self.runPending();
            }

            self.waitForWork();
        }
    }

    /// Sleeps until the next task deadline, a schedule mutation, unpause,
    /// or shutdown. Sleeps in short slices so stop() joins promptly even
    /// when the next deadline is far away.
    fn waitForWork(self: *Scheduler) void {
        const gen = self.wakeGeneration.load(.acquire);

        var waitMs: i64 = 60_000;
        var foundTasks = false;
        self.mutex.lockUncancelable(self.io);
        const now = Utils.currentMillis();
        for (self.tasks.items) |task| {
            if (!task.enabled) continue;
            foundTasks = true;
            const delta = task.nextRun - now;
            if (delta < waitMs) waitMs = delta;
        }

        if (!foundTasks) waitMs = 1_000;
        if (waitMs < 0) waitMs = 0;

        if (waitMs > 0 and self.running.load(.acquire) and self.wakeGeneration.load(.acquire) == gen) {
            const timeout: std.Io.Timeout = .{
                .duration = .{
                    .raw = std.Io.Duration.fromMilliseconds(@intCast(waitMs)),
                    .clock = .awake,
                },
            };
            std.Io.Condition.waitTimeout(&self.condition, self.io, &self.mutex, timeout) catch {};
        }
        self.mutex.unlock(self.io);
    }

    fn executeTask(self: *Scheduler, task: *ScheduledTask) !void {
        const now = Utils.currentMillis();
        const startNs = Utils.currentNanos();

        // Start telemetry span if enabled
        var maybeSpan: ?Span = null;
        if (self.telemetry) |t| {
            maybeSpan = t.startSpan(task.name, .{
                .kind = SpanKind.internal,
            }) catch null;
            if (maybeSpan) |*span| {
                span.setAttribute("task.type", .{ .string = @tagName(task.taskType) }) catch {};
                span.setAttribute("task.priority", .{ .string = @tagName(task.priority) }) catch {};
            }
        }

        // Execute task based on type with error tracking
        const execResult = self.executeTaskCore(task, &maybeSpan);

        // Calculate duration
        const durationNs = Utils.durationSinceNs(startNs);
        const durationMs: i64 = @intCast(@divFloor(durationNs, Constants.TimeConstants.nsPerMs));

        // End telemetry span
        if (maybeSpan) |*span| {
            span.setAttribute("task.duration_ms", .{ .integer = durationMs }) catch {};
            if (execResult) |_| {} else |err| {
                span.setStatusWithMessage(.err, @errorName(err)) catch {};
            }
            if (self.telemetry) |t| {
                t.endSpan(span) catch {};
            }
        }

        // Record task execution metrics in telemetry
        if (self.telemetry) |t| {
            t.recordCounter("scheduler.tasks_executed", 1.0) catch {};
            t.recordGauge("scheduler.task_duration_ms", @floatFromInt(durationMs)) catch {};
        }

        // Propagate error if task failed
        try execResult;

        task.lastRun = now;
        task.nextRun = task.schedule.nextRunTime(now);
        task.runCount += 1;
        _ = self.stats.tasksExecuted.fetchAdd(1, .monotonic);
        self.stats.lastRunTime.store(@truncate(now), .monotonic);
    }

    /// Core task execution logic (separated for telemetry tracking).
    fn executeTaskCore(self: *Scheduler, task: *ScheduledTask, maybeSpan: *?Span) !void {
        switch (task.taskType) {
            .cleanup => {
                if (task.config.path) |path| {
                    const result = try self.performCleanup(path, task.config);
                    _ = self.stats.filesCleaned.fetchAdd(@intCast(result.filesDeleted), .monotonic);
                    _ = self.stats.bytesFreed.fetchAdd(@intCast(result.bytesFreed), .monotonic);

                    // Record cleanup stats in span
                    if (maybeSpan.*) |*span| {
                        span.setAttribute("cleanup.files_deleted", .{ .integer = @intCast(result.filesDeleted) }) catch {};
                        span.setAttribute("cleanup.bytes_freed", .{ .integer = @intCast(result.bytesFreed) }) catch {};
                    }
                }
            },
            .compression => {
                if (task.config.path) |path| {
                    const result = try self.performCompression(path, task.config);
                    _ = self.stats.filesCompressed.fetchAdd(@intCast(result.filesCompressed), .monotonic);
                    _ = self.stats.bytesSaved.fetchAdd(@intCast(result.bytesSaved), .monotonic);

                    // Record compression stats in span
                    if (maybeSpan.*) |*span| {
                        span.setAttribute("compression.files", .{ .integer = @intCast(result.filesCompressed) }) catch {};
                        span.setAttribute("compression.bytes_saved", .{ .integer = @intCast(result.bytesSaved) }) catch {};
                    }
                }
            },
            .rotation => {
                // Rotation is handled by the sink directly based on size/time
                // This task is typically used to trigger manual rotation checks
            },
            .flush => {
                // Flush task - triggers a flush of any buffered data
                // This is typically handled by the logger or sinks
            },
            .custom => {
                if (task.callback) |cb| {
                    try cb(task);
                }
            },
            .healthCheck => {
                // Perform health check and store result
                const health = self.getHealthStatus();
                if (!health.healthy) {
                    task.errorCount += 1;
                }
                // Record health status in span
                if (maybeSpan.*) |*span| {
                    span.setAttribute("health.healthy", .{ .boolean = health.healthy }) catch {};
                }
            },
            .metricsSnapshot => {
                // Capture metrics snapshot
                const metrics = self.getMetrics();
                if (maybeSpan.*) |*span| {
                    span.setAttribute("metrics.log_count", .{ .integer = @intCast(metrics.logCount) }) catch {};
                    span.setAttribute("metrics.error_count", .{ .integer = @intCast(metrics.errorCount) }) catch {};
                }
            },
        }
    }

    fn performCleanup(self: *Scheduler, path: []const u8, config: ScheduledTask.TaskConfig) !CleanupResult {
        var result = CleanupResult{};
        const now = Utils.currentSeconds();
        const maxAge = @as(i64, @intCast(config.maxAgeSeconds));

        var dir = std.Io.Dir.cwd().openDir(self.io, path, .{ .iterate = true }) catch {
            return result;
        };
        defer dir.close(self.io);

        // Collect file info for ranking
        var files: std.ArrayList(FileInfo) = .empty;
        defer {
            for (files.items) |fi| {
                self.allocator.free(fi.name);
            }
            files.deinit(self.allocator);
        }

        var iter = dir.iterate();
        var totalSize: u64 = 0;
        while (try iter.next(self.io)) |entry| {
            if (entry.kind != .file) continue;

            // Check file pattern
            if (config.filePattern) |pattern| {
                if (!matchPattern(entry.name, pattern)) continue;
            }

            // Get file stats
            const file = dir.openFile(self.io, entry.name, .{}) catch continue;
            const stat = file.stat(self.io) catch {
                file.close(self.io);
                continue;
            };
            file.close(self.io);

            const mtime = stat.mtime.toSeconds();
            const age = now - mtime;

            const nameCopy = self.allocator.dupe(u8, entry.name) catch continue;
            files.append(self.allocator, .{
                .name = nameCopy,
                .mtime = mtime,
                .size = stat.size,
                .age = age,
            }) catch {
                self.allocator.free(nameCopy);
                continue;
            };
            totalSize += stat.size;
        }

        // Sort by modification time (oldest first)
        std.mem.sort(FileInfo, files.items, {}, struct {
            fn lessThan(_: void, a: FileInfo, b: FileInfo) bool {
                return a.mtime < b.mtime;
            }
        }.lessThan);

        // Track what we delete
        var deletedIndices = std.DynamicBitSet.initEmpty(self.allocator, files.items.len) catch return result;
        defer deletedIndices.deinit();

        // 1. Delete files based on age (or compress based on mode)
        for (files.items, 0..) |fi, i| {
            if (fi.age > maxAge) {
                const alreadyCompressed = Constants.CompressionExtensions.isCompressed(fi.name);
                const shouldSkipCompressed = config.skipAlreadyCompressed and alreadyCompressed;

                // Mode: Compress only (no deletion)
                if (config.compressOnly) {
                    if (self.compressionInitialized and !shouldSkipCompressed) {
                        const fullPath = try std.fs.path.join(self.allocator, &[_][]const u8{ path, fi.name });
                        defer self.allocator.free(fullPath);
                        _ = self.compression.compressFile(fullPath, null) catch {
                            result.errors += 1;
                            continue;
                        };
                        result.filesCompressed += 1;
                    }
                    continue; // Don't delete anything
                }

                // Mode: Compress and keep both original and compressed
                if (config.compressAndKeep and self.compressionInitialized and !shouldSkipCompressed) {
                    const fullPath = try std.fs.path.join(self.allocator, &[_][]const u8{ path, fi.name });
                    defer self.allocator.free(fullPath);
                    _ = self.compression.compressFile(fullPath, null) catch {
                        result.errors += 1;
                        continue;
                    };
                    result.filesCompressed += 1;
                    continue; // Keep original, don't delete
                }

                // Mode: Compress before delete (compress then delete original).
                // Count only successful compressions, never failures.
                if (config.compressBeforeDelete and self.compressionInitialized and !shouldSkipCompressed) {
                    const fullPath = try std.fs.path.join(self.allocator, &[_][]const u8{ path, fi.name });
                    defer self.allocator.free(fullPath);
                    _ = self.compression.compressFile(fullPath, null) catch {
                        result.errors += 1;
                        continue;
                    };
                    result.filesCompressed += 1;
                }

                // Default: Delete the file
                dir.deleteFile(self.io, fi.name) catch {
                    result.errors += 1;
                    continue;
                };

                result.filesDeleted += 1;
                result.bytesFreed += fi.size;
                totalSize -= fi.size;
                deletedIndices.set(i);
            }
        }

        // 2. Enforce max files limit
        if (config.maxFiles) |max| {
            var currentCount = files.items.len - result.filesDeleted;
            if (currentCount > max) {
                for (files.items, 0..) |fi, i| {
                    if (deletedIndices.isSet(i)) continue;
                    if (currentCount <= max) break;

                    dir.deleteFile(self.io, fi.name) catch {
                        result.errors += 1;
                        continue;
                    };

                    result.filesDeleted += 1;
                    result.bytesFreed += fi.size;
                    totalSize -= fi.size;
                    deletedIndices.set(i);
                    currentCount -= 1;
                }
            }
        }

        // 3. Enforce max total size limit
        if (config.maxTotalSize) |maxSize| {
            if (totalSize > maxSize) {
                for (files.items, 0..) |fi, i| {
                    if (deletedIndices.isSet(i)) continue;
                    if (totalSize <= maxSize) break;

                    dir.deleteFile(self.io, fi.name) catch {
                        result.errors += 1;
                        continue;
                    };

                    result.filesDeleted += 1;
                    result.bytesFreed += fi.size;
                    totalSize -= fi.size;
                    deletedIndices.set(i);
                }
            }
        }

        return result;
    }

    /// File info for sorting during cleanup.
    const FileInfo = struct {
        name: []const u8,
        mtime: i64,
        size: u64,
        age: i64,
    };

    /// Compression result information.
    pub const CompressionTaskResult = struct {
        filesCompressed: usize = 0,
        bytesBefore: u64 = 0,
        bytesAfter: u64 = 0,
        bytesSaved: u64 = 0,
        errors: usize = 0,
    };

    fn performCompression(self: *Scheduler, path: []const u8, config: ScheduledTask.TaskConfig) !CompressionTaskResult {
        var result = CompressionTaskResult{};

        if (!self.compressionInitialized) return result;

        var dir = std.Io.Dir.cwd().openDir(self.io, path, .{ .iterate = true }) catch return result;
        defer dir.close(self.io);

        var iter = dir.iterate();
        const now = Utils.currentSeconds();
        while (try iter.next(self.io)) |entry| {
            if (entry.kind != .file) continue;

            // Skip already compressed files
            if (Constants.CompressionExtensions.isCompressed(entry.name)) continue;

            // Check pattern
            if (config.filePattern) |pattern| {
                if (!matchPattern(entry.name, pattern)) continue;
            }

            // Check age if min_age_seconds is set
            if (config.minAgeSeconds > 0) {
                const file = dir.openFile(self.io, entry.name, .{}) catch continue;
                const stat = file.stat(self.io) catch {
                    file.close(self.io);
                    continue;
                };
                file.close(self.io);
                const mtime = stat.mtime.toSeconds();
                if (now - mtime < @as(i64, @intCast(config.minAgeSeconds))) continue;
            }

            // Build full path
            const fullPath = std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ path, entry.name }) catch continue;
            defer self.allocator.free(fullPath);

            // Compress the file
            const compResult = self.compression.compressFile(fullPath, null) catch {
                result.errors += 1;
                continue;
            };

            if (compResult.success) {
                result.filesCompressed += 1;
                result.bytesBefore += compResult.originalSize;
                result.bytesAfter += compResult.compressedSize;
                if (compResult.originalSize > compResult.compressedSize) {
                    result.bytesSaved += compResult.originalSize - compResult.compressedSize;
                }

                // Free the output path if allocated
                if (compResult.outputPath) |outPath| {
                    self.allocator.free(outPath);
                }
            } else {
                result.errors += 1;
            }
        }

        return result;
    }

    /// Gets scheduler statistics.
    pub fn getStats(self: *const Scheduler) SchedulerStats {
        return self.stats;
    }

    /// Resets statistics (per-field atomic stores; safe against concurrent readers).
    pub fn resetStats(self: *Scheduler) void {
        self.stats.tasksExecuted.store(0, .monotonic);
        self.stats.tasksFailed.store(0, .monotonic);
        self.stats.filesCleaned.store(0, .monotonic);
        self.stats.filesCompressed.store(0, .monotonic);
        self.stats.bytesFreed.store(0, .monotonic);
        self.stats.bytesSaved.store(0, .monotonic);
        self.stats.lastRunTime.store(0, .monotonic);
        self.stats.startTime.store(@truncate(Utils.monotonicMillis()), .monotonic);
    }

    /// Sets the telemetry instance for distributed tracing.
    /// When set, task executions will create spans for observability.
    pub fn setTelemetry(self: *Scheduler, telemetry: *Telemetry) void {
        self.telemetry = telemetry;
    }

    /// Clears the telemetry instance.
    pub fn clearTelemetry(self: *Scheduler) void {
        self.telemetry = null;
    }

    /// Gets list of all tasks.
    pub fn getTasks(self: *const Scheduler) []const ScheduledTask {
        return self.tasks.items;
    }

    /// Returns the number of tasks.
    pub fn taskCount(self: *const Scheduler) usize {
        return self.tasks.items.len;
    }

    /// Returns true if the scheduler is running.
    pub fn isRunning(self: *const Scheduler) bool {
        return self.running.load(.acquire);
    }

    /// Returns true if any tasks are scheduled.
    pub fn hasTasks(self: *const Scheduler) bool {
        return self.tasks.items.len > 0;
    }

    fn getDiskUsage(self: *Scheduler, path: []const u8) !u8 {
        if (@import("builtin").os.tag == .windows) {
            var freeBytes: u64 = 0;
            var totalBytes: u64 = 0;
            var totalFree: u64 = 0;

            const pathW = try std.unicode.utf8ToUtf16LeAllocZ(self.allocator, path);
            defer self.allocator.free(pathW);

            if (GetDiskFreeSpaceExW(pathW.ptr, &freeBytes, &totalBytes, &totalFree) == 0) {
                return 0;
            }
            if (totalBytes == 0) return 0;
            return @intCast(100 - (freeBytes * 100 / totalBytes));
        } else {
            if (comptime @hasDecl(std.posix, "statvfs")) {
                const pathC = try self.allocator.dupeSentinel(u8, path, 0);
                defer self.allocator.free(pathC);

                var stat: std.posix.statvfs = undefined;
                try std.posix.statvfs(pathC, &stat);

                if (stat.blocks == 0) return 0;
                return @intCast(100 - (stat.bfree * 100 / stat.blocks));
            } else {
                return 0; // Fallback for systems where statvfs is not available in std.posix
            }
        }
    }

    fn getFreeSpace(self: *Scheduler, path: []const u8) !u64 {
        if (@import("builtin").os.tag == .windows) {
            var freeBytes: u64 = 0;
            var totalBytes: u64 = 0;
            var totalFree: u64 = 0;

            const pathW = try std.unicode.utf8ToUtf16LeAllocZ(self.allocator, path);
            defer self.allocator.free(pathW);

            if (GetDiskFreeSpaceExW(pathW.ptr, &freeBytes, &totalBytes, &totalFree) == 0) {
                return 0;
            }
            return freeBytes;
        } else {
            if (comptime @hasDecl(std.posix, "statvfs")) {
                const pathC = try self.allocator.dupeSentinel(u8, path, 0);
                defer self.allocator.free(pathC);

                var stat: std.posix.statvfs = undefined;
                try std.posix.statvfs(pathC, &stat);

                return stat.bfree * stat.frsize;
            } else {
                return 0; // Fallback for systems where statvfs is not available in std.posix
            }
        }
    }
};

fn matchPattern(name: []const u8, pattern: []const u8) bool {
    // Wildcard matches everything
    if (std.mem.eql(u8, pattern, "*")) return true;
    // Simple glob matching for *.ext patterns
    if (std.mem.startsWith(u8, pattern, "*.")) {
        const ext = pattern[1..];
        return std.mem.endsWith(u8, name, ext);
    }
    return std.mem.eql(u8, name, pattern);
}

/// Preset scheduler configurations.
pub const SchedulerPresets = struct {
    /// Daily cleanup at midnight.
    pub fn dailyCleanup(path: []const u8, maxAgeDays: u64) Scheduler.ScheduledTask.TaskConfig {
        return .{
            .path = path,
            .maxAgeSeconds = maxAgeDays * Constants.TimeConstants.secondsPerDay,
            .filePattern = "*.log",
        };
    }

    /// Weekly cleanup on Sunday at 2 AM.
    pub fn weeklyCleanup() Scheduler.Schedule {
        return .{ .cron = .{
            .hour = 2,
            .minute = 0,
            .dayOfWeek = 0,
        } };
    }

    /// Hourly compression.
    pub fn hourlyCompression() Scheduler.Schedule {
        return .{ .interval = Constants.TimeConstants.secondsPerHour * Constants.TimeConstants.msPerSecond };
    }

    /// Every N minutes.
    pub fn everyMinutes(n: u64) Scheduler.Schedule {
        return .{ .interval = n * Constants.TimeConstants.secondsPerMinute * Constants.TimeConstants.msPerSecond };
    }

    /// Daily at specific time.
    pub fn dailyAt(hour: u8, minute: u8) Scheduler.Schedule {
        return .{ .daily = .{ .hour = hour, .minute = minute } };
    }

    /// Creates a scheduled log sink configuration.
    pub fn createScheduledSink(filePath: []const u8, rotation: []const u8) SinkConfig {
        return SinkConfig{
            .path = filePath,
            .rotation = rotation,
            .retention = 7,
            .color = false,
        };
    }

    /// Every 30 minutes.
    pub fn every30Minutes() Scheduler.Schedule {
        return .{ .interval = 30 * Constants.TimeConstants.secondsPerMinute * Constants.TimeConstants.msPerSecond };
    }

    /// Every 6 hours.
    pub fn every6Hours() Scheduler.Schedule {
        return .{ .interval = 6 * Constants.TimeConstants.secondsPerHour * Constants.TimeConstants.msPerSecond };
    }

    /// Every 12 hours.
    pub fn every12Hours() Scheduler.Schedule {
        return .{ .interval = 12 * Constants.TimeConstants.secondsPerHour * Constants.TimeConstants.msPerSecond };
    }

    /// Daily at midnight.
    pub fn dailyMidnight() Scheduler.Schedule {
        return dailyAt(0, 0);
    }

    /// Daily at 2 AM (maintenance window).
    pub fn dailyMaintenance() Scheduler.Schedule {
        return dailyAt(2, 0);
    }

    /// Creates a weekly cleanup config.
    pub fn weeklyCleanupConfig(path: []const u8, maxAgeDays: u64) Scheduler.ScheduledTask.TaskConfig {
        return dailyCleanup(path, maxAgeDays);
    }

    /// Compress files older than N days, then delete originals.
    /// Use this to archive logs before cleanup.
    pub fn compressThenDelete(path: []const u8, minAgeDays: u64) Scheduler.ScheduledTask.TaskConfig {
        return .{
            .path = path,
            .minAgeSeconds = minAgeDays * Constants.TimeConstants.secondsPerDay,
            .filePattern = "*.log",
            .compressBeforeDelete = true,
            .skipAlreadyCompressed = true,
        };
    }

    /// Compress files older than N days, keep both original and compressed.
    /// Use this for redundant archival where you need both versions.
    pub fn compressAndKeep(path: []const u8, minAgeDays: u64) Scheduler.ScheduledTask.TaskConfig {
        return .{
            .path = path,
            .minAgeSeconds = minAgeDays * Constants.TimeConstants.secondsPerDay,
            .filePattern = "*.log",
            .compressAndKeep = true,
            .skipAlreadyCompressed = true,
        };
    }

    /// Only compress files, never delete anything.
    /// Use this for pure archival without any deletion.
    pub fn compressOnly(path: []const u8, minAgeDays: u64) Scheduler.ScheduledTask.TaskConfig {
        return .{
            .path = path,
            .minAgeSeconds = minAgeDays * Constants.TimeConstants.secondsPerDay,
            .filePattern = "*.log",
            .compressOnly = true,
            .skipAlreadyCompressed = true,
        };
    }

    /// Archive old logs: compress files older than N days, delete originals after compression.
    /// Similar to compressThenDelete but with max_age enforcement.
    pub fn archiveOldLogs(path: []const u8, compressAfterDays: u64, deleteAfterDays: u64) Scheduler.ScheduledTask.TaskConfig {
        return .{
            .path = path,
            .minAgeSeconds = compressAfterDays * Constants.TimeConstants.secondsPerDay,
            .maxAgeSeconds = deleteAfterDays * Constants.TimeConstants.secondsPerDay,
            .filePattern = "*.log",
            .compressBeforeDelete = true,
            .skipAlreadyCompressed = true,
        };
    }

    /// Aggressive cleanup: compress and delete files older than N days, enforce max file count.
    pub fn aggressiveCleanup(path: []const u8, maxAgeDays: u64, maxFiles: usize) Scheduler.ScheduledTask.TaskConfig {
        return .{
            .path = path,
            .maxAgeSeconds = maxAgeDays * Constants.TimeConstants.secondsPerDay,
            .maxFiles = maxFiles,
            .filePattern = "*.log",
            .compressBeforeDelete = true,
            .skipAlreadyCompressed = true,
        };
    }

    /// Compress files older than 1 day on an hourly schedule.
    pub fn hourlyArchive(path: []const u8) Scheduler.ScheduledTask.TaskConfig {
        return .{
            .path = path,
            .minAgeSeconds = Constants.TimeConstants.secondsPerDay, // 1 day
            .filePattern = "*.log",
            .compressOnly = true,
            .skipAlreadyCompressed = true,
        };
    }

    /// Compress on rotation: for files that have just rotated.
    pub fn compressOnRotation(path: []const u8) Scheduler.ScheduledTask.TaskConfig {
        return .{
            .path = path,
            .minAgeSeconds = Constants.TimeConstants.secondsPerMinute, // At least 1 minute old (just rotated)
            .filePattern = "*.log.*",
            .compressOnly = true,
            .skipAlreadyCompressed = true,
        };
    }

    /// Size-based compression trigger: compress when total size exceeds threshold.
    pub fn sizeBasedCompression(path: []const u8, maxTotalBytes: u64) Scheduler.ScheduledTask.TaskConfig {
        return .{
            .path = path,
            .maxTotalSize = maxTotalBytes,
            .filePattern = "*.log",
            .compressOnly = true,
            .skipAlreadyCompressed = true,
        };
    }

    /// Disk usage triggered compression: only run when disk usage exceeds threshold.
    pub fn diskUsageTriggered(path: []const u8, diskUsagePercent: u8) Scheduler.ScheduledTask.TaskConfig {
        return .{
            .path = path,
            .filePattern = "*.log",
            .compressBeforeDelete = true,
            .skipAlreadyCompressed = true,
            .triggerDiskUsagePercent = diskUsagePercent,
        };
    }

    /// Low disk space triggered: only run when free space is below threshold.
    pub fn lowDiskSpaceTriggered(path: []const u8, minFreeBytes: u64) Scheduler.ScheduledTask.TaskConfig {
        return .{
            .path = path,
            .filePattern = "*.log",
            .compressBeforeDelete = true,
            .skipAlreadyCompressed = true,
            .minFreeSpaceBytes = minFreeBytes,
        };
    }

    /// Recursive directory compression for nested log structures.
    pub fn recursiveCompression(path: []const u8, minAgeDays: u64) Scheduler.ScheduledTask.TaskConfig {
        return .{
            .path = path,
            .minAgeSeconds = minAgeDays * Constants.TimeConstants.secondsPerDay,
            .filePattern = "*.log",
            .compressOnly = true,
            .skipAlreadyCompressed = true,
            .recursive = true,
        };
    }

    /// Every 15 minutes.
    pub fn every15Minutes() Scheduler.Schedule {
        return .{ .interval = 15 * Constants.TimeConstants.secondsPerMinute * Constants.TimeConstants.msPerSecond };
    }

    /// Once after delay in seconds.
    pub fn onceAfter(seconds: u64) Scheduler.Schedule {
        return .{ .once = seconds * Constants.TimeConstants.msPerSecond };
    }

    /// Creates a health check schedule (every 5 minutes).
    pub fn healthCheckSchedule() Scheduler.Schedule {
        return .{ .interval = 5 * Constants.TimeConstants.secondsPerMinute * Constants.TimeConstants.msPerSecond };
    }

    /// Creates a metrics collection schedule (every minute).
    pub fn metricsSchedule() Scheduler.Schedule {
        return .{ .interval = Constants.TimeConstants.secondsPerMinute * Constants.TimeConstants.msPerSecond };
    }
};

test "scheduler basic" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const scheduler = try Scheduler.init(allocator);
    defer scheduler.deinit();

    _ = try scheduler.addTask("test", .cleanup, .{ .interval = Constants.TimeConstants.rotationCheckIntervalMs }, .{});

    try std.testing.expectEqual(@as(usize, 1), scheduler.tasks.items.len);
}

test "schedule next run time" {
    const now = Utils.currentMillis();

    const interval = Scheduler.Schedule{ .interval = Constants.SchedulerDefaults.retryIntervalMs };
    const next = interval.nextRunTime(now);

    try std.testing.expect(next > now);
    try std.testing.expect(next <= now + @as(i64, @intCast(Constants.SchedulerDefaults.retryIntervalMs)));
}

test "pattern matching" {
    try std.testing.expect(matchPattern("app.log", "*.log"));
    try std.testing.expect(!matchPattern("app.txt", "*.log"));
    try std.testing.expect(matchPattern("test.log.gz", "*.gz"));
}

test "scheduler maintenance task" {
    const allocator = std.testing.allocator;
    const scheduler = try Scheduler.init(allocator);
    defer scheduler.deinit();

    const tmpPath = ".test_logs_maintenance";
    std.Io.Dir.cwd().createDir(Utils.defaultIo(), tmpPath, .default_dir) catch {};
    defer std.Io.Dir.cwd().deleteTree(Utils.defaultIo(), tmpPath) catch {};

    var dir = try std.Io.Dir.cwd().openDir(Utils.defaultIo(), tmpPath, .{ .iterate = true });
    defer dir.close(Utils.defaultIo());

    // Create initial set of log files for testing limit enforcement
    var i: usize = 0;
    while (i < 10) : (i += 1) {
        const name = try std.fmt.allocPrint(allocator, "test_{d}.log", .{i});
        defer allocator.free(name);
        const file = try dir.createFile(Utils.defaultIo(), name, .{});
        try file.writeStreamingAll(Utils.defaultIo(), "test content");
        file.close(Utils.defaultIo());
    }

    // Create additional files to test overflow handling
    while (i < 15) : (i += 1) {
        const name = try std.fmt.allocPrint(allocator, "new_{d}.log", .{i});
        defer allocator.free(name);
        const file = try dir.createFile(Utils.defaultIo(), name, .{});
        try file.writeStreamingAll(Utils.defaultIo(), "new log content");
        file.close(Utils.defaultIo());
    }

    // Verify max_files constraint enforcement
    var config = Scheduler.ScheduledTask.TaskConfig{
        .path = tmpPath,
        .maxFiles = 5,
        .filePattern = "*.log",
    };

    const result = try scheduler.performCleanup(tmpPath, config);
    try std.testing.expectEqual(@as(usize, 10), result.filesDeleted);

    var count: usize = 0;
    var iter = dir.iterate();
    while (try iter.next(Utils.defaultIo())) |_| {
        count += 1;
    }
    try std.testing.expectEqual(@as(usize, 5), count);

    // Verify max_total_size constraint enforcement
    {
        const file = try dir.createFile(Utils.defaultIo(), "large.log", .{});
        var fill: [Constants.SizeConstants.bytesPerKb]u8 = @splat('A');
        try file.writeStreamingAll(Utils.defaultIo(), &fill);
        file.close(Utils.defaultIo());
    }

    config.maxFiles = null;
    config.maxTotalSize = 500;

    const result2 = try scheduler.performCleanup(tmpPath, config);
    try std.testing.expect(result2.filesDeleted >= 1);
}

test "scheduler task introspection helpers" {
    const allocator = std.testing.allocator;
    const scheduler = try Scheduler.init(allocator);
    defer scheduler.deinit();

    const idxA = try scheduler.addTask("introspect-a", .custom, .{ .once = 0 }, .{});
    const idxB = try scheduler.addTask("introspect-b", .custom, .{ .interval = Constants.TimeConstants.rotationCheckIntervalMs }, .{});

    try std.testing.expectEqual(@as(?usize, idxA), scheduler.taskIndexByName("introspect-a"));
    try std.testing.expect(scheduler.hasTaskNamed("introspect-b"));
    try std.testing.expect(!scheduler.hasTaskNamed("missing-task"));

    scheduler.setTaskEnabled(idxB, false);
    try std.testing.expectEqual(@as(usize, 1), scheduler.enabledTaskCount());

    const nextA = scheduler.nextRunInMs(idxA);
    try std.testing.expect(nextA != null);
    try std.testing.expect(nextA.? >= 0);

    try std.testing.expect(scheduler.setTaskSchedule(idxB, .{ .once = 0 }));
    try std.testing.expect(scheduler.rescheduleNow(idxB));
}

test "scheduler name based controls and snapshots" {
    const allocator = std.testing.allocator;
    const scheduler = try Scheduler.init(allocator);
    defer scheduler.deinit();

    const idx = try scheduler.addTask("named-task", .custom, .{ .interval = Constants.TimeConstants.rotationCheckIntervalMs }, .{});
    try std.testing.expectEqual(@as(usize, 0), idx);

    const snapshot = scheduler.getTaskSnapshot(idx);
    try std.testing.expect(snapshot != null);
    try std.testing.expectEqualStrings("named-task", snapshot.?.name);
    try std.testing.expect(snapshot.?.enabled);

    const namedSnapshot = scheduler.getTaskSnapshotByName("named-task");
    try std.testing.expect(namedSnapshot != null);
    try std.testing.expectEqual(Scheduler.TaskType.custom, namedSnapshot.?.taskType);

    try std.testing.expect(scheduler.setTaskEnabledByName("named-task", false));
    try std.testing.expect(!scheduler.getTaskSnapshotByName("named-task").?.enabled);

    try std.testing.expect(scheduler.nextRunInMsByName("named-task") != null);
    try std.testing.expect(!(try scheduler.runNowByName("missing-task")));
    try std.testing.expect(try scheduler.runNowByName("named-task"));

    try std.testing.expect(scheduler.removeTaskByName("named-task"));
    try std.testing.expect(!scheduler.hasTaskNamed("named-task"));
    try std.testing.expect(!scheduler.removeTaskByName("named-task"));
}

test "scheduler dependency validation" {
    const allocator = std.testing.allocator;
    const scheduler = try Scheduler.init(allocator);
    defer scheduler.deinit();

    const Callbacks = struct {
        fn run(task: *Scheduler.ScheduledTask) anyerror!void {
            _ = task;
        }
    };

    const a = try scheduler.addCustomTask("task-a", .{ .once = 0 }, Callbacks.run);
    const b = try scheduler.addCustomTask("task-b", .{ .once = 0 }, Callbacks.run);
    try scheduler.setTaskDependency(a, "task-b");
    try scheduler.setTaskDependency(b, "task-a");

    try std.testing.expectError(error.DependencyCycle, scheduler.validateDependencies());
}

var schedulerTickCalled = false;
var schedulerTickReady: u32 = 0;
var schedulerTickTotal: u32 = 0;

fn testSchedulerTickCallback(ready: u32, total: u32) void {
    schedulerTickCalled = true;
    schedulerTickReady = ready;
    schedulerTickTotal = total;
}

test "scheduler tick callback receives ready and total" {
    const allocator = std.testing.allocator;
    const scheduler = try Scheduler.init(allocator);
    defer scheduler.deinit();

    schedulerTickCalled = false;
    schedulerTickReady = 0;
    schedulerTickTotal = 0;

    _ = try scheduler.addTask("tick-task", .custom, .{ .once = 0 }, .{});
    scheduler.setScheduleTickCallback(&testSchedulerTickCallback);

    scheduler.runPending();

    try std.testing.expect(schedulerTickCalled);
    try std.testing.expect(schedulerTickTotal >= 1);
    try std.testing.expect(schedulerTickReady >= 1);
}

// Windows helper functions
extern "kernel32" fn GetDiskFreeSpaceExW(
    lpDirectoryName: ?[*:0]const u16,
    lpFreeBytesAvailableToCaller: ?*u64,
    lpTotalNumberOfBytes: ?*u64,
    lpTotalNumberOfFreeBytes: ?*u64,
) callconv(.winapi) i32;

test "scheduler phase 3 features (pause/resume)" {
    var sched = try Scheduler.init(std.testing.allocator);
    defer sched.deinit();

    try std.testing.expect(!sched.isPaused.load(.acquire));
    sched.pause();
    try std.testing.expect(sched.isPaused.load(.acquire));
    sched.unpause();
    try std.testing.expect(!sched.isPaused.load(.acquire));
}

test "scheduler task retries and jitter" {
    const task = Scheduler.ScheduledTask{
        .name = "retry_task",
        .taskType = .custom,
        .schedule = .{ .interval = 1000 },
        .retryPolicy = .{
            .maxRetries = 3,
            .intervalMs = 500,
            .backoffMultiplier = 1.5,
        },
    };
    try std.testing.expectEqual(@as(u32, 3), task.retryPolicy.maxRetries);
    try std.testing.expectEqual(@as(u32, 500), task.retryPolicy.intervalMs);
    try std.testing.expectEqual(@as(f32, 1.5), task.retryPolicy.backoffMultiplier);
}
