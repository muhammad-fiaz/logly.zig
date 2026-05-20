//! Task Scheduler Module
//!
//! Provides automated scheduling for log maintenance tasks such as
//! cleanup, rotation, compression, and custom operations.
//!
//! Task Types:
//! - cleanup: Remove old log files based on age or count
//! - rotation: Rotate log files on schedule
//! - compression: Compress archived log files
//! - flush: Flush all sink buffers
//! - health_check: System health monitoring
//! - metrics_snapshot: Periodic metrics collection
//! - custom: User-defined callback tasks
//!
//! Schedule Types:
//! - once: Run once after delay
//! - interval: Run at fixed intervals
//! - daily: Run at specific time each day
//! - cron: Cron-like flexible scheduling
//!
//! Features:
//! - Priority-based task execution
//! - Retry policies with exponential backoff
//! - Task dependencies
//! - Thread pool integration

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
    /// List of scheduled tasks.
    tasks: std.ArrayList(ScheduledTask),
    /// Whether the scheduler is currently running.
    running: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    /// Background worker thread for task execution.
    worker_thread: ?std.Thread = null,
    /// Mutex for thread-safe access to tasks.
    mutex: std.Io.Mutex = std.Io.Mutex.init,
    /// Condition variable for worker thread signaling.
    condition: std.Io.Condition = .init,
    /// Scheduler statistics (tasks executed, failed, etc.).
    stats: SchedulerStats,
    /// Compression utility for compression tasks.
    compression: Compression,
    /// Whether compression has been initialized.
    compression_initialized: bool = false,
    /// Optional thread pool for parallel task execution.
    thread_pool: ?*ThreadPool = null,
    /// Callback for health status checks.
    health_callback: ?*const fn () HealthStatus = null,
    /// Callback for metrics collection.
    metrics_callback: ?*const fn () MetricsSnapshot = null,

    /// Callback invoked when a task starts execution.
    /// Parameters: (task_name: []const u8, run_count: u64)
    on_task_started: ?*const fn ([]const u8, u64) void = null,

    /// Callback invoked when a task completes successfully.
    /// Parameters: (task_name: []const u8, duration_ms: u64)
    on_task_completed: ?*const fn ([]const u8, u64) void = null,

    /// Callback invoked when a task encounters an error.
    /// Parameters: (task_name: []const u8, error_msg: []const u8)
    on_task_error: ?*const fn ([]const u8, []const u8) void = null,

    /// Callback invoked on each scheduler cycle.
    /// Parameters: (tasks_ready: u32, tasks_total: u32)
    on_schedule_tick: ?*const fn (u32, u32) void = null,

    /// Callback invoked during health checks.
    /// Parameters: (status: *const HealthStatus)
    on_health_check: ?*const fn (*const HealthStatus) void = null,

    /// Optional telemetry instance for distributed tracing.
    /// When enabled, task executions create spans for observability.
    telemetry: ?*Telemetry = null,

    /// Centralized scheduler configuration.
    /// Re-exports centralized config for convenience.
    pub const SchedulerConfig = Config.SchedulerConfig;

    /// Health status returned by health checks.
    pub const HealthStatus = struct {
        healthy: bool = true,
        disk_space_ok: bool = true,
        memory_ok: bool = true,
        write_latency_ms: u64 = 0,
        message: ?[]const u8 = null,
    };

    /// Metrics snapshot for monitoring.
    pub const MetricsSnapshot = struct {
        timestamp: i64 = 0,
        log_count: u64 = 0,
        bytes_written: u64 = 0,
        error_count: u64 = 0,
        avg_latency_ms: f64 = 0,
    };

    /// A scheduled task configuration.
    pub const ScheduledTask = struct {
        name: []const u8,
        task_type: TaskType,
        schedule: Schedule,
        callback: ?*const fn (*ScheduledTask) anyerror!void = null,
        last_run: i64 = 0,
        next_run: i64 = 0,
        run_count: u64 = 0,
        error_count: u64 = 0,
        retries_remaining: u32 = 0,
        enabled: bool = true,
        running: bool = false,
        priority: Priority = .normal,
        retry_policy: RetryPolicy = .{},
        depends_on: ?[]const u8 = null,
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
            max_retries: u32 = 3,
            interval_ms: u32 = Constants.SchedulerDefaults.retry_interval_ms,
            backoff_multiplier: f32 = 1.5,
        };

        /// Task-specific configuration.
        pub const TaskConfig = struct {
            /// Path for file-based tasks
            path: ?[]const u8 = null,
            /// Maximum age in seconds for cleanup
            max_age_seconds: u64 = Constants.SchedulerDefaults.max_age_seconds,
            /// Maximum files to keep
            max_files: ?usize = null,
            /// Maximum total size in bytes
            max_total_size: ?u64 = null,
            /// Minimum age in seconds (useful for compression - e.g. compress files older than 1 day)
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
            /// Trigger task only if disk usage exceeds this percentage (0-100, null to disable)
            trigger_disk_usage_percent: ?u8 = null,
            /// Required free space in bytes before running task
            min_free_space_bytes: ?u64 = null,

            /// Create from centralized Config.SchedulerConfig.
            pub fn fromCentralized(cfg: SchedulerConfig) TaskConfig {
                return .{
                    .max_age_seconds = cfg.cleanup_max_age_days * Constants.TimeConstants.seconds_per_day,
                    .max_files = cfg.max_files,
                    .file_pattern = cfg.file_pattern,
                    .compress_before_delete = cfg.compress_before_cleanup,
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
                result.max_age_seconds = days * Constants.TimeConstants.seconds_per_day;
                return result;
            }

            /// Returns a copy with the specified file pattern.
            pub fn withFilePattern(self: TaskConfig, pattern: []const u8) TaskConfig {
                var result = self;
                result.file_pattern = pattern;
                return result;
            }
        };
    };

    /// Immutable task state snapshot for introspection APIs.
    pub const TaskSnapshot = struct {
        name: []const u8,
        task_type: TaskType,
        enabled: bool,
        running: bool,
        next_run: i64,
        last_run: i64,
        run_count: u64,
        error_count: u64,
        retries_remaining: u32,
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
        health_check,
        /// Metrics collection
        metrics_snapshot,
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
            day_of_month: ?u8 = null, // 1-31 or null for any
            month: ?u8 = null, // 1-12 or null for any
            day_of_week: ?u8 = null, // 0-6 (Sunday=0) or null for any
        };

        /// Calculates the next run time from now.
        pub fn nextRunTime(self: Schedule, from_time: i64) i64 {
            const now_ms = from_time;
            return switch (self) {
                .once => |delay| now_ms + @as(i64, @intCast(delay)),
                .interval => |interval| now_ms + @as(i64, @intCast(interval)),
                .daily => |daily| blk: {
                    const now_sec = Utils.currentSeconds();
                    const epoch = std.time.epoch.EpochSeconds{ .secs = @intCast(now_sec) };
                    const day_seconds = epoch.getDaySeconds();

                    const target_seconds = @as(u64, daily.hour) * @as(u64, Constants.TimeConstants.seconds_per_hour) + @as(u64, daily.minute) * @as(u64, Constants.TimeConstants.seconds_per_minute);
                    const current_seconds = day_seconds.secs;

                    if (current_seconds < target_seconds) {
                        // Today
                        break :blk now_ms + @as(i64, @intCast((target_seconds - current_seconds) * @as(u64, Constants.TimeConstants.ms_per_second)));
                    } else {
                        // Tomorrow
                        break :blk now_ms + @as(i64, @intCast((@as(u64, Constants.TimeConstants.seconds_per_day) - current_seconds + target_seconds) * @as(u64, Constants.TimeConstants.ms_per_second)));
                    }
                },
                .cron => |cron| blk: {
                    var check_time = now_ms + Constants.SchedulerDefaults.cron_fallback_interval_ms;
                    // Find closest match within the next 30 days
                    const limit = now_ms + @as(i64, @intCast(30 * @as(u64, Constants.TimeConstants.seconds_per_day) * @as(u64, Constants.TimeConstants.ms_per_second)));
                    while (check_time < limit) : (check_time += @as(i64, @intCast(@as(u64, Constants.TimeConstants.seconds_per_minute) * @as(u64, Constants.TimeConstants.ms_per_second)))) {
                        const sec = @divFloor(check_time, @as(i64, @intCast(Constants.TimeConstants.ms_per_second)));
                        const epoch = std.time.epoch.EpochSeconds{ .secs = @intCast(sec) };
                        const day = epoch.getEpochDay();
                        const year_day = day.calculateYearDay();
                        const month_day = year_day.calculateMonthDay();
                        const day_sec = epoch.getDaySeconds();

                        const minute = @divFloor(day_sec.secs % @as(u64, Constants.TimeConstants.seconds_per_hour), @as(u64, Constants.TimeConstants.seconds_per_minute));
                        const hour = @divFloor(day_sec.secs, @as(u64, Constants.TimeConstants.seconds_per_hour));
                        const month = month_day.month.numeric();
                        const mday = month_day.day_index + 1;
                        // Unix epoch (Jan 1, 1970) was a Thursday (4)
                        const wday = @as(u8, @intCast((day.day + 4) % 7));

                        if (cron.minute != null and cron.minute.? != minute) continue;
                        if (cron.hour != null and cron.hour.? != hour) continue;
                        if (cron.month != null and cron.month.? != month) continue;
                        if (cron.day_of_month != null and cron.day_of_month.? != mday) continue;
                        if (cron.day_of_week != null and cron.day_of_week.? != wday) continue;

                        break :blk check_time;
                    }
                    break :blk now_ms + Constants.SchedulerDefaults.cron_fallback_interval_ms; // Fallback
                },
            };
        }
    };

    /// Statistics for scheduler operations with atomic counters for thread safety.
    pub const SchedulerStats = struct {
        /// Total tasks executed successfully.
        tasks_executed: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        /// Total tasks that failed.
        tasks_failed: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        /// Total files cleaned up.
        files_cleaned: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        /// Total files compressed.
        files_compressed: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        /// Total bytes freed by cleanup operations.
        bytes_freed: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        /// Total bytes saved by compression.
        bytes_saved: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        /// Last run time in milliseconds (uses AtomicSigned for 32-bit platform compatibility).
        last_run_time: std.atomic.Value(Constants.AtomicSigned) = std.atomic.Value(Constants.AtomicSigned).init(0),
        /// Scheduler start time for uptime calculation (uses AtomicSigned for 32-bit platform compatibility).
        start_time: std.atomic.Value(Constants.AtomicSigned) = std.atomic.Value(Constants.AtomicSigned).init(0),

        /// Calculate task success rate (0.0 - 1.0).
        pub fn successRate(self: *const SchedulerStats) f64 {
            const executed = Utils.atomicLoadU64(&self.tasks_executed);
            const failed = Utils.atomicLoadU64(&self.tasks_failed);
            const total = executed + failed;
            return Utils.calculateRate(executed, total);
        }

        /// Calculate task failure rate (0.0 - 1.0).
        pub fn failureRate(self: *const SchedulerStats) f64 {
            const executed = Utils.atomicLoadU64(&self.tasks_executed);
            const failed = Utils.atomicLoadU64(&self.tasks_failed);
            return Utils.calculateErrorRate(failed, executed + failed);
        }

        /// Returns true if any tasks have failed.
        pub fn hasFailures(self: *const SchedulerStats) bool {
            return Utils.atomicLoadU64(&self.tasks_failed) > 0;
        }

        /// Returns total tasks executed as u64.
        pub fn getExecuted(self: *const SchedulerStats) u64 {
            return Utils.atomicLoadU64(&self.tasks_executed);
        }

        /// Returns total tasks failed as u64.
        pub fn getFailed(self: *const SchedulerStats) u64 {
            return Utils.atomicLoadU64(&self.tasks_failed);
        }

        /// Returns total files cleaned as u64.
        pub fn getFilesCleaned(self: *const SchedulerStats) u64 {
            return Utils.atomicLoadU64(&self.files_cleaned);
        }

        /// Returns total files compressed as u64.
        pub fn getFilesCompressed(self: *const SchedulerStats) u64 {
            return Utils.atomicLoadU64(&self.files_compressed);
        }

        /// Returns total bytes freed as u64.
        pub fn getBytesFreed(self: *const SchedulerStats) u64 {
            return Utils.atomicLoadU64(&self.bytes_freed);
        }

        /// Returns total bytes saved by compression as u64.
        pub fn getBytesSaved(self: *const SchedulerStats) u64 {
            return Utils.atomicLoadU64(&self.bytes_saved);
        }

        /// Returns uptime in seconds since scheduler started.
        pub fn uptimeSeconds(self: *const SchedulerStats) i64 {
            const start_ts = self.start_time.load(.monotonic);
            if (start_ts == 0) return 0;
            return @intCast(Utils.elapsedSeconds(start_ts));
        }

        /// Returns average tasks per hour.
        pub fn tasksPerHour(self: *const SchedulerStats) f64 {
            const uptime = self.uptimeSeconds();
            if (uptime <= 0) return 0;
            const executed = Utils.atomicLoadU64(&self.tasks_executed);
            const hours = @as(f64, @floatFromInt(uptime)) / 3600.0;
            return Utils.safeFloatDiv(@as(f64, @floatFromInt(executed)), hours);
        }

        /// Calculate compression ratio (bytes saved / total bytes).
        pub fn compressionRatio(self: *const SchedulerStats) f64 {
            const saved = Utils.atomicLoadU64(&self.bytes_saved);
            const freed = Utils.atomicLoadU64(&self.bytes_freed);
            return Utils.calculateRate(saved, saved + freed);
        }
    };

    /// Cleanup result information.
    pub const CleanupResult = struct {
        files_deleted: usize = 0,
        files_compressed: usize = 0,
        bytes_freed: u64 = 0,
        errors: usize = 0,
    };

    /// Initializes a new Scheduler.
    ///
    /// Arguments:
    ///     allocator: Memory allocator for internal operations.
    ///
    /// Returns:
    ///     A pointer to the new Scheduler instance.
    pub fn init(allocator: std.mem.Allocator) !*Scheduler {
        const self = try allocator.create(Scheduler);
        self.* = .{
            .allocator = allocator,
            .tasks = .empty,
            .stats = .{},
            .compression = Compression.init(allocator),
            .compression_initialized = true,
            .health_callback = null,
            .metrics_callback = null,
        };

        return self;
    }

    /// Alias for init().
    pub const create = init;

    /// Initializes a new Scheduler with a ThreadPool.
    pub fn initWithThreadPool(allocator: std.mem.Allocator, thread_pool: *ThreadPool) !*Scheduler {
        const self = try init(allocator);
        self.thread_pool = thread_pool;
        return self;
    }

    /// Initializes a Scheduler from global Config.SchedulerConfig.
    ///
    /// Arguments:
    ///     allocator: Memory allocator for internal operations.
    ///     config: Global scheduler configuration from Config.
    ///     logs_path: Optional path for log files (used for auto-setup cleanup task).
    ///
    /// Returns:
    ///     A pointer to the new Scheduler instance with configured tasks.
    pub fn initFromConfig(allocator: std.mem.Allocator, config: SchedulerConfig, logs_path: ?[]const u8) !*Scheduler {
        const self = try init(allocator);
        errdefer self.deinit();

        // If scheduler is enabled and path is provided, auto-setup default cleanup task
        if (config.enabled) {
            if (logs_path) |path| {
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

    /// Alias for initFromConfig
    pub const fromConfig = initFromConfig;

    /// Releases all resources.
    pub fn deinit(self: *Scheduler) void {
        self.stop();

        // Deinit compression if initialized
        if (self.compression_initialized) {
            self.compression.deinit();
        }

        for (self.tasks.items) |*task| {
            self.allocator.free(task.name);
            if (task.config.path) |p| self.allocator.free(p);
            if (task.config.file_pattern) |p| self.allocator.free(p);
            if (task.depends_on) |p| self.allocator.free(p);
        }
        self.tasks.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    /// Alias for deinit().
    pub const destroy = deinit;

    /// Sets health check callback.
    pub fn setHealthCallback(self: *Scheduler, callback: *const fn () HealthStatus) void {
        self.health_callback = callback;
    }

    /// Alias for setHealthCallback
    pub const onHealth = setHealthCallback;

    /// Sets metrics callback.
    pub fn setMetricsCallback(self: *Scheduler, callback: *const fn () MetricsSnapshot) void {
        self.metrics_callback = callback;
    }

    /// Alias for setMetricsCallback
    pub const onMetrics = setMetricsCallback;

    /// Gets current health status.
    pub fn getHealthStatus(self: *Scheduler) HealthStatus {
        if (self.health_callback) |cb| {
            return cb();
        }
        // Default health check - check disk space on current directory
        return self.performBasicHealthCheck();
    }

    /// Alias for getHealthStatus
    pub const healthStatus = getHealthStatus;

    /// Gets current metrics snapshot.
    pub fn getMetrics(self: *Scheduler) MetricsSnapshot {
        if (self.metrics_callback) |cb| {
            return cb();
        }
        return .{
            .timestamp = Utils.currentMillis(),
            .log_count = self.stats.getExecuted(),
            .error_count = self.stats.getFailed(),
        };
    }

    /// Alias for getMetrics
    pub const snapshot = getMetrics;

    fn performBasicHealthCheck(_: *Scheduler) HealthStatus {
        var status = HealthStatus{};

        // Check if we can write to current directory
        const test_file = std.Io.Dir.cwd().createFile(Utils.io(), ".health_check_temp", .{}) catch {
            status.healthy = false;
            status.message = "Cannot write to disk";
            return status;
        };
        test_file.close(Utils.io());
        std.Io.Dir.cwd().deleteFile(Utils.io(), ".health_check_temp") catch {};

        return status;
    }

    /// Adds a scheduled task.
    ///
    /// Arguments:
    ///     name: Task identifier.
    ///     task_type: Type of task to schedule.
    ///     schedule: When to run the task.
    ///     config: Task-specific configuration.
    ///
    /// Returns:
    ///     Index of the added task.
    pub fn addTask(
        self: *Scheduler,
        name: []const u8,
        task_type: TaskType,
        schedule: Schedule,
        config: ScheduledTask.TaskConfig,
    ) !usize {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());

        const owned_name = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(owned_name);

        var owned_config = config;
        if (config.path) |p| {
            owned_config.path = try self.allocator.dupe(u8, p);
        }
        errdefer if (owned_config.path) |p| self.allocator.free(p);

        if (config.file_pattern) |p| {
            owned_config.file_pattern = try self.allocator.dupe(u8, p);
        }
        errdefer if (owned_config.file_pattern) |p| self.allocator.free(p);

        const now = Utils.currentMillis();
        const task = ScheduledTask{
            .name = owned_name,
            .task_type = task_type,
            .schedule = schedule,
            .next_run = schedule.nextRunTime(now),
            .config = owned_config,
            .retries_remaining = 3, // Default retries
        };

        try self.tasks.append(self.allocator, task);
        return self.tasks.items.len - 1;
    }

    /// Alias for addTask
    pub const add = addTask;

    /// Configures priority for a specific task.
    pub fn setTaskPriority(self: *Scheduler, index: usize, priority: ScheduledTask.Priority) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        if (index < self.tasks.items.len) {
            self.tasks.items[index].priority = priority;
        }
    }

    /// Alias for setTaskPriority
    pub const setPriority = setTaskPriority;

    /// Configures retry policy for a specific task.
    pub fn setTaskRetryPolicy(self: *Scheduler, index: usize, policy: ScheduledTask.RetryPolicy) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        if (index < self.tasks.items.len) {
            self.tasks.items[index].retry_policy = policy;
            self.tasks.items[index].retries_remaining = policy.max_retries;
        }
    }

    /// Alias for setTaskRetryPolicy
    pub const retry = setTaskRetryPolicy;

    /// Sets a dependency for a task.
    pub fn setTaskDependency(self: *Scheduler, index: usize, dependency_name: []const u8) !void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        if (index < self.tasks.items.len) {
            if (self.tasks.items[index].depends_on) |p| self.allocator.free(p);
            self.tasks.items[index].depends_on = try self.allocator.dupe(u8, dependency_name);
        }
    }

    /// Alias for setTaskDependency
    pub const dependsOn = setTaskDependency;

    /// Validates that every task dependency resolves and that no dependency cycle exists.
    ///
    /// Returns an error if a dependency name cannot be resolved or if following the
    /// dependency chain revisits a task.
    pub fn validateDependencies(self: *Scheduler) !void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());

        for (self.tasks.items, 0..) |task, start_index| {
            _ = task;
            var current_index: usize = start_index;
            var hops: usize = 0;

            while (true) {
                if (hops > self.tasks.items.len) return error.DependencyCycle;

                const current_task = self.tasks.items[current_index];
                const dep_name = current_task.depends_on orelse break;

                var next_index: ?usize = null;
                for (self.tasks.items, 0..) |candidate, candidate_index| {
                    if (std.mem.eql(u8, candidate.name, dep_name)) {
                        next_index = candidate_index;
                        break;
                    }
                }

                const resolved_index = next_index orelse return error.MissingDependency;
                if (resolved_index == start_index) return error.DependencyCycle;

                current_index = resolved_index;
                hops += 1;
            }
        }
    }

    /// Adds a cleanup task for old log files.
    ///
    /// Arguments:
    ///     name: Task identifier.
    ///     path: Directory path to clean.
    ///     max_age_days: Maximum age of files in days.
    ///     schedule: When to run cleanup.
    pub fn addCleanupTask(
        self: *Scheduler,
        name: []const u8,
        path: []const u8,
        max_age_days: u64,
        schedule: Schedule,
    ) !usize {
        return self.addTask(name, .cleanup, schedule, .{
            .path = path,
            .max_age_seconds = max_age_days * Constants.TimeConstants.seconds_per_day,
            .file_pattern = "*.log",
        });
    }

    /// Alias for addCleanupTask
    pub const cleanup = addCleanupTask;

    /// Adds a compression task for log files.
    pub fn addCompressionTask(
        self: *Scheduler,
        name: []const u8,
        path: []const u8,
        schedule: Schedule,
    ) !usize {
        return self.addTask(name, .compression, schedule, .{
            .path = path,
            .file_pattern = "*.log",
        });
    }

    /// Alias for addCompressionTask
    pub const compress = addCompressionTask;

    /// Adds a custom callback task.
    pub fn addCustomTask(
        self: *Scheduler,
        name: []const u8,
        schedule: Schedule,
        callback: *const fn (*ScheduledTask) anyerror!void,
    ) !usize {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());

        const owned_name = try self.allocator.dupe(u8, name);
        const now = Utils.currentMillis();

        const task = ScheduledTask{
            .name = owned_name,
            .task_type = .custom,
            .schedule = schedule,
            .callback = callback,
            .next_run = schedule.nextRunTime(now),
        };

        try self.tasks.append(self.allocator, task);
        return self.tasks.items.len - 1;
    }

    /// Alias for addCustomTask
    pub const custom = addCustomTask;

    /// Enables or disables a task.
    pub fn setTaskEnabled(self: *Scheduler, index: usize, enabled: bool) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        if (index < self.tasks.items.len) {
            self.tasks.items[index].enabled = enabled;
        }
    }

    /// Alias for setTaskEnabled
    pub const enable = setTaskEnabled;

    /// Removes a task by index.
    pub fn removeTask(self: *Scheduler, index: usize) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        if (index < self.tasks.items.len) {
            const task = self.tasks.orderedRemove(index);
            self.allocator.free(task.name);
            if (task.config.path) |p| self.allocator.free(p);
            if (task.config.file_pattern) |p| self.allocator.free(p);
            if (task.depends_on) |p| self.allocator.free(p);
        }
    }

    /// Alias for removeTask
    pub const remove = removeTask;

    /// Finds a task index by name.
    pub fn taskIndexByName(self: *Scheduler, name: []const u8) ?usize {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());

        for (self.tasks.items, 0..) |task, i| {
            if (std.mem.eql(u8, task.name, name)) return i;
        }
        return null;
    }

    /// Returns task snapshot by index.
    pub fn getTaskSnapshot(self: *Scheduler, index: usize) ?TaskSnapshot {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());

        if (index >= self.tasks.items.len) return null;
        const task = self.tasks.items[index];
        return .{
            .name = task.name,
            .task_type = task.task_type,
            .enabled = task.enabled,
            .running = task.running,
            .next_run = task.next_run,
            .last_run = task.last_run,
            .run_count = task.run_count,
            .error_count = task.error_count,
            .retries_remaining = task.retries_remaining,
        };
    }

    /// Returns task snapshot by name.
    pub fn getTaskSnapshotByName(self: *Scheduler, name: []const u8) ?TaskSnapshot {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());

        for (self.tasks.items) |task| {
            if (std.mem.eql(u8, task.name, name)) {
                return .{
                    .name = task.name,
                    .task_type = task.task_type,
                    .enabled = task.enabled,
                    .running = task.running,
                    .next_run = task.next_run,
                    .last_run = task.last_run,
                    .run_count = task.run_count,
                    .error_count = task.error_count,
                    .retries_remaining = task.retries_remaining,
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
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());

        for (self.tasks.items) |*task| {
            if (std.mem.eql(u8, task.name, name)) {
                task.enabled = enabled;
                return true;
            }
        }

        return false;
    }

    /// Removes a task by name.
    ///
    /// Returns true when a task was removed.
    pub fn removeTaskByName(self: *Scheduler, name: []const u8) bool {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());

        for (self.tasks.items, 0..) |task, i| {
            if (std.mem.eql(u8, task.name, name)) {
                const removed = self.tasks.orderedRemove(i);
                self.allocator.free(removed.name);
                if (removed.config.path) |p| self.allocator.free(p);
                if (removed.config.file_pattern) |p| self.allocator.free(p);
                if (removed.depends_on) |p| self.allocator.free(p);
                return true;
            }
        }

        return false;
    }

    /// Returns enabled task count.
    pub fn enabledTaskCount(self: *Scheduler) usize {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());

        var enabled_total: usize = 0;
        for (self.tasks.items) |task| {
            if (task.enabled) enabled_total += 1;
        }
        return enabled_total;
    }

    /// Returns running task count.
    pub fn runningTaskCount(self: *Scheduler) usize {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());

        var running_total: usize = 0;
        for (self.tasks.items) |task| {
            if (task.running) running_total += 1;
        }
        return running_total;
    }

    /// Returns milliseconds until task next run.
    pub fn nextRunInMs(self: *Scheduler, index: usize) ?i64 {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());

        if (index >= self.tasks.items.len) return null;
        const delta = self.tasks.items[index].next_run - Utils.currentMillis();
        return if (delta > 0) delta else 0;
    }

    /// Returns milliseconds until task next run by task name.
    pub fn nextRunInMsByName(self: *Scheduler, name: []const u8) ?i64 {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());

        for (self.tasks.items) |task| {
            if (std.mem.eql(u8, task.name, name)) {
                const delta = task.next_run - Utils.currentMillis();
                return if (delta > 0) delta else 0;
            }
        }

        return null;
    }

    /// Updates schedule for a task and recalculates next run.
    pub fn setTaskSchedule(self: *Scheduler, index: usize, schedule: Schedule) bool {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());

        if (index >= self.tasks.items.len) return false;

        self.tasks.items[index].schedule = schedule;
        self.tasks.items[index].next_run = schedule.nextRunTime(Utils.currentMillis());
        return true;
    }

    /// Forces a task to become runnable on next scheduler pass.
    pub fn rescheduleNow(self: *Scheduler, index: usize) bool {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());

        if (index >= self.tasks.items.len) return false;

        self.tasks.items[index].next_run = Utils.currentMillis();
        self.tasks.items[index].retries_remaining = self.tasks.items[index].retry_policy.max_retries;
        return true;
    }

    /// Sets the callback for task started events.
    pub fn setTaskStartedCallback(self: *Scheduler, callback: *const fn ([]const u8, u64) void) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        self.on_task_started = callback;
    }

    /// Alias for setTaskStartedCallback
    pub const onStarted = setTaskStartedCallback;

    /// Sets the callback for task completed events.
    pub fn setTaskCompletedCallback(self: *Scheduler, callback: *const fn ([]const u8, u64) void) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        self.on_task_completed = callback;
    }

    /// Alias for setTaskCompletedCallback
    pub const onCompleted = setTaskCompletedCallback;

    /// Sets the callback for task error events.
    pub fn setTaskErrorCallback(self: *Scheduler, callback: *const fn ([]const u8, []const u8) void) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        self.on_task_error = callback;
    }

    /// Alias for setTaskErrorCallback
    pub const onError = setTaskErrorCallback;

    /// Sets the callback for schedule tick events.
    pub fn setScheduleTickCallback(self: *Scheduler, callback: *const fn (u32, u32) void) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        self.on_schedule_tick = callback;
    }

    /// Alias for setScheduleTickCallback
    pub const onTick = setScheduleTickCallback;

    /// Sets the callback for health check events.
    pub fn setHealthCheckCallback(self: *Scheduler, callback: *const fn (*const HealthStatus) void) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        self.on_health_check = callback;
    }

    /// Alias for setHealthCheckCallback
    pub const onHealthCheck = setHealthCheckCallback;

    /// Starts the scheduler.
    pub fn start(self: *Scheduler) !void {
        if (self.running.load(.acquire)) return;

        // Record start time for uptime calculations (truncated on 32-bit platforms)
        self.stats.start_time.store(@truncate(Utils.currentMillis()), .monotonic);

        self.running.store(true, .release);
        self.worker_thread = try std.Thread.spawn(.{}, schedulerLoop, .{self});
    }

    /// Stops the scheduler.
    /// Stops the scheduler and waits for pending tasks.
    pub fn stop(self: *Scheduler) void {
        if (!self.running.load(.acquire)) return;

        self.running.store(false, .release);
        self.condition.broadcast(Utils.io());

        // Join the worker loop thread
        if (self.worker_thread) |thread| {
            thread.join();
            self.worker_thread = null;
        }

        // Wait for running tasks to complete (with a 5-second graceful shutdown timeout)
        var wait_loops: u8 = 0;
        while (wait_loops < 50) : (wait_loops += 1) { // 5 second max wait
            var any_running = false;
            self.mutex.lockUncancelable(Utils.io());
            for (self.tasks.items) |task| {
                if (task.running) {
                    any_running = true;
                    break;
                }
            }
            self.mutex.unlock(Utils.io());

            if (!any_running) break;
            Utils.sleepMs(100);
        }
    }

    /// Runs a task immediately regardless of schedule.
    pub fn runNow(self: *Scheduler, index: usize) !void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());

        if (index >= self.tasks.items.len) return;
        try self.executeTask(&self.tasks.items[index]);
    }

    /// Alias for runNow
    pub const run = runNow;

    /// Runs a task immediately by task name.
    ///
    /// Returns true when task exists and was executed.
    pub fn runNowByName(self: *Scheduler, name: []const u8) !bool {
        const index = self.taskIndexByName(name) orelse return false;
        try self.runNow(index);
        return true;
    }

    fn dependenciesSatisfiedLocked(self: *Scheduler, task: *const ScheduledTask) bool {
        if (task.depends_on) |dep_name| {
            for (self.tasks.items) |t| {
                if (std.mem.eql(u8, t.name, dep_name) and t.running) {
                    return false;
                }
            }
        }
        return true;
    }

    fn resourceThresholdsSatisfied(task: *const ScheduledTask, scheduler: *Scheduler) bool {
        if (task.config.trigger_disk_usage_percent) |threshold| {
            const usage = scheduler.getDiskUsage(task.config.path orelse ".") catch return false;
            if (usage < threshold) return false;
        }

        if (task.config.min_free_space_bytes) |min_free| {
            const free = scheduler.getFreeSpace(task.config.path orelse ".") catch return false;
            if (free < min_free) return false;
        }

        return true;
    }

    fn isTaskReadyLocked(self: *Scheduler, task: *const ScheduledTask, now: i64) bool {
        if (!task.enabled or task.running or task.next_run > now) return false;
        if (!self.dependenciesSatisfiedLocked(task)) return false;
        return resourceThresholdsSatisfied(task, self);
    }

    /// Returns number of tasks currently ready to run.
    pub fn readyTaskCount(self: *Scheduler) usize {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());

        const now = Utils.currentMillis();
        var ready_total: usize = 0;
        for (self.tasks.items) |task| {
            if (self.isTaskReadyLocked(&task, now)) ready_total += 1;
        }
        return ready_total;
    }

    /// Runs all pending tasks.
    pub fn runPending(self: *Scheduler) void {
        var tick_cb: ?*const fn (u32, u32) void = null;
        var ready_count: u32 = 0;
        var total_count: u32 = 0;

        self.mutex.lockUncancelable(Utils.io());
        const precheck_now = Utils.currentMillis();
        total_count = @as(u32, @intCast(@min(self.tasks.items.len, std.math.maxInt(u32))));
        for (self.tasks.items) |task| {
            if (self.isTaskReadyLocked(&task, precheck_now)) {
                ready_count += 1;
            }
        }
        tick_cb = self.on_schedule_tick;
        self.mutex.unlock(Utils.io());

        if (tick_cb) |cb| cb(ready_count, total_count);

        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());

        const now = Utils.currentMillis();
        for (self.tasks.items, 0..) |*task, i| {
            if (self.isTaskReadyLocked(task, now)) {
                if (self.thread_pool) |tp| {
                    task.running = true;
                    const TaskCtx = struct {
                        scheduler: *Scheduler,
                        task_index: usize,

                        fn run(ctx_ptr: *anyopaque, _: ?std.mem.Allocator) void {
                            const ctx = @as(*@This(), @ptrCast(@alignCast(ctx_ptr)));
                            defer ctx.scheduler.allocator.destroy(ctx);

                            ctx.scheduler.runTaskByIndex(ctx.task_index) catch |err| {
                                ctx.scheduler.handleTaskError(ctx.task_index, err);
                            };
                        }
                    };

                    const ctx = self.allocator.create(TaskCtx) catch continue;
                    ctx.* = .{
                        .scheduler = self,
                        .task_index = i,
                    };

                    const tp_prio: ThreadPool.WorkItem.Priority = switch (task.priority) {
                        .low => .low,
                        .normal => .normal,
                        .high => .high,
                        .critical => .critical,
                    };

                    if (!tp.submit(.{ .callback = .{ .func = TaskCtx.run, .context = ctx } }, tp_prio)) {
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

    /// Alias for runPending
    pub const pending = runPending;

    fn handleTaskError(self: *Scheduler, index: usize, err: anyerror) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());

        self.handleTaskErrorLocked(index, err);
    }

    fn handleTaskErrorLocked(self: *Scheduler, index: usize, err: anyerror) void {
        if (index >= self.tasks.items.len) return;
        const task = &self.tasks.items[index];

        task.error_count += 1;
        _ = self.stats.tasks_failed.fetchAdd(1, .monotonic);

        if (task.retries_remaining > 0) {
            task.retries_remaining -= 1;
            const delay = @as(u64, @intFromFloat(@as(f32, @floatFromInt(task.retry_policy.interval_ms)) * std.math.pow(f32, task.retry_policy.backoff_multiplier, @floatFromInt(task.retry_policy.max_retries - task.retries_remaining))));
            task.next_run = Utils.currentMillis() + @as(i64, @intCast(delay));

            std.log.warn("Scheduled task '{s}' failed ({s}), retrying in {d}ms ({d} retries left)", .{ task.name, @errorName(err), delay, task.retries_remaining });
        } else {
            if (self.on_task_error) |cb| {
                cb(task.name, @errorName(err));
            } else {
                std.log.err("Scheduled task '{s}' failed: {s}", .{ task.name, @errorName(err) });
            }
        }
    }

    fn runTaskByIndex(self: *Scheduler, index: usize) !void {
        self.mutex.lockUncancelable(Utils.io());
        if (index >= self.tasks.items.len) {
            self.mutex.unlock(Utils.io());
            return;
        }
        const task = &self.tasks.items[index];
        self.mutex.unlock(Utils.io());

        defer {
            self.mutex.lockUncancelable(Utils.io());
            task.running = false;
            self.mutex.unlock(Utils.io());
        }

        try self.executeTask(task);
    }

    fn schedulerLoop(self: *Scheduler) void {
        while (self.running.load(.acquire)) {
            self.runPending();

            // Check every 500ms for more responsive scheduling
            var i: usize = 0;
            while (i < 5 and self.running.load(.acquire)) : (i += 1) {
                Utils.sleepMs(100);
            }
        }
    }

    fn executeTask(self: *Scheduler, task: *ScheduledTask) !void {
        const now = Utils.currentMillis();
        const start_ns = Utils.currentNanos();

        // Start telemetry span if enabled
        var maybe_span: ?Span = null;
        if (self.telemetry) |t| {
            maybe_span = t.startSpan(task.name, .{
                .kind = SpanKind.internal,
            }) catch null;
            if (maybe_span) |*span| {
                span.setAttribute("task.type", .{ .string = @tagName(task.task_type) }) catch {};
                span.setAttribute("task.priority", .{ .string = @tagName(task.priority) }) catch {};
            }
        }

        // Execute task based on type with error tracking
        const exec_result = self.executeTaskCore(task, &maybe_span);

        // Calculate duration
        const duration_ns = Utils.durationSinceNs(start_ns);
        const duration_ms: i64 = @intCast(@divFloor(duration_ns, Constants.TimeConstants.ns_per_ms));

        // End telemetry span
        if (maybe_span) |*span| {
            span.setAttribute("task.duration_ms", .{ .integer = duration_ms }) catch {};
            if (exec_result) |_| {} else |err| {
                span.setStatusWithMessage(.err, @errorName(err)) catch {};
            }
            if (self.telemetry) |t| {
                t.endSpan(span) catch {};
            }
        }

        // Record task execution metrics in telemetry
        if (self.telemetry) |t| {
            t.recordCounter("scheduler.tasks_executed", 1.0) catch {};
            t.recordGauge("scheduler.task_duration_ms", @floatFromInt(duration_ms)) catch {};
        }

        // Propagate error if task failed
        try exec_result;

        task.last_run = now;
        task.next_run = task.schedule.nextRunTime(now);
        task.run_count += 1;
        _ = self.stats.tasks_executed.fetchAdd(1, .monotonic);
        self.stats.last_run_time.store(@truncate(now), .monotonic);
    }

    /// Core task execution logic (separated for telemetry tracking).
    fn executeTaskCore(self: *Scheduler, task: *ScheduledTask, maybe_span: *?Span) !void {
        switch (task.task_type) {
            .cleanup => {
                if (task.config.path) |path| {
                    const result = try self.performCleanup(path, task.config);
                    _ = self.stats.files_cleaned.fetchAdd(@intCast(result.files_deleted), .monotonic);
                    _ = self.stats.bytes_freed.fetchAdd(@intCast(result.bytes_freed), .monotonic);

                    // Record cleanup stats in span
                    if (maybe_span.*) |*span| {
                        span.setAttribute("cleanup.files_deleted", .{ .integer = @intCast(result.files_deleted) }) catch {};
                        span.setAttribute("cleanup.bytes_freed", .{ .integer = @intCast(result.bytes_freed) }) catch {};
                    }
                }
            },
            .compression => {
                if (task.config.path) |path| {
                    const result = try self.performCompression(path, task.config);
                    _ = self.stats.files_compressed.fetchAdd(@intCast(result.files_compressed), .monotonic);
                    _ = self.stats.bytes_saved.fetchAdd(@intCast(result.bytes_saved), .monotonic);

                    // Record compression stats in span
                    if (maybe_span.*) |*span| {
                        span.setAttribute("compression.files", .{ .integer = @intCast(result.files_compressed) }) catch {};
                        span.setAttribute("compression.bytes_saved", .{ .integer = @intCast(result.bytes_saved) }) catch {};
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
            .health_check => {
                // Perform health check and store result
                const health = self.getHealthStatus();
                if (!health.healthy) {
                    task.error_count += 1;
                }
                // Record health status in span
                if (maybe_span.*) |*span| {
                    span.setAttribute("health.healthy", .{ .boolean = health.healthy }) catch {};
                }
            },
            .metrics_snapshot => {
                // Capture metrics snapshot
                const metrics = self.getMetrics();
                if (maybe_span.*) |*span| {
                    span.setAttribute("metrics.log_count", .{ .integer = @intCast(metrics.log_count) }) catch {};
                    span.setAttribute("metrics.error_count", .{ .integer = @intCast(metrics.error_count) }) catch {};
                }
            },
        }
    }

    fn performCleanup(self: *Scheduler, path: []const u8, config: ScheduledTask.TaskConfig) !CleanupResult {
        var result = CleanupResult{};
        const now = Utils.currentSeconds();
        const max_age = @as(i64, @intCast(config.max_age_seconds));

        var dir = std.Io.Dir.cwd().openDir(Utils.io(), path, .{ .iterate = true }) catch {
            return result;
        };
        defer dir.close(Utils.io());

        // Collect file info for ranking
        var files: std.ArrayList(FileInfo) = .empty;
        defer {
            for (files.items) |fi| {
                self.allocator.free(fi.name);
            }
            files.deinit(self.allocator);
        }

        var iter = dir.iterate();
        var total_size: u64 = 0;
        while (try iter.next(Utils.io())) |entry| {
            if (entry.kind != .file) continue;

            // Check file pattern
            if (config.file_pattern) |pattern| {
                if (!matchPattern(entry.name, pattern)) continue;
            }

            // Get file stats
            const file = dir.openFile(Utils.io(), entry.name, .{}) catch continue;
            const stat = file.stat(Utils.io()) catch {
                file.close(Utils.io());
                continue;
            };
            file.close(Utils.io());

            const mtime = stat.mtime.toSeconds();
            const age = now - mtime;

            const name_copy = self.allocator.dupe(u8, entry.name) catch continue;
            files.append(self.allocator, .{
                .name = name_copy,
                .mtime = mtime,
                .size = stat.size,
                .age = age,
            }) catch {
                self.allocator.free(name_copy);
                continue;
            };
            total_size += stat.size;
        }

        // Sort by modification time (oldest first)
        std.mem.sort(FileInfo, files.items, {}, struct {
            fn lessThan(_: void, a: FileInfo, b: FileInfo) bool {
                return a.mtime < b.mtime;
            }
        }.lessThan);

        // Track what we delete
        var deleted_indices = std.DynamicBitSet.initEmpty(self.allocator, files.items.len) catch return result;
        defer deleted_indices.deinit();

        // 1. Delete files based on age (or compress based on mode)
        for (files.items, 0..) |fi, i| {
            if (fi.age > max_age) {
                const already_compressed = Constants.CompressionExtensions.isCompressed(fi.name);
                const should_skip_compressed = config.skip_already_compressed and already_compressed;

                // Mode: Compress only (no deletion)
                if (config.compress_only) {
                    if (self.compression_initialized and !should_skip_compressed) {
                        const full_path = try std.fs.path.join(self.allocator, &[_][]const u8{ path, fi.name });
                        defer self.allocator.free(full_path);
                        _ = self.compression.compressFile(full_path, null) catch {};
                        result.files_compressed += 1;
                    }
                    continue; // Don't delete anything
                }

                // Mode: Compress and keep both original and compressed
                if (config.compress_and_keep and self.compression_initialized and !should_skip_compressed) {
                    const full_path = try std.fs.path.join(self.allocator, &[_][]const u8{ path, fi.name });
                    defer self.allocator.free(full_path);
                    _ = self.compression.compressFile(full_path, null) catch {};
                    result.files_compressed += 1;
                    continue; // Keep original, don't delete
                }

                // Mode: Compress before delete (compress then delete original)
                if (config.compress_before_delete and self.compression_initialized and !should_skip_compressed) {
                    const full_path = try std.fs.path.join(self.allocator, &[_][]const u8{ path, fi.name });
                    defer self.allocator.free(full_path);
                    _ = self.compression.compressFile(full_path, null) catch {};
                    result.files_compressed += 1;
                }

                // Default: Delete the file
                dir.deleteFile(Utils.io(), fi.name) catch {
                    result.errors += 1;
                    continue;
                };

                result.files_deleted += 1;
                result.bytes_freed += fi.size;
                total_size -= fi.size;
                deleted_indices.set(i);
            }
        }

        // 2. Enforce max files limit
        if (config.max_files) |max| {
            var current_count = files.items.len - result.files_deleted;
            if (current_count > max) {
                for (files.items, 0..) |fi, i| {
                    if (deleted_indices.isSet(i)) continue;
                    if (current_count <= max) break;

                    dir.deleteFile(Utils.io(), fi.name) catch {
                        result.errors += 1;
                        continue;
                    };

                    result.files_deleted += 1;
                    result.bytes_freed += fi.size;
                    total_size -= fi.size;
                    deleted_indices.set(i);
                    current_count -= 1;
                }
            }
        }

        // 3. Enforce max total size limit
        if (config.max_total_size) |max_size| {
            if (total_size > max_size) {
                for (files.items, 0..) |fi, i| {
                    if (deleted_indices.isSet(i)) continue;
                    if (total_size <= max_size) break;

                    dir.deleteFile(Utils.io(), fi.name) catch {
                        result.errors += 1;
                        continue;
                    };

                    result.files_deleted += 1;
                    result.bytes_freed += fi.size;
                    total_size -= fi.size;
                    deleted_indices.set(i);
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
        files_compressed: usize = 0,
        bytes_before: u64 = 0,
        bytes_after: u64 = 0,
        bytes_saved: u64 = 0,
        errors: usize = 0,
    };

    fn performCompression(self: *Scheduler, path: []const u8, config: ScheduledTask.TaskConfig) !CompressionTaskResult {
        var result = CompressionTaskResult{};

        if (!self.compression_initialized) return result;

        var dir = std.Io.Dir.cwd().openDir(Utils.io(), path, .{ .iterate = true }) catch return result;
        defer dir.close(Utils.io());

        var iter = dir.iterate();
        const now = Utils.currentSeconds();
        while (try iter.next(Utils.io())) |entry| {
            if (entry.kind != .file) continue;

            // Skip already compressed files
            if (Constants.CompressionExtensions.isCompressed(entry.name)) continue;

            // Check pattern
            if (config.file_pattern) |pattern| {
                if (!matchPattern(entry.name, pattern)) continue;
            }

            // Check age if min_age_seconds is set
            if (config.min_age_seconds > 0) {
                const file = dir.openFile(Utils.io(), entry.name, .{}) catch continue;
                const stat = file.stat(Utils.io()) catch {
                    file.close(Utils.io());
                    continue;
                };
                file.close(Utils.io());
                const mtime = stat.mtime.toSeconds();
                if (now - mtime < @as(i64, @intCast(config.min_age_seconds))) continue;
            }

            // Build full path
            const full_path = std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ path, entry.name }) catch continue;
            defer self.allocator.free(full_path);

            // Compress the file
            const comp_result = self.compression.compressFile(full_path, null) catch {
                result.errors += 1;
                continue;
            };

            if (comp_result.success) {
                result.files_compressed += 1;
                result.bytes_before += comp_result.original_size;
                result.bytes_after += comp_result.compressed_size;
                if (comp_result.original_size > comp_result.compressed_size) {
                    result.bytes_saved += comp_result.original_size - comp_result.compressed_size;
                }

                // Free the output path if allocated
                if (comp_result.output_path) |out_path| {
                    self.allocator.free(out_path);
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

    /// Resets statistics.
    pub fn resetStats(self: *Scheduler) void {
        self.stats = .{};
    }

    /// Alias for resetStats
    pub const clearStats = resetStats;

    /// Sets the telemetry instance for distributed tracing.
    /// When set, task executions will create spans for observability.
    pub fn setTelemetry(self: *Scheduler, telemetry: *Telemetry) void {
        self.telemetry = telemetry;
    }

    /// Alias for setTelemetry
    pub const trace = setTelemetry;

    /// Clears the telemetry instance.
    pub fn clearTelemetry(self: *Scheduler) void {
        self.telemetry = null;
    }

    /// Alias for clearTelemetry
    pub const noTelemetry = clearTelemetry;

    /// Gets list of all tasks.
    pub fn getTasks(self: *const Scheduler) []const ScheduledTask {
        return self.tasks.items;
    }

    /// Alias for getTasks
    pub const tasks_ = getTasks;

    /// Returns the number of tasks.
    pub fn taskCount(self: *const Scheduler) usize {
        return self.tasks.items.len;
    }

    /// Alias for taskCount
    pub const count = taskCount;

    /// Alias for taskIndexByName
    pub const indexOfTask = taskIndexByName;

    /// Alias for getTaskSnapshot
    pub const snapshotTask = getTaskSnapshot;

    /// Alias for getTaskSnapshotByName
    pub const snapshotTaskByName = getTaskSnapshotByName;

    /// Alias for hasTaskNamed
    pub const hasTask = hasTaskNamed;

    /// Alias for setTaskEnabledByName
    pub const enableByName = setTaskEnabledByName;

    /// Alias for removeTaskByName
    pub const removeNamed = removeTaskByName;

    /// Alias for enabledTaskCount
    pub const enabledCount = enabledTaskCount;

    /// Alias for runningTaskCount
    pub const runningCount = runningTaskCount;

    /// Alias for readyTaskCount
    pub const readyCount = readyTaskCount;

    /// Alias for nextRunInMs
    pub const nextRunMs = nextRunInMs;

    /// Alias for nextRunInMsByName
    pub const nextRunForTask = nextRunInMsByName;

    /// Alias for setTaskSchedule
    pub const updateSchedule = setTaskSchedule;

    /// Alias for rescheduleNow
    pub const runSoon = rescheduleNow;

    /// Alias for runNowByName
    pub const runNamed = runNowByName;

    /// Returns true if the scheduler is running.
    pub fn isRunning(self: *const Scheduler) bool {
        return self.running.load(.acquire);
    }

    /// Alias for isRunning
    pub const running_ = isRunning;

    /// Returns true if any tasks are scheduled.
    pub fn hasTasks(self: *const Scheduler) bool {
        return self.tasks.items.len > 0;
    }

    /// Alias for hasTasks
    pub const has_ = hasTasks;

    /// Alias for start
    pub const begin = start;

    /// Alias for stop
    pub const end = stop;
    pub const halt = stop;

    /// Alias for getStats
    pub const statistics = getStats;

    fn getDiskUsage(_: *Scheduler, path: []const u8) !u8 {
        if (@import("builtin").os.tag == .windows) {
            var free_bytes: u64 = 0;
            var total_bytes: u64 = 0;
            var total_free: u64 = 0;

            const path_w = try std.unicode.utf8ToUtf16LeAllocZ(std.heap.page_allocator, path);
            defer std.heap.page_allocator.free(path_w);

            if (GetDiskFreeSpaceExW(path_w.ptr, &free_bytes, &total_bytes, &total_free) == 0) {
                return 0;
            }
            if (total_bytes == 0) return 0;
            return @intCast(100 - (free_bytes * 100 / total_bytes));
        } else {
            if (comptime @hasDecl(std.posix, "statvfs")) {
                const path_c = try std.heap.page_allocator.dupeZ(u8, path);
                defer std.heap.page_allocator.free(path_c);

                var stat: std.posix.statvfs = undefined;
                try std.posix.statvfs(path_c, &stat);

                if (stat.blocks == 0) return 0;
                return @intCast(100 - (stat.bfree * 100 / stat.blocks));
            } else {
                return 0; // Fallback for systems where statvfs is not available in std.posix
            }
        }
    }

    fn getFreeSpace(_: *Scheduler, path: []const u8) !u64 {
        if (@import("builtin").os.tag == .windows) {
            var free_bytes: u64 = 0;
            var total_bytes: u64 = 0;
            var total_free: u64 = 0;

            const path_w = try std.unicode.utf8ToUtf16LeAllocZ(std.heap.page_allocator, path);
            defer std.heap.page_allocator.free(path_w);

            if (GetDiskFreeSpaceExW(path_w.ptr, &free_bytes, &total_bytes, &total_free) == 0) {
                return 0;
            }
            return free_bytes;
        } else {
            if (comptime @hasDecl(std.posix, "statvfs")) {
                const path_c = try std.heap.page_allocator.dupeZ(u8, path);
                defer std.heap.page_allocator.free(path_c);

                var stat: std.posix.statvfs = undefined;
                try std.posix.statvfs(path_c, &stat);

                return stat.bfree * stat.frsize;
            } else {
                return 0; // Fallback for systems where statvfs is not available in std.posix
            }
        }
    }
};

fn matchPattern(name: []const u8, pattern: []const u8) bool {
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
    pub fn dailyCleanup(path: []const u8, max_age_days: u64) Scheduler.ScheduledTask.TaskConfig {
        return .{
            .path = path,
            .max_age_seconds = max_age_days * Constants.TimeConstants.seconds_per_day,
            .file_pattern = "*.log",
        };
    }

    /// Weekly cleanup on Sunday at 2 AM.
    pub fn weeklyCleanup() Scheduler.Schedule {
        return .{ .cron = .{
            .hour = 2,
            .minute = 0,
            .day_of_week = 0,
        } };
    }

    /// Hourly compression.
    pub fn hourlyCompression() Scheduler.Schedule {
        return .{ .interval = Constants.TimeConstants.seconds_per_hour * Constants.TimeConstants.ms_per_second };
    }

    /// Every N minutes.
    pub fn everyMinutes(n: u64) Scheduler.Schedule {
        return .{ .interval = n * Constants.TimeConstants.seconds_per_minute * Constants.TimeConstants.ms_per_second };
    }

    /// Daily at specific time.
    pub fn dailyAt(hour: u8, minute: u8) Scheduler.Schedule {
        return .{ .daily = .{ .hour = hour, .minute = minute } };
    }

    /// Creates a scheduled log sink configuration.
    pub fn createScheduledSink(file_path: []const u8, rotation: []const u8) SinkConfig {
        return SinkConfig{
            .path = file_path,
            .rotation = rotation,
            .retention = 7,
            .color = false,
        };
    }

    /// Every 30 minutes.
    pub fn every30Minutes() Scheduler.Schedule {
        return .{ .interval = 30 * Constants.TimeConstants.seconds_per_minute * Constants.TimeConstants.ms_per_second };
    }

    /// Every 6 hours.
    pub fn every6Hours() Scheduler.Schedule {
        return .{ .interval = 6 * Constants.TimeConstants.seconds_per_hour * Constants.TimeConstants.ms_per_second };
    }

    /// Every 12 hours.
    pub fn every12Hours() Scheduler.Schedule {
        return .{ .interval = 12 * Constants.TimeConstants.seconds_per_hour * Constants.TimeConstants.ms_per_second };
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
    pub fn weeklyCleanupConfig(path: []const u8, max_age_days: u64) Scheduler.ScheduledTask.TaskConfig {
        return dailyCleanup(path, max_age_days);
    }

    /// Compress files older than N days, then delete originals.
    /// Use this to archive logs before cleanup.
    pub fn compressThenDelete(path: []const u8, min_age_days: u64) Scheduler.ScheduledTask.TaskConfig {
        return .{
            .path = path,
            .min_age_seconds = min_age_days * Constants.TimeConstants.seconds_per_day,
            .file_pattern = "*.log",
            .compress_before_delete = true,
            .skip_already_compressed = true,
        };
    }

    /// Compress files older than N days, keep both original and compressed.
    /// Use this for redundant archival where you need both versions.
    pub fn compressAndKeep(path: []const u8, min_age_days: u64) Scheduler.ScheduledTask.TaskConfig {
        return .{
            .path = path,
            .min_age_seconds = min_age_days * Constants.TimeConstants.seconds_per_day,
            .file_pattern = "*.log",
            .compress_and_keep = true,
            .skip_already_compressed = true,
        };
    }

    /// Only compress files, never delete anything.
    /// Use this for pure archival without any deletion.
    pub fn compressOnly(path: []const u8, min_age_days: u64) Scheduler.ScheduledTask.TaskConfig {
        return .{
            .path = path,
            .min_age_seconds = min_age_days * Constants.TimeConstants.seconds_per_day,
            .file_pattern = "*.log",
            .compress_only = true,
            .skip_already_compressed = true,
        };
    }

    /// Archive old logs: compress files older than N days, delete originals after compression.
    /// Similar to compressThenDelete but with max_age enforcement.
    pub fn archiveOldLogs(path: []const u8, compress_after_days: u64, delete_after_days: u64) Scheduler.ScheduledTask.TaskConfig {
        return .{
            .path = path,
            .min_age_seconds = compress_after_days * Constants.TimeConstants.seconds_per_day,
            .max_age_seconds = delete_after_days * Constants.TimeConstants.seconds_per_day,
            .file_pattern = "*.log",
            .compress_before_delete = true,
            .skip_already_compressed = true,
        };
    }

    /// Aggressive cleanup: compress and delete files older than N days, enforce max file count.
    pub fn aggressiveCleanup(path: []const u8, max_age_days: u64, max_files: usize) Scheduler.ScheduledTask.TaskConfig {
        return .{
            .path = path,
            .max_age_seconds = max_age_days * Constants.TimeConstants.seconds_per_day,
            .max_files = max_files,
            .file_pattern = "*.log",
            .compress_before_delete = true,
            .skip_already_compressed = true,
        };
    }

    /// Compress files older than 1 day on an hourly schedule.
    pub fn hourlyArchive(path: []const u8) Scheduler.ScheduledTask.TaskConfig {
        return .{
            .path = path,
            .min_age_seconds = Constants.TimeConstants.seconds_per_day, // 1 day
            .file_pattern = "*.log",
            .compress_only = true,
            .skip_already_compressed = true,
        };
    }

    /// Compress on rotation: for files that have just rotated.
    pub fn compressOnRotation(path: []const u8) Scheduler.ScheduledTask.TaskConfig {
        return .{
            .path = path,
            .min_age_seconds = Constants.TimeConstants.seconds_per_minute, // At least 1 minute old (just rotated)
            .file_pattern = "*.log.*",
            .compress_only = true,
            .skip_already_compressed = true,
        };
    }

    /// Size-based compression trigger: compress when total size exceeds threshold.
    pub fn sizeBasedCompression(path: []const u8, max_total_bytes: u64) Scheduler.ScheduledTask.TaskConfig {
        return .{
            .path = path,
            .max_total_size = max_total_bytes,
            .file_pattern = "*.log",
            .compress_only = true,
            .skip_already_compressed = true,
        };
    }

    /// Disk usage triggered compression: only run when disk usage exceeds threshold.
    pub fn diskUsageTriggered(path: []const u8, disk_usage_percent: u8) Scheduler.ScheduledTask.TaskConfig {
        return .{
            .path = path,
            .file_pattern = "*.log",
            .compress_before_delete = true,
            .skip_already_compressed = true,
            .trigger_disk_usage_percent = disk_usage_percent,
        };
    }

    /// Low disk space triggered: only run when free space is below threshold.
    pub fn lowDiskSpaceTriggered(path: []const u8, min_free_bytes: u64) Scheduler.ScheduledTask.TaskConfig {
        return .{
            .path = path,
            .file_pattern = "*.log",
            .compress_before_delete = true,
            .skip_already_compressed = true,
            .min_free_space_bytes = min_free_bytes,
        };
    }

    /// Recursive directory compression for nested log structures.
    pub fn recursiveCompression(path: []const u8, min_age_days: u64) Scheduler.ScheduledTask.TaskConfig {
        return .{
            .path = path,
            .min_age_seconds = min_age_days * Constants.TimeConstants.seconds_per_day,
            .file_pattern = "*.log",
            .compress_only = true,
            .skip_already_compressed = true,
            .recursive = true,
        };
    }

    /// Every 15 minutes.
    pub fn every15Minutes() Scheduler.Schedule {
        return .{ .interval = 15 * Constants.TimeConstants.seconds_per_minute * Constants.TimeConstants.ms_per_second };
    }

    /// Once after delay in seconds.
    pub fn onceAfter(seconds: u64) Scheduler.Schedule {
        return .{ .once = seconds * Constants.TimeConstants.ms_per_second };
    }

    /// Creates a health check schedule (every 5 minutes).
    pub fn healthCheckSchedule() Scheduler.Schedule {
        return .{ .interval = 5 * Constants.TimeConstants.seconds_per_minute * Constants.TimeConstants.ms_per_second };
    }

    /// Creates a metrics collection schedule (every minute).
    pub fn metricsSchedule() Scheduler.Schedule {
        return .{ .interval = Constants.TimeConstants.seconds_per_minute * Constants.TimeConstants.ms_per_second };
    }
};

test "scheduler basic" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const scheduler = try Scheduler.init(allocator);
    defer scheduler.deinit();

    _ = try scheduler.addTask("test", .cleanup, .{ .interval = Constants.TimeConstants.rotation_check_interval_ms }, .{});

    try std.testing.expectEqual(@as(usize, 1), scheduler.tasks.items.len);
}

test "schedule next run time" {
    const now = Utils.currentMillis();

    const interval = Scheduler.Schedule{ .interval = Constants.SchedulerDefaults.retry_interval_ms };
    const next = interval.nextRunTime(now);

    try std.testing.expect(next > now);
    try std.testing.expect(next <= now + @as(i64, @intCast(Constants.SchedulerDefaults.retry_interval_ms)));
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

    const tmp_path = ".test_logs_maintenance";
    std.Io.Dir.cwd().createDir(Utils.io(), tmp_path, .default_dir) catch {};
    defer std.Io.Dir.cwd().deleteTree(Utils.io(), tmp_path) catch {};

    var dir = try std.Io.Dir.cwd().openDir(Utils.io(), tmp_path, .{ .iterate = true });
    defer dir.close(Utils.io());

    // Create initial set of log files for testing limit enforcement
    var i: usize = 0;
    while (i < 10) : (i += 1) {
        const name = try std.fmt.allocPrint(allocator, "test_{d}.log", .{i});
        defer allocator.free(name);
        const file = try dir.createFile(Utils.io(), name, .{});
        try file.writeStreamingAll(Utils.io(), "test content");
        file.close(Utils.io());
    }

    // Create additional files to test overflow handling
    while (i < 15) : (i += 1) {
        const name = try std.fmt.allocPrint(allocator, "new_{d}.log", .{i});
        defer allocator.free(name);
        const file = try dir.createFile(Utils.io(), name, .{});
        try file.writeStreamingAll(Utils.io(), "new log content");
        file.close(Utils.io());
    }

    // Verify max_files constraint enforcement
    var config = Scheduler.ScheduledTask.TaskConfig{
        .path = tmp_path,
        .max_files = 5,
        .file_pattern = "*.log",
    };

    const result = try scheduler.performCleanup(tmp_path, config);
    try std.testing.expectEqual(@as(usize, 10), result.files_deleted);

    var count: usize = 0;
    var iter = dir.iterate();
    while (try iter.next(Utils.io())) |_| {
        count += 1;
    }
    try std.testing.expectEqual(@as(usize, 5), count);

    // Verify max_total_size constraint enforcement
    {
        const file = try dir.createFile(Utils.io(), "large.log", .{});
        try file.writeStreamingAll(Utils.io(), &([_]u8{'A'} ** Constants.SizeConstants.bytes_per_kb));
        file.close(Utils.io());
    }

    config.max_files = null;
    config.max_total_size = 500;

    const result2 = try scheduler.performCleanup(tmp_path, config);
    try std.testing.expect(result2.files_deleted >= 1);
}

test "scheduler task introspection helpers" {
    const allocator = std.testing.allocator;
    const scheduler = try Scheduler.init(allocator);
    defer scheduler.deinit();

    const idx_a = try scheduler.addTask("introspect-a", .custom, .{ .once = 0 }, .{});
    const idx_b = try scheduler.addTask("introspect-b", .custom, .{ .interval = Constants.TimeConstants.rotation_check_interval_ms }, .{});

    try std.testing.expectEqual(@as(?usize, idx_a), scheduler.taskIndexByName("introspect-a"));
    try std.testing.expect(scheduler.hasTaskNamed("introspect-b"));
    try std.testing.expect(!scheduler.hasTaskNamed("missing-task"));

    scheduler.setTaskEnabled(idx_b, false);
    try std.testing.expectEqual(@as(usize, 1), scheduler.enabledTaskCount());

    const next_a = scheduler.nextRunInMs(idx_a);
    try std.testing.expect(next_a != null);
    try std.testing.expect(next_a.? >= 0);

    try std.testing.expect(scheduler.setTaskSchedule(idx_b, .{ .once = 0 }));
    try std.testing.expect(scheduler.rescheduleNow(idx_b));
}

test "scheduler name based controls and snapshots" {
    const allocator = std.testing.allocator;
    const scheduler = try Scheduler.init(allocator);
    defer scheduler.deinit();

    const idx = try scheduler.addTask("named-task", .custom, .{ .interval = Constants.TimeConstants.rotation_check_interval_ms }, .{});
    try std.testing.expectEqual(@as(usize, 0), idx);

    const snapshot = scheduler.getTaskSnapshot(idx);
    try std.testing.expect(snapshot != null);
    try std.testing.expectEqualStrings("named-task", snapshot.?.name);
    try std.testing.expect(snapshot.?.enabled);

    const named_snapshot = scheduler.getTaskSnapshotByName("named-task");
    try std.testing.expect(named_snapshot != null);
    try std.testing.expectEqual(Scheduler.TaskType.custom, named_snapshot.?.task_type);

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

var scheduler_tick_called = false;
var scheduler_tick_ready: u32 = 0;
var scheduler_tick_total: u32 = 0;

fn testSchedulerTickCallback(ready: u32, total: u32) void {
    scheduler_tick_called = true;
    scheduler_tick_ready = ready;
    scheduler_tick_total = total;
}

test "scheduler tick callback receives ready and total" {
    const allocator = std.testing.allocator;
    const scheduler = try Scheduler.init(allocator);
    defer scheduler.deinit();

    scheduler_tick_called = false;
    scheduler_tick_ready = 0;
    scheduler_tick_total = 0;

    _ = try scheduler.addTask("tick-task", .custom, .{ .once = 0 }, .{});
    scheduler.setScheduleTickCallback(&testSchedulerTickCallback);

    scheduler.runPending();

    try std.testing.expect(scheduler_tick_called);
    try std.testing.expect(scheduler_tick_total >= 1);
    try std.testing.expect(scheduler_tick_ready >= 1);
}

// Windows helper functions
extern "kernel32" fn GetDiskFreeSpaceExW(
    lpDirectoryName: ?[*:0]const u16,
    lpFreeBytesAvailableToCaller: ?*u64,
    lpTotalNumberOfBytes: ?*u64,
    lpTotalNumberOfFreeBytes: ?*u64,
) callconv(.winapi) i32;
