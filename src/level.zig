//! Log levels.
//!
//! Severity-ordered levels from trace to fatal, plus user-defined custom levels.
const std = @import("std");
const Constants = @import("constants.zig");
const Color = @import("color.zig");
const TintColor = Color.Color;
const TintStyle = Color.Style;

/// Defines the standard logging levels and their priorities.
///
/// Levels are ordered by priority, where higher values indicate higher severity.
/// Each level has a numeric priority, string representation, and default color.
pub const Level = enum(u8) {
    /// Detailed tracing information (priority: 5).
    trace = Constants.LevelConstants.Priorities.trace,
    /// Debugging information (priority: 10).
    debug = Constants.LevelConstants.Priorities.debug,
    /// General informational messages (priority: 20).
    info = Constants.LevelConstants.Priorities.info,
    /// Notice messages (priority: 22).
    notice = Constants.LevelConstants.Priorities.notice,
    /// Success messages (priority: 25).
    success = Constants.LevelConstants.Priorities.success,
    /// Warning conditions (priority: 30).
    warning = Constants.LevelConstants.Priorities.warning,
    /// Error conditions (priority: 40).
    err = Constants.LevelConstants.Priorities.err,
    /// Failure conditions (priority: 45).
    fail = Constants.LevelConstants.Priorities.fail,
    /// Critical failures (priority: 50).
    critical = Constants.LevelConstants.Priorities.critical,
    /// Fatal system errors - highest severity (priority: 55).
    fatal = Constants.LevelConstants.Priorities.fatal,

    /// Returns the numeric priority value of this level.
    pub fn priority(self: Level) u8 {
        return @backingInt(self);
    }

    /// Returns the Level enum from a numeric priority, or null if invalid.
    pub fn fromPriority(p: u8) ?Level {
        const P = Constants.LevelConstants.Priorities;
        return switch (p) {
            P.trace => .trace,
            P.debug => .debug,
            P.info => .info,
            P.notice => .notice,
            P.success => .success,
            P.warning => .warning,
            P.err => .err,
            P.fail => .fail,
            P.critical => .critical,
            P.fatal => .fatal,
            else => null,
        };
    }

    /// Returns the uppercase string representation of this level.
    pub fn asString(self: Level) []const u8 {
        const N = Constants.MetricsConstants.levelNames;
        return switch (self) {
            .trace => N[0],
            .debug => N[1],
            .info => N[2],
            .notice => N[3],
            .success => N[4],
            .warning => N[5],
            .err => N[6],
            .fail => N[7],
            .critical => N[8],
            .fatal => N[9],
        };
    }

    /// Returns the default foreground color for this level.
    ///
    /// The returned tint `Color` is a plain value: copying it copies the
    /// data, no allocation or synchronization is involved. Render it with
    /// `color.sequence()` (or `tint.ansi.render` for an explicit
    /// capability) and write `Sequence.slice()` to the sink.
    pub fn defaultColor(self: Level) TintColor {
        return Color.levelColor(self);
    }

    /// Returns the full default style for this level.
    ///
    /// Equivalent to `defaultColor` except `.fatal`, which also carries a
    /// red background (preserving the historical white-on-red rendering).
    /// Pure data; safe to copy and share across threads.
    pub fn defaultStyle(self: Level) TintStyle {
        return Color.levelStyle(self);
    }

    pub fn fromString(s: []const u8) ?Level {
        if (std.ascii.eqlIgnoreCase(s, "trace")) return .trace;
        if (std.ascii.eqlIgnoreCase(s, "debug")) return .debug;
        if (std.ascii.eqlIgnoreCase(s, "info")) return .info;
        if (std.ascii.eqlIgnoreCase(s, "notice")) return .notice;
        if (std.ascii.eqlIgnoreCase(s, "success")) return .success;
        if (std.ascii.eqlIgnoreCase(s, "warning") or std.ascii.eqlIgnoreCase(s, "warn")) return .warning;
        if (std.ascii.eqlIgnoreCase(s, "error") or std.ascii.eqlIgnoreCase(s, "err")) return .err;
        if (std.ascii.eqlIgnoreCase(s, "fail")) return .fail;
        if (std.ascii.eqlIgnoreCase(s, "critical") or std.ascii.eqlIgnoreCase(s, "crit")) return .critical;
        if (std.ascii.eqlIgnoreCase(s, "fatal")) return .fatal;
        return null;
    }

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

/// A mask for enabling/disabling specific logging levels independently.
/// Allows fine-grained control over which levels are logged, ignoring the standard priority hierarchy.
pub const LevelMask = struct {
    /// 16-bit mask storing the enabled state of standard levels.
    mask: u16 = 0,

    /// Returns the bit index for a given standard level.
    fn bitIndex(lvl: Level) u4 {
        return switch (lvl) {
            .trace => 0,
            .debug => 1,
            .info => 2,
            .notice => 3,
            .success => 4,
            .warning => 5,
            .err => 6,
            .fail => 7,
            .critical => 8,
            .fatal => 9,
        };
    }

    /// Creates an empty mask (no levels enabled).
    pub fn init() LevelMask {
        return .{};
    }

    /// Creates a mask with all standard levels enabled.
    pub fn all() LevelMask {
        return .{ .mask = 0x03FF }; // First 10 bits
    }

    /// Creates a mask with only error/fatal levels enabled.
    pub fn errorsOnly() LevelMask {
        var m = LevelMask.init();
        m.enable(.err);
        m.enable(.fail);
        m.enable(.critical);
        m.enable(.fatal);
        return m;
    }

    /// Enables a specific level in the mask.
    pub fn enable(self: *LevelMask, lvl: Level) void {
        self.mask |= (@as(u16, 1) << LevelMask.bitIndex(lvl));
    }

    /// Disables a specific level in the mask.
    pub fn disable(self: *LevelMask, lvl: Level) void {
        self.mask &= ~(@as(u16, 1) << LevelMask.bitIndex(lvl));
    }

    /// Toggles a specific level in the mask.
    pub fn toggle(self: *LevelMask, lvl: Level) void {
        self.mask ^= (@as(u16, 1) << LevelMask.bitIndex(lvl));
    }

    /// Returns true if the given level is enabled in this mask.
    pub fn isEnabled(self: LevelMask, lvl: Level) bool {
        return (self.mask & (@as(u16, 1) << LevelMask.bitIndex(lvl))) != 0;
    }
};

/// User-defined logging level.
///
/// Colors are tint `Color` values (plain data, no allocation). Use
/// `Color.parse` to convert user-supplied text (names, `#rrggbb`, or
/// historical SGR params) into a `Color`.
pub const CustomLevel = struct {
    /// Name of the custom level (e.g. "AUDIT").
    name: []const u8,
    /// Priority value (0-255).
    priority: u8,
    /// Foreground color for this level.
    color: TintColor,
    /// Optional background color.
    bgColor: ?TintColor = null,
    /// Optional full style override (attributes and background).
    /// When set, it takes precedence over `color`/`bgColor` at render time.
    style: ?TintStyle = null,

    /// Creates a new custom level.
    pub fn init(levelName: []const u8, levelPriority: u8, levelColor: TintColor) CustomLevel {
        return .{
            .name = levelName,
            .priority = levelPriority,
            .color = levelColor,
        };
    }

    /// Creates a custom level with RGB color.
    pub fn initRgb(levelName: []const u8, levelPriority: u8, r: u8, g: u8, b: u8) CustomLevel {
        return .{
            .name = levelName,
            .priority = levelPriority,
            .color = Color.Tint.color.rgb(r, g, b),
        };
    }

    /// Creates a custom level with 256-color palette.
    pub fn init256(levelName: []const u8, levelPriority: u8, colorIndex: u8) CustomLevel {
        return .{
            .name = levelName,
            .priority = levelPriority,
            .color = Color.Tint.color.ansi256.index(colorIndex),
        };
    }

    /// Creates a custom level with an explicit style.
    pub fn initStyled(levelName: []const u8, levelPriority: u8, levelStyle: TintStyle) CustomLevel {
        return .{
            .name = levelName,
            .priority = levelPriority,
            .color = levelStyle.foreground orelse Color.Tint.color.ansi4.white,
            .bgColor = levelStyle.background,
            .style = levelStyle,
        };
    }

    /// Creates a custom level with background color.
    pub fn initWithBackground(levelName: []const u8, levelPriority: u8, fgColor: TintColor, background: TintColor) CustomLevel {
        return .{
            .name = levelName,
            .priority = levelPriority,
            .color = fgColor,
            .bgColor = background,
        };
    }

    /// Returns the effective style (explicit style, else fg plus background).
    ///
    /// Pure data; safe to copy and share across threads.
    pub fn effectiveStyle(self: CustomLevel) TintStyle {
        if (self.style) |s| return s;
        return .{ .foreground = self.color, .background = self.bgColor };
    }

    /// Returns the effective foreground color.
    pub fn effectiveColor(self: CustomLevel) TintColor {
        return self.color;
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

    /// Check if custom level has background color.
    pub fn hasBackground(self: CustomLevel) bool {
        return self.bgColor != null;
    }

    /// Check if custom level has style.
    pub fn hasStyle(self: CustomLevel) bool {
        return self.style != null;
    }
};

test "level priority" {
    const P = Constants.LevelConstants.Priorities;
    try std.testing.expectEqual(P.trace, Level.trace.priority());
    try std.testing.expectEqual(P.debug, Level.debug.priority());
    try std.testing.expectEqual(P.info, Level.info.priority());
    try std.testing.expectEqual(P.notice, Level.notice.priority());
    try std.testing.expectEqual(P.success, Level.success.priority());
    try std.testing.expectEqual(P.warning, Level.warning.priority());
    try std.testing.expectEqual(P.err, Level.err.priority());
    try std.testing.expectEqual(P.fail, Level.fail.priority());
    try std.testing.expectEqual(P.critical, Level.critical.priority());
    try std.testing.expectEqual(P.fatal, Level.fatal.priority());
}

test "level from priority" {
    const P = Constants.LevelConstants.Priorities;
    try std.testing.expectEqual(Level.trace, Level.fromPriority(P.trace).?);
    try std.testing.expectEqual(Level.debug, Level.fromPriority(P.debug).?);
    try std.testing.expectEqual(Level.info, Level.fromPriority(P.info).?);
    try std.testing.expectEqual(Level.notice, Level.fromPriority(P.notice).?);
    try std.testing.expectEqual(Level.success, Level.fromPriority(P.success).?);
    try std.testing.expectEqual(Level.warning, Level.fromPriority(P.warning).?);
    try std.testing.expectEqual(Level.err, Level.fromPriority(P.err).?);
    try std.testing.expectEqual(Level.fail, Level.fromPriority(P.fail).?);
    try std.testing.expectEqual(Level.critical, Level.fromPriority(P.critical).?);
    try std.testing.expectEqual(Level.fatal, Level.fromPriority(P.fatal).?);
    try std.testing.expectEqual(@as(?Level, null), Level.fromPriority(99));
}

test "level string conversion" {
    const N = Constants.MetricsConstants.levelNames;
    try std.testing.expectEqualStrings(N[0], Level.trace.asString());
    try std.testing.expectEqualStrings(N[1], Level.debug.asString());
    try std.testing.expectEqualStrings(N[2], Level.info.asString());
    try std.testing.expectEqualStrings(N[3], Level.notice.asString());
    try std.testing.expectEqualStrings(N[4], Level.success.asString());
    try std.testing.expectEqualStrings(N[5], Level.warning.asString());
    try std.testing.expectEqualStrings(N[6], Level.err.asString());
    try std.testing.expectEqualStrings(N[7], Level.fail.asString());
    try std.testing.expectEqualStrings(N[8], Level.critical.asString());
    try std.testing.expectEqualStrings(N[9], Level.fatal.asString());
}

test "level from string" {
    const N = Constants.MetricsConstants.levelNames;
    try std.testing.expectEqual(Level.trace, Level.fromString(N[0]).?);
    try std.testing.expectEqual(Level.debug, Level.fromString(N[1]).?);
    try std.testing.expectEqual(Level.info, Level.fromString(N[2]).?);
    try std.testing.expectEqual(Level.notice, Level.fromString(N[3]).?);
    try std.testing.expectEqual(Level.success, Level.fromString(N[4]).?);
    try std.testing.expectEqual(Level.warning, Level.fromString(N[5]).?);
    try std.testing.expectEqual(Level.err, Level.fromString(N[6]).?);
    try std.testing.expectEqual(Level.fail, Level.fromString(N[7]).?);
    try std.testing.expectEqual(Level.critical, Level.fromString(N[8]).?);
    try std.testing.expectEqual(Level.fatal, Level.fromString(N[9]).?);
    try std.testing.expectEqual(@as(?Level, null), Level.fromString("INVALID"));
}

test "level colors" {
    // Default colors render as distinct foreground sequences.
    const traceSeq = Color.sequence(Level.trace.defaultColor(), .trueColor);
    const errSeq = Color.sequence(Level.err.defaultColor(), .trueColor);
    try std.testing.expect(traceSeq.len > 0);
    try std.testing.expect(errSeq.len > 0);
    try std.testing.expect(!traceSeq.eql(&errSeq));
    // Spot-check exact sequences (true color degrades to ANSI4 for these).
    try std.testing.expectEqualStrings("\x1b[36m", traceSeq.slice());
    try std.testing.expectEqualStrings("\x1b[31m", errSeq.slice());
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

test "level styles" {
    // Fatal carries a background; other levels are foreground-only.
    try std.testing.expect(Level.fatal.defaultStyle().background != null);
    try std.testing.expect(Level.info.defaultStyle().background == null);
    const fatalSeq = Color.styleSequence(Level.fatal.defaultStyle());
    try std.testing.expect(fatalSeq.len > 0);
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
    const audit = CustomLevel.init("AUDIT", 35, Color.Tint.color.cyan);
    try std.testing.expectEqualStrings("AUDIT", audit.name);
    try std.testing.expectEqual(@as(u8, 35), audit.priority);
    try std.testing.expectEqual(Color.Tint.color.cyan, audit.color);
}

test "custom level rgb creation" {
    const rgbLevel = CustomLevel.initRgb("RGB_LEVEL", 50, 255, 128, 64);
    try std.testing.expectEqual(Color.Tint.color.rgb(255, 128, 64), rgbLevel.color);
}

test "custom level styled creation" {
    const styled = CustomLevel.initStyled("STYLED", 45, .{ .foreground = Color.Tint.color.red, .underline = true });
    try std.testing.expect(styled.hasStyle());
    try std.testing.expect(styled.style.?.underline);
}

test "custom level with background" {
    const bgLevel = CustomLevel.initWithBackground("BG_LEVEL", 40, Color.Tint.color.white, Color.Tint.color.red);
    try std.testing.expect(bgLevel.hasBackground());
    try std.testing.expectEqual(Color.Tint.color.red, bgLevel.bgColor.?);
}

test "custom level comparison" {
    const custom = CustomLevel.init("CUSTOM", 35, Color.Tint.color.yellow);
    try std.testing.expect(custom.isAtLeast(.warning));
    try std.testing.expect(!custom.isAtLeast(.err));
    try std.testing.expect(!custom.isError());

    const highCustom = CustomLevel.init("HIGH", 45, Color.Tint.color.red);
    try std.testing.expect(highCustom.isError());
}
