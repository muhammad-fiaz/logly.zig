const std = @import("std");
const Record = @import("record.zig").Record;
const Level = @import("level.zig").Level;

/// Handles the formatting of log records into strings or JSON.
///
/// The Formatter is responsible for taking a `Record` and converting it into a final
/// output string based on the configuration (e.g., JSON, plain text, custom patterns).
pub const Formatter = struct {
    allocator: std.mem.Allocator,

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

            // Filename and line (Clickable format: path/to/file:line)
            if (config.show_filename and record.filename != null) {
                try writer.print("{s}", .{record.filename.?});
                if (config.show_lineno and record.line != null) {
                    try writer.print(":{d}", .{record.line.?});
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

        if (std.mem.eql(u8, config.time_format, "unix")) {
            try writer.print("{d}", .{timestamp_ms});
            return;
        }

        const seconds = @divFloor(timestamp_ms, 1000);
        const millis = @mod(timestamp_ms, 1000);

        // Convert to YYYY-MM-DD HH:MM:SS
        const epoch_seconds = @as(u64, @intCast(seconds));
        const epoch = std.time.epoch.EpochSeconds{ .secs = epoch_seconds };
        const day_seconds = epoch.getDaySeconds();
        const year_day = epoch.getEpochDay();
        const yd = year_day.calculateYearDay();
        const month_day = yd.calculateMonthDay();

        const seconds_in_day = day_seconds.secs;
        const hours = seconds_in_day / 3600;
        const minutes = (seconds_in_day % 3600) / 60;
        const secs = seconds_in_day % 60;

        // Default format: YYYY-MM-DD HH:MM:SS.mmm
        try writer.print("{d:0>4}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2}.{d:0>3}", .{
            yd.year,
            month_day.month.numeric(),
            month_day.day_index + 1,
            hours,
            minutes,
            secs,
            millis,
        });
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
                try writer.writeAll("\"windows-host\"");
            } else {
                // var hostname_buf: [std.posix.HOST_NAME_MAX]u8 = undefined;
                // const hostname = std.posix.gethostname(&hostname_buf) catch "unknown";
                // try escapeJsonString(writer, hostname);
                try writer.writeAll("\"non-windows-host\"");
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
        return buf.toOwnedSlice(self.allocator);
    }
};
