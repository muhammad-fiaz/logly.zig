//! Runtime Configuration Override & Conflict Resolution Example
//!
//! Demonstrates:
//! 1. Dynamic logger level and format updates at runtime.
//! 2. Granular per-sink runtime overrides (level, format, color, enabled/disabled).
//! 3. Partial configuration overrides via ConfigOverride.
//! 4. Automatic conflict resolution (color consistency, stack trace dependencies, inverted sink ranges).

const std = @import("std");
const logly = @import("logly");
const Logger = logly.Logger;
const Config = logly.Config;
const SinkConfig = logly.SinkConfig;
const Level = logly.Level;

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== Runtime Configuration Override & Conflict Resolution Demo ===\n\n", .{});

    // 1. Initial logger setup (info level, text format)
    var initialConfig = Config.default();
    initialConfig.autoSink = false;
    initialConfig.level = .info;

    var logger = try Logger.initWithConfig(allocator, initialConfig);
    defer logger.deinit();

    const consoleSinkId = try logger.addSink(SinkConfig.console());
    const memorySinkId = try logger.addSink(SinkConfig.memory());
    _ = memorySinkId;

    std.debug.print("1. Initial state (Logger minimum level: {s}):\n", .{@tagName(logger.getLevel())});
    try logger.info("This is an info message (visible)", null);
    try logger.debug("This is a debug message (suppressed by initial info level)", null);

    // 2. Dynamic runtime level change
    std.debug.print("\n2. Dynamically changing logger level to DEBUG via logger.setLevel():\n", .{});
    logger.setLevel(.debug);
    std.debug.print("   New active level: {s}\n", .{@tagName(logger.getLevel())});
    try logger.debug("This is a debug message (now visible after runtime setLevel)", null);

    // 3. Dynamic per-sink format and level customization
    std.debug.print("\n3. Customizing console sink dynamically at runtime:\n", .{});
    try logger.setSinkFormat(consoleSinkId, .logfmt);
    try logger.info("Output in logfmt format after setSinkFormat()", null);

    // Switch back to text
    try logger.setSinkFormat(consoleSinkId, .text);

    // 4. Runtime partial override via ConfigOverride
    std.debug.print("\n4. Applying partial config override (warning level, json format, autoFlush):\n", .{});
    logger.applyOverride(.{
        .level = .warning,
        .format = .json,
        .autoFlush = true,
    });
    std.debug.print("   New logger level: {s}, logger default format: {s}\n", .{
        @tagName(logger.getLevel()),
        @tagName(logger.config.format),
    });
    try logger.info("Info message (suppressed by warning level)", null);
    try logger.warn("Warning message (visible in JSON format)", null);

    // 5. Automatic conflict resolution
    std.debug.print("\n5. Demonstrating automatic conflict resolution:\n", .{});

    // Conflict A: Symbolize stack trace enabled without capture stack trace
    var conflictConfig = Config.default();
    conflictConfig.captureStackTrace = false;
    conflictConfig.symbolizeStackTrace = true;
    std.debug.print("   [Conflict A] symbolizeStackTrace=true, captureStackTrace=false\n", .{});
    conflictConfig.resolveConflicts();
    std.debug.print("   -> Resolved: captureStackTrace is auto-enabled ({})\n", .{conflictConfig.captureStackTrace});

    // Conflict B: ColorMode .none with color=true
    conflictConfig.color = true;
    conflictConfig.globalColorDisplay = true;
    conflictConfig.colorMode = .none;
    std.debug.print("   [Conflict B] color=true, colorMode=.none\n", .{});
    conflictConfig.resolveConflicts();
    std.debug.print("   -> Resolved: color is disabled ({}), globalColorDisplay is ({})\n", .{
        conflictConfig.color,
        conflictConfig.globalColorDisplay,
    });

    // Conflict C: Inverted sink level range (min level higher than max level)
    var sinkRange = SinkConfig.console();
    sinkRange.level = .fatal;
    sinkRange.maxLevel = .debug;
    std.debug.print("   [Conflict C] Sink level={s}, maxLevel={s}\n", .{
        @tagName(sinkRange.level.?),
        @tagName(sinkRange.maxLevel.?),
    });
    sinkRange.resolveConflicts();
    std.debug.print("   -> Resolved: range re-ordered so min={s}, max={s}\n", .{
        @tagName(sinkRange.level.?),
        @tagName(sinkRange.maxLevel.?),
    });

    // 6. Reset logger to text format and complete
    logger.setFormat(.text);
    logger.setLevel(.info);
    try logger.info("Runtime configuration override demo finished successfully!", null);
    std.debug.print("\nRuntime Configuration Override Demo Complete\n", .{});
}
