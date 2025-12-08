const std = @import("std");
const Config = @import("config.zig").Config;
const Level = @import("level.zig").Level;
const Record = @import("record.zig").Record;
const Formatter = @import("formatter.zig").Formatter;
const Rotation = @import("rotation.zig").Rotation;

/// Configuration for a specific log sink.
///
/// Sinks are destinations where logs are written (e.g., console, file).
/// Each sink can have its own configuration, overriding global settings.
pub const SinkConfig = struct {
    /// File path for the sink. If null, defaults to console output.
    path: ?[]const u8 = null,

    /// Sink identifier name for metrics and debugging.
    name: ?[]const u8 = null,

    /// Rotation settings: "minutely", "hourly", "daily", "weekly", "monthly", "yearly".
    rotation: ?[]const u8 = null,

    /// Size limit for rotation (in bytes).
    size_limit: ?u64 = null,

    /// Size limit as a string (e.g., "10MB", "1GB").
    size_limit_str: ?[]const u8 = null,

    /// Number of rotated files to keep.
    retention: ?usize = null,

    /// Sink-specific log level. Overrides the global level if set.
    level: ?Level = null,

    /// Maximum log level for this sink (create level range filters).
    max_level: ?Level = null,

    /// Enable async writing with background buffering.
    async_write: bool = true,

    /// Buffer size for async writing in bytes.
    buffer_size: usize = 8192,

    /// Force JSON output for this sink.
    json: bool = false,

    /// Pretty print JSON output with indentation.
    pretty_json: bool = false,

    /// Enable/disable colors for this sink.
    /// If null, auto-detect (enabled for console, disabled for files).
    color: ?bool = null,

    /// Enable/disable this sink initially.
    enabled: bool = true,

    /// Include timestamp in output.
    include_timestamp: bool = true,

    /// Include log level in output.
    include_level: bool = true,

    /// Include source location in output.
    include_source: bool = false,

    /// Include trace IDs in output (for distributed tracing).
    include_trace_id: bool = false,

    /// Custom log format string for this sink.
    /// Overrides global format if set.
    log_format: ?[]const u8 = null,

    /// Time format for this sink.
    time_format: ?[]const u8 = null,

    /// File write mode: false = append (default), true = overwrite.
    /// When true, existing files are truncated before writing.
    overwrite_mode: bool = false,

    /// Compression settings for file sinks.
    compression: CompressionConfig = .{},

    /// Filter configuration for this sink.
    filter: FilterConfig = .{},

    /// Error handling for this sink.
    on_error: ErrorBehavior = .log_stderr,

    /// Maximum records to buffer before forcing a flush.
    max_buffer_records: usize = 1000,

    /// Flush interval in milliseconds.
    flush_interval_ms: u64 = 1000,

    /// File permissions for created log files (Unix only).
    file_mode: ?u32 = null,

    /// Compression configuration for sink.
    /// Re-exports centralized config for convenience.
    pub const CompressionConfig = struct {
        enabled: bool = false,
        algorithm: Config.CompressionConfig.CompressionAlgorithm = .deflate,
        level: Config.CompressionConfig.CompressionLevel = .default,
    };

    /// Filter configuration for sink-level filtering.
    pub const FilterConfig = struct {
        /// Include only logs from these modules.
        include_modules: ?[]const []const u8 = null,

        /// Exclude logs from these modules.
        exclude_modules: ?[]const []const u8 = null,

        /// Include only logs containing these substrings.
        include_messages: ?[]const []const u8 = null,

        /// Exclude logs containing these substrings.
        exclude_messages: ?[]const []const u8 = null,
    };

    /// Error behavior for sink write failures.
    pub const ErrorBehavior = enum {
        /// Silently ignore errors.
        silent,

        /// Log errors to stderr.
        log_stderr,

        /// Disable the sink on error.
        disable_sink,

        /// Propagate the error to the caller.
        propagate,
    };

    /// Returns the default sink configuration (Console, async, standard format).
    pub fn default() SinkConfig {
        return .{};
    }

    /// Returns a file sink configuration.
    ///
    /// Arguments:
    ///     file_path: Path to the log file.
    ///
    /// Returns:
    ///     A SinkConfig configured for file output.
    pub fn file(file_path: []const u8) SinkConfig {
        return .{
            .path = file_path,
            .color = false,
        };
    }

    /// Returns a JSON file sink configuration.
    ///
    /// Arguments:
    ///     file_path: Path to the log file.
    ///
    /// Returns:
    ///     A SinkConfig configured for JSON file output.
    pub fn jsonFile(file_path: []const u8) SinkConfig {
        return .{
            .path = file_path,
            .json = true,
            .color = false,
        };
    }

    /// Returns a rotating file sink configuration.
    ///
    /// Arguments:
    ///     file_path: Path to the log file.
    ///     rotation_interval: Rotation interval string.
    ///     retention_count: Number of files to retain.
    ///
    /// Returns:
    ///     A SinkConfig configured for rotating file output.
    pub fn rotating(file_path: []const u8, rotation_interval: []const u8, retention_count: usize) SinkConfig {
        return .{
            .path = file_path,
            .rotation = rotation_interval,
            .retention = retention_count,
            .color = false,
        };
    }

    /// Returns an error-only sink configuration.
    ///
    /// Arguments:
    ///     file_path: Path to the error log file.
    ///
    /// Returns:
    ///     A SinkConfig configured to only capture error-level and above.
    pub fn errorOnly(file_path: []const u8) SinkConfig {
        return .{
            .path = file_path,
            .level = .err,
            .color = false,
        };
    }
};

fn parseSize(s: []const u8) ?u64 {
    var end: usize = 0;
    while (end < s.len and std.ascii.isDigit(s[end])) : (end += 1) {}

    if (end == 0) return null;

    const num = std.fmt.parseInt(u64, s[0..end], 10) catch return null;

    // Skip whitespace
    var unit_start = end;
    while (unit_start < s.len and std.ascii.isWhitespace(s[unit_start])) : (unit_start += 1) {}

    if (unit_start >= s.len) return num; // Default to bytes if no unit

    const unit = s[unit_start..];

    if (std.ascii.eqlIgnoreCase(unit, "B")) return num;
    if (std.ascii.eqlIgnoreCase(unit, "KB") or std.ascii.eqlIgnoreCase(unit, "K")) return num * 1024;
    if (std.ascii.eqlIgnoreCase(unit, "MB") or std.ascii.eqlIgnoreCase(unit, "M")) return num * 1024 * 1024;
    if (std.ascii.eqlIgnoreCase(unit, "GB") or std.ascii.eqlIgnoreCase(unit, "G")) return num * 1024 * 1024 * 1024;
    if (std.ascii.eqlIgnoreCase(unit, "TB") or std.ascii.eqlIgnoreCase(unit, "T")) return num * 1024 * 1024 * 1024 * 1024;

    return num;
}

pub const Sink = struct {
    /// Sink statistics for monitoring and diagnostics.
    pub const SinkStats = struct {
        total_written: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
        bytes_written: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
        write_errors: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
        flush_count: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
        rotation_count: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),

        /// Calculate throughput (bytes per second)
        pub fn throughputBytesPerSecond(self: *const SinkStats, elapsed_seconds: f64) f64 {
            if (elapsed_seconds == 0) return 0;
            const bytes = self.bytes_written.load(.monotonic);
            return @as(f64, @floatFromInt(bytes)) / elapsed_seconds;
        }

        /// Calculate error rate (0.0 - 1.0)
        pub fn errorRate(self: *const SinkStats) f64 {
            const total = self.total_written.load(.monotonic);
            const errors = self.write_errors.load(.monotonic);
            const total_ops = total + errors;
            if (total_ops == 0) return 0;
            return @as(f64, @floatFromInt(errors)) / @as(f64, @floatFromInt(total_ops));
        }

        /// Calculate average bytes per write
        pub fn avgBytesPerWrite(self: *const SinkStats) f64 {
            const total = self.total_written.load(.monotonic);
            if (total == 0) return 0;
            const bytes = self.bytes_written.load(.monotonic);
            return @as(f64, @floatFromInt(bytes)) / @as(f64, @floatFromInt(total));
        }
    };

    allocator: std.mem.Allocator,
    config: SinkConfig,
    file: ?std.fs.File = null,
    formatter: Formatter,
    rotation: ?Rotation = null,
    buffer: std.ArrayList(u8),
    mutex: std.Thread.Mutex = .{},
    enabled: bool = true,
    json_first_entry: bool = true, // Track if this is the first JSON entry for file output
    stats: SinkStats = .{},

    /// Callback invoked when a record is written to the sink.
    /// Parameters: (record_count: u64, bytes_written: u64)
    on_write: ?*const fn (u64, u64) void = null,

    /// Callback invoked when a flush operation completes.
    /// Parameters: (bytes_flushed: u64, duration_ns: u64)
    on_flush: ?*const fn (u64, u64) void = null,

    /// Callback invoked when a write error occurs.
    /// Parameters: (error_msg: []const u8, record_count: u64)
    on_error: ?*const fn ([]const u8, u64) void = null,

    /// Callback invoked when rotation occurs (if enabled).
    /// Parameters: (old_file: []const u8, new_file: []const u8)
    on_rotation: ?*const fn ([]const u8, []const u8) void = null,

    /// Callback invoked when sink is disabled/enabled.
    /// Parameters: (is_enabled: bool)
    on_state_change: ?*const fn (bool) void = null,

    pub fn init(allocator: std.mem.Allocator, config: SinkConfig) !*Sink {
        const sink = try allocator.create(Sink);
        sink.* = .{
            .allocator = allocator,
            .config = config,
            .formatter = Formatter.init(allocator),
            .buffer = .empty,
            .enabled = config.enabled,
            .json_first_entry = true,
        };
        errdefer sink.deinit();

        if (config.path) |path_pattern| {
            // Resolve dynamic path patterns (e.g. {date}, {YYYY-MM-DD})
            const path = try resolvePath(allocator, path_pattern);
            defer allocator.free(path);

            const dir = std.fs.path.dirname(path);
            if (dir) |d| {
                std.fs.cwd().makePath(d) catch {
                    // Failed to create directory - continue anyway
                };
            }

            // Use overwrite_mode to determine file truncation behavior
            sink.file = try std.fs.cwd().createFile(path, .{
                .read = true,
                .truncate = config.overwrite_mode,
            });

            // Write opening bracket for JSON array files
            if (config.json) {
                if (sink.file) |file| {
                    try file.writeAll("[\n");
                }
            }

            var size_limit = config.size_limit;
            if (size_limit == null and config.size_limit_str != null) {
                size_limit = parseSize(config.size_limit_str.?);
            }

            if (config.rotation != null or size_limit != null) {
                sink.rotation = try Rotation.init(
                    allocator,
                    path,
                    config.rotation,
                    size_limit,
                    config.retention,
                );
            }
        }

        return sink;
    }

    fn resolvePath(allocator: std.mem.Allocator, path_pattern: []const u8) ![]u8 {
        var buf: std.ArrayList(u8) = .empty;
        errdefer buf.deinit(allocator);
        const writer = buf.writer(allocator);

        const timestamp = std.time.milliTimestamp();
        const abs_timestamp = if (timestamp < 0) @as(u64, 0) else @as(u64, @intCast(timestamp));
        const seconds = abs_timestamp / 1000;

        const epoch = std.time.epoch.EpochSeconds{ .secs = seconds };
        const day_seconds = epoch.getDaySeconds();
        const year_day = epoch.getEpochDay();
        const yd = year_day.calculateYearDay();
        const month_day = yd.calculateMonthDay();

        const seconds_in_day = day_seconds.secs;
        const hours = seconds_in_day / 3600;
        const minutes = (seconds_in_day % 3600) / 60;
        const secs = seconds_in_day % 60;

        var i: usize = 0;
        while (i < path_pattern.len) {
            if (path_pattern[i] == '{') {
                const end = std.mem.indexOfScalarPos(u8, path_pattern, i + 1, '}') orelse {
                    try writer.writeByte(path_pattern[i]);
                    i += 1;
                    continue;
                };
                const tag = path_pattern[i + 1 .. end];

                if (std.mem.eql(u8, tag, "date")) {
                    try writer.print("{d:0>4}-{d:0>2}-{d:0>2}", .{ yd.year, month_day.month.numeric(), month_day.day_index + 1 });
                } else if (std.mem.eql(u8, tag, "time")) {
                    try writer.print("{d:0>2}-{d:0>2}-{d:0>2}", .{ hours, minutes, secs });
                } else {
                    try formatCustomTime(writer, tag, yd.year, month_day.month.numeric(), month_day.day_index + 1, hours, minutes, secs);
                }
                i = end + 1;
            } else {
                try writer.writeByte(path_pattern[i]);
                i += 1;
            }
        }
        return buf.toOwnedSlice(allocator);
    }

    fn formatCustomTime(writer: anytype, fmt: []const u8, year: i32, month: u8, day: u8, hour: u64, minute: u64, second: u64) !void {
        var i: usize = 0;
        while (i < fmt.len) {
            if (i + 4 <= fmt.len and std.mem.eql(u8, fmt[i .. i + 4], "YYYY")) {
                try writer.print("{d:0>4}", .{year});
                i += 4;
            } else if (i + 2 <= fmt.len and std.mem.eql(u8, fmt[i .. i + 2], "YY")) {
                try writer.print("{d:0>2}", .{@mod(year, 100)});
                i += 2;
            } else if (i + 2 <= fmt.len and std.mem.eql(u8, fmt[i .. i + 2], "MM")) {
                try writer.print("{d:0>2}", .{month});
                i += 2;
            } else if (i + 2 <= fmt.len and std.mem.eql(u8, fmt[i .. i + 2], "DD")) {
                try writer.print("{d:0>2}", .{day});
                i += 2;
            } else if (i + 2 <= fmt.len and std.mem.eql(u8, fmt[i .. i + 2], "HH")) {
                try writer.print("{d:0>2}", .{hour});
                i += 2;
            } else if (i + 2 <= fmt.len and std.mem.eql(u8, fmt[i .. i + 2], "mm")) {
                try writer.print("{d:0>2}", .{minute});
                i += 2;
            } else if (i + 2 <= fmt.len and std.mem.eql(u8, fmt[i .. i + 2], "ss")) {
                try writer.print("{d:0>2}", .{second});
                i += 2;
            } else {
                try writer.writeByte(fmt[i]);
                i += 1;
            }
        }
    }

    pub fn deinit(self: *Sink) void {
        self.flush() catch {};
        // Write closing bracket for JSON array files
        if (self.config.json and self.file != null) {
            if (self.file) |file| {
                file.writeAll("\n]") catch {};
            }
        }
        if (self.file) |f| f.close();
        if (self.rotation) |*r| r.deinit();
        self.buffer.deinit(self.allocator);
        self.formatter.deinit();
        self.allocator.destroy(self);
    }

    /// Sets the callback for write events.
    pub fn setWriteCallback(self: *Sink, callback: *const fn (u64, u64) void) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.on_write = callback;
    }

    /// Sets the callback for flush events.
    pub fn setFlushCallback(self: *Sink, callback: *const fn (u64, u64) void) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.on_flush = callback;
    }

    /// Sets the callback for error events.
    pub fn setErrorCallback(self: *Sink, callback: *const fn ([]const u8, u64) void) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.on_error = callback;
    }

    /// Sets the callback for rotation events.
    pub fn setRotationCallback(self: *Sink, callback: *const fn ([]const u8, []const u8) void) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.on_rotation = callback;
    }

    /// Sets the callback for state changes.
    pub fn setStateChangeCallback(self: *Sink, callback: *const fn (bool) void) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.on_state_change = callback;
    }

    /// Returns sink statistics.
    pub fn getStats(self: *Sink) SinkStats {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.stats;
    }

    pub fn write(self: *Sink, record: *const Record, global_config: anytype) !void {
        return self.writeWithAllocator(record, global_config, null);
    }

    pub fn writeWithAllocator(self: *Sink, record: *const Record, global_config: anytype, scratch_allocator: ?std.mem.Allocator) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (!self.enabled) return;

        // Check minimum level filtering
        if (self.config.level) |min_level| {
            if (record.level.priority() < min_level.priority()) {
                return;
            }
        }

        // Check maximum level filtering
        if (self.config.max_level) |max_level| {
            if (record.level.priority() > max_level.priority()) {
                return;
            }
        }

        // Apply per-sink filter configuration
        if (!self.applyFilterConfig(record)) {
            return;
        }

        // Check rotation
        if (self.rotation) |*rot| {
            if (self.file) |*f| {
                try rot.checkAndRotate(f);
            }
        }

        // Determine effective config for this sink
        // We need to create a new config struct that overrides specific fields
        var effective_config = global_config;

        // Override JSON setting
        if (self.config.json) {
            effective_config.json = true;
        }
        if (self.config.pretty_json) {
            effective_config.pretty_json = true;
        }

        // Override Color setting
        // If sink is a file, default color to false unless explicitly enabled
        if (self.config.color) |c| {
            effective_config.global_color_display = c;
        } else if (self.file != null) {
            // Default to no color for files
            effective_config.global_color_display = false;
        }

        // Format the message
        // Use scratch allocator if provided, otherwise use sink's allocator
        const fmt_allocator = scratch_allocator orelse self.allocator;

        // We need a temporary formatter if using scratch allocator
        var formatter = if (scratch_allocator) |_| Formatter.init(fmt_allocator) else self.formatter;
        // If we created a temp formatter, we don't need to deinit it as it doesn't hold resources,
        // but we should be aware of it.

        const formatted = if (effective_config.json)
            try formatter.formatJson(record, effective_config)
        else
            try formatter.format(record, effective_config);
        defer fmt_allocator.free(formatted);

        // Write to console or file
        if (self.file) |file| {
            if (global_config.global_file_storage) {
                // For JSON file output, add comma separator between entries
                const is_json_file = effective_config.json;

                if (self.config.async_write) {
                    // Buffered async write
                    if (is_json_file) {
                        if (!self.json_first_entry) {
                            try self.buffer.appendSlice(self.allocator, ",\n");
                        }
                        try self.buffer.appendSlice(self.allocator, formatted);
                        self.json_first_entry = false;
                    } else {
                        try self.buffer.appendSlice(self.allocator, formatted);
                        try self.buffer.append(self.allocator, '\n');
                    }
                    // Flush when buffer exceeds threshold
                    if (self.buffer.items.len >= self.config.buffer_size) {
                        try self.flush();
                    }
                } else {
                    // Direct synchronous write
                    if (is_json_file) {
                        if (!self.json_first_entry) {
                            try file.writeAll(",\n");
                        }
                        try file.writeAll(formatted);
                        self.json_first_entry = false;
                    } else {
                        try file.writeAll(formatted);
                        try file.writeAll("\n");
                    }
                }
            }
        } else {
            // Console output - direct write for best performance
            if (global_config.global_console_display) {
                const stdout_file = std.fs.File.stdout();
                try stdout_file.writeAll(formatted);
                try stdout_file.writeAll("\n");
            }
        }
    }

    pub fn writeRaw(self: *Sink, data: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (!self.enabled) return;

        if (self.file) |file| {
            if (self.config.async_write) {
                try self.buffer.appendSlice(self.allocator, data);
                try self.buffer.append(self.allocator, '\n');
                if (self.buffer.items.len >= self.config.buffer_size) {
                    try self.flush();
                }
            } else {
                try file.writeAll(data);
                try file.writeAll("\n");
            }
        } else {
            const stdout_file = std.fs.File.stdout();
            try stdout_file.writeAll(data);
            try stdout_file.writeAll("\n");
        }
    }

    pub fn flush(self: *Sink) !void {
        if (self.buffer.items.len == 0) return;
        if (self.file) |file| {
            try file.writeAll(self.buffer.items);
            self.buffer.clearRetainingCapacity();
        }
    }

    /// Applies per-sink filter configuration to determine if the record should be logged.
    /// Returns true if the record passes all filters, false otherwise.
    fn applyFilterConfig(self: *const Sink, record: *const Record) bool {
        const filter = self.config.filter;

        // Check include_modules - if set, only allow logs from these modules
        if (filter.include_modules) |modules| {
            if (modules.len > 0) {
                const module = record.module orelse return false;
                var found = false;
                for (modules) |m| {
                    if (std.mem.indexOf(u8, record.message, m) != null or
                        std.mem.startsWith(u8, module, m) or
                        std.mem.eql(u8, module, m))
                    {
                        found = true;
                        break;
                    }
                }
                if (!found) return false;
            }
        }

        // Check exclude_modules - if set, exclude logs from these modules
        if (filter.exclude_modules) |modules| {
            if (record.module) |module| {
                for (modules) |m| {
                    if (std.mem.startsWith(u8, module, m) or std.mem.eql(u8, module, m)) {
                        return false;
                    }
                }
            }
        }

        // Check include_messages - if set, only allow messages containing these substrings
        if (filter.include_messages) |messages| {
            if (messages.len > 0) {
                var found = false;
                for (messages) |m| {
                    if (std.mem.indexOf(u8, record.message, m) != null) {
                        found = true;
                        break;
                    }
                }
                if (!found) return false;
            }
        }

        // Check exclude_messages - if set, exclude messages containing these substrings
        if (filter.exclude_messages) |messages| {
            for (messages) |m| {
                if (std.mem.indexOf(u8, record.message, m) != null) {
                    return false;
                }
            }
        }

        return true;
    }
};
