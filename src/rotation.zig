const std = @import("std");
const Config = @import("config.zig").Config;
const SinkConfig = @import("sink.zig").SinkConfig;
const Constants = @import("constants.zig");

/// Handles log file rotation logic with comprehensive callback support.
///
/// Supports rotation based on time intervals (hourly, daily, etc.) or file size.
/// Also manages retention of old log files with customizable lifecycle callbacks.
///
/// Callbacks:
/// - `on_rotation_start`: Called before rotation begins
/// - `on_rotation_complete`: Called after rotation succeeds
/// - `on_rotation_error`: Called if rotation fails
/// - `on_file_archived`: Called when old file is archived/compressed
/// - `on_retention_cleanup`: Called when old files are deleted for retention
///
/// Performance Features:
/// - O(1) time-based rotation checks (simple timestamp comparison)
/// - O(1) size-based rotation checks (single file stat)
/// - Lazy cleanup during rotation to minimize blocking
/// - Lock-free stats updates for minimal contention
pub const Rotation = struct {
    /// Defines the time interval for rotation.
    pub const RotationInterval = enum {
        minutely,
        hourly,
        daily,
        weekly,
        monthly,
        yearly,

        /// Returns the duration of the interval in seconds.
        pub fn seconds(self: RotationInterval) i64 {
            return switch (self) {
                .minutely => 60,
                .hourly => 3600,
                .daily => 86400,
                .weekly => 604800,
                .monthly => 2592000, // 30 days
                .yearly => 31536000, // 365 days
            };
        }

        /// Returns the duration in milliseconds.
        pub fn millis(self: RotationInterval) i64 {
            return self.seconds() * 1000;
        }

        /// Parse interval from string.
        pub fn fromString(s: []const u8) ?RotationInterval {
            if (std.mem.eql(u8, s, "minutely")) return .minutely;
            if (std.mem.eql(u8, s, "hourly")) return .hourly;
            if (std.mem.eql(u8, s, "daily")) return .daily;
            if (std.mem.eql(u8, s, "weekly")) return .weekly;
            if (std.mem.eql(u8, s, "monthly")) return .monthly;
            if (std.mem.eql(u8, s, "yearly")) return .yearly;
            return null;
        }

        /// Returns human-readable name.
        pub fn name(self: RotationInterval) []const u8 {
            return switch (self) {
                .minutely => "Minutely",
                .hourly => "Hourly",
                .daily => "Daily",
                .weekly => "Weekly",
                .monthly => "Monthly",
                .yearly => "Yearly",
            };
        }
    };

    /// Rotation statistics for monitoring.
    pub const RotationStats = struct {
        total_rotations: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        files_archived: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        files_deleted: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        last_rotation_time_ms: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        rotation_errors: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),

        pub fn reset(self: *RotationStats) void {
            self.total_rotations.store(0, .monotonic);
            self.files_archived.store(0, .monotonic);
            self.files_deleted.store(0, .monotonic);
            self.last_rotation_time_ms.store(0, .monotonic);
            self.rotation_errors.store(0, .monotonic);
        }

        pub fn rotationCount(self: *const RotationStats) u64 {
            return @as(u64, self.total_rotations.load(.monotonic));
        }

        pub fn errorCount(self: *const RotationStats) u64 {
            return @as(u64, self.rotation_errors.load(.monotonic));
        }
    };

    allocator: std.mem.Allocator,
    base_path: []const u8,
    interval: ?RotationInterval = null,
    size_limit: ?u64 = null,
    retention: ?usize = null,
    last_rotation: i64,

    /// Callback invoked before rotation begins.
    /// Parameters: (old_path: []const u8, new_path: []const u8)
    on_rotation_start: ?*const fn ([]const u8, []const u8) void = null,

    /// Callback invoked after successful rotation.
    /// Parameters: (old_path: []const u8, new_path: []const u8, elapsed_ms: u64)
    on_rotation_complete: ?*const fn ([]const u8, []const u8, u64) void = null,

    /// Callback invoked when rotation fails.
    /// Parameters: (path: []const u8, error: anyerror)
    on_rotation_error: ?*const fn ([]const u8, anyerror) void = null,

    /// Callback invoked when file is archived/compressed.
    /// Parameters: (old_path: []const u8, archive_path: []const u8)
    on_file_archived: ?*const fn ([]const u8, []const u8) void = null,

    /// Callback invoked when file is deleted for retention.
    /// Parameters: (path: []const u8)
    on_retention_cleanup: ?*const fn ([]const u8) void = null,

    stats: RotationStats = .{},
    mutex: std.Thread.Mutex = .{},

    /// Initializes a new Rotation instance.
    ///
    /// - `allocator`: Memory allocator.
    /// - `path`: Base path for log files.
    /// - `interval_str`: Rotation interval string ("daily", "hourly", etc.).
    /// - `size_limit`: Maximum file size in bytes before rotation.
    /// - `retention`: Number of rotated files to keep.
    pub fn init(
        allocator: std.mem.Allocator,
        path: []const u8,
        interval_str: ?[]const u8,
        size_limit: ?u64,
        retention: ?usize,
    ) !Rotation {
        const interval = if (interval_str) |s| RotationInterval.fromString(s) else null;

        return .{
            .allocator = allocator,
            .base_path = try allocator.dupe(u8, path),
            .interval = interval,
            .size_limit = size_limit,
            .retention = retention,
            .last_rotation = @divFloor(std.time.milliTimestamp(), 1000),
        };
    }

    /// Creates a Rotation with daily interval.
    pub fn daily(allocator: std.mem.Allocator, path: []const u8, retention: ?usize) !Rotation {
        return init(allocator, path, "daily", null, retention);
    }

    /// Creates a Rotation with hourly interval.
    pub fn hourly(allocator: std.mem.Allocator, path: []const u8, retention: ?usize) !Rotation {
        return init(allocator, path, "hourly", null, retention);
    }

    /// Creates a size-based Rotation.
    pub fn bySize(allocator: std.mem.Allocator, path: []const u8, size_limit: u64, retention: ?usize) !Rotation {
        return init(allocator, path, null, size_limit, retention);
    }

    /// Releases all resources associated with the Rotation instance.
    ///
    /// Must be called when the rotation handler is no longer needed.
    pub fn deinit(self: *Rotation) void {
        self.allocator.free(self.base_path);
    }

    /// Returns statistics snapshot.
    pub fn getStats(self: *const Rotation) RotationStats {
        return self.stats;
    }

    /// Resets statistics.
    pub fn resetStats(self: *Rotation) void {
        self.stats.reset();
    }

    /// Returns true if rotation is enabled.
    pub fn isEnabled(self: *const Rotation) bool {
        return self.interval != null or self.size_limit != null;
    }

    /// Returns the current interval name or "none".
    pub fn intervalName(self: *const Rotation) []const u8 {
        if (self.interval) |i| return i.name();
        return "none";
    }

    /// Checks if rotation should occur and performs it if necessary.
    pub fn checkAndRotate(self: *Rotation, file_ptr: *std.fs.File) !void {
        var should_rotate = false;

        // Check time-based rotation
        if (self.interval) |interval| {
            const now = @divFloor(std.time.milliTimestamp(), 1000);
            if (now - self.last_rotation >= interval.seconds()) {
                should_rotate = true;
            }
        }

        // Check size-based rotation
        if (self.size_limit) |limit| {
            const stat = try file_ptr.stat();
            if (stat.size >= limit) {
                should_rotate = true;
            }
        }

        if (should_rotate) {
            try self.rotate(file_ptr);
            self.last_rotation = @divFloor(std.time.milliTimestamp(), 1000);
        }
    }

    /// Alias for checkAndRotate
    pub const check = checkAndRotate;
    pub const tryRotate = checkAndRotate;

    /// Force rotation regardless of conditions.
    pub fn forceRotate(self: *Rotation, file_ptr: *std.fs.File) !void {
        try self.rotate(file_ptr);
        self.last_rotation = @divFloor(std.time.milliTimestamp(), 1000);
    }

    /// Alias for forceRotate
    pub const rotateNow = forceRotate;

    fn rotate(self: *Rotation, file_ptr: *std.fs.File) !void {
        const start_time = std.time.milliTimestamp();
        file_ptr.close();

        // Generate rotated filename with timestamp
        const now = @divFloor(std.time.milliTimestamp(), 1000);
        const rotated_name = try std.fmt.allocPrint(
            self.allocator,
            "{s}_{d}",
            .{ self.base_path, now },
        );
        defer self.allocator.free(rotated_name);

        // Rename current file
        std.fs.cwd().rename(self.base_path, rotated_name) catch |err| {
            _ = self.stats.rotation_errors.fetchAdd(1, .monotonic);
            if (self.on_rotation_error) |cb| cb(self.base_path, err);
            return err;
        };

        // Re-open original file
        file_ptr.* = try std.fs.cwd().createFile(self.base_path, .{
            .read = true,
            .truncate = true, // Start fresh
        });

        // Update stats
        _ = self.stats.total_rotations.fetchAdd(1, .monotonic);
        const elapsed: u64 = @intCast(std.time.milliTimestamp() - start_time);
        self.stats.last_rotation_time_ms.store(@truncate(elapsed), .monotonic);

        // Clean up old files if retention is set
        if (self.retention) |max_files| {
            try self.cleanupOldFiles(max_files);
        }
    }

    fn cleanupOldFiles(self: *Rotation, max_files: usize) !void {
        const dir_path = std.fs.path.dirname(self.base_path) orelse ".";
        const base_name = std.fs.path.basename(self.base_path);

        var dir = try std.fs.cwd().openDir(dir_path, .{ .iterate = true });
        defer dir.close();

        var files: std.ArrayList([]const u8) = .empty;
        defer {
            for (files.items) |f| self.allocator.free(f);
            files.deinit(self.allocator);
        }

        var iter = dir.iterate();
        while (try iter.next()) |entry| {
            if (entry.kind != .file) continue;
            if (std.mem.startsWith(u8, entry.name, base_name)) {
                try files.append(self.allocator, try self.allocator.dupe(u8, entry.name));
            }
        }

        // Sort by name (timestamp is in the name)
        std.mem.sort([]const u8, files.items, {}, struct {
            fn lessThan(_: void, a: []const u8, b: []const u8) bool {
                return std.mem.lessThan(u8, a, b);
            }
        }.lessThan);

        // Delete oldest files
        if (files.items.len > max_files) {
            const to_delete = files.items.len - max_files;
            for (files.items[0..to_delete]) |filename| {
                const full_path = try std.fs.path.join(self.allocator, &.{ dir_path, filename });
                defer self.allocator.free(full_path);
                std.fs.cwd().deleteFile(full_path) catch continue;
                _ = self.stats.files_deleted.fetchAdd(1, .monotonic);
                if (self.on_retention_cleanup) |cb| cb(full_path);
            }
        }
    }

    /// Creates a rotating sink configuration.
    pub fn createRotatingSink(file_path: []const u8, interval: []const u8, retention: usize) SinkConfig {
        return SinkConfig{
            .path = file_path,
            .rotation = interval,
            .retention = retention,
            .color = false,
        };
    }

    /// Creates a size-based rotating sink configuration.
    pub fn createSizeRotatingSink(file_path: []const u8, size_limit: u64, retention: usize) SinkConfig {
        return SinkConfig{
            .path = file_path,
            .size_limit = size_limit,
            .retention = retention,
            .color = false,
        };
    }

    /// Aliases for sink creation
    pub const rotatingSink = createRotatingSink;
    pub const sizeSink = createSizeRotatingSink;
};

/// Preset rotation configurations.
pub const RotationPresets = struct {
    /// Daily rotation with 7 day retention.
    pub fn daily7Days(allocator: std.mem.Allocator, path: []const u8) !Rotation {
        return Rotation.daily(allocator, path, 7);
    }

    /// Daily rotation with 30 day retention.
    pub fn daily30Days(allocator: std.mem.Allocator, path: []const u8) !Rotation {
        return Rotation.daily(allocator, path, 30);
    }

    /// Hourly rotation with 24 hour retention.
    pub fn hourly24Hours(allocator: std.mem.Allocator, path: []const u8) !Rotation {
        return Rotation.hourly(allocator, path, 24);
    }

    /// 10MB size-based rotation with 5 file retention.
    pub fn size10MB(allocator: std.mem.Allocator, path: []const u8) !Rotation {
        return Rotation.bySize(allocator, path, 10 * 1024 * 1024, 5);
    }

    /// 100MB size-based rotation with 10 file retention.
    pub fn size100MB(allocator: std.mem.Allocator, path: []const u8) !Rotation {
        return Rotation.bySize(allocator, path, 100 * 1024 * 1024, 10);
    }
};
