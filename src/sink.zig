const std = @import("std");
const builtin = @import("builtin");
const Config = @import("config.zig").Config;
const Level = @import("level.zig").Level;
const Record = @import("record.zig").Record;
const Formatter = @import("formatter.zig").Formatter;
const Rotation = @import("rotation.zig").Rotation;
const Network = @import("network.zig");

// Helper writer for compression that adapts ArrayList to std.io.Writer interface
const SinkWriter = struct {
    writer: std.io.Writer,
    list: *std.ArrayList(u8),
    allocator: std.mem.Allocator,

    fn drain(writer: *std.io.Writer, iovecs: []const []const u8, len: usize) error{WriteFailed}!usize {
        const self: *SinkWriter = @fieldParentPtr("writer", writer);
        var total: usize = 0;
        for (iovecs[0..len]) |iov| {
            self.list.appendSlice(self.allocator, iov) catch return error.WriteFailed;
            total += iov.len;
        }
        return total;
    }

    const vtable = std.io.Writer.VTable{ .drain = drain };

    pub fn init(list: *std.ArrayList(u8), allocator: std.mem.Allocator, buffer: []u8) SinkWriter {
        return .{
            .writer = .{
                .vtable = &vtable,
                .buffer = buffer,
                .end = 0,
            },
            .list = list,
            .allocator = allocator,
        };
    }
};

/// Abstraction for system-level logging (Event Log on Windows, Syslog on POSIX).
const SystemLog = struct {
    const Platform = enum { windows, posix, other };
    const platform: Platform = if (builtin.os.tag == .windows) .windows else if (builtin.os.tag == .linux or builtin.os.tag == .macos or builtin.os.tag == .freebsd or builtin.os.tag == .openbsd or builtin.os.tag == .netbsd or builtin.os.tag == .dragonfly or builtin.os.tag == .solaris) .posix else .other;

    // Windows specific definitions
    const windows = if (platform == .windows) struct {
        // Define WINAPI calling convention based on architecture
        const WINAPI: std.builtin.CallingConvention = if (builtin.cpu.arch == .x86) .stdcall else .c;

        const HANDLE = std.os.windows.HANDLE;
        const LPCSTR = [*:0]const u8;
        const WORD = u16;
        const DWORD = u32;
        const PSID = ?*anyopaque;

        const EVENTLOG_SUCCESS: WORD = 0x0000;
        const EVENTLOG_ERROR_TYPE: WORD = 0x0001;
        const EVENTLOG_WARNING_TYPE: WORD = 0x0002;
        const EVENTLOG_INFORMATION_TYPE: WORD = 0x0004;

        extern "advapi32" fn RegisterEventSourceA(lpUNCServerName: ?LPCSTR, lpSourceName: LPCSTR) callconv(WINAPI) ?HANDLE;
        extern "advapi32" fn ReportEventA(hEventLog: HANDLE, wType: WORD, wCategory: WORD, dwEventID: DWORD, lpUserSid: PSID, wNumStrings: WORD, dwDataSize: DWORD, lpStrings: ?[*]const LPCSTR, lpRawData: ?*anyopaque) callconv(WINAPI) bool;
        extern "advapi32" fn DeregisterEventSource(hEventLog: HANDLE) callconv(WINAPI) bool;
    } else struct {};

    // POSIX specific definitions
    const posix = if (platform == .posix) struct {
        const LOG_PID = 0x01;
        const LOG_CONS = 0x02;
        const LOG_USER = 3 << 3;

        const LOG_ERR = 3;
        const LOG_WARNING = 4;
        const LOG_INFO = 6;

        extern "c" fn openlog(ident: ?[*:0]const u8, option: c_int, facility: c_int) void;
        extern "c" fn syslog(priority: c_int, format: [*:0]const u8, ...) void;
        extern "c" fn closelog() void;
    } else struct {};

    handle: ?*anyopaque = null,
    ident: ?[:0]const u8 = null,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, name: ?[]const u8) !SystemLog {
        var self = SystemLog{ .allocator = allocator };
        const safe_name = name orelse "Logly";

        switch (platform) {
            .windows => {
                const name_z = try allocator.dupeZ(u8, safe_name);
                errdefer allocator.free(name_z);
                self.ident = name_z;
                if (windows.RegisterEventSourceA(null, name_z)) |h| {
                    self.handle = @ptrCast(h);
                }
            },
            .posix => {
                const name_z = try allocator.dupeZ(u8, safe_name);
                self.ident = name_z;
                posix.openlog(name_z, posix.LOG_PID | posix.LOG_CONS, posix.LOG_USER);
            },
            .other => {},
        }
        return self;
    }

    pub fn deinit(self: *SystemLog) void {
        switch (platform) {
            .windows => {
                if (self.handle) |h| {
                    _ = windows.DeregisterEventSource(@ptrCast(h));
                }
                if (self.ident) |id| self.allocator.free(id);
            },
            .posix => {
                posix.closelog();
                if (self.ident) |id| self.allocator.free(id);
            },
            .other => {},
        }
    }

    pub fn log(self: *SystemLog, level: Level, message: []const u8) !void {
        switch (platform) {
            .windows => {
                if (self.handle) |h| {
                    const msg_z = try self.allocator.dupeZ(u8, message);
                    defer self.allocator.free(msg_z);
                    const strings = [_]windows.LPCSTR{msg_z};
                    const wType = switch (level) {
                        .err, .critical, .fail => windows.EVENTLOG_ERROR_TYPE,
                        .warning => windows.EVENTLOG_WARNING_TYPE,
                        else => windows.EVENTLOG_INFORMATION_TYPE,
                    };
                    _ = windows.ReportEventA(@ptrCast(h), wType, 0, 0, null, 1, 0, &strings, null);
                }
            },
            .posix => {
                const msg_z = try self.allocator.dupeZ(u8, message);
                defer self.allocator.free(msg_z);
                const priority = switch (level) {
                    .err, .critical, .fail => posix.LOG_ERR,
                    .warning => posix.LOG_WARNING,
                    else => posix.LOG_INFO,
                };
                posix.syslog(priority, "%s", msg_z);
            },
            .other => {
                // Fallback for baremetal or unsupported OS
            },
        }
    }
};

/// Configuration for a specific log sink.
///
/// Sinks are destinations where logs are written (e.g., console, file, network).
/// Each sink can have its own configuration, overriding global settings.
///
/// Supported Sink Types:
/// - Console (Standard Output)
/// - File (Text or JSON)
/// - Rotating File (Size or Time-based)
/// - Network (TCP/UDP)
/// - System Event Log (Windows Event Log / Syslog - *Experimental*)
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

    /// Enable system event log output (Windows Event Log / Syslog).
    event_log: bool = false,

    /// Custom color theme for this sink.
    theme: ?Formatter.Theme = null,

    /// Compression configuration for sink.
    /// Re-exports centralized config for convenience.
    pub const CompressionConfig = Config.CompressionConfig;

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

    /// Returns a network sink configuration.
    ///
    /// Arguments:
    ///     uri: Network URI (e.g., "tcp://127.0.0.1:8080", "udp://127.0.0.1:514").
    ///
    /// Returns:
    ///     A SinkConfig configured for network output.
    pub fn network(uri: []const u8) SinkConfig {
        return .{
            .path = uri,
            .color = false,
            .async_write = true, // Network I/O should default to async
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
    stream: ?std.net.Stream = null,
    udp_socket: ?std.posix.socket_t = null,
    udp_addr: ?std.net.Address = null,
    system_log: ?SystemLog = null,
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

        if (config.theme) |t| {
            sink.formatter.setTheme(t);
        }

        if (config.event_log) {
            sink.system_log = try SystemLog.init(allocator, config.name);
        } else if (config.path) |path_pattern| {
            // Check for network schemes
            if (std.mem.startsWith(u8, path_pattern, "tcp://")) {
                sink.stream = try Network.connectTcp(allocator, path_pattern);
            } else if (std.mem.startsWith(u8, path_pattern, "udp://")) {
                const result = try Network.createUdpSocket(allocator, path_pattern);
                sink.udp_socket = result.socket;
                sink.udp_addr = result.address;
            } else {
                // File path
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

        if (self.system_log) |*syslog| {
            syslog.deinit();
        }

        // Write closing bracket for JSON array files
        if (self.config.json and self.file != null) {
            if (self.file) |file| {
                file.writeAll("\n]") catch {};
            }
        }
        if (self.file) |f| f.close();
        if (self.stream) |s| s.close();
        if (self.udp_socket) |s| std.posix.close(s);

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
        } else if (self.file != null or self.stream != null or self.udp_socket != null) {
            // Default to no color for files/network
            effective_config.global_color_display = false;
        }

        // Use scratch allocator if provided, otherwise use sink's allocator
        const fmt_allocator = scratch_allocator orelse self.allocator;

        // We need a temporary formatter if using scratch allocator
        var formatter = if (scratch_allocator) |_| Formatter.init(fmt_allocator) else self.formatter;
        // If we created a temp formatter, we don't need to deinit it as it doesn't hold resources,
        // but we should be aware of it.

        // Check global switches
        if (self.file != null) {
            if (!global_config.global_file_storage) return;
        } else if (self.stream == null and self.udp_socket == null and self.system_log == null) {
            // Console
            if (!global_config.global_console_display) return;
        }

        // Handle SystemLog separately to preserve log level
        if (self.system_log) |*syslog| {
            // Clear buffer to ensure we only send the current message
            self.buffer.clearRetainingCapacity();
            const writer = self.buffer.writer(self.allocator);

            // Format message
            if (effective_config.json) {
                try formatter.formatJsonToWriter(writer, record, effective_config);
            } else {
                try formatter.formatToWriter(writer, record, effective_config);
            }

            // Send to system log
            if (self.buffer.items.len > 0) {
                try syslog.log(record.level, self.buffer.items);

                // Update stats
                _ = self.stats.total_written.fetchAdd(1, .monotonic);
                _ = self.stats.bytes_written.fetchAdd(self.buffer.items.len, .monotonic);

                if (self.on_write) |cb| {
                    cb(1, self.buffer.items.len);
                }
            }

            self.buffer.clearRetainingCapacity();
            return;
        }

        // Write to buffer
        const writer = self.buffer.writer(self.allocator);
        const is_file = self.file != null;
        const use_json_array = is_file and effective_config.json;

        if (use_json_array) {
            if (!self.json_first_entry) {
                try writer.writeAll(",\n");
            }
            try formatter.formatJsonToWriter(writer, record, effective_config);
            self.json_first_entry = false;
        } else {
            if (effective_config.json) {
                try formatter.formatJsonToWriter(writer, record, effective_config);
            } else {
                try formatter.formatToWriter(writer, record, effective_config);
            }
            try writer.writeByte('\n');
        }

        // Flush logic
        if (!self.config.async_write) {
            try self.flush();
        } else {
            if (self.buffer.items.len >= self.config.buffer_size) {
                try self.flush();
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
        } else if (self.stream) |stream| {
            try stream.writeAll(data);
            try stream.writeAll("\n");
        } else if (self.system_log) |*syslog| {
            // For raw writes, we assume INFO level if not specified, but Sink.write doesn't take a level.
            // We'll default to INFO.
            try syslog.log(.info, data);
        } else {
            const stdout_file = std.fs.File.stdout();
            try stdout_file.writeAll(data);
            try stdout_file.writeAll("\n");
        }
    }

    fn reconnect(self: *Sink) bool {
        if (self.stream) |s| s.close();
        self.stream = null;

        if (self.config.path) |uri| {
            if (std.mem.startsWith(u8, uri, "tcp://")) {
                self.stream = Network.connectTcp(self.allocator, uri) catch return false;
                return true;
            }
        }
        return false;
    }

    pub fn flush(self: *Sink) !void {
        if (self.buffer.items.len == 0) return;

        // Compression for Network Sinks
        var data_to_write: []const u8 = self.buffer.items;
        var compressed_data: ?[]u8 = null;

        if (self.config.compression.enabled and (self.stream != null or self.udp_socket != null)) {
            var list = try std.ArrayList(u8).initCapacity(self.allocator, 4096);
            errdefer list.deinit(self.allocator);

            var compress_buffer: [4096]u8 = undefined;
            var sink_writer_buffer: [4096]u8 = undefined;
            var sink_writer = SinkWriter.init(&list, self.allocator, &sink_writer_buffer);

            var compressor = std.compress.flate.Compress.init(&sink_writer.writer, &compress_buffer, .{});

            try compressor.writer.writeAll(self.buffer.items);
            try compressor.end();

            compressed_data = try list.toOwnedSlice(self.allocator);
            data_to_write = compressed_data.?;
        }
        defer if (compressed_data) |d| self.allocator.free(d);

        if (self.file) |file| {
            try file.writeAll(self.buffer.items);
        } else if (self.stream) |stream| {
            stream.writeAll(data_to_write) catch |err| {
                if (self.reconnect()) {
                    if (self.stream) |new_stream| {
                        try new_stream.writeAll(data_to_write);
                    } else {
                        return err;
                    }
                } else {
                    return err;
                }
            };
        } else if (self.udp_socket) |sock| {
            if (self.udp_addr) |addr| {
                _ = try std.posix.sendto(sock, data_to_write, 0, &addr.any, addr.getOsSockLen());
            }
        } else if (self.system_log) |*syslog| {
            const msg = self.buffer.items;
            if (msg.len > 0) {
                // Use info level as default for flushed buffers where we lost the record context
                try syslog.log(.info, msg);
            }
        } else {
            // Console
            const stdout_file = std.fs.File.stdout();
            try stdout_file.writeAll(self.buffer.items);
        }

        self.buffer.clearRetainingCapacity();
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
