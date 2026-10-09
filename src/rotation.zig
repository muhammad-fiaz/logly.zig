//! Log file rotation.
//!
//! Size- and time-based rotation with retention, archival, and compression.
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

        /// Returns the interval duration in seconds (reuse central TimeConstants).
        pub fn seconds(self: RotationInterval) i64 {
            return switch (self) {
                .minutely => @as(i64, Constants.TimeConstants.secondsPerMinute),
                .hourly => @as(i64, Constants.TimeConstants.secondsPerHour),
                .daily => @as(i64, Constants.TimeConstants.secondsPerDay),
                .weekly => @as(i64, Constants.TimeConstants.secondsPerWeek),
                .monthly => @as(i64, Constants.TimeConstants.secondsPerMonth),
                .yearly => @as(i64, Constants.TimeConstants.secondsPerYear),
            };
        }

        /// Parses an interval from string (e.g., "daily", "hourly").
        /// Case-insensitive matching.
        pub fn fromString(s: []const u8) ?RotationInterval {
            if (std.ascii.eqlIgnoreCase(s, "minutely")) return .minutely;
            if (std.ascii.eqlIgnoreCase(s, "hourly")) return .hourly;
            if (std.ascii.eqlIgnoreCase(s, "daily")) return .daily;
            if (std.ascii.eqlIgnoreCase(s, "weekly")) return .weekly;
            if (std.ascii.eqlIgnoreCase(s, "monthly")) return .monthly;
            if (std.ascii.eqlIgnoreCase(s, "yearly")) return .yearly;
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

    /// Reason why a rotation should occur.
    pub const RotationReason = enum {
        interval,
        size,
        intervalAndSize,
    };

    /// Rotation statistics for monitoring.
    pub const RotationStats = struct {
        /// Total number of rotations performed.
        totalRotations: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        /// Number of files moved to archive.
        filesArchived: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        /// Number of files deleted during cleanup.
        filesDeleted: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        /// Timestamp of last rotation in milliseconds.
        lastRotationTimeMs: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        /// Number of rotation errors.
        rotationErrors: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        /// Number of compression errors during rotation.
        compressionErrors: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),

        /// Resets all statistics to zero.
        pub fn reset(self: *RotationStats) void {
            self.totalRotations.store(0, .monotonic);
            self.filesArchived.store(0, .monotonic);
            self.filesDeleted.store(0, .monotonic);
            self.lastRotationTimeMs.store(0, .monotonic);
            self.rotationErrors.store(0, .monotonic);
            self.compressionErrors.store(0, .monotonic);
        }

        /// Returns total rotation count as u64.
        pub fn rotationCount(self: *const RotationStats) u64 {
            return Utils.atomicLoadU64(&self.totalRotations);
        }

        /// Returns total error count as u64.
        pub fn errorCount(self: *const RotationStats) u64 {
            return Utils.atomicLoadU64(&self.rotationErrors);
        }

        /// Returns files archived count as u64.
        pub fn getFilesArchived(self: *const RotationStats) u64 {
            return Utils.atomicLoadU64(&self.filesArchived);
        }

        /// Returns files deleted count as u64.
        pub fn getFilesDeleted(self: *const RotationStats) u64 {
            return Utils.atomicLoadU64(&self.filesDeleted);
        }

        /// Returns compression error count as u64.
        pub fn getCompressionErrors(self: *const RotationStats) u64 {
            return Utils.atomicLoadU64(&self.compressionErrors);
        }

        /// Returns last rotation timestamp in milliseconds.
        pub fn getLastRotationTimeMs(self: *const RotationStats) u64 {
            return Utils.atomicLoadU64(&self.lastRotationTimeMs);
        }

        /// Checks if any rotation errors occurred.
        pub fn hasErrors(self: *const RotationStats) bool {
            return self.rotationErrors.load(.monotonic) > 0;
        }

        /// Checks if any compression errors occurred.
        pub fn hasCompressionErrors(self: *const RotationStats) bool {
            return self.compressionErrors.load(.monotonic) > 0;
        }

        /// Calculate rotation success rate (0.0 - 1.0).
        pub fn successRate(self: *const RotationStats) f64 {
            const total = Utils.atomicLoadU64(&self.totalRotations);
            const errors = Utils.atomicLoadU64(&self.rotationErrors);
            if (total == 0) return 1.0;
            return 1.0 - Utils.calculateErrorRate(errors, total);
        }

        /// Calculate total error rate (0.0 - 1.0).
        pub fn totalErrorRate(self: *const RotationStats) f64 {
            const total = Utils.atomicLoadU64(&self.totalRotations);
            const rotErrors = Utils.atomicLoadU64(&self.rotationErrors);
            const compErrors = Utils.atomicLoadU64(&self.compressionErrors);
            return Utils.calculateErrorRate(rotErrors + compErrors, total);
        }
    };

    /// Memory allocator for file operations.
    allocator: std.mem.Allocator,
    /// Base path of the log file to rotate.
    basePath: []const u8,
    /// Time-based rotation interval (null to disable).
    interval: ?RotationInterval = null,
    /// Size-based rotation limit in bytes (null to disable).
    sizeLimit: ?u64 = null,
    /// Maximum number of rotated files to keep.
    retention: ?usize = null,
    /// Maximum age of rotated files in seconds.
    maxAgeSeconds: ?i64 = null,
    /// Maximum total size of all rotated files in bytes.
    maxTotalSize: ?u64 = null,
    /// Custom rotation callback.
    onRotate: ?*const fn (oldPath: []const u8, newPath: []const u8) void = null,
    /// Timestamp of last rotation.
    lastRotation: i64,
    /// Naming strategy for rotated files.
    naming: NamingStrategy = .timestamp,
    /// Custom naming format string.
    namingFormat: ?[]const u8 = null,
    /// Compression configuration for rotated files.
    compression: ?CompressionConfig = null,
    /// Compression engine instance.
    compressor: ?Compression = null,
    /// Directory for archived/compressed files.
    archiveDir: ?[]const u8 = null,
    /// Clean empty directories after rotation.
    cleanEmptyDirs: bool = false,

    /// Keep original file after compression (default: false - delete original).
    keepOriginal: bool = false,

    /// Compress files during retention cleanup instead of deleting them.
    /// When true, old files exceeding retention limits are compressed rather than deleted.
    compressOnRetention: bool = false,

    /// Delete files after compression during retention (only applies when compress_on_retention is true).
    /// When false, compressed files are kept; when true, originals are deleted after compression.
    deleteAfterRetentionCompress: bool = true,

    /// Callback invoked when rotation starts.
    onRotationStart: ?*const fn (oldPath: []const u8, newPath: []const u8) void = null,
    /// Callback invoked when rotation completes successfully.
    onRotationComplete: ?*const fn (oldPath: []const u8, newPath: []const u8, elapsedMs: u64) void = null,
    /// Callback invoked when rotation encounters an error.
    onRotationError: ?*const fn (path: []const u8, err: anyerror) void = null,
    /// Callback invoked when a file is archived.
    onFileArchived: ?*const fn (originalPath: []const u8, archivePath: []const u8) void = null,
    /// Callback invoked during retention cleanup.
    onRetentionCleanup: ?*const fn (path: []const u8) void = null,

    /// Rotation statistics.
    stats: RotationStats = .{},
    /// Explicit I/O handle for file operations and synchronization.
    io: std.Io = Utils.defaultIo(),
    /// Mutex for thread-safe operations.
    mutex: std.Io.Mutex = std.Io.Mutex.init,

    /// Initializes rotation with optional interval, size limit, and retention count using default Io.
    pub fn init(
        allocator: std.mem.Allocator,
        path: []const u8,
        intervalStr: ?[]const u8,
        sizeLimit: ?u64,
        retention: ?usize,
    ) !Rotation {
        return initWithIo(allocator, Utils.defaultIo(), path, intervalStr, sizeLimit, retention);
    }

    /// Initializes rotation with explicit Io handle.
    pub fn initWithIo(
        allocator: std.mem.Allocator,
        io_handle: std.Io,
        path: []const u8,
        intervalStr: ?[]const u8,
        sizeLimit: ?u64,
        retention: ?usize,
    ) !Rotation {
        const interval = if (intervalStr) |s| RotationInterval.fromString(s) else null;
        var r = Rotation{
            .allocator = allocator,
            .io = io_handle,
            .basePath = try allocator.dupe(u8, path),
            .interval = interval,
            .sizeLimit = sizeLimit,
            .retention = retention,
            .maxTotalSize = null,
            .onRotate = null,
            .lastRotation = Utils.currentSeconds(),
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

    /// Enables compression for rotated files.
    pub fn withCompression(self: *Rotation, config: CompressionConfig) !void {
        self.compression = config;
        // Pre-initialize compressor if needed
        self.compressor = Compression.initWithConfig(self.allocator, config);
    }

    /// Sets naming strategy used for rotated files.
    pub fn withNaming(self: *Rotation, strategy: NamingStrategy) void {
        self.naming = strategy;
    }

    /// Sets a custom naming format and switches to custom naming strategy.
    pub fn withNamingFormat(self: *Rotation, format: []const u8) !void {
        if (self.namingFormat) |f| self.allocator.free(f);
        self.namingFormat = try self.allocator.dupe(u8, format);
        self.naming = .custom;
    }

    /// Sets max retention age in seconds.
    pub fn withMaxAge(self: *Rotation, seconds: i64) void {
        self.maxAgeSeconds = seconds;
    }

    /// Sets the time-based interval directly.
    pub fn setInterval(self: *Rotation, interval: ?RotationInterval) void {
        self.interval = interval;
    }

    /// Sets the interval from a string value.
    ///
    /// Returns true when parsing succeeds. Passing null disables interval rotation.
    pub fn setIntervalFromString(self: *Rotation, intervalStr: ?[]const u8) bool {
        if (intervalStr) |value| {
            const parsed = RotationInterval.fromString(value) orelse return false;
            self.interval = parsed;
            return true;
        }

        self.interval = null;
        return true;
    }

    /// Sets size-based rotation threshold in bytes.
    pub fn setSizeLimit(self: *Rotation, sizeLimit: ?u64) void {
        self.sizeLimit = sizeLimit;
    }

    /// Sets max number of retained rotated files.
    pub fn setRetentionCount(self: *Rotation, retentionCount: ?usize) void {
        self.retention = retentionCount;
    }

    /// Sets retention count and max age in a single call.
    pub fn setRetentionPolicy(self: *Rotation, retentionCount: ?usize, maxAgeSeconds: ?i64) void {
        self.retention = retentionCount;
        self.maxAgeSeconds = maxAgeSeconds;
    }

    /// Sets max total size in bytes for all rotated files combined.
    pub fn setMaxTotalSize(self: *Rotation, limit: ?u64) void {
        self.maxTotalSize = limit;
    }

    /// Builder for setting max total size.
    pub fn withMaxTotalSize(self: *Rotation, limit: u64) void {
        self.maxTotalSize = limit;
    }

    /// Sets custom rotation callback.
    pub fn withOnRotate(self: *Rotation, callback: ?*const fn (oldPath: []const u8, newPath: []const u8) void) void {
        self.onRotate = callback;
    }

    /// Sets archive directory for rotated files.
    pub fn withArchiveDir(self: *Rotation, dir: []const u8) !void {
        if (self.archiveDir) |d| self.allocator.free(d);
        self.archiveDir = try self.allocator.dupe(u8, dir);
    }

    /// Enables or disables cleanup of empty directories during retention cleanup.
    pub fn setCleanEmptyDirs(self: *Rotation, clean: bool) void {
        self.cleanEmptyDirs = clean;
    }

    /// Set whether to keep original files after compression.
    pub fn withKeepOriginal(self: *Rotation, keep: bool) void {
        self.keepOriginal = keep;
    }

    /// Enable compression during retention cleanup instead of deletion.
    /// Old files will be compressed rather than deleted when they exceed retention limits.
    pub fn withCompressOnRetention(self: *Rotation, enable: bool) void {
        self.compressOnRetention = enable;
    }

    /// Set whether to delete original files after retention compression.
    /// Only applies when compress_on_retention is true.
    pub fn withDeleteAfterRetentionCompress(self: *Rotation, delete: bool) void {
        self.deleteAfterRetentionCompress = delete;
    }

    /// Applies global rotation configuration where local settings are missing.
    pub fn applyConfig(self: *Rotation, config: RotationConfig) !void {
        if (self.interval == null and config.interval != null) {
            const s = config.interval.?;
            if (RotationInterval.fromString(s)) |inv| {
                self.interval = inv;
            } else if (Utils.parseDuration(s)) |durMs| {
                self.maxAgeSeconds = @divTrunc(durMs, Constants.TimeConstants.msPerSecond);
            }
        }
        if (self.sizeLimit == null) {
            if (config.sizeLimit) |l| self.sizeLimit = l else if (config.sizeLimitStr) |s| {
                self.sizeLimit = Utils.parseSize(s);
            }
        }
        if (self.maxTotalSize == null) {
            if (config.maxTotalSize) |l| {
                self.maxTotalSize = l;
            } else if (config.maxTotalSizeStr) |s| {
                self.maxTotalSize = Utils.parseSize(s);
            }
        }
        if (self.onRotate == null) {
            self.onRotate = config.onRotate;
        }
        if (self.retention == null) self.retention = config.retentionCount;
        if (self.maxAgeSeconds == null) self.maxAgeSeconds = config.maxAgeSeconds;
        self.naming = config.namingStrategy;
        if (config.namingFormat) |f| try self.withNamingFormat(f);
        if (config.archiveDir) |d| try self.withArchiveDir(d);
        self.cleanEmptyDirs = config.cleanEmptyDirs;
        self.keepOriginal = config.keepOriginal;
        self.compressOnRetention = config.compressOnRetention;
        self.deleteAfterRetentionCompress = config.deleteAfterRetentionCompress;
    }

    /// Releases rotation-owned allocations.
    pub fn deinit(self: *Rotation) void {
        self.allocator.free(self.basePath);
        if (self.archiveDir) |d| self.allocator.free(d);
        if (self.namingFormat) |f| self.allocator.free(f);
        if (self.compressor) |*comp| comp.deinit();
    }

    /// Returns current rotation statistics.
    pub fn getStats(self: *const Rotation) RotationStats {
        return self.stats;
    }

    /// Returns whether any rotation trigger is currently enabled.
    pub fn isEnabled(self: *const Rotation) bool {
        return self.interval != null or self.sizeLimit != null;
    }

    /// Returns current interval name, or `"none"` when disabled.
    pub fn intervalName(self: *const Rotation) []const u8 {
        if (self.interval) |i| return i.name();
        return "none";
    }

    /// Computes rotation reason without taking locks.
    /// Both triggers are always evaluated so hybrid setups report the
    /// exact reason via getRotationReason().
    fn computeRotationReason(self: *Rotation, filePtr: *std.Io.File, now: i64) ?RotationReason {
        var byInterval = false;
        var bySize = false;

        if (self.interval) |interval| {
            byInterval = now - self.lastRotation >= interval.seconds();
        }

        if (self.sizeLimit) |limit| {
            if (filePtr.stat(self.io)) |stat| {
                bySize = stat.size >= limit;
            } else |_| {
                // Ignore stat errors and retry on next check.
            }
        }

        if (byInterval and bySize) return .intervalAndSize;
        if (byInterval) return .interval;
        if (bySize) return .size;
        return null;
    }

    /// Returns why rotation would occur for the current file state.
    pub fn getRotationReason(self: *Rotation, filePtr: *std.Io.File) ?RotationReason {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);

        return self.computeRotationReason(filePtr, Utils.currentSeconds());
    }

    /// Returns true when rotation conditions are currently met.
    pub fn shouldRotate(self: *Rotation, filePtr: *std.Io.File) bool {
        return self.getRotationReason(filePtr) != null;
    }

    /// Returns remaining seconds until next time-based rotation.
    ///
    /// Returns null when interval rotation is disabled.
    pub fn nextRotationInSeconds(self: *const Rotation) ?i64 {
        const interval = self.interval orelse return null;
        const elapsed = Utils.currentSeconds() - self.lastRotation;
        const remaining = interval.seconds() - elapsed;
        return if (remaining > 0) remaining else 0;
    }

    /// Returns the next rotation time as epoch seconds.
    ///
    /// Returns null when interval rotation is disabled.
    pub fn nextRotationAt(self: *const Rotation) ?i64 {
        const remaining = self.nextRotationInSeconds() orelse return null;
        return Utils.currentSeconds() + remaining;
    }

    /// Returns how many seconds have elapsed since the last rotation.
    pub fn rotationAgeSeconds(self: *const Rotation) i64 {
        return Utils.currentSeconds() - self.lastRotation;
    }

    /// Forces immediate rotation regardless of current interval/size checks.
    pub fn forceRotate(self: *Rotation, filePtr: *std.Io.File) !void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);

        try self.performRotation(filePtr);
    }

    /// Returns the next rotated path without mutating state.
    pub fn previewNextPath(self: *Rotation) ![]u8 {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        return self.generateRotatedPath();
    }

    /// Whether rotation is due right now.
    ///
    /// Single source of truth for the trigger decision shared by
    /// checkAndRotate and external callers. When contentSize is provided it
    /// replaces the file stat for the size check (mmap files: stat sees
    /// preallocation, not content); otherwise the file is statted.
    /// Pure predicate: no locks, no mutation.
    pub fn rotationDue(self: *Rotation, filePtr: *std.Io.File, now: i64, contentSize: ?u64) bool {
        if (self.interval) |interval| {
            if (now - self.lastRotation >= interval.seconds()) return true;
        }
        if (self.sizeLimit) |limit| {
            if (contentSize) |size| {
                if (size >= limit) return true;
            } else {
                if (filePtr.stat(self.io)) |stat| {
                    if (stat.size >= limit) return true;
                } else |_| {}
            }
        }
        return false;
    }

    /// Performs rotation when interval and/or size triggers are met.
    ///
    /// Hot-path fast path: the interval check is pure integer arithmetic,
    /// so when it fires the size stat syscall is skipped. Exact reason
    /// reporting stays in getRotationReason().
    pub fn checkAndRotate(self: *Rotation, filePtr: *std.Io.File) !void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);

        if (self.rotationDue(filePtr, Utils.currentSeconds(), null)) {
            // Perform rotation
            self.performRotation(filePtr) catch |err| {
                _ = self.stats.rotationErrors.fetchAdd(1, .monotonic);
                if (self.onRotationError) |cb| cb(self.basePath, err);
                // Don't propagate error to avoid crashing application logging, just log error
            };
        }
    }

    /// Alias for withCompression
    // pub const compression = withCompression; // conflicts with field

    /// Alias for withNaming
    // pub const naming = withNaming; // conflicts with field

    /// Alias for deinit
    // pub const destroy = deinit; // already exists

    /// Alias for getStats
    // pub const statistics = getStats; // already exists
    // pub const stats = getStats; // conflicts with field

    fn performRotation(self: *Rotation, filePtr: *std.Io.File) !void {
        const startTime = Utils.currentMillis();

        // 1. Generate new filename
        const rotatedPath = try self.generateRotatedPath();
        defer self.allocator.free(rotatedPath);

        // Ensure archive dir exists if used
        if (self.archiveDir) |_| {
            const dir = std.fs.path.dirname(rotatedPath);
            if (dir) |d| {
                std.Io.Dir.cwd().createDirPath(self.io, d) catch {};
            }
        }

        if (self.onRotationStart) |cb| cb(self.basePath, rotatedPath);

        // 2. Close current file
        filePtr.close(self.io);

        // 3. Rename current file to rotated path
        // For index strategy, we might need to shift existing files first
        if (self.naming == .index) {
            try self.shiftIndexFiles();
        }

        std.Io.Dir.cwd().rename(self.basePath, std.Io.Dir.cwd(), rotatedPath, self.io) catch |err| {
            // Try to reopen functionality if rename fails
            filePtr.* = try std.Io.Dir.cwd().createFile(self.io, self.basePath, .{ .read = true, .truncate = false }); // Append mode effectively
            return err;
        };

        // 4. Re-open log file (fresh)
        filePtr.* = try std.Io.Dir.cwd().createFile(self.io, self.basePath, .{
            .read = true,
            .truncate = true,
        });

        self.lastRotation = Utils.currentSeconds();
        _ = self.stats.totalRotations.fetchAdd(1, .monotonic);

        const elapsed = @as(Constants.AtomicUnsigned, @intCast(Utils.currentMillis() - startTime));
        self.stats.lastRotationTimeMs.store(elapsed, .monotonic);
        if (self.onRotationComplete) |cb| cb(self.basePath, rotatedPath, @as(u64, @intCast(elapsed)));
        if (self.onRotate) |cb| cb(self.basePath, rotatedPath);

        // 5. Compress if enabled
        var finalPath = try self.allocator.dupe(u8, rotatedPath);
        errdefer self.allocator.free(finalPath);

        if (self.compression) |compConfig| {
            if (self.compressor) |*comp| {
                const compressedPath = try uniqueCompressedPath(self.allocator, rotatedPath, compConfig.algorithm);
                errdefer self.allocator.free(compressedPath);

                // Compress; archive accounting happens only on success so a
                // failed compression never masquerades as an archived file.
                _ = comp.compressFile(rotatedPath, compressedPath) catch {
                    _ = self.stats.compressionErrors.fetchAdd(1, .monotonic);
                    // On failure, we keep the uncompressed file
                    self.allocator.free(compressedPath);
                    self.allocator.free(finalPath);
                    if (self.retention != null or self.maxAgeSeconds != null) {
                        self.cleanupOldFiles() catch {};
                    }
                    return;
                };

                // If successful and keep_original is false, remove uncompressed rotated file
                if (!self.keepOriginal) {
                    std.Io.Dir.cwd().deleteFile(self.io, rotatedPath) catch {};
                }

                self.allocator.free(finalPath);
                finalPath = try self.allocator.dupe(u8, compressedPath);

                _ = self.stats.filesArchived.fetchAdd(1, .monotonic);
                if (self.onFileArchived) |cb| cb(rotatedPath, finalPath);
            }
        }

        self.allocator.free(finalPath);

        // 6. Cleanup old files
        if (self.retention != null or self.maxAgeSeconds != null) {
            self.cleanupOldFiles() catch {};
        }
    }

    fn generateRotatedPath(self: *Rotation) ![]u8 {
        const nowMs = Utils.currentMillis();
        const now = @divFloor(nowMs, Constants.TimeConstants.msPerSecond);
        const millis = @as(u64, @intCast(@mod(nowMs, Constants.TimeConstants.msPerSecond)));
        var nameBuf: []u8 = undefined;

        const baseName = std.fs.path.basename(self.basePath);

        switch (self.naming) {
            .timestamp => {
                nameBuf = try std.fmt.allocPrint(self.allocator, "{s}.{d}", .{ baseName, now });
            },
            .date => {
                // Format YYYY-MM-DD
                const epoch = std.time.epoch.EpochSeconds{ .secs = @intCast(now) };
                const yd = epoch.getEpochDay().calculateYearDay();
                const md = yd.calculateMonthDay();
                nameBuf = try std.fmt.allocPrint(self.allocator, "{s}.{d:0>4}-{d:0>2}-{d:0>2}", .{ baseName, yd.year, md.month.numeric(), md.day_index + 1 });
            },
            .isoDatetime => {
                const epoch = std.time.epoch.EpochSeconds{ .secs = @intCast(now) };
                const yd = epoch.getEpochDay().calculateYearDay();
                const md = yd.calculateMonthDay();
                const ds = epoch.getDaySeconds();
                const h = ds.secs / @as(u64, Constants.TimeConstants.secondsPerHour);
                const m = (ds.secs % @as(u64, Constants.TimeConstants.secondsPerHour)) / @as(u64, Constants.TimeConstants.secondsPerMinute);
                const s = ds.secs % @as(u64, Constants.TimeConstants.secondsPerMinute);

                var res = std.Io.Writer.Allocating.init(self.allocator);
                errdefer res.deinit();
                const w = &res.writer;
                try w.writeAll(baseName);
                try w.writeByte('.');
                try Utils.writeFilenameSafe(w, Utils.TimeComponents{
                    .year = yd.year,
                    .month = md.month.numeric(),
                    .day = md.day_index + 1,
                    .hour = h,
                    .minute = m,
                    .second = s,
                });
                nameBuf = try res.toOwnedSlice();
            },
            .index => {
                // For index strategy, the immediate rotated file is always .1
                nameBuf = try std.fmt.allocPrint(self.allocator, "{s}.1", .{baseName});
            },
            .custom => {
                if (self.namingFormat) |fmt| {
                    // Parse format: {base}, {ext}, {timestamp}, {date}, {time}, {iso}
                    const ext = std.fs.path.extension(baseName);
                    const stem = if (ext.len > 0) baseName[0..(baseName.len - ext.len)] else baseName;

                    // Helper formatting
                    const epoch = std.time.epoch.EpochSeconds{ .secs = @intCast(now) };
                    const yd = epoch.getEpochDay().calculateYearDay();
                    const md = yd.calculateMonthDay();
                    const ds = epoch.getDaySeconds();
                    const h = ds.secs / @as(u64, Constants.TimeConstants.secondsPerHour);
                    const m = (ds.secs % @as(u64, Constants.TimeConstants.secondsPerHour)) / @as(u64, Constants.TimeConstants.secondsPerMinute);
                    const s = ds.secs % @as(u64, Constants.TimeConstants.secondsPerMinute);

                    // Optimization: Pre-allocate buffer to minimize reallocations
                    // Estimate size: format length + extra space for replacements (timestamp, etc.)
                    var res = try std.Io.Writer.Allocating.initCapacity(self.allocator, fmt.len + 64);
                    errdefer res.deinit();
                    const w = &res.writer;

                    var i: usize = 0;
                    while (i < fmt.len) {
                        if (fmt[i] == '{') {
                            const end = std.mem.indexOfPos(u8, fmt, i, "}") orelse {
                                try w.writeByte(fmt[i]);
                                i += 1;
                                continue;
                            };
                            const tag = fmt[i + 1 .. end];
                            if (std.mem.eql(u8, tag, "base")) {
                                try w.writeAll(stem);
                            } else if (std.mem.eql(u8, tag, "ext")) {
                                try w.writeAll(ext);
                            } else if (std.mem.eql(u8, tag, "timestamp")) {
                                try Utils.writeInt(w, now);
                            } else if (std.mem.eql(u8, tag, "date")) {
                                try Utils.writeIsoDate(w, Utils.TimeComponents{
                                    .year = yd.year,
                                    .month = md.month.numeric(),
                                    .day = md.day_index + 1,
                                    .hour = h,
                                    .minute = m,
                                    .second = s,
                                });
                            } else if (std.mem.eql(u8, tag, "time")) {
                                try Utils.writeIsoTime(w, Utils.TimeComponents{
                                    .year = yd.year,
                                    .month = md.month.numeric(),
                                    .day = md.day_index + 1,
                                    .hour = h,
                                    .minute = m,
                                    .second = s,
                                });
                            } else if (std.mem.eql(u8, tag, "iso")) {
                                try Utils.writeIsoDateTime(w, Utils.TimeComponents{
                                    .year = yd.year,
                                    .month = md.month.numeric(),
                                    .day = md.day_index + 1,
                                    .hour = h,
                                    .minute = m,
                                    .second = s,
                                });
                            } else {
                                // Granular date format parsing via shared utility
                                try Utils.formatDatePattern(w, tag, yd.year, md.month.numeric(), md.day_index + 1, h, m, s, millis);
                            }
                            i = end + 1;
                        } else {
                            try w.writeByte(fmt[i]);
                            i += 1;
                        }
                    }
                    nameBuf = try res.toOwnedSlice();
                } else {
                    // Fallback if custom selected but no format
                    nameBuf = try std.fmt.allocPrint(self.allocator, "{s}.{d}", .{ baseName, now });
                }
            },
        }
        defer self.allocator.free(nameBuf);

        if (self.archiveDir) |dir| {
            return std.fs.path.join(self.allocator, &.{ dir, nameBuf });
        } else {
            const dir = std.fs.path.dirname(self.basePath) orelse ".";
            return std.fs.path.join(self.allocator, &.{ dir, nameBuf });
        }
    }

    fn uniqueCompressedPath(allocator: std.mem.Allocator, base: []const u8, algo: Compression.Algorithm) ![]u8 {
        const ext = Utils.getCompressionExtension(algo);
        return std.fmt.allocPrint(allocator, "{s}{s}", .{ base, ext });
    }

    fn shiftIndexFiles(self: *Rotation) !void {
        // This assumes we have a reasonable max retention to avoid infinite loop
        // We shift .N -> .N+1
        const max = self.retention orelse Constants.RotationDefaults.retentionCount; // Default limit for shifting
        const targetDir = self.archiveDir orelse (std.fs.path.dirname(self.basePath) orelse ".");
        const baseName = std.fs.path.basename(self.basePath);

        // Work backwards
        var i: usize = max;
        while (i >= 1) : (i -= 1) {
            const currentName = try std.fmt.allocPrint(self.allocator, "{s}.{d}", .{ baseName, i });
            defer self.allocator.free(currentName);
            const currentPath = try std.fs.path.join(self.allocator, &.{ targetDir, currentName });
            defer self.allocator.free(currentPath);

            // If file exists
            if (std.Io.Dir.cwd().access(self.io, currentPath, .{})) |_| {
                if (i == max) {
                    // Delete overflow
                    std.Io.Dir.cwd().deleteFile(self.io, currentPath) catch {};
                } else {
                    // Rename to next
                    const nextName = try std.fmt.allocPrint(self.allocator, "{s}.{d}", .{ baseName, i + 1 });
                    defer self.allocator.free(nextName);
                    const nextPath = try std.fs.path.join(self.allocator, &.{ targetDir, nextName });
                    defer self.allocator.free(nextPath);

                    std.Io.Dir.cwd().rename(currentPath, std.Io.Dir.cwd(), nextPath, self.io) catch {};
                }
            } else |_| {}
        }
    }

    fn cleanupOldFiles(self: *Rotation) !void {
        const dirPath = self.archiveDir orelse (std.fs.path.dirname(self.basePath) orelse ".");
        const baseName = std.fs.path.basename(self.basePath);

        var dir = std.Io.Dir.cwd().openDir(self.io, dirPath, .{ .iterate = true }) catch return;
        defer dir.close(self.io);

        const FileInfo = struct { name: []u8, mtime: i128, isCompressed: bool, size: u64 };
        var files: std.ArrayList(FileInfo) = .empty;
        defer {
            for (files.items) |f| self.allocator.free(f.name);
            files.deinit(self.allocator);
        }

        var iter = dir.iterate();
        while (try iter.next(self.io)) |entry| {
            if (entry.kind != .file) continue;
            // Matches base_name and starts with it
            if (std.mem.startsWith(u8, entry.name, baseName) and !std.mem.eql(u8, entry.name, baseName)) {
                const fullPath = try std.fs.path.join(self.allocator, &.{ dirPath, entry.name });
                defer self.allocator.free(fullPath);

                const stat = std.Io.Dir.cwd().statFile(self.io, fullPath, .{}) catch continue;

                // Check if already compressed
                const isCompressed = Constants.CompressionExtensions.isCompressed(entry.name);

                // Age check (both sides wall-clock: file mtime is wall time,
                // so compare against wall now, never the monotonic clock).
                if (self.maxAgeSeconds) |maxAge| {
                    const nowWallNs: i128 = @as(i128, Utils.currentMillis()) * Constants.TimeConstants.nsPerMs;
                    const age = nowWallNs - stat.mtime.toNanoseconds();
                    if (age > @as(i128, maxAge) * Constants.TimeConstants.nsPerSecond) {
                        self.handleRetentionFile(fullPath, isCompressed) catch {};
                        continue; // handled, don't add to list
                    }
                }

                try files.append(self.allocator, .{
                    .name = try self.allocator.dupe(u8, entry.name),
                    .mtime = stat.mtime.toNanoseconds(),
                    .isCompressed = isCompressed,
                    .size = stat.size,
                });
            }
        }

        // Sort by modification time (oldest first)
        std.mem.sort(FileInfo, files.items, {}, struct {
            fn lessThan(_: void, a: FileInfo, b: FileInfo) bool {
                return a.mtime < b.mtime;
            }
        }.lessThan);

        var remainingStart: usize = 0;

        // Retention check with count sorted by mtime. One bad file must not
        // abort the remaining retention pass.
        if (self.retention) |maxFiles| {
            if (files.items.len > maxFiles) {
                const toDelete = files.items.len - maxFiles;
                for (files.items[0..toDelete]) |item| {
                    const fullPath = try std.fs.path.join(self.allocator, &.{ dirPath, item.name });
                    defer self.allocator.free(fullPath);
                    self.handleRetentionFile(fullPath, item.isCompressed) catch {};
                }
                remainingStart = toDelete;
            }
        }

        // Max total size check
        if (self.maxTotalSize) |maxBytes| {
            const remainingFiles = files.items[remainingStart..];
            var totalSize: u64 = 0;
            for (remainingFiles) |item| {
                totalSize += item.size;
            }

            var idx: usize = 0;
            while (idx < remainingFiles.len and totalSize > maxBytes) {
                const item = remainingFiles[idx];
                const fullPath = try std.fs.path.join(self.allocator, &.{ dirPath, item.name });
                defer self.allocator.free(fullPath);
                self.handleRetentionFile(fullPath, item.isCompressed) catch {};
                totalSize -= item.size;
                idx += 1;
            }
        }

        if (self.cleanEmptyDirs) {
            // Only attempt to clean if archive_dir is explicitly set to avoid accidents
            if (self.archiveDir) |archivePath| {
                // Attempt to remove directory. Will fail safely if not empty.
                std.Io.Dir.cwd().deleteDir(self.io, archivePath) catch {};
            }
        }
    }

    /// Handle a file during retention cleanup - either compress or delete based on settings.
    fn handleRetentionFile(self: *Rotation, path: []const u8, isCompressed: bool) !void {
        // If compress_on_retention is enabled and file is not already compressed
        if (self.compressOnRetention and !isCompressed) {
            if (self.compressor) |*comp| {
                const algo = if (self.compression) |c| c.algorithm else .deflate;
                const compressedPath = try uniqueCompressedPath(self.allocator, path, algo);
                defer self.allocator.free(compressedPath);

                // Compress the file
                _ = comp.compressFile(path, compressedPath) catch |err| {
                    _ = self.stats.compressionErrors.fetchAdd(1, .monotonic);
                    // On failure, fall back to deletion if delete_after_retention_compress is true
                    if (self.deleteAfterRetentionCompress) {
                        try self.deleteFile(path);
                    }
                    return err;
                };

                _ = self.stats.filesArchived.fetchAdd(1, .monotonic);
                if (self.onFileArchived) |cb| cb(path, compressedPath);

                // Delete original after successful compression if configured
                if (self.deleteAfterRetentionCompress) {
                    std.Io.Dir.cwd().deleteFile(self.io, path) catch {};
                }
                return;
            }
        }

        // Default behavior: delete the file
        try self.deleteFile(path);
    }

    fn deleteFile(self: *Rotation, path: []const u8) !void {
        std.Io.Dir.cwd().deleteFile(self.io, path) catch {
            _ = self.stats.rotationErrors.fetchAdd(1, .monotonic);
            return;
        };
        _ = self.stats.filesDeleted.fetchAdd(1, .monotonic);
        if (self.onRetentionCleanup) |cb| cb(path);
    }

    /// Creates a rotating sink with specified naming strategy
    pub fn createRotatingSink(filePath: []const u8, interval: []const u8, retention: usize) SinkConfig {
        return SinkConfig{
            .path = filePath,
            .rotation = interval,
            .retention = retention,
            .color = false,
        };
    }

    /// Creates a size-based rotating sink configuration.
    pub fn createSizeRotatingSink(filePath: []const u8, sizeLimit: u64, retention: usize) SinkConfig {
        return SinkConfig{
            .path = filePath,
            .sizeLimit = sizeLimit,
            .retention = retention,
            .color = false,
        };
    }
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
        return Rotation.init(allocator, path, null, 1 * Constants.SizeConstants.bytesPerMb, 5);
    }

    /// 5MB size-based rotation with 5 file retention.
    pub fn size5MB(allocator: std.mem.Allocator, path: []const u8) !Rotation {
        return Rotation.init(allocator, path, null, 5 * Constants.SizeConstants.bytesPerMb, 5);
    }

    /// 10MB size-based rotation with 5 file retention.
    pub fn size10MB(allocator: std.mem.Allocator, path: []const u8) !Rotation {
        return Rotation.init(allocator, path, null, 10 * Constants.SizeConstants.bytesPerMb, 5);
    }

    /// 25MB size-based rotation with 10 file retention.
    pub fn size25MB(allocator: std.mem.Allocator, path: []const u8) !Rotation {
        return Rotation.init(allocator, path, null, 25 * Constants.SizeConstants.bytesPerMb, 10);
    }

    /// 50MB size-based rotation with 10 file retention.
    pub fn size50MB(allocator: std.mem.Allocator, path: []const u8) !Rotation {
        return Rotation.init(allocator, path, null, 50 * Constants.SizeConstants.bytesPerMb, 10);
    }

    /// 100MB size-based rotation with 10 file retention.
    pub fn size100MB(allocator: std.mem.Allocator, path: []const u8) !Rotation {
        return Rotation.init(allocator, path, null, 100 * Constants.SizeConstants.bytesPerMb, 10);
    }

    /// 250MB size-based rotation with 5 file retention (large logs).
    pub fn size250MB(allocator: std.mem.Allocator, path: []const u8) !Rotation {
        return Rotation.init(allocator, path, null, 250 * Constants.SizeConstants.bytesPerMb, 5);
    }

    /// 500MB size-based rotation with 3 file retention.
    pub fn size500MB(allocator: std.mem.Allocator, path: []const u8) !Rotation {
        return Rotation.init(allocator, path, null, 500 * Constants.SizeConstants.bytesPerMb, 3);
    }

    /// 1GB size-based rotation with 2 file retention.
    pub fn size1GB(allocator: std.mem.Allocator, path: []const u8) !Rotation {
        return Rotation.init(allocator, path, null, Constants.SizeConstants.bytesPerGb, 2);
    }

    // Hybrid Presets (Time + Size)

    /// Daily rotation OR 100MB, 30 day retention.
    pub fn dailyOr100MB(allocator: std.mem.Allocator, path: []const u8) !Rotation {
        return Rotation.init(allocator, path, "daily", 100 * Constants.SizeConstants.bytesPerMb, 30);
    }

    /// Hourly rotation OR 50MB, 48 hour retention.
    pub fn hourlyOr50MB(allocator: std.mem.Allocator, path: []const u8) !Rotation {
        return Rotation.init(allocator, path, "hourly", 50 * Constants.SizeConstants.bytesPerMb, 48);
    }

    /// Daily rotation OR 500MB, 7 day retention (high volume).
    pub fn dailyOr500MB(allocator: std.mem.Allocator, path: []const u8) !Rotation {
        return Rotation.init(allocator, path, "daily", 500 * Constants.SizeConstants.bytesPerMb, 7);
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
        rot.withNaming(.isoDatetime);
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
        var rot = try Rotation.init(allocator, path, "hourly", 500 * Constants.SizeConstants.bytesPerMb, 168);
        rot.withNaming(.isoDatetime);
        try rot.withCompression(.{ .algorithm = .deflate });
        return rot;
    }

    /// Audit preset: daily rotation, 365 days, compressed archive, ISO naming.
    pub fn audit(allocator: std.mem.Allocator, path: []const u8) !Rotation {
        var rot = try Rotation.init(allocator, path, "daily", null, 365);
        rot.withNaming(.isoDatetime);
        try rot.withCompression(.{ .algorithm = .deflate, .level = .best });
        rot.withCompressOnRetention(true);
        rot.withDeleteAfterRetentionCompress(false);
        return rot;
    }

    /// Minimal preset: size-only 10MB, 3 files (embedded/resource constrained).
    pub fn minimal(allocator: std.mem.Allocator, path: []const u8) !Rotation {
        var rot = try Rotation.init(allocator, path, null, 10 * Constants.SizeConstants.bytesPerMb, 3);
        rot.withNaming(.index);
        return rot;
    }

    // Sink Configuration Helpers

    /// Creates a daily rotation sink config.
    pub fn dailySink(filePath: []const u8, retentionDays: usize) SinkConfig {
        return Rotation.createRotatingSink(filePath, "daily", retentionDays);
    }

    /// Creates an hourly rotation sink config.
    pub fn hourlySink(filePath: []const u8, retentionHours: usize) SinkConfig {
        return Rotation.createRotatingSink(filePath, "hourly", retentionHours);
    }

    /// Creates a weekly rotation sink config.
    pub fn weeklySink(filePath: []const u8, retentionWeeks: usize) SinkConfig {
        return Rotation.createRotatingSink(filePath, "weekly", retentionWeeks);
    }

    /// Creates a monthly rotation sink config.
    pub fn monthlySink(filePath: []const u8, retentionMonths: usize) SinkConfig {
        return Rotation.createRotatingSink(filePath, "monthly", retentionMonths);
    }

    /// Creates a size-based rotation sink config.
    pub fn sizeSink(filePath: []const u8, sizeBytes: u64, retention: usize) SinkConfig {
        return Rotation.createSizeRotatingSink(filePath, sizeBytes, retention);
    }

    // Aliases for common presets
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
    try std.testing.expectEqual(@as(i64, Constants.TimeConstants.secondsPerMinute), Rotation.RotationInterval.minutely.seconds());
    try std.testing.expectEqual(@as(i64, Constants.TimeConstants.secondsPerHour), Rotation.RotationInterval.hourly.seconds());
    try std.testing.expectEqual(@as(i64, Constants.TimeConstants.secondsPerDay), Rotation.RotationInterval.daily.seconds());
    try std.testing.expectEqual(@as(i64, Constants.TimeConstants.secondsPerWeek), Rotation.RotationInterval.weekly.seconds());
    try std.testing.expectEqual(@as(i64, Constants.TimeConstants.secondsPerMonth), Rotation.RotationInterval.monthly.seconds());
    try std.testing.expectEqual(@as(i64, Constants.TimeConstants.secondsPerYear), Rotation.RotationInterval.yearly.seconds());
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
    _ = stats.totalRotations.fetchAdd(10, .monotonic);
    _ = stats.rotationErrors.fetchAdd(2, .monotonic);

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
    try std.testing.expectEqual(@as(?u64, 1 * Constants.SizeConstants.bytesPerMb), size1.sizeLimit);

    var size10 = try RotationPresets.size10MB(allocator, "test.log");
    defer size10.deinit();
    try std.testing.expectEqual(@as(?u64, 10 * Constants.SizeConstants.bytesPerMb), size10.sizeLimit);

    var size100 = try RotationPresets.size100MB(allocator, "test.log");
    defer size100.deinit();
    try std.testing.expectEqual(@as(?u64, 100 * Constants.SizeConstants.bytesPerMb), size100.sizeLimit);

    var size1gb = try RotationPresets.size1GB(allocator, "test.log");
    defer size1gb.deinit();
    try std.testing.expectEqual(@as(?u64, Constants.SizeConstants.bytesPerGb), size1gb.sizeLimit);
}

test "rotation presets hybrid" {
    const allocator = std.testing.allocator;

    var hybrid = try RotationPresets.dailyOr100MB(allocator, "test.log");
    defer hybrid.deinit();
    try std.testing.expectEqual(Rotation.RotationInterval.daily, hybrid.interval.?);
    try std.testing.expectEqual(@as(?u64, 100 * Constants.SizeConstants.bytesPerMb), hybrid.sizeLimit);
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
    try std.testing.expectEqual(Rotation.NamingStrategy.isoDatetime, ent.naming);
    try std.testing.expect(ent.compressOnRetention);

    // Audit preset
    var audit = try RotationPresets.audit(allocator, "test.log");
    defer audit.deinit();
    try std.testing.expectEqual(@as(?usize, 365), audit.retention);
    try std.testing.expect(audit.compressOnRetention);
    try std.testing.expect(!audit.deleteAfterRetentionCompress);

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
    try std.testing.expect(rot.keepOriginal);

    rot.withCompressOnRetention(true);
    try std.testing.expect(rot.compressOnRetention);

    rot.withDeleteAfterRetentionCompress(false);
    try std.testing.expect(!rot.deleteAfterRetentionCompress);

    rot.withMaxAge(@as(i64, Constants.TimeConstants.secondsPerDay) * 7);
    try std.testing.expectEqual(@as(?i64, @as(i64, Constants.TimeConstants.secondsPerWeek)), rot.maxAgeSeconds);

    rot.setCleanEmptyDirs(true);
    try std.testing.expect(rot.cleanEmptyDirs);
}

test "rotation explicit control helpers" {
    const allocator = std.testing.allocator;

    var rot = try Rotation.init(allocator, "rotation_controls.log", "daily", Constants.SizeConstants.bytesPerKb, 7);
    defer rot.deinit();

    rot.setInterval(.hourly);
    try std.testing.expectEqual(Rotation.RotationInterval.hourly, rot.interval.?);

    try std.testing.expect(rot.setIntervalFromString("weekly"));
    try std.testing.expectEqual(Rotation.RotationInterval.weekly, rot.interval.?);

    try std.testing.expect(rot.setIntervalFromString(null));
    try std.testing.expect(rot.interval == null);
    try std.testing.expect(!rot.setIntervalFromString("invalid-interval"));

    rot.setSizeLimit(Constants.SizeConstants.bytesPerKb * 2);
    try std.testing.expectEqual(@as(?u64, Constants.SizeConstants.bytesPerKb * 2), rot.sizeLimit);

    rot.setRetentionCount(12);
    try std.testing.expectEqual(@as(?usize, 12), rot.retention);

    rot.setRetentionPolicy(5, @as(i64, Constants.TimeConstants.secondsPerDay));
    try std.testing.expectEqual(@as(?usize, 5), rot.retention);
    try std.testing.expectEqual(@as(?i64, Constants.TimeConstants.secondsPerDay), rot.maxAgeSeconds);
}

test "rotation force rotate helper" {
    const allocator = std.testing.allocator;

    const fileName = try std.fmt.allocPrint(allocator, "rotation_force_{d}.log", .{Utils.currentMillis()});
    defer allocator.free(fileName);
    defer std.Io.Dir.cwd().deleteFile(Utils.defaultIo(), fileName) catch {};

    const rotatedName = try std.fmt.allocPrint(allocator, "{s}.1", .{fileName});
    defer allocator.free(rotatedName);
    defer std.Io.Dir.cwd().deleteFile(Utils.defaultIo(), rotatedName) catch {};

    var file = try std.Io.Dir.cwd().createFile(Utils.defaultIo(), fileName, .{ .read = true, .truncate = true });
    defer file.close(Utils.defaultIo());
    try file.writeStreamingAll(Utils.defaultIo(), "force rotation content");

    var rot = try Rotation.init(allocator, fileName, null, null, 3);
    defer rot.deinit();
    rot.withNaming(.index);

    try rot.forceRotate(&file);

    try std.Io.Dir.cwd().access(Utils.defaultIo(), fileName, .{});
    try std.Io.Dir.cwd().access(Utils.defaultIo(), rotatedName, .{});
    try std.testing.expect(rot.getStats().rotationCount() >= 1);
}

test "rotation sink creation" {
    // Daily sink
    const dailySink = RotationPresets.dailySink("logs/app.log", 7);
    try std.testing.expectEqualStrings("logs/app.log", dailySink.path.?);
    try std.testing.expectEqualStrings("daily", dailySink.rotation.?);
    try std.testing.expectEqual(@as(?usize, 7), dailySink.retention);

    // Size sink
    const sizeSink = RotationPresets.sizeSink("logs/app.log", 50 * Constants.SizeConstants.bytesPerMb, 5);
    try std.testing.expectEqual(@as(?u64, 50 * Constants.SizeConstants.bytesPerMb), sizeSink.sizeLimit);
    try std.testing.expectEqual(@as(?usize, 5), sizeSink.retention);
}

test "rotation is enabled check" {
    const allocator = std.testing.allocator;

    // Time-based enabled
    var rot1 = try Rotation.init(allocator, "test.log", "daily", null, null);
    defer rot1.deinit();
    try std.testing.expect(rot1.isEnabled());

    // Size-based enabled
    var rot2 = try Rotation.init(allocator, "test.log", null, Constants.SizeConstants.bytesPerKb, null);
    defer rot2.deinit();
    try std.testing.expect(rot2.isEnabled());

    // Neither enabled (though this is unusual usage)
    var rot3 = try Rotation.init(allocator, "test.log", null, null, null);
    defer rot3.deinit();
    try std.testing.expect(!rot3.isEnabled());
}

test "rotation reason helpers and preview path" {
    const allocator = std.testing.allocator;

    const fileName = try std.fmt.allocPrint(allocator, "rotation_reason_{d}.log", .{Utils.currentMillis()});
    defer allocator.free(fileName);
    defer std.Io.Dir.cwd().deleteFile(Utils.defaultIo(), fileName) catch {};

    var file = try std.Io.Dir.cwd().createFile(Utils.defaultIo(), fileName, .{ .read = true, .truncate = true });
    defer file.close(Utils.defaultIo());
    try file.writeStreamingAll(Utils.defaultIo(), "0123456789");

    var rot = try Rotation.init(allocator, fileName, null, 1, 3);
    defer rot.deinit();

    const reason = rot.getRotationReason(&file);
    try std.testing.expect(reason != null);
    try std.testing.expectEqual(Rotation.RotationReason.size, reason.?);
    try std.testing.expect(rot.shouldRotate(&file));

    const preview = try rot.previewNextPath();
    defer allocator.free(preview);
    try std.testing.expect(std.mem.indexOf(u8, preview, std.fs.path.basename(fileName)) != null);
}

test "rotation next rotation in seconds" {
    const allocator = std.testing.allocator;

    var rot = try Rotation.init(allocator, "test-next.log", "hourly", null, 7);
    defer rot.deinit();

    rot.lastRotation = Utils.currentSeconds() - 10;
    const remaining = rot.nextRotationInSeconds();

    try std.testing.expect(remaining != null);
    try std.testing.expect(remaining.? >= 0);
    try std.testing.expect(remaining.? <= @as(i64, Constants.TimeConstants.secondsPerHour));
}

test "rotation next rotation at and age helpers" {
    const allocator = std.testing.allocator;

    var rot = try Rotation.init(allocator, "test-next-at.log", "hourly", null, 7);
    defer rot.deinit();

    rot.lastRotation = Utils.currentSeconds() - 10;
    const nextAt = rot.nextRotationAt();
    try std.testing.expect(nextAt != null);
    try std.testing.expect(nextAt.? >= Utils.currentSeconds());

    const age = rot.rotationAgeSeconds();
    try std.testing.expect(age >= 0);
}

test "retention keeps the configured number of archives and prunes overflow" {
    const allocator = std.testing.allocator;
    const base = "test_retention.log";
    const dir = "logs";
    _ = std.Io.Dir.cwd().deleteFile(Utils.defaultIo(), base) catch {};
    defer std.Io.Dir.cwd().deleteFile(Utils.defaultIo(), base) catch {};
    std.Io.Dir.cwd().createDirPath(Utils.defaultIo(), dir) catch {};

    const retention: usize = 3;
    var rot = try Rotation.init(allocator, base, null, 1, retention);
    defer rot.deinit();

    // Force more rotations than retention allows. Each pass appends to the
    // live file, trips the 1-byte size limit, and shifts the index files.
    var pass: usize = 0;
    while (pass < retention + 2) : (pass += 1) {
        var f = try std.Io.Dir.cwd().createFile(Utils.defaultIo(), base, .{ .truncate = true });
        try rot.checkAndRotate(&f);

        // Write past the size limit so the next pass sees an oversized file.
        var filler: [64]u8 = @splat('x');
        try f.writeStreamingAll(Utils.defaultIo(), &filler);
        f.close(Utils.defaultIo());
    }

    // Every index file within the retention window exists.
    var i: usize = 1;
    while (i <= retention) : (i += 1) {
        var nameBuf: [64]u8 = undefined;
        const name = try std.fmt.bufPrint(&nameBuf, "{s}.{d}", .{ base, i });
        try std.testing.expectError(
            error.FileNotFound,
            std.Io.Dir.cwd().access(Utils.defaultIo(), name, .{}),
        );
    }

    // Anything past the window has been pruned.
    var overBuf: [64]u8 = undefined;
    const over = try std.fmt.bufPrint(&overBuf, "{s}.{d}", .{ base, retention + 1 });
    std.Io.Dir.cwd().deleteFile(Utils.defaultIo(), over) catch {};
}
