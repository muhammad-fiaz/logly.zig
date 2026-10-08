const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Enable ANSI colors on Windows (no-op on Linux/macOS)
    _ = logly.Terminal.enableAnsiColors();

    const logger = try logly.Logger.init(allocator);
    defer logger.deinit();

    std.debug.print("Color System Demo (tint.zig)\n\n", .{});

    // Custom levels with tint colors (parsed from names or SGR params).
    try logger.addCustomLevel("NOTICE", 22, logly.Color.parse("cyan").?);
    try logger.addCustomLevel("ALERT", 42, logly.Color.parse("red").?);
    try logger.addCustomLevel("HIGHLIGHT", 52, logly.Color.parse("yellow").?);

    // Standard levels with default colors
    try logger.info("Standard Info - white", @src());
    try logger.flush();

    // Demonstrate global color overrides
    std.debug.print("\nGlobal Color Overrides\n\n", .{});
    var config = logly.Config.default();
    config.levelColors.infoColor = logly.Color.parse("cyan").?;
    config.levelColors.warningColor = logly.Color.parse("yellow").?;
    logger.configure(config);

    try logger.info("Info - now Cyan", @src());
    try logger.warning("Warning - now Yellow", @src());
    try logger.flush();

    // Demonstrate theme presets
    std.debug.print("\nTheme Presets\n\n", .{});
    config.levelColors.themePreset = .neon;
    logger.configure(config);
    try logger.info("Info - Neon Theme", @src());
    try logger.warning("Warning - Neon Theme", @src());

    try logger.success("Success message - green", @src());
    try logger.warning("Warning message - yellow", @src());
    try logger.err("Error message - red", @src());
    try logger.critical("Critical message - bright red", @src());
    try logger.flush();

    std.debug.print("\nCustom Level Colors\n\n", .{});

    try logger.custom("NOTICE", "Notice (Cyan)", @src());
    try logger.custom("ALERT", "Alert (Red)", @src());
    try logger.custom("HIGHLIGHT", "Highlight (Yellow)", @src());
    try logger.flush();

    std.debug.print("\nLevel Colors (tint sequences)\n\n", .{});

    // Demonstrate tint-backed level colors rendered as SGR sequences.
    // Each sequence is shown applied to sample text (raw bytes would be
    // invisible since the terminal interprets them as colors).
    const Level = logly.Level;
    const reset = logly.Color.resetAll;
    const seq = logly.Color.sequence(Level.trace.defaultColor(), .trueColor);
    std.debug.print("TRACE sequence: {s}sample trace text{s}\n", .{ seq.slice(), reset });
    const errSeq = logly.Color.sequence(Level.err.defaultColor(), .trueColor);
    std.debug.print("ERROR sequence: {s}sample error text{s}\n", .{ errSeq.slice(), reset });

    std.debug.print("\ntint Colors\n\n", .{});

    // Show tint color primitives directly.
    const tint = logly.Color.Tint;
    std.debug.print("ANSI red: {s}red sample{s}\n", .{ tint.color.ansi4.red.fg().slice(), reset });
    std.debug.print("256-color orange (208): {s}orange sample{s}\n", .{ tint.color.ansi256.index(208).fg().slice(), reset });
    std.debug.print("RGB coral: {s}coral sample{s}\n", .{ tint.color.rgb(255, 127, 80).fg().slice(), reset });

    std.debug.print("\nTheme Presets\n\n", .{});

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

    // Show theme colors rendered as sequences.
    const neon = Theme.neon();
    const neonTrace = logly.Color.sequence(neon.trace, .trueColor);
    const neonErr = logly.Color.sequence(neon.err, .trueColor);
    std.debug.print("\nNeon theme sequences:\n", .{});
    std.debug.print("  trace={s}sample{s} err={s}sample{s}\n", .{ neonTrace.slice(), reset, neonErr.slice(), reset });

    std.debug.print("\nAdvanced CustomLevel\n\n", .{});

    // Demonstrate CustomLevel creation with tint colors.
    const CustomLevel = logly.CustomLevel;

    const audit = CustomLevel.init("AUDIT", 35, logly.Color.parse("cyan").?);
    std.debug.print("CustomLevel.init - AUDIT: {s}\n", .{audit.name});

    // RGB custom level
    const metric = CustomLevel.initRgb("METRIC", 25, 50, 205, 50);
    const metricSeq = logly.Color.sequence(metric.color, .trueColor);
    std.debug.print("CustomLevel.initRgb - METRIC: {s}sample metric text{s}\n", .{ metricSeq.slice(), reset });

    // With background
    const alert = CustomLevel.initWithBackground(
        "ALERTBG",
        50,
        logly.Color.Tint.color.ansi4.brightWhite,
        logly.Color.Tint.color.ansi4.red,
    );
    std.debug.print("CustomLevel with background: hasBackground={}\n", .{alert.hasBackground()});

    std.debug.print("\nPlatform Support\n", .{});
    std.debug.print("Colors work on: Linux, macOS, Windows 10+, VS Code Terminal\n", .{});
    std.debug.print("256-color and RGB require terminal support\n", .{});
    std.debug.print("\nCustom colors example completed!\n", .{});
}
