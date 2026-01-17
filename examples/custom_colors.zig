const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Enable ANSI colors on Windows (no-op on Linux/macOS)
    _ = logly.Terminal.enableAnsiColors();

    const logger = try logly.Logger.init(allocator);
    defer logger.deinit();

    std.debug.print("=== Color System Demo (v0.1.5) ===\n\n", .{});

    // Basic custom levels with ANSI codes
    try logger.addCustomLevel("NOTICE", 22, "36;1");
    try logger.addCustomLevel("ALERT", 42, "31;4");
    try logger.addCustomLevel("HIGHLIGHT", 52, "33;1;7");

    // Standard levels with default colors
    try logger.info("Standard Info - white", @src());

    // Demonstrate global color overrides
    std.debug.print("\n=== Global Color Overrides ===\n\n", .{});
    var config = logly.Config.default();
    config.level_colors.info_color = "36"; // Cyan
    config.level_colors.warning_color = "33;1"; // Bold Yellow
    logger.configure(config);

    try logger.info("Info - now Cyan", @src());
    try logger.warning("Warning - now Bold Yellow", @src());

    // Demonstrate theme presets
    std.debug.print("\n=== Theme Presets ===\n\n", .{});
    config.level_colors.theme_preset = .neon;
    logger.configure(config);
    try logger.info("Info - Neon Theme", @src());
    try logger.warning("Warning - Neon Theme", @src());

    try logger.success("Success message - green", @src());
    try logger.warning("Warning message - yellow", @src());
    try logger.err("Error message - red", @src());
    try logger.critical("Critical message - bright red", @src());

    std.debug.print("\n=== Custom Level Colors ===\n\n", .{});

    try logger.custom("NOTICE", "Notice (Cyan Bold)", @src());
    try logger.custom("ALERT", "Alert (Red Underline)", @src());
    try logger.custom("HIGHLIGHT", "Highlight (Yellow Bold Reverse)", @src());

    std.debug.print("\n=== Level Color Variants (v0.1.5) ===\n\n", .{});

    // Demonstrate color variants available on each level
    const Level = logly.Level;
    std.debug.print("TRACE colors:\n", .{});
    std.debug.print("  default:   {s}\n", .{Level.trace.defaultColor()});
    std.debug.print("  bright:    {s}\n", .{Level.trace.brightColor()});
    std.debug.print("  dim:       {s}\n", .{Level.trace.dimColor()});
    std.debug.print("  underline: {s}\n", .{Level.trace.underlineColor()});
    std.debug.print("  256-color: {s}\n\n", .{Level.trace.color256()});

    std.debug.print("\n=== Color Constants ===\n\n", .{});

    // Show color constants
    const Colors = logly.Constants.Colors;
    std.debug.print("Foreground colors (30-37):\n", .{});
    std.debug.print("  red={s} green={s} blue={s} cyan={s}\n", .{
        Colors.Fg.red,
        Colors.Fg.green,
        Colors.Fg.blue,
        Colors.Fg.cyan,
    });

    std.debug.print("\nBright foreground (90-97):\n", .{});
    std.debug.print("  red={s} green={s} blue={s} cyan={s}\n", .{
        Colors.BrightFg.red,
        Colors.BrightFg.green,
        Colors.BrightFg.blue,
        Colors.BrightFg.cyan,
    });

    std.debug.print("\nStyles:\n", .{});
    std.debug.print("  bold={s} dim={s} underline={s} reverse={s}\n", .{
        Colors.Style.bold,
        Colors.Style.dim,
        Colors.Style.underline,
        Colors.Style.reverse,
    });

    std.debug.print("\n=== 256-Color Palette ===\n\n", .{});

    // 256-color codes
    std.debug.print("256-color examples:\n", .{});
    std.debug.print("  orange (208): {s}\n", .{Colors.fg256(208)});
    std.debug.print("  purple (141): {s}\n", .{Colors.fg256(141)});
    std.debug.print("  teal bg (43): {s}\n", .{Colors.bg256(43)});

    std.debug.print("\n=== RGB Colors ===\n\n", .{});

    // RGB color codes
    std.debug.print("RGB color examples:\n", .{});
    std.debug.print("  coral (255,127,80): {s}\n", .{Colors.fgRgb(255, 127, 80)});
    std.debug.print("  lime (50,205,50):   {s}\n", .{Colors.fgRgb(50, 205, 50)});
    std.debug.print("  navy bg (0,0,128):  {s}\n", .{Colors.bgRgb(0, 0, 128)});

    std.debug.print("\n=== Theme Presets ===\n\n", .{});

    // Theme presets
    const Theme = logly.Formatter.Theme;
    std.debug.print("Available theme presets:\n", .{});
    std.debug.print("  Theme.bright()  - Bold/bright colors\n", .{});
    std.debug.print("  Theme.dim()     - Dim colors\n", .{});
    std.debug.print("  Theme.minimal() - Subtle grays\n", .{});
    std.debug.print("  Theme.neon()    - Vivid 256-colors\n", .{});
    std.debug.print("  Theme.pastel()  - Soft colors\n", .{});
    std.debug.print("  Theme.dark()    - Dark terminal\n", .{});
    std.debug.print("  Theme.light()   - Light terminal\n", .{});

    // Show theme colors
    const neon = Theme.neon();
    std.debug.print("\nNeon theme colors:\n", .{});
    std.debug.print("  trace={s} debug={s} info={s}\n", .{ neon.trace, neon.debug, neon.info });
    std.debug.print("  success={s} warning={s} err={s}\n", .{ neon.success, neon.warning, neon.err });

    std.debug.print("\n=== Advanced CustomLevel (v0.1.5) ===\n\n", .{});

    // Demonstrate advanced CustomLevel creation
    const CustomLevel = logly.CustomLevel;

    // Full color options
    const audit = CustomLevel.initFull("AUDIT", 35, "36", "96;1", "36;2", "38;5;81");
    std.debug.print("CustomLevel.initFull - AUDIT:\n", .{});
    std.debug.print("  effective: {s}\n", .{audit.effectiveColor()});
    std.debug.print("  bright:    {s}\n", .{audit.getBrightColor()});
    std.debug.print("  dim:       {s}\n", .{audit.getDimColor()});
    std.debug.print("  256-color: {s}\n", .{audit.get256Color()});

    // RGB custom level
    const metric = CustomLevel.initRgb("METRIC", 25, 50, 205, 50);
    std.debug.print("\nCustomLevel.initRgb - METRIC:\n", .{});
    std.debug.print("  has RGB: {}\n", .{metric.hasRgbColor()});

    // Styled custom level
    const styled = CustomLevel.initStyled("STYLED", 45, "31", "1;4");
    std.debug.print("\nCustomLevel.initStyled - STYLED:\n", .{});
    std.debug.print("  has style: {}\n", .{styled.hasStyle()});

    // With background
    const alert = CustomLevel.initWithBackground("ALERTBG", 50, "97", "41");
    std.debug.print("\nCustomLevel.initWithBackground - ALERTBG:\n", .{});
    std.debug.print("  has background: {}\n", .{alert.hasBackground()});

    std.debug.print("\n=== Platform Support ===\n", .{});
    std.debug.print("Colors work on: Linux, macOS, Windows 10+, VS Code Terminal\n", .{});
    std.debug.print("256-color and RGB require terminal support\n", .{});
    std.debug.print("\nCustom colors example completed!\n", .{});
}
