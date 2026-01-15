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
            const total = self.getTotalFormatted();
            const json_count = self.getJsonFormats();
            const custom_count = self.getCustomFormats();
            if (total > json_count + custom_count) {
                return total - json_count - custom_count;
            }
            return 0;
        }

        /// Check if any records have been formatted.
        pub fn hasFormatted(self: *const FormatterStats) bool {
            return self.getTotalFormatted() > 0;
        }

        /// Check if any JSON formats have been used.
        pub fn hasJsonFormats(self: *const FormatterStats) bool {
            return self.getJsonFormats() > 0;
        }

        /// Check if any custom formats have been used.
        pub fn hasCustomFormats(self: *const FormatterStats) bool {
            return self.getCustomFormats() > 0;
        }

        /// Check if any format errors have occurred.
        pub fn hasErrors(self: *const FormatterStats) bool {
            return self.getFormatErrors() > 0;
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
                @as(f64, @floatFromInt(self.getTotalBytesFormatted())),
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
    };

    /// Memory allocator for formatting operations.
    allocator: std.mem.Allocator,
    /// Formatter statistics.
    stats: FormatterStats = .{},
    /// Mutex for thread-safe operations.
    mutex: std.Thread.Mutex = .{},

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

    /// Defines a color theme for log levels.
    pub const Theme = struct {
        trace: []const u8 = "36", // Cyan
        debug: []const u8 = "34", // Blue
        info: []const u8 = "37", // White
        success: []const u8 = "32", // Green
        warning: []const u8 = "33", // Yellow
        err: []const u8 = "31", // Red
        fail: []const u8 = "35", // Magenta
        critical: []const u8 = "91", // Bright Red

        pub fn getColor(self: Theme, level: Level) []const u8 {
            return switch (level) {
                .trace => self.trace,
                .debug => self.debug,
                .info => self.info,
                .notice => "96",
                .success => self.success,
                .warning => self.warning,
                .err => self.err,
                .fail => self.fail,
                .critical => self.critical,
                .fatal => "97;41",
            };
        }
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
        self.mutex.lock();
        defer self.mutex.unlock();
        self.on_format_complete = callback;
    }

    /// Sets the callback for JSON formatting.
    pub fn setJsonFormatCallback(self: *Formatter, callback: *const fn (*const Record, u64) void) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.on_json_format = callback;
    }

    /// Sets the callback for custom formatting.
    pub fn setCustomFormatCallback(self: *Formatter, callback: *const fn ([]const u8, u64) void) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.on_custom_format = callback;
    }

    /// Sets the callback for format errors.
    pub fn setErrorCallback(self: *Formatter, callback: *const fn ([]const u8) void) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.on_format_error = callback;
    }

    /// Sets a custom color theme.
    pub fn setTheme(self: *Formatter, theme: Theme) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.theme = theme;
    }

    /// Returns formatter statistics.
    pub fn getStats(self: *Formatter) FormatterStats {
        self.mutex.lock();
        defer self.mutex.unlock();

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
        const start_time = std.time.nanoTimestamp();
        defer {
            const elapsed = @as(u64, @intCast(@max(0, std.time.nanoTimestamp() - start_time)));
            _ = self.stats.total_records_formatted.fetchAdd(1, .monotonic);
            _ = self.stats.total_bytes_formatted.fetchAdd(100, .monotonic); // Estimation, real size difficult to get here efficiently without double pass
            // In a real implementation we would track precise bytes
            _ = elapsed;
        }

        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.configIsJson(config)) {
            return self.formatJsonWithAllocator(record, config, scratch_allocator);
        }

        var buf: std.ArrayList(u8) = .empty;
        errdefer buf.deinit(alloc);
        const writer = buf.writer(alloc);

        if (self.configIsCustom(config)) {
            _ = self.stats.custom_formats.fetchAdd(1, .monotonic);
        }

        try self.formatToWriter(writer, record, config);

        if (self.on_format_complete) |cb| {
            cb(0, buf.items.len);
        }

        return buf.toOwnedSlice(alloc);
    }

    /// Internal helper to detect if JSON config is active.
    fn configIsJson(self: *Formatter, config: anytype) bool {
        _ = self;
        return if (@hasField(@TypeOf(config), "json")) config.json else false;
    }

    /// Internal helper to detect if custom format is active.
    fn configIsCustom(self: *Formatter, config: anytype) bool {
        _ = self;
        return if (@hasField(@TypeOf(config), "log_format")) config.log_format != null else false;
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
        // Use custom color if available, otherwise use standard level color or theme
        var color_code = record.levelColor();
        if (self.theme) |t| {
            // Only override if record doesn't have a custom color
            if (record.custom_level_color == null) {
                color_code = t.getColor(record.level);
            }
        }

        // Check for custom log format
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

                    if (std.mem.eql(u8, tag, "time")) {
                        try self.writeTimestamp(writer, record.timestamp, config);
                    } else if (std.mem.eql(u8, tag, "level")) {
                        // Use custom level name if available
                        try writer.writeAll(record.levelName());
                    } else if (std.mem.eql(u8, tag, "message")) {
                        try writer.writeAll(record.message);
                    } else if (std.mem.eql(u8, tag, "module")) {
                        if (record.module) |m| try writer.writeAll(m);
                    } else if (std.mem.eql(u8, tag, "function")) {
                        if (record.function) |f| try writer.writeAll(f);
                    } else if (std.mem.eql(u8, tag, "file")) {
                        if (record.filename) |f| try writer.writeAll(f);
                    } else if (std.mem.eql(u8, tag, "line")) {
                        if (record.line) |l| try Utils.writeInt(writer, l);
                    } else if (std.mem.eql(u8, tag, "thread")) {
                        if (record.thread_id) |tid| try Utils.writeInt(writer, tid);
                    } else if (std.mem.eql(u8, tag, "trace_id")) {
                        if (record.trace_id) |tid| try writer.writeAll(tid);
                    } else if (std.mem.eql(u8, tag, "span_id")) {
                        if (record.span_id) |sid| try writer.writeAll(sid);
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
                            // Attempt to get module and symbol
                            // Note: getSymbolAtAddress allocates unless we provide a buffer,
                            // but here it uses di.allocator which is typically gpa
                            if (di.getModuleForAddress(addr) catch null) |module| {
                                if (module.getSymbolAtAddress(di.allocator, addr) catch null) |symbol| {
                                    if (symbol.source_location) |sl| {
                                        try writer.print("  {s} ({s}:{d})\n", .{ symbol.name, sl.file_name, sl.line });
                                    } else {
                                        try writer.print("  {s}\n", .{symbol.name});
                                    }
                                } else {
                                    try writer.print("  0x{x}\n", .{addr});
                                }
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

    fn writeTimestamp(self: *Formatter, writer: anytype, timestamp_ms: i64, config: anytype) !void {
        _ = self;

        // Handle special time formats
        if (std.mem.eql(u8, config.time_format, "unix")) {
            try Utils.writeInt(writer, @as(u64, @intCast(@divFloor(timestamp_ms, 1000))));
            return;
        }
        if (std.mem.eql(u8, config.time_format, "unix_ms")) {
            try Utils.writeInt(writer, @as(u64, @intCast(timestamp_ms)));
            return;
        }

        const tc = Utils.fromMilliTimestamp(timestamp_ms);
        const abs_ts = if (timestamp_ms < 0) 0 else @as(u64, @intCast(timestamp_ms));
        const millis = abs_ts % 1000;

        // ISO8601 format: 2025-12-04T06:39:53.091Z
        if (std.mem.eql(u8, config.time_format, "ISO8601")) {
            try Utils.writeIsoDateTime(writer, tc);
            try writer.writeByte('.');
            try Utils.write3Digits(writer, millis);
            try writer.writeByte('Z');
            return;
        }

        // RFC3339 format: 2025-12-04T06:39:53+00:00
        if (std.mem.eql(u8, config.time_format, "RFC3339")) {
            try Utils.writeIsoDateTime(writer, tc);
            try writer.writeAll("+00:00");
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
        try Utils.formatDatePattern(writer, config.time_format, tc.year, tc.month, tc.day, tc.hour, tc.minute, tc.second, millis);
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
        var buf: std.ArrayList(u8) = .empty;
        errdefer buf.deinit(alloc);
        const writer = buf.writer(alloc);
        try self.formatJsonToWriter(writer, record, config);

        _ = self.stats.json_formats.fetchAdd(1, .monotonic);

        if (self.on_json_format) |cb| {
            cb(record, buf.items.len);
        }

        return buf.toOwnedSlice(alloc);
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
        if (std.mem.eql(u8, config.time_format, "unix")) {
            try Utils.writeInt(writer, @as(u64, @intCast(@divFloor(record.timestamp, 1000))));
        } else {
            try writer.writeAll("\"");
            try self.writeTimestamp(writer, record.timestamp, config);
            try writer.writeAll("\"");
        }

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
                        if (di.getModuleForAddress(addr) catch null) |module| {
                            if (module.getSymbolAtAddress(di.allocator, addr) catch null) |symbol| {
                                if (symbol.source_location) |sl| {
                                    try writer.print("\"{s} ({s}:{d})\"", .{ symbol.name, sl.file_name, sl.line });
                                } else {
                                    try writer.print("\"{s}\"", .{symbol.name});
                                }
                            } else {
                                try writer.print("\"{x}\"", .{addr});
                            }
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

    /// Alias for format
    pub const render = format;
    pub const output = format;

    /// Alias for formatToWriter
    pub const renderToWriter = formatToWriter;
    pub const writeFormatted = formatToWriter;

    /// Alias for formatJson
    pub const json = formatJson;
    pub const toJson = formatJson;

    /// Alias for formatJsonToWriter
    pub const jsonToWriter = formatJsonToWriter;
    pub const writeJson = formatJsonToWriter;

    /// Alias for getStats
    pub const statistics = getStats;

    /// Alias for setTheme
    pub const colors = setTheme;
};

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

    /// Creates a formatter with dark theme.
    pub fn dark(allocator: std.mem.Allocator) Formatter {
        var f = Formatter.init(allocator);
        f.theme = Formatter.Theme.dark();
        return f;
    }

    /// Creates a formatter with light theme.
    pub fn light(allocator: std.mem.Allocator) Formatter {
        var f = Formatter.init(allocator);
        f.theme = Formatter.Theme.light();
        return f;
    }
};

test "formatter plain text" {
    const allocator = std.testing.allocator;
    var formatter = Formatter.init(allocator);
    defer formatter.deinit();

    var record = Record.init(allocator, .info, "Test message");
    defer record.deinit();
    record.module = "test_mod";
    record.timestamp = 1700000000000;

    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(allocator);

    try formatter.formatToWriter(buf.writer(allocator), &record, Config{});
    const output_str = buf.items;

    try std.testing.expect(std.mem.indexOf(u8, output_str, "INFO") != null);
    try std.testing.expect(std.mem.indexOf(u8, output_str, "test_mod") != null);
    try std.testing.expect(std.mem.indexOf(u8, output_str, "Test message") != null);
}

test "formatter json" {
    const allocator = std.testing.allocator;
    var formatter = Formatter.init(allocator);
    defer formatter.deinit();

    var record = Record.init(allocator, .err, "Error occurred");
    defer record.deinit();
    record.module = "api";
    record.timestamp = 1700000000000;

    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(allocator);

    try formatter.formatJsonToWriter(buf.writer(allocator), &record, Config{});
    const output_str = buf.items;

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

    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(allocator);

    try formatter.formatJsonToWriter(buf.writer(allocator), &record, config);
    const output_str = buf.items;

    try std.testing.expect(std.mem.indexOf(u8, output_str, "\"service\":\"test-service\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output_str, "\"region\":\"us-east-1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output_str, "\"trace_id\":\"trace-123\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output_str, "\"span_id\":\"span-456\"") != null);
}
