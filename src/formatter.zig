const std = @import("std");
const Config = @import("config.zig").Config;
const Record = @import("record.zig").Record;
const Level = @import("level.zig").Level;

/// Handles the formatting of log records into strings or JSON.
///
/// The Formatter is responsible for taking a `Record` and converting it into a final
/// output string based on the configuration (e.g., JSON, plain text, custom patterns).
///
/// Callbacks:
/// - `on_format_complete`: Called after a record is formatted
/// - `on_json_format`: Called when formatting as JSON
/// - `on_custom_format`: Called when using custom format string
/// - `on_format_error`: Called when formatting fails
///
/// Performance:
/// - O(n) where n = output string length
/// - Minimal allocations with StringBuilder pattern
/// - Lock-free formatting operations
pub const Formatter = struct {
    /// Formatter statistics for monitoring and diagnostics.
    pub const FormatterStats = struct {
        total_records_formatted: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
        json_formats: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
        custom_formats: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
        format_errors: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
        total_bytes_formatted: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),

        /// Calculate average format size
        pub fn avgFormatSize(self: *const FormatterStats) f64 {
            const total = self.total_records_formatted.load(.monotonic);
            if (total == 0) return 0;
            const bytes = self.total_bytes_formatted.load(.monotonic);
            return @as(f64, @floatFromInt(bytes)) / @as(f64, @floatFromInt(total));
        }

        /// Calculate error rate (0.0 - 1.0)
        pub fn errorRate(self: *const FormatterStats) f64 {
            const total = self.total_records_formatted.load(.monotonic);
            if (total == 0) return 0;
            const errors = self.format_errors.load(.monotonic);
            return @as(f64, @floatFromInt(errors)) / @as(f64, @floatFromInt(total));
        }
    };

    allocator: std.mem.Allocator,
    stats: FormatterStats = .{},
    mutex: std.Thread.Mutex = .{},

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

    /// Initializes a new Formatter.
    ///
    /// Arguments:
    /// * `allocator`: The allocator used for string building.
    pub fn init(allocator: std.mem.Allocator) Formatter {
        return .{ .allocator = allocator };
    }

    /// Deinitializes the Formatter.
    ///
    /// Currently a no-op as the formatter doesn't hold persistent resources,
    /// but good for future-proofing! 🔮
    pub fn deinit(_: *Formatter) void {}

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

    /// Returns formatter statistics.
    pub fn getStats(self: *Formatter) FormatterStats {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.stats;
    }

    /// Formats a log record into a string.
    ///
    /// This function handles:
    /// *   Custom format strings (parsing tags like `{time}`, `{level}`).
    /// *   Default text formatting.
    /// *   Color application (ENTIRE line is colored, not just level tag).
    ///
    /// Arguments:
    /// * `record`: The log record to format.
    /// * `config`: The configuration object (Config or SinkConfig).
    ///
    /// Returns:
    /// * `![]u8`: The formatted string (caller must free).
    pub fn format(self: *Formatter, record: *const Record, config: anytype) ![]u8 {
        var buf: std.ArrayList(u8) = .empty;
        errdefer buf.deinit(self.allocator);
        const writer = buf.writer(self.allocator);

        const use_color = config.color and config.global_color_display;
        // Use custom color if available, otherwise use standard level color
        const color_code = record.levelColor();

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
                        if (record.line) |l| try writer.print("{d}", .{l});
                    } else if (std.mem.eql(u8, tag, "thread")) {
                        if (record.thread_id) |tid| try writer.print("{d}", .{tid});
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
            try writer.print("[{s}] ", .{record.levelName()});

            // Module
            if (config.show_module and record.module != null) {
                try writer.print("[{s}] ", .{record.module.?});
            }

            // Function
            if (config.show_function and record.function != null) {
                try writer.print("[{s}] ", .{record.function.?});
            }

            // Thread ID
            if (config.show_thread_id and record.thread_id != null) {
                try writer.print("[TID:{d}] ", .{record.thread_id.?});
            }

            // Filename and line (Clickable format: file:line:column: for terminal clickability)
            if (config.show_filename and record.filename != null) {
                try writer.print("{s}", .{record.filename.?});
                if (config.show_lineno and record.line != null) {
                    try writer.print(":{d}:0:", .{record.line.?});
                } else {
                    try writer.writeAll(":0:0:");
                }
                try writer.writeAll(" ");
            }

            // Message
            try writer.writeAll(record.message);

            // Reset color at end of entire line
            if (use_color) {
                try writer.writeAll("\x1b[0m");
            }
        }

        return buf.toOwnedSlice(self.allocator);
    }

    fn writeTimestamp(self: *Formatter, writer: anytype, timestamp_ms: i64, config: anytype) !void {
        _ = self;

        // Handle special time formats
        if (std.mem.eql(u8, config.time_format, "unix")) {
            try writer.print("{d}", .{@divFloor(timestamp_ms, 1000)});
            return;
        }
        if (std.mem.eql(u8, config.time_format, "unix_ms")) {
            try writer.print("{d}", .{timestamp_ms});
            return;
        }

        // Ensure positive values for date/time calculation
        const abs_timestamp = if (timestamp_ms < 0) @as(u64, 0) else @as(u64, @intCast(timestamp_ms));
        const seconds = abs_timestamp / 1000;
        const millis = abs_timestamp % 1000;

        // Convert to date/time components
        const epoch = std.time.epoch.EpochSeconds{ .secs = seconds };
        const day_seconds = epoch.getDaySeconds();
        const year_day = epoch.getEpochDay();
        const yd = year_day.calculateYearDay();
        const month_day = yd.calculateMonthDay();

        const seconds_in_day = day_seconds.secs;
        const hours = seconds_in_day / 3600;
        const minutes = (seconds_in_day % 3600) / 60;
        const secs = seconds_in_day % 60;

        // ISO8601 format: 2025-12-04T06:39:53.091Z
        if (std.mem.eql(u8, config.time_format, "ISO8601")) {
            try writer.print("{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}.{d:0>3}Z", .{
                yd.year,
                month_day.month.numeric(),
                month_day.day_index + 1,
                hours,
                minutes,
                secs,
                millis,
            });
            return;
        }

        // RFC3339 format: 2025-12-04T06:39:53+00:00
        if (std.mem.eql(u8, config.time_format, "RFC3339")) {
            try writer.print("{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}+00:00", .{
                yd.year,
                month_day.month.numeric(),
                month_day.day_index + 1,
                hours,
                minutes,
                secs,
            });
            return;
        }

        // Custom format parsing - supports any format with placeholders:
        // YYYY = 4-digit year, YY = 2-digit year
        // MM = 2-digit month, M = 1-2 digit month
        // DD = 2-digit day, D = 1-2 digit day
        // HH = 2-digit hour (24h), hh = 2-digit hour (12h)
        // mm = 2-digit minute
        // ss = 2-digit second
        // SSS = 3-digit millisecond
        // Any other characters are output literally (-, /, :, space, T, etc.)
        try writeCustomFormat(writer, config.time_format, yd.year, month_day.month.numeric(), month_day.day_index + 1, hours, minutes, secs, millis);
    }

    /// Writes a timestamp using a custom format string.
    /// Supports placeholders: YYYY, YY, MM, M, DD, D, HH, hh, mm, ss, SSS
    /// Any other characters are written literally.
    fn writeCustomFormat(
        writer: anytype,
        fmt: []const u8,
        year: i32,
        month: u9,
        day: u9,
        hours: u64,
        minutes: u64,
        secs: u64,
        millis: u64,
    ) !void {
        var i: usize = 0;
        while (i < fmt.len) {
            // Check for YYYY (4-digit year)
            if (i + 4 <= fmt.len and std.mem.eql(u8, fmt[i .. i + 4], "YYYY")) {
                const abs_year: u32 = @intCast(if (year < 0) 0 else year);
                try writer.print("{d:0>4}", .{abs_year});
                i += 4;
                continue;
            }
            // Check for YY (2-digit year)
            if (i + 2 <= fmt.len and std.mem.eql(u8, fmt[i .. i + 2], "YY")) {
                const short_year = @mod(@as(u32, @intCast(if (year < 0) 0 else year)), 100);
                try writer.print("{d:0>2}", .{short_year});
                i += 2;
                continue;
            }
            // Check for SSS (3-digit milliseconds) - must check before ss
            if (i + 3 <= fmt.len and std.mem.eql(u8, fmt[i .. i + 3], "SSS")) {
                try writer.print("{d:0>3}", .{millis});
                i += 3;
                continue;
            }
            // Check for MM (2-digit month)
            if (i + 2 <= fmt.len and std.mem.eql(u8, fmt[i .. i + 2], "MM")) {
                try writer.print("{d:0>2}", .{month});
                i += 2;
                continue;
            }
            // Check for M (1-2 digit month)
            if (i + 1 <= fmt.len and fmt[i] == 'M' and (i + 1 >= fmt.len or fmt[i + 1] != 'M')) {
                try writer.print("{d}", .{month});
                i += 1;
                continue;
            }
            // Check for DD (2-digit day)
            if (i + 2 <= fmt.len and std.mem.eql(u8, fmt[i .. i + 2], "DD")) {
                try writer.print("{d:0>2}", .{day});
                i += 2;
                continue;
            }
            // Check for D (1-2 digit day)
            if (i + 1 <= fmt.len and fmt[i] == 'D' and (i + 1 >= fmt.len or fmt[i + 1] != 'D')) {
                try writer.print("{d}", .{day});
                i += 1;
                continue;
            }
            // Check for HH (2-digit hour 24h)
            if (i + 2 <= fmt.len and std.mem.eql(u8, fmt[i .. i + 2], "HH")) {
                try writer.print("{d:0>2}", .{hours});
                i += 2;
                continue;
            }
            // Check for hh (2-digit hour 12h)
            if (i + 2 <= fmt.len and std.mem.eql(u8, fmt[i .. i + 2], "hh")) {
                const hour12 = if (hours == 0) 12 else if (hours > 12) hours - 12 else hours;
                try writer.print("{d:0>2}", .{hour12});
                i += 2;
                continue;
            }
            // Check for mm (2-digit minute)
            if (i + 2 <= fmt.len and std.mem.eql(u8, fmt[i .. i + 2], "mm")) {
                try writer.print("{d:0>2}", .{minutes});
                i += 2;
                continue;
            }
            // Check for ss (2-digit second)
            if (i + 2 <= fmt.len and std.mem.eql(u8, fmt[i .. i + 2], "ss")) {
                try writer.print("{d:0>2}", .{secs});
                i += 2;
                continue;
            }
            // Any other character - write literally
            try writer.writeByte(fmt[i]);
            i += 1;
        }
    }

    fn escapeJsonString(writer: anytype, s: []const u8) !void {
        for (s) |c| {
            switch (c) {
                '"' => try writer.writeAll("\\\""),
                '\\' => try writer.writeAll("\\\\"),
                '\x08' => try writer.writeAll("\\b"),
                '\x0c' => try writer.writeAll("\\f"),
                '\n' => try writer.writeAll("\\n"),
                '\r' => try writer.writeAll("\\r"),
                '\t' => try writer.writeAll("\\t"),
                else => {
                    if (c < 0x20) {
                        try writer.print("\\u{x:0>4}", .{c});
                    } else {
                        try writer.writeByte(c);
                    }
                },
            }
        }
    }

    pub fn formatJson(self: *Formatter, record: *const Record, config: anytype) ![]u8 {
        var buf: std.ArrayList(u8) = .empty;
        errdefer buf.deinit(self.allocator);
        const writer = buf.writer(self.allocator);

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
            try writer.print("\x1b[{s}m", .{color_code});
        }

        try writer.writeAll("{");
        try writer.writeAll(newline);

        // Timestamp
        try writer.print("{s}\"timestamp\"{s}", .{ indent, sep });
        if (std.mem.eql(u8, config.time_format, "unix")) {
            try writer.print("{d}", .{record.timestamp});
        } else {
            try writer.writeAll("\"");
            try self.writeTimestamp(writer, record.timestamp, config);
            try writer.writeAll("\"");
        }

        // Level (use custom name if available)
        try writer.writeAll(comma);
        try writer.print("{s}\"level\"{s}\"{s}\"", .{ indent, sep, record.levelName() });

        // Message
        try writer.writeAll(comma);
        try writer.print("{s}\"message\"{s}\"", .{ indent, sep });
        try escapeJsonString(writer, record.message);
        try writer.writeAll("\"");

        // Optional fields
        if (record.module) |m| {
            try writer.writeAll(comma);
            try writer.print("{s}\"module\"{s}\"", .{ indent, sep });
            try escapeJsonString(writer, m);
            try writer.writeAll("\"");
        }
        if (record.function) |f| {
            try writer.writeAll(comma);
            try writer.print("{s}\"function\"{s}\"", .{ indent, sep });
            try escapeJsonString(writer, f);
            try writer.writeAll("\"");
        }
        if (record.filename) |f| {
            try writer.writeAll(comma);
            try writer.print("{s}\"filename\"{s}\"", .{ indent, sep });
            try escapeJsonString(writer, f);
            try writer.writeAll("\"");
        }
        if (record.line) |l| {
            try writer.writeAll(comma);
            try writer.print("{s}\"line\"{s}{d}", .{ indent, sep, l });
        }

        // Hostname and PID
        if (config.include_hostname) {
            try writer.writeAll(comma);
            try writer.print("{s}\"hostname\"{s}\"", .{ indent, sep });

            // 🐛 Workaround: std.posix.gethostname seems to have issues on some Windows builds.
            // We'll use a safe fallback for now to ensure the library compiles.
            if (@import("builtin").os.tag == .windows) {
                try writer.writeAll("windows-host");
            } else {
                // var hostname_buf: [std.posix.HOST_NAME_MAX]u8 = undefined;
                // const hostname = std.posix.gethostname(&hostname_buf) catch "unknown";
                // try escapeJsonString(writer, hostname);
                try writer.writeAll("non-windows-host");
            }
            try writer.writeAll("\"");
        }

        if (config.include_pid) {
            try writer.writeAll(comma);

            // 🐛 Workaround: PID retrieval can be tricky across platforms in Zig.
            // We'll use a safe fallback or platform-specific calls where we are sure.
            const pid = switch (@import("builtin").os.tag) {
                // .windows => std.os.windows.kernel32.GetCurrentProcessId(), // Not found in this Zig version
                else => 0,
            };

            try writer.print("{s}\"pid\"{s}{d}", .{ indent, sep, pid });
        }

        // Context fields
        var it = record.context.iterator();
        while (it.next()) |entry| {
            try writer.writeAll(comma);
            try writer.print("{s}\"", .{indent});
            try escapeJsonString(writer, entry.key_ptr.*);
            try writer.print("\"{s}", .{sep});
            switch (entry.value_ptr.*) {
                .string => |s| {
                    try writer.writeAll("\"");
                    try escapeJsonString(writer, s);
                    try writer.writeAll("\"");
                },
                .integer => |i| try writer.print("{d}", .{i}),
                .float => |f| try writer.print("{d}", .{f}),
                .bool => |b| try writer.print("{}", .{b}),
                else => try writer.writeAll("null"),
            }
        }

        try writer.writeAll(newline);
        try writer.writeAll("}");

        // Reset color at end of JSON
        if (use_color) {
            try writer.writeAll("\x1b[0m");
        }

        return buf.toOwnedSlice(self.allocator);
    }
};
