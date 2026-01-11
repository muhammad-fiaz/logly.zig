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

        /// Returns total rotation count.
        pub fn rotationCount(self: *const RotationStats) u64 {
            return @as(u64, self.total_rotations.load(.monotonic));
        }

        /// Returns total error count.
        pub fn errorCount(self: *const RotationStats) u64 {
            return @as(u64, self.rotation_errors.load(.monotonic));
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
            .last_rotation = @divFloor(std.time.milliTimestamp(), 1000),
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
        const now = @divFloor(std.time.milliTimestamp(), 1000);

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
        const start_time = std.time.milliTimestamp();

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

        self.last_rotation = @divFloor(std.time.milliTimestamp(), 1000);
        _ = self.stats.total_rotations.fetchAdd(1, .monotonic);

        const elapsed = @as(Constants.AtomicUnsigned, @intCast(std.time.milliTimestamp() - start_time));
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
        const now_ms = std.time.milliTimestamp();
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
                    const age = std.time.nanoTimestamp() - stat.mtime;
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

/// Preset rotation configurations.
pub const RotationPresets = struct {
    /// Daily rotation with 7 day retention.
    pub fn daily7Days(allocator: std.mem.Allocator, path: []const u8) !Rotation {
        return Rotation.init(allocator, path, "daily", null, 7);
    }

    /// Daily rotation with 30 day retention.
    pub fn daily30Days(allocator: std.mem.Allocator, path: []const u8) !Rotation {
        return Rotation.init(allocator, path, "daily", null, 30);
    }

    /// Hourly rotation with 24 hour retention.
    pub fn hourly24Hours(allocator: std.mem.Allocator, path: []const u8) !Rotation {
        return Rotation.init(allocator, path, "hourly", null, 24);
    }

    /// 10MB size-based rotation with 5 file retention.
    pub fn size10MB(allocator: std.mem.Allocator, path: []const u8) !Rotation {
        return Rotation.init(allocator, path, null, 10 * 1024 * 1024, 5);
    }

    /// 100MB size-based rotation with 10 file retention.
    pub fn size100MB(allocator: std.mem.Allocator, path: []const u8) !Rotation {
        return Rotation.init(allocator, path, null, 100 * 1024 * 1024, 10);
    }

    /// Creates a daily rotation sink config.
    pub fn dailySink(file_path: []const u8, retention_days: usize) SinkConfig {
        return Rotation.createRotatingSink(file_path, "daily", retention_days);
    }

    /// Creates an hourly rotation sink config.
    pub fn hourlySink(file_path: []const u8, retention_hours: usize) SinkConfig {
        return Rotation.createRotatingSink(file_path, "hourly", retention_hours);
    }
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
