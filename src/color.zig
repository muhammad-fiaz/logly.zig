//! Logly's color entry point. Re-exports the tint.zig primitives and maps
//! log levels onto colors. Use `tint` directly for anything not covered here;
//! do not add a second ANSI implementation elsewhere in Logly.
//!
//! Every value here is a plain copyable type with no allocator and no shared
//! state, so it is usable from any thread. Rendering honors the
//! caller-supplied `Capability`; terminal detection lives in `logly.Terminal`.

const std = @import("std");
const tint = @import("tint");
const Level = @import("level.zig").Level;

/// Terminal color primitives from tint.zig.
pub const Tint = tint;
/// A single color (ANSI4, ANSI256, RGB, named, etc.).
pub const Color = tint.color.Color;
/// A composable foreground/background/attribute set.
pub const Style = tint.style.Style;
/// A named palette of semantic roles.
pub const Theme = tint.theme.Theme;
/// How much color the target terminal understands.
pub const Capability = tint.ansi.Capability;
/// A rendered escape sequence, owned inline by value.
pub const Sequence = tint.ansi.Sequence;

/// Capability assumed when a caller does not state one. True color is
/// lossless; `Sequence` values degrade explicitly via `tint.ansi.render`.
pub const defaultCapability: Capability = .trueColor;

/// Full SGR reset (`ESC[0m`).
pub const resetAll: []const u8 = tint.ansi.reset.all;

/// Default foreground color for a log level.
///
/// | Level    | Color      |
/// |----------|------------|
/// | TRACE    | cyan       |
/// | DEBUG    | blue       |
/// | INFO     | white      |
/// | NOTICE   | brightCyan |
/// | SUCCESS  | green      |
/// | WARNING  | yellow     |
/// | ERROR    | red        |
/// | FAIL     | magenta    |
/// | CRITICAL | brightRed  |
/// | FATAL    | brightWhite (white-on-red via `levelStyle`) |
pub fn levelColor(level: Level) Color {
    return switch (level) {
        .trace => tint.color.ansi4.cyan,
        .debug => tint.color.ansi4.blue,
        .info => tint.color.ansi4.white,
        .notice => tint.color.ansi4.brightCyan,
        .success => tint.color.ansi4.green,
        .warning => tint.color.ansi4.yellow,
        .err => tint.color.ansi4.red,
        .fail => tint.color.ansi4.magenta,
        .critical => tint.color.ansi4.brightRed,
        .fatal => tint.color.ansi4.brightWhite,
    };
}

/// Default style for a level: its foreground color, plus a red background for
/// `.fatal` to keep the historical white-on-red rendering.
pub fn levelStyle(level: Level) Style {
    const fg = levelColor(level);
    return switch (level) {
        .fatal => .{ .foreground = fg, .background = tint.color.ansi4.red },
        else => .{ .foreground = fg },
    };
}

/// Renders `color` as a foreground sequence for `capability`.
pub fn sequence(color: Color, capability: Capability) Sequence {
    return tint.ansi.render(color, .foreground, capability);
}

/// Renders `style` as a single SGR sequence.
///
/// `Style.toAnsi` always emits full true-color parameters; callers that
/// must target a lesser capability should downgrade the constituent
/// colors first via `Color.downgrade`.
pub fn styleSequence(style: Style) Sequence {
    return style.toAnsi();
}

/// Parses a user-supplied color: a tint color name (`"red"`, `"brightCyan"`),
/// `#rrggbb` hex, or raw SGR parameters (`"31"`, `"38;5;196"`) accepted for
/// compatibility with older Logly configuration. Returns `null` when the text
/// does not name a color.
pub fn parse(text: []const u8) ?Color {
    if (tint.color.parse(text)) |c| return c;
    if (parseSgrParams(text)) |c| return c;
    return null;
}

/// Extracts the foreground color from raw SGR parameters (`"31"`,
/// `"38;5;196"`, `"38;2;r;g;b"`). Text attributes and background selectors
/// are skipped, since `Color` cannot represent them.
fn parseSgrParams(text: []const u8) ?Color {
    if (text.len == 0) return null;
    var fields: [8][]const u8 = undefined;
    var count: usize = 0;
    var it = std.mem.splitScalar(u8, text, ';');
    while (it.next()) |part| {
        if (count >= fields.len) return null;
        fields[count] = part;
        count += 1;
    }
    if (count == 0) return null;

    var i: usize = 0;
    // Skip leading text attributes; keep the first color selector.
    while (i < count) : (i += 1) {
        const code = std.fmt.parseInt(u8, fields[i], 10) catch return null;
        switch (code) {
            30...37 => return ansi4FromCode(code - 30),
            39 => return tint.color.ansi4.default,
            90...97 => return ansi4BrightFromCode(code - 90),
            38 => {
                if (i + 2 < count and std.mem.eql(u8, fields[i + 1], "5")) {
                    const index = std.fmt.parseInt(u8, fields[i + 2], 10) catch return null;
                    return tint.color.ansi256.index(index);
                }
                if (i + 4 < count and std.mem.eql(u8, fields[i + 1], "2")) {
                    const r = std.fmt.parseInt(u8, fields[i + 2], 10) catch return null;
                    const g = std.fmt.parseInt(u8, fields[i + 3], 10) catch return null;
                    const b = std.fmt.parseInt(u8, fields[i + 4], 10) catch return null;
                    return tint.color.rgb(r, g, b);
                }
                return null;
            },
            // Text attributes and background selectors carry no foreground.
            else => continue,
        }
    }
    return null;
}

fn ansi4FromCode(code: u8) Color {
    return switch (code) {
        0 => tint.color.ansi4.black,
        1 => tint.color.ansi4.red,
        2 => tint.color.ansi4.green,
        3 => tint.color.ansi4.yellow,
        4 => tint.color.ansi4.blue,
        5 => tint.color.ansi4.magenta,
        6 => tint.color.ansi4.cyan,
        else => tint.color.ansi4.white,
    };
}

fn ansi4BrightFromCode(code: u8) Color {
    return switch (code) {
        0 => tint.color.ansi4.brightBlack,
        1 => tint.color.ansi4.brightRed,
        2 => tint.color.ansi4.brightGreen,
        3 => tint.color.ansi4.brightYellow,
        4 => tint.color.ansi4.brightBlue,
        5 => tint.color.ansi4.brightMagenta,
        6 => tint.color.ansi4.brightCyan,
        else => tint.color.ansi4.brightWhite,
    };
}

test "level colors render distinct foreground sequences" {
    const traceSeq = sequence(levelColor(.trace), .trueColor);
    const errSeq = sequence(levelColor(.err), .trueColor);
    try std.testing.expect(traceSeq.len > 0);
    try std.testing.expect(errSeq.len > 0);
    try std.testing.expect(!traceSeq.eql(&errSeq));
}

test "fatal style carries a background" {
    const fatal = levelStyle(.fatal);
    try std.testing.expect(fatal.background != null);
    try std.testing.expect(levelStyle(.info).background == null);
}

test "parse accepts names, hex, and SGR params" {
    try std.testing.expect(parse("red") != null);
    try std.testing.expect(parse("#ff0000") != null);
    try std.testing.expect(parse("31") != null);
    try std.testing.expect(parse("38;5;196") != null);
    try std.testing.expect(parse("") == null);
    try std.testing.expect(parse("not-a-color") == null);
}
