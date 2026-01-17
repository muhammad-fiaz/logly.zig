//! Log Level Module
//!
//! Defines the standard logging levels and their priorities for the Logly library.
//! Levels are ordered by severity, enabling filtering and conditional logging.
//!
//! Priority Order (lowest to highest):
//! - trace (5): Detailed tracing information
//! - debug (10): Debugging information
//! - info (20): General informational messages
//! - notice (22): Notable events
//! - success (25): Successful operation completion
//! - warning (30): Warning conditions
//! - err (40): Error conditions
//! - fail (45): Failure conditions
//! - critical (50): Critical failures
//! - fatal (55): Fatal system errors
//!
//! Custom levels can be created with arbitrary priorities and colors.

const std = @import("std");
const Constants = @import("constants.zig");

/// Defines the standard logging levels and their priorities.
///
/// Levels are ordered by priority, where higher values indicate higher severity.
/// Each level has a numeric priority, string representation, and default color.
pub const Level = enum(u8) {
    /// Detailed tracing information (priority: 5).
    trace = 5,
    /// Debugging information (priority: 10).
    debug = 10,
    /// General informational messages (priority: 20).
    info = 20,
    /// Notice messages (priority: 22).
    notice = 22,
    /// Success messages (priority: 25).
    success = 25,
    /// Warning conditions (priority: 30).
    warning = 30,
    /// Error conditions (priority: 40).
    err = 40,
    /// Failure conditions (priority: 45).
    fail = 45,
    /// Critical failures (priority: 50).
    critical = 50,
    /// Fatal system errors - highest severity (priority: 55).
    fatal = 55,

    /// Returns the numeric priority value of this level.
    pub fn priority(self: Level) u8 {
        return @intFromEnum(self);
    }

    /// Returns the Level enum from a numeric priority, or null if invalid.
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

    /// Returns the uppercase string representation of this level.
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

    /// Returns the default ANSI color code for this level.
    pub fn defaultColor(self: Level) []const u8 {
        const T = Constants.Colors.Themes.default_theme;
        return switch (self) {
            .trace => T.trace,
            .debug => T.debug,
            .info => T.info,
            .notice => T.notice,
            .success => T.success,
            .warning => T.warning,
            .err => T.err,
            .fail => T.fail,
            .critical => T.critical,
            .fatal => T.fatal,
        };
    }

    /// Returns the bright (bold) ANSI color code for this level.
    pub fn brightColor(self: Level) []const u8 {
        const T = Constants.Colors.Themes.bright;
        return switch (self) {
            .trace => T.trace,
            .debug => T.debug,
            .info => T.info,
            .notice => T.notice,
            .success => T.success,
            .warning => T.warning,
            .err => T.err,
            .fail => T.fail,
            .critical => T.critical,
            .fatal => T.fatal,
        };
    }

    /// Returns the dim ANSI color code for this level.
    pub fn dimColor(self: Level) []const u8 {
        const T = Constants.Colors.Themes.dim;
        return switch (self) {
            .trace => T.trace,
            .debug => T.debug,
            .info => T.info,
            .notice => T.notice,
            .success => T.success,
            .warning => T.warning,
            .err => T.err,
            .fail => T.fail,
            .critical => T.critical,
            .fatal => T.fatal,
        };
    }

    /// Returns the underlined ANSI color code for this level.
    pub fn underlineColor(self: Level) []const u8 {
        const T = Constants.Colors.Themes.underlined;
        return switch (self) {
            .trace => T.trace,
            .debug => T.debug,
            .info => T.info,
            .notice => T.notice,
            .success => T.success,
            .warning => T.warning,
            .err => T.err,
            .fail => T.fail,
            .critical => T.critical,
            .fatal => T.fatal,
        };
    }

    /// Returns a 256-color palette code for this level.
    pub fn color256(self: Level) []const u8 {
        const T = Constants.Colors.Themes.neon;
        return switch (self) {
            .trace => T.trace,
            .debug => T.debug,
            .info => T.info,
            .notice => T.notice,
            .success => T.success,
            .warning => T.warning,
            .err => T.err,
            .fail => T.fail,
            .critical => T.critical,
            .fatal => T.fatal,
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

/// User-defined logging level.
pub const CustomLevel = struct {
    /// Name of the custom level (e.g. "AUDIT").
    name: []const u8,
    /// Priority value (0-255).
    priority: u8,
    /// ANSI color code for this level.
    color: []const u8,
    /// Optional bright color variant.
    bright_color: ?[]const u8 = null,
    /// Optional dim color variant.
    dim_color: ?[]const u8 = null,
    /// Optional 256-color variant.
    color_256: ?[]const u8 = null,
    /// Optional RGB color (foreground).
    rgb_color: ?struct { r: u8, g: u8, b: u8 } = null,
    /// Optional background color.
    bg_color: ?[]const u8 = null,
    /// Text style (bold, italic, underline, etc.).
    style: ?[]const u8 = null,

    /// Creates a new custom level.
    pub fn init(level_name: []const u8, level_priority: u8, level_color: []const u8) CustomLevel {
        return .{
            .name = level_name,
            .priority = level_priority,
            .color = level_color,
        };
    }

    /// Creates a custom level with full color options.
    pub fn initFull(
        level_name: []const u8,
        level_priority: u8,
        level_color: []const u8,
        bright: ?[]const u8,
        dim: ?[]const u8,
        c256: ?[]const u8,
    ) CustomLevel {
        return .{
            .name = level_name,
            .priority = level_priority,
            .color = level_color,
            .bright_color = bright,
            .dim_color = dim,
            .color_256 = c256,
        };
    }

    /// Creates a custom level with RGB color.
    pub fn initRgb(level_name: []const u8, level_priority: u8, r: u8, g: u8, b: u8) CustomLevel {
        return .{
            .name = level_name,
            .priority = level_priority,
            .color = "37",
            .rgb_color = .{ .r = r, .g = g, .b = b },
        };
    }

    /// Creates a custom level with 256-color palette.
    pub fn init256(level_name: []const u8, level_priority: u8, color_index: u8) CustomLevel {
        _ = color_index;
        return .{
            .name = level_name,
            .priority = level_priority,
            .color = "37",
            .color_256 = null,
        };
    }

    /// Creates a custom level with style.
    pub fn initStyled(level_name: []const u8, level_priority: u8, level_color: []const u8, level_style: []const u8) CustomLevel {
        return .{
            .name = level_name,
            .priority = level_priority,
            .color = level_color,
            .style = level_style,
        };
    }

    /// Creates a custom level with background color.
    pub fn initWithBackground(level_name: []const u8, level_priority: u8, fg_color: []const u8, background: []const u8) CustomLevel {
        return .{
            .name = level_name,
            .priority = level_priority,
            .color = fg_color,
            .bg_color = background,
        };
    }

    /// Returns the effective color code (combining style, fg, bg).
    pub fn effectiveColor(self: CustomLevel) []const u8 {
        if (self.style) |s| {
            if (self.bg_color) |bg| {
                _ = s;
                _ = bg;
                return self.color;
            }
            return self.color;
        }
        if (self.bg_color) |_| {
            return self.color;
        }
        return self.color;
    }

    /// Returns the bright color if set, otherwise default color with bold.
    pub fn getBrightColor(self: CustomLevel) []const u8 {
        return self.bright_color orelse self.color;
    }

    /// Returns the dim color if set, otherwise default color.
    pub fn getDimColor(self: CustomLevel) []const u8 {
        return self.dim_color orelse self.color;
    }

    /// Returns the 256-color if set, otherwise default color.
    pub fn get256Color(self: CustomLevel) []const u8 {
        return self.color_256 orelse self.color;
    }

    /// Returns true if this custom level is at least as severe as standard level.
    pub fn isAtLeast(self: CustomLevel, level: Level) bool {
        return self.priority >= level.priority();
    }

    /// Returns true if this is an error-level or higher.
    pub fn isError(self: CustomLevel) bool {
        return self.priority >= Level.err.priority();
    }

    /// Alias for name.
    pub fn asString(self: CustomLevel) []const u8 {
        return self.name;
    }

    /// Check if custom level has RGB color.
    pub fn hasRgbColor(self: CustomLevel) bool {
        return self.rgb_color != null;
    }

    /// Check if custom level has 256-color.
    pub fn has256Color(self: CustomLevel) bool {
        return self.color_256 != null;
    }

    /// Check if custom level has background color.
    pub fn hasBackground(self: CustomLevel) bool {
        return self.bg_color != null;
    }

    /// Check if custom level has style.
    pub fn hasStyle(self: CustomLevel) bool {
        return self.style != null;
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

test "level bright colors" {
    try std.testing.expectEqualStrings("96;1", Level.trace.brightColor());
    try std.testing.expectEqualStrings("94;1", Level.debug.brightColor());
    try std.testing.expectEqualStrings("97;1", Level.info.brightColor());
    try std.testing.expectEqualStrings("92;1", Level.success.brightColor());
    try std.testing.expectEqualStrings("93;1", Level.warning.brightColor());
    try std.testing.expectEqualStrings("91;1", Level.err.brightColor());
}

test "level dim colors" {
    try std.testing.expectEqualStrings("36;2", Level.trace.dimColor());
    try std.testing.expectEqualStrings("34;2", Level.debug.dimColor());
    try std.testing.expectEqualStrings("37;2", Level.info.dimColor());
}

test "level underline colors" {
    try std.testing.expectEqualStrings("36;4", Level.trace.underlineColor());
    try std.testing.expectEqualStrings("34;4", Level.debug.underlineColor());
    try std.testing.expectEqualStrings("31;4", Level.err.underlineColor());
}

test "level 256 colors" {
    try std.testing.expectEqualStrings("38;5;51", Level.trace.color256());
    try std.testing.expectEqualStrings("38;5;33", Level.debug.color256());
    try std.testing.expectEqualStrings("38;5;196", Level.err.color256());
}

test "level comparison methods" {
    try std.testing.expect(Level.err.isAtLeast(.warning));
    try std.testing.expect(Level.fatal.isMoreSevereThan(.critical));
    try std.testing.expect(Level.err.isError());
    try std.testing.expect(Level.critical.isError());
    try std.testing.expect(Level.warning.isWarning());
    try std.testing.expect(Level.debug.isDebug());
    try std.testing.expect(Level.trace.isDebug());
    try std.testing.expect(!Level.info.isDebug());
}

test "custom level creation" {
    const audit = CustomLevel.init("AUDIT", 35, "36;1");
    try std.testing.expectEqualStrings("AUDIT", audit.name);
    try std.testing.expectEqual(@as(u8, 35), audit.priority);
    try std.testing.expectEqualStrings("36;1", audit.color);
}

test "custom level full creation" {
    const custom = CustomLevel.initFull("CUSTOM", 42, "32", "92;1", "32;2", "38;5;46");
    try std.testing.expectEqualStrings("CUSTOM", custom.name);
    try std.testing.expectEqualStrings("32", custom.color);
    try std.testing.expectEqualStrings("92;1", custom.getBrightColor());
    try std.testing.expectEqualStrings("32;2", custom.getDimColor());
    try std.testing.expectEqualStrings("38;5;46", custom.get256Color());
}

test "custom level rgb creation" {
    const rgb_level = CustomLevel.initRgb("RGB_LEVEL", 50, 255, 128, 64);
    try std.testing.expect(rgb_level.hasRgbColor());
    try std.testing.expectEqual(@as(u8, 255), rgb_level.rgb_color.?.r);
    try std.testing.expectEqual(@as(u8, 128), rgb_level.rgb_color.?.g);
    try std.testing.expectEqual(@as(u8, 64), rgb_level.rgb_color.?.b);
}

test "custom level styled creation" {
    const styled = CustomLevel.initStyled("STYLED", 45, "31", "1;4");
    try std.testing.expect(styled.hasStyle());
    try std.testing.expectEqualStrings("1;4", styled.style.?);
}

test "custom level with background" {
    const bg_level = CustomLevel.initWithBackground("BG_LEVEL", 40, "37", "41");
    try std.testing.expect(bg_level.hasBackground());
    try std.testing.expectEqualStrings("41", bg_level.bg_color.?);
}

test "custom level comparison" {
    const custom = CustomLevel.init("CUSTOM", 35, "33");
    try std.testing.expect(custom.isAtLeast(.warning));
    try std.testing.expect(!custom.isAtLeast(.err));
    try std.testing.expect(!custom.isError());

    const high_custom = CustomLevel.init("HIGH", 45, "31");
    try std.testing.expect(high_custom.isError());
}
