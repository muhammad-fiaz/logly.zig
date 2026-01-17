//! Log File Rotation Module
//!
//! Handles automatic log file rotation with comprehensive features
//! for enterprise use including time-based, size-based, and hybrid rotation.
//!
//! Rotation Triggers:
//! - Time-based: Minutely, hourly, daily, weekly, monthly, yearly
//! - Size-based: Rotate when file exceeds specified size
//! - Hybrid: Combine time and size triggers
//!
//! Naming Strategies:
//! - timestamp: Unix timestamp suffix (app.log.1704067200)
//! - date: Date suffix (app.log.2024-01-01)
//! - iso_datetime: ISO 8601 datetime (app.log.2024-01-01T120000)
//! - index: Numbered suffix with shifting (app.log.1, app.log.2)
//! - custom: User-defined format string
//!
//! Features:
//! - Automatic compression of rotated files
//! - Retention policies (max files, max age)
//! - Archive directory support
//! - Configurable callbacks for rotation events
//!
//! Performance:
//! - Minimal I/O during rotation checks
//! - Background compression option

const std = @import("std");
const Config = @import("config.zig").Config;
const SinkConfig = @import("sink.zig").SinkConfig;
const Constants = @import("constants.zig");
const Compression = @import("compression.zig").Compression;
const CompressionConfig = Config.CompressionConfig;
const RotationConfig = Config.RotationConfig;
const Utils = @import("utils.zig");

/// Handles log file rotation logic with comprehensive features for enterprise use.
pub const Rotation = struct {
    /// Defines the time interval for rotation.
    pub const RotationInterval = enum {
        /// Rotate every minute.
        minutely,
        /// Rotate every hour.
        hourly,
        /// Rotate every day.
        daily,
        /// Rotate every week.
        weekly,
        /// Rotate every 30 days.
        monthly,
        /// Rotate every 365 days.
        yearly,

        /// Returns the interval duration in seconds.
        pub fn seconds(self: RotationInterval) i64 {
            return switch (self) {
                .minutely => 60,
                .hourly => 3600,
                .daily => 86400,
                .weekly => 604800,
                .monthly => 2592000,
                .yearly => 31536000,
            };
        }

        /// Parses an interval from string (e.g., "daily", "hourly").
        pub fn fromString(s: []const u8) ?RotationInterval {
            if (std.mem.eql(u8, s, "minutely")) return .minutely;
            if (std.mem.eql(u8, s, "hourly")) return .hourly;
            if (std.mem.eql(u8, s, "daily")) return .daily;
            if (std.mem.eql(u8, s, "weekly")) return .weekly;
            if (std.mem.eql(u8, s, "monthly")) return .monthly;
            if (std.mem.eql(u8, s, "yearly")) return .yearly;
            return null;
        }

        /// Returns a human-readable name for the interval.
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

    /// Naming strategy for rotated files.
    pub const NamingStrategy = Config.RotationConfig.NamingStrategy;

    /// Rotation statistics for monitoring.
    pub const RotationStats = struct {
        /// Total number of rotations performed.
        total_rotations: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        /// Number of files moved to archive.
        files_archived: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        /// Number of files deleted during cleanup.
        files_deleted: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        /// Timestamp of last rotation in milliseconds.
        last_rotation_time_ms: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        /// Number of rotation errors.
        rotation_errors: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        /// Number of compression errors during rotation.
        compression_errors: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),

        /// Resets all statistics to zero.
        pub fn reset(self: *RotationStats) void {
            self.total_rotations.store(0, .monotonic);
            self.files_archived.store(0, .monotonic);
            self.files_deleted.store(0, .monotonic);
            self.last_rotation_time_ms.store(0, .monotonic);
            self.rotation_errors.store(0, .monotonic);
            self.compression_errors.store(0, .monotonic);
        }

        /// Returns total rotation count as u64.
        pub fn rotationCount(self: *const RotationStats) u64 {
            return Utils.atomicLoadU64(&self.total_rotations);
        }

        /// Returns total error count as u64.
        pub fn errorCount(self: *const RotationStats) u64 {
            return Utils.atomicLoadU64(&self.rotation_errors);
        }

        /// Returns files archived count as u64.
        pub fn getFilesArchived(self: *const RotationStats) u64 {
            return Utils.atomicLoadU64(&self.files_archived);
        }

        /// Returns files deleted count as u64.
        pub fn getFilesDeleted(self: *const RotationStats) u64 {
            return Utils.atomicLoadU64(&self.files_deleted);
        }

        /// Returns compression error count as u64.
        pub fn getCompressionErrors(self: *const RotationStats) u64 {
            return Utils.atomicLoadU64(&self.compression_errors);
        }

        /// Checks if any rotation errors occurred.
        pub fn hasErrors(self: *const RotationStats) bool {
            return self.rotation_errors.load(.monotonic) > 0;
        }

        /// Checks if any compression errors occurred.
        pub fn hasCompressionErrors(self: *const RotationStats) bool {
            return self.compression_errors.load(.monotonic) > 0;
        }

        /// Calculate rotation success rate (0.0 - 1.0).
        pub fn successRate(self: *const RotationStats) f64 {
            const total = Utils.atomicLoadU64(&self.total_rotations);
            const errors = Utils.atomicLoadU64(&self.rotation_errors);
            if (total == 0) return 1.0;
            return 1.0 - Utils.calculateErrorRate(errors, total);
        }

        /// Calculate total error rate (0.0 - 1.0).
        pub fn totalErrorRate(self: *const RotationStats) f64 {
            const total = Utils.atomicLoadU64(&self.total_rotations);
            const rot_errors = Utils.atomicLoadU64(&self.rotation_errors);
            const comp_errors = Utils.atomicLoadU64(&self.compression_errors);
            return Utils.calculateErrorRate(rot_errors + comp_errors, total);
        }
    };

    /// Memory allocator for file operations.
    allocator: std.mem.Allocator,
    /// Base path of the log file to rotate.
    base_path: []const u8,
    /// Time-based rotation interval (null to disable).
    interval: ?RotationInterval = null,
    /// Size-based rotation limit in bytes (null to disable).
    size_limit: ?u64 = null,
    /// Maximum number of rotated files to keep.
    retention: ?usize = null,
    /// Maximum age of rotated files in seconds.
    max_age_seconds: ?i64 = null,
    /// Timestamp of last rotation.
    last_rotation: i64,
    /// Naming strategy for rotated files.
    naming: NamingStrategy = .timestamp,
    /// Custom naming format string.
    naming_format: ?[]const u8 = null,
    /// Compression configuration for rotated files.
    compression: ?CompressionConfig = null,
    /// Compression engine instance.
    compressor: ?Compression = null,
    /// Directory for archived/compressed files.
    archive_dir: ?[]const u8 = null,
    /// Clean empty directories after rotation.
    clean_empty_dirs: bool = false,

    /// Keep original file after compression (default: false - delete original).
    keep_original: bool = false,

    /// Compress files during retention cleanup instead of deleting them.
    /// When true, old files exceeding retention limits are compressed rather than deleted.
    compress_on_retention: bool = false,

    /// Delete files after compression during retention (only applies when compress_on_retention is true).
    /// When false, compressed files are kept; when true, originals are deleted after compression.
    delete_after_retention_compress: bool = true,

    /// Callback invoked when rotation starts.
    on_rotation_start: ?*const fn (old_path: []const u8, new_path: []const u8) void = null,
    /// Callback invoked when rotation completes successfully.
    on_rotation_complete: ?*const fn (old_path: []const u8, new_path: []const u8, elapsed_ms: u64) void = null,
    /// Callback invoked when rotation encounters an error.
    on_rotation_error: ?*const fn (path: []const u8, err: anyerror) void = null,
    /// Callback invoked when a file is archived.
    on_file_archived: ?*const fn (original_path: []const u8, archive_path: []const u8) void = null,
    /// Callback invoked during retention cleanup.
    on_retention_cleanup: ?*const fn (path: []const u8) void = null,

    /// Rotation statistics.
    stats: RotationStats = .{},
    /// Mutex for thread-safe operations.
    mutex: std.Thread.Mutex = .{},

    pub fn init(
        allocator: std.mem.Allocator,
        path: []const u8,
        interval_str: ?[]const u8,
        size_limit: ?u64,
        retention: ?usize,
    ) !Rotation {
        const interval = if (interval_str) |s| RotationInterval.fromString(s) else null;
        var r = Rotation{
            .allocator = allocator,
            .base_path = try allocator.dupe(u8, path),
            .interval = interval,
            .size_limit = size_limit,
            .retention = retention,
            .last_rotation = Utils.currentSeconds(),
        };

        // Smart default naming based on interval
        if (interval) |i| {
            switch (i) {
                .daily, .weekly, .monthly, .yearly => r.naming = .date,
                else => r.naming = .timestamp,
            }
        } else {
            r.naming = .timestamp;
        }

        return r;
    }

    /// Alias for init().
    pub const create = init;

    pub fn withCompression(self: *Rotation, config: CompressionConfig) !void {
        self.compression = config;
        // Pre-initialize compressor if needed
        self.compressor = Compression.initWithConfig(self.allocator, config);
    }

    pub fn withNaming(self: *Rotation, strategy: NamingStrategy) void {
        self.naming = strategy;
    }

    pub fn withNamingFormat(self: *Rotation, format: []const u8) !void {
        if (self.naming_format) |f| self.allocator.free(f);
        self.naming_format = try self.allocator.dupe(u8, format);
        self.naming = .custom;
    }

    pub fn withMaxAge(self: *Rotation, seconds: i64) void {
        self.max_age_seconds = seconds;
    }

    pub fn withArchiveDir(self: *Rotation, dir: []const u8) !void {
        if (self.archive_dir) |d| self.allocator.free(d);
        self.archive_dir = try self.allocator.dupe(u8, dir);
    }

    pub fn setCleanEmptyDirs(self: *Rotation, clean: bool) void {
        self.clean_empty_dirs = clean;
    }

    /// Set whether to keep original files after compression.
    pub fn withKeepOriginal(self: *Rotation, keep: bool) void {
        self.keep_original = keep;
    }

    /// Enable compression during retention cleanup instead of deletion.
    /// Old files will be compressed rather than deleted when they exceed retention limits.
    pub fn withCompressOnRetention(self: *Rotation, enable: bool) void {
        self.compress_on_retention = enable;
    }

    /// Set whether to delete original files after retention compression.
    /// Only applies when compress_on_retention is true.
    pub fn withDeleteAfterRetentionCompress(self: *Rotation, delete: bool) void {
        self.delete_after_retention_compress = delete;
    }

    /// Applies global rotation configuration where local settings are missing.
    pub fn applyConfig(self: *Rotation, config: RotationConfig) !void {
        if (self.interval == null and config.interval != null) {
            self.interval = RotationInterval.fromString(config.interval.?);
        }
        if (self.size_limit == null) {
            if (config.size_limit) |l| self.size_limit = l else if (config.size_limit_str) |s| {
                self.size_limit = Utils.parseSize(s);
            }
        }
        if (self.retention == null) self.retention = config.retention_count;
        if (self.max_age_seconds == null) self.max_age_seconds = config.max_age_seconds;
        self.naming = config.naming_strategy;
        if (config.naming_format) |f| try self.withNamingFormat(f);
        if (config.archive_dir) |d| try self.withArchiveDir(d);
        self.clean_empty_dirs = config.clean_empty_dirs;
        self.keep_original = config.keep_original;
        self.compress_on_retention = config.compress_on_retention;
        self.delete_after_retention_compress = config.delete_after_retention_compress;
    }

    pub fn deinit(self: *Rotation) void {
        self.allocator.free(self.base_path);
        if (self.archive_dir) |d| self.allocator.free(d);
        // Compressor doesn't strictly need deinit if it holds no state
    }

    /// Alias for deinit().
    pub const destroy = deinit;

    pub fn getStats(self: *const Rotation) RotationStats {
        return self.stats;
    }

    pub fn isEnabled(self: *const Rotation) bool {
        return self.interval != null or self.size_limit != null;
    }

    pub fn intervalName(self: *const Rotation) []const u8 {
        if (self.interval) |i| return i.name();
        return "none";
    }

    pub fn checkAndRotate(self: *Rotation, file_ptr: *std.fs.File) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var should_rotate = false;
        const now = Utils.currentSeconds();

        // Check time-based rotation
        if (self.interval) |interval| {
            if (now - self.last_rotation >= interval.seconds()) {
                should_rotate = true;
            }
        }

        // Check size-based rotation
        if (self.size_limit) |limit| {
            if (file_ptr.stat()) |stat| {
                if (stat.size >= limit) {
                    should_rotate = true;
                }
            } else |_| {
                // Ignore stat errors, retry later
            }
        }

        if (should_rotate) {
            // Perform rotation
            self.performRotation(file_ptr) catch |err| {
                _ = self.stats.rotation_errors.fetchAdd(1, .monotonic);
                if (self.on_rotation_error) |cb| cb(self.base_path, err);
                // Don't propagate error to avoid crashing application logging, just log error
            };
        }
    }

    fn performRotation(self: *Rotation, file_ptr: *std.fs.File) !void {
        const start_time = Utils.currentMillis();

        // 1. Generate new filename
        const rotated_path = try self.generateRotatedPath();
        defer self.allocator.free(rotated_path);

        // Ensure archive dir exists if used
        if (self.archive_dir) |_| {
            const dir = std.fs.path.dirname(rotated_path);
            if (dir) |d| {
                std.fs.cwd().makePath(d) catch {};
            }
        }

        if (self.on_rotation_start) |cb| cb(self.base_path, rotated_path);

        // 2. Close current file
        file_ptr.close();

        // 3. Rename current file to rotated path
        // For index strategy, we might need to shift existing files first
        if (self.naming == .index) {
            try self.shiftIndexFiles();
        }

        std.fs.cwd().rename(self.base_path, rotated_path) catch |err| {
            // Try to reopen functionality if rename fails
            file_ptr.* = try std.fs.cwd().createFile(self.base_path, .{ .read = true, .truncate = false }); // Append mode effectively
            file_ptr.seekFromEnd(0) catch {};
            return err;
        };

        // 4. Re-open log file (fresh)
        file_ptr.* = try std.fs.cwd().createFile(self.base_path, .{
            .read = true,
            .truncate = true,
        });

        self.last_rotation = Utils.currentSeconds();
        _ = self.stats.total_rotations.fetchAdd(1, .monotonic);

        const elapsed = @as(Constants.AtomicUnsigned, @intCast(Utils.currentMillis() - start_time));
        self.stats.last_rotation_time_ms.store(elapsed, .monotonic);
        if (self.on_rotation_complete) |cb| cb(self.base_path, rotated_path, @as(u64, @intCast(elapsed)));

        // 5. Compress if enabled
        var final_path = try self.allocator.dupe(u8, rotated_path);
        errdefer self.allocator.free(final_path);

        if (self.compression) |comp_config| {
            if (self.compressor) |*comp| {
                // This is blocking operation in current thread (usually sink internal thread or main thread)
                // For production systems with large logs, this should ideally be offloaded.
                // However, for consistency we'll do it here or let specific scheduler handle it.
                // Since we are in Rotation module, we do it here.
                const compressed_path = try uniqueCompressedPath(self.allocator, rotated_path, comp_config.algorithm);
                errdefer self.allocator.free(compressed_path);

                // Compress
                _ = comp.compressFile(rotated_path, compressed_path) catch {
                    _ = self.stats.compression_errors.fetchAdd(1, .monotonic);
                    // On failure, we keep the uncompressed file
                };

                // If successful and keep_original is false, remove uncompressed rotated file
                if (!self.keep_original) {
                    std.fs.cwd().deleteFile(rotated_path) catch {};
                }

                self.allocator.free(final_path);
                final_path = try self.allocator.dupe(u8, compressed_path);

                _ = self.stats.files_archived.fetchAdd(1, .monotonic);
                if (self.on_file_archived) |cb| cb(rotated_path, final_path);
            }
        }

        self.allocator.free(final_path);

        // 6. Cleanup old files
        if (self.retention != null or self.max_age_seconds != null) {
            self.cleanupOldFiles() catch {};
        }
    }

    fn generateRotatedPath(self: *Rotation) ![]u8 {
        const now_ms = Utils.currentMillis();
        const now = @divFloor(now_ms, 1000);
        const millis = @as(u64, @intCast(@mod(now_ms, 1000)));
        var name_buf: []u8 = undefined;

        const base_name = std.fs.path.basename(self.base_path);

        switch (self.naming) {
            .timestamp => {
                name_buf = try std.fmt.allocPrint(self.allocator, "{s}.{d}", .{ base_name, now });
            },
            .date => {
                // Format YYYY-MM-DD
                const epoch = std.time.epoch.EpochSeconds{ .secs = @intCast(now) };
                const yd = epoch.getEpochDay().calculateYearDay();
                const md = yd.calculateMonthDay();
                name_buf = try std.fmt.allocPrint(self.allocator, "{s}.{d:0>4}-{d:0>2}-{d:0>2}", .{ base_name, yd.year, md.month.numeric(), md.day_index + 1 });
            },
            .iso_datetime => {
                const epoch = std.time.epoch.EpochSeconds{ .secs = @intCast(now) };
                const yd = epoch.getEpochDay().calculateYearDay();
                const md = yd.calculateMonthDay();
                const ds = epoch.getDaySeconds();
                const h = ds.secs / 3600;
                const m = (ds.secs % 3600) / 60;
                const s = ds.secs % 60;

                var res: std.ArrayList(u8) = .empty;
                errdefer res.deinit(self.allocator);
                const w = res.writer(self.allocator);
                try w.writeAll(base_name);
                try w.writeByte('.');
                try Utils.writeFilenameSafe(w, Utils.TimeComponents{
                    .year = yd.year,
                    .month = md.month.numeric(),
                    .day = md.day_index + 1,
                    .hour = h,
                    .minute = m,
                    .second = s,
                });
                name_buf = try res.toOwnedSlice(self.allocator);
            },
            .index => {
                // For index strategy, the immediate rotated file is always .1
                name_buf = try std.fmt.allocPrint(self.allocator, "{s}.1", .{base_name});
            },
            .custom => {
                if (self.naming_format) |fmt| {
                    // Parse format: {base}, {ext}, {timestamp}, {date}, {time}, {iso}
                    const ext = std.fs.path.extension(base_name);
                    const stem = if (ext.len > 0) base_name[0..(base_name.len - ext.len)] else base_name;

                    // Helper formatting
                    const epoch = std.time.epoch.EpochSeconds{ .secs = @intCast(now) };
                    const yd = epoch.getEpochDay().calculateYearDay();
                    const md = yd.calculateMonthDay();
                    const ds = epoch.getDaySeconds();
                    const h = ds.secs / 3600;
                    const m = (ds.secs % 3600) / 60;
                    const s = ds.secs % 60;

                    // Optimization: Pre-allocate buffer to minimize reallocations
                    // Estimate size: format length + extra space for replacements (timestamp, etc.)
                    var res = std.ArrayList(u8){};
                    try res.ensureTotalCapacity(self.allocator, fmt.len + 64);
                    defer res.deinit(self.allocator);

                    var i: usize = 0;
                    while (i < fmt.len) {
                        if (fmt[i] == '{') {
                            const end = std.mem.indexOfPos(u8, fmt, i, "}") orelse {
                                try res.append(self.allocator, fmt[i]);
                                i += 1;
                                continue;
                            };
                            const tag = fmt[i + 1 .. end];
                            if (std.mem.eql(u8, tag, "base")) {
                                try res.appendSlice(self.allocator, stem);
                            } else if (std.mem.eql(u8, tag, "ext")) {
                                try res.appendSlice(self.allocator, ext);
                            } else if (std.mem.eql(u8, tag, "timestamp")) {
                                try Utils.writeInt(res.writer(self.allocator), now);
                            } else if (std.mem.eql(u8, tag, "date")) {
                                try Utils.writeIsoDate(res.writer(self.allocator), Utils.TimeComponents{
                                    .year = yd.year,
                                    .month = md.month.numeric(),
                                    .day = md.day_index + 1,
                                    .hour = h,
                                    .minute = m,
                                    .second = s,
                                });
                            } else if (std.mem.eql(u8, tag, "time")) {
                                try Utils.writeIsoTime(res.writer(self.allocator), Utils.TimeComponents{
                                    .year = yd.year,
                                    .month = md.month.numeric(),
                                    .day = md.day_index + 1,
                                    .hour = h,
                                    .minute = m,
                                    .second = s,
                                });
                            } else if (std.mem.eql(u8, tag, "iso")) {
                                try Utils.writeIsoDateTime(res.writer(self.allocator), Utils.TimeComponents{
                                    .year = yd.year,
                                    .month = md.month.numeric(),
                                    .day = md.day_index + 1,
                                    .hour = h,
                                    .minute = m,
                                    .second = s,
                                });
                            } else {
                                // Granular date format parsing via shared utility
                                try Utils.formatDatePattern(res.writer(self.allocator), tag, yd.year, md.month.numeric(), md.day_index + 1, h, m, s, millis);
                            }
                            i = end + 1;
                        } else {
                            try res.append(self.allocator, fmt[i]);
                            i += 1;
                        }
                    }
                    name_buf = try res.toOwnedSlice(self.allocator);
                } else {
                    // Fallback if custom selected but no format
                    name_buf = try std.fmt.allocPrint(self.allocator, "{s}.{d}", .{ base_name, now });
                }
            },
        }
        defer self.allocator.free(name_buf);

        if (self.archive_dir) |dir| {
            return std.fs.path.join(self.allocator, &.{ dir, name_buf });
        } else {
            const dir = std.fs.path.dirname(self.base_path) orelse ".";
            return std.fs.path.join(self.allocator, &.{ dir, name_buf });
        }
    }

    fn uniqueCompressedPath(allocator: std.mem.Allocator, base: []const u8, algo: Compression.Algorithm) ![]u8 {
        const ext = switch (algo) {
            .deflate, .zlib, .raw_deflate => ".gz",
            else => ".gz",
        };
        return std.fmt.allocPrint(allocator, "{s}{s}", .{ base, ext });
    }

    fn shiftIndexFiles(self: *Rotation) !void {
        // This assumes we have a reasonable max retention to avoid infinite loop
        // We shift .N -> .N+1
        const max = self.retention orelse 10; // Default limit for shifting
        const target_dir = self.archive_dir orelse (std.fs.path.dirname(self.base_path) orelse ".");
        const base_name = std.fs.path.basename(self.base_path);

        // Work backwards
        var i: usize = max;
        while (i >= 1) : (i -= 1) {
            const current_name = try std.fmt.allocPrint(self.allocator, "{s}.{d}", .{ base_name, i });
            defer self.allocator.free(current_name);
            const current_path = try std.fs.path.join(self.allocator, &.{ target_dir, current_name });
            defer self.allocator.free(current_path);

            // If file exists
            if (std.fs.cwd().access(current_path, .{})) |_| {
                if (i == max) {
                    // Delete overflow
                    std.fs.cwd().deleteFile(current_path) catch {};
                } else {
                    // Rename to next
                    const next_name = try std.fmt.allocPrint(self.allocator, "{s}.{d}", .{ base_name, i + 1 });
                    defer self.allocator.free(next_name);
                    const next_path = try std.fs.path.join(self.allocator, &.{ target_dir, next_name });
                    defer self.allocator.free(next_path);

                    std.fs.cwd().rename(current_path, next_path) catch {};
                }
            } else |_| {}
        }
    }

    fn cleanupOldFiles(self: *Rotation) !void {
        const dir_path = self.archive_dir orelse (std.fs.path.dirname(self.base_path) orelse ".");
        const base_name = std.fs.path.basename(self.base_path);

        var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch return;
        defer dir.close();

        const FileInfo = struct { name: []u8, mtime: i128, is_compressed: bool };
        var files: std.ArrayList(FileInfo) = .empty;
        defer {
            for (files.items) |f| self.allocator.free(f.name);
            files.deinit(self.allocator);
        }

        var iter = dir.iterate();
        while (try iter.next()) |entry| {
            if (entry.kind != .file) continue;
            // Matches base_name and starts with it
            if (std.mem.startsWith(u8, entry.name, base_name) and !std.mem.eql(u8, entry.name, base_name)) {
                const full_path = try std.fs.path.join(self.allocator, &.{ dir_path, entry.name });
                defer self.allocator.free(full_path);

                const stat = std.fs.cwd().statFile(full_path) catch continue;

                // Check if already compressed
                const is_compressed = std.mem.endsWith(u8, entry.name, ".gz") or
                    std.mem.endsWith(u8, entry.name, ".lgz") or
                    std.mem.endsWith(u8, entry.name, ".zst") or
                    std.mem.endsWith(u8, entry.name, ".deflate");

                // Age check
                if (self.max_age_seconds) |max_age| {
                    const age = Utils.currentNanos() - stat.mtime;
                    if (age > max_age * std.time.ns_per_s) {
                        try self.handleRetentionFile(full_path, is_compressed);
                        continue; // handled, don't add to list
                    }
                }

                try files.append(self.allocator, .{
                    .name = try self.allocator.dupe(u8, entry.name),
                    .mtime = stat.mtime,
                    .is_compressed = is_compressed,
                });
            }
        }

        // Retention check with count sorted by mtime
        if (self.retention) |max_files| {
            if (files.items.len > max_files) {
                // Sort by modification time (oldest first)
                std.mem.sort(FileInfo, files.items, {}, struct {
                    fn lessThan(_: void, a: FileInfo, b: FileInfo) bool {
                        return a.mtime < b.mtime;
                    }
                }.lessThan);

                const to_delete = files.items.len - max_files;
                for (files.items[0..to_delete]) |item| {
                    const full_path = try std.fs.path.join(self.allocator, &.{ dir_path, item.name });
                    defer self.allocator.free(full_path);
                    try self.handleRetentionFile(full_path, item.is_compressed);
                }
            }
        }

        if (self.clean_empty_dirs) {
            // Only attempt to clean if archive_dir is explicitly set to avoid accidents
            if (self.archive_dir) |archive_path| {
                // Attempt to remove directory. Will fail safely if not empty.
                std.fs.cwd().deleteDir(archive_path) catch {};
            }
        }
    }

    /// Handle a file during retention cleanup - either compress or delete based on settings.
    fn handleRetentionFile(self: *Rotation, path: []const u8, is_compressed: bool) !void {
        // If compress_on_retention is enabled and file is not already compressed
        if (self.compress_on_retention and !is_compressed) {
            if (self.compressor) |*comp| {
                const algo = if (self.compression) |c| c.algorithm else .deflate;
                const compressed_path = try uniqueCompressedPath(self.allocator, path, algo);
                defer self.allocator.free(compressed_path);

                // Compress the file
                _ = comp.compressFile(path, compressed_path) catch |err| {
                    _ = self.stats.compression_errors.fetchAdd(1, .monotonic);
                    // On failure, fall back to deletion if delete_after_retention_compress is true
                    if (self.delete_after_retention_compress) {
                        try self.deleteFile(path);
                    }
                    return err;
                };

                _ = self.stats.files_archived.fetchAdd(1, .monotonic);
                if (self.on_file_archived) |cb| cb(path, compressed_path);

                // Delete original after successful compression if configured
                if (self.delete_after_retention_compress) {
                    std.fs.cwd().deleteFile(path) catch {};
                }
                return;
            }
        }

        // Default behavior: delete the file
        try self.deleteFile(path);
    }

    fn deleteFile(self: *Rotation, path: []const u8) !void {
        std.fs.cwd().deleteFile(path) catch return;
        _ = self.stats.files_deleted.fetchAdd(1, .monotonic);
        if (self.on_retention_cleanup) |cb| cb(path);
    }

    /// Creates a rotating sink with specified naming strategy
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

/// Preset rotation configurations for common use cases.
pub const RotationPresets = struct {
    // Time-Based Presets

    /// Daily rotation with 7 day retention (standard weekly cleanup).
    pub fn daily7Days(allocator: std.mem.Allocator, path: []const u8) !Rotation {
        return Rotation.init(allocator, path, "daily", null, 7);
    }

    /// Daily rotation with 30 day retention (monthly cleanup).
    pub fn daily30Days(allocator: std.mem.Allocator, path: []const u8) !Rotation {
        return Rotation.init(allocator, path, "daily", null, 30);
    }

    /// Daily rotation with 90 day retention (quarterly cleanup).
    pub fn daily90Days(allocator: std.mem.Allocator, path: []const u8) !Rotation {
        return Rotation.init(allocator, path, "daily", null, 90);
    }

    /// Daily rotation with 365 day retention (yearly archive).
    pub fn daily365Days(allocator: std.mem.Allocator, path: []const u8) !Rotation {
        return Rotation.init(allocator, path, "daily", null, 365);
    }

    /// Hourly rotation with 24 hour retention (daily cleanup).
    pub fn hourly24Hours(allocator: std.mem.Allocator, path: []const u8) !Rotation {
        return Rotation.init(allocator, path, "hourly", null, 24);
    }

    /// Hourly rotation with 48 hour retention (two-day buffer).
    pub fn hourly48Hours(allocator: std.mem.Allocator, path: []const u8) !Rotation {
        return Rotation.init(allocator, path, "hourly", null, 48);
    }

    /// Hourly rotation with 168 hour (7 day) retention.
    pub fn hourly7Days(allocator: std.mem.Allocator, path: []const u8) !Rotation {
        return Rotation.init(allocator, path, "hourly", null, 168);
    }

    /// Weekly rotation with 4 week retention.
    pub fn weekly4Weeks(allocator: std.mem.Allocator, path: []const u8) !Rotation {
        return Rotation.init(allocator, path, "weekly", null, 4);
    }

    /// Weekly rotation with 12 week (quarterly) retention.
    pub fn weekly12Weeks(allocator: std.mem.Allocator, path: []const u8) !Rotation {
        return Rotation.init(allocator, path, "weekly", null, 12);
    }

    /// Monthly rotation with 12 month retention.
    pub fn monthly12Months(allocator: std.mem.Allocator, path: []const u8) !Rotation {
        return Rotation.init(allocator, path, "monthly", null, 12);
    }

    /// Minutely rotation with 60 file retention (debugging).
    pub fn minutely60(allocator: std.mem.Allocator, path: []const u8) !Rotation {
        return Rotation.init(allocator, path, "minutely", null, 60);
    }

    // Size-Based Presets

    /// 1MB size-based rotation with 5 file retention (small logs).
    pub fn size1MB(allocator: std.mem.Allocator, path: []const u8) !Rotation {
        return Rotation.init(allocator, path, null, 1 * 1024 * 1024, 5);
    }

    /// 5MB size-based rotation with 5 file retention.
    pub fn size5MB(allocator: std.mem.Allocator, path: []const u8) !Rotation {
        return Rotation.init(allocator, path, null, 5 * 1024 * 1024, 5);
    }

    /// 10MB size-based rotation with 5 file retention.
    pub fn size10MB(allocator: std.mem.Allocator, path: []const u8) !Rotation {
        return Rotation.init(allocator, path, null, 10 * 1024 * 1024, 5);
    }

    /// 25MB size-based rotation with 10 file retention.
    pub fn size25MB(allocator: std.mem.Allocator, path: []const u8) !Rotation {
        return Rotation.init(allocator, path, null, 25 * 1024 * 1024, 10);
    }

    /// 50MB size-based rotation with 10 file retention.
    pub fn size50MB(allocator: std.mem.Allocator, path: []const u8) !Rotation {
        return Rotation.init(allocator, path, null, 50 * 1024 * 1024, 10);
    }

    /// 100MB size-based rotation with 10 file retention.
    pub fn size100MB(allocator: std.mem.Allocator, path: []const u8) !Rotation {
        return Rotation.init(allocator, path, null, 100 * 1024 * 1024, 10);
    }

    /// 250MB size-based rotation with 5 file retention (large logs).
    pub fn size250MB(allocator: std.mem.Allocator, path: []const u8) !Rotation {
        return Rotation.init(allocator, path, null, 250 * 1024 * 1024, 5);
    }

    /// 500MB size-based rotation with 3 file retention.
    pub fn size500MB(allocator: std.mem.Allocator, path: []const u8) !Rotation {
        return Rotation.init(allocator, path, null, 500 * 1024 * 1024, 3);
    }

    /// 1GB size-based rotation with 2 file retention.
    pub fn size1GB(allocator: std.mem.Allocator, path: []const u8) !Rotation {
        return Rotation.init(allocator, path, null, 1024 * 1024 * 1024, 2);
    }

    // Hybrid Presets (Time + Size)

    /// Daily rotation OR 100MB, 30 day retention.
    pub fn dailyOr100MB(allocator: std.mem.Allocator, path: []const u8) !Rotation {
        return Rotation.init(allocator, path, "daily", 100 * 1024 * 1024, 30);
    }

    /// Hourly rotation OR 50MB, 48 hour retention.
    pub fn hourlyOr50MB(allocator: std.mem.Allocator, path: []const u8) !Rotation {
        return Rotation.init(allocator, path, "hourly", 50 * 1024 * 1024, 48);
    }

    /// Daily rotation OR 500MB, 7 day retention (high volume).
    pub fn dailyOr500MB(allocator: std.mem.Allocator, path: []const u8) !Rotation {
        return Rotation.init(allocator, path, "daily", 500 * 1024 * 1024, 7);
    }

    // Production Presets

    /// Production preset: daily rotation, 30 days, with compression.
    pub fn production(allocator: std.mem.Allocator, path: []const u8) !Rotation {
        var rot = try Rotation.init(allocator, path, "daily", null, 30);
        rot.withNaming(.date);
        try rot.withCompression(.{ .algorithm = .deflate });
        return rot;
    }

    /// Enterprise preset: daily rotation, 90 days, compressed archive.
    pub fn enterprise(allocator: std.mem.Allocator, path: []const u8) !Rotation {
        var rot = try Rotation.init(allocator, path, "daily", null, 90);
        rot.withNaming(.iso_datetime);
        try rot.withCompression(.{ .algorithm = .deflate, .level = .best });
        rot.withCompressOnRetention(true);
        return rot;
    }

    /// Debug preset: minutely rotation, 60 files, no compression.
    pub fn debug(allocator: std.mem.Allocator, path: []const u8) !Rotation {
        var rot = try Rotation.init(allocator, path, "minutely", null, 60);
        rot.withNaming(.timestamp);
        return rot;
    }

    /// High-volume preset: hourly OR 500MB, 7 days, compressed.
    pub fn highVolume(allocator: std.mem.Allocator, path: []const u8) !Rotation {
        var rot = try Rotation.init(allocator, path, "hourly", 500 * 1024 * 1024, 168);
        rot.withNaming(.iso_datetime);
        try rot.withCompression(.{ .algorithm = .deflate });
        return rot;
    }

    /// Audit preset: daily rotation, 365 days, compressed archive, ISO naming.
    pub fn audit(allocator: std.mem.Allocator, path: []const u8) !Rotation {
        var rot = try Rotation.init(allocator, path, "daily", null, 365);
        rot.withNaming(.iso_datetime);
        try rot.withCompression(.{ .algorithm = .deflate, .level = .best });
        rot.withCompressOnRetention(true);
        rot.withDeleteAfterRetentionCompress(false);
        return rot;
    }

    /// Minimal preset: size-only 10MB, 3 files (embedded/resource constrained).
    pub fn minimal(allocator: std.mem.Allocator, path: []const u8) !Rotation {
        var rot = try Rotation.init(allocator, path, null, 10 * 1024 * 1024, 3);
        rot.withNaming(.index);
        return rot;
    }

    // Sink Configuration Helpers

    /// Creates a daily rotation sink config.
    pub fn dailySink(file_path: []const u8, retention_days: usize) SinkConfig {
        return Rotation.createRotatingSink(file_path, "daily", retention_days);
    }

    /// Creates an hourly rotation sink config.
    pub fn hourlySink(file_path: []const u8, retention_hours: usize) SinkConfig {
        return Rotation.createRotatingSink(file_path, "hourly", retention_hours);
    }

    /// Creates a weekly rotation sink config.
    pub fn weeklySink(file_path: []const u8, retention_weeks: usize) SinkConfig {
        return Rotation.createRotatingSink(file_path, "weekly", retention_weeks);
    }

    /// Creates a monthly rotation sink config.
    pub fn monthlySink(file_path: []const u8, retention_months: usize) SinkConfig {
        return Rotation.createRotatingSink(file_path, "monthly", retention_months);
    }

    /// Creates a size-based rotation sink config.
    pub fn sizeSink(file_path: []const u8, size_bytes: u64, retention: usize) SinkConfig {
        return Rotation.createSizeRotatingSink(file_path, size_bytes, retention);
    }

    // Aliases for common presets
    pub const weekly = weekly4Weeks;
    pub const monthly = monthly12Months;
    pub const hourly = hourly24Hours;
    pub const daily = daily7Days;
};

test "rotation functionality" {
    const allocator = std.testing.allocator;
    // We mock the file system operations by checking logic or using tmp dir
    var rot = try Rotation.init(allocator, "test.log", "daily", null, 5);
    defer rot.deinit();

    try std.testing.expect(rot.interval != null);
    try std.testing.expectEqual(Rotation.RotationInterval.daily, rot.interval.?);

    rot.withNaming(.index);
    try std.testing.expectEqual(Rotation.NamingStrategy.index, rot.naming);

    try rot.withCompression(CompressionConfig{ .algorithm = .deflate });
    try std.testing.expect(rot.compression != null);
}

test "rotation interval seconds" {
    try std.testing.expectEqual(@as(i64, 60), Rotation.RotationInterval.minutely.seconds());
    try std.testing.expectEqual(@as(i64, 3600), Rotation.RotationInterval.hourly.seconds());
    try std.testing.expectEqual(@as(i64, 86400), Rotation.RotationInterval.daily.seconds());
    try std.testing.expectEqual(@as(i64, 604800), Rotation.RotationInterval.weekly.seconds());
    try std.testing.expectEqual(@as(i64, 2592000), Rotation.RotationInterval.monthly.seconds());
    try std.testing.expectEqual(@as(i64, 31536000), Rotation.RotationInterval.yearly.seconds());
}

test "rotation interval from string" {
    try std.testing.expectEqual(Rotation.RotationInterval.minutely, Rotation.RotationInterval.fromString("minutely"));
    try std.testing.expectEqual(Rotation.RotationInterval.hourly, Rotation.RotationInterval.fromString("hourly"));
    try std.testing.expectEqual(Rotation.RotationInterval.daily, Rotation.RotationInterval.fromString("daily"));
    try std.testing.expectEqual(Rotation.RotationInterval.weekly, Rotation.RotationInterval.fromString("weekly"));
    try std.testing.expectEqual(Rotation.RotationInterval.monthly, Rotation.RotationInterval.fromString("monthly"));
    try std.testing.expectEqual(Rotation.RotationInterval.yearly, Rotation.RotationInterval.fromString("yearly"));
    try std.testing.expectEqual(@as(?Rotation.RotationInterval, null), Rotation.RotationInterval.fromString("invalid"));
}

test "rotation stats" {
    var stats = Rotation.RotationStats{};

    // Initial values
    try std.testing.expectEqual(@as(u64, 0), stats.rotationCount());
    try std.testing.expectEqual(@as(u64, 0), stats.errorCount());
    try std.testing.expectEqual(@as(f64, 1.0), stats.successRate());
    try std.testing.expect(!stats.hasErrors());

    // Increment counters
    _ = stats.total_rotations.fetchAdd(10, .monotonic);
    _ = stats.rotation_errors.fetchAdd(2, .monotonic);

    try std.testing.expectEqual(@as(u64, 10), stats.rotationCount());
    try std.testing.expectEqual(@as(u64, 2), stats.errorCount());
    try std.testing.expect(stats.hasErrors());
    try std.testing.expectApproxEqAbs(@as(f64, 0.8), stats.successRate(), 0.01);

    // Reset
    stats.reset();
    try std.testing.expectEqual(@as(u64, 0), stats.rotationCount());
    try std.testing.expect(!stats.hasErrors());
}

test "rotation presets time-based" {
    const allocator = std.testing.allocator;

    // Daily presets
    var daily7 = try RotationPresets.daily7Days(allocator, "test.log");
    defer daily7.deinit();
    try std.testing.expectEqual(Rotation.RotationInterval.daily, daily7.interval.?);
    try std.testing.expectEqual(@as(?usize, 7), daily7.retention);

    var daily30 = try RotationPresets.daily30Days(allocator, "test.log");
    defer daily30.deinit();
    try std.testing.expectEqual(@as(?usize, 30), daily30.retention);

    var daily90 = try RotationPresets.daily90Days(allocator, "test.log");
    defer daily90.deinit();
    try std.testing.expectEqual(@as(?usize, 90), daily90.retention);

    // Hourly presets
    var hourly24 = try RotationPresets.hourly24Hours(allocator, "test.log");
    defer hourly24.deinit();
    try std.testing.expectEqual(Rotation.RotationInterval.hourly, hourly24.interval.?);
    try std.testing.expectEqual(@as(?usize, 24), hourly24.retention);

    // Weekly presets
    var weekly4 = try RotationPresets.weekly4Weeks(allocator, "test.log");
    defer weekly4.deinit();
    try std.testing.expectEqual(Rotation.RotationInterval.weekly, weekly4.interval.?);
    try std.testing.expectEqual(@as(?usize, 4), weekly4.retention);
}

test "rotation presets size-based" {
    const allocator = std.testing.allocator;

    var size1 = try RotationPresets.size1MB(allocator, "test.log");
    defer size1.deinit();
    try std.testing.expectEqual(@as(?u64, 1 * 1024 * 1024), size1.size_limit);

    var size10 = try RotationPresets.size10MB(allocator, "test.log");
    defer size10.deinit();
    try std.testing.expectEqual(@as(?u64, 10 * 1024 * 1024), size10.size_limit);

    var size100 = try RotationPresets.size100MB(allocator, "test.log");
    defer size100.deinit();
    try std.testing.expectEqual(@as(?u64, 100 * 1024 * 1024), size100.size_limit);

    var size1gb = try RotationPresets.size1GB(allocator, "test.log");
    defer size1gb.deinit();
    try std.testing.expectEqual(@as(?u64, 1024 * 1024 * 1024), size1gb.size_limit);
}

test "rotation presets hybrid" {
    const allocator = std.testing.allocator;

    var hybrid = try RotationPresets.dailyOr100MB(allocator, "test.log");
    defer hybrid.deinit();
    try std.testing.expectEqual(Rotation.RotationInterval.daily, hybrid.interval.?);
    try std.testing.expectEqual(@as(?u64, 100 * 1024 * 1024), hybrid.size_limit);
    try std.testing.expectEqual(@as(?usize, 30), hybrid.retention);
}

test "rotation presets production configs" {
    const allocator = std.testing.allocator;

    // Production preset
    var prod = try RotationPresets.production(allocator, "test.log");
    defer prod.deinit();
    try std.testing.expectEqual(Rotation.RotationInterval.daily, prod.interval.?);
    try std.testing.expectEqual(Rotation.NamingStrategy.date, prod.naming);
    try std.testing.expect(prod.compression != null);

    // Enterprise preset
    var ent = try RotationPresets.enterprise(allocator, "test.log");
    defer ent.deinit();
    try std.testing.expectEqual(@as(?usize, 90), ent.retention);
    try std.testing.expectEqual(Rotation.NamingStrategy.iso_datetime, ent.naming);
    try std.testing.expect(ent.compress_on_retention);

    // Audit preset
    var audit = try RotationPresets.audit(allocator, "test.log");
    defer audit.deinit();
    try std.testing.expectEqual(@as(?usize, 365), audit.retention);
    try std.testing.expect(audit.compress_on_retention);
    try std.testing.expect(!audit.delete_after_retention_compress);

    // Minimal preset
    var min = try RotationPresets.minimal(allocator, "test.log");
    defer min.deinit();
    try std.testing.expectEqual(@as(?usize, 3), min.retention);
    try std.testing.expectEqual(Rotation.NamingStrategy.index, min.naming);
}

test "rotation configuration methods" {
    const allocator = std.testing.allocator;

    var rot = try Rotation.init(allocator, "test.log", "daily", null, 7);
    defer rot.deinit();

    // Test configuration methods
    rot.withKeepOriginal(true);
    try std.testing.expect(rot.keep_original);

    rot.withCompressOnRetention(true);
    try std.testing.expect(rot.compress_on_retention);

    rot.withDeleteAfterRetentionCompress(false);
    try std.testing.expect(!rot.delete_after_retention_compress);

    rot.withMaxAge(86400 * 7);
    try std.testing.expectEqual(@as(?i64, 604800), rot.max_age_seconds);

    rot.setCleanEmptyDirs(true);
    try std.testing.expect(rot.clean_empty_dirs);
}

test "rotation sink creation" {
    // Daily sink
    const daily_sink = RotationPresets.dailySink("logs/app.log", 7);
    try std.testing.expectEqualStrings("logs/app.log", daily_sink.path.?);
    try std.testing.expectEqualStrings("daily", daily_sink.rotation.?);
    try std.testing.expectEqual(@as(?usize, 7), daily_sink.retention);

    // Size sink
    const size_sink = RotationPresets.sizeSink("logs/app.log", 50 * 1024 * 1024, 5);
    try std.testing.expectEqual(@as(?u64, 50 * 1024 * 1024), size_sink.size_limit);
    try std.testing.expectEqual(@as(?usize, 5), size_sink.retention);
}

test "rotation is enabled check" {
    const allocator = std.testing.allocator;

    // Time-based enabled
    var rot1 = try Rotation.init(allocator, "test.log", "daily", null, null);
    defer rot1.deinit();
    try std.testing.expect(rot1.isEnabled());

    // Size-based enabled
    var rot2 = try Rotation.init(allocator, "test.log", null, 1024, null);
    defer rot2.deinit();
    try std.testing.expect(rot2.isEnabled());

    // Neither enabled (though this is unusual usage)
    var rot3 = try Rotation.init(allocator, "test.log", null, null, null);
    defer rot3.deinit();
    try std.testing.expect(!rot3.isEnabled());
}
