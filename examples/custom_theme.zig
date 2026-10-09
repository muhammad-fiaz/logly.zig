const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    _ = logly.Terminal.enableAnsiColors();

    const logger = try logly.Logger.init(allocator);
    defer logger.deinit();

    const ThemePreset = logly.Config.LevelColorConfig.ThemePreset;

    std.debug.print("\nTheme Presets\n\n", .{});
    std.debug.print("Available presets (Config.ThemePreset):\n", .{});
    std.debug.print("  .bright  - Bold/bright colors\n", .{});
    std.debug.print("  .dim     - Dim colors\n", .{});
    std.debug.print("  .minimal - Subtle grays\n", .{});
    std.debug.print("  .neon    - Vivid 256-colors\n", .{});
    std.debug.print("  .pastel  - Soft colors\n", .{});
    std.debug.print("  .dark    - Dark terminal\n", .{});
    std.debug.print("  .light   - Light terminal\n\n", .{});

    // A preset is selected on the level-color config and applies to every sink
    // that resolves color.
    logger.config.levelColors.themePreset = ThemePreset.neon;

    std.debug.print("Neon Theme\n\n", .{});
    try logger.trace("Trace - neon cyan", @src());
    try logger.debug("Debug - neon blue", @src());
    try logger.info("Info - light gray", @src());
    try logger.success("Success - neon green", @src());
    try logger.warning("Warning - neon yellow", @src());
    try logger.err("Error - neon red", @src());
    try logger.critical("Critical - bold red", @src());

    // Switching presets takes effect on the next record.
    logger.config.levelColors.themePreset = ThemePreset.pastel;

    std.debug.print("\nPastel Theme\n\n", .{});
    try logger.trace("Trace - soft cyan", @src());
    try logger.debug("Debug - soft blue", @src());
    try logger.info("Info - light", @src());
    try logger.success("Success - soft green", @src());
    try logger.warning("Warning - soft yellow", @src());
    try logger.err("Error - soft red", @src());

    logger.config.levelColors.themePreset = ThemePreset.dark;

    std.debug.print("\nDark Theme\n\n", .{});
    try logger.info("Info in dark theme", @src());
    try logger.warning("Warning in dark theme", @src());
    try logger.err("Error in dark theme", @src());

    // Custom per-level colors. Each level accepts any tint color: an ANSI
    // name, a #rrggbb hex value, or raw SGR parameters. Overrides win over the
    // selected preset.
    std.debug.print("\nCustom Level Colors\n\n", .{});
    logger.config.levelColors.traceColor = logly.Color.parse("90").?;
    logger.config.levelColors.debugColor = logly.Color.parse("35").?;
    logger.config.levelColors.infoColor = logly.Color.parse("36").?;
    logger.config.levelColors.noticeColor = logly.Color.parse("96").?;
    logger.config.levelColors.successColor = logly.Color.parse("92").?;
    logger.config.levelColors.warningColor = logly.Color.parse("93").?;
    logger.config.levelColors.errorColor = logly.Color.parse("91").?;
    logger.config.levelColors.failColor = logly.Color.parse("31").?;
    logger.config.levelColors.criticalColor = logly.Color.parse("red").?;
    logger.config.levelColors.fatalColor = logly.Color.Tint.color.ansi4.brightRed;

    try logger.trace("Trace (Gray)", @src());
    try logger.debug("Debug (Magenta)", @src());
    try logger.info("Info (Cyan)", @src());
    try logger.success("Success (Bright Green)", @src());
    try logger.warning("Warning (Bright Yellow)", @src());
    try logger.err("Error (Bright Red)", @src());
    try logger.fail("Fail (Red)", @src());
    try logger.critical("Critical (Red)", @src());

    // Rendered sequences for a preset, without emitting a record.
    std.debug.print("\nTheme Colors Reference\n\n", .{});
    var neon = logly.Config.LevelColorConfig{ .themePreset = ThemePreset.neon };
    inline for ([_]logly.Level{ .trace, .debug, .info, .success, .warning, .err, .critical, .fatal }) |lvl| {
        const seq = logly.Color.sequence(neon.getColorForLevel(lvl), .trueColor);
        std.debug.print("  {s: <10}{s}sample{s}\n", .{ @tagName(lvl), seq.slice(), logly.Color.resetAll });
    }

    // Custom output templates.
    std.debug.print("\nCustom Format Example\n\n", .{});

    var config = logly.Config.default();
    config.logFormat = ">>> {time} | {level} | {message} <<<";
    logger.configure(config);

    try logger.info("This uses a custom format", @src());

    config.logFormat = "[{level}] {message} ({file}:{line})";
    logger.configure(config);

    try logger.warning("Minimal format with location", @src());
}
