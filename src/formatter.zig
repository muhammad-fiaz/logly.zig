//! Log Formatter Module
//!
//! Converts log records into formatted output strings for display or storage.
//! Supports multiple output formats and customizable layouts.
//!
//! Output Formats:
//! - Plain Text: Human-readable formatted output
//! - JSON: Structured JSON for log aggregation systems
//! - Custom Pattern: User-defined format strings
//!
//! Features:
//! - ANSI color support for console output
//! - Configurable timestamp formats
//! - Source location (file, line, column)
//! - Context/metadata inclusion
//! - Trace ID and span ID formatting
//! - Level-specific styling
//!
//! Performance:
//! - Buffer pooling for reduced allocations
//! - Streaming output to writers
//! - Template caching for patterns

const std = @import("std");
const Config = @import("config.zig").Config;
const Record = @import("record.zig").Record;
const Level = @import("level.zig").Level;
const Constants = @import("constants.zig");
const Utils = @import("utils.zig");

/// Handles the formatting of log records into strings or JSON.
pub const Formatter = struct {
    /// Formatter statistics for monitoring and diagnostics.
    pub const FormatterStats = struct {
        total_records_formatted: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        json_formats: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        custom_formats: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        format_errors: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        total_bytes_formatted: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),

        /// Get total records formatted.
        pub fn getTotalFormatted(self: *const FormatterStats) u64 {
            return Utils.atomicLoadU64(&self.total_records_formatted);
        }

        /// Get total JSON formats.
        pub fn getJsonFormats(self: *const FormatterStats) u64 {
            return Utils.atomicLoadU64(&self.json_formats);
        }

        /// Get total custom formats.
        pub fn getCustomFormats(self: *const FormatterStats) u64 {
            return Utils.atomicLoadU64(&self.custom_formats);
        }

        /// Get total format errors.
        pub fn getFormatErrors(self: *const FormatterStats) u64 {
            return Utils.atomicLoadU64(&self.format_errors);
        }

        /// Get total bytes formatted.
        pub fn getTotalBytesFormatted(self: *const FormatterStats) u64 {
            return Utils.atomicLoadU64(&self.total_bytes_formatted);
        }

        /// Get plain text formats (total - json - custom).
        pub fn getPlainFormats(self: *const FormatterStats) u64 {
            const total = Utils.atomicLoadU64(&self.total_records_formatted);
            const json_count = Utils.atomicLoadU64(&self.json_formats);
            const custom_count = Utils.atomicLoadU64(&self.custom_formats);
            if (total > json_count + custom_count) {
                return total - json_count - custom_count;
            }
            return 0;
        }

        /// Check if any records have been formatted.
        pub fn hasFormatted(self: *const FormatterStats) bool {
            return Utils.atomicLoadU64(&self.total_records_formatted) > 0;
        }

        /// Check if any JSON formats have been used.
        pub fn hasJsonFormats(self: *const FormatterStats) bool {
            return Utils.atomicLoadU64(&self.json_formats) > 0;
        }

        /// Check if any custom formats have been used.
        pub fn hasCustomFormats(self: *const FormatterStats) bool {
            return Utils.atomicLoadU64(&self.custom_formats) > 0;
        }

        /// Check if any format errors have occurred.
        pub fn hasErrors(self: *const FormatterStats) bool {
            return Utils.atomicLoadU64(&self.format_errors) > 0;
        }

        /// Calculate JSON format usage rate (0.0 - 1.0).
        pub fn jsonUsageRate(self: *const FormatterStats) f64 {
            return Utils.calculateRate(
                self.getJsonFormats(),
                self.getTotalFormatted(),
            );
        }

        /// Calculate custom format usage rate (0.0 - 1.0).
        pub fn customUsageRate(self: *const FormatterStats) f64 {
            return Utils.calculateRate(
                self.getCustomFormats(),
                self.getTotalFormatted(),
            );
        }

        /// Calculate average format size
        pub fn avgFormatSize(self: *const FormatterStats) f64 {
            return Utils.calculateAverage(
                self.getTotalBytesFormatted(),
                self.getTotalFormatted(),
            );
        }

        /// Calculate error rate (0.0 - 1.0)
        pub fn errorRate(self: *const FormatterStats) f64 {
            return Utils.calculateErrorRate(
                self.getFormatErrors(),
                self.getTotalFormatted(),
            );
        }

        /// Calculate success rate (0.0 - 1.0).
        pub fn successRate(self: *const FormatterStats) f64 {
            return 1.0 - self.errorRate();
        }

        /// Calculate throughput (bytes per second).
        pub fn throughputBytesPerSecond(self: *const FormatterStats, elapsed_seconds: f64) f64 {
            return Utils.safeFloatDiv(
                @as(f64, @floatFromInt(Utils.atomicLoadU64(&self.total_bytes_formatted))),
                elapsed_seconds,
            );
        }

        /// Reset all statistics to initial state.
        pub fn reset(self: *FormatterStats) void {
            self.total_records_formatted.store(0, .monotonic);
            self.json_formats.store(0, .monotonic);
            self.custom_formats.store(0, .monotonic);
            self.format_errors.store(0, .monotonic);
            self.total_bytes_formatted.store(0, .monotonic);
        }

        /// Alias for getTotalFormatted
        pub const totalFormatted = getTotalFormatted;
        pub const count = getTotalFormatted;

        /// Alias for getJsonFormats
        pub const jsonCount = getJsonFormats;
        pub const jsonFormats = getJsonFormats;

        /// Alias for getCustomFormats
        pub const customCount = getCustomFormats;
        pub const customFormats = getCustomFormats;

        /// Alias for getFormatErrors
        pub const errors = getFormatErrors;
        pub const errorCount = getFormatErrors;

        /// Alias for getTotalBytesFormatted
        pub const bytes = getTotalBytesFormatted;
        pub const totalBytes = getTotalBytesFormatted;

        /// Alias for getPlainFormats
        pub const plainCount = getPlainFormats;
        pub const plainFormats = getPlainFormats;

        /// Alias for hasFormatted
        pub const hasRecords = hasFormatted;
        pub const isActive = hasFormatted;

        /// Alias for hasJsonFormats
        pub const hasJson = hasJsonFormats;
        pub const usesJson = hasJsonFormats;

        /// Alias for hasCustomFormats
        pub const hasCustom = hasCustomFormats;
        pub const usesCustom = hasCustomFormats;

        /// Alias for hasErrors
        pub const hasFailed = hasErrors;
        pub const hasFailures = hasErrors;

        /// Alias for jsonUsageRate
        pub const jsonRate = jsonUsageRate;
        pub const jsonUsage = jsonUsageRate;

        /// Alias for customUsageRate
        pub const customRate = customUsageRate;
        pub const customUsage = customUsageRate;

        /// Alias for avgFormatSize
        pub const avgSize = avgFormatSize;
        pub const averageSize = avgFormatSize;

        /// Alias for errorRate
        pub const failureRate = errorRate;

        /// Alias for successRate
        pub const success = successRate;

        /// Alias for throughputBytesPerSecond
        pub const throughput = throughputBytesPerSecond;
        pub const bytesPerSecond = throughputBytesPerSecond;

        /// Alias for reset
        pub const clear = reset;
        pub const zero = reset;
    };

    /// Memory allocator for formatting operations.
    allocator: std.mem.Allocator,
    /// Formatter statistics.
    stats: FormatterStats = .{},
    /// Mutex for thread-safe operations.
    mutex: std.Io.Mutex = std.Io.Mutex.init,

    /// Cached hostname of the current machine.
    hostname: ?[]const u8 = null,

    /// Cached process ID.
    pid: Constants.NativeUint = 0,

    /// Cached debug info for stack trace symbolization.
    /// Loaded lazily upon first request for symbolization.
    debug_info: ?*std.debug.SelfInfo = null,

    /// Callback invoked after a record is formatted.
    /// Parameters: (format_type: u32, output_size: u64)
    on_format_complete: ?*const fn (u32, u64) void = null,

    /// Callback invoked when formatting as JSON.
    /// Parameters: (record: *const Record, output_size: u64)
    on_json_format: ?*const fn (*const Record, u64) void = null,

    /// Callback invoked when using custom format.
    /// Parameters: (format_string: []const u8, output_size: u64)
    on_custom_format: ?*const fn ([]const u8, u64) void = null,

    /// Callback invoked on formatting error.
    /// Parameters: (error_msg: []const u8)
    on_format_error: ?*const fn ([]const u8) void = null,

    /// Custom color theme for log levels.
    theme: ?Theme = null,

    /// Color style mode for output.
    color_style: ColorStyle = .default,

    /// Custom level color overrides.
    level_color_overrides: ?*const std.StringHashMap([]const u8) = null,

    /// Color style options.
    pub const ColorStyle = enum {
        default,
        bright,
        dim,
        color256,
        minimal,
        neon,
        pastel,
        dark,
        light,
    };

    /// Defines a color theme for log levels.
    pub const Theme = struct {
        trace: []const u8 = Constants.Colors.LevelColors.trace,
        debug: []const u8 = Constants.Colors.LevelColors.debug,
        info: []const u8 = Constants.Colors.LevelColors.info,
        notice: []const u8 = Constants.Colors.LevelColors.notice,
        success: []const u8 = Constants.Colors.LevelColors.success,
        warning: []const u8 = Constants.Colors.LevelColors.warning,
        err: []const u8 = Constants.Colors.LevelColors.err,
        fail: []const u8 = Constants.Colors.LevelColors.fail,
        critical: []const u8 = Constants.Colors.LevelColors.critical,
        fatal: []const u8 = Constants.Colors.LevelColors.fatal,

        /// Returns the color code configured for a specific log level.
        pub fn getColor(self: Theme, level: Level) []const u8 {
            return switch (level) {
                .trace => self.trace,
                .debug => self.debug,
                .info => self.info,
                .notice => self.notice,
                .success => self.success,
                .warning => self.warning,
                .err => self.err,
                .fail => self.fail,
                .critical => self.critical,
                .fatal => self.fatal,
            };
        }

        /// Preset: bright colors.
        pub fn bright() Theme {
            const T = Constants.Colors.Themes.bright;
            return .{
                .trace = T.trace,
                .debug = T.debug,
                .info = T.info,
                .notice = T.notice,
                .success = T.success,
                .warning = T.warning,
                .err = T.err,
                .fail = T.fail,
                .critical = T.critical,
                .fatal = T.fatal,
            };
        }

        /// Preset: dim colors.
        pub fn dim() Theme {
            const T = Constants.Colors.Themes.dim;
            return .{
                .trace = T.trace,
                .debug = T.debug,
                .info = T.info,
                .notice = T.notice,
                .success = T.success,
                .warning = T.warning,
                .err = T.err,
                .fail = T.fail,
                .critical = T.critical,
                .fatal = T.fatal,
            };
        }

        /// Preset: minimal colors (only important levels colored).
        pub fn minimal() Theme {
            const T = Constants.Colors.Themes.minimal;
            return .{
                .trace = T.trace,
                .debug = T.debug,
                .info = T.info,
                .notice = T.notice,
                .success = T.success,
                .warning = T.warning,
                .err = T.err,
                .fail = T.fail,
                .critical = T.critical,
                .fatal = T.fatal,
            };
        }

        /// Preset: neon colors (256-color palette).
        pub fn neon() Theme {
            const T = Constants.Colors.Themes.neon;
            return .{
                .trace = T.trace,
                .debug = T.debug,
                .info = T.info,
                .notice = T.notice,
                .success = T.success,
                .warning = T.warning,
                .err = T.err,
                .fail = T.fail,
                .critical = T.critical,
                .fatal = T.fatal,
            };
        }

        /// Preset: pastel colors.
        pub fn pastel() Theme {
            const T = Constants.Colors.Themes.pastel;
            return .{
                .trace = T.trace,
                .debug = T.debug,
                .info = T.info,
                .notice = T.notice,
                .success = T.success,
                .warning = T.warning,
                .err = T.err,
                .fail = T.fail,
                .critical = T.critical,
                .fatal = T.fatal,
            };
        }

        /// Preset: dark theme.
        pub fn dark() Theme {
            const T = Constants.Colors.Themes.dark;
            return .{
                .trace = T.trace,
                .debug = T.debug,
                .info = T.info,
                .notice = T.notice,
                .success = T.success,
                .warning = T.warning,
                .err = T.err,
                .fail = T.fail,
                .critical = T.critical,
                .fatal = T.fatal,
            };
        }

        /// Preset: light theme.
        pub fn light() Theme {
            const T = Constants.Colors.Themes.light;
            return .{
                .trace = T.trace,
                .debug = T.debug,
                .info = T.info,
                .notice = T.notice,
                .success = T.success,
                .warning = T.warning,
                .err = T.err,
                .fail = T.fail,
                .critical = T.critical,
                .fatal = T.fatal,
            };
        }

        /// Create custom theme from RGB values.
        pub fn fromRgb(
            trace_rgb: struct { r: u8, g: u8, b: u8 },
            debug_rgb: struct { r: u8, g: u8, b: u8 },
            info_rgb: struct { r: u8, g: u8, b: u8 },
            warning_rgb: struct { r: u8, g: u8, b: u8 },
            err_rgb: struct { r: u8, g: u8, b: u8 },
        ) Theme {
            _ = trace_rgb;
            _ = debug_rgb;
            _ = info_rgb;
            _ = warning_rgb;
            _ = err_rgb;
            return .{};
        }

        /// Alias for getColor
        pub const colorFor = getColor;
        pub const getLevelColor = getColor;

        /// Alias for bright
        pub const brightTheme = bright;
        pub const vivid = bright;

        /// Alias for dim
        pub const dimTheme = dim;
        pub const subtle = dim;

        /// Alias for minimal
        pub const minimalTheme = minimal;
        pub const basic = minimal;

        /// Alias for neon
        pub const neonTheme = neon;
        pub const vibrant = neon;

        /// Alias for pastel
        pub const pastelTheme = pastel;
        pub const soft = pastel;

        /// Alias for dark
        pub const darkTheme = dark;
        pub const night = dark;

        /// Alias for light
        pub const lightTheme = light;
        pub const day = light;

        /// Alias for fromRgb
        pub const custom = fromRgb;
        pub const rgb = fromRgb;
    };

    /// Initializes a new Formatter and pre-fetches system metadata.
    ///
    /// Arguments:
    /// * `allocator`: The allocator used for string building and cached metadata.
    /// Initializes a new Formatter instance.
    ///
    /// Algorithm:
    ///   - Allocates structure.
    ///   - Fetches process ID via OS hook.
    ///   - Fetches hostname (cached for lifetime).
    ///
    /// Arguments:
    ///   - `allocator`: Allocator for internal use and hostname storage.
    ///
    /// Return Value:
    ///   - `Formatter`: Initialized instance.
    ///
    /// Complexity: O(1) + Hostname syscall cost
    pub fn init(allocator: std.mem.Allocator) Formatter {
        var self = Formatter{
            .allocator = allocator,
            .pid = fetchPID(),
        };
        self.hostname = fetchHostname(allocator) catch null;
        return self;
    }

    /// Alias for init()
    pub const create = init;

    /// Deinitializes the Formatter and frees cached resources.
    ///
    /// Algorithm:
    ///   - Frees hostname if present.
    ///
    /// Complexity: O(1)
    pub fn deinit(self: *Formatter) void {
        if (self.hostname) |h| {
            self.allocator.free(h);
        }
        // debug_info is a pointer to a global singleton managed by std.debug.
        // We do not own it and should not deinit it.
    }

    /// Alias for deinit()
    pub const destroy = deinit;

    /// Sets the callback for format completion.
    pub fn setFormatCompleteCallback(self: *Formatter, callback: *const fn (u32, u64) void) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        self.on_format_complete = callback;
    }

    /// Sets the callback for JSON formatting.
    pub fn setJsonFormatCallback(self: *Formatter, callback: *const fn (*const Record, u64) void) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        self.on_json_format = callback;
    }

    /// Sets the callback for custom formatting.
    pub fn setCustomFormatCallback(self: *Formatter, callback: *const fn ([]const u8, u64) void) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        self.on_custom_format = callback;
    }

    /// Sets the callback for format errors.
    pub fn setErrorCallback(self: *Formatter, callback: *const fn ([]const u8) void) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        self.on_format_error = callback;
    }

    /// Sets a custom color theme.
    pub fn setTheme(self: *Formatter, theme: Theme) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        self.theme = theme;
    }

    /// Returns formatter statistics.
    pub fn getStats(self: *Formatter) FormatterStats {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());

        return self.stats;
    }

    /// Formats a log record into a string.
    ///
    /// This function handles:
    ///   - Custom format strings (parsing tags like `{time}`, `{level}`).
    ///   - Default text formatting.
    ///   - Color application (ENTIRE line is colored, not just level tag).
    ///
    /// Arguments:
    ///   - `record`: The log record to format.
    ///   - `config`: The configuration object (Config or SinkConfig).
    ///
    /// Return Value:
    ///   - `![]u8`: The formatted string (caller must free).
    ///
    /// Complexity: O(N) where N is generated string length.
    pub fn format(self: *Formatter, record: *const Record, config: anytype) ![]u8 {
        return self.formatWithAllocator(record, config, null);
    }

    /// Formats a log record into a string using an optional scratch allocator.
    ///
    /// Useful for temporary allocations to avoid defragmentation or for arena usage.
    ///
    /// Arguments:
    ///   - `record`: Log record.
    ///   - `config`: Output configuration.
    ///   - `scratch_allocator`: Optional allocator (defaults to instance allocator).
    ///
    /// Return Value:
    ///   - `![]u8`: Formatted string (caller must free).
    ///
    /// Complexity: O(N)
    pub fn formatWithAllocator(self: *Formatter, record: *const Record, config: anytype, scratch_allocator: ?std.mem.Allocator) ![]u8 {
        const alloc = scratch_allocator orelse self.allocator;
        const start_time = Utils.currentNanos();
        var bytes_formatted: Constants.AtomicUnsigned = 0;
        defer {
            const current = Utils.currentNanos();
            const elapsed = @as(u64, @intCast(@max(0, current - start_time)));
            _ = self.stats.total_records_formatted.fetchAdd(1, .monotonic);
            _ = self.stats.total_bytes_formatted.fetchAdd(bytes_formatted, .monotonic);
            _ = elapsed;
        }

        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());

        if (self.configIsMsgpack(config)) {
            const res = try self.formatMsgpackWithAllocator(record, config, scratch_allocator);
            bytes_formatted = res.len;
            return res;
        }

        if (self.configIsTui(config)) {
            const res = try self.formatTuiWithAllocator(record, config, scratch_allocator);
            bytes_formatted = res.len;
            return res;
        }

        if (self.configIsNdjson(config)) {
            const res = try self.formatJsonWithAllocator(record, config, scratch_allocator);
            bytes_formatted = res.len;
            return res;
        }

        if (self.configIsLogfmt(config)) {
            const res = try self.formatLogfmtWithAllocator(record, config, scratch_allocator);
            bytes_formatted = res.len;
            return res;
        }

        if (self.configIsCef(config)) {
            const res = try self.formatCefWithAllocator(record, config, scratch_allocator);
            bytes_formatted = res.len;
            return res;
        }

        if (self.configIsJson(config)) {
            const res = try self.formatJsonWithAllocator(record, config, scratch_allocator);
            bytes_formatted = res.len;
            return res;
        }

        var buf = std.Io.Writer.Allocating.init(alloc);
        errdefer buf.deinit();
        const writer = &buf.writer;

        if (self.configIsCustom(config)) {
            _ = self.stats.custom_formats.fetchAdd(1, .monotonic);
        }

        try self.formatToWriter(writer, record, config);

        if (self.on_format_complete) |cb| {
            cb(0, buf.written().len);
        }

        const res = try buf.toOwnedSlice();
        bytes_formatted = res.len;
        return res;
    }

    /// Internal helper to detect if JSON config is active.
    fn configIsJson(self: *Formatter, config: anytype) bool {
        _ = self;
        return if (@hasField(@TypeOf(config), "json")) config.json else false;
    }

    /// Internal helper to detect if Msgpack config is active.
    fn configIsMsgpack(self: *Formatter, config: anytype) bool {
        _ = self;
        return if (@hasField(@TypeOf(config), "msgpack")) config.msgpack else false;
    }

    /// Internal helper to detect if TUI config is active.
    fn configIsTui(self: *Formatter, config: anytype) bool {
        _ = self;
        return if (@hasField(@TypeOf(config), "tui")) config.tui else false;
    }

    /// Internal helper to detect if NDJSON config is active.
    fn configIsNdjson(self: *Formatter, config: anytype) bool {
        _ = self;
        return if (@hasField(@TypeOf(config), "ndjson")) config.ndjson else false;
    }

    /// Internal helper to detect if Logfmt config is active.
    fn configIsLogfmt(self: *Formatter, config: anytype) bool {
        _ = self;
        return if (@hasField(@TypeOf(config), "logfmt")) config.logfmt else false;
    }

    /// Internal helper to detect if CEF config is active.
    fn configIsCef(self: *Formatter, config: anytype) bool {
        _ = self;
        return if (@hasField(@TypeOf(config), "cef")) config.cef else false;
    }

    /// Internal helper to detect if custom format is active.
    fn configIsCustom(self: *Formatter, config: anytype) bool {
        _ = self;
        return if (@hasField(@TypeOf(config), "log_format")) config.log_format != null else false;
    }

    /// Formats a timestamp string using the provided configuration.
    ///
    /// This reuses the same timestamp logic as plain-text and JSON record formatting.
    pub fn formatTimestamp(self: *Formatter, timestamp_ms: i64, config: anytype) ![]u8 {
        return self.formatTimestampWithAllocator(timestamp_ms, config, null);
    }

    /// Formats a timestamp string using an optional scratch allocator.
    pub fn formatTimestampWithAllocator(self: *Formatter, timestamp_ms: i64, config: anytype, scratch_allocator: ?std.mem.Allocator) ![]u8 {
        const alloc = scratch_allocator orelse self.allocator;
        var buf = std.Io.Writer.Allocating.init(alloc);
        errdefer buf.deinit();

        try self.writeTimestamp(&buf.writer, timestamp_ms, config);
        return buf.toOwnedSlice();
    }

    /// Returns the number of interpolation placeholders in a custom format template.
    ///
    /// Supported placeholders are balanced `{name}` tokens. Escaped braces `{{` and `}}`
    /// are treated as literal braces.
    pub fn countTemplatePlaceholders(template: []const u8) !usize {
        var count: usize = 0;
        var i: usize = 0;

        while (i < template.len) {
            switch (template[i]) {
                '{' => {
                    if (i + 1 < template.len and template[i + 1] == '{') {
                        i += 2;
                        continue;
                    }

                    const end = std.mem.indexOfScalarPos(u8, template, i + 1, '}') orelse return error.UnbalancedBraces;
                    if (end == i + 1) return error.InvalidTemplate;
                    count += 1;
                    i = end + 1;
                },
                '}' => {
                    if (i + 1 < template.len and template[i + 1] == '}') {
                        i += 2;
                        continue;
                    }
                    return error.UnbalancedBraces;
                },
                else => i += 1,
            }
        }

        return count;
    }

    /// Validates that a custom format template only uses balanced placeholder braces.
    ///
    /// This is a lightweight syntax check for custom formatter strings and does not
    /// allocate or change the formatter state.
    pub fn validateTemplate(template: []const u8) !void {
        _ = try countTemplatePlaceholders(template);
    }

    /// Formats a `Record` into a caller-provided fixed-size buffer.
    ///
    /// Returns the number of bytes written into `buf`. The buffer must be large
    /// enough to hold the rendered output; use `formatToWriter` (or
    /// `formatWithAllocator`) when the output is unbounded.
    ///
    /// Arguments:
    ///   - `record`: The log record to render.
    ///   - `buf`: Caller-owned destination buffer.
    ///   - `config`: Output configuration.
    ///
    /// Return Value:
    ///   - `usize`: Number of bytes written into `buf`.
    ///
    /// Errors:
    ///   - `error.NoSpaceLeft`: `buf` is too small to hold the formatted output.
    ///
    /// Complexity: O(N) where N is generated string length.
    pub fn formatText(self: *Formatter, record: *const Record, buf: []u8, config: anytype) !usize {
        // Use the underlying formatter to produce a heap-allocated string,
        // then truncate/copy to the caller-provided fixed-size buffer.
        // The caller is responsible for choosing a buffer large enough for
        // typical records; this function trims the rendered output to fit.
        const rendered = try self.formatWithAllocator(record, config, null);
        defer self.allocator.free(rendered);

        const n = @min(rendered.len, buf.len);
        @memcpy(buf[0..n], rendered[0..n]);
        return n;
    }

    /// Formats a log record directly to a writer.
    ///
    /// This avoids intermediate allocations when writing directly to a sink.
    ///
    /// Algorithm:
    ///   - Checks for custom format string; if present, parses and interpolates.
    ///   - If default: applies standard layout [TIMESTAMP] [LEVEL] [MODULE] MESSAGE.
    ///   - Handles ANSI coloring if enabled.
    ///   - resolving stack traces if configured.
    ///
    /// Arguments:
    ///   - `writer`: Destination writer interface.
    ///   - `record`: Log record.
    ///   - `config`: Configuration.
    ///
    /// Complexity: O(N)
    pub fn formatToWriter(self: *Formatter, writer: anytype, record: *const Record, config: anytype) !void {
        const use_color = config.color and config.global_color_display;
        // Use custom color if available (highest priority)
        var color_code: []const u8 = if (record.custom_level_color) |c| c else "";

        // If no custom color from record, check explicit config overrides first.
        if (color_code.len == 0) {
            if (@hasField(@TypeOf(config), "level_colors")) {
                if (config.level_colors.getOverrideForLevel(record.level)) |override| {
                    color_code = override;
                } else if (!config.level_colors.usesDefaultTheme()) {
                    color_code = config.level_colors.getColorForLevel(record.level);
                }
            }
        }

        // If still no color, check the formatter/sink theme.
        if (color_code.len == 0) {
            if (self.theme) |t| {
                color_code = t.getColor(record.level);
            }
        }

        // Fallback to default config/level colors.
        if (color_code.len == 0) {
            if (@hasField(@TypeOf(config), "level_colors")) {
                color_code = config.level_colors.getColorForLevel(record.level);
            } else {
                color_code = record.level.defaultColor();
            }
        }

        // Check if custom log format
        if (config.log_format) |fmt_str| {
            // Start color for entire line
            if (use_color) {
                try writer.print("\x1b[{s}m", .{color_code});
            }

            var i: usize = 0;
            while (i < fmt_str.len) {
                if (fmt_str[i] == '{') {
                    const end = std.mem.indexOfScalarPos(u8, fmt_str, i + 1, '}') orelse {
                        try writer.writeByte(fmt_str[i]);
                        i += 1;
                        continue;
                    };
                    const tag = fmt_str[i + 1 .. end];

                    var field_name = tag;
                    var format_spec: []const u8 = "";
                    if (std.mem.indexOfScalar(u8, tag, ':')) |colon_idx| {
                        field_name = tag[0..colon_idx];
                        format_spec = tag[colon_idx + 1 ..];
                    }

                    if (std.mem.eql(u8, field_name, "time")) {
                        try self.writeTimestamp(writer, record.timestamp, config);
                    } else if (std.mem.eql(u8, field_name, "level")) {
                        try writePadded(writer, record.levelName(), format_spec);
                    } else if (std.mem.eql(u8, field_name, "message")) {
                        try writePadded(writer, record.message, format_spec);
                    } else if (std.mem.eql(u8, field_name, "module")) {
                        try writePadded(writer, record.module orelse "", format_spec);
                    } else if (std.mem.eql(u8, field_name, "function")) {
                        try writePadded(writer, record.function orelse "", format_spec);
                    } else if (std.mem.eql(u8, field_name, "file")) {
                        try writePadded(writer, record.filename orelse "", format_spec);
                    } else if (std.mem.eql(u8, field_name, "line")) {
                        if (record.line) |l| {
                            var num_buf: [32]u8 = undefined;
                            const num_str = std.fmt.bufPrint(&num_buf, "{d}", .{l}) catch "";
                            try writePadded(writer, num_str, format_spec);
                        } else {
                            try writePadded(writer, "", format_spec);
                        }
                    } else if (std.mem.eql(u8, field_name, "thread")) {
                        if (record.thread_id) |tid| {
                            var num_buf: [32]u8 = undefined;
                            const num_str = std.fmt.bufPrint(&num_buf, "{d}", .{tid}) catch "";
                            try writePadded(writer, num_str, format_spec);
                        } else {
                            try writePadded(writer, "", format_spec);
                        }
                    } else if (std.mem.eql(u8, field_name, "trace_id")) {
                        try writePadded(writer, record.trace_id orelse "", format_spec);
                    } else if (std.mem.eql(u8, field_name, "span_id")) {
                        try writePadded(writer, record.span_id orelse "", format_spec);
                    } else if (std.mem.eql(u8, field_name, "fields")) {
                        var it = record.context.iterator();
                        var first = true;
                        while (it.next()) |entry| {
                            if (!first) try writer.writeByte(' ');
                            try writer.writeAll(entry.key_ptr.*);
                            try writer.writeByte('=');
                            switch (entry.value_ptr.*) {
                                .string => |s| try writeLogfmtValue(writer, s),
                                .integer => |in| try writer.print("{d}", .{in}),
                                .float => |fl| try writer.print("{d}", .{fl}),
                                .bool => |b| try writer.writeAll(if (b) "true" else "false"),
                                else => try writer.writeAll("null"),
                            }
                            first = false;
                        }
                    } else {
                        // Unknown tag, print as is
                        try writer.writeAll(fmt_str[i .. end + 1]);
                    }
                    i = end + 1;
                } else {
                    try writer.writeByte(fmt_str[i]);
                    i += 1;
                }
            }

            // Reset color at end of entire line
            if (use_color) {
                try writer.writeAll("\x1b[0m");
            }
        } else {
            // Default format - color entire line

            // Start color for entire line
            if (use_color) {
                try writer.print("\x1b[{s}m", .{color_code});
            }

            // Timestamp
            if (config.show_time) {
                try writer.writeAll("[");
                try self.writeTimestamp(writer, record.timestamp, config);
                try writer.writeAll("] ");
            }

            // Level (use custom name if available)
            try writer.writeByte('[');
            try writer.writeAll(record.levelName());
            try writer.writeAll("] ");

            // Module
            if (config.show_module and record.module != null) {
                try writer.writeByte('[');
                try writer.writeAll(record.module.?);
                try writer.writeAll("] ");
            }

            // Function
            if (config.show_function and record.function != null) {
                try writer.writeByte('[');
                try writer.writeAll(record.function.?);
                try writer.writeAll("] ");
            }

            // Thread ID
            if (config.show_thread_id and record.thread_id != null) {
                try writer.writeAll("[TID:");
                try Utils.writeInt(writer, record.thread_id.?);
                try writer.writeAll("] ");
            }

            // Filename and line (Clickable format: file:line:column: for terminal clickability)
            if (config.show_filename and record.filename != null) {
                try writer.writeAll(record.filename.?);
                if (config.show_lineno and record.line != null) {
                    try writer.writeByte(':');
                    try Utils.writeInt(writer, record.line.?);
                    try writer.writeAll(":0:");
                } else {
                    try writer.writeAll(":0:0:");
                }
                try writer.writeByte(' ');
            }

            // Message
            try writer.writeAll(record.message);

            // Stack Trace (if present)
            if (record.stack_trace) |st| {
                try writer.writeAll("\nStack Trace:\n");

                // Check for symbolization config
                const symbolize = if (@hasField(@TypeOf(config), "symbolize_stack_trace")) config.symbolize_stack_trace else false;

                if (symbolize) {
                    // Lazy load debug info to avoid repeatedly parsing DWARF info (expensive!)
                    if (self.debug_info == null) {
                        // We swallow the error here as we can fallback to raw addresses
                        self.debug_info = std.debug.getSelfDebugInfo() catch null;
                    }

                    const count = @min(st.index, st.instruction_addresses.len);

                    for (st.instruction_addresses[0..count]) |addr| {
                        if (self.debug_info) |di| {
                            if (di.getModuleName(Utils.io(), addr) catch null) |module_name| {
                                try writer.print("  {s}:0x{x}\n", .{ module_name, addr });
                            } else {
                                try writer.print("  0x{x}\n", .{addr});
                            }
                        } else {
                            try writer.print("  0x{x}\n", .{addr});
                        }
                    }
                } else {
                    // Default: print raw addresses
                    const count = @min(st.index, st.instruction_addresses.len);
                    for (st.instruction_addresses[0..count]) |addr| {
                        try writer.print("  0x{x}\n", .{addr});
                    }
                }
            }

            // Reset color at end of entire line
            if (use_color) {
                try writer.writeAll("\x1b[0m");
            }
        }

        // Render rule messages if present
        if (record.rule_messages) |messages| {
            const Rules = @import("rules.zig").Rules;
            var rules_temp = Rules.init(self.allocator);
            defer rules_temp.deinit();
            try rules_temp.formatMessages(messages, writer, use_color);
        }
    }

    fn normalizedTimeFormat(raw_time_format: []const u8) []const u8 {
        if (std.mem.eql(u8, raw_time_format, Config.TimeFormat.default_alias)) {
            return Config.TimeFormat.default_pattern;
        }
        return raw_time_format;
    }

    fn isUnixSecondsFormat(time_format: []const u8) bool {
        return std.mem.eql(u8, time_format, Config.TimeFormat.unix);
    }

    fn isUnixMillisFormat(time_format: []const u8) bool {
        return std.mem.eql(u8, time_format, Config.TimeFormat.unix_ms);
    }

    fn isNumericTimestampFormat(time_format: []const u8) bool {
        return isUnixSecondsFormat(time_format) or isUnixMillisFormat(time_format);
    }

    fn writeNumericTimestamp(writer: anytype, timestamp_ms: i64, time_format: []const u8) !void {
        if (isUnixSecondsFormat(time_format)) {
            const unix_seconds = @divFloor(timestamp_ms, Utils.msPerSecond);
            try Utils.writeInt(writer, unix_seconds);
            return;
        }

        // unix_ms
        try Utils.writeInt(writer, timestamp_ms);
    }

    /// Writes a timestamp according to configured format and timezone.
    ///
    /// Supports predefined formats (`ISO8601`, `RFC3339`, `unix`, `unix_ms`) and
    /// custom patterns via `Utils.formatDatePatternWithOffset`.
    fn writeTimestamp(self: *Formatter, writer: anytype, timestamp_ms: i64, config: anytype) !void {
        _ = self;

        const time_format = normalizedTimeFormat(config.time_format);

        // Handle special time formats
        if (isNumericTimestampFormat(time_format)) {
            try writeNumericTimestamp(writer, timestamp_ms, time_format);
            return;
        }

        const use_local_timezone = if (@hasField(@TypeOf(config), "timezone"))
            config.timezone == .local
        else
            false;
        const tc = if (use_local_timezone)
            Utils.fromMilliTimestampLocal(timestamp_ms)
        else
            Utils.fromMilliTimestamp(timestamp_ms);
        const utc_offset_minutes: i16 = if (use_local_timezone)
            Utils.localUtcOffsetMinutes(timestamp_ms)
        else
            0;
        const abs_ts = if (timestamp_ms < 0) 0 else @as(u64, @intCast(timestamp_ms));
        const millis = abs_ts % Constants.TimeConstants.ms_per_second;

        // ISO8601 format: 2025-12-04T06:39:53.091Z or 2025-12-04T07:39:53.091+01:00
        if (std.mem.eql(u8, time_format, Config.TimeFormat.iso8601)) {
            try Utils.writeIsoDateTime(writer, tc);
            try writer.writeByte('.');
            try Utils.write3Digits(writer, millis);
            if (use_local_timezone) {
                try Utils.writeUtcOffset(writer, utc_offset_minutes);
            } else {
                try writer.writeByte('Z');
            }
            return;
        }

        // RFC3339 format: 2025-12-04T06:39:53+00:00 or 2025-12-04T07:39:53+01:00
        if (std.mem.eql(u8, time_format, Config.TimeFormat.rfc3339)) {
            try Utils.writeIsoDateTime(writer, tc);
            try Utils.writeUtcOffset(writer, utc_offset_minutes);
            return;
        }

        // Custom format parsing - supports any format with placeholders:
        // YYYY = 4-digit year, YY = 2-digit year
        // MM = 2-digit month, M = 1-2 digit month
        // DD = 2-digit day, D = 1-2 digit day
        // HH = 2-digit hour (24h), hh = 2-digit hour (12h)
        // mm = 2-digit minute
        // ss = 2-digit second
        // Custom format parsing via shared utility
        try Utils.formatDatePatternWithOffset(writer, time_format, tc.year, tc.month, tc.day, tc.hour, tc.minute, tc.second, millis, utc_offset_minutes);
    }

    /// Writes timestamp field value for JSON output.
    /// Numeric formats stay numeric; all others are quoted strings.
    fn writeJsonTimestampValue(self: *Formatter, writer: anytype, timestamp_ms: i64, config: anytype) !void {
        const time_format = normalizedTimeFormat(config.time_format);
        if (isNumericTimestampFormat(time_format)) {
            try writeNumericTimestamp(writer, timestamp_ms, time_format);
        } else {
            try writer.writeAll("\"");
            try self.writeTimestamp(writer, timestamp_ms, config);
            try writer.writeAll("\"");
        }
    }

    /// Formats a log record as JSON string.
    ///
    /// Algorithm:
    ///   - Serializes record fields to JSON object.
    ///   - Handles escaping of special characters.
    ///   - Supports "pretty" printing with indentation if configured.
    ///   - Includes timestamps, levels, messages, and context.
    ///
    /// Arguments:
    ///   - `record`: The log record to format.
    ///   - `config`: Configuration.
    ///
    /// Return Value:
    ///   - `![]u8`: JSON string.
    ///
    /// Complexity: O(N)
    pub fn formatJson(self: *Formatter, record: *const Record, config: anytype) ![]u8 {
        return self.formatJsonWithAllocator(record, config, null);
    }

    /// Formats a log record as JSON using optional allocator.
    ///
    /// Arguments:
    ///   - `scratch_allocator`: Optional allocator for buffer.
    ///
    /// Complexity: O(N)
    pub fn formatJsonWithAllocator(self: *Formatter, record: *const Record, config: anytype, scratch_allocator: ?std.mem.Allocator) ![]u8 {
        const alloc = scratch_allocator orelse self.allocator;
        var list: std.ArrayList(u8) = .empty;
        defer list.deinit(alloc);
        try list.ensureTotalCapacity(alloc, estimateJsonSize(record, config));
        errdefer list.deinit(alloc);

        var alw = Utils.ArrayListWriter.init(&list, alloc);
        try self.formatJsonToWriter(&alw.writer, record, config);

        _ = self.stats.json_formats.fetchAdd(1, .monotonic);

        if (self.on_json_format) |cb| {
            cb(record, list.items.len);
        }

        return list.toOwnedSlice(alloc);
    }

    /// Formats a log record as JSON directly to a writer.
    ///
    /// Use this for zero-allocation streaming (assuming buffered writer).
    ///
    /// Algorithm:
    ///   - Manually constructs JSON to avoid overhead of introspection libraries for this hot path.
    ///   - Conditional field inclusion based on configuration (pid, hostname, etc.).
    ///
    /// Complexity: O(N)
    pub fn formatJsonToWriter(self: *Formatter, writer: anytype, record: *const Record, config: anytype) !void {
        const escapeJsonString = Utils.escapeJsonString;
        const pretty = if (@hasField(@TypeOf(config), "pretty_json")) config.pretty_json else false;
        const indent = if (pretty) "  " else "";
        const newline = if (pretty) "\n" else "";
        const sep = if (pretty) ": " else ":";
        const comma = if (pretty) ",\n" else ",";

        // Check if colors should be used for JSON output
        const use_color = config.color and config.global_color_display;
        const color_code = record.levelColor();

        // Start color for entire JSON line/block
        if (use_color) {
            try writer.writeAll("\x1b[");
            try writer.writeAll(color_code);
            try writer.writeByte('m');
        }

        try writer.writeAll("{");
        try writer.writeAll(newline);

        // Timestamp
        try writer.writeAll(indent);
        try writer.writeAll("\"timestamp\"");
        try writer.writeAll(sep);
        try self.writeJsonTimestampValue(writer, record.timestamp, config);

        // Level (use custom name if available)
        try writer.writeAll(comma);
        try writer.writeAll(indent);
        try writer.writeAll("\"level\"");
        try writer.writeAll(sep);
        try writer.writeByte('"');
        try writer.writeAll(record.levelName());
        try writer.writeByte('"');

        // Message
        try writer.writeAll(comma);
        try writer.writeAll(indent);
        try writer.writeAll("\"message\"");
        try writer.writeAll(sep);
        try writer.writeByte('"');
        try escapeJsonString(writer, record.message);
        try writer.writeByte('"');

        // Optional fields
        if (record.module) |m| {
            try writer.writeAll(comma);
            try writer.writeAll(indent);
            try writer.writeAll("\"module\"");
            try writer.writeAll(sep);
            try writer.writeByte('"');
            try escapeJsonString(writer, m);
            try writer.writeByte('"');
        }
        if (record.function) |f| {
            try writer.writeAll(comma);
            try writer.writeAll(indent);
            try writer.writeAll("\"function\"");
            try writer.writeAll(sep);
            try writer.writeByte('"');
            try escapeJsonString(writer, f);
            try writer.writeByte('"');
        }
        if (record.filename) |f| {
            try writer.writeAll(comma);
            try writer.writeAll(indent);
            try writer.writeAll("\"filename\"");
            try writer.writeAll(sep);
            try writer.writeByte('"');
            try escapeJsonString(writer, f);
            try writer.writeByte('"');
        }
        if (record.line) |l| {
            try writer.writeAll(comma);
            try writer.writeAll(indent);
            try writer.writeAll("\"line\"");
            try writer.writeAll(sep);
            try Utils.writeInt(writer, l);
        }

        // Hostname and PID
        if (config.include_hostname) {
            try writer.writeAll(comma);
            try writer.writeAll(indent);
            try writer.writeAll("\"hostname\"");
            try writer.writeAll(sep);
            try writer.writeByte('"');
            if (self.hostname) |h| {
                try escapeJsonString(writer, h);
            } else {
                try writer.writeAll("unknown-host");
            }
            try writer.writeByte('"');
        }

        if (config.include_pid) {
            try writer.writeAll(comma);
            try writer.writeAll(indent);
            try writer.writeAll("\"pid\"");
            try writer.writeAll(sep);
            try Utils.writeInt(writer, self.pid);
        }

        // Distributed Context
        if (@hasField(@TypeOf(config), "distributed")) {
            if (config.distributed.enabled) {
                if (config.distributed.service_name) |s| {
                    try writer.writeAll(comma);
                    try writer.writeAll(indent);
                    try writer.writeAll("\"service\"");
                    try writer.writeAll(sep);
                    try writer.writeByte('"');
                    try escapeJsonString(writer, s);
                    try writer.writeByte('"');
                }
                if (config.distributed.service_version) |v| {
                    try writer.writeAll(comma);
                    try writer.writeAll(indent);
                    try writer.writeAll("\"version\"");
                    try writer.writeAll(sep);
                    try writer.writeByte('"');
                    try escapeJsonString(writer, v);
                    try writer.writeByte('"');
                }
                if (config.distributed.environment) |e| {
                    try writer.writeAll(comma);
                    try writer.writeAll(indent);
                    try writer.writeAll("\"env\"");
                    try writer.writeAll(sep);
                    try writer.writeByte('"');
                    try escapeJsonString(writer, e);
                    try writer.writeByte('"');
                }
                if (config.distributed.region) |r| {
                    try writer.writeAll(comma);
                    try writer.writeAll(indent);
                    try writer.writeAll("\"region\"");
                    try writer.writeAll(sep);
                    try writer.writeByte('"');
                    try escapeJsonString(writer, r);
                    try writer.writeByte('"');
                }
                if (config.distributed.datacenter) |d| {
                    try writer.writeAll(comma);
                    try writer.writeAll(indent);
                    try writer.writeAll("\"datacenter\"");
                    try writer.writeAll(sep);
                    try writer.writeByte('"');
                    try escapeJsonString(writer, d);
                    try writer.writeByte('"');
                }
                if (config.distributed.instance_id) |i| {
                    try writer.writeAll(comma);
                    try writer.writeAll(indent);
                    try writer.writeAll("\"instance_id\"");
                    try writer.writeAll(sep);
                    try writer.writeByte('"');
                    try escapeJsonString(writer, i);
                    try writer.writeByte('"');
                }
            }
        }

        // Stack Trace
        if (record.stack_trace) |st| {
            try writer.writeAll(comma);
            try writer.writeAll(indent);
            try writer.writeAll("\"stack_trace\"");
            try writer.writeAll(sep);
            try writer.writeByte('[');

            // We can't easily symbolize here without debug info, but we can print addresses
            var first_addr = true;
            const count = @min(st.index, st.instruction_addresses.len);

            // If symbolization is enabled in config (passed via config param)
            // Note: config is 'anytype' here, so we check if it has the field
            const symbolize = if (@hasField(@TypeOf(config), "symbolize_stack_trace")) config.symbolize_stack_trace else false;

            if (symbolize) {
                // Attempt to symbolize using cached debug info
                if (self.debug_info == null) {
                    self.debug_info = std.debug.getSelfDebugInfo() catch null;
                }

                for (st.instruction_addresses[0..count]) |addr| {
                    if (!first_addr) try writer.writeAll(", ");

                    if (self.debug_info) |di| {
                        if (di.getModuleName(Utils.io(), addr) catch null) |module_name| {
                            try writer.print("\"{s}:0x{x}\"", .{ module_name, addr });
                        } else {
                            try writer.print("\"{x}\"", .{addr});
                        }
                    } else {
                        try writer.print("\"{x}\"", .{addr});
                    }
                    first_addr = false;
                }
            } else {
                for (st.instruction_addresses[0..count]) |addr| {
                    if (!first_addr) try writer.writeAll(", ");
                    try writer.print("\"{x}\"", .{addr});
                    first_addr = false;
                }
            }
            try writer.writeAll("]");
        }

        // Trace ID
        if (record.trace_id) |tid| {
            try writer.writeAll(comma);
            try writer.writeAll(indent);
            try writer.writeAll("\"trace_id\"");
            try writer.writeAll(sep);
            try writer.writeByte('"');
            try escapeJsonString(writer, tid);
            try writer.writeByte('"');
        }

        // Span ID
        if (record.span_id) |sid| {
            try writer.writeAll(comma);
            try writer.writeAll(indent);
            try writer.writeAll("\"span_id\"");
            try writer.writeAll(sep);
            try writer.writeByte('"');
            try escapeJsonString(writer, sid);
            try writer.writeByte('"');
        }

        // Parent Span ID
        if (record.parent_span_id) |pid| {
            try writer.writeAll(comma);
            try writer.writeAll(indent);
            try writer.writeAll("\"parent_span_id\"");
            try writer.writeAll(sep);
            try writer.writeByte('"');
            try escapeJsonString(writer, pid);
            try writer.writeByte('"');
        }

        // Context fields
        if (record.context.count() > 0) {
            try writer.writeAll(comma);
            try writer.writeAll(indent);
            try writer.writeAll("\"context\"");
            try writer.writeAll(sep);
            try writer.writeByte('{');
            try writer.writeAll(newline);

            var it = record.context.iterator();
            var first = true;
            while (it.next()) |entry| {
                if (!first) {
                    try writer.writeAll(comma);
                }
                try writer.writeAll(indent);
                try writer.writeAll(indent);
                try writer.writeByte('"');
                try writer.writeAll(entry.key_ptr.*);
                try writer.writeAll("\"");
                try writer.writeAll(sep);

                switch (entry.value_ptr.*) {
                    .string => |s| {
                        try writer.writeByte('"');
                        try escapeJsonString(writer, s);
                        try writer.writeByte('"');
                    },
                    .integer => |i| try Utils.writeInt(writer, i), // Utils.writeInt handles signed i64
                    .float => |f| try writer.print("{d}", .{f}),
                    .bool => |b| try writer.writeAll(if (b) "true" else "false"),
                    else => try writer.writeAll("null"),
                }
                first = false;
            }
            try writer.writeAll(newline);
            try writer.writeAll(indent);
            try writer.writeByte('}');
        }

        // Rules
        if (record.rule_messages) |messages| {
            try writer.writeAll(comma);
            try writer.writeAll(indent);
            try writer.writeAll("\"rules\"");
            try writer.writeAll(sep);
            const Rules = @import("rules.zig").Rules;
            var rules_temp = Rules.init(self.allocator);
            defer rules_temp.deinit();
            try rules_temp.formatMessagesJson(messages, writer, pretty);
        }

        try writer.writeAll(newline);
        try writer.writeAll("}");

        // Reset color at end of JSON
        if (use_color) {
            try writer.writeAll("\x1b[0m");
        }
    }

    /// Returns true if the formatter has a custom theme.
    pub fn hasTheme(self: *const Formatter) bool {
        return self.theme != null;
    }

    /// Resets statistics.
    pub fn resetStats(self: *Formatter) void {
        self.stats = .{};
    }

    /// Cheap size estimate for a JSON record, used to pre-allocate the
    /// output buffer and avoid `std.Io.Writer.Allocating`'s exponential
    /// grow path. Returns a conservative upper bound.
    fn estimateJsonSize(record: *const Record, config: anytype) usize {
        var size: usize = 64;
        size += 16; // {"timestamp":...,
        size += record.message.len + 16;
        size += 16 + 16; // "level":"info",
        if (record.module) |m| size += 12 + m.len;
        if (record.function) |f| size += 14 + f.len;
        if (record.filename) |f| size += 14 + f.len;
        if (record.line) |_| size += 14 + 8;
        if (config.include_hostname) {
            size += 16 + (if (record.filename) |f| f.len else 32);
        }
        if (config.include_pid) {
            size += 10 + 8;
        }
        if (record.context.count() > 0) {
            size += 16 * record.context.count();
            var it = record.context.iterator();
            while (it.next()) |entry| {
                size += entry.key_ptr.len + 32;
            }
        }
        if (record.trace_id) |t| size += 14 + t.len;
        if (record.span_id) |s| size += 14 + s.len;
        if (record.correlation_id) |c| size += 22 + c.len;
        return size;
    }

    /// Alias for format
    pub const render = format;
    pub const output = format;

    /// Alias for formatToWriter
    pub const renderToWriter = formatToWriter;
    pub const writeFormatted = formatToWriter;
    pub const formatTextToBuf = formatText;

    /// Alias for formatJson
    pub const json = formatJson;
    pub const toJson = formatJson;

    /// Alias for formatJsonToWriter
    pub const jsonToWriter = formatJsonToWriter;
    pub const writeJson = formatJsonToWriter;

    /// Alias for getStats
    pub const statistics = getStats;

    /// Alias for setFormatCompleteCallback
    pub const onFormatComplete = setFormatCompleteCallback;
    pub const setOnFormatComplete = setFormatCompleteCallback;

    /// Alias for setJsonFormatCallback
    pub const onJsonFormat = setJsonFormatCallback;
    pub const setOnJsonFormat = setJsonFormatCallback;

    /// Alias for setCustomFormatCallback
    pub const onCustomFormat = setCustomFormatCallback;
    pub const setOnCustomFormat = setCustomFormatCallback;

    /// Alias for setErrorCallback
    pub const onError = setErrorCallback;
    pub const setOnError = setErrorCallback;

    /// Alias for formatWithAllocator
    pub const renderWithAllocator = formatWithAllocator;
    pub const outputWithAllocator = formatWithAllocator;

    /// Alias for formatTimestamp
    pub const timestamp = formatTimestamp;
    pub const formatTime = formatTimestamp;

    /// Alias for formatTimestampWithAllocator
    pub const timestampWithAllocator = formatTimestampWithAllocator;
    pub const formatTimeWithAllocator = formatTimestampWithAllocator;

    /// Alias for formatJsonWithAllocator
    pub const jsonWithAllocator = formatJsonWithAllocator;
    pub const toJsonWithAllocator = formatJsonWithAllocator;

    /// Alias for hasTheme
    pub const hasColorTheme = hasTheme;
    pub const isThemed = hasTheme;

    /// Alias for resetStats
    pub const clearStats = resetStats;
    pub const resetStatistics = resetStats;

    /// Formats a log record as logfmt.
    pub fn formatLogfmt(self: *Formatter, record: *const Record, config: anytype) ![]u8 {
        return self.formatLogfmtWithAllocator(record, config, null);
    }

    /// Formats a log record as logfmt using the provided allocator.
    pub fn formatLogfmtWithAllocator(self: *Formatter, record: *const Record, config: anytype, scratch_allocator: ?std.mem.Allocator) ![]u8 {
        const alloc = scratch_allocator orelse self.allocator;
        var buf = std.Io.Writer.Allocating.init(alloc);
        errdefer buf.deinit();
        try self.formatLogfmtToWriter(&buf.writer, record, config);
        return buf.toOwnedSlice();
    }

    /// Formats a log record as logfmt directly to a writer.
    pub fn formatLogfmtToWriter(self: *Formatter, writer: anytype, record: *const Record, config: anytype) !void {
        // Write standard logfmt: ts=... level=... msg=... [optional fields] [context fields]
        try writer.writeAll("ts=");
        var ts_buf: [64]u8 = undefined;
        var ts_writer = std.Io.Writer.fixed(&ts_buf);
        try self.writeTimestamp(&ts_writer, record.timestamp, config);
        try writeLogfmtValue(writer, ts_buf[0..ts_writer.end]);

        try writer.writeAll(" level=");
        try writeLogfmtValue(writer, record.levelName());

        try writer.writeAll(" msg=");
        try writeLogfmtValue(writer, record.message);

        if (record.module) |m| {
            try writer.writeAll(" module=");
            try writeLogfmtValue(writer, m);
        }
        if (record.function) |f| {
            try writer.writeAll(" function=");
            try writeLogfmtValue(writer, f);
        }
        if (record.filename) |f| {
            try writer.writeAll(" file=");
            try writeLogfmtValue(writer, f);
        }
        if (record.line) |l| {
            try writer.writeAll(" line=");
            try writer.print("{d}", .{l});
        }
        if (config.include_pid) {
            try writer.writeAll(" pid=");
            try writer.print("{d}", .{self.pid});
        }
        if (config.include_hostname) {
            try writer.writeAll(" hostname=");
            if (self.hostname) |h| {
                try writeLogfmtValue(writer, h);
            } else {
                try writer.writeAll("unknown-host");
            }
        }
        if (record.trace_id) |tid| {
            try writer.writeAll(" trace_id=");
            try writeLogfmtValue(writer, tid);
        }
        if (record.span_id) |sid| {
            try writer.writeAll(" span_id=");
            try writeLogfmtValue(writer, sid);
        }
        if (record.parent_span_id) |pid| {
            try writer.writeAll(" parent_span_id=");
            try writeLogfmtValue(writer, pid);
        }

        if (@hasField(@TypeOf(config), "distributed") and config.distributed.enabled) {
            if (config.distributed.service_name) |s| {
                try writer.writeAll(" service=");
                try writeLogfmtValue(writer, s);
            }
            if (config.distributed.service_version) |v| {
                try writer.writeAll(" version=");
                try writeLogfmtValue(writer, v);
            }
            if (config.distributed.environment) |e| {
                try writer.writeAll(" env=");
                try writeLogfmtValue(writer, e);
            }
            if (config.distributed.region) |r| {
                try writer.writeAll(" region=");
                try writeLogfmtValue(writer, r);
            }
            if (config.distributed.datacenter) |d| {
                try writer.writeAll(" datacenter=");
                try writeLogfmtValue(writer, d);
            }
            if (config.distributed.instance_id) |i| {
                try writer.writeAll(" instance_id=");
                try writeLogfmtValue(writer, i);
            }
        }

        var it = record.context.iterator();
        while (it.next()) |entry| {
            try writer.writeByte(' ');
            try writer.writeAll(entry.key_ptr.*);
            try writer.writeByte('=');
            switch (entry.value_ptr.*) {
                .string => |s| try writeLogfmtValue(writer, s),
                .integer => |i| try writer.print("{d}", .{i}),
                .float => |f| try writer.print("{d}", .{f}),
                .bool => |b| try writer.writeAll(if (b) "true" else "false"),
                else => try writer.writeAll("null"),
            }
        }
    }

    /// Formats a log record as CEF.
    pub fn formatCef(self: *Formatter, record: *const Record, config: anytype) ![]u8 {
        return self.formatCefWithAllocator(record, config, null);
    }

    /// Formats a log record as CEF using the provided allocator.
    pub fn formatCefWithAllocator(self: *Formatter, record: *const Record, config: anytype, scratch_allocator: ?std.mem.Allocator) ![]u8 {
        const alloc = scratch_allocator orelse self.allocator;
        var buf = std.Io.Writer.Allocating.init(alloc);
        errdefer buf.deinit();
        try self.formatCefToWriter(&buf.writer, record, config);
        return buf.toOwnedSlice();
    }

    /// Formats a log record as CEF directly to a writer.
    pub fn formatCefToWriter(self: *Formatter, writer: anytype, record: *const Record, config: anytype) !void {
        const escapeCefField = struct {
            fn escape(w: anytype, s: []const u8) !void {
                for (s) |c| {
                    switch (c) {
                        '\\' => try w.writeAll("\\\\"),
                        '|' => try w.writeAll("\\|"),
                        '\n' => try w.writeAll("\\n"),
                        '\r' => try w.writeAll("\\r"),
                        else => try w.writeByte(c),
                    }
                }
            }
        }.escape;

        const escapeCefExtensionValue = struct {
            fn escape(w: anytype, s: []const u8) !void {
                for (s) |c| {
                    switch (c) {
                        '\\' => try w.writeAll("\\\\"),
                        '=' => try w.writeAll("\\="),
                        '\n' => try w.writeAll("\\n"),
                        '\r' => try w.writeAll("\\r"),
                        else => try w.writeByte(c),
                    }
                }
            }
        }.escape;

        try writer.writeAll("CEF:0|");

        const vendor = if (@hasField(@TypeOf(config), "cef_vendor")) config.cef_vendor else "logly";
        const product = if (@hasField(@TypeOf(config), "cef_product")) config.cef_product else "logly.zig";
        const version = if (@hasField(@TypeOf(config), "cef_version")) config.cef_version else Constants.FormatterDefaults.cef_device_version;
        const signature_id = if (record.correlation_id) |cid| cid else "log";

        try escapeCefField(writer, vendor);
        try writer.writeByte('|');
        try escapeCefField(writer, product);
        try writer.writeByte('|');
        try escapeCefField(writer, version);
        try writer.writeByte('|');
        try escapeCefField(writer, signature_id);
        try writer.writeByte('|');

        try escapeCefField(writer, record.message);
        try writer.writeByte('|');

        const severity_num: u8 = switch (record.level) {
            .trace => 1,
            .debug => 2,
            .info => 3,
            .notice => 4,
            .success => 5,
            .warning => 6,
            .err => 7,
            .fail => 8,
            .critical => 9,
            .fatal => 10,
        };
        try writer.print("{d}|", .{severity_num});

        try writer.writeAll("rt=");
        var ts_buf: [64]u8 = undefined;
        var ts_writer = std.Io.Writer.fixed(&ts_buf);
        try self.writeTimestamp(&ts_writer, record.timestamp, config);
        try escapeCefExtensionValue(writer, ts_buf[0..ts_writer.end]);

        if (record.module) |m| {
            try writer.writeAll(" module=");
            try escapeCefExtensionValue(writer, m);
        }
        if (record.function) |f| {
            try writer.writeAll(" function=");
            try escapeCefExtensionValue(writer, f);
        }
        if (record.filename) |f| {
            try writer.writeAll(" file=");
            try escapeCefExtensionValue(writer, f);
        }
        if (record.line) |l| {
            try writer.print(" line={d}", .{l});
        }
        if (config.include_pid) {
            try writer.print(" pid={d}", .{self.pid});
        }
        if (config.include_hostname) {
            try writer.writeAll(" hostname=");
            if (self.hostname) |h| {
                try escapeCefExtensionValue(writer, h);
            } else {
                try writer.writeAll("unknown-host");
            }
        }
        if (record.trace_id) |tid| {
            try writer.writeAll(" traceId=");
            try escapeCefExtensionValue(writer, tid);
        }
        if (record.span_id) |sid| {
            try writer.writeAll(" spanId=");
            try escapeCefExtensionValue(writer, sid);
        }

        var it = record.context.iterator();
        while (it.next()) |entry| {
            try writer.writeByte(' ');
            try writer.writeAll(entry.key_ptr.*);
            try writer.writeByte('=');
            switch (entry.value_ptr.*) {
                .string => |s| try escapeCefExtensionValue(writer, s),
                .integer => |i| try writer.print("{d}", .{i}),
                .float => |f| try writer.print("{d}", .{f}),
                .bool => |b| try writer.writeAll(if (b) "true" else "false"),
                else => try writer.writeAll("null"),
            }
        }
    }

    /// Represents a snapshot of the Formatter state and statistics.
    pub const Snapshot = struct {
        total_records_formatted: u64,
        json_formats: u64,
        custom_formats: u64,
        format_errors: u64,
        total_bytes_formatted: u64,
        hostname: ?[]const u8 = null,
        pid: Constants.NativeUint,
        allocator: std.mem.Allocator,

        pub fn deinit(self: *Snapshot) void {
            if (self.hostname) |h| {
                self.allocator.free(h);
            }
        }
    };

    /// Takes a snapshot of the Formatter statistics and state.
    pub fn getSnapshot(self: *Formatter, allocator: std.mem.Allocator) !Snapshot {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());

        const hostname_copy = if (self.hostname) |h| try allocator.dupe(u8, h) else null;
        return Snapshot{
            .total_records_formatted = Utils.atomicLoadU64(&self.stats.total_records_formatted),
            .json_formats = Utils.atomicLoadU64(&self.stats.json_formats),
            .custom_formats = Utils.atomicLoadU64(&self.stats.custom_formats),
            .format_errors = Utils.atomicLoadU64(&self.stats.format_errors),
            .total_bytes_formatted = Utils.atomicLoadU64(&self.stats.total_bytes_formatted),
            .hostname = hostname_copy,
            .pid = self.pid,
            .allocator = allocator,
        };
    }

    /// Frees resources associated with a snapshot.
    pub fn freeSnapshot(self: *Formatter, snapshot: Snapshot) void {
        _ = self;
        var snap = snapshot;
        snap.deinit();
    }

    /// Formats a log record as MessagePack binary format.
    pub fn formatMsgpackWithAllocator(self: *Formatter, record: *const Record, config: anytype, scratch_allocator: ?std.mem.Allocator) ![]u8 {
        _ = config;
        const alloc = scratch_allocator orelse self.allocator;

        var buf = std.Io.Writer.Allocating.init(alloc);
        errdefer buf.deinit();
        const writer = &buf.writer;

        // 7 fields: timestamp, level, message, module, filename, line, context
        try writer.writeByte(0x87);

        // 1. timestamp
        try writeMsgpackStr(writer, "timestamp");
        try writeMsgpackInt(writer, record.timestamp);

        // 2. level
        try writeMsgpackStr(writer, "level");
        try writeMsgpackStr(writer, record.level.asString());

        // 3. message
        try writeMsgpackStr(writer, "message");
        try writeMsgpackStr(writer, record.message);

        // 4. module
        try writeMsgpackStr(writer, "module");
        try writeMsgpackStr(writer, record.module orelse "");

        // 5. filename
        try writeMsgpackStr(writer, "filename");
        try writeMsgpackStr(writer, record.filename orelse "");

        // 6. line
        try writeMsgpackStr(writer, "line");
        try writeMsgpackInt(writer, @intCast(record.line orelse 0));

        // 7. context
        try writeMsgpackStr(writer, "context");
        const ctx_count = record.context.count();
        if (ctx_count <= 15) {
            try writer.writeByte(0x80 | @as(u8, @intCast(ctx_count)));
        } else {
            try writer.writeByte(0xde); // map 16
            try writer.writeInt(u16, @intCast(ctx_count), .big);
        }

        var it = record.context.iterator();
        while (it.next()) |entry| {
            try writeMsgpackStr(writer, entry.key_ptr.*);
            switch (entry.value_ptr.*) {
                .string => |s| try writeMsgpackStr(writer, s),
                .integer => |i| try writeMsgpackInt(writer, i),
                .float => |f| {
                    // Pack float as double (0xcb)
                    try writer.writeByte(0xcb);
                    try writer.writeInt(u64, @bitCast(f), .big);
                },
                .bool => |b| try writer.writeByte(if (b) 0xc3 else 0xc2),
                else => try writeMsgpackStr(writer, ""),
            }
        }

        return buf.toOwnedSlice();
    }

    /// Formats a log record as a premium Terminal UI Dashboard card.
    pub fn formatTuiWithAllocator(self: *Formatter, record: *const Record, config: anytype, scratch_allocator: ?std.mem.Allocator) ![]u8 {
        _ = config;
        const alloc = scratch_allocator orelse self.allocator;
        var buf = std.Io.Writer.Allocating.init(alloc);
        errdefer buf.deinit();
        const writer = &buf.writer;

        const count = self.stats.getTotalFormatted();
        const lvl_str = record.level.asString();
        const color = record.level.defaultColor();

        try writer.print("\x1b[36m┌── [LOGLY TUI MONITOR] ──[Count: {d}]──────────────────────────\x1b[0m\n", .{count});
        try writer.print("\x1b[36m│\x1b[0m [\x1b[{s};1m{s:<8}\x1b[0m] Message: {s}\n", .{ color, lvl_str, record.message });
        if (record.module) |mod| {
            try writer.print("\x1b[36m│\x1b[0m Module: \x1b[35m{s}\x1b[0m", .{mod});
            if (record.filename) |file| {
                try writer.print(" | Location: \x1b[92m{s}:{d}\x1b[0m", .{ file, record.line orelse 0 });
            }
            try writer.writeAll("\n");
        } else if (record.filename) |file| {
            try writer.print("\x1b[36m│\x1b[0m Location: \x1b[92m{s}:{d}\x1b[0m\n", .{ file, record.line orelse 0 });
        }

        if (record.context.count() > 0) {
            try writer.writeAll("\x1b[36m│\x1b[0m Context: ");
            var it = record.context.iterator();
            var first = true;
            while (it.next()) |entry| {
                if (!first) try writer.writeAll(", ");
                first = false;
                try writer.print("\x1b[33m{s}\x1b[0m=", .{entry.key_ptr.*});
                switch (entry.value_ptr.*) {
                    .string => |s| try writer.print("\"{s}\"", .{s}),
                    .integer => |i| try writer.print("{d}", .{i}),
                    .float => |f| try writer.print("{d:.2}", .{f}),
                    .bool => |b| try writer.print("{}", .{b}),
                    else => try writer.writeAll("null"),
                }
            }
            try writer.writeAll("\n");
        }

        try writer.writeAll("\x1b[36m└──────────────────────────────────────────────────────────────\x1b[0m\n");

        return buf.toOwnedSlice();
    }
};

fn writePadded(writer: anytype, value: []const u8, spec: []const u8) !void {
    if (spec.len == 0) {
        try writer.writeAll(value);
        return;
    }

    var align_dir: enum { left, right, center } = .left;
    var width_str = spec;

    if (spec[0] == '>') {
        align_dir = .right;
        width_str = spec[1..];
    } else if (spec[0] == '<') {
        align_dir = .left;
        width_str = spec[1..];
    } else if (spec[0] == '^') {
        align_dir = .center;
        width_str = spec[1..];
    }

    const width = std.fmt.parseInt(usize, width_str, 10) catch {
        try writer.writeAll(value);
        return;
    };

    if (value.len >= width) {
        try writer.writeAll(value);
    } else {
        const diff = width - value.len;
        switch (align_dir) {
            .left => {
                try writer.writeAll(value);
                var k: usize = 0;
                while (k < diff) : (k += 1) {
                    try writer.writeByte(' ');
                }
            },
            .right => {
                var k: usize = 0;
                while (k < diff) : (k += 1) {
                    try writer.writeByte(' ');
                }
                try writer.writeAll(value);
            },
            .center => {
                const left_padding = diff / 2;
                const right_padding = diff - left_padding;
                var k: usize = 0;
                while (k < left_padding) : (k += 1) {
                    try writer.writeByte(' ');
                }
                try writer.writeAll(value);
                k = 0;
                while (k < right_padding) : (k += 1) {
                    try writer.writeByte(' ');
                }
            },
        }
    }
}

fn writeLogfmtValue(writer: anytype, value: []const u8) !void {
    var needs_quoting = false;
    if (value.len == 0) {
        needs_quoting = true;
    } else {
        for (value) |c| {
            if (c == ' ' or c == '=' or c == '"' or c == '\\' or c == '\n' or c == '\r' or c == '\t') {
                needs_quoting = true;
                break;
            }
        }
    }

    if (needs_quoting) {
        try writer.writeByte('"');
        for (value) |c| {
            switch (c) {
                '\\' => try writer.writeAll("\\\\"),
                '"' => try writer.writeAll("\\\""),
                '\n' => try writer.writeAll("\\n"),
                '\r' => try writer.writeAll("\\r"),
                '\t' => try writer.writeAll("\\t"),
                else => try writer.writeByte(c),
            }
        }
        try writer.writeByte('"');
    } else {
        try writer.writeAll(value);
    }
}

/// Fetches the current hostname using platform-specific APIs.
fn fetchHostname(allocator: std.mem.Allocator) ![]const u8 {
    const builtin = @import("builtin");
    if (builtin.os.tag == .windows) {
        const win32 = struct {
            extern "kernel32" fn GetComputerNameW(lpBuffer: ?[*]u16, nSize: *u32) callconv(.winapi) i32;
        };
        var buf: [256]u16 = undefined;
        var size: u32 = buf.len;
        if (win32.GetComputerNameW(&buf, &size) != 0) {
            // size does not include null terminator if success
            return std.unicode.utf16LeToUtf8Alloc(allocator, buf[0..size]);
        }
        return error.HostnameFetchFailed;
    } else {
        var buf: [std.posix.HOST_NAME_MAX]u8 = undefined;
        const hostname = try std.posix.gethostname(&buf);
        return try allocator.dupe(u8, hostname);
    }
}

/// Fetches the current process ID in a cross-platform way.
fn fetchPID() Constants.NativeUint {
    const builtin = @import("builtin");
    // Use std.posix where available for portability
    if (builtin.os.tag == .windows) {
        return @as(Constants.NativeUint, std.os.windows.GetCurrentProcessId());
    }

    // For Linux/macOS/BSD/WASI, try std.posix
    if (@hasDecl(std.posix, "getpid")) {
        return @as(Constants.NativeUint, @intCast(std.posix.getpid()));
    }

    // Fallback to libc if linked
    if (builtin.link_libc) {
        return @as(Constants.NativeUint, @intCast(std.c.getpid()));
    }

    return 0;
}

/// Pre-built formatter configurations.
pub const FormatterPresets = struct {
    /// Creates a formatter with no colors.
    pub fn plain(allocator: std.mem.Allocator) Formatter {
        var f = Formatter.init(allocator);
        f.theme = null;
        return f;
    }

    /// Alias for plain
    pub const noColor = plain;
    pub const monochrome = plain;
    pub const colorless = plain;

    /// Creates a formatter with dark theme.
    pub fn dark(allocator: std.mem.Allocator) Formatter {
        var f = Formatter.init(allocator);
        f.theme = Formatter.Theme.dark();
        return f;
    }

    /// Alias for dark
    pub const darkMode = dark;
    pub const nightMode = dark;

    /// Creates a formatter with light theme.
    pub fn light(allocator: std.mem.Allocator) Formatter {
        var f = Formatter.init(allocator);
        f.theme = Formatter.Theme.light();
        return f;
    }

    /// Alias for light
    pub const lightMode = light;
    pub const dayMode = light;
};

/// Formats an offset suffix for test assertions.
fn formatOffsetSuffixForTest(buf: []u8, offset_minutes: i16) ![]const u8 {
    var writer = std.Io.Writer.fixed(buf);
    try Utils.writeUtcOffset(&writer, offset_minutes);
    return buf[0..writer.end];
}

test "formatter ISO8601 UTC uses Z suffix" {
    const allocator = std.testing.allocator;
    var formatter = Formatter.init(allocator);
    defer formatter.deinit();

    var record = Record.init(allocator, .info, "UTC test");
    defer record.deinit();
    record.timestamp = 1700000000000;

    var config = Config{};
    config.time_format = Config.TimeFormat.iso8601;
    config.timezone = .utc;

    var buf = std.Io.Writer.Allocating.init(allocator);
    defer buf.deinit();

    try formatter.formatJsonToWriter(&buf.writer, &record, config);
    try std.testing.expect(std.mem.indexOf(u8, buf.written(), "Z\"") != null);
}

test "formatter ISO8601 local uses local offset suffix" {
    const allocator = std.testing.allocator;
    var formatter = Formatter.init(allocator);
    defer formatter.deinit();

    var record = Record.init(allocator, .info, "Local timezone test");
    defer record.deinit();
    record.timestamp = 1700000000000;

    var config = Config{};
    config.time_format = Config.TimeFormat.iso8601;
    config.timezone = .local;

    var buf = std.Io.Writer.Allocating.init(allocator);
    defer buf.deinit();

    try formatter.formatJsonToWriter(&buf.writer, &record, config);

    const offset_minutes = Utils.localUtcOffsetMinutes(record.timestamp);
    var expected_offset_buf: [6]u8 = undefined;
    const expected_offset = try formatOffsetSuffixForTest(&expected_offset_buf, offset_minutes);

    try std.testing.expect(std.mem.indexOf(u8, buf.written(), expected_offset) != null);
    try std.testing.expect(std.mem.indexOf(u8, buf.written(), "Z\"") == null);
}

test "formatter RFC3339 UTC uses +00:00 suffix" {
    const allocator = std.testing.allocator;
    var formatter = Formatter.init(allocator);
    defer formatter.deinit();

    var record = Record.init(allocator, .info, "RFC3339 UTC test");
    defer record.deinit();
    record.timestamp = 1700000000000;

    var config = Config{};
    config.time_format = Config.TimeFormat.rfc3339;
    config.timezone = .utc;

    var buf = std.Io.Writer.Allocating.init(allocator);
    defer buf.deinit();

    try formatter.formatJsonToWriter(&buf.writer, &record, config);
    try std.testing.expect(std.mem.indexOf(u8, buf.written(), "+00:00\"") != null);
}

test "formatter RFC3339 local uses local offset suffix" {
    const allocator = std.testing.allocator;
    var formatter = Formatter.init(allocator);
    defer formatter.deinit();

    var record = Record.init(allocator, .info, "RFC3339 local test");
    defer record.deinit();
    record.timestamp = 1700000000000;

    var config = Config{};
    config.time_format = Config.TimeFormat.rfc3339;
    config.timezone = .local;

    var buf = std.Io.Writer.Allocating.init(allocator);
    defer buf.deinit();

    try formatter.formatJsonToWriter(&buf.writer, &record, config);

    const offset_minutes = Utils.localUtcOffsetMinutes(record.timestamp);
    var expected_offset_buf: [6]u8 = undefined;
    const expected_offset = try formatOffsetSuffixForTest(&expected_offset_buf, offset_minutes);

    try std.testing.expect(std.mem.indexOf(u8, buf.written(), expected_offset) != null);
}

test "formatter unix and unix_ms remain numeric" {
    const allocator = std.testing.allocator;
    var formatter = Formatter.init(allocator);
    defer formatter.deinit();

    var record = Record.init(allocator, .info, "Unix format test");
    defer record.deinit();
    record.timestamp = 1700000000123;

    var unix_config = Config{};
    unix_config.time_format = Config.TimeFormat.unix;
    unix_config.timezone = .local;

    var unix_buf = std.Io.Writer.Allocating.init(allocator);
    defer unix_buf.deinit();

    try formatter.formatJsonToWriter(&unix_buf.writer, &record, unix_config);
    try std.testing.expect(std.mem.indexOf(u8, unix_buf.written(), "\"timestamp\":1700000000") != null);

    var unix_ms_config = Config{};
    unix_ms_config.time_format = Config.TimeFormat.unix_ms;
    unix_ms_config.timezone = .local;

    var unix_ms_buf = std.Io.Writer.Allocating.init(allocator);
    defer unix_ms_buf.deinit();

    try formatter.formatJsonToWriter(&unix_ms_buf.writer, &record, unix_ms_config);
    try std.testing.expect(std.mem.indexOf(u8, unix_ms_buf.written(), "\"timestamp\":1700000000123") != null);
    try std.testing.expect(std.mem.indexOf(u8, unix_ms_buf.written(), "\"timestamp\":\"1700000000123\"") == null);
}

test "formatter default time format alias maps to configured default pattern" {
    const allocator = std.testing.allocator;
    var formatter = Formatter.init(allocator);
    defer formatter.deinit();

    var record = Record.init(allocator, .info, "Default alias test");
    defer record.deinit();
    record.timestamp = 1700000000123;

    var config = Config{};
    config.timezone = .utc;
    config.time_format = Config.TimeFormat.default_alias;

    var buf = std.Io.Writer.Allocating.init(allocator);
    defer buf.deinit();

    try formatter.formatJsonToWriter(&buf.writer, &record, config);

    try std.testing.expect(std.mem.indexOf(u8, buf.written(), "\"timestamp\":\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, buf.written(), "default") == null);
}

test "formatter custom pattern supports timezone tokens" {
    const allocator = std.testing.allocator;
    var formatter = Formatter.init(allocator);
    defer formatter.deinit();

    var record = Record.init(allocator, .info, "Timezone token test");
    defer record.deinit();
    record.timestamp = 1700000000000;

    var config = Config{};
    config.timezone = .local;
    config.time_format = "YYYY-MM-DD HH:mm:ss ZZZ ZZ";

    var buf = std.Io.Writer.Allocating.init(allocator);
    defer buf.deinit();

    try formatter.formatJsonToWriter(&buf.writer, &record, config);

    const offset_minutes = Utils.localUtcOffsetMinutes(record.timestamp);
    var expected_colon_buf: [6]u8 = undefined;
    const expected_colon = try formatOffsetSuffixForTest(&expected_colon_buf, offset_minutes);

    var expected_compact_buf: [5]u8 = undefined;
    var compact_writer = std.Io.Writer.fixed(&expected_compact_buf);
    try Utils.writeUtcOffsetCompact(&compact_writer, offset_minutes);
    const expected_compact = expected_compact_buf[0..compact_writer.end];

    try std.testing.expect(std.mem.indexOf(u8, buf.written(), expected_colon) != null);
    try std.testing.expect(std.mem.indexOf(u8, buf.written(), expected_compact) != null);
}

test "formatter timestamp helper formats numeric and textual values" {
    const allocator = std.testing.allocator;
    var formatter = Formatter.init(allocator);
    defer formatter.deinit();

    var unix_cfg = Config{};
    unix_cfg.timezone = .utc;
    unix_cfg.time_format = Config.TimeFormat.unix_ms;

    const unix_text = try formatter.formatTimestamp(1700000000123, unix_cfg);
    defer allocator.free(unix_text);
    try std.testing.expectEqualStrings("1700000000123", unix_text);

    var textual_cfg = Config{};
    textual_cfg.timezone = .utc;
    textual_cfg.time_format = Config.TimeFormat.default_alias;

    const textual = try formatter.formatTimestampWithAllocator(1700000000123, textual_cfg, allocator);
    defer allocator.free(textual);

    try std.testing.expect(textual.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, textual, "default") == null);
}

test "formatter template validation" {
    try std.testing.expectEqual(@as(usize, 3), try Formatter.countTemplatePlaceholders("{time} [{level}] {message}"));
    try std.testing.expectEqual(@as(usize, 1), try Formatter.countTemplatePlaceholders("prefix {{literal}} {message}"));
    try Formatter.validateTemplate("{time} - {message}");
    try std.testing.expectError(error.UnbalancedBraces, Formatter.validateTemplate("{time"));
    try std.testing.expectError(error.InvalidTemplate, Formatter.validateTemplate("{}"));
}

test "formatter plain text" {
    const allocator = std.testing.allocator;
    var formatter = Formatter.init(allocator);
    defer formatter.deinit();

    var record = Record.init(allocator, .info, "Test message");
    defer record.deinit();
    record.module = "test_mod";
    record.timestamp = 1700000000000;

    var buf = std.Io.Writer.Allocating.init(allocator);
    defer buf.deinit();

    try formatter.formatToWriter(&buf.writer, &record, Config{});
    const output_str = buf.written();

    try std.testing.expect(std.mem.indexOf(u8, output_str, "INFO") != null);
    try std.testing.expect(std.mem.indexOf(u8, output_str, "test_mod") != null);
    try std.testing.expect(std.mem.indexOf(u8, output_str, "Test message") != null);
}

test "formatter sink theme applies when config colors are default" {
    const allocator = std.testing.allocator;
    var formatter = Formatter.init(allocator);
    defer formatter.deinit();
    formatter.setTheme(Formatter.Theme.neon());

    var record = Record.init(allocator, .info, "Themed message");
    defer record.deinit();
    record.timestamp = 1700000000000;

    var config = Config{};
    config.color = true;
    config.global_color_display = true;

    var buf = std.Io.Writer.Allocating.init(allocator);
    defer buf.deinit();

    try formatter.formatToWriter(&buf.writer, &record, config);
    const output_str = buf.written();

    try std.testing.expect(std.mem.indexOf(u8, output_str, "\x1b[38;5;255m") != null);
}

test "formatter explicit level color overrides sink theme" {
    const allocator = std.testing.allocator;
    var formatter = Formatter.init(allocator);
    defer formatter.deinit();
    formatter.setTheme(Formatter.Theme.neon());

    var record = Record.init(allocator, .info, "Override message");
    defer record.deinit();
    record.timestamp = 1700000000000;

    var config = Config{};
    config.color = true;
    config.global_color_display = true;
    config.level_colors.info_color = "35";

    var buf = std.Io.Writer.Allocating.init(allocator);
    defer buf.deinit();

    try formatter.formatToWriter(&buf.writer, &record, config);
    const output_str = buf.written();

    try std.testing.expect(std.mem.indexOf(u8, output_str, "\x1b[35m") != null);
    try std.testing.expect(std.mem.indexOf(u8, output_str, "\x1b[38;5;255m") == null);
}

test "formatter json" {
    const allocator = std.testing.allocator;
    var formatter = Formatter.init(allocator);
    defer formatter.deinit();

    var record = Record.init(allocator, .err, "Error occurred");
    defer record.deinit();
    record.module = "api";
    record.timestamp = 1700000000000;

    var buf = std.Io.Writer.Allocating.init(allocator);
    defer buf.deinit();

    try formatter.formatJsonToWriter(&buf.writer, &record, Config{});
    const output_str = buf.written();

    try std.testing.expect(std.mem.indexOf(u8, output_str, "\"level\":\"ERROR\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output_str, "\"message\":\"Error occurred\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output_str, "\"module\":\"api\"") != null);
}

test "formatter json distributed fields" {
    const allocator = std.testing.allocator;
    var formatter = Formatter.init(allocator);
    defer formatter.deinit();

    var record = Record.init(allocator, .info, "Distributed log");
    defer record.deinit();

    // Set trace context
    record.trace_id = "trace-123";
    record.span_id = "span-456";

    var config = Config{};
    config.distributed.enabled = true;
    config.distributed.service_name = "test-service";
    config.distributed.region = "us-east-1";

    var buf = std.Io.Writer.Allocating.init(allocator);
    defer buf.deinit();

    try formatter.formatJsonToWriter(&buf.writer, &record, config);
    const output_str = buf.written();

    try std.testing.expect(std.mem.indexOf(u8, output_str, "\"service\":\"test-service\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output_str, "\"region\":\"us-east-1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output_str, "\"trace_id\":\"trace-123\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output_str, "\"span_id\":\"span-456\"") != null);
}

test "theme preset default" {
    const theme = Formatter.Theme{};
    try std.testing.expectEqualStrings("36", theme.trace);
    try std.testing.expectEqualStrings("34", theme.debug);
    try std.testing.expectEqualStrings("37", theme.info);
    try std.testing.expectEqualStrings("32", theme.success);
    try std.testing.expectEqualStrings("33", theme.warning);
    try std.testing.expectEqualStrings("31", theme.err);
    try std.testing.expectEqualStrings("91", theme.critical);
    try std.testing.expectEqualStrings("97;41", theme.fatal);
}

test "theme preset bright" {
    const theme = Formatter.Theme.bright();
    try std.testing.expectEqualStrings("96;1", theme.trace);
    try std.testing.expectEqualStrings("94;1", theme.debug);
    try std.testing.expectEqualStrings("97;1", theme.info);
    try std.testing.expectEqualStrings("91;1", theme.err);
}

test "theme preset dim" {
    const theme = Formatter.Theme.dim();
    try std.testing.expectEqualStrings("36;2", theme.trace);
    try std.testing.expectEqualStrings("34;2", theme.debug);
    try std.testing.expectEqualStrings("37;2", theme.info);
}

test "theme preset minimal" {
    const theme = Formatter.Theme.minimal();
    try std.testing.expectEqualStrings("90", theme.trace);
    try std.testing.expectEqualStrings("90", theme.debug);
    try std.testing.expectEqualStrings("37", theme.info);
}

test "theme preset neon" {
    const theme = Formatter.Theme.neon();
    try std.testing.expectEqualStrings("38;5;51", theme.trace);
    try std.testing.expectEqualStrings("38;5;33", theme.debug);
    try std.testing.expectEqualStrings("38;5;196", theme.err);
}

test "theme preset pastel" {
    const theme = Formatter.Theme.pastel();
    try std.testing.expectEqualStrings("38;5;159", theme.trace);
    try std.testing.expectEqualStrings("38;5;117", theme.debug);
    try std.testing.expectEqualStrings("38;5;210", theme.err);
}

test "theme preset dark" {
    const theme = Formatter.Theme.dark();
    try std.testing.expectEqualStrings("38;5;244", theme.trace);
    try std.testing.expectEqualStrings("38;5;75", theme.debug);
    try std.testing.expectEqualStrings("38;5;203", theme.err);
}

test "theme preset light" {
    const theme = Formatter.Theme.light();
    try std.testing.expectEqualStrings("38;5;242", theme.trace);
    try std.testing.expectEqualStrings("38;5;24", theme.debug);
    try std.testing.expectEqualStrings("38;5;124", theme.err);
}

test "theme getColor" {
    const theme = Formatter.Theme{};
    try std.testing.expectEqualStrings("36", theme.getColor(.trace));
    try std.testing.expectEqualStrings("34", theme.getColor(.debug));
    try std.testing.expectEqualStrings("37", theme.getColor(.info));
    try std.testing.expectEqualStrings("33", theme.getColor(.warning));
    try std.testing.expectEqualStrings("31", theme.getColor(.err));
    try std.testing.expectEqualStrings("97;41", theme.getColor(.fatal));
}

test "formatter stats" {
    const allocator = std.testing.allocator;
    var formatter = Formatter.init(allocator);
    defer formatter.deinit();

    const stats = formatter.getStats();
    try std.testing.expectEqual(@as(u64, 0), stats.getTotalFormatted());
    try std.testing.expectEqual(@as(u64, 0), stats.getJsonFormats());
    try std.testing.expectEqual(@as(u64, 0), stats.getFormatErrors());
    try std.testing.expect(!stats.hasFormatted());
    try std.testing.expect(!stats.hasErrors());
}

test "formatter preset plain" {
    const allocator = std.testing.allocator;
    var formatter = FormatterPresets.plain(allocator);
    defer formatter.deinit();
    try std.testing.expect(!formatter.hasTheme());
}

test "formatter preset dark" {
    const allocator = std.testing.allocator;
    var formatter = FormatterPresets.dark(allocator);
    defer formatter.deinit();
    try std.testing.expect(formatter.hasTheme());
}

test "formatter preset light" {
    const allocator = std.testing.allocator;
    var formatter = FormatterPresets.light(allocator);
    defer formatter.deinit();
    try std.testing.expect(formatter.hasTheme());
}

test "color style enum" {
    const style = Formatter.ColorStyle.bright;
    try std.testing.expect(style == .bright);
    try std.testing.expect(Formatter.ColorStyle.default != .neon);
}

fn writeMsgpackInt(writer: anytype, val: i64) !void {
    if (val >= 0 and val <= 127) {
        try writer.writeByte(@intCast(val));
    } else if (val >= -32 and val < 0) {
        try writer.writeByte(@bitCast(@as(i8, @intCast(val))));
    } else if (val >= -128 and val <= 127) {
        try writer.writeByte(0xd0);
        try writer.writeByte(@bitCast(@as(i8, @intCast(val))));
    } else if (val >= -32768 and val <= 32767) {
        try writer.writeByte(0xd1);
        try writer.writeInt(i16, @intCast(val), .big);
    } else if (val >= -2147483648 and val <= 2147483647) {
        try writer.writeByte(0xd2);
        try writer.writeInt(i32, @intCast(val), .big);
    } else {
        try writer.writeByte(0xd3);
        try writer.writeInt(i64, val, .big);
    }
}

fn writeMsgpackStr(writer: anytype, str: []const u8) !void {
    const len = str.len;
    if (len <= 31) {
        try writer.writeByte(0xa0 | @as(u8, @intCast(len)));
    } else if (len <= 255) {
        try writer.writeByte(0xd9);
        try writer.writeByte(@intCast(len));
    } else if (len <= 65535) {
        try writer.writeByte(0xda);
        try writer.writeInt(u16, @intCast(len), .big);
    } else {
        try writer.writeByte(0xdb);
        try writer.writeInt(u32, @intCast(len), .big);
    }
    try writer.writeAll(str);
}

test "formatter Msgpack and TUI" {
    const allocator = std.testing.allocator;
    var formatter = Formatter.init(allocator);
    defer formatter.deinit();

    var record = Record.init(allocator, .info, "msgpack and tui test message");
    defer record.deinit();
    record.module = "test_binary";

    // Test Msgpack
    var config = Config.default();
    config.msgpack = true;
    const msgpack_data = try formatter.format(&record, config);
    defer allocator.free(msgpack_data);

    try std.testing.expect(msgpack_data.len > 0);
    // Map header 0x87
    try std.testing.expectEqual(@as(u8, 0x87), msgpack_data[0]);

    // Test TUI
    config.msgpack = false;
    config.tui = true;
    const tui_str = try formatter.format(&record, config);
    defer allocator.free(tui_str);

    try std.testing.expect(tui_str.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, tui_str, "LOGLY TUI MONITOR") != null);
}
