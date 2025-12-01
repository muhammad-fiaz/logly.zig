const std = @import("std");
const Record = @import("record.zig").Record;
const Level = @import("level.zig").Level;

pub const Formatter = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Formatter {
        return .{ .allocator = allocator };
    }

    pub fn deinit(_: *Formatter) void {}

    pub fn format(self: *Formatter, record: *const Record, config: anytype) ![]u8 {
        var buf: std.ArrayList(u8) = .empty;
        errdefer buf.deinit(self.allocator);
        const writer = buf.writer(self.allocator);

        // Color prefix
        if (config.color and config.global_color_display) {
            try writer.print("\x1b[{s}m", .{record.level.defaultColor()});
        }

        // Timestamp
        if (config.show_time) {
            const timestamp = @as(u64, @intCast(record.timestamp));
            const seconds = @divFloor(timestamp, 1000);
            const millis = @mod(timestamp, 1000);
            try writer.print("[{d}.{d:0>3}] ", .{ seconds, millis });
        }

        // Level
        try writer.print("[{s}] ", .{record.level.asString()});

        // Module
        if (config.show_module and record.module != null) {
            try writer.print("[{s}] ", .{record.module.?});
        }

        // Function
        if (config.show_function and record.function != null) {
            try writer.print("[{s}] ", .{record.function.?});
        }

        // Filename and line
        if (config.show_filename and record.filename != null) {
            try writer.print("[{s}", .{record.filename.?});
            if (config.show_lineno and record.line != null) {
                try writer.print(":{d}", .{record.line.?});
            }
            try writer.writeAll("] ");
        }

        // Message
        try writer.writeAll(record.message);

        // Color reset
        if (config.color and config.global_color_display) {
            try writer.writeAll("\x1b[0m");
        }

        return buf.toOwnedSlice(self.allocator);
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
        try writer.print("{s}\"timestamp\"{s}{d}", .{ indent, sep, record.timestamp });

        // Level
        try writer.writeAll(comma);
        try writer.print("{s}\"level\"{s}\"{s}\"", .{ indent, sep, record.level.asString() });

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
