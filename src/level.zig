const std = @import("std");

/// Defines the standard logging levels and their priorities.
///
/// Levels are ordered by priority, where higher values indicate higher severity.
/// *   `trace` (5): Detailed tracing information.
/// *   `debug` (10): Debugging information.
/// *   `info` (20): General informational messages.
/// *   `notice` (22): Notice messages.
/// *   `success` (25): Successful operations (often green).
/// *   `warning` (30): Warning conditions.
/// *   `err` (40): Error conditions.
/// *   `fail` (45): Failure conditions (often red).
/// *   `critical` (50): Critical failures (often bold red/background).
/// *   `fatal` (55): Fatal system errors (highest severity).
///
/// Usage:
/// ```zig
/// // Check if a level is enabled
/// if (level.priority() >= config.level.priority()) {
///     // Log message
/// }
///
/// // Convert to string
/// const str = level.asString();
/// ```
pub const Level = enum(u8) {
    // 🔍 Detailed tracing information
    trace = 5,
    // 🐛 Debugging information
    debug = 10,
    // ℹ️ General information
    info = 20,
    // 📢 Notice messages
    notice = 22,
    // ✅ Success messages
    success = 25,
    // ⚠️ Warnings
    warning = 30,
    // ❌ Errors
    err = 40,
    // 🛑 Failures
    fail = 45,
    // 🚨 Critical failures
    critical = 50,
    // ☠️ Fatal system errors
    fatal = 55,

    pub fn priority(self: Level) u8 {
        return @intFromEnum(self);
    }

    pub fn fromPriority(p: u8) ?Level {
        return switch (p) {
            5 => .trace,
            10 => .debug,
            20 => .info,
            22 => .notice,
            25 => .success,
            30 => .warning,
            40 => .err,
            45 => .fail,
            50 => .critical,
            55 => .fatal,
            else => null,
        };
    }

    pub fn asString(self: Level) []const u8 {
        return switch (self) {
            .trace => "TRACE",
            .debug => "DEBUG",
            .info => "INFO",
            .notice => "NOTICE",
            .success => "SUCCESS",
            .warning => "WARNING",
            .err => "ERROR",
            .fail => "FAIL",
            .critical => "CRITICAL",
            .fatal => "FATAL",
        };
    }

    pub fn defaultColor(self: Level) []const u8 {
        return switch (self) {
            .trace => "36", // Cyan
            .debug => "34", // Blue
            .info => "37", // White
            .notice => "96", // Bright Cyan
            .success => "32", // Green
            .warning => "33", // Yellow
            .err => "31", // Red
            .fail => "35", // Magenta
            .critical => "91", // Bright Red
            .fatal => "97;41", // White on Red background
        };
    }

    pub fn fromString(s: []const u8) ?Level {
        if (std.mem.eql(u8, s, "TRACE")) return .trace;
        if (std.mem.eql(u8, s, "DEBUG")) return .debug;
        if (std.mem.eql(u8, s, "INFO")) return .info;
        if (std.mem.eql(u8, s, "NOTICE")) return .notice;
        if (std.mem.eql(u8, s, "SUCCESS")) return .success;
        if (std.mem.eql(u8, s, "WARNING")) return .warning;
        if (std.mem.eql(u8, s, "ERROR")) return .err;
        if (std.mem.eql(u8, s, "FAIL")) return .fail;
        if (std.mem.eql(u8, s, "CRITICAL")) return .critical;
        if (std.mem.eql(u8, s, "FATAL")) return .fatal;
        return null;
    }

    /// Alias for priority
    pub const value = priority;
    pub const severity = priority;

    /// Alias for asString
    pub const toString = asString;
    pub const str = asString;

    /// Alias for defaultColor
    pub const color = defaultColor;

    /// Alias for fromString
    pub const parse = fromString;

    /// Returns true if this level is at least as severe as the given level.
    pub fn isAtLeast(self: Level, other: Level) bool {
        return self.priority() >= other.priority();
    }

    /// Returns true if this level is more severe than the given level.
    pub fn isMoreSevereThan(self: Level, other: Level) bool {
        return self.priority() > other.priority();
    }

    /// Returns true if this is an error-level or higher.
    pub fn isError(self: Level) bool {
        return self.priority() >= Level.err.priority();
    }

    /// Returns true if this is a warning-level.
    pub fn isWarning(self: Level) bool {
        return self == .warning;
    }

    /// Returns true if this is debug or trace level.
    pub fn isDebug(self: Level) bool {
        return self == .debug or self == .trace;
    }
};

pub const CustomLevel = struct {
    name: []const u8,
    priority: u8,
    color: []const u8,

    /// Creates a new custom level.
    pub fn init(level_name: []const u8, level_priority: u8, level_color: []const u8) CustomLevel {
        return .{
            .name = level_name,
            .priority = level_priority,
            .color = level_color,
        };
    }

    /// Returns true if this custom level is at least as severe as standard level.
    pub fn isAtLeast(self: CustomLevel, level: Level) bool {
        return self.priority >= level.priority();
    }

    /// Returns true if this is an error-level or higher.
    pub fn isError(self: CustomLevel) bool {
        return self.priority >= Level.err.priority();
    }

    /// Alias for name
    pub fn asString(self: CustomLevel) []const u8 {
        return self.name;
    }
};

test "level priority" {
    try std.testing.expectEqual(@as(u8, 5), Level.trace.priority());
    try std.testing.expectEqual(@as(u8, 10), Level.debug.priority());
    try std.testing.expectEqual(@as(u8, 20), Level.info.priority());
    try std.testing.expectEqual(@as(u8, 22), Level.notice.priority());
    try std.testing.expectEqual(@as(u8, 25), Level.success.priority());
    try std.testing.expectEqual(@as(u8, 30), Level.warning.priority());
    try std.testing.expectEqual(@as(u8, 40), Level.err.priority());
    try std.testing.expectEqual(@as(u8, 45), Level.fail.priority());
    try std.testing.expectEqual(@as(u8, 50), Level.critical.priority());
    try std.testing.expectEqual(@as(u8, 55), Level.fatal.priority());
}

test "level from priority" {
    try std.testing.expectEqual(Level.trace, Level.fromPriority(5).?);
    try std.testing.expectEqual(Level.debug, Level.fromPriority(10).?);
    try std.testing.expectEqual(Level.info, Level.fromPriority(20).?);
    try std.testing.expectEqual(Level.notice, Level.fromPriority(22).?);
    try std.testing.expectEqual(Level.success, Level.fromPriority(25).?);
    try std.testing.expectEqual(Level.warning, Level.fromPriority(30).?);
    try std.testing.expectEqual(Level.err, Level.fromPriority(40).?);
    try std.testing.expectEqual(Level.fail, Level.fromPriority(45).?);
    try std.testing.expectEqual(Level.critical, Level.fromPriority(50).?);
    try std.testing.expectEqual(Level.fatal, Level.fromPriority(55).?);
    try std.testing.expectEqual(@as(?Level, null), Level.fromPriority(99));
}

test "level string conversion" {
    try std.testing.expectEqualStrings("TRACE", Level.trace.asString());
    try std.testing.expectEqualStrings("DEBUG", Level.debug.asString());
    try std.testing.expectEqualStrings("INFO", Level.info.asString());
    try std.testing.expectEqualStrings("NOTICE", Level.notice.asString());
    try std.testing.expectEqualStrings("SUCCESS", Level.success.asString());
    try std.testing.expectEqualStrings("WARNING", Level.warning.asString());
    try std.testing.expectEqualStrings("ERROR", Level.err.asString());
    try std.testing.expectEqualStrings("FAIL", Level.fail.asString());
    try std.testing.expectEqualStrings("CRITICAL", Level.critical.asString());
    try std.testing.expectEqualStrings("FATAL", Level.fatal.asString());
}

test "level from string" {
    try std.testing.expectEqual(Level.trace, Level.fromString("TRACE").?);
    try std.testing.expectEqual(Level.debug, Level.fromString("DEBUG").?);
    try std.testing.expectEqual(Level.info, Level.fromString("INFO").?);
    try std.testing.expectEqual(Level.notice, Level.fromString("NOTICE").?);
    try std.testing.expectEqual(Level.success, Level.fromString("SUCCESS").?);
    try std.testing.expectEqual(Level.warning, Level.fromString("WARNING").?);
    try std.testing.expectEqual(Level.err, Level.fromString("ERROR").?);
    try std.testing.expectEqual(Level.fail, Level.fromString("FAIL").?);
    try std.testing.expectEqual(Level.critical, Level.fromString("CRITICAL").?);
    try std.testing.expectEqual(Level.fatal, Level.fromString("FATAL").?);
    try std.testing.expectEqual(@as(?Level, null), Level.fromString("INVALID"));
}

test "level colors" {
    try std.testing.expectEqualStrings("36", Level.trace.defaultColor());
    try std.testing.expectEqualStrings("34", Level.debug.defaultColor());
    try std.testing.expectEqualStrings("37", Level.info.defaultColor());
    try std.testing.expectEqualStrings("96", Level.notice.defaultColor());
    try std.testing.expectEqualStrings("32", Level.success.defaultColor());
    try std.testing.expectEqualStrings("33", Level.warning.defaultColor());
    try std.testing.expectEqualStrings("31", Level.err.defaultColor());
    try std.testing.expectEqualStrings("35", Level.fail.defaultColor());
    try std.testing.expectEqualStrings("91", Level.critical.defaultColor());
    try std.testing.expectEqualStrings("97;41", Level.fatal.defaultColor());
}

test "level ordering" {
    // Verify severity ordering: trace < debug < info < notice < success < warning < err < fail < critical < fatal
    try std.testing.expect(Level.trace.priority() < Level.debug.priority());
    try std.testing.expect(Level.debug.priority() < Level.info.priority());
    try std.testing.expect(Level.info.priority() < Level.notice.priority());
    try std.testing.expect(Level.notice.priority() < Level.success.priority());
    try std.testing.expect(Level.success.priority() < Level.warning.priority());
    try std.testing.expect(Level.warning.priority() < Level.err.priority());
    try std.testing.expect(Level.err.priority() < Level.fail.priority());
    try std.testing.expect(Level.fail.priority() < Level.critical.priority());
    try std.testing.expect(Level.critical.priority() < Level.fatal.priority());
}
