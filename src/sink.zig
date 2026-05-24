//! Log Sink Module
//!
//! Defines output destinations for log records. Sinks handle the final
//! step of the logging pipeline: writing formatted output to storage.
//!
//! Sink Types:
//! - Console: Standard output/error stream
//! - File: Local file with optional rotation
//! - Network: TCP/UDP stream to remote server
//! - Buffered: Memory buffer with periodic flush
//!
//! Features:
//! - Automatic file rotation (size/time-based)
//! - Buffered writes for performance
//! - Async write support
//! - Compression integration
//! - Level-based routing (e.g., errors to separate file)
//!
//! Configuration:
//! - Path: File path or network URI
//! - Rotation: Interval and retention settings
//! - Buffer: Size and flush interval
//! - Format: JSON, text, or custom
//!
//! Thread Safety:
//! All sink operations are thread-safe with internal locking.

const std = @import("std");
const builtin = @import("builtin");
const Config = @import("config.zig").Config;
const Level = @import("level.zig").Level;
const Constants = @import("constants.zig");
const Record = @import("record.zig").Record;
const Formatter = @import("formatter.zig").Formatter;
const Rotation = @import("rotation.zig").Rotation;
const Network = @import("network.zig");
const Utils = @import("utils.zig");

/// File write mode.
pub const WriteMode = enum {
    append,
    overwrite,
    append_rotate,
};

fn writeStreamAll(stream: std.Io.net.Stream, data: []const u8) !void {
    var buffer: [Constants.BufferSizes.message]u8 = undefined;
    var writer = stream.writer(Utils.io(), &buffer);
    try writer.interface.writeAll(data);
    try writer.interface.flush();
}

/// Abstraction for system-level logging (Event Log on Windows, Syslog on POSIX).
const SystemLog = struct {
    const Platform = enum { windows, posix, other };
    const platform: Platform = if (builtin.os.tag == .windows) .windows else if (builtin.os.tag == .linux or builtin.os.tag == .macos or builtin.os.tag == .freebsd or builtin.os.tag == .openbsd or builtin.os.tag == .netbsd or builtin.os.tag == .dragonfly or builtin.os.tag == .solaris) .posix else .other;

    // Windows specific definitions
    const windows = if (platform == .windows) struct {
        // Define WINAPI calling convention based on architecture
        const WINAPI: std.builtin.CallingConvention = std.builtin.CallingConvention.winapi;

        const HANDLE = std.os.windows.HANDLE;
        const LPCSTR = [*:0]const u8;
        const WORD = u16;
        const DWORD = u32;
        const PSID = ?*anyopaque;

        pub const EVENTLOG_SUCCESS: WORD = @as(WORD, Constants.EventLogConstants.success);
        pub const EVENTLOG_ERROR_TYPE: WORD = @as(WORD, Constants.EventLogConstants.error_type);
        pub const EVENTLOG_WARNING_TYPE: WORD = @as(WORD, Constants.EventLogConstants.warning_type);
        pub const EVENTLOG_INFORMATION_TYPE: WORD = @as(WORD, Constants.EventLogConstants.information_type);

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

    const PosixImpl = if (platform == .posix) struct {
        fn logPosix(self: *SystemLog, level: Level, message: []const u8) !void {
            // Prepare zero-terminated message
            const msg_z: [:0]const u8 = try self.allocator.dupeZ(u8, message);
            defer self.allocator.free(msg_z);

            // Map level to syslog priority
            const priority: c_int = switch (level) {
                .err, .critical, .fail, .fatal => posix.LOG_ERR,
                .warning => posix.LOG_WARNING,
                .notice => posix.LOG_INFO, // Notice maps to INFO (syslog has LOG_NOTICE but we use LOG_INFO)
                else => posix.LOG_INFO,
            };

            // Call syslog with a fixed format string and the message as vararg
            const c_msg: [*:0]const u8 = msg_z;
            posix.syslog(priority, "%s", c_msg);
        }
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

    pub const create = init;

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

    pub const destroy = deinit;

    pub fn log(self: *SystemLog, level: Level, message: []const u8) !void {
        if (comptime platform == .windows) {
            return self.logWindows(level, message);
        } else if (comptime platform == .posix) {
            return PosixImpl.logPosix(self, level, message);
        } else {
            return self.logOther(level, message);
        }
    }

    pub const record = log;

    fn logWindows(self: *SystemLog, level: Level, message: []const u8) !void {
        if (self.handle) |h| {
            const msg_z = try self.allocator.dupeZ(u8, message);
            defer self.allocator.free(msg_z);
            const strings = [_]windows.LPCSTR{msg_z};
            const wType = switch (level) {
                .err, .critical, .fail, .fatal => windows.EVENTLOG_ERROR_TYPE,
                .warning => windows.EVENTLOG_WARNING_TYPE,
                .notice, .info, .success => windows.EVENTLOG_INFORMATION_TYPE,
                else => windows.EVENTLOG_INFORMATION_TYPE,
            };
            _ = windows.ReportEventA(@ptrCast(h), wType, 0, 0, null, 1, 0, &strings, null);
        }
    }

    fn logOther(self: *SystemLog, level: Level, message: []const u8) void {
        _ = self;
        _ = level;
        _ = message;
        // Fallback for baremetal or unsupported OS
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

    /// Custom naming format for rotated files (e.g., "{base}-{date}{ext}").
    /// Placeholders: base, ext, date, time, timestamp, iso
    naming_format: ?[]const u8 = null,

    /// Sink-specific log level. Overrides the global level if set.
    level: ?Level = null,

    /// Maximum log level for this sink (create level range filters).
    max_level: ?Level = null,

    /// Enable async writing with background buffering.
    async_write: bool = true,

    /// Buffer size for async writing in bytes.
    buffer_size: usize = Constants.BufferSizes.sink,

    /// Force JSON output for this sink.
    json: bool = false,

    /// Pretty print JSON output with indentation.
    pretty_json: bool = false,

    /// New formatting options.
    ndjson: bool = false,
    logfmt: bool = false,
    cef: bool = false,
    align_fields: bool = false,

    /// Enables cryptographic log chaining to detect tampering.
    tamper_evident: bool = false,

    /// Enables memory-mapped file logging for extremely high performance.
    mmap: bool = false,

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

    /// New File write mode.
    write_mode: WriteMode = .append,

    /// Whether this is an in-memory sink.
    is_memory: bool = false,

    /// Whether this is a stderr console sink.
    is_stderr: bool = false,

    /// Per-sink rate limiting (messages per second, 0 = unlimited).
    rate_limit_per_second: u32 = Constants.SinkDefaults.rate_limit_per_second,

    /// Capacity of the in-memory ring buffer.
    memory_capacity: usize = Constants.SinkDefaults.memory_ring_size,

    /// Compression settings for file sinks.
    compression: CompressionConfig = .{},

    /// Filter configuration for this sink.
    filter: FilterConfig = .{},

    /// Error handling for this sink.
    on_error: ErrorBehavior = .log_stderr,

    /// Maximum records to buffer before forcing a flush.
    max_buffer_records: usize = Constants.SinkDefaults.max_buffer_records,

    /// Flush interval in milliseconds.
    flush_interval_ms: u64 = Constants.SinkDefaults.flush_interval_ms,

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

    /// Returns a console sink configuration with default settings.
    pub fn console() SinkConfig {
        return .{
            .path = null, // Console output
            .color = null, // Auto-detect
            .async_write = true,
            .enabled = true,
        };
    }

    /// Returns a stderr console sink configuration.
    pub fn stderr() SinkConfig {
        return .{
            .path = null,
            .is_stderr = true,
            .color = null,
            .async_write = true,
            .enabled = true,
        };
    }

    /// Returns an in-memory ring buffer sink configuration.
    pub fn memory() SinkConfig {
        return .{
            .path = "memory",
            .is_memory = true,
            .color = false,
            .async_write = false, // Sync write by default to keep memory immediate
            .enabled = true,
        };
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

/// Log output destination (console, file, network, etc.).
///
/// Sinks handle the final step of the logging pipeline: writing formatted
/// output to storage or network destinations.
pub const Sink = struct {
    /// Sink statistics for monitoring and diagnostics.
    pub const SinkStats = struct {
        /// Total number of records written.
        total_written: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        /// Total bytes written to the sink.
        bytes_written: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        /// Number of write errors encountered.
        write_errors: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        /// Number of flush operations performed.
        flush_count: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        /// Number of file rotations performed.
        rotation_count: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),

        /// Get total number of records written.
        pub fn getTotalWritten(self: *const SinkStats) u64 {
            return Utils.atomicLoadU64(&self.total_written);
        }

        /// Get total bytes written.
        pub fn getBytesWritten(self: *const SinkStats) u64 {
            return Utils.atomicLoadU64(&self.bytes_written);
        }

        /// Get number of write errors.
        pub fn getWriteErrors(self: *const SinkStats) u64 {
            return Utils.atomicLoadU64(&self.write_errors);
        }

        /// Get number of flush operations.
        pub fn getFlushCount(self: *const SinkStats) u64 {
            return Utils.atomicLoadU64(&self.flush_count);
        }

        /// Get number of file rotations.
        pub fn getRotationCount(self: *const SinkStats) u64 {
            return Utils.atomicLoadU64(&self.rotation_count);
        }

        /// Check if any records have been written.
        pub fn hasWritten(self: *const SinkStats) bool {
            return self.getTotalWritten() > 0;
        }

        /// Check if any errors have occurred.
        pub fn hasErrors(self: *const SinkStats) bool {
            return self.getWriteErrors() > 0;
        }

        /// Check if any flushes have occurred.
        pub fn hasFlushed(self: *const SinkStats) bool {
            return self.getFlushCount() > 0;
        }

        /// Check if any rotations have occurred.
        pub fn hasRotated(self: *const SinkStats) bool {
            return self.getRotationCount() > 0;
        }

        /// Calculate throughput (bytes per second).
        pub fn throughputBytesPerSecond(self: *const SinkStats, elapsed_seconds: f64) f64 {
            return Utils.safeFloatDiv(
                @as(f64, @floatFromInt(self.getBytesWritten())),
                elapsed_seconds,
            );
        }

        /// Calculate records per second throughput.
        pub fn throughputRecordsPerSecond(self: *const SinkStats, elapsed_seconds: f64) f64 {
            return Utils.safeFloatDiv(
                @as(f64, @floatFromInt(self.getTotalWritten())),
                elapsed_seconds,
            );
        }

        /// Calculate error rate (0.0 - 1.0).
        pub fn errorRate(self: *const SinkStats) f64 {
            const total = self.getTotalWritten();
            const errors = self.getWriteErrors();
            return Utils.calculateErrorRate(errors, total + errors);
        }

        /// Calculate success rate (0.0 - 1.0).
        pub fn successRate(self: *const SinkStats) f64 {
            return 1.0 - self.errorRate();
        }

        /// Calculate average bytes per write.
        pub fn avgBytesPerWrite(self: *const SinkStats) f64 {
            return Utils.calculateAverage(
                self.getBytesWritten(),
                self.getTotalWritten(),
            );
        }

        /// Calculate average flushes per rotation.
        pub fn avgFlushesPerRotation(self: *const SinkStats) f64 {
            return Utils.calculateAverage(
                self.getFlushCount(),
                self.getRotationCount(),
            );
        }

        /// Reset all statistics to initial state.
        pub fn reset(self: *SinkStats) void {
            self.total_written.store(0, .monotonic);
            self.bytes_written.store(0, .monotonic);
            self.write_errors.store(0, .monotonic);
            self.flush_count.store(0, .monotonic);
            self.rotation_count.store(0, .monotonic);
        }
    };

    /// Memory allocator for sink operations.
    allocator: std.mem.Allocator,
    /// Sink configuration options.
    config: SinkConfig,
    /// File handle for file-based sinks.
    file: ?std.Io.File = null,
    /// Memory-mapped file handle for high-performance sinks.
    mmap_file: ?MmapFile = null,
    /// TCP stream for network sinks.
    stream: ?std.Io.net.Stream = null,
    /// UDP socket for network sinks.
    udp_socket: ?std.Io.net.Socket = null,
    /// UDP destination address.
    udp_addr: ?std.Io.net.IpAddress = null,
    /// System log handle (Windows Event Log / Syslog).
    system_log: ?SystemLog = null,
    /// Formatter for converting records to output.
    formatter: Formatter,
    /// Rotation handler for file-based sinks.
    rotation: ?Rotation = null,
    /// Internal write buffer.
    buffer: std.ArrayList(u8),
    /// Mutex for thread-safe operations.
    mutex: std.Io.Mutex = std.Io.Mutex.init,
    /// Whether the sink is enabled.
    enabled: bool = true,
    /// Track if this is the first JSON entry for file output.
    json_first_entry: bool = true,
    /// Number of records currently buffered and pending flush.
    buffered_records: usize = 0,
    /// Sink statistics.
    stats: SinkStats = .{},

    /// Last cryptographic chain hash.
    last_record_hash: ?[32]u8 = null,

    /// Number of consecutive write errors.
    consecutive_errors: u32 = 0,

    /// Rate limiter: last token refill timestamp (nanoseconds).
    rate_limit_last_refill_ns: i128 = 0,
    /// Rate limiter: current tokens.
    rate_limit_tokens: f64 = 0,

    /// Ring buffer for in-memory logging.
    memory_ring: ?[]?[]const u8 = null,
    /// Ring buffer write index.
    memory_ring_index: usize = 0,
    /// Ring buffer count of stored messages.
    memory_ring_count: usize = 0,

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

    /// Callback invoked when a cryptographic signature is generated for a log record.
    /// Parameters: (sink_name: []const u8, signature: []const u8)
    on_signature: ?*const fn ([]const u8, []const u8) void = null,

    /// Callback invoked when a memory-mapped sink grows in virtual memory size.
    /// Parameters: (sink_name: []const u8, old_size: u64, new_size: u64)
    on_mmap_resize: ?*const fn ([]const u8, u64, u64) void = null,

    /// Initializes a new sink with the provided configuration.
    ///
    /// Arguments:
    ///     allocator: Memory allocator for sink operations.
    ///     config: Sink configuration options.
    ///
    /// Returns:
    ///     A pointer to the initialized Sink or an error.
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

        if (config.is_memory) {
            sink.memory_ring = try allocator.alloc(?[]const u8, config.memory_capacity);
            @memset(sink.memory_ring.?, null);
            sink.memory_ring_index = 0;
            sink.memory_ring_count = 0;
        } else if (config.event_log) {
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
                    std.Io.Dir.cwd().createDirPath(Utils.io(), d) catch {
                        // Failed to create directory - continue anyway
                    };
                }

                // Use overwrite_mode to determine file truncation behavior
                sink.file = try std.Io.Dir.cwd().createFile(Utils.io(), path, .{
                    .read = true,
                    .truncate = config.overwrite_mode or (config.write_mode == .overwrite),
                });

                if (config.mmap) {
                    sink.mmap_file = try MmapFile.init(allocator, sink.file.?, 1024 * 1024);
                }

                // Write opening bracket for JSON array files
                if (config.json) {
                    if (config.mmap) {
                        if (sink.mmap_file) |*mmap_f| {
                            try mmap_f.write("[\n");
                        }
                    } else if (sink.file) |file| {
                        try file.writeStreamingAll(Utils.io(), "[\n");
                    }
                }

                var size_limit = config.size_limit;
                if (size_limit == null and config.size_limit_str != null) {
                    size_limit = Utils.parseSize(config.size_limit_str.?);
                }

                if (config.rotation != null or size_limit != null) {
                    sink.rotation = try Rotation.init(
                        allocator,
                        path,
                        config.rotation,
                        size_limit,
                        config.retention,
                    );

                    if (config.compression.enabled) {
                        try sink.rotation.?.withCompression(config.compression);
                    }
                    if (config.naming_format) |fmt| {
                        try sink.rotation.?.withNamingFormat(fmt);
                    }
                }
            }
        }

        return sink;
    }

    /// Alias for init().
    pub const create = init;

    fn resolvePath(allocator: std.mem.Allocator, path_pattern: []const u8) ![]u8 {
        var buf = std.Io.Writer.Allocating.init(allocator);
        errdefer buf.deinit();
        const writer = &buf.writer;

        const now_ms = Utils.currentMillis();
        const tc = Utils.fromMilliTimestamp(now_ms);
        const millis = @mod(if (now_ms < 0) 0 else @as(u64, @intCast(now_ms)), Constants.TimeConstants.ms_per_second);

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
                    try Utils.write4Digits(writer, tc.year);
                    try writer.writeByte('-');
                    try Utils.write2Digits(writer, tc.month);
                    try writer.writeByte('-');
                    try Utils.write2Digits(writer, tc.day);
                } else if (std.mem.eql(u8, tag, "time")) {
                    try Utils.write2Digits(writer, tc.hour);
                    try writer.writeByte('-');
                    try Utils.write2Digits(writer, tc.minute);
                    try writer.writeByte('-');
                    try Utils.write2Digits(writer, tc.second);
                } else {
                    try Utils.formatDatePattern(writer, tag, tc.year, tc.month, tc.day, tc.hour, tc.minute, tc.second, millis);
                }
                i = end + 1;
            } else {
                try writer.writeByte(path_pattern[i]);
                i += 1;
            }
        }
        return buf.toOwnedSlice();
    }

    /// Deinitializes the sink and releases resources.
    /// Flushes any pending data before closing.
    pub fn deinit(self: *Sink) void {
        self.flush() catch {};

        if (self.system_log) |*syslog| {
            syslog.deinit();
        }

        // Write closing bracket for JSON array files
        if (self.config.json and self.file != null) {
            if (self.config.mmap) {
                if (self.mmap_file) |*mmap_f| {
                    mmap_f.write("\n]") catch {};
                }
            } else if (self.file) |file| {
                file.writeStreamingAll(Utils.io(), "\n]") catch {};
            }
        }
        if (self.config.mmap) {
            if (self.mmap_file) |*mmap_f| {
                mmap_f.deinit();
            }
            self.mmap_file = null;
        }
        if (self.file) |f| f.close(Utils.io());
        if (self.stream) |s| s.close(Utils.io());
        if (self.udp_socket) |s| s.close(Utils.io());

        if (self.rotation) |*r| r.deinit();
        if (self.memory_ring) |ring| {
            for (ring) |msg| {
                if (msg) |m| self.allocator.free(m);
            }
            self.allocator.free(ring);
        }
        self.buffer.deinit(self.allocator);
        self.formatter.deinit();
        self.allocator.destroy(self);
    }

    /// Alias for deinit().
    pub const destroy = deinit;

    /// Sets the callback for write events.
    pub fn setWriteCallback(self: *Sink, callback: *const fn (u64, u64) void) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        self.on_write = callback;
    }

    /// Alias for setWriteCallback
    pub const onWrite = setWriteCallback;

    /// Sets the callback for flush events.
    pub fn setFlushCallback(self: *Sink, callback: *const fn (u64, u64) void) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        self.on_flush = callback;
    }

    /// Alias for setFlushCallback
    pub const onFlush = setFlushCallback;

    /// Sets the callback for error events.
    pub fn setErrorCallback(self: *Sink, callback: *const fn ([]const u8, u64) void) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        self.on_error = callback;
    }

    /// Alias for setErrorCallback
    pub const onError = setErrorCallback;

    /// Sets the callback for rotation events.
    pub fn setRotationCallback(self: *Sink, callback: *const fn ([]const u8, []const u8) void) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        self.on_rotation = callback;
    }

    /// Alias for setRotationCallback
    pub const onRotation = setRotationCallback;

    /// Sets the callback for state changes.
    pub fn setStateChangeCallback(self: *Sink, callback: *const fn (bool) void) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        self.on_state_change = callback;
    }

    /// Alias for setStateChangeCallback
    pub const onStateChange = setStateChangeCallback;

    /// Sets the callback for cryptographic signature generation.
    pub fn setSignatureCallback(self: *Sink, callback: *const fn ([]const u8, []const u8) void) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        self.on_signature = callback;
    }

    /// Alias for setSignatureCallback
    pub const onSignature = setSignatureCallback;

    /// Sets the callback for memory-mapped sink resizes.
    pub fn setMmapResizeCallback(self: *Sink, callback: *const fn ([]const u8, u64, u64) void) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        self.on_mmap_resize = callback;
    }

    /// Alias for setMmapResizeCallback
    pub const onMmapResize = setMmapResizeCallback;

    /// Returns sink statistics.
    pub fn getStats(self: *Sink) SinkStats {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());

        return self.stats;
    }

    /// Alias for getStats() - shorter form.
    pub const statistics = getStats;
    pub const stats_ = getStats;

    /// Clears the internal buffer.
    pub fn clearBuffer(self: *Sink) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        self.buffer.clearRetainingCapacity();
    }

    /// Alias for clearBuffer() - shorter form.
    pub const clear = clearBuffer;

    /// Synchronizes buffer to storage (calls flush).
    pub const sync = flush;

    /// Alias for deinit() - alternative name.
    pub const close = deinit;

    /// Returns true if sink is enabled.
    pub fn isEnabled(self: *Sink) bool {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        return self.enabled;
    }

    /// Alias for isEnabled
    pub const is_enabled = isEnabled;

    /// Returns true if the sink is healthy (errors have not exceeded the unhealthy threshold).
    pub fn isHealthy(self: *Sink) bool {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        return self.consecutive_errors < Constants.SinkDefaults.unhealthy_error_threshold;
    }

    /// Alias for isHealthy
    pub const is_healthy = isHealthy;

    /// Retrieves in-memory logged messages in chronological order.
    /// The caller owns the returned slice and all the duplicated string elements.
    pub fn getMemoryMessages(self: *Sink, allocator: std.mem.Allocator) ![][]const u8 {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());

        const ring = self.memory_ring orelse return error.NotAMemorySink;
        const count = self.memory_ring_count;
        var list: std.ArrayListUnmanaged([]const u8) = .empty;
        errdefer {
            for (list.items) |msg| {
                allocator.free(msg);
            }
            list.deinit(allocator);
        }

        try list.ensureTotalCapacity(allocator, count);

        if (count < ring.len) {
            var i: usize = 0;
            while (i < count) : (i += 1) {
                if (ring[i]) |msg| {
                    const dup = try allocator.dupe(u8, msg);
                    list.appendAssumeCapacity(dup);
                }
            }
        } else {
            var i: usize = 0;
            while (i < ring.len) : (i += 1) {
                const idx = (self.memory_ring_index + i) % ring.len;
                if (ring[idx]) |msg| {
                    const dup = try allocator.dupe(u8, msg);
                    list.appendAssumeCapacity(dup);
                }
            }
        }

        return try list.toOwnedSlice(allocator);
    }

    /// Alias for getMemoryMessages
    pub const get_memory_messages = getMemoryMessages;

    /// Enables the sink.
    pub fn enable(self: *Sink) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        self.enabled = true;
        if (self.on_state_change) |cb| cb(true);
    }

    /// Disables the sink.
    pub fn disable(self: *Sink) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        self.enabled = false;
        if (self.on_state_change) |cb| cb(false);
    }

    /// Returns true if async writing is enabled for this sink.
    pub fn isAsyncEnabled(self: *Sink) bool {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        return self.config.async_write;
    }

    /// Alias for isAsyncEnabled
    pub const asyncEnabled = isAsyncEnabled;

    /// Enables async writing for this sink.
    pub fn enableAsync(self: *Sink) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        self.config.async_write = true;
    }

    /// Disables async writing for this sink (forces immediate flush).
    pub fn disableAsync(self: *Sink) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        self.config.async_write = false;
        // Flush any pending data when disabling async
        self.flush() catch {};
    }

    /// Manually flushes the sink buffer.
    /// Thread-safe: Uses mutex for concurrent access protection.
    pub fn flushNow(self: *Sink) !void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        try self.flush();
    }

    /// Alias for flushNow
    pub const flushImmediate = flushNow;

    /// Returns the sink's name, if set.
    pub fn getName(self: *Sink) ?[]const u8 {
        return self.config.name;
    }

    /// Alias for getName() - shorter form.
    pub const name = getName;

    /// Writes a log record to the sink.
    ///
    /// Arguments:
    ///     record: The log record to write.
    ///     global_config: Global configuration to merge with sink config.
    pub fn write(self: *Sink, record: *const Record, global_config: anytype) !void {
        return self.writeWithAllocator(record, global_config, null);
    }

    /// Writes a log record using a specific allocator.
    ///
    /// Arguments:
    ///     record: The log record to write.
    ///     global_config: Global configuration.
    ///     scratch_allocator: Optional allocator for temporary formatting.
    pub fn writeWithAllocator(self: *Sink, record: *const Record, global_config: anytype, scratch_allocator: ?std.mem.Allocator) !void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());

        if (!self.enabled) return;

        // Rate limiting
        if (self.config.rate_limit_per_second > 0) {
            const now = Utils.currentNanos();
            if (self.rate_limit_last_refill_ns == 0) {
                self.rate_limit_last_refill_ns = now;
                self.rate_limit_tokens = @floatFromInt(self.config.rate_limit_per_second);
            } else {
                const elapsed_ns = now - self.rate_limit_last_refill_ns;
                const elapsed_secs = @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000_000.0;
                const new_tokens = elapsed_secs * @as(f64, @floatFromInt(self.config.rate_limit_per_second));
                if (new_tokens > 0) {
                    self.rate_limit_tokens = @min(@as(f64, @floatFromInt(self.config.rate_limit_per_second)), self.rate_limit_tokens + new_tokens);
                    self.rate_limit_last_refill_ns = now;
                }
            }

            if (self.rate_limit_tokens < 1.0) {
                // Rate limit exceeded - silent drop
                return;
            }
            self.rate_limit_tokens -= 1.0;
        }

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
        if (self.config.ndjson) {
            effective_config.ndjson = true;
        }
        if (self.config.logfmt) {
            effective_config.logfmt = true;
        }
        if (self.config.cef) {
            effective_config.cef = true;
        }
        if (self.config.align_fields) {
            effective_config.align_fields = true;
        }
        if (self.config.tamper_evident) {
            effective_config.tamper_evident = true;
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

        // Check global switches - early exit if globally disabled
        if (self.file != null) {
            // File sink - check global file storage setting
            if (!global_config.global_file_storage) return;
        } else if (self.stream == null and self.udp_socket == null and self.system_log == null) {
            // Console sink - check global console display setting
            if (!global_config.global_console_display) return;
        }
        // Network and system log sinks are not affected by global console/file settings

        // Handle SystemLog separately to preserve log level
        if (self.system_log) |*syslog| {
            // Clear buffer to ensure we only send the current message
            self.buffer.clearRetainingCapacity();
            var buffer_writer = std.Io.Writer.Allocating.fromArrayList(self.allocator, &self.buffer);
            errdefer self.buffer = buffer_writer.toArrayList();
            const writer = &buffer_writer.writer;

            // Format message
            if (effective_config.ndjson) {
                try formatter.formatJsonToWriter(writer, record, effective_config);
            } else if (effective_config.logfmt) {
                try formatter.formatLogfmtToWriter(writer, record, effective_config);
            } else if (effective_config.cef) {
                try formatter.formatCefToWriter(writer, record, effective_config);
            } else if (effective_config.json) {
                try formatter.formatJsonToWriter(writer, record, effective_config);
            } else {
                try formatter.formatToWriter(writer, record, effective_config);
            }
            const written = buffer_writer.written();

            // Send to system log
            if (written.len > 0) {
                try syslog.log(record.level, written);

                // Update stats
                _ = self.stats.total_written.fetchAdd(1, .monotonic);
                _ = self.stats.bytes_written.fetchAdd(written.len, .monotonic);

                if (self.on_write) |cb| {
                    cb(1, written.len);
                }
            }

            self.buffer = buffer_writer.toArrayList();
            self.buffer.clearRetainingCapacity();
            return;
        }

        // Write to buffer
        const start_idx = self.buffer.items.len;
        var buffer_writer = std.Io.Writer.Allocating.fromArrayList(self.allocator, &self.buffer);
        errdefer self.buffer = buffer_writer.toArrayList();
        const writer = &buffer_writer.writer;
        const is_file = self.file != null;
        const use_json_array = is_file and effective_config.json and !effective_config.ndjson;

        if (use_json_array) {
            if (!self.json_first_entry) {
                try writer.writeAll(",\n");
            }
            try formatter.formatJsonToWriter(writer, record, effective_config);
            self.json_first_entry = false;
        } else {
            if (effective_config.ndjson) {
                try formatter.formatJsonToWriter(writer, record, effective_config);
            } else if (effective_config.logfmt) {
                try formatter.formatLogfmtToWriter(writer, record, effective_config);
            } else if (effective_config.cef) {
                try formatter.formatCefToWriter(writer, record, effective_config);
            } else if (effective_config.json) {
                try formatter.formatJsonToWriter(writer, record, effective_config);
            } else {
                try formatter.formatToWriter(writer, record, effective_config);
            }
        }
        self.buffer = buffer_writer.toArrayList();

        // Apply Tamper-Evident Hashing
        if (effective_config.tamper_evident) {
            const newly_written = self.buffer.items[start_idx..];
            self.last_record_hash = Utils.computeChainHash(self.last_record_hash, newly_written);

            const hash_hex = std.fmt.bytesToHex(self.last_record_hash.?, .lower);

            if (self.on_signature) |cb| {
                cb(self.config.name orelse "unnamed_sink", &hash_hex);
            }

            if (use_json_array or effective_config.ndjson or effective_config.json) {
                // For JSON, we inject it as a metadata field at the end before the closing brace if possible
                // As a simpler robust approach, we just append it as a raw string comment or metadata block
                try self.buffer.appendSlice(self.allocator, " /* SIG:");
                try self.buffer.appendSlice(self.allocator, &hash_hex);
                try self.buffer.appendSlice(self.allocator, " */");
            } else {
                try self.buffer.appendSlice(self.allocator, " [SIG:");
                try self.buffer.appendSlice(self.allocator, &hash_hex);
                try self.buffer.append(self.allocator, ']');
            }
        }

        if (!use_json_array) {
            try self.buffer.append(self.allocator, '\n');
        }

        self.buffered_records += 1;

        // Flush logic
        if (!self.config.async_write) {
            try self.flush();
        } else {
            if (self.buffer.items.len >= self.config.buffer_size) {
                try self.flush();
            }
        }
    }

    /// Alias for writeWithAllocator
    pub const writeWithAlloc = writeWithAllocator;

    /// Writes raw data directly to the sink bypassing formatting.
    ///
    /// Arguments:
    ///     data: The raw string data to write.
    pub fn writeRaw(self: *Sink, data: []const u8) !void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());

        if (!self.enabled) return;

        const bytes_with_newline = data.len + 1;

        if (self.file) |file| {
            if (self.config.async_write) {
                try self.buffer.appendSlice(self.allocator, data);
                try self.buffer.append(self.allocator, '\n');
                self.buffered_records += 1;
                if (self.buffer.items.len >= self.config.buffer_size) {
                    try self.flush();
                }
            } else {
                if (self.config.mmap) {
                    if (self.mmap_file) |*mmap_f| {
                        const old_capacity = mmap_f.capacity;
                        mmap_f.write(data) catch |err| {
                            try self.handleWriteError(err, 1);
                            return;
                        };
                        mmap_f.write("\n") catch |err| {
                            try self.handleWriteError(err, 1);
                            return;
                        };
                        if (mmap_f.capacity > old_capacity) {
                            if (self.on_mmap_resize) |cb| {
                                cb(self.config.name orelse "unnamed_sink", old_capacity, mmap_f.capacity);
                            }
                        }
                    }
                } else {
                    file.writeStreamingAll(Utils.io(), data) catch |err| {
                        try self.handleWriteError(err, 1);
                        return;
                    };
                    file.writeStreamingAll(Utils.io(), "\n") catch |err| {
                        try self.handleWriteError(err, 1);
                        return;
                    };
                }

                _ = self.stats.total_written.fetchAdd(1, .monotonic);
                _ = self.stats.bytes_written.fetchAdd(bytes_with_newline, .monotonic);
                if (self.on_write) |cb| {
                    cb(1, bytes_with_newline);
                }
            }
        } else if (self.stream) |stream| {
            writeStreamAll(stream, data) catch |err| {
                try self.handleWriteError(err, 1);
                return;
            };
            writeStreamAll(stream, "\n") catch |err| {
                try self.handleWriteError(err, 1);
                return;
            };

            _ = self.stats.total_written.fetchAdd(1, .monotonic);
            _ = self.stats.bytes_written.fetchAdd(bytes_with_newline, .monotonic);
            if (self.on_write) |cb| {
                cb(1, bytes_with_newline);
            }
        } else if (self.system_log) |*syslog| {
            // For raw writes, we assume INFO level if not specified, but Sink.write doesn't take a level.
            // We'll default to INFO.
            syslog.log(.info, data) catch |err| {
                try self.handleWriteError(err, 1);
                return;
            };

            _ = self.stats.total_written.fetchAdd(1, .monotonic);
            _ = self.stats.bytes_written.fetchAdd(data.len, .monotonic);
            if (self.on_write) |cb| {
                cb(1, data.len);
            }
        } else {
            const stdout_file = std.Io.File.stdout();
            stdout_file.writeStreamingAll(Utils.io(), data) catch |err| {
                try self.handleWriteError(err, 1);
                return;
            };
            stdout_file.writeStreamingAll(Utils.io(), "\n") catch |err| {
                try self.handleWriteError(err, 1);
                return;
            };

            _ = self.stats.total_written.fetchAdd(1, .monotonic);
            _ = self.stats.bytes_written.fetchAdd(bytes_with_newline, .monotonic);
            if (self.on_write) |cb| {
                cb(1, bytes_with_newline);
            }
        }
    }

    fn reconnect(self: *Sink) bool {
        if (self.stream) |s| s.close(Utils.io());
        self.stream = null;

        if (self.config.path) |uri| {
            if (std.mem.startsWith(u8, uri, "tcp://")) {
                const max_retries = Constants.TimeDefaults.max_retries;
                const retry_sleep = std.Io.Duration.fromMilliseconds(Constants.TimeDefaults.retry_delay_ms);

                var attempt: u32 = 0;
                while (attempt <= max_retries) : (attempt += 1) {
                    self.stream = Network.connectTcp(self.allocator, uri) catch {
                        if (attempt < max_retries) {
                            Utils.io().sleep(retry_sleep, .awake) catch {};
                        }
                        continue;
                    };
                    return true;
                }
            }
        }
        return false;
    }

    fn handleWriteError(self: *Sink, err: anyerror, record_count: u64) !void {
        _ = self.stats.write_errors.fetchAdd(1, .monotonic);
        self.consecutive_errors += 1;

        if (self.on_error) |callback| {
            callback(@errorName(err), record_count);
        }

        switch (self.config.on_error) {
            .silent => {},
            .log_stderr => {
                const sink_name = self.config.name orelse "unnamed";
                std.debug.print("[logly:sink:{s}] write error: {s}\n", .{ sink_name, @errorName(err) });
            },
            .disable_sink => {
                self.enabled = false;
                if (self.on_state_change) |callback| {
                    callback(false);
                }
            },
            .propagate => return err,
        }
    }

    /// Flushes the internal buffer to storage.
    pub fn flush(self: *Sink) !void {
        if (self.buffer.items.len == 0) return;

        const start_ns = Utils.currentNanos();
        const buffered_records = if (self.buffered_records == 0) @as(u64, 1) else @as(u64, @intCast(self.buffered_records));

        // Memory sink handling
        if (self.memory_ring) |ring| {
            var it = std.mem.splitScalar(u8, self.buffer.items, '\n');
            while (it.next()) |line| {
                if (line.len == 0) continue;
                var trimmed = line;
                if (std.mem.endsWith(u8, trimmed, ",")) {
                    trimmed = trimmed[0 .. trimmed.len - 1];
                }
                trimmed = std.mem.trim(u8, trimmed, " \r\t");
                if (trimmed.len == 0) continue;

                const idx = self.memory_ring_index;
                if (ring[idx]) |old| {
                    self.allocator.free(old);
                }
                ring[idx] = try self.allocator.dupe(u8, trimmed);
                self.memory_ring_index = (idx + 1) % ring.len;
                if (self.memory_ring_count < ring.len) {
                    self.memory_ring_count += 1;
                }
            }

            const buffered_records_atomic: Constants.AtomicUnsigned = @intCast(@min(
                buffered_records,
                @as(u64, std.math.maxInt(Constants.AtomicUnsigned)),
            ));
            _ = self.stats.total_written.fetchAdd(buffered_records_atomic, .monotonic);
            _ = self.stats.bytes_written.fetchAdd(self.buffer.items.len, .monotonic);
            _ = self.stats.flush_count.fetchAdd(1, .monotonic);
            self.consecutive_errors = 0;

            if (self.on_write) |callback| {
                callback(buffered_records, self.buffer.items.len);
            }

            self.buffer.clearRetainingCapacity();
            self.buffered_records = 0;
            return;
        }

        // Compression for Network Sinks
        var data_to_write: []const u8 = self.buffer.items;
        var compressed_data: ?[]u8 = null;

        if (self.config.compression.enabled and (self.stream != null or self.udp_socket != null)) {
            var list = try std.Io.Writer.Allocating.initCapacity(self.allocator, Constants.BufferSizes.message);
            errdefer list.deinit();

            var compress_buffer: [Constants.BufferSizes.message]u8 = undefined;

            var compressor = try std.compress.flate.Compress.init(&list.writer, &compress_buffer, .raw, .default);

            try compressor.writer.writeAll(self.buffer.items);
            try compressor.finish();

            compressed_data = try list.toOwnedSlice();
            data_to_write = compressed_data.?;
        }
        defer if (compressed_data) |d| self.allocator.free(d);

        if (self.file) |file| {
            if (self.config.mmap) {
                if (self.mmap_file) |*mmap_f| {
                    const old_capacity = mmap_f.capacity;
                    mmap_f.write(self.buffer.items) catch |err| {
                        try self.handleWriteError(err, buffered_records);
                        self.buffer.clearRetainingCapacity();
                        self.buffered_records = 0;
                        return;
                    };
                    if (mmap_f.capacity > old_capacity) {
                        if (self.on_mmap_resize) |cb| {
                            cb(self.config.name orelse "unnamed_sink", old_capacity, mmap_f.capacity);
                        }
                    }
                    mmap_f.flush();
                }
            } else {
                file.writeStreamingAll(Utils.io(), self.buffer.items) catch |err| {
                    try self.handleWriteError(err, buffered_records);
                    self.buffer.clearRetainingCapacity();
                    self.buffered_records = 0;
                    return;
                };
            }
        } else if (self.stream) |stream| {
            writeStreamAll(stream, data_to_write) catch |err| {
                if (self.reconnect()) {
                    if (self.stream) |new_stream| {
                        writeStreamAll(new_stream, data_to_write) catch |retry_err| {
                            try self.handleWriteError(retry_err, buffered_records);
                            self.buffer.clearRetainingCapacity();
                            self.buffered_records = 0;
                            return;
                        };
                    } else {
                        try self.handleWriteError(err, buffered_records);
                        self.buffer.clearRetainingCapacity();
                        self.buffered_records = 0;
                        return;
                    }
                } else {
                    try self.handleWriteError(err, buffered_records);
                    self.buffer.clearRetainingCapacity();
                    self.buffered_records = 0;
                    return;
                }
            };
        } else if (self.udp_socket) |sock| {
            if (self.udp_addr) |addr| {
                sock.send(Utils.io(), &addr, data_to_write) catch |err| {
                    try self.handleWriteError(err, buffered_records);
                    self.buffer.clearRetainingCapacity();
                    self.buffered_records = 0;
                    return;
                };
            }
        } else if (self.system_log) |*syslog| {
            const msg = self.buffer.items;
            if (msg.len > 0) {
                // Use info level as default for flushed buffers where we lost the record context
                syslog.log(.info, msg) catch |err| {
                    try self.handleWriteError(err, buffered_records);
                    self.buffer.clearRetainingCapacity();
                    self.buffered_records = 0;
                    return;
                };
            }
        } else {
            // Console
            const stdout_file = std.Io.File.stdout();
            stdout_file.writeStreamingAll(Utils.io(), self.buffer.items) catch |err| {
                try self.handleWriteError(err, buffered_records);
                self.buffer.clearRetainingCapacity();
                self.buffered_records = 0;
                return;
            };
        }

        const bytes_flushed = if (self.file != null) self.buffer.items.len else data_to_write.len;
        const end_ns = Utils.currentNanos();
        const duration_ns: u64 = if (end_ns > start_ns) @as(u64, @intCast(end_ns - start_ns)) else 0;
        const buffered_records_atomic: Constants.AtomicUnsigned = @intCast(@min(
            buffered_records,
            @as(u64, std.math.maxInt(Constants.AtomicUnsigned)),
        ));

        _ = self.stats.total_written.fetchAdd(buffered_records_atomic, .monotonic);
        _ = self.stats.bytes_written.fetchAdd(bytes_flushed, .monotonic);
        _ = self.stats.flush_count.fetchAdd(1, .monotonic);

        if (self.on_write) |callback| {
            callback(buffered_records, bytes_flushed);
        }
        if (self.on_flush) |callback| {
            callback(bytes_flushed, duration_ns);
        }

        self.consecutive_errors = 0;
        self.buffer.clearRetainingCapacity();
        self.buffered_records = 0;
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
                    if (std.mem.startsWith(u8, module, m) or
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

test "sink parseSize" {
    try std.testing.expectEqual(@as(?u64, Constants.SizeConstants.bytes_per_kb), Utils.parseSize("1024"));
    try std.testing.expectEqual(@as(?u64, Constants.SizeConstants.bytes_per_kb), Utils.parseSize("1KB"));
    try std.testing.expectEqual(@as(?u64, Constants.SizeConstants.bytes_per_mb), Utils.parseSize("1MB"));
    try std.testing.expectEqual(@as(?u64, 10 * Constants.SizeConstants.bytes_per_mb), Utils.parseSize("10M"));
    try std.testing.expectEqual(@as(?u64, Constants.SizeConstants.bytes_per_gb), Utils.parseSize("1GB"));
    try std.testing.expectEqual(@as(?u64, 5 * Constants.SizeConstants.bytes_per_gb), Utils.parseSize("5G"));
}

test "sink filtering" {
    const allocator = std.testing.allocator;
    var sink_cfg = SinkConfig.default();
    sink_cfg.filter = .{
        .include_modules = &[_][]const u8{"auth"},
        .exclude_messages = &[_][]const u8{"password"},
    };

    const sink = try Sink.init(allocator, sink_cfg);
    defer sink.deinit();

    var record = Record.init(allocator, .info, "user logged in");
    defer record.deinit();
    record.module = "auth.service";
    record.timestamp = 0;

    try std.testing.expect(sink.applyFilterConfig(&record));

    record.module = "database";
    try std.testing.expect(!sink.applyFilterConfig(&record));

    record.module = "auth";
    record.message = "inputted password was wrong";
    try std.testing.expect(!sink.applyFilterConfig(&record));
}

test "sink flush updates stats" {
    const allocator = std.testing.allocator;
    const log_path = ".zig-cache/logly-sink-auto-flush-stats.log";

    var sink_cfg = SinkConfig.default();
    sink_cfg.path = log_path;
    sink_cfg.async_write = false;
    sink_cfg.overwrite_mode = true;

    const sink = try Sink.init(allocator, sink_cfg);
    defer std.Io.Dir.cwd().deleteFile(Utils.io(), log_path) catch {};
    defer sink.deinit();

    var record = Record.init(allocator, .info, "stats check");
    defer record.deinit();
    record.timestamp = Utils.currentMillis();

    var global_config = Config.default();
    global_config.auto_sink = false;

    try sink.write(&record, global_config);

    const stats = sink.getStats();
    try std.testing.expect(stats.getTotalWritten() >= 1);
    try std.testing.expect(stats.getBytesWritten() > 0);
    try std.testing.expect(stats.getFlushCount() >= 1);
    try std.testing.expectEqual(@as(u64, 0), stats.getWriteErrors());
}

test "sink manual flushNow updates stats" {
    const allocator = std.testing.allocator;
    const log_path = ".zig-cache/logly-sink-manual-flush-stats.log";

    var sink_cfg = SinkConfig.default();
    sink_cfg.path = log_path;
    sink_cfg.async_write = true;
    sink_cfg.buffer_size = Constants.BufferSizes.sink;
    sink_cfg.overwrite_mode = true;

    const sink = try Sink.init(allocator, sink_cfg);
    defer std.Io.Dir.cwd().deleteFile(Utils.io(), log_path) catch {};
    defer sink.deinit();

    var record = Record.init(allocator, .info, "manual flush stats check");
    defer record.deinit();
    record.timestamp = Utils.currentMillis();

    var global_config = Config.default();
    global_config.auto_sink = false;

    try sink.write(&record, global_config);

    const before_flush_stats = sink.getStats();
    try std.testing.expectEqual(@as(u64, 0), before_flush_stats.getFlushCount());
    try std.testing.expectEqual(@as(u64, 0), before_flush_stats.getTotalWritten());

    try sink.flushNow();

    const after_flush_stats = sink.getStats();
    try std.testing.expect(after_flush_stats.getFlushCount() >= 1);
    try std.testing.expect(after_flush_stats.getTotalWritten() >= 1);
    try std.testing.expect(after_flush_stats.getBytesWritten() > 0);
    try std.testing.expectEqual(@as(u64, 0), after_flush_stats.getWriteErrors());
}

test "sink on_error disable_sink disables sink" {
    const allocator = std.testing.allocator;

    var sink_cfg = SinkConfig.default();
    sink_cfg.on_error = .disable_sink;

    const sink = try Sink.init(allocator, sink_cfg);
    defer sink.deinit();

    const TestError = error{WriteFailed};
    try sink.handleWriteError(TestError.WriteFailed, 1);

    try std.testing.expect(!sink.isEnabled());
    const stats = sink.getStats();
    try std.testing.expectEqual(@as(u64, 1), stats.getWriteErrors());
}

test "sink on_error propagate returns error" {
    const allocator = std.testing.allocator;

    var sink_cfg = SinkConfig.default();
    sink_cfg.on_error = .propagate;

    const sink = try Sink.init(allocator, sink_cfg);
    defer sink.deinit();

    const TestError = error{WriteFailed};
    try std.testing.expectError(TestError.WriteFailed, sink.handleWriteError(TestError.WriteFailed, 2));

    const stats = sink.getStats();
    try std.testing.expectEqual(@as(u64, 1), stats.getWriteErrors());
}

/// A group of sinks to which logs can be fanned out atomically.
pub const SinkGroup = struct {
    allocator: std.mem.Allocator,
    sinks: std.ArrayListUnmanaged(*Sink),
    mutex: std.Io.Mutex = std.Io.Mutex.init,

    pub fn init(allocator: std.mem.Allocator) SinkGroup {
        return .{
            .allocator = allocator,
            .sinks = .empty,
        };
    }

    pub fn deinit(self: *SinkGroup) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        self.sinks.deinit(self.allocator);
    }

    pub fn addSink(self: *SinkGroup, sink: *Sink) !void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        try self.sinks.append(self.allocator, sink);
    }

    pub const add_sink = addSink;

    pub fn write(self: *SinkGroup, record: *const Record, global_config: anytype) !void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());

        for (self.sinks.items) |sink| {
            try sink.write(record, global_config);
        }
    }

    pub fn flush(self: *SinkGroup) !void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());

        for (self.sinks.items) |sink| {
            try sink.flush();
        }
    }
};

test "SinkGroup fan-out and flush" {
    const allocator = std.testing.allocator;

    var group = SinkGroup.init(allocator);
    defer group.deinit();

    var s1_cfg = SinkConfig.memory();
    s1_cfg.name = "s1";
    const s1 = try Sink.init(allocator, s1_cfg);
    defer s1.deinit();

    var s2_cfg = SinkConfig.memory();
    s2_cfg.name = "s2";
    const s2 = try Sink.init(allocator, s2_cfg);
    defer s2.deinit();

    try group.addSink(s1);
    try group.addSink(s2);

    var record = Record.init(allocator, .info, "sink group check");
    defer record.deinit();
    record.timestamp = 0;

    var global_config = Config.default();
    global_config.auto_sink = false;

    try group.write(&record, global_config);
    try group.flush();

    const m1 = try s1.getMemoryMessages(allocator);
    defer {
        for (m1) |msg| allocator.free(msg);
        allocator.free(m1);
    }
    const m2 = try s2.getMemoryMessages(allocator);
    defer {
        for (m2) |msg| allocator.free(msg);
        allocator.free(m2);
    }

    try std.testing.expectEqual(@as(usize, 1), m1.len);
    try std.testing.expectEqual(@as(usize, 1), m2.len);
    try std.testing.expect(std.mem.indexOf(u8, m1[0], "sink group check") != null);
    try std.testing.expect(std.mem.indexOf(u8, m2[0], "sink group check") != null);
}

test "sink tamper_evident cryptographic log chaining" {
    const allocator = std.testing.allocator;

    var sink_cfg = SinkConfig.memory();
    sink_cfg.name = "tamper_evident_sink";
    sink_cfg.tamper_evident = true;

    const sink = try Sink.init(allocator, sink_cfg);
    defer sink.deinit();

    var record1 = Record.init(allocator, .info, "first log record");
    defer record1.deinit();
    record1.timestamp = 1000;

    var global_config = Config.default();
    global_config.auto_sink = false;

    try sink.write(&record1, global_config);
    try sink.flush();

    const m1 = try sink.getMemoryMessages(allocator);
    defer {
        for (m1) |msg| allocator.free(msg);
        allocator.free(m1);
    }

    try std.testing.expectEqual(@as(usize, 1), m1.len);
    // It should contain "first log record" and the signature "SIG:"
    try std.testing.expect(std.mem.indexOf(u8, m1[0], "first log record") != null);
    try std.testing.expect(std.mem.indexOf(u8, m1[0], "SIG:") != null);

    // Write a second record, which should be chained to the first one
    var record2 = Record.init(allocator, .info, "second log record");
    defer record2.deinit();
    record2.timestamp = 2000;

    try sink.write(&record2, global_config);
    try sink.flush();

    const m2 = try sink.getMemoryMessages(allocator);
    defer {
        for (m2) |msg| allocator.free(msg);
        allocator.free(m2);
    }

    try std.testing.expectEqual(@as(usize, 2), m2.len);
    try std.testing.expect(std.mem.indexOf(u8, m2[1], "second log record") != null);
    try std.testing.expect(std.mem.indexOf(u8, m2[1], "SIG:") != null);
}

/// A memory-mapped file abstraction for extremely high-performance logging.
/// Supports native memory mapping on Windows and POSIX (Linux, macOS) systems,
/// with automatic dynamic resizing/remapping and graceful fallback.
pub const MmapFile = struct {
    file: std.Io.File,
    memory: []align(std.heap.page_size_min) u8 = &.{},
    write_ptr: usize = 0,
    capacity: usize = 0,
    allocator: std.mem.Allocator,
    is_mapped: bool = false,

    // Platform-specific fields
    mapping_handle: if (builtin.os.tag == .windows) ?std.os.windows.HANDLE else void = if (builtin.os.tag == .windows) null else {},

    // Windows mapping API declarations
    const win32 = if (builtin.os.tag == .windows) struct {
        extern "kernel32" fn CreateFileMappingW(
            hFile: std.os.windows.HANDLE,
            lpFileMappingAttributes: ?*anyopaque,
            flProtect: std.os.windows.DWORD,
            dwMaximumSizeHigh: std.os.windows.DWORD,
            dwMaximumSizeLow: std.os.windows.DWORD,
            lpName: ?std.os.windows.LPCWSTR,
        ) callconv(.winapi) ?std.os.windows.HANDLE;

        extern "kernel32" fn MapViewOfFile(
            hFileMappingObject: std.os.windows.HANDLE,
            dwDesiredAccess: std.os.windows.DWORD,
            dwFileOffsetHigh: std.os.windows.DWORD,
            dwFileOffsetLow: std.os.windows.DWORD,
            dwNumberOfBytesToMap: usize,
        ) callconv(.winapi) ?*anyopaque;

        extern "kernel32" fn UnmapViewOfFile(
            lpBaseAddress: ?*const anyopaque,
        ) callconv(.winapi) std.os.windows.BOOL;

        extern "kernel32" fn FlushViewOfFile(
            lpBaseAddress: ?*const anyopaque,
            dwNumberOfBytesToFlush: usize,
        ) callconv(.winapi) std.os.windows.BOOL;
    } else struct {};

    pub fn init(allocator: std.mem.Allocator, file: std.Io.File, initial_size: usize) !MmapFile {
        const io = Utils.io();
        // Pre-allocate / grow file
        try file.setLength(io, initial_size);

        var self = MmapFile{
            .allocator = allocator,
            .file = file,
            .write_ptr = 0,
            .capacity = initial_size,
        };

        self.map() catch {
            self.is_mapped = false;
        };

        return self;
    }

    pub fn deinit(self: *MmapFile) void {
        self.unmap();
        // Truncate file to actual bytes written before closing
        const io = Utils.io();
        self.file.setLength(io, self.write_ptr) catch {};
    }

    pub fn write(self: *MmapFile, data: []const u8) !void {
        if (!self.is_mapped) {
            // Fallback to standard file write
            const io = Utils.io();
            try self.file.writeStreamingAll(io, data);
            self.write_ptr += data.len;
            return;
        }

        if (self.write_ptr + data.len > self.capacity) {
            // Grow file and remap
            const new_capacity = self.capacity * 2 + data.len;
            try self.grow(new_capacity);
        }

        @memcpy(self.memory[self.write_ptr..][0..data.len], data);
        self.write_ptr += data.len;
    }

    pub fn flush(self: *MmapFile) void {
        if (!self.is_mapped) return;

        if (builtin.os.tag == .windows) {
            _ = win32.FlushViewOfFile(self.memory.ptr, self.write_ptr);
        } else {
            // POSIX msync (MS_ASYNC = 1)
            std.posix.msync(self.memory, 1) catch {};
        }
    }

    fn map(self: *MmapFile) !void {
        if (self.capacity == 0) return;

        if (builtin.os.tag == .windows) {
            const h = win32.CreateFileMappingW(self.file.handle, null, 4, 0, @intCast(self.capacity), null) orelse return error.MmapFailed;
            self.mapping_handle = h;
            errdefer {
                _ = std.os.windows.CloseHandle(h);
                self.mapping_handle = null;
            }

            const ptr = win32.MapViewOfFile(h, 2, 0, 0, self.capacity) orelse return error.MmapFailed;
            const aligned_ptr = @as([*]align(std.heap.page_size_min) u8, @ptrCast(@alignCast(ptr)));
            self.memory = aligned_ptr[0..self.capacity];
            self.is_mapped = true;
        } else {
            const memory = try std.posix.mmap(
                null,
                self.capacity,
                std.posix.PROT{ .READ = true, .WRITE = true },
                std.posix.MAP{ .TYPE = .SHARED },
                self.file.handle,
                0,
            );
            self.memory = memory;
            self.is_mapped = true;
        }
    }

    fn unmap(self: *MmapFile) void {
        if (!self.is_mapped) return;

        if (builtin.os.tag == .windows) {
            _ = win32.UnmapViewOfFile(self.memory.ptr);
            if (self.mapping_handle) |h| {
                _ = std.os.windows.CloseHandle(h);
                self.mapping_handle = null;
            }
        } else {
            std.posix.munmap(self.memory);
        }
        self.memory = &.{};
        self.is_mapped = false;
    }

    pub fn grow(self: *MmapFile, new_capacity: usize) !void {
        const aligned_capacity = std.mem.alignForward(usize, new_capacity, std.heap.page_size_min);
        self.unmap();

        const io = Utils.io();
        try self.file.setLength(io, aligned_capacity);
        self.capacity = aligned_capacity;

        try self.map();
    }
};

test "sink memory-mapped file sink" {
    const allocator = std.testing.allocator;

    const test_path = "mmap_test.log";
    std.Io.Dir.cwd().deleteFile(Utils.io(), test_path) catch {};
    defer std.Io.Dir.cwd().deleteFile(Utils.io(), test_path) catch {};

    var sink_cfg = SinkConfig.file(test_path);
    sink_cfg.name = "mmap_sink";
    sink_cfg.mmap = true;
    sink_cfg.async_write = false; // direct write

    const sink = try Sink.init(allocator, sink_cfg);
    errdefer sink.deinit();

    var record1 = Record.init(allocator, .info, "first mmap log message");
    defer record1.deinit();
    record1.timestamp = 1000;

    var global_config = Config.default();
    global_config.auto_sink = false;

    try sink.write(&record1, global_config);
    try sink.flush();

    // Deinitialize here to flush, unmap, and truncate the file on disk
    sink.deinit();

    // Verify the file content by reading it back
    const file_content = try std.Io.Dir.cwd().readFileAlloc(Utils.io(), test_path, allocator, .limited(Constants.BufferSizes.file_read));
    defer allocator.free(file_content);

    try std.testing.expect(std.mem.indexOf(u8, file_content, "first mmap log message") != null);
}

var test_sig_called: bool = false;
var test_sig_value: [64]u8 = undefined;
var test_sig_len: usize = 0;
fn mockSignatureCallback(sink_name: []const u8, sig: []const u8) void {
    _ = sink_name;
    @memcpy(test_sig_value[0..sig.len], sig);
    test_sig_len = sig.len;
    test_sig_called = true;
}

test "sink cryptographic log chaining signature callback" {
    const allocator = std.testing.allocator;
    const test_path = "sig_callback_test.log";
    std.Io.Dir.cwd().deleteFile(Utils.io(), test_path) catch {};
    defer std.Io.Dir.cwd().deleteFile(Utils.io(), test_path) catch {};

    var sink_cfg = SinkConfig.file(test_path);
    sink_cfg.name = "chaining_sink";
    sink_cfg.tamper_evident = true;
    sink_cfg.async_write = false;

    const sink = try Sink.init(allocator, sink_cfg);
    defer sink.deinit();

    test_sig_called = false;
    test_sig_len = 0;
    sink.setSignatureCallback(&mockSignatureCallback);

    var record = Record.init(allocator, .info, "test chaining callback");
    defer record.deinit();

    var global_config = Config.default();
    global_config.auto_sink = false;

    try sink.write(&record, global_config);
    try std.testing.expect(test_sig_called);
    try std.testing.expect(test_sig_len > 0);
}

var test_mmap_resize_called: bool = false;
var test_mmap_old_capacity: u64 = 0;
var test_mmap_new_capacity: u64 = 0;
fn mockMmapResizeCallback(sink_name: []const u8, old_cap: u64, new_cap: u64) void {
    _ = sink_name;
    test_mmap_old_capacity = old_cap;
    test_mmap_new_capacity = new_cap;
    test_mmap_resize_called = true;
}

test "sink memory-mapped resize callback" {
    const allocator = std.testing.allocator;
    const test_path = "mmap_resize_test.log";
    std.Io.Dir.cwd().deleteFile(Utils.io(), test_path) catch {};
    defer std.Io.Dir.cwd().deleteFile(Utils.io(), test_path) catch {};

    var sink_cfg = SinkConfig.file(test_path);
    sink_cfg.name = "mmap_resize_sink";
    sink_cfg.mmap = true;
    sink_cfg.async_write = false;

    const sink = try Sink.init(allocator, sink_cfg);
    defer sink.deinit();

    test_mmap_resize_called = false;
    sink.setMmapResizeCallback(&mockMmapResizeCallback);

    if (sink.mmap_file) |*mmap_f| {
        const old_cap = mmap_f.capacity;
        try mmap_f.grow(old_cap + 1000);
        if (sink.on_mmap_resize) |cb| {
            cb("mmap_resize_sink", old_cap, mmap_f.capacity);
        }
    }

    try std.testing.expect(test_mmap_resize_called);
    try std.testing.expect(test_mmap_new_capacity > test_mmap_old_capacity);
}
