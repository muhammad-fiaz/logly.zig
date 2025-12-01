const std = @import("std");

/// Log levels with associated priorities
pub const Level = enum(u8) {
    trace = 5,
    debug = 10,
    info = 20,
    success = 25,
    warning = 30,
    err = 40,
    fail = 45,
    critical = 50,

    pub fn priority(self: Level) u8 {
        return @intFromEnum(self);
    }

    pub fn fromPriority(p: u8) ?Level {
        return switch (p) {
            5 => .trace,
            10 => .debug,
            20 => .info,
            25 => .success,
            30 => .warning,
            40 => .err,
            45 => .fail,
            50 => .critical,
            else => null,
        };
    }

    pub fn asString(self: Level) []const u8 {
        return switch (self) {
            .trace => "TRACE",
            .debug => "DEBUG",
            .info => "INFO",
            .success => "SUCCESS",
            .warning => "WARNING",
            .err => "ERROR",
            .fail => "FAIL",
            .critical => "CRITICAL",
        };
    }

    pub fn defaultColor(self: Level) []const u8 {
        return switch (self) {
            .trace => "36", // Cyan
            .debug => "34", // Blue
            .info => "37", // White
            .success => "32", // Green
            .warning => "33", // Yellow
            .err => "31", // Red
            .fail => "35", // Magenta
            .critical => "91", // Bright Red
        };
    }

    pub fn fromString(s: []const u8) ?Level {
        if (std.mem.eql(u8, s, "TRACE")) return .trace;
        if (std.mem.eql(u8, s, "DEBUG")) return .debug;
        if (std.mem.eql(u8, s, "INFO")) return .info;
        if (std.mem.eql(u8, s, "SUCCESS")) return .success;
        if (std.mem.eql(u8, s, "WARNING")) return .warning;
        if (std.mem.eql(u8, s, "ERROR")) return .err;
        if (std.mem.eql(u8, s, "FAIL")) return .fail;
        if (std.mem.eql(u8, s, "CRITICAL")) return .critical;
        return null;
    }
};

pub const CustomLevel = struct {
    name: []const u8,
    priority: u8,
    color: []const u8,
};

test "level priority" {
    try std.testing.expectEqual(@as(u8, 5), Level.trace.priority());
    try std.testing.expectEqual(@as(u8, 50), Level.critical.priority());
}

test "level from priority" {
    try std.testing.expectEqual(Level.info, Level.fromPriority(20).?);
    try std.testing.expectEqual(@as(?Level, null), Level.fromPriority(99));
}

test "level string conversion" {
    try std.testing.expectEqualStrings("INFO", Level.info.asString());
    try std.testing.expectEqual(Level.warning, Level.fromString("WARNING").?);
}
