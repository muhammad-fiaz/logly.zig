const std = @import("std");
const Config = @import("config.zig").Config;

/// Handles log file rotation logic.
///
/// Supports rotation based on time intervals (hourly, daily, etc.) or file size.
/// Also manages retention of old log files.
pub const Rotation = struct {
    allocator: std.mem.Allocator,
    base_path: []const u8,
    interval: ?RotationInterval = null,
    size_limit: ?u64 = null,
    retention: ?usize = null,
    last_rotation: i64,

    /// Defines the time interval for rotation.
    const RotationInterval = enum {
        minutely,
        hourly,
        daily,
        weekly,
        monthly,
        yearly,

        /// Returns the duration of the interval in seconds.
        fn seconds(self: RotationInterval) i64 {
            return switch (self) {
                .minutely => 60,
                .hourly => 3600,
                .daily => 86400,
                .weekly => 604800,
                .monthly => 2592000, // 30 days
                .yearly => 31536000, // 365 days
            };
        }
    };

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
        const interval = if (interval_str) |s| blk: {
            if (std.mem.eql(u8, s, "minutely")) break :blk RotationInterval.minutely;
            if (std.mem.eql(u8, s, "hourly")) break :blk RotationInterval.hourly;
            if (std.mem.eql(u8, s, "daily")) break :blk RotationInterval.daily;
            if (std.mem.eql(u8, s, "weekly")) break :blk RotationInterval.weekly;
            if (std.mem.eql(u8, s, "monthly")) break :blk RotationInterval.monthly;
            if (std.mem.eql(u8, s, "yearly")) break :blk RotationInterval.yearly;
            break :blk null;
        } else null;

        return .{
            .allocator = allocator,
            .base_path = try allocator.dupe(u8, path),
            .interval = interval,
            .size_limit = size_limit,
            .retention = retention,
            .last_rotation = @divFloor(std.time.milliTimestamp(), 1000),
        };
    }

    pub fn deinit(self: *Rotation) void {
        self.allocator.free(self.base_path);
    }

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

    fn rotate(self: *Rotation, file_ptr: *std.fs.File) !void {
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
        try std.fs.cwd().rename(self.base_path, rotated_name);

        // Re-open original file
        file_ptr.* = try std.fs.cwd().createFile(self.base_path, .{
            .read = true,
            .truncate = true, // Start fresh
        });

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
                try std.fs.cwd().deleteFile(full_path);
            }
        }
    }
};
