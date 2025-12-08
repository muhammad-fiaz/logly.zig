const std = @import("std");
const Config = @import("config.zig").Config;
const Compression = @import("compression.zig").Compression;

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
        enabled: bool = true,
        config: TaskConfig = .{},

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
            /// File pattern to match (e.g., "*.log")
            file_pattern: ?[]const u8 = null,
            /// Compress files before cleanup
            compress_before_delete: bool = false,
            /// Recursive directory processing
            recursive: bool = false,

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
                .cron => now_ms + 60 * 1000, // Simplified: check every minute
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

        // Deinit compression
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
        };

        try self.tasks.append(self.allocator, task);
        return self.tasks.items.len - 1;
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
            const task = self.tasks.orderedRemove(self.allocator, index);
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
    pub fn stop(self: *Scheduler) void {
        if (!self.running.load(.acquire)) return;

        self.running.store(false, .release);
        self.condition.broadcast();

        if (self.worker_thread) |thread| {
            thread.join();
            self.worker_thread = null;
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
        for (self.tasks.items) |*task| {
            if (task.enabled and task.next_run <= now) {
                self.executeTask(task) catch {
                    task.error_count += 1;
                    self.stats.tasks_failed += 1;
                };
            }
        }
    }

    fn schedulerLoop(self: *Scheduler) void {
        while (self.running.load(.acquire)) {
            self.runPending();
            std.Thread.sleep(1000 * std.time.ns_per_ms); // Check every second
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

        // Collect file info for sorting (needed for max_files)
        var files: std.ArrayList(FileInfo) = .empty;
        defer {
            for (files.items) |fi| {
                self.allocator.free(fi.name);
            }
            files.deinit(self.allocator);
        }

        var iter = dir.iterate();
        while (try iter.next()) |entry| {
            if (entry.kind != .file) continue;

            // Check file pattern
            if (config.file_pattern) |pattern| {
                if (!matchPattern(entry.name, pattern)) continue;
            }

            // Get file stats
            const file = dir.openFile(entry.name, .{}) catch continue;
            defer file.close();

            const stat = file.stat() catch continue;
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
        }

        // Sort by modification time (oldest first)
        std.mem.sort(FileInfo, files.items, {}, struct {
            fn lessThan(_: void, a: FileInfo, b: FileInfo) bool {
                return a.mtime < b.mtime;
            }
        }.lessThan);

        // Delete files based on age
        for (files.items) |fi| {
            var should_delete = false;

            // Check age
            if (fi.age > max_age) {
                should_delete = true;
            }

            if (should_delete) {
                // Optionally compress before delete
                if (config.compress_before_delete and self.compression_initialized) {
                    const full_path = std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ path, fi.name }) catch continue;
                    defer self.allocator.free(full_path);

                    // Skip already compressed files
                    if (!std.mem.endsWith(u8, fi.name, ".gz") and
                        !std.mem.endsWith(u8, fi.name, ".lgz"))
                    {
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
            }
        }

        // Enforce max files limit (delete oldest files beyond limit)
        if (config.max_files) |max| {
            if (files.items.len > max) {
                const files_to_delete = files.items.len - max;
                var deleted: usize = 0;

                // Files are sorted oldest first, delete from the beginning
                for (files.items) |fi| {
                    if (deleted >= files_to_delete) break;

                    dir.deleteFile(fi.name) catch {
                        result.errors += 1;
                        continue;
                    };

                    result.files_deleted += 1;
                    result.bytes_freed += fi.size;
                    deleted += 1;
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
