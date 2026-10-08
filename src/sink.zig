//! Log output destinations.
//!
//! Console, file, memory, mmap, and network sinks with buffering and rotation.
const std = @import("std");
const builtin = @import("builtin");
const Config = @import("config.zig").Config;
const Color = @import("color.zig");
const Level = @import("level.zig").Level;
const Constants = @import("constants.zig");
const Record = @import("record.zig").Record;
const Formatter = @import("formatter.zig").Formatter;
const Rotation = @import("rotation.zig").Rotation;
const Network = @import("network.zig");
const Utils = @import("utils.zig");

/// File write mode.
pub const WriteMode = enum {
    /// Append to existing file (default).
    append,
    /// Truncate file before writing.
    overwrite,
    /// Append normally but trigger rotation when size/time limits are reached.
    appendRotate,
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

        pub const eventlogSuccess: WORD = @as(WORD, Constants.EventLogConstants.success);
        pub const eventlogErrorType: WORD = @as(WORD, Constants.EventLogConstants.errorType);
        pub const eventlogWarningType: WORD = @as(WORD, Constants.EventLogConstants.warningType);
        pub const eventlogInformationType: WORD = @as(WORD, Constants.EventLogConstants.informationType);

        extern "advapi32" fn RegisterEventSourceA(lpUNCServerName: ?LPCSTR, lpSourceName: LPCSTR) callconv(WINAPI) ?HANDLE;
        extern "advapi32" fn ReportEventA(hEventLog: HANDLE, wType: WORD, wCategory: WORD, dwEventID: DWORD, lpUserSid: PSID, wNumStrings: WORD, dwDataSize: DWORD, lpStrings: ?[*]const LPCSTR, lpRawData: ?*anyopaque) callconv(WINAPI) bool;
        extern "advapi32" fn DeregisterEventSource(hEventLog: HANDLE) callconv(WINAPI) bool;
    } else struct {};

    // POSIX specific definitions
    const posix = if (platform == .posix) struct {
        const logPID = 0x01;
        const logCONS = 0x02;
        const logUSER = 3 << 3;

        const logERR = 3;
        const logWARNING = 4;
        const logINFO = 6;

        extern "c" fn openlog(ident: ?[*:0]const u8, option: c_int, facility: c_int) void;
        extern "c" fn syslog(priority: c_int, format: [*:0]const u8, ...) void;
        extern "c" fn closelog() void;
    } else struct {};

    const PosixImpl = if (platform == .posix) struct {
        fn logPosix(self: *SystemLog, level: Level, message: []const u8) !void {
            // Prepare zero-terminated message
            const msgZ: [:0]const u8 = try self.allocator.dupeSentinel(u8, message, 0);
            defer self.allocator.free(msgZ);

            // Map level to syslog priority
            const priority: c_int = switch (level) {
                .err, .critical, .fail, .fatal => posix.logERR,
                .warning => posix.logWARNING,
                .notice => posix.logINFO, // Notice maps to INFO (syslog has LOG_NOTICE but we use LOG_INFO)
                else => posix.logINFO,
            };

            // Call syslog with a fixed format string and the message as vararg
            const cMsg: [*:0]const u8 = msgZ;
            posix.syslog(priority, "%s", cMsg);
        }
    } else struct {};

    handle: ?*anyopaque = null,
    ident: ?[:0]const u8 = null,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, name: ?[]const u8) !SystemLog {
        var self = SystemLog{ .allocator = allocator };
        const safeName = name orelse "Logly";

        switch (platform) {
            .windows => {
                const nameZ = try allocator.dupeSentinel(u8, safeName, 0);
                errdefer allocator.free(nameZ);
                self.ident = nameZ;
                if (windows.RegisterEventSourceA(null, nameZ)) |h| {
                    self.handle = @ptrCast(h);
                }
            },
            .posix => {
                const nameZ = try allocator.dupeSentinel(u8, safeName, 0);
                self.ident = nameZ;
                posix.openlog(nameZ, posix.logPID | posix.logCONS, posix.logUSER);
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
        if (comptime platform == .windows) {
            return self.logWindows(level, message);
        } else if (comptime platform == .posix) {
            return PosixImpl.logPosix(self, level, message);
        } else {
            return self.logOther(level, message);
        }
    }

    fn logWindows(self: *SystemLog, level: Level, message: []const u8) !void {
        if (self.handle) |h| {
            const msgZ = try self.allocator.dupeSentinel(u8, message, 0);
            defer self.allocator.free(msgZ);
            const strings = [_]windows.LPCSTR{msgZ};
            const wType = switch (level) {
                .err, .critical, .fail, .fatal => windows.eventlogErrorType,
                .warning => windows.eventlogWarningType,
                .notice, .info, .success => windows.eventlogInformationType,
                else => windows.eventlogInformationType,
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
    sizeLimit: ?u64 = null,

    /// Size limit as a string (e.g., "10MB", "1GB").
    sizeLimitStr: ?[]const u8 = null,

    /// Number of rotated files to keep.
    retention: ?usize = null,

    /// Custom naming format for rotated files (e.g., "{base}-{date}{ext}").
    /// Placeholders: base, ext, date, time, timestamp, iso
    namingFormat: ?[]const u8 = null,

    /// Sink-specific log level. Overrides the global level if set.
    level: ?Level = null,

    /// Maximum log level for this sink (create level range filters).
    maxLevel: ?Level = null,

    /// Enable async writing with background buffering.
    asyncWrite: bool = true,

    /// Buffer size for async writing in bytes.
    bufferSize: usize = Constants.BufferSizes.sink,

    /// Output format for this sink. Null inherits the logger-wide
    /// Config.format, so a default sink follows the logger with no
    /// conflicting flags. Set explicitly (e.g. `.format = .ndjson`) to
    /// render this sink differently from the rest.
    format: ?Config.Format = null,

    /// Pretty print JSON document output (applies to .json file documents).
    prettyJson: bool = false,

    /// Enables cryptographic log chaining to detect tampering.
    tamperEvident: bool = false,

    /// Enables memory-mapped file logging for extremely high performance.
    mmap: bool = false,

    /// Enable/disable colors for this sink.
    /// If null, auto-detect: enabled for console targets only when stdout
    /// is an interactive terminal, disabled for files and network sinks.
    /// Explicit true forces color even when piped; explicit false disables.
    color: ?bool = null,

    /// Enable/disable this sink initially.
    enabled: bool = true,

    /// Include timestamp in output.
    includeTimestamp: bool = true,

    /// Include log level in output.
    includeLevel: bool = true,

    /// Include source location in output.
    includeSource: bool = false,

    /// Include trace IDs in output (for distributed tracing).
    includeTraceId: bool = false,

    /// Custom log format string for this sink.
    /// Overrides global format if set.
    logFormat: ?[]const u8 = null,

    /// Time format for this sink.
    timeFormat: ?[]const u8 = null,

    /// File write mode: false = append (default), true = overwrite.
    /// When true, existing files are truncated before writing.
    overwriteMode: bool = false,

    /// File write mode. Controls whether files are appended to, overwritten, or
    /// appended with rotation triggers.
    writeMode: WriteMode = .append,

    /// Whether this is an in-memory sink.
    isMemory: bool = false,

    /// Whether this is a stderr console sink.
    isStderr: bool = false,

    /// Per-sink rate limiting (messages per second, 0 = unlimited).
    rateLimitPerSecond: u32 = Constants.SinkDefaults.rateLimitPerSecond,

    /// Capacity of the in-memory ring buffer.
    memoryCapacity: usize = Constants.SinkDefaults.memoryRingSize,

    /// Compression settings for file sinks.
    compression: CompressionConfig = .{},

    /// Filter configuration for this sink.
    filter: FilterConfig = .{},

    /// Error handling for this sink.
    onError: ErrorBehavior = .logStderr,

    /// Maximum records to buffer before forcing a flush.
    maxBufferRecords: usize = Constants.SinkDefaults.maxBufferRecords,

    /// Flush interval in milliseconds.
    flushIntervalMs: u64 = Constants.SinkDefaults.flushIntervalMs,

    /// File permissions for created log files (Unix only).
    fileMode: ?u32 = null,

    /// Enable system event log output (Windows Event Log / Syslog).
    eventLog: bool = false,

    /// Custom color theme for this sink.
    theme: ?Formatter.Theme = null,

    /// Compression configuration for sink.
    /// Re-exports centralized config for convenience.
    pub const CompressionConfig = Config.CompressionConfig;

    /// Filter configuration for sink-level filtering.
    pub const FilterConfig = struct {
        /// Include only logs from these modules.
        includeModules: ?[]const []const u8 = null,

        /// Exclude logs from these modules.
        excludeModules: ?[]const []const u8 = null,

        /// Include only logs containing these substrings.
        includeMessages: ?[]const []const u8 = null,

        /// Exclude logs containing these substrings.
        excludeMessages: ?[]const []const u8 = null,
    };

    /// Error behavior for sink write failures.
    pub const ErrorBehavior = enum {
        /// Silently ignore errors.
        silent,

        /// Log errors to stderr.
        logStderr,

        /// Disable the sink on error.
        disableSink,

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
            // Console must flush immediately so `std.debug.print` (stderr)
            // section headers and logger output (stdout) stay in order.
            // Buffered console output flushed only at deinit caused all
            // log lines to appear after "Example Complete" footers.
            .asyncWrite = false,
            .enabled = true,
        };
    }

    /// Returns a stderr console sink configuration.
    pub fn stderr() SinkConfig {
        return .{
            .path = null,
            .isStderr = true,
            .color = null,
            // Same reasoning as console(): stderr readers expect immediacy.
            .asyncWrite = false,
            .enabled = true,
        };
    }

    /// Returns an in-memory ring buffer sink configuration.
    pub fn memory() SinkConfig {
        return .{
            .path = "memory",
            .isMemory = true,
            .color = false,
            .asyncWrite = false, // Sync write by default to keep memory immediate
            .enabled = true,
        };
    }

    /// Returns a file sink configuration.
    pub fn file(filePath: []const u8) SinkConfig {
        return .{
            .path = filePath,
            .color = false,
        };
    }

    /// Returns a JSON file sink configuration.
    pub fn jsonFile(filePath: []const u8) SinkConfig {
        return .{
            .path = filePath,
            .format = .json,
            .color = false,
        };
    }

    /// Returns a rotating file sink configuration.
    pub fn rotating(filePath: []const u8, rotationInterval: []const u8, retentionCount: usize) SinkConfig {
        return .{
            .path = filePath,
            .rotation = rotationInterval,
            .retention = retentionCount,
            .color = false,
        };
    }

    /// Returns an error-only sink configuration.
    pub fn errorOnly(filePath: []const u8) SinkConfig {
        return .{
            .path = filePath,
            .level = .err,
            .color = false,
        };
    }

    /// Returns a network sink configuration.
    pub fn network(uri: []const u8) SinkConfig {
        return .{
            .path = uri,
            .color = false,
            .asyncWrite = true, // Network I/O should default to async
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
        totalWritten: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        /// Total bytes written to the sink.
        bytesWritten: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        /// Number of write errors encountered.
        writeErrors: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        /// Number of flush operations performed.
        flushCount: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        /// Number of file rotations performed.
        rotationCount: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),

        /// Get total number of records written.
        pub fn getTotalWritten(self: *const SinkStats) u64 {
            return Utils.atomicLoadU64(&self.totalWritten);
        }

        /// Get total bytes written.
        pub fn getBytesWritten(self: *const SinkStats) u64 {
            return Utils.atomicLoadU64(&self.bytesWritten);
        }

        /// Get number of write errors.
        pub fn getWriteErrors(self: *const SinkStats) u64 {
            return Utils.atomicLoadU64(&self.writeErrors);
        }

        /// Get number of flush operations.
        pub fn getFlushCount(self: *const SinkStats) u64 {
            return Utils.atomicLoadU64(&self.flushCount);
        }

        /// Get number of file rotations.
        pub fn getRotationCount(self: *const SinkStats) u64 {
            return Utils.atomicLoadU64(&self.rotationCount);
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
        pub fn throughputBytesPerSecond(self: *const SinkStats, elapsedSeconds: f64) f64 {
            return Utils.safeFloatDiv(
                @as(f64, @floatFromInt(self.getBytesWritten())),
                elapsedSeconds,
            );
        }

        /// Calculate records per second throughput.
        pub fn throughputRecordsPerSecond(self: *const SinkStats, elapsedSeconds: f64) f64 {
            return Utils.safeFloatDiv(
                @as(f64, @floatFromInt(self.getTotalWritten())),
                elapsedSeconds,
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
            self.totalWritten.store(0, .monotonic);
            self.bytesWritten.store(0, .monotonic);
            self.writeErrors.store(0, .monotonic);
            self.flushCount.store(0, .monotonic);
            self.rotationCount.store(0, .monotonic);
        }
    };

    /// Memory allocator for sink operations.
    allocator: std.mem.Allocator,
    /// Sink configuration options.
    config: SinkConfig,
    /// File handle for file-based sinks.
    file: ?std.Io.File = null,
    /// Memory-mapped file handle for high-performance sinks.
    mmapFile: ?MmapFile = null,
    /// TCP stream for network sinks.
    stream: ?std.Io.net.Stream = null,
    /// UDP socket for network sinks.
    udpSocket: ?std.Io.net.Socket = null,
    /// UDP destination address.
    udpAddr: ?std.Io.net.IpAddress = null,
    /// System log handle (Windows Event Log / Syslog).
    systemLog: ?SystemLog = null,
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
    /// True when the sink targets the OS null device (NUL, /dev/null).
    /// Writes are formatted (for benchmark fidelity) then discarded
    /// without creating files or touching the console.
    isNullDevice: bool = false,
    /// Track if this is the first JSON entry for file output.
    jsonFirstEntry: bool = true,
    /// Whether the current file holds an open JSON-array document ("[\n"
    /// written, closing "\n]" still owed). Set at creation, by Logger
    /// reconciliation for inherited formats, and across rotations.
    jsonArrayOpen: bool = false,
    /// Number of records currently buffered and pending flush.
    bufferedRecords: usize = 0,
    /// Sink statistics.
    stats: SinkStats = .{},

    /// Last cryptographic chain hash.
    lastRecordHash: ?[32]u8 = null,

    /// Number of consecutive write errors.
    consecutiveErrors: u32 = 0,

    /// Rate limiter: last token refill timestamp (nanoseconds).
    rateLimitLastRefillNs: i128 = 0,
    /// Rate limiter: current tokens.
    rateLimitTokens: f64 = 0,

    /// Ring buffer for in-memory logging.
    memoryRing: ?[]?[]const u8 = null,
    /// Ring buffer write index.
    memoryRingIndex: usize = 0,
    /// Ring buffer count of stored messages.
    memoryRingCount: usize = 0,

    /// Callback invoked when a record is written to the sink.
    onWrite: ?*const fn (u64, u64) void = null,

    /// Callback invoked when a flush operation completes.
    onFlush: ?*const fn (u64, u64) void = null,

    /// Callback invoked when a write error occurs.
    onError: ?*const fn ([]const u8, u64) void = null,

    /// Callback invoked when rotation occurs (if enabled).
    onRotation: ?*const fn ([]const u8, []const u8) void = null,

    /// Callback invoked when sink is disabled/enabled.
    onStateChange: ?*const fn (bool) void = null,

    /// Callback invoked when a cryptographic signature is generated for a log record.
    onSignature: ?*const fn ([]const u8, []const u8) void = null,

    /// Callback invoked when a memory-mapped sink grows in virtual memory size.
    onMmapResize: ?*const fn ([]const u8, u64, u64) void = null,

    /// Initializes a new sink with the provided configuration.
    pub fn init(allocator: std.mem.Allocator, config: SinkConfig) !*Sink {
        const sink = try allocator.create(Sink);
        sink.* = .{
            .allocator = allocator,
            .config = config,
            .formatter = Formatter.init(allocator),
            .buffer = .empty,
            .enabled = config.enabled,
            .jsonFirstEntry = true,
        };
        errdefer sink.deinit();

        if (config.theme) |t| {
            sink.formatter.setTheme(t);
        }

        if (config.isMemory) {
            sink.memoryRing = try allocator.alloc(?[]const u8, config.memoryCapacity);
            @memset(sink.memoryRing.?, null);
            sink.memoryRingIndex = 0;
            sink.memoryRingCount = 0;
        } else if (config.eventLog) {
            // Event-log transports carry text: binary MessagePack cannot
            // survive NUL-terminated syslog/EventLog strings, and a
            // syslog-framed record would gain a second header from the
            // daemon. Reject explicitly instead of emitting corrupt data.
            if (config.format) |f| switch (f) {
                .msgpack, .syslog, .syslog3164 => return error.UnsupportedFormatForSink,
                .text, .json, .ndjson, .logfmt => {},
            };
            sink.systemLog = try SystemLog.init(allocator, config.name);
        } else if (config.path) |pathPattern| {
            // Null device (benchmark blackhole): format but discard.
            // Must be checked before network/file handling so we never
            // create real files named "NUL" or rotate them.
            if (isNullDevicePath(pathPattern)) {
                sink.isNullDevice = true;
                return sink;
            }
            // Check for network schemes
            if (std.mem.startsWith(u8, pathPattern, "tcp://")) {
                sink.stream = try Network.connectTcp(allocator, pathPattern);
            } else if (std.mem.startsWith(u8, pathPattern, "udp://")) {
                const result = try Network.createUdpSocket(allocator, pathPattern);
                sink.udpSocket = result.socket;
                sink.udpAddr = result.address;
            } else {
                // File path
                // Resolve dynamic path patterns (e.g. {date}, {YYYY-MM-DD})
                const path = try resolvePath(allocator, pathPattern);
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
                    .truncate = config.overwriteMode or (config.writeMode == .overwrite),
                });

                if (config.mmap) {
                    sink.mmapFile = try MmapFile.init(allocator, sink.file.?, 1024 * 1024);
                }

                // Open (or continue) the JSON-array document: fresh files
                // gain the bracket, appends continue a tailed array or fail
                // loudly, and mmap files restart at offset zero.
                if (config.format != null and config.format.? == .json) {
                    try sink.ensureJsonArrayOpen();
                }

                var sizeLimit = config.sizeLimit;
                if (sizeLimit == null and config.sizeLimitStr != null) {
                    sizeLimit = Utils.parseSize(config.sizeLimitStr.?);
                }

                if (config.rotation != null or sizeLimit != null) {
                    sink.rotation = try Rotation.init(
                        allocator,
                        path,
                        config.rotation,
                        sizeLimit,
                        config.retention,
                    );

                    if (config.compression.enabled) {
                        try sink.rotation.?.withCompression(config.compression);
                    }
                    if (config.namingFormat) |fmt| {
                        try sink.rotation.?.withNamingFormat(fmt);
                    }
                }
            }
        }

        sink.resolveAutoColor();
        return sink;
    }

    /// Resolves an unset color selection for console targets.
    ///
    /// Explicit `color` always wins. Otherwise a console sink (standard
    /// output, not a file/pipe target) enables color only when stdout is
    /// an interactive terminal, so piped, redirected, and CI output stays
    /// plain unless colors are forced. Files and network sinks keep the
    /// existing default-off behavior. Pure decision plus one syscall,
    /// evaluated once at creation rather than per record.
    fn resolveAutoColor(self: *Sink) void {
        if (self.config.color != null) return;
        const isConsole = self.config.path == null and !self.config.isMemory and !self.config.eventLog;
        if (!isConsole) return;
        self.config.color = Utils.stdoutIsTty();
    }

    /// Pure auto-color decision for a console target, injectable for tests.
    /// Explicit selection always wins; otherwise a TTY means color.
    pub fn autoConsoleColor(explicit: ?bool, isTty: bool) bool {
        return explicit orelse isTty;
    }

    /// Returns true for OS null-device paths that must never become real files.
    /// Returns true for OS null-device paths that must never become real files.
    ///
    /// Single source of truth: Logger.addSink consults this so that a sink
    /// accepted here is never rejected there (and vice versa) when file
    /// storage is disabled. Matching is case-insensitive on Windows, where
    /// "NUL", "nul", and "NUL.txt" all resolve to the null device.
    pub fn isNullDevicePath(path: []const u8) bool {
        if (std.mem.eql(u8, path, "/dev/null")) return true;
        // Windows reserves NUL (any case, with optional extension like NUL.txt).
        if (path.len >= 3 and (path[0] == 'N' or path[0] == 'n') and (path[1] == 'U' or path[1] == 'u') and (path[2] == 'L' or path[2] == 'l')) {
            if (path.len == 3) return true;
            // "NUL.<anything>" would otherwise create stray rotation files.
            if (path[3] == '.') return true;
        }
        return false;
    }

    fn resolvePath(allocator: std.mem.Allocator, pathPattern: []const u8) ![]u8 {
        var buf = std.Io.Writer.Allocating.init(allocator);
        errdefer buf.deinit();
        const writer = &buf.writer;

        const nowMs = Utils.currentMillis();
        const tc = Utils.fromMilliTimestamp(nowMs);
        const millis = @mod(if (nowMs < 0) 0 else @as(u64, @intCast(nowMs)), Constants.TimeConstants.msPerSecond);

        var i: usize = 0;
        while (i < pathPattern.len) {
            if (pathPattern[i] == '{') {
                const end = std.mem.indexOfScalarPos(u8, pathPattern, i + 1, '}') orelse {
                    try writer.writeByte(pathPattern[i]);
                    i += 1;
                    continue;
                };
                const tag = pathPattern[i + 1 .. end];

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
                try writer.writeByte(pathPattern[i]);
                i += 1;
            }
        }
        return buf.toOwnedSlice();
    }

    /// Deinitializes the sink and releases resources.
    /// Flushes any pending data before closing.
    pub fn deinit(self: *Sink) void {
        self.flush() catch {};

        if (self.systemLog) |*syslog| {
            syslog.deinit();
        }

        // Write closing bracket for JSON array files
        if (self.jsonArrayOpen and self.file != null) {
            if (self.config.mmap) {
                if (self.mmapFile) |*mmapF| {
                    mmapF.write("\n]") catch {};
                }
            } else if (self.file) |file| {
                file.writeStreamingAll(Utils.io(), "\n]") catch {};
            }
        }
        if (self.config.mmap) {
            if (self.mmapFile) |*mmapF| {
                mmapF.deinit();
            }
            self.mmapFile = null;
        }
        if (self.file) |f| f.close(Utils.io());
        if (self.stream) |s| s.close(Utils.io());
        if (self.udpSocket) |s| s.close(Utils.io());

        if (self.rotation) |*r| r.deinit();
        if (self.memoryRing) |ring| {
            for (ring) |msg| {
                if (msg) |m| self.allocator.free(m);
            }
            self.allocator.free(ring);
        }
        self.buffer.deinit(self.allocator);
        self.formatter.deinit();
        self.allocator.destroy(self);
    }

    /// Sets the callback for write events.
    pub fn setWriteCallback(self: *Sink, callback: *const fn (u64, u64) void) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        self.onWrite = callback;
    }

    /// Sets the callback for flush events.
    pub fn setFlushCallback(self: *Sink, callback: *const fn (u64, u64) void) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        self.onFlush = callback;
    }

    /// Sets the callback for error events.
    pub fn setErrorCallback(self: *Sink, callback: *const fn ([]const u8, u64) void) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        self.onError = callback;
    }

    /// Sets the callback for rotation events.
    pub fn setRotationCallback(self: *Sink, callback: *const fn ([]const u8, []const u8) void) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        self.onRotation = callback;
    }

    /// Sets the callback for state changes.
    pub fn setStateChangeCallback(self: *Sink, callback: *const fn (bool) void) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        self.onStateChange = callback;
    }

    /// Sets the callback for cryptographic signature generation.
    pub fn setSignatureCallback(self: *Sink, callback: *const fn ([]const u8, []const u8) void) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        self.onSignature = callback;
    }

    /// Sets the callback for memory-mapped sink resizes.
    pub fn setMmapResizeCallback(self: *Sink, callback: *const fn ([]const u8, u64, u64) void) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        self.onMmapResize = callback;
    }

    /// Returns sink statistics.
    pub fn getStats(self: *Sink) SinkStats {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());

        return self.stats;
    }

    /// Clears the internal buffer.
    pub fn clearBuffer(self: *Sink) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        self.buffer.clearRetainingCapacity();
    }

    /// Synchronizes buffer to storage (calls flush).
    /// Returns true if sink is enabled.
    pub fn isEnabled(self: *Sink) bool {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        return self.enabled;
    }

    /// Returns true if the sink is healthy (errors have not exceeded the unhealthy threshold).
    pub fn isHealthy(self: *Sink) bool {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        return self.consecutiveErrors < Constants.SinkDefaults.unhealthyErrorThreshold;
    }

    /// Retrieves in-memory logged messages in chronological order.
    /// The caller owns the returned slice and all the duplicated string elements.
    pub fn getMemoryMessages(self: *Sink, allocator: std.mem.Allocator) ![][]const u8 {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());

        const ring = self.memoryRing orelse return error.NotAMemorySink;
        const count = self.memoryRingCount;
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
                const idx = (self.memoryRingIndex + i) % ring.len;
                if (ring[idx]) |msg| {
                    const dup = try allocator.dupe(u8, msg);
                    list.appendAssumeCapacity(dup);
                }
            }
        }

        return try list.toOwnedSlice(allocator);
    }

    /// Enables the sink.
    pub fn enable(self: *Sink) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        self.enabled = true;
        if (self.onStateChange) |cb| cb(true);
    }

    /// Disables the sink.
    pub fn disable(self: *Sink) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        self.enabled = false;
        if (self.onStateChange) |cb| cb(false);
    }

    /// Returns true if async writing is enabled for this sink.
    pub fn isAsyncEnabled(self: *Sink) bool {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        return self.config.asyncWrite;
    }

    /// Enables async writing for this sink.
    pub fn enableAsync(self: *Sink) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        self.config.asyncWrite = true;
    }

    /// Disables async writing for this sink (forces immediate flush).
    pub fn disableAsync(self: *Sink) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        self.config.asyncWrite = false;
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

    /// Returns the sink's name, if set.
    pub fn getName(self: *Sink) ?[]const u8 {
        return self.config.name;
    }

    /// Writes a log record to the sink.
    pub fn write(self: *Sink, record: *const Record, globalConfig: anytype) !void {
        return self.writeWithAllocator(record, globalConfig, null);
    }

    /// Writes a log record using a specific allocator.
    pub fn writeWithAllocator(self: *Sink, record: *const Record, globalConfig: anytype, scratchAllocator: ?std.mem.Allocator) !void {
        _ = scratchAllocator;
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());

        if (!self.enabled) return;

        // Rate limiting
        if (self.config.rateLimitPerSecond > 0) {
            const now = Utils.currentNanos();
            if (self.rateLimitLastRefillNs == 0) {
                self.rateLimitLastRefillNs = now;
                self.rateLimitTokens = @floatFromInt(self.config.rateLimitPerSecond);
            } else {
                const elapsedNs = now - self.rateLimitLastRefillNs;
                const elapsedSecs = @as(f64, @floatFromInt(elapsedNs)) / 1_000_000_000.0;
                const newTokens = elapsedSecs * @as(f64, @floatFromInt(self.config.rateLimitPerSecond));
                if (newTokens > 0) {
                    self.rateLimitTokens = @min(@as(f64, @floatFromInt(self.config.rateLimitPerSecond)), self.rateLimitTokens + newTokens);
                    self.rateLimitLastRefillNs = now;
                }
            }

            if (self.rateLimitTokens < 1.0) {
                // Rate limit exceeded - silent drop
                return;
            }
            self.rateLimitTokens -= 1.0;
        }

        // Check minimum level filtering
        if (self.config.level) |minLevel| {
            if (record.level.priority() < minLevel.priority()) {
                return;
            }
        }

        // Check maximum level filtering
        if (self.config.maxLevel) |maxLevel| {
            if (record.level.priority() > maxLevel.priority()) {
                return;
            }
        }

        // Apply per-sink filter configuration
        if (!self.applyFilterConfig(record)) {
            return;
        }

        // Check rotation. The sink owns all document framing here:
        // regular files get array tails/headers around the rename, mmap
        // mappings are finalized beforehand and re-established afterwards
        // (writes would otherwise keep landing in the archived file).
        if (self.rotation) |*rot| {
            if (self.file) |*f| {
                const globalFormat = if (@hasField(@TypeOf(globalConfig), "format")) globalConfig.format else Config.Format.text;
                const effectiveFormat = self.config.format orelse globalFormat;
                const framing = effectiveFormat == .json;
                // The document must be open before any tail/header work:
                // direct writes and inherited formats may arrive here first.
                if (framing and !self.jsonArrayOpen) try self.ensureJsonArrayOpen();
                if (self.mmapFile) |*mmapF| {
                    try self.rotateMmap(rot, f, mmapF, framing);
                } else if (framing) {
                    if (!self.jsonArrayOpen) try self.ensureJsonArrayOpen();
                    try self.flush();
                    if (rot.shouldRotate(f)) {
                        const oldSize = (f.stat(Utils.io()) catch {
                            try rot.checkAndRotate(f);
                            return;
                        }).size;
                        f.writeStreamingAll(Utils.io(), "\n]") catch |err| {
                            try self.handleWriteError(err, 1);
                            return;
                        };
                        const before = rot.stats.totalRotations.load(.monotonic);
                        try rot.checkAndRotate(f);
                        if (rot.stats.totalRotations.load(.monotonic) != before) {
                            f.writeStreamingAll(Utils.io(), "[\n") catch |err| {
                                try self.handleWriteError(err, 1);
                                return;
                            };
                            self.jsonFirstEntry = true;
                            self.jsonArrayOpen = true;
                        } else {
                            // Rotation did not happen: retract the premature
                            // tail so the document stays valid.
                            f.setLength(Utils.io(), oldSize) catch |err| {
                                try self.handleWriteError(err, 1);
                                return;
                            };
                        }
                    }
                } else {
                    try rot.checkAndRotate(f);
                }
            }
        }

        // Determine effective config for this sink
        // We need to create a new config struct that overrides specific fields
        var effectiveConfig = globalConfig;

        // Single explicit format selection: a set per-sink format wins,
        // otherwise the logger-wide format flows through unchanged.
        if (self.config.format) |f| {
            effectiveConfig.format = f;
        }
        if (self.config.prettyJson) {
            effectiveConfig.prettyJson = true;
        }
        if (self.config.tamperEvident) {
            effectiveConfig.tamperEvident = true;
        }

        // Override Color setting
        // If sink is a file, default color to false unless explicitly enabled
        if (self.config.color) |c| {
            effectiveConfig.globalColorDisplay = c;
        } else if (self.file != null or self.stream != null or self.udpSocket != null) {
            // Default to no color for files/network
            effectiveConfig.globalColorDisplay = false;
        }

        // The sink-owned formatter is reused for every record. A temporary
        // formatter must not be constructed per record: Formatter.init
        // duplicates the hostname, which would leak on every thread-pool
        // record. All ToWriter paths below stream into the sink buffer, so
        // no scratch allocation is needed.
        var formatter = self.formatter;

        // Check global switches - early exit if globally disabled
        if (self.file != null) {
            // File sink - check global file storage setting
            if (!globalConfig.globalFileStorage) return;
        } else if (self.memoryRing == null and self.stream == null and self.udpSocket == null and self.systemLog == null) {
            // Console sink - check global console display setting. Memory sinks
            // are excluded: they capture in-process and never touch the console,
            // so disabling console output must not silently drop their records.
            if (!globalConfig.globalConsoleDisplay) return;
        }
        // Network and system log sinks are not affected by global console/file settings

        // Handle SystemLog separately to preserve log level
        if (self.systemLog) |*syslog| {
            // Clear buffer to ensure we only send the current message
            self.buffer.clearRetainingCapacity();
            var bufferWriter = std.Io.Writer.Allocating.fromArrayList(self.allocator, &self.buffer);
            errdefer self.buffer = bufferWriter.toArrayList();
            const writer = &bufferWriter.writer;

            // Format message. Two selections fall back here to avoid
            // invalid output: binary msgpack becomes JSON (event-log
            // transports are text-based), and syslog framing becomes plain
            // text (the transport already adds its own syslog header).
            switch (effectiveConfig.format) {
                .msgpack => try formatter.formatJsonToWriter(writer, record, effectiveConfig),
                .ndjson => try formatter.formatJsonToWriter(writer, record, effectiveConfig),
                .syslog, .syslog3164 => try formatter.formatToWriter(writer, record, effectiveConfig),
                .logfmt => try formatter.formatLogfmtToWriter(writer, record, effectiveConfig),
                .json => try formatter.formatJsonToWriter(writer, record, effectiveConfig),
                .text => try formatter.formatToWriter(writer, record, effectiveConfig),
            }
            const written = bufferWriter.written();

            // Send to system log
            if (written.len > 0) {
                try syslog.log(record.level, written);

                // Update stats
                _ = self.stats.totalWritten.fetchAdd(1, .monotonic);
                _ = self.stats.bytesWritten.fetchAdd(written.len, .monotonic);

                if (self.onWrite) |cb| {
                    cb(1, written.len);
                }
            }

            self.buffer = bufferWriter.toArrayList();
            self.buffer.clearRetainingCapacity();
            return;
        }

        // MessagePack takes a dedicated path: binary records carry no line
        // terminator, so they must never flow through the text buffer with
        // an appended '\n' (0x0A decodes as fixint 10 and would silently
        // corrupt the stream).
        if (effectiveConfig.format == .msgpack) {
            return self.writeMsgpackRecord(record, &effectiveConfig);
        }

        // Write to buffer
        const startIdx = self.buffer.items.len;
        var bufferWriter = std.Io.Writer.Allocating.fromArrayList(self.allocator, &self.buffer);
        errdefer self.buffer = bufferWriter.toArrayList();
        const writer = &bufferWriter.writer;
        const isFile = self.file != null;
        const useJsonArray = isFile and effectiveConfig.format == .json;

        // Direct-write path (no Logger.addSink reconciliation ran): open or
        // continue the array document here, so inherited-global formats are
        // framed exactly like explicit per-sink ones.
        if (useJsonArray and !self.jsonArrayOpen) try self.ensureJsonArrayOpen();

        // Record start within the buffer (after any array separator), so
        // presentation color wraps the record itself, never framing bytes.
        var recStart = startIdx;
        if (useJsonArray) {
            if (!self.jsonFirstEntry) {
                try writer.writeAll(",\n");
                recStart += ",\n".len;
            }
            try formatter.formatJsonToWriter(writer, record, effectiveConfig);
            self.jsonFirstEntry = false;
        } else {
            switch (effectiveConfig.format) {
                .msgpack => unreachable, // handled above
                .ndjson => try formatter.formatJsonToWriter(writer, record, effectiveConfig),
                .syslog => try formatter.formatSyslogToWriter(writer, record, effectiveConfig),
                .syslog3164 => try formatter.formatSyslog3164ToWriter(writer, record, effectiveConfig),
                .logfmt => try formatter.formatLogfmtToWriter(writer, record, effectiveConfig),
                .json => try formatter.formatJsonToWriter(writer, record, effectiveConfig),
                .text => try formatter.formatToWriter(writer, record, effectiveConfig),
            }
        }
        self.buffer = bufferWriter.toArrayList();

        // Apply Tamper-Evident Hashing
        if (effectiveConfig.tamperEvident) {
            const newlyWritten = self.buffer.items[startIdx..];
            self.lastRecordHash = Utils.computeChainHash(self.lastRecordHash, newlyWritten);

            const hashHex = std.fmt.bytesToHex(self.lastRecordHash.?, .lower);

            if (self.onSignature) |cb| {
                cb(self.config.name orelse "unnamed_sink", &hashHex);
            }

            if (useJsonArray or effectiveConfig.format == .ndjson or effectiveConfig.format == .json) {
                // Inject the signature as a real JSON field so the output
                // stays valid JSON (a /* comment */ would corrupt it).
                // The record just written ends with '}' (color is never
                // emitted for JSON); insert before that brace.
                if (self.buffer.items.len > startIdx and self.buffer.items[self.buffer.items.len - 1] == '}') {
                    self.buffer.items.len -= 1;
                    try self.buffer.appendSlice(self.allocator, ",\"sig\":\"");
                    try self.buffer.appendSlice(self.allocator, &hashHex);
                    try self.buffer.appendSlice(self.allocator, "\"}");
                }
            } else {
                try self.buffer.appendSlice(self.allocator, " [SIG:");
                try self.buffer.appendSlice(self.allocator, &hashHex);
                try self.buffer.append(self.allocator, ']');
            }
        }

        // Terminal presentation coloring for structured formats.
        //
        // Serialization above is always valid on its own; color is applied
        // afterwards as pure presentation, never inside the data:
        // - json/ndjson, horizontal mode: whole rendered record wrapped in
        //   the resolved level color (strip ANSI to recover valid JSON).
        // - json/ndjson, vertical mode: re-rendered with per-field colors
        //   from columnColors (same validity guarantee).
        // - syslog/syslog3164: whole-record wrap in both modes (PRI,
        //   timestamp, and hostname stay byte-identical inside).
        // - text/logfmt color inline in the formatter; msgpack never colors.
        // Multiline records (e.g. pretty JSON) are wrapped whole: one open
        // sequence at the record start, one reset at its end.
        if (Formatter.resolveRecordColor(record, effectiveConfig, self.formatter.theme)) |presColor| {
            const vertical = @hasField(@TypeOf(effectiveConfig), "colorMode") and effectiveConfig.colorMode == .vertical;
            switch (effectiveConfig.format) {
                .json, .ndjson => {
                    if (vertical) {
                        // Re-render the just-written slice (including any
                        // tamper-evident field) with per-field colors.
                        const presSlice = self.buffer.items[recStart..];
                        var tmp = std.Io.Writer.Allocating.init(self.allocator);
                        defer tmp.deinit();
                        try Formatter.writeHighlightedJson(&tmp.writer, presSlice, presColor, effectiveConfig);
                        self.buffer.items.len = recStart;
                        try self.buffer.appendSlice(self.allocator, tmp.written());
                    } else {
                        const seq = Color.sequence(presColor, Color.defaultCapability);
                        try self.buffer.insertSlice(self.allocator, recStart, seq.slice());
                        try self.buffer.appendSlice(self.allocator, Color.resetAll);
                    }
                },
                .syslog, .syslog3164 => {
                    const seq = Color.sequence(presColor, Color.defaultCapability);
                    try self.buffer.insertSlice(self.allocator, recStart, seq.slice());
                    try self.buffer.appendSlice(self.allocator, Color.resetAll);
                },
                else => {},
            }
        }

        if (!useJsonArray) {
            try self.buffer.append(self.allocator, '\n');
        }

        self.bufferedRecords += 1;

        // Flush logic
        if (!self.config.asyncWrite) {
            try self.flush();
        } else {
            if (self.buffer.items.len >= self.config.bufferSize) {
                try self.flush();
            }
        }
    }

    /// Writes one MessagePack record to the sink.
    ///
    /// Binary records are self-delimiting and carry no line terminator:
    /// file/memory sinks store raw concatenation, TCP streams get a
    /// big-endian u32 length prefix per record, UDP sends one datagram per
    /// record (records over 65000 bytes are rejected, never truncated).
    fn writeMsgpackRecord(self: *Sink, record: *const Record, effectiveConfig: anytype) !void {
        var tmp = std.Io.Writer.Allocating.init(self.allocator);
        defer tmp.deinit();
        self.formatter.formatMsgpackToWriter(&tmp.writer, record) catch |err| {
            try self.handleWriteError(err, 1);
            return;
        };
        const bytes = tmp.written();

        if (effectiveConfig.tamperEvident) {
            self.lastRecordHash = Utils.computeChainHash(self.lastRecordHash, bytes);
            if (self.onSignature) |cb| {
                const hashHex = std.fmt.bytesToHex(self.lastRecordHash.?, .lower);
                cb(self.config.name orelse "unnamed_sink", &hashHex);
            }
        }

        if (self.file) |file| {
            if (self.config.asyncWrite) {
                try self.buffer.appendSlice(self.allocator, bytes);
                self.bufferedRecords += 1;
                if (self.buffer.items.len >= self.config.bufferSize) {
                    try self.flush();
                }
            } else {
                if (self.config.mmap) {
                    if (self.mmapFile) |*mmapF| {
                        const oldCapacity = mmapF.capacity;
                        mmapF.write(bytes) catch |err| {
                            try self.handleWriteError(err, 1);
                            return;
                        };
                        if (mmapF.capacity > oldCapacity) {
                            if (self.onMmapResize) |cb| {
                                cb(self.config.name orelse "unnamed_sink", oldCapacity, mmapF.capacity);
                            }
                        }
                    }
                } else {
                    file.writeStreamingAll(Utils.io(), bytes) catch |err| {
                        try self.handleWriteError(err, 1);
                        return;
                    };
                }
                self.noteMsgpackWritten(bytes.len);
            }
        } else if (self.memoryRing) |ring| {
            const idx = self.memoryRingIndex;
            if (ring[idx]) |old| {
                self.allocator.free(old);
            }
            ring[idx] = self.allocator.dupe(u8, bytes) catch |err| {
                try self.handleWriteError(err, 1);
                return;
            };
            self.memoryRingIndex = (idx + 1) % ring.len;
            if (self.memoryRingCount < ring.len) {
                self.memoryRingCount += 1;
            }
            self.noteMsgpackWritten(bytes.len);
        } else if (self.stream) |stream| {
            if (bytes.len > std.math.maxInt(u32)) {
                try self.handleWriteError(error.RecordTooLarge, 1);
                return;
            }
            var hdr: [4]u8 = undefined;
            std.mem.writeInt(u32, &hdr, @intCast(bytes.len), .big);
            writeStreamAll(stream, &hdr) catch |err| {
                try self.handleWriteError(err, 1);
                return;
            };
            writeStreamAll(stream, bytes) catch |err| {
                try self.handleWriteError(err, 1);
                return;
            };
            self.noteMsgpackWritten(4 + bytes.len);
        } else if (self.udpSocket) |sock| {
            if (self.udpAddr) |addr| {
                if (bytes.len > 65000) {
                    try self.handleWriteError(error.DatagramTooLarge, 1);
                    return;
                }
                sock.send(Utils.io(), &addr, bytes) catch |err| {
                    try self.handleWriteError(err, 1);
                    return;
                };
                self.noteMsgpackWritten(bytes.len);
            }
        } else if (self.systemLog) |*syslog| {
            syslog.log(record.level, bytes) catch |err| {
                try self.handleWriteError(err, 1);
                return;
            };
            self.noteMsgpackWritten(bytes.len);
        } else {
            const stdoutFile = std.Io.File.stdout();
            stdoutFile.writeStreamingAll(Utils.io(), bytes) catch |err| {
                try self.handleWriteError(err, 1);
                return;
            };
            self.noteMsgpackWritten(bytes.len);
        }
    }

    /// Records one completed MessagePack write in sink statistics.
    fn noteMsgpackWritten(self: *Sink, byteCount: usize) void {
        _ = self.stats.totalWritten.fetchAdd(1, .monotonic);
        _ = self.stats.bytesWritten.fetchAdd(byteCount, .monotonic);
        self.consecutiveErrors = 0;
        if (self.onWrite) |cb| {
            cb(1, byteCount);
        }
    }

    /// Ensures the sink file holds an open JSON-array document.
    ///
    /// Fresh files gain the opening bracket. Non-empty regular files
    /// continue the existing array: when the file ends with the array tail
    /// ("\n]"), the file offset rewinds over it so the next record
    /// overwrites the tail in place (no truncation needed, no bytes lost).
    /// Anything else is foreign content that appending would corrupt, so
    /// it is rejected with error.JsonArrayAppendUnsupported instead of
    /// silently producing an invalid document. Memory-mapped files always
    /// restart at offset zero, so they unconditionally open fresh.
    pub fn ensureJsonArrayOpen(self: *Sink) !void {
        if (self.jsonArrayOpen) return;
        if (self.mmapFile) |*mmapF| {
            try mmapF.write("[\n");
            self.jsonArrayOpen = true;
            return;
        }
        const file = self.file orelse return error.NoFileForArrayDocument;
        const stat = try file.stat(Utils.io());
        if (stat.size == 0) {
            try file.writeStreamingAll(Utils.io(), "[\n");
        } else if (stat.size >= 2) {
            var rbuf: [8]u8 = undefined;
            var reader = file.reader(Utils.io(), &rbuf);
            try reader.seekTo(stat.size - 2);
            var tail: [2]u8 = undefined;
            var got: usize = 0;
            while (got < 2) {
                const n = try reader.interface.readSliceShort(tail[got..]);
                if (n == 0) break;
                got += n;
            }
            if (got != 2 or !std.mem.eql(u8, &tail, "\n]")) {
                return error.JsonArrayAppendUnsupported;
            }
            var wbuf: [8]u8 = undefined;
            // Streaming (not positional) writer: the rewind must move the
            // shared file offset, since later writes go through
            // writeStreamingAll at that offset.
            var writer = file.writerStreaming(Utils.io(), &wbuf);
            try writer.seekTo(stat.size - 2);
            self.jsonFirstEntry = false;
        } else {
            return error.JsonArrayAppendUnsupported;
        }
        self.jsonArrayOpen = true;
    }

    /// Rotation handoff for memory-mapped files.
    ///
    /// Decides on content bytes (a stat would only see preallocation),
    /// finalizes the mapping beforehand (writes would otherwise keep
    /// landing in the archived file, and rename needs the mapping
    /// released), and re-establishes it on the fresh handle afterwards.
    /// Array framing uses the same tail/header protocol as regular files,
    /// written through the mapping so offsets stay exact.
    fn rotateMmap(self: *Sink, rot: *Rotation, f: *std.Io.File, mmapF: *MmapFile, framing: bool) !void {
        try self.flush();
        if (!rot.rotationDue(f, Utils.currentSeconds(), mmapF.writePtr)) return;

        const oldPtr = mmapF.writePtr;
        if (framing) {
            mmapF.write("\n]") catch |err| {
                try self.handleWriteError(err, 1);
                return;
            };
        }
        mmapF.finalizeForRotation();
        const before = rot.stats.totalRotations.load(.monotonic);
        try rot.checkAndRotate(f);
        if (rot.stats.totalRotations.load(.monotonic) != before) {
            mmapF.remapToFile(self.file.?, 1024 * 1024) catch |err| {
                // Mapping failed: fall back to regular file writes so
                // logging continues on the fresh handle instead of stalling.
                self.config.mmap = false;
                try self.handleWriteError(err, 1);
                return;
            };
            if (framing) {
                mmapF.write("[\n") catch |err| {
                    try self.handleWriteError(err, 1);
                    return;
                };
                self.jsonFirstEntry = true;
                self.jsonArrayOpen = true;
            }
        } else {
            // Rotation did not happen: retract a premature tail and restore
            // the mapping on the unchanged file.
            if (framing) mmapF.writePtr = oldPtr;
            mmapF.resumeMapping();
        }
    }

    /// Applies terminal presentation to an already-serialized record that was
    /// queued by the async pipeline.
    ///
    /// Returns null when this sink must receive the bytes unchanged, which is
    /// the default for files, network targets, binary formats, and any sink
    /// with colors disabled. Only a sink that explicitly asked for color gets
    /// ANSI, and the payload underneath stays valid: horizontal mode wraps the
    /// whole record, vertical mode re-renders per field. Allocation happens
    /// only on the colored path, so the plain path stays allocation-free.
    pub fn applyQueuedPresentation(
        self: *Sink,
        allocator: std.mem.Allocator,
        bytes: []const u8,
        color: Color.Color,
        vertical: bool,
        presentable: bool,
    ) ?[]u8 {
        if (bytes.len == 0) return null;
        // `color` unset means "not requested": only an explicit opt-in (or the
        // console auto-detection already resolved in `init`) colors.
        if (self.config.color orelse false) {} else return null;
        // Text/logfmt render color inline and msgpack must stay byte-exact, so
        // the producer flags eligibility rather than this sink guessing format.
        if (!presentable) return null;

        if (vertical) {
            var tmp = std.Io.Writer.Allocating.init(allocator);
            defer tmp.deinit();
            Formatter.writeHighlightedJson(&tmp.writer, bytes, color, self.config) catch return null;
            return tmp.toOwnedSlice() catch null;
        }

        const seq = Color.sequence(color, Color.defaultCapability);
        var out = std.Io.Writer.Allocating.init(allocator);
        errdefer out.deinit();
        out.writer.writeAll(seq.slice()) catch return null;
        out.writer.writeAll(bytes) catch return null;
        out.writer.writeAll(Color.resetAll) catch return null;
        return out.toOwnedSlice() catch null;
    }

    /// Writes raw data directly to the sink bypassing formatting.
    pub fn writeRaw(self: *Sink, data: []const u8) !void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());

        if (!self.enabled) return;
        if (self.isNullDevice) {
            _ = self.stats.totalWritten.fetchAdd(1, .monotonic);
            _ = self.stats.bytesWritten.fetchAdd(data.len + 1, .monotonic);
            if (self.onWrite) |cb| cb(1, data.len + 1);
            return;
        }

        const bytesWithNewline = data.len + 1;

        if (self.file) |file| {
            if (self.config.asyncWrite) {
                try self.buffer.appendSlice(self.allocator, data);
                try self.buffer.append(self.allocator, '\n');
                self.bufferedRecords += 1;
                if (self.buffer.items.len >= self.config.bufferSize) {
                    try self.flush();
                }
            } else {
                if (self.config.mmap) {
                    if (self.mmapFile) |*mmapF| {
                        const oldCapacity = mmapF.capacity;
                        mmapF.write(data) catch |err| {
                            try self.handleWriteError(err, 1);
                            return;
                        };
                        mmapF.write("\n") catch |err| {
                            try self.handleWriteError(err, 1);
                            return;
                        };
                        if (mmapF.capacity > oldCapacity) {
                            if (self.onMmapResize) |cb| {
                                cb(self.config.name orelse "unnamed_sink", oldCapacity, mmapF.capacity);
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

                _ = self.stats.totalWritten.fetchAdd(1, .monotonic);
                _ = self.stats.bytesWritten.fetchAdd(bytesWithNewline, .monotonic);
                if (self.onWrite) |cb| {
                    cb(1, bytesWithNewline);
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

            _ = self.stats.totalWritten.fetchAdd(1, .monotonic);
            _ = self.stats.bytesWritten.fetchAdd(bytesWithNewline, .monotonic);
            if (self.onWrite) |cb| {
                cb(1, bytesWithNewline);
            }
        } else if (self.udpSocket) |sock| {
            // Datagram framing: one record per datagram, no trailing
            // newline (syslog convention). Oversized payloads are rejected
            // and counted, never silently truncated.
            if (self.udpAddr) |addr| {
                if (data.len > Constants.NetworkConstants.udpMaxPacket) {
                    try self.handleWriteError(error.DatagramTooLarge, 1);
                    return;
                }
                sock.send(Utils.io(), &addr, data) catch |err| {
                    try self.handleWriteError(err, 1);
                    return;
                };

                _ = self.stats.totalWritten.fetchAdd(1, .monotonic);
                _ = self.stats.bytesWritten.fetchAdd(data.len, .monotonic);
                if (self.onWrite) |cb| {
                    cb(1, data.len);
                }
            }
        } else if (self.systemLog) |*syslog| {
            // For raw writes, we assume INFO level if not specified, but Sink.write doesn't take a level.
            // We'll default to INFO.
            syslog.log(.info, data) catch |err| {
                try self.handleWriteError(err, 1);
                return;
            };

            _ = self.stats.totalWritten.fetchAdd(1, .monotonic);
            _ = self.stats.bytesWritten.fetchAdd(data.len, .monotonic);
            if (self.onWrite) |cb| {
                cb(1, data.len);
            }
        } else if (self.memoryRing) |ring| {
            // Memory sinks must capture, never print. Falling through to the
            // stdout branch below would silently leak every queued record to
            // the process console, which both loses the record and corrupts any
            // protocol sharing stdout (Zig's own build-runner test protocol).
            const idx = self.memoryRingIndex;
            if (ring[idx]) |old| {
                self.allocator.free(old);
            }
            ring[idx] = self.allocator.dupe(u8, data) catch |err| {
                try self.handleWriteError(err, 1);
                return;
            };
            self.memoryRingIndex = (idx + 1) % ring.len;
            if (self.memoryRingCount < ring.len) {
                self.memoryRingCount += 1;
            }
            _ = self.stats.totalWritten.fetchAdd(1, .monotonic);
            _ = self.stats.bytesWritten.fetchAdd(bytesWithNewline, .monotonic);
            if (self.onWrite) |cb| cb(1, bytesWithNewline);
        } else {
            const stdoutFile = std.Io.File.stdout();
            stdoutFile.writeStreamingAll(Utils.io(), data) catch |err| {
                try self.handleWriteError(err, 1);
                return;
            };
            stdoutFile.writeStreamingAll(Utils.io(), "\n") catch |err| {
                try self.handleWriteError(err, 1);
                return;
            };

            _ = self.stats.totalWritten.fetchAdd(1, .monotonic);
            _ = self.stats.bytesWritten.fetchAdd(bytesWithNewline, .monotonic);
            if (self.onWrite) |cb| {
                cb(1, bytesWithNewline);
            }
        }
    }

    /// Writes binary data (e.g. MessagePack) without any terminator.
    ///
    /// Unlike writeRaw, no newline is appended: 0x0A is a valid data byte
    /// that would decode as spurious content. Files store raw
    /// concatenation (self-delimiting for MessagePack), TCP streams get a
    /// big-endian u32 length prefix per call, and UDP sends one datagram
    /// per call (oversized payloads rejected, never truncated).
    pub fn writeRawBinary(self: *Sink, data: []const u8) !void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());

        if (!self.enabled) return;
        if (self.isNullDevice) {
            _ = self.stats.totalWritten.fetchAdd(1, .monotonic);
            _ = self.stats.bytesWritten.fetchAdd(data.len, .monotonic);
            if (self.onWrite) |cb| cb(1, data.len);
            return;
        }

        if (self.file) |file| {
            if (self.config.asyncWrite) {
                try self.buffer.appendSlice(self.allocator, data);
                self.bufferedRecords += 1;
                if (self.buffer.items.len >= self.config.bufferSize) {
                    try self.flush();
                }
            } else {
                if (self.config.mmap) {
                    if (self.mmapFile) |*mmapF| {
                        const oldCapacity = mmapF.capacity;
                        mmapF.write(data) catch |err| {
                            try self.handleWriteError(err, 1);
                            return;
                        };
                        if (mmapF.capacity > oldCapacity) {
                            if (self.onMmapResize) |cb| {
                                cb(self.config.name orelse "unnamed_sink", oldCapacity, mmapF.capacity);
                            }
                        }
                    }
                } else {
                    file.writeStreamingAll(Utils.io(), data) catch |err| {
                        try self.handleWriteError(err, 1);
                        return;
                    };
                }

                _ = self.stats.totalWritten.fetchAdd(1, .monotonic);
                _ = self.stats.bytesWritten.fetchAdd(data.len, .monotonic);
                if (self.onWrite) |cb| {
                    cb(1, data.len);
                }
            }
        } else if (self.memoryRing) |ring| {
            const idx = self.memoryRingIndex;
            if (ring[idx]) |old| {
                self.allocator.free(old);
            }
            ring[idx] = self.allocator.dupe(u8, data) catch |err| {
                try self.handleWriteError(err, 1);
                return;
            };
            self.memoryRingIndex = (idx + 1) % ring.len;
            if (self.memoryRingCount < ring.len) {
                self.memoryRingCount += 1;
            }

            _ = self.stats.totalWritten.fetchAdd(1, .monotonic);
            _ = self.stats.bytesWritten.fetchAdd(data.len, .monotonic);
            if (self.onWrite) |cb| {
                cb(1, data.len);
            }
        } else if (self.stream) |stream| {
            if (data.len > std.math.maxInt(u32)) {
                try self.handleWriteError(error.RecordTooLarge, 1);
                return;
            }
            var hdr: [4]u8 = undefined;
            std.mem.writeInt(u32, &hdr, @intCast(data.len), .big);
            writeStreamAll(stream, &hdr) catch |err| {
                try self.handleWriteError(err, 1);
                return;
            };
            writeStreamAll(stream, data) catch |err| {
                try self.handleWriteError(err, 1);
                return;
            };

            _ = self.stats.totalWritten.fetchAdd(1, .monotonic);
            _ = self.stats.bytesWritten.fetchAdd(4 + data.len, .monotonic);
            if (self.onWrite) |cb| {
                cb(1, 4 + data.len);
            }
        } else if (self.udpSocket) |sock| {
            if (self.udpAddr) |addr| {
                if (data.len > Constants.NetworkConstants.udpMaxPacket) {
                    try self.handleWriteError(error.DatagramTooLarge, 1);
                    return;
                }
                sock.send(Utils.io(), &addr, data) catch |err| {
                    try self.handleWriteError(err, 1);
                    return;
                };

                _ = self.stats.totalWritten.fetchAdd(1, .monotonic);
                _ = self.stats.bytesWritten.fetchAdd(data.len, .monotonic);
                if (self.onWrite) |cb| {
                    cb(1, data.len);
                }
            }
        } else if (self.systemLog) |*syslog| {
            syslog.log(.info, data) catch |err| {
                try self.handleWriteError(err, 1);
                return;
            };

            _ = self.stats.totalWritten.fetchAdd(1, .monotonic);
            _ = self.stats.bytesWritten.fetchAdd(data.len, .monotonic);
            if (self.onWrite) |cb| {
                cb(1, data.len);
            }
        } else {
            const stdoutFile = std.Io.File.stdout();
            stdoutFile.writeStreamingAll(Utils.io(), data) catch |err| {
                try self.handleWriteError(err, 1);
                return;
            };

            _ = self.stats.totalWritten.fetchAdd(1, .monotonic);
            _ = self.stats.bytesWritten.fetchAdd(data.len, .monotonic);
            if (self.onWrite) |cb| {
                cb(1, data.len);
            }
        }
    }

    fn reconnect(self: *Sink) bool {
        if (self.stream) |s| s.close(Utils.io());
        self.stream = null;

        if (self.config.path) |uri| {
            if (std.mem.startsWith(u8, uri, "tcp://")) {
                const maxRetries = Constants.TimeDefaults.maxRetries;
                const retrySleep = std.Io.Duration.fromMilliseconds(Constants.TimeDefaults.retryDelayMs);

                var attempt: u32 = 0;
                while (attempt <= maxRetries) : (attempt += 1) {
                    self.stream = Network.connectTcp(self.allocator, uri) catch {
                        if (attempt < maxRetries) {
                            Utils.io().sleep(retrySleep, .awake) catch {};
                        }
                        continue;
                    };
                    return true;
                }
            }
        }
        return false;
    }

    fn handleWriteError(self: *Sink, err: anyerror, recordCount: u64) !void {
        _ = self.stats.writeErrors.fetchAdd(1, .monotonic);
        self.consecutiveErrors += 1;

        if (self.onError) |callback| {
            callback(@errorName(err), recordCount);
        }

        switch (self.config.onError) {
            .silent => {},
            .logStderr => {
                const sinkName = self.config.name orelse "unnamed";
                std.debug.print("[logly:sink:{s}] write error: {s}\n", .{ sinkName, @errorName(err) });
            },
            .disableSink => {
                self.enabled = false;
                if (self.onStateChange) |callback| {
                    callback(false);
                }
            },
            .propagate => return err,
        }
    }

    /// Flushes the internal buffer to storage.
    pub fn flush(self: *Sink) !void {
        if (self.buffer.items.len == 0) return;

        const startNs = Utils.currentNanos();
        const bufferedRecords = if (self.bufferedRecords == 0) @as(u64, 1) else @as(u64, @intCast(self.bufferedRecords));

        // Null-device sink: discard formatted bytes, keep stats for benchmarks.
        if (self.isNullDevice) {
            const bytesFlushed = self.buffer.items.len;
            _ = self.stats.totalWritten.fetchAdd(@min(bufferedRecords, std.math.maxInt(Constants.AtomicUnsigned)), .monotonic);
            _ = self.stats.bytesWritten.fetchAdd(bytesFlushed, .monotonic);
            _ = self.stats.flushCount.fetchAdd(1, .monotonic);
            self.consecutiveErrors = 0;
            if (self.onWrite) |callback| {
                callback(bufferedRecords, bytesFlushed);
            }
            if (self.onFlush) |callback| {
                const endNs = Utils.currentNanos();
                const durationNs: u64 = if (endNs > startNs) @as(u64, @intCast(endNs - startNs)) else 0;
                callback(bytesFlushed, durationNs);
            }
            self.buffer.clearRetainingCapacity();
            self.bufferedRecords = 0;
            return;
        }

        // Memory sink handling
        if (self.memoryRing) |ring| {
            var it = std.mem.splitScalar(u8, self.buffer.items, '\n');
            while (it.next()) |line| {
                if (line.len == 0) continue;
                var trimmed = line;
                if (std.mem.endsWith(u8, trimmed, ",")) {
                    trimmed = trimmed[0 .. trimmed.len - 1];
                }
                trimmed = std.mem.trim(u8, trimmed, " \r\t");
                if (trimmed.len == 0) continue;

                const idx = self.memoryRingIndex;
                if (ring[idx]) |old| {
                    self.allocator.free(old);
                }
                ring[idx] = try self.allocator.dupe(u8, trimmed);
                self.memoryRingIndex = (idx + 1) % ring.len;
                if (self.memoryRingCount < ring.len) {
                    self.memoryRingCount += 1;
                }
            }

            const bufferedRecordsAtomic: Constants.AtomicUnsigned = @intCast(@min(
                bufferedRecords,
                @as(u64, std.math.maxInt(Constants.AtomicUnsigned)),
            ));
            _ = self.stats.totalWritten.fetchAdd(bufferedRecordsAtomic, .monotonic);
            _ = self.stats.bytesWritten.fetchAdd(self.buffer.items.len, .monotonic);
            _ = self.stats.flushCount.fetchAdd(1, .monotonic);
            self.consecutiveErrors = 0;

            if (self.onWrite) |callback| {
                callback(bufferedRecords, self.buffer.items.len);
            }

            self.buffer.clearRetainingCapacity();
            self.bufferedRecords = 0;
            return;
        }

        // Compression for Network Sinks
        var dataToWrite: []const u8 = self.buffer.items;
        var compressedData: ?[]u8 = null;

        if (self.config.compression.enabled and (self.stream != null or self.udpSocket != null)) {
            var list = try std.Io.Writer.Allocating.initCapacity(self.allocator, Constants.BufferSizes.message);
            errdefer list.deinit();

            var compressBuffer: [Constants.BufferSizes.message]u8 = undefined;

            var compressor = try std.compress.flate.Compress.init(&list.writer, &compressBuffer, .raw, .default);

            try compressor.writer.writeAll(self.buffer.items);
            try compressor.finish();

            compressedData = try list.toOwnedSlice();
            dataToWrite = compressedData.?;
        }
        defer if (compressedData) |d| self.allocator.free(d);

        if (self.file) |file| {
            if (self.config.mmap) {
                if (self.mmapFile) |*mmapF| {
                    const oldCapacity = mmapF.capacity;
                    mmapF.write(self.buffer.items) catch |err| {
                        try self.handleWriteError(err, bufferedRecords);
                        self.buffer.clearRetainingCapacity();
                        self.bufferedRecords = 0;
                        return;
                    };
                    if (mmapF.capacity > oldCapacity) {
                        if (self.onMmapResize) |cb| {
                            cb(self.config.name orelse "unnamed_sink", oldCapacity, mmapF.capacity);
                        }
                    }
                    mmapF.flush();
                }
            } else {
                file.writeStreamingAll(Utils.io(), self.buffer.items) catch |err| {
                    try self.handleWriteError(err, bufferedRecords);
                    self.buffer.clearRetainingCapacity();
                    self.bufferedRecords = 0;
                    return;
                };
            }
        } else if (self.stream) |stream| {
            writeStreamAll(stream, dataToWrite) catch |err| {
                if (self.reconnect()) {
                    if (self.stream) |newStream| {
                        writeStreamAll(newStream, dataToWrite) catch |retryErr| {
                            try self.handleWriteError(retryErr, bufferedRecords);
                            self.buffer.clearRetainingCapacity();
                            self.bufferedRecords = 0;
                            return;
                        };
                    } else {
                        try self.handleWriteError(err, bufferedRecords);
                        self.buffer.clearRetainingCapacity();
                        self.bufferedRecords = 0;
                        return;
                    }
                } else {
                    try self.handleWriteError(err, bufferedRecords);
                    self.buffer.clearRetainingCapacity();
                    self.bufferedRecords = 0;
                    return;
                }
            };
        } else if (self.udpSocket) |sock| {
            if (self.udpAddr) |addr| {
                sock.send(Utils.io(), &addr, dataToWrite) catch |err| {
                    try self.handleWriteError(err, bufferedRecords);
                    self.buffer.clearRetainingCapacity();
                    self.bufferedRecords = 0;
                    return;
                };
            }
        } else if (self.systemLog) |*syslog| {
            const msg = self.buffer.items;
            if (msg.len > 0) {
                // Use info level as default for flushed buffers where we lost the record context
                syslog.log(.info, msg) catch |err| {
                    try self.handleWriteError(err, bufferedRecords);
                    self.buffer.clearRetainingCapacity();
                    self.bufferedRecords = 0;
                    return;
                };
            }
        } else {
            // Console
            const stdoutFile = std.Io.File.stdout();
            stdoutFile.writeStreamingAll(Utils.io(), self.buffer.items) catch |err| {
                try self.handleWriteError(err, bufferedRecords);
                self.buffer.clearRetainingCapacity();
                self.bufferedRecords = 0;
                return;
            };
        }

        const bytesFlushed = if (self.file != null) self.buffer.items.len else dataToWrite.len;
        const endNs = Utils.currentNanos();
        const durationNs: u64 = if (endNs > startNs) @as(u64, @intCast(endNs - startNs)) else 0;
        const bufferedRecordsAtomic: Constants.AtomicUnsigned = @intCast(@min(
            bufferedRecords,
            @as(u64, std.math.maxInt(Constants.AtomicUnsigned)),
        ));

        _ = self.stats.totalWritten.fetchAdd(bufferedRecordsAtomic, .monotonic);
        _ = self.stats.bytesWritten.fetchAdd(bytesFlushed, .monotonic);
        _ = self.stats.flushCount.fetchAdd(1, .monotonic);

        if (self.onWrite) |callback| {
            callback(bufferedRecords, bytesFlushed);
        }
        if (self.onFlush) |callback| {
            callback(bytesFlushed, durationNs);
        }

        self.consecutiveErrors = 0;
        self.buffer.clearRetainingCapacity();
        self.bufferedRecords = 0;
    }

    /// Applies per-sink filter configuration to determine if the record should be logged.
    /// Returns true if the record passes all filters, false otherwise.
    fn applyFilterConfig(self: *const Sink, record: *const Record) bool {
        const filter = self.config.filter;

        // Check include_modules - if set, only allow logs from these modules
        if (filter.includeModules) |modules| {
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
        if (filter.excludeModules) |modules| {
            if (record.module) |module| {
                for (modules) |m| {
                    if (std.mem.startsWith(u8, module, m) or std.mem.eql(u8, module, m)) {
                        return false;
                    }
                }
            }
        }

        // Check include_messages - if set, only allow messages containing these substrings
        if (filter.includeMessages) |messages| {
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
        if (filter.excludeMessages) |messages| {
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
    try std.testing.expectEqual(@as(?u64, Constants.SizeConstants.bytesPerKb), Utils.parseSize("1024"));
    try std.testing.expectEqual(@as(?u64, Constants.SizeConstants.bytesPerKb), Utils.parseSize("1KB"));
    try std.testing.expectEqual(@as(?u64, Constants.SizeConstants.bytesPerMb), Utils.parseSize("1MB"));
    try std.testing.expectEqual(@as(?u64, 10 * Constants.SizeConstants.bytesPerMb), Utils.parseSize("10M"));
    try std.testing.expectEqual(@as(?u64, Constants.SizeConstants.bytesPerGb), Utils.parseSize("1GB"));
    try std.testing.expectEqual(@as(?u64, 5 * Constants.SizeConstants.bytesPerGb), Utils.parseSize("5G"));
}

test "sink filtering" {
    const allocator = std.testing.allocator;
    var sinkCfg = SinkConfig.default();
    sinkCfg.filter = .{
        .includeModules = &[_][]const u8{"auth"},
        .excludeMessages = &[_][]const u8{"password"},
    };

    const sink = try Sink.init(allocator, sinkCfg);
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
    const logPath = ".zig-cache/logly-sink-auto-flush-stats.log";

    var sinkCfg = SinkConfig.default();
    sinkCfg.path = logPath;
    sinkCfg.asyncWrite = false;
    sinkCfg.overwriteMode = true;

    const sink = try Sink.init(allocator, sinkCfg);
    defer std.Io.Dir.cwd().deleteFile(Utils.io(), logPath) catch {};
    defer sink.deinit();

    var record = Record.init(allocator, .info, "stats check");
    defer record.deinit();
    record.timestamp = Utils.currentMillis();

    var globalConfig = Config.default();
    globalConfig.autoSink = false;

    try sink.write(&record, globalConfig);

    const stats = sink.getStats();
    try std.testing.expect(stats.getTotalWritten() >= 1);
    try std.testing.expect(stats.getBytesWritten() > 0);
    try std.testing.expect(stats.getFlushCount() >= 1);
    try std.testing.expectEqual(@as(u64, 0), stats.getWriteErrors());
}

test "sink manual flushNow updates stats" {
    const allocator = std.testing.allocator;
    const logPath = ".zig-cache/logly-sink-manual-flush-stats.log";

    var sinkCfg = SinkConfig.default();
    sinkCfg.path = logPath;
    sinkCfg.asyncWrite = true;
    sinkCfg.bufferSize = Constants.BufferSizes.sink;
    sinkCfg.overwriteMode = true;

    const sink = try Sink.init(allocator, sinkCfg);
    defer std.Io.Dir.cwd().deleteFile(Utils.io(), logPath) catch {};
    defer sink.deinit();

    var record = Record.init(allocator, .info, "manual flush stats check");
    defer record.deinit();
    record.timestamp = Utils.currentMillis();

    var globalConfig = Config.default();
    globalConfig.autoSink = false;

    try sink.write(&record, globalConfig);

    const beforeFlushStats = sink.getStats();
    try std.testing.expectEqual(@as(u64, 0), beforeFlushStats.getFlushCount());
    try std.testing.expectEqual(@as(u64, 0), beforeFlushStats.getTotalWritten());

    try sink.flushNow();

    const afterFlushStats = sink.getStats();
    try std.testing.expect(afterFlushStats.getFlushCount() >= 1);
    try std.testing.expect(afterFlushStats.getTotalWritten() >= 1);
    try std.testing.expect(afterFlushStats.getBytesWritten() > 0);
    try std.testing.expectEqual(@as(u64, 0), afterFlushStats.getWriteErrors());
}

test "sink on_error disable_sink disables sink" {
    const allocator = std.testing.allocator;

    var sinkCfg = SinkConfig.default();
    sinkCfg.onError = .disableSink;

    const sink = try Sink.init(allocator, sinkCfg);
    defer sink.deinit();

    const TestError = error{WriteFailed};
    try sink.handleWriteError(TestError.WriteFailed, 1);

    try std.testing.expect(!sink.isEnabled());
    const stats = sink.getStats();
    try std.testing.expectEqual(@as(u64, 1), stats.getWriteErrors());
}

test "sink on_error propagate returns error" {
    const allocator = std.testing.allocator;

    var sinkCfg = SinkConfig.default();
    sinkCfg.onError = .propagate;

    const sink = try Sink.init(allocator, sinkCfg);
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

    pub fn write(self: *SinkGroup, record: *const Record, globalConfig: anytype) !void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());

        for (self.sinks.items) |sink| {
            try sink.write(record, globalConfig);
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

    var s1Cfg = SinkConfig.memory();
    s1Cfg.name = "s1";
    const s1 = try Sink.init(allocator, s1Cfg);
    defer s1.deinit();

    var s2Cfg = SinkConfig.memory();
    s2Cfg.name = "s2";
    const s2 = try Sink.init(allocator, s2Cfg);
    defer s2.deinit();

    try group.addSink(s1);
    try group.addSink(s2);

    var record = Record.init(allocator, .info, "sink group check");
    defer record.deinit();
    record.timestamp = 0;

    var globalConfig = Config.default();
    globalConfig.autoSink = false;

    try group.write(&record, globalConfig);
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

    var sinkCfg = SinkConfig.memory();
    sinkCfg.name = "tamper_evident_sink";
    sinkCfg.tamperEvident = true;

    const sink = try Sink.init(allocator, sinkCfg);
    defer sink.deinit();

    var record1 = Record.init(allocator, .info, "first log record");
    defer record1.deinit();
    record1.timestamp = 1000;

    var globalConfig = Config.default();
    globalConfig.autoSink = false;

    try sink.write(&record1, globalConfig);
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

    try sink.write(&record2, globalConfig);
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

test "sink format inherits global unless overridden" {
    const allocator = std.testing.allocator;

    var record = Record.init(allocator, .info, "hello");
    defer record.deinit();
    record.timestamp = 1700000000000;

    var globalConfig = Config.default();
    globalConfig.autoSink = false;
    globalConfig.format = .ndjson;

    // Default sink inherits the logger-wide format.
    {
        const sink = try Sink.init(allocator, SinkConfig.memory());
        defer sink.deinit();
        try sink.write(&record, globalConfig);
        try sink.flush();
        const msgs = try sink.getMemoryMessages(allocator);
        defer {
            for (msgs) |msg| allocator.free(msg);
            allocator.free(msgs);
        }
        try std.testing.expectEqual(@as(usize, 1), msgs.len);
        try std.testing.expect(std.mem.startsWith(u8, msgs[0], "{\"timestamp\""));
    }

    // Explicit per-sink format wins over the inherited one.
    {
        var cfg = SinkConfig.memory();
        cfg.format = .logfmt;
        const sink = try Sink.init(allocator, cfg);
        defer sink.deinit();
        try sink.write(&record, globalConfig);
        try sink.flush();
        const msgs = try sink.getMemoryMessages(allocator);
        defer {
            for (msgs) |msg| allocator.free(msg);
            allocator.free(msgs);
        }
        try std.testing.expectEqual(@as(usize, 1), msgs.len);
        try std.testing.expect(std.mem.startsWith(u8, msgs[0], "ts="));
    }
}

/// Strips ANSI SGR sequences (sink test helper only).
fn stripAnsiSinkForTest(allocator: std.mem.Allocator, s: []const u8) ![]u8 {
    var out = std.Io.Writer.Allocating.init(allocator);
    errdefer out.deinit();
    var i: usize = 0;
    while (i < s.len) {
        if (s[i] == 0x1b and i + 1 < s.len and s[i + 1] == '[') {
            i += 2;
            while (i < s.len and s[i] != 'm') : (i += 1) {}
            i += @intFromBool(i < s.len);
        } else {
            try out.writer.writeByte(s[i]);
            i += 1;
        }
    }
    return out.toOwnedSlice();
}

test "sink json horizontal presentation wraps line" {
    const allocator = std.testing.allocator;

    var record = Record.init(allocator, .warning, "hello");
    defer record.deinit();
    record.timestamp = 1700000000000;

    var globalConfig = Config.default();
    globalConfig.autoSink = false;
    globalConfig.format = .json;

    var cfg = SinkConfig.memory();
    cfg.color = true;
    const sink = try Sink.init(allocator, cfg);
    defer sink.deinit();
    try sink.write(&record, globalConfig);
    try sink.flush();
    const msgs = try sink.getMemoryMessages(allocator);
    defer {
        for (msgs) |msg| allocator.free(msg);
        allocator.free(msgs);
    }
    try std.testing.expectEqual(@as(usize, 1), msgs.len);

    const seq = Color.sequence(Color.Tint.color.ansi4.yellow, Color.defaultCapability);
    try std.testing.expect(std.mem.startsWith(u8, msgs[0], seq.slice()));
    try std.testing.expect(std.mem.endsWith(u8, msgs[0], Color.resetAll));
    // Strip presentation -> byte-identical valid JSON.
    const stripped = try stripAnsiSinkForTest(allocator, msgs[0]);
    defer allocator.free(stripped);
    var formatter = Formatter.init(allocator);
    defer formatter.deinit();
    const plain = try formatter.formatJson(&record, globalConfig);
    defer allocator.free(plain);
    try std.testing.expectEqualStrings(plain, stripped);
}

test "sink json vertical presentation highlights keys" {
    const allocator = std.testing.allocator;

    var record = Record.init(allocator, .info, "hello");
    defer record.deinit();
    record.timestamp = 1700000000000;

    var globalConfig = Config.default();
    globalConfig.autoSink = false;
    globalConfig.format = .json;
    globalConfig.colorMode = .vertical;
    globalConfig.columnColors.message = Color.Tint.color.ansi4.green;

    var cfg = SinkConfig.memory();
    cfg.color = true;
    const sink = try Sink.init(allocator, cfg);
    defer sink.deinit();
    try sink.write(&record, globalConfig);
    try sink.flush();
    const msgs = try sink.getMemoryMessages(allocator);
    defer {
        for (msgs) |msg| allocator.free(msg);
        allocator.free(msgs);
    }
    try std.testing.expectEqual(@as(usize, 1), msgs.len);
    try std.testing.expect(std.mem.endsWith(u8, msgs[0], Color.resetAll));
    const keySeq = Color.sequence(Color.Tint.color.ansi4.green, Color.defaultCapability);
    try std.testing.expect(std.mem.indexOf(u8, msgs[0], keySeq.slice()) != null);
    try std.testing.expect(std.mem.indexOf(u8, msgs[0], "\"message\"") != null);
    const stripped = try stripAnsiSinkForTest(allocator, msgs[0]);
    defer allocator.free(stripped);
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, stripped, .{});
    defer parsed.deinit();
    try std.testing.expect(parsed.value == .object);
}

test "sink syslog horizontal presentation wraps line" {
    const allocator = std.testing.allocator;

    var record = Record.init(allocator, .err, "disk failing");
    defer record.deinit();
    record.timestamp = 1700000000000;

    var globalConfig = Config.default();
    globalConfig.autoSink = false;
    globalConfig.format = .syslog;

    var cfg = SinkConfig.memory();
    cfg.color = true;
    const sink = try Sink.init(allocator, cfg);
    defer sink.deinit();
    try sink.write(&record, globalConfig);
    try sink.flush();
    const msgs = try sink.getMemoryMessages(allocator);
    defer {
        for (msgs) |msg| allocator.free(msg);
        allocator.free(msgs);
    }
    try std.testing.expectEqual(@as(usize, 1), msgs.len);
    // PRI/timestamp/host bytes intact inside the wrap.
    try std.testing.expect(std.mem.indexOf(u8, msgs[0], "<11>1 ") != null);
    try std.testing.expect(std.mem.endsWith(u8, msgs[0], Color.resetAll));
}

test "sink msgpack never carries color" {
    const allocator = std.testing.allocator;

    var record = Record.init(allocator, .info, "binary");
    defer record.deinit();
    record.timestamp = 1700000000000;

    var globalConfig = Config.default();
    globalConfig.autoSink = false;
    globalConfig.format = .msgpack;

    var cfg = SinkConfig.memory();
    cfg.color = true;
    const sink = try Sink.init(allocator, cfg);
    defer sink.deinit();
    try sink.write(&record, globalConfig);
    try sink.flush();
    const msgs = try sink.getMemoryMessages(allocator);
    defer {
        for (msgs) |msg| allocator.free(msg);
        allocator.free(msgs);
    }
    try std.testing.expectEqual(@as(usize, 1), msgs.len);
    var formatter = Formatter.init(allocator);
    defer formatter.deinit();
    const expected = try formatter.formatMsgpack(&record, globalConfig);
    defer allocator.free(expected);
    try std.testing.expectEqualStrings(expected, msgs[0]);
}

test "sink color none emits zero ansi" {
    const allocator = std.testing.allocator;

    var record = Record.init(allocator, .critical, "boom");
    defer record.deinit();
    record.timestamp = 1700000000000;

    var globalConfig = Config.default();
    globalConfig.autoSink = false;
    globalConfig.format = .json;
    globalConfig.color = true;
    globalConfig.globalColorDisplay = true;
    globalConfig.colorMode = .none;

    var cfg = SinkConfig.memory();
    cfg.color = true;
    const sink = try Sink.init(allocator, cfg);
    defer sink.deinit();
    try sink.write(&record, globalConfig);
    try sink.flush();
    const msgs = try sink.getMemoryMessages(allocator);
    defer {
        for (msgs) |msg| allocator.free(msg);
        allocator.free(msgs);
    }
    try std.testing.expectEqual(@as(usize, 1), msgs.len);
    for (msgs[0]) |b| {
        try std.testing.expect(b != 0x1b);
    }
}

test "sink auto console color decision" {
    try std.testing.expect(Sink.autoConsoleColor(null, true));
    try std.testing.expect(!Sink.autoConsoleColor(null, false));
    try std.testing.expect(Sink.autoConsoleColor(true, false));
    try std.testing.expect(!Sink.autoConsoleColor(false, true));
}

test "sink per sink color isolation" {
    const allocator = std.testing.allocator;

    var record = Record.init(allocator, .err, "isolated");
    defer record.deinit();
    record.timestamp = 1700000000000;

    var globalConfig = Config.default();
    globalConfig.autoSink = false;
    globalConfig.format = .json;

    var coloredCfg = SinkConfig.memory();
    coloredCfg.color = true;
    const colored = try Sink.init(allocator, coloredCfg);
    defer colored.deinit();

    // Memory sinks inherit the global display flag, so opt out explicitly.
    var plainCfg = SinkConfig.memory();
    plainCfg.color = false;
    const plain = try Sink.init(allocator, plainCfg);
    defer plain.deinit();

    try colored.write(&record, globalConfig);
    try colored.flush();
    try plain.write(&record, globalConfig);
    try plain.flush();

    const cMsgs = try colored.getMemoryMessages(allocator);
    defer {
        for (cMsgs) |msg| allocator.free(msg);
        allocator.free(cMsgs);
    }
    const pMsgs = try plain.getMemoryMessages(allocator);
    defer {
        for (pMsgs) |msg| allocator.free(msg);
        allocator.free(pMsgs);
    }
    try std.testing.expect(!std.mem.eql(u8, cMsgs[0], pMsgs[0]));
    for (pMsgs[0]) |b| {
        try std.testing.expect(b != 0x1b);
    }
    const stripped = try stripAnsiSinkForTest(allocator, cMsgs[0]);
    defer allocator.free(stripped);
    try std.testing.expectEqualStrings(pMsgs[0], stripped);
}

test "sink pretty json presentation spans lines safely" {
    const allocator = std.testing.allocator;

    var record = Record.init(allocator, .info, "multi");
    defer record.deinit();
    record.timestamp = 1700000000000;

    var globalConfig = Config.default();
    globalConfig.autoSink = false;
    globalConfig.format = .json;
    globalConfig.prettyJson = true;

    var cfg = SinkConfig.memory();
    cfg.color = true;
    const sink = try Sink.init(allocator, cfg);
    defer sink.deinit();
    try sink.write(&record, globalConfig);
    try sink.flush();
    const msgs = try sink.getMemoryMessages(allocator);
    defer {
        for (msgs) |msg| allocator.free(msg);
        allocator.free(msgs);
    }
    // First line opens color, last line closes it: no bleed either way.
    // (The memory ring splits pretty output per line, so per-line content
    // is asserted here; byte-identical validity is covered at formatter
    // level, where no line splitting happens.)
    const infoSeq = Color.sequence(Color.Tint.color.ansi4.white, Color.defaultCapability);
    try std.testing.expect(std.mem.startsWith(u8, msgs[0], infoSeq.slice()));
    try std.testing.expect(std.mem.endsWith(u8, msgs[msgs.len - 1], Color.resetAll));
}

test "sink multiline text wrap has no bleed" {
    const allocator = std.testing.allocator;

    var record = Record.init(allocator, .warning, "first\nsecond");
    defer record.deinit();
    record.timestamp = 1700000000000;

    var globalConfig = Config.default();
    globalConfig.autoSink = false;
    globalConfig.format = .text;

    var cfg = SinkConfig.memory();
    cfg.color = true;
    const sink = try Sink.init(allocator, cfg);
    defer sink.deinit();
    try sink.write(&record, globalConfig);
    try sink.flush();
    const msgs = try sink.getMemoryMessages(allocator);
    defer {
        for (msgs) |msg| allocator.free(msg);
        allocator.free(msgs);
    }
    try std.testing.expectEqual(@as(usize, 2), msgs.len);
    const warnSeq = Color.sequence(Color.Tint.color.ansi4.yellow, Color.defaultCapability);
    try std.testing.expect(std.mem.startsWith(u8, msgs[0], warnSeq.slice()));
    try std.testing.expect(std.mem.endsWith(u8, msgs[msgs.len - 1], Color.resetAll));
    // Rejoin and strip: the underlying text record is intact.
    var joined = std.Io.Writer.Allocating.init(allocator);
    defer joined.deinit();
    for (msgs, 0..) |m, idx| {
        const s = try stripAnsiSinkForTest(allocator, m);
        defer allocator.free(s);
        if (idx > 0) try joined.writer.writeByte('\n');
        try joined.writer.writeAll(s);
    }
    var formatter = Formatter.init(allocator);
    defer formatter.deinit();
    var plainConfig = Config.default();
    plainConfig.color = false;
    const plain = try formatter.format(&record, plainConfig);
    defer allocator.free(plain);
    try std.testing.expectEqualStrings(plain, joined.written());
}

test "sink custom level color presents" {
    const allocator = std.testing.allocator;

    var record = Record.init(allocator, .info, "audit event");
    defer record.deinit();
    record.timestamp = 1700000000000;
    record.customLevelName = "AUDIT";
    record.customLevelColor = Color.Tint.color.ansi4.magenta;

    var globalConfig = Config.default();
    globalConfig.autoSink = false;
    globalConfig.format = .json;

    var cfg = SinkConfig.memory();
    cfg.color = true;
    const sink = try Sink.init(allocator, cfg);
    defer sink.deinit();
    try sink.write(&record, globalConfig);
    try sink.flush();
    const msgs = try sink.getMemoryMessages(allocator);
    defer {
        for (msgs) |msg| allocator.free(msg);
        allocator.free(msgs);
    }
    const magSeq = Color.sequence(Color.Tint.color.ansi4.magenta, Color.defaultCapability);
    try std.testing.expect(std.mem.startsWith(u8, msgs[0], magSeq.slice()));
    try std.testing.expect(std.mem.indexOf(u8, msgs[0], "\"AUDIT\"") != null);
}

test "sink tamper evident keeps json valid" {
    const allocator = std.testing.allocator;

    var sinkCfg = SinkConfig.memory();
    sinkCfg.tamperEvident = true;

    const sink = try Sink.init(allocator, sinkCfg);
    defer sink.deinit();

    var record = Record.init(allocator, .warning, "audit me");
    defer record.deinit();
    record.timestamp = 1700000000000;

    var globalConfig = Config.default();
    globalConfig.autoSink = false;
    globalConfig.format = .json;

    try sink.write(&record, globalConfig);
    try sink.flush();

    const msgs = try sink.getMemoryMessages(allocator);
    defer {
        for (msgs) |msg| allocator.free(msg);
        allocator.free(msgs);
    }

    try std.testing.expectEqual(@as(usize, 1), msgs.len);
    // Signature is a real JSON field, not a /* comment */.
    try std.testing.expect(std.mem.indexOf(u8, msgs[0], "\"sig\":\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, msgs[0], "/*") == null);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, msgs[0], .{});
    defer parsed.deinit();
    try std.testing.expect(parsed.value == .object);
    try std.testing.expect(parsed.value.object.get("sig") != null);
    try std.testing.expectEqualStrings("audit me", parsed.value.object.get("message").?.string);
}

test "sink json array append continues the document" {
    const allocator = std.testing.allocator;

    const fileName = try std.fmt.allocPrint(allocator, "test_json_cont_{d}.log", .{Utils.currentMillis()});
    defer allocator.free(fileName);
    defer std.Io.Dir.cwd().deleteFile(Utils.io(), fileName) catch {};

    var globalConfig = Config.default();
    globalConfig.autoSink = false;
    globalConfig.format = .json;

    // First session: two records, closed document on deinit.
    {
        var sinkCfg = SinkConfig.file(fileName);
        sinkCfg.asyncWrite = false;
        const sink = try Sink.init(allocator, sinkCfg);
        defer sink.deinit();
        var i: usize = 0;
        while (i < 2) : (i += 1) {
            var record = Record.init(allocator, .info, "first session");
            defer record.deinit();
            record.timestamp = 1700000000000;
            try sink.write(&record, globalConfig);
        }
        try sink.flush();
    }

    // Second session appends: the tail is rewound, no second header.
    {
        var sinkCfg = SinkConfig.file(fileName);
        sinkCfg.asyncWrite = false;
        const sink = try Sink.init(allocator, sinkCfg);
        defer sink.deinit();
        var record = Record.init(allocator, .info, "second session");
        defer record.deinit();
        record.timestamp = 1700000000001;
        try sink.write(&record, globalConfig);
        try sink.flush();
    }

    var file = try std.Io.Dir.cwd().openFile(Utils.io(), fileName, .{});
    defer file.close(Utils.io());
    const stat = try file.stat(Utils.io());
    const bytes = try allocator.alloc(u8, stat.size);
    defer allocator.free(bytes);
    var readBuf: [4096]u8 = undefined;
    var reader = file.reader(Utils.io(), &readBuf);
    var total: usize = 0;
    while (total < bytes.len) {
        const n = try reader.interface.readSliceShort(bytes[total..]);
        if (n == 0) break;
        total += n;
    }
    // Exactly one opening bracket: continuation, not a nested document.
    var opens: usize = 0;
    for (bytes[0..total]) |b| {
        if (b == '[') opens += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), opens);
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, bytes[0..total], .{});
    defer parsed.deinit();
    try std.testing.expect(parsed.value == .array);
    try std.testing.expectEqual(@as(usize, 3), parsed.value.array.items.len);
}

test "sink json array rejects foreign append content" {
    const allocator = std.testing.allocator;

    const fileName = try std.fmt.allocPrint(allocator, "test_json_foreign_{d}.log", .{Utils.currentMillis()});
    defer allocator.free(fileName);
    defer std.Io.Dir.cwd().deleteFile(Utils.io(), fileName) catch {};

    {
        var file = try std.Io.Dir.cwd().createFile(Utils.io(), fileName, .{});
        defer file.close(Utils.io());
        try file.writeStreamingAll(Utils.io(), "not a json array document\n");
    }

    var sinkCfg = SinkConfig.file(fileName);
    sinkCfg.format = .json;
    try std.testing.expectError(error.JsonArrayAppendUnsupported, Sink.init(allocator, sinkCfg));
}

test "sink mmap json rotation remaps and frames" {
    const allocator = std.testing.allocator;

    const baseName = try std.fmt.allocPrint(allocator, "test_mmap_rot_{d}.log", .{Utils.currentMillis()});
    defer allocator.free(baseName);
    defer {
        if (std.Io.Dir.cwd().openDir(Utils.io(), ".", .{ .iterate = true })) |*dir| {
            defer dir.close(Utils.io());
            var iter = dir.iterate();
            while (iter.next(Utils.io()) catch null) |entry| {
                if (entry.kind != .file) continue;
                if (std.mem.startsWith(u8, entry.name, baseName)) {
                    const full = std.fs.path.join(allocator, &.{ ".", entry.name }) catch continue;
                    defer allocator.free(full);
                    std.Io.Dir.cwd().deleteFile(Utils.io(), full) catch {};
                }
            }
        } else |_| {}
    }

    var globalConfig = Config.default();
    globalConfig.autoSink = false;
    globalConfig.format = .json;

    var sinkCfg = SinkConfig.file(baseName);
    sinkCfg.mmap = true;
    sinkCfg.asyncWrite = false;
    sinkCfg.sizeLimit = 128;
    sinkCfg.retention = 8;

    {
        const sink = try Sink.init(allocator, sinkCfg);
        defer sink.deinit();
        var i: usize = 0;
        while (i < 10) : (i += 1) {
            var record = Record.init(allocator, .info, "mmap rotation record");
            defer record.deinit();
            record.timestamp = 1700000000000;
            try sink.write(&record, globalConfig);
        }
        try sink.flush();
        // Marker proves post-rotation writes land in the active file,
        // which requires the mapping to follow the fresh handle.
        var marker = Record.init(allocator, .info, "post rotation marker");
        defer marker.deinit();
        marker.timestamp = 1700000000001;
        try sink.write(&marker, globalConfig);
        try sink.flush();
    }

    // Active file plus at least one rotated sibling, all valid arrays,
    // and the marker is in the active file (not stranded in an archive).
    var checked: usize = 0;
    var markerInActive = false;
    var dir = try std.Io.Dir.cwd().openDir(Utils.io(), ".", .{ .iterate = true });
    defer dir.close(Utils.io());
    var iter = dir.iterate();
    while (try iter.next(Utils.io())) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.startsWith(u8, entry.name, baseName)) continue;
        const full = try std.fs.path.join(allocator, &.{ ".", entry.name });
        defer allocator.free(full);
        var file = try std.Io.Dir.cwd().openFile(Utils.io(), full, .{});
        defer file.close(Utils.io());
        const stat = try file.stat(Utils.io());
        const bytes = try allocator.alloc(u8, stat.size);
        defer allocator.free(bytes);
        var readBuf: [4096]u8 = undefined;
        var reader = file.reader(Utils.io(), &readBuf);
        var total: usize = 0;
        while (total < bytes.len) {
            const n = try reader.interface.readSliceShort(bytes[total..]);
            if (n == 0) break;
            total += n;
        }
        const parsed = try std.json.parseFromSlice(std.json.Value, allocator, bytes[0..total], .{});
        defer parsed.deinit();
        try std.testing.expect(parsed.value == .array);
        try std.testing.expect(parsed.value.array.items.len > 0);
        checked += 1;
        if (std.mem.eql(u8, entry.name, baseName)) {
            markerInActive = std.mem.indexOf(u8, bytes[0..total], "post rotation marker") != null;
        }
    }
    try std.testing.expect(checked >= 2);
    try std.testing.expect(markerInActive);
}

test "sink msgpack file output" {
    const allocator = std.testing.allocator;

    const fileName = "test_msgpack_sink.msgpack";
    defer std.Io.Dir.cwd().deleteFile(Utils.io(), fileName) catch {};

    var sinkCfg = SinkConfig.file(fileName);
    sinkCfg.format = .msgpack;
    sinkCfg.asyncWrite = false;

    const sink = try Sink.init(allocator, sinkCfg);
    defer sink.deinit();

    var record = Record.init(allocator, .info, "binary record");
    defer record.deinit();
    record.timestamp = 1700000000000;

    var globalConfig = Config.default();
    globalConfig.autoSink = false;

    try sink.write(&record, globalConfig);
    try sink.flush();

    // Two records concatenate into one decodable stream.
    var record2 = Record.init(allocator, .err, "second");
    defer record2.deinit();
    record2.timestamp = 1700000000001;
    try sink.write(&record2, globalConfig);
    try sink.flush();

    var file = try std.Io.Dir.cwd().openFile(Utils.io(), fileName, .{});
    defer file.close(Utils.io());
    const stat = try file.stat(Utils.io());
    const bytes = try allocator.alloc(u8, stat.size);
    defer allocator.free(bytes);
    var readBuf: [4096]u8 = undefined;
    var reader = file.reader(Utils.io(), &readBuf);
    var total: usize = 0;
    while (total < bytes.len) {
        const n = try reader.interface.readSliceShort(bytes[total..]);
        if (n == 0) break;
        total += n;
    }
    try std.testing.expect(total > 0);
    try std.testing.expectEqual(@as(u8, 0x87), bytes[0]);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "binary record") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "second") != null);
}

test "sink json array rotation keeps documents valid" {
    const allocator = std.testing.allocator;

    const baseName = try std.fmt.allocPrint(allocator, "test_json_rot_{d}.log", .{Utils.currentMillis()});
    defer allocator.free(baseName);
    defer {
        // Best-effort cleanup of the active file plus any rotated siblings.
        if (std.Io.Dir.cwd().openDir(Utils.io(), ".", .{ .iterate = true })) |*dir| {
            defer dir.close(Utils.io());
            var iter = dir.iterate();
            while (iter.next(Utils.io()) catch null) |entry| {
                if (entry.kind != .file) continue;
                if (std.mem.startsWith(u8, entry.name, baseName)) {
                    const full = std.fs.path.join(allocator, &.{ ".", entry.name }) catch continue;
                    defer allocator.free(full);
                    std.Io.Dir.cwd().deleteFile(Utils.io(), full) catch {};
                }
            }
        } else |_| {}
    }

    var sinkCfg = SinkConfig.file(baseName);
    sinkCfg.format = .json;
    sinkCfg.asyncWrite = false;
    sinkCfg.sizeLimit = 64;
    sinkCfg.retention = 8;

    {
        const sink = try Sink.init(allocator, sinkCfg);
        defer sink.deinit();

        var globalConfig = Config.default();
        globalConfig.autoSink = false;

        var i: usize = 0;
        while (i < 12) : (i += 1) {
            var record = Record.init(allocator, .info, "rotation framing record");
            defer record.deinit();
            record.timestamp = 1700000000000;
            try sink.write(&record, globalConfig);
        }
        try sink.flush();
    }

    // Every JSON-array file on disk (active + rotated) must parse standalone.
    var checked: usize = 0;
    var dir = try std.Io.Dir.cwd().openDir(Utils.io(), ".", .{ .iterate = true });
    defer dir.close(Utils.io());
    var iter = dir.iterate();
    while (try iter.next(Utils.io())) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.startsWith(u8, entry.name, baseName)) continue;
        const full = try std.fs.path.join(allocator, &.{ ".", entry.name });
        defer allocator.free(full);
        var file = try std.Io.Dir.cwd().openFile(Utils.io(), full, .{});
        defer file.close(Utils.io());
        const stat = try file.stat(Utils.io());
        const bytes = try allocator.alloc(u8, stat.size);
        defer allocator.free(bytes);
        var readBuf: [4096]u8 = undefined;
        var reader = file.reader(Utils.io(), &readBuf);
        var total: usize = 0;
        while (total < bytes.len) {
            const n = try reader.interface.readSliceShort(bytes[total..]);
            if (n == 0) break;
            total += n;
        }
        const parsed = try std.json.parseFromSlice(std.json.Value, allocator, bytes[0..total], .{});
        defer parsed.deinit();
        try std.testing.expect(parsed.value == .array);
        try std.testing.expect(parsed.value.array.items.len > 0);
        checked += 1;
    }
    try std.testing.expect(checked >= 2);
}

/// A memory-mapped file abstraction for extremely high-performance logging.
/// Supports native memory mapping on Windows and POSIX (Linux, macOS) systems,
/// with automatic dynamic resizing/remapping and graceful fallback.
pub const MmapFile = struct {
    file: std.Io.File,
    memory: []align(std.heap.page_size_min) u8 = &.{},
    writePtr: usize = 0,
    capacity: usize = 0,
    allocator: std.mem.Allocator,
    isMapped: bool = false,

    // Platform-specific fields
    mappingHandle: if (builtin.os.tag == .windows) ?std.os.windows.HANDLE else void = if (builtin.os.tag == .windows) null else {},

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

    pub fn init(allocator: std.mem.Allocator, file: std.Io.File, initialSize: usize) !MmapFile {
        const io = Utils.io();
        // Pre-allocate / grow file
        try file.setLength(io, initialSize);

        var self = MmapFile{
            .allocator = allocator,
            .file = file,
            .writePtr = 0,
            .capacity = initialSize,
        };

        self.map() catch {
            self.isMapped = false;
        };

        return self;
    }

    pub fn deinit(self: *MmapFile) void {
        self.unmap();
        // Truncate file to actual bytes written before closing
        const io = Utils.io();
        self.file.setLength(io, self.writePtr) catch {};
    }

    pub fn write(self: *MmapFile, data: []const u8) !void {
        if (!self.isMapped) {
            // Fallback to standard file write
            const io = Utils.io();
            try self.file.writeStreamingAll(io, data);
            self.writePtr += data.len;
            return;
        }

        if (self.writePtr + data.len > self.capacity) {
            // Grow file and remap
            const newCapacity = self.capacity * 2 + data.len;
            try self.grow(newCapacity);
        }

        @memcpy(self.memory[self.writePtr..][0..data.len], data);
        self.writePtr += data.len;
    }

    pub fn flush(self: *MmapFile) void {
        if (!self.isMapped) return;

        if (builtin.os.tag == .windows) {
            _ = win32.FlushViewOfFile(self.memory.ptr, self.writePtr);
        } else {
            // POSIX msync (MS_ASYNC = 1)
            std.posix.msync(self.memory, 1) catch {};
        }
    }

    /// Prepares the mapping for log rotation: syncs, releases the mapping,
    /// then truncates the file to the bytes actually written (so the
    /// archive carries no zero padding). The mapping must be released
    /// before truncate/rename: truncating a mapped file fails on some
    /// platforms, and renaming needs the mapping released, notably on
    /// Windows. writePtr is preserved so a failed rotation can resume.
    /// Files never mapped (fallback mode) keep their layout untouched.
    pub fn finalizeForRotation(self: *MmapFile) void {
        self.flush();
        if (!self.isMapped) return;
        self.unmap();
        self.file.setLength(Utils.io(), self.writePtr) catch {};
    }

    /// Maps onto a fresh file handle after rotation (the previous file was
    /// renamed away). Resets the write offset and preallocates like init.
    pub fn remapToFile(self: *MmapFile, newFile: std.Io.File, initialSize: usize) !void {
        self.file = newFile;
        self.writePtr = 0;
        self.capacity = initialSize;
        try newFile.setLength(Utils.io(), initialSize);
        self.map() catch {
            self.isMapped = false;
        };
    }

    /// Re-establishes the mapping on the current file after rotation did
    /// not happen. The file is untouched; only the mapping is restored.
    /// Call only after finalizeForRotation on the same file.
    pub fn resumeMapping(self: *MmapFile) void {
        self.map() catch {
            self.isMapped = false;
        };
    }

    fn map(self: *MmapFile) !void {
        if (self.capacity == 0) return;

        if (builtin.os.tag == .windows) {
            const h = win32.CreateFileMappingW(self.file.handle, null, 4, 0, @intCast(self.capacity), null) orelse return error.MmapFailed;
            self.mappingHandle = h;
            errdefer {
                _ = std.os.windows.CloseHandle(h);
                self.mappingHandle = null;
            }

            const ptr = win32.MapViewOfFile(h, 2, 0, 0, self.capacity) orelse return error.MmapFailed;
            const alignedPtr = @as([*]align(std.heap.page_size_min) u8, @ptrCast(@alignCast(ptr)));
            self.memory = alignedPtr[0..self.capacity];
            self.isMapped = true;
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
            self.isMapped = true;
        }
    }

    fn unmap(self: *MmapFile) void {
        if (!self.isMapped) return;

        if (builtin.os.tag == .windows) {
            _ = win32.UnmapViewOfFile(self.memory.ptr);
            if (self.mappingHandle) |h| {
                _ = std.os.windows.CloseHandle(h);
                self.mappingHandle = null;
            }
        } else {
            std.posix.munmap(self.memory);
        }
        self.memory = &.{};
        self.isMapped = false;
    }

    pub fn grow(self: *MmapFile, newCapacity: usize) !void {
        const alignedCapacity = std.mem.alignForward(usize, newCapacity, std.heap.page_size_min);
        self.unmap();

        const io = Utils.io();
        try self.file.setLength(io, alignedCapacity);
        self.capacity = alignedCapacity;

        try self.map();
    }
};

test "sink memory-mapped file sink" {
    const allocator = std.testing.allocator;

    const testPath = "mmap_test.log";
    std.Io.Dir.cwd().deleteFile(Utils.io(), testPath) catch {};
    defer std.Io.Dir.cwd().deleteFile(Utils.io(), testPath) catch {};

    var sinkCfg = SinkConfig.file(testPath);
    sinkCfg.name = "mmap_sink";
    sinkCfg.mmap = true;
    sinkCfg.asyncWrite = false; // direct write

    const sink = try Sink.init(allocator, sinkCfg);
    errdefer sink.deinit();

    var record1 = Record.init(allocator, .info, "first mmap log message");
    defer record1.deinit();
    record1.timestamp = 1000;

    var globalConfig = Config.default();
    globalConfig.autoSink = false;

    try sink.write(&record1, globalConfig);
    try sink.flush();

    // Deinitialize here to flush, unmap, and truncate the file on disk
    sink.deinit();

    // Verify the file content by reading it back
    const fileContent = try std.Io.Dir.cwd().readFileAlloc(Utils.io(), testPath, allocator, .limited(Constants.BufferSizes.fileRead));
    defer allocator.free(fileContent);

    try std.testing.expect(std.mem.indexOf(u8, fileContent, "first mmap log message") != null);
}

var testSigCalled: bool = false;
var testSigValue: [64]u8 = undefined;
var testSigLen: usize = 0;
fn mockSignatureCallback(sinkName: []const u8, sig: []const u8) void {
    _ = sinkName;
    @memcpy(testSigValue[0..sig.len], sig);
    testSigLen = sig.len;
    testSigCalled = true;
}

test "sink cryptographic log chaining signature callback" {
    const allocator = std.testing.allocator;
    const testPath = "sig_callback_test.log";
    std.Io.Dir.cwd().deleteFile(Utils.io(), testPath) catch {};
    defer std.Io.Dir.cwd().deleteFile(Utils.io(), testPath) catch {};

    var sinkCfg = SinkConfig.file(testPath);
    sinkCfg.name = "chaining_sink";
    sinkCfg.tamperEvident = true;
    sinkCfg.asyncWrite = false;

    const sink = try Sink.init(allocator, sinkCfg);
    defer sink.deinit();

    testSigCalled = false;
    testSigLen = 0;
    sink.setSignatureCallback(&mockSignatureCallback);

    var record = Record.init(allocator, .info, "test chaining callback");
    defer record.deinit();

    var globalConfig = Config.default();
    globalConfig.autoSink = false;

    try sink.write(&record, globalConfig);
    try std.testing.expect(testSigCalled);
    try std.testing.expect(testSigLen > 0);
}

var testMmapResizeCalled: bool = false;
var testMmapOldCapacity: u64 = 0;
var testMmapNewCapacity: u64 = 0;
fn mockMmapResizeCallback(sinkName: []const u8, oldCap: u64, newCap: u64) void {
    _ = sinkName;
    testMmapOldCapacity = oldCap;
    testMmapNewCapacity = newCap;
    testMmapResizeCalled = true;
}

test "sink memory-mapped resize callback" {
    const allocator = std.testing.allocator;
    const testPath = "mmap_resize_test.log";
    std.Io.Dir.cwd().deleteFile(Utils.io(), testPath) catch {};
    defer std.Io.Dir.cwd().deleteFile(Utils.io(), testPath) catch {};

    var sinkCfg = SinkConfig.file(testPath);
    sinkCfg.name = "mmap_resize_sink";
    sinkCfg.mmap = true;
    sinkCfg.asyncWrite = false;

    const sink = try Sink.init(allocator, sinkCfg);
    defer sink.deinit();

    testMmapResizeCalled = false;
    sink.setMmapResizeCallback(&mockMmapResizeCallback);

    if (sink.mmapFile) |*mmapF| {
        const oldCap = mmapF.capacity;
        try mmapF.grow(oldCap + 1000);
        if (sink.onMmapResize) |cb| {
            cb("mmap_resize_sink", oldCap, mmapF.capacity);
        }
    }

    try std.testing.expect(testMmapResizeCalled);
    try std.testing.expect(testMmapNewCapacity > testMmapOldCapacity);
}
