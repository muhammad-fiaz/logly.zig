const std = @import("std");
const Config = @import("config.zig").Config;
const Compression = @import("compression.zig").Compression;
const SinkConfig = @import("sink.zig").SinkConfig;
const ThreadPool = @import("thread_pool.zig").ThreadPool;

/// Scheduler for automated log maintenance tasks.
///
/// Provides scheduled execution of tasks like log cleanup, rotation,
/// compression, and custom maintenance operations.
///
/// Callbacks:
/// - `on_task_started`: Called when a scheduled task starts execution
/// - `on_task_completed`: Called when a task completes successfully
/// - `on_task_error`: Called when a task fails
/// - `on_schedule_tick`: Called on each scheduler cycle
/// - `on_health_check`: Called when health status is checked
///
/// Performance:
/// - O(n) per cycle where n = number of tasks
/// - Minimal overhead: only active tasks are evaluated
/// - Lock-free read operations for task status
pub const Scheduler = struct {
    allocator: std.mem.Allocator,
    tasks: std.ArrayList(ScheduledTask),
    running: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    worker_thread: ?std.Thread = null,
    mutex: std.Thread.Mutex = .{},
    condition: std.Thread.Condition = .{},
    stats: SchedulerStats,
    compression: Compression,
    compression_initialized: bool = false,
    thread_pool: ?*ThreadPool = null,
    health_callback: ?*const fn () HealthStatus = null,
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

        /// Task-specific configuration.
        pub const TaskConfig = struct {
            /// Path for file-based tasks
            path: ?[]const u8 = null,
            /// Maximum age in seconds for cleanup
            max_age_seconds: u64 = 7 * 24 * 60 * 60, // 7 days
            /// Maximum files to keep
            max_files: ?usize = null,
            /// Maximum total size in bytes
            max_total_size: ?u64 = null,
            /// Minimum age in seconds (useful for compression - e.g. compress files older than 1 day)
            min_age_seconds: u64 = 0,
            /// File pattern to match (e.g., "*.log")
            file_pattern: ?[]const u8 = null,
            /// Compress files before cleanup
            compress_before_delete: bool = false,
            /// Recursive directory processing
            recursive: bool = false,
            /// Trigger task only if disk usage exceeds this percentage (0-100, null to disable)
            trigger_disk_usage_percent: ?u8 = null,
            /// Required free space in bytes before running task
            min_free_space_bytes: ?u64 = null,

            /// Create from centralized Config.SchedulerConfig.
            pub fn fromCentralized(cfg: SchedulerConfig) TaskConfig {
                return .{
                    .max_age_seconds = cfg.cleanup_max_age_days * 24 * 60 * 60,
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
                result.max_age_seconds = days * 24 * 60 * 60;
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

        pub const DailySchedule = struct {
            hour: u8 = 0,
            minute: u8 = 0,
        };

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
                    const now_sec = @divFloor(now_ms, 1000);
                    const epoch = std.time.epoch.EpochSeconds{ .secs = @intCast(now_sec) };
                    const day_seconds = epoch.getDaySeconds();

                    const target_seconds = @as(u64, daily.hour) * 3600 + @as(u64, daily.minute) * 60;
                    const current_seconds = day_seconds.secs;

                    if (current_seconds < target_seconds) {
                        // Today
                        break :blk now_ms + @as(i64, @intCast((target_seconds - current_seconds) * 1000));
                    } else {
                        // Tomorrow
                        break :blk now_ms + @as(i64, @intCast((24 * 3600 - current_seconds + target_seconds) * 1000));
                    }
                },
                .cron => |cron| blk: {
                    var check_time = now_ms + 60 * 1000;
                    // Find closest match within the next 30 days
                    const limit = now_ms + 30 * 24 * 3600 * 1000;
                    while (check_time < limit) : (check_time += 60 * 1000) {
                        const sec = @divFloor(check_time, 1000);
                        const epoch = std.time.epoch.EpochSeconds{ .secs = @intCast(sec) };
                        const day = epoch.getEpochDay();
                        const year_day = day.calculateYearDay();
                        const month_day = year_day.calculateMonthDay();
                        const day_sec = epoch.getDaySeconds();

                        const minute = @divFloor(day_sec.secs % 3600, 60);
                        const hour = @divFloor(day_sec.secs, 3600);
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
                    break :blk now_ms + 60 * 1000; // Fallback
                },
            };
        }
    };

    /// Statistics for scheduler operations.
    pub const SchedulerStats = struct {
        tasks_executed: u64 = 0,
        tasks_failed: u64 = 0,
        files_cleaned: u64 = 0,
        bytes_freed: u64 = 0,
        last_run_time: i64 = 0,
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
        }
        self.tasks.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    /// Sets health check callback.
    pub fn setHealthCallback(self: *Scheduler, callback: *const fn () HealthStatus) void {
        self.health_callback = callback;
    }

    /// Sets metrics callback.
    pub fn setMetricsCallback(self: *Scheduler, callback: *const fn () MetricsSnapshot) void {
        self.metrics_callback = callback;
    }

    /// Gets current health status.
    pub fn getHealthStatus(self: *Scheduler) HealthStatus {
        if (self.health_callback) |cb| {
            return cb();
        }
        // Default health check - check disk space on current directory
        return self.performBasicHealthCheck();
    }

    /// Gets current metrics snapshot.
    pub fn getMetrics(self: *Scheduler) MetricsSnapshot {
        if (self.metrics_callback) |cb| {
            return cb();
        }
        return .{
            .timestamp = std.time.milliTimestamp(),
            .log_count = self.stats.tasks_executed,
            .error_count = self.stats.tasks_failed,
        };
    }

    fn performBasicHealthCheck(_: *Scheduler) HealthStatus {
        var status = HealthStatus{};

        // Check if we can write to current directory
        const test_file = std.fs.cwd().createFile(".health_check_temp", .{}) catch {
            status.healthy = false;
            status.message = "Cannot write to disk";
            return status;
        };
        test_file.close();
        std.fs.cwd().deleteFile(".health_check_temp") catch {};

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
        self.mutex.lock();
        defer self.mutex.unlock();

        const owned_name = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(owned_name);

        var owned_config = config;
        if (config.path) |p| {
            owned_config.path = try self.allocator.dupe(u8, p);
        }
        if (config.file_pattern) |p| {
            owned_config.file_pattern = try self.allocator.dupe(u8, p);
        }

        const now = std.time.milliTimestamp();
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

    /// Configures priority for a specific task.
    pub fn setTaskPriority(self: *Scheduler, index: usize, priority: ScheduledTask.Priority) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        if (index < self.tasks.items.len) {
            self.tasks.items[index].priority = priority;
        }
    }

    /// Configures retry policy for a specific task.
    pub fn setTaskRetryPolicy(self: *Scheduler, index: usize, policy: ScheduledTask.RetryPolicy) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        if (index < self.tasks.items.len) {
            self.tasks.items[index].retry_policy = policy;
            self.tasks.items[index].retries_remaining = policy.max_retries;
        }
    }

    /// Sets a dependency for a task.
    pub fn setTaskDependency(self: *Scheduler, index: usize, dependency_name: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        if (index < self.tasks.items.len) {
            if (self.tasks.items[index].depends_on) |p| self.allocator.free(p);
            self.tasks.items[index].depends_on = try self.allocator.dupe(u8, dependency_name);
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
            .max_age_seconds = max_age_days * 24 * 60 * 60,
            .file_pattern = "*.log",
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
            .file_pattern = "*.log",
        });
    }

    /// Adds a custom callback task.
    pub fn addCustomTask(
        self: *Scheduler,
        name: []const u8,
        schedule: Schedule,
        callback: *const fn (*ScheduledTask) anyerror!void,
    ) !usize {
        self.mutex.lock();
        defer self.mutex.unlock();

        const owned_name = try self.allocator.dupe(u8, name);
        const now = std.time.milliTimestamp();

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

    /// Enables or disables a task.
    pub fn setTaskEnabled(self: *Scheduler, index: usize, enabled: bool) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        if (index < self.tasks.items.len) {
            self.tasks.items[index].enabled = enabled;
        }
    }

    /// Removes a task by index.
    pub fn removeTask(self: *Scheduler, index: usize) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        if (index < self.tasks.items.len) {
            const task = self.tasks.orderedRemove(index);
            self.allocator.free(task.name);
            if (task.config.path) |p| self.allocator.free(p);
            if (task.config.file_pattern) |p| self.allocator.free(p);
        }
    }

    /// Sets the callback for task started events.
    pub fn setTaskStartedCallback(self: *Scheduler, callback: *const fn ([]const u8, u64) void) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.on_task_started = callback;
    }

    /// Sets the callback for task completed events.
    pub fn setTaskCompletedCallback(self: *Scheduler, callback: *const fn ([]const u8, u64) void) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.on_task_completed = callback;
    }

    /// Sets the callback for task error events.
    pub fn setTaskErrorCallback(self: *Scheduler, callback: *const fn ([]const u8, []const u8) void) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.on_task_error = callback;
    }

    /// Sets the callback for schedule tick events.
    pub fn setScheduleTickCallback(self: *Scheduler, callback: *const fn (u32, u32) void) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.on_schedule_tick = callback;
    }

    /// Sets the callback for health check events.
    pub fn setHealthCheckCallback(self: *Scheduler, callback: *const fn (*const HealthStatus) void) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.on_health_check = callback;
    }

    /// Starts the scheduler.
    pub fn start(self: *Scheduler) !void {
        if (self.running.load(.acquire)) return;

        self.running.store(true, .release);
        self.worker_thread = try std.Thread.spawn(.{}, schedulerLoop, .{self});
    }

    /// Stops the scheduler.
    /// Stops the scheduler and waits for pending tasks.
    pub fn stop(self: *Scheduler) void {
        if (!self.running.load(.acquire)) return;

        self.running.store(false, .release);
        self.condition.broadcast();

        // Join the worker loop thread
        if (self.worker_thread) |thread| {
            thread.join();
            self.worker_thread = null;
        }

        // Wait for running tasks (with a simple timeout)
        var wait_loops: u8 = 0;
        while (wait_loops < 50) : (wait_loops += 1) { // 5 second max wait
            var any_running = false;
            self.mutex.lock();
            for (self.tasks.items) |task| {
                if (task.running) {
                    any_running = true;
                    break;
                }
            }
            self.mutex.unlock();

            if (!any_running) break;
            std.Thread.sleep(100 * std.time.ns_per_ms);
        }
    }

    /// Runs a task immediately regardless of schedule.
    pub fn runNow(self: *Scheduler, index: usize) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (index >= self.tasks.items.len) return;
        try self.executeTask(&self.tasks.items[index]);
    }

    /// Runs all pending tasks.
    pub fn runPending(self: *Scheduler) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const now = std.time.milliTimestamp();
        for (self.tasks.items, 0..) |*task, i| {
            if (task.enabled and !task.running and task.next_run <= now) {
                // Check dependencies
                if (task.depends_on) |dep_name| {
                    var dep_running = false;
                    for (self.tasks.items) |t| {
                        if (std.mem.eql(u8, t.name, dep_name) and t.running) {
                            dep_running = true;
                            break;
                        }
                    }
                    if (dep_running) continue;
                }

                // Check disk usage if configured
                if (task.config.trigger_disk_usage_percent) |threshold| {
                    const usage = self.getDiskUsage(task.config.path orelse ".") catch 0;
                    if (usage < threshold) continue;
                }

                if (task.config.min_free_space_bytes) |min_free| {
                    const free = self.getFreeSpace(task.config.path orelse ".") catch min_free;
                    if (free < min_free) continue;
                }

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
                            self.handleTaskError(i, err);
                        };
                        task.running = false;
                    }
                } else {
                    self.executeTask(task) catch |err| {
                        self.handleTaskError(i, err);
                    };
                }
            }
        }
    }

    fn handleTaskError(self: *Scheduler, index: usize, err: anyerror) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (index >= self.tasks.items.len) return;
        const task = &self.tasks.items[index];

        task.error_count += 1;
        self.stats.tasks_failed += 1;

        if (task.retries_remaining > 0) {
            task.retries_remaining -= 1;
            const delay = @as(u64, @intFromFloat(@as(f32, @floatFromInt(task.retry_policy.interval_ms)) * std.math.pow(f32, task.retry_policy.backoff_multiplier, @floatFromInt(task.retry_policy.max_retries - task.retries_remaining))));
            task.next_run = std.time.milliTimestamp() + @as(i64, @intCast(delay));

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
        self.mutex.lock();
        if (index >= self.tasks.items.len) {
            self.mutex.unlock();
            return;
        }
        const task = &self.tasks.items[index];
        self.mutex.unlock();

        defer {
            self.mutex.lock();
            task.running = false;
            self.mutex.unlock();
        }

        try self.executeTask(task);
    }

    fn schedulerLoop(self: *Scheduler) void {
        while (self.running.load(.acquire)) {
            self.runPending();

            // Check every 500ms for more responsive scheduling
            var i: usize = 0;
            while (i < 5 and self.running.load(.acquire)) : (i += 1) {
                std.Thread.sleep(100 * std.time.ns_per_ms);
            }
        }
    }

    fn executeTask(self: *Scheduler, task: *ScheduledTask) !void {
        const now = std.time.milliTimestamp();

        switch (task.task_type) {
            .cleanup => {
                if (task.config.path) |path| {
                    const result = try self.performCleanup(path, task.config);
                    self.stats.files_cleaned += result.files_deleted;
                    self.stats.bytes_freed += result.bytes_freed;
                }
            },
            .compression => {
                if (task.config.path) |path| {
                    const result = try self.performCompression(path, task.config);
                    self.stats.files_cleaned += result.files_compressed;
                    self.stats.bytes_freed += result.bytes_saved;
                }
            },
            .rotation => {
                // Rotation is handled by the sink directly based on size/time
                // This task is typically used to trigger manual rotation checks
                // The sink will handle the actual file rotation when logs are written
            },
            .flush => {
                // Flush task - triggers a flush of any buffered data
                // This is typically handled by the logger or sinks
                // Used to ensure all buffered logs are written to disk
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
            },
            .metrics_snapshot => {
                // Capture metrics snapshot
                const metrics = self.getMetrics();
                _ = metrics; // Store or report metrics as needed
            },
        }

        task.last_run = now;
        task.next_run = task.schedule.nextRunTime(now);
        task.run_count += 1;
        self.stats.tasks_executed += 1;
        self.stats.last_run_time = now;
    }

    fn performCleanup(self: *Scheduler, path: []const u8, config: ScheduledTask.TaskConfig) !CleanupResult {
        var result = CleanupResult{};
        const now = std.time.timestamp();
        const max_age = @as(i64, @intCast(config.max_age_seconds));

        var dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch {
            return result;
        };
        defer dir.close();

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
        while (try iter.next()) |entry| {
            if (entry.kind != .file) continue;

            // Check file pattern
            if (config.file_pattern) |pattern| {
                if (!matchPattern(entry.name, pattern)) continue;
            }

            // Get file stats
            const file = dir.openFile(entry.name, .{}) catch continue;
            const stat = file.stat() catch {
                file.close();
                continue;
            };
            file.close();

            const mtime: i64 = @intCast(@divFloor(stat.mtime, std.time.ns_per_s));
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

        // 1. Delete files based on age
        for (files.items, 0..) |fi, i| {
            if (fi.age > max_age) {
                // Optionally compress before delete
                if (config.compress_before_delete and self.compression_initialized) {
                    // Skip already compressed files
                    if (!std.mem.endsWith(u8, fi.name, ".gz") and
                        !std.mem.endsWith(u8, fi.name, ".lgz"))
                    {
                        const full_path = try std.fs.path.join(self.allocator, &[_][]const u8{ path, fi.name });
                        defer self.allocator.free(full_path);
                        _ = self.compression.compressFile(full_path, null) catch {};
                        result.files_compressed += 1;
                    }
                }

                dir.deleteFile(fi.name) catch {
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

                    dir.deleteFile(fi.name) catch {
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

                    dir.deleteFile(fi.name) catch {
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

        var dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch return result;
        defer dir.close();

        var iter = dir.iterate();
        const now = std.time.timestamp();
        while (try iter.next()) |entry| {
            if (entry.kind != .file) continue;

            // Skip already compressed files
            if (std.mem.endsWith(u8, entry.name, ".gz")) continue;
            if (std.mem.endsWith(u8, entry.name, ".lgz")) continue;
            if (std.mem.endsWith(u8, entry.name, ".zst")) continue;

            // Check pattern
            if (config.file_pattern) |pattern| {
                if (!matchPattern(entry.name, pattern)) continue;
            }

            // Check age if min_age_seconds is set
            if (config.min_age_seconds > 0) {
                const file = dir.openFile(entry.name, .{}) catch continue;
                const stat = file.stat() catch {
                    file.close();
                    continue;
                };
                file.close();
                const mtime: i64 = @intCast(@divFloor(stat.mtime, std.time.ns_per_s));
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
            const path_c = try std.heap.page_allocator.dupeZ(u8, path);
            defer std.heap.page_allocator.free(path_c);

            var stat: std.posix.statvfs = undefined;
            try std.posix.statvfs(path_c, &stat);

            if (stat.blocks == 0) return 0;
            return @intCast(100 - (stat.bfree * 100 / stat.blocks));
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
            const path_c = try std.heap.page_allocator.dupeZ(u8, path);
            defer std.heap.page_allocator.free(path_c);

            var stat: std.posix.statvfs = undefined;
            try std.posix.statvfs(path_c, &stat);

            return stat.bfree * stat.frsize;
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
            .max_age_seconds = max_age_days * 24 * 60 * 60,
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
        return .{ .interval = 60 * 60 * 1000 };
    }

    /// Every N minutes.
    pub fn everyMinutes(n: u64) Scheduler.Schedule {
        return .{ .interval = n * 60 * 1000 };
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
        return .{ .interval = 30 * 60 * 1000 };
    }

    /// Every 6 hours.
    pub fn every6Hours() Scheduler.Schedule {
        return .{ .interval = 6 * 60 * 60 * 1000 };
    }

    /// Every 12 hours.
    pub fn every12Hours() Scheduler.Schedule {
        return .{ .interval = 12 * 60 * 60 * 1000 };
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
};

test "scheduler basic" {
    const allocator = std.testing.allocator;

    const scheduler = try Scheduler.init(allocator);
    defer scheduler.deinit();

    _ = try scheduler.addTask("test", .cleanup, .{ .interval = 60000 }, .{});

    try std.testing.expectEqual(@as(usize, 1), scheduler.tasks.items.len);
}

test "schedule next run time" {
    const now = std.time.milliTimestamp();

    const interval = Scheduler.Schedule{ .interval = 5000 };
    const next = interval.nextRunTime(now);

    try std.testing.expect(next > now);
    try std.testing.expect(next <= now + 5000);
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
    std.fs.cwd().makeDir(tmp_path) catch {};
    defer std.fs.cwd().deleteTree(tmp_path) catch {};

    var dir = try std.fs.cwd().openDir(tmp_path, .{ .iterate = true });
    defer dir.close();

    // Create initial set of log files for testing limit enforcement
    var i: usize = 0;
    while (i < 10) : (i += 1) {
        const name = try std.fmt.allocPrint(allocator, "test_{d}.log", .{i});
        defer allocator.free(name);
        const file = try dir.createFile(name, .{});
        try file.writeAll("test content");
        file.close();
    }

    // Create additional files to test overflow handling
    while (i < 15) : (i += 1) {
        const name = try std.fmt.allocPrint(allocator, "new_{d}.log", .{i});
        defer allocator.free(name);
        const file = try dir.createFile(name, .{});
        try file.writeAll("new log content");
        file.close();
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
    while (try iter.next()) |_| {
        count += 1;
    }
    try std.testing.expectEqual(@as(usize, 5), count);

    // Verify max_total_size constraint enforcement
    {
        const file = try dir.createFile("large.log", .{});
        try file.writeAll(&([_]u8{'A'} ** 1024));
        file.close();
    }

    config.max_files = null;
    config.max_total_size = 500;

    const result2 = try scheduler.performCleanup(tmp_path, config);
    try std.testing.expect(result2.files_deleted >= 1);
}

// Windows helper functions
extern "kernel32" fn GetDiskFreeSpaceExW(
    lpDirectoryName: ?[*:0]const u16,
    lpFreeBytesAvailableToCaller: ?*u64,
    lpTotalNumberOfBytes: ?*u64,
    lpTotalNumberOfFreeBytes: ?*u64,
) callconv(.winapi) i32;
