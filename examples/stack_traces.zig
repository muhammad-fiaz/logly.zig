//! Stack Traces Example.
//!
//! Demonstrates automatic stack trace capture and formatting
//! for error and critical log messages in Logly.zig.

const std = @import("std");
const logly = @import("logly");

fn triggerFailure(logger: *logly.Logger) !void {
    try helperFunction(logger);
}

fn helperFunction(logger: *logly.Logger) !void {
    try deepOperation(logger);
}

fn deepOperation(logger: *logly.Logger) !void {
    try logger.err("Database transaction failed with connection timeout", @src());
    try logger.critical("Kernel subsystem unrecoverable error", @src());
}

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n=== Stack Traces Demo ===\n\n", .{});

    // 1. Text Format with Stack Trace Capture
    std.debug.print("1. Text Format with captureStackTrace enabled:\n", .{});
    {
        var config = logly.Config.default();
        config.captureStackTrace = true;
        config.symbolizeStackTrace = true;
        config.color = false;

        const logger = try logly.Logger.initWithConfig(allocator, config);
        defer logger.deinit();

        try triggerFailure(logger);
    }

    // 2. JSON Format with Stack Trace Capture
    std.debug.print("\n2. JSON Format with captureStackTrace enabled:\n", .{});
    {
        var config = logly.Config.default();
        config.format = .json;
        config.captureStackTrace = true;
        config.color = false;

        const logger = try logly.Logger.initWithConfig(allocator, config);
        defer logger.deinit();

        try logger.err("API request payload failed validation", @src());
    }

    std.debug.print("\nStack Traces Demo completed successfully!\n", .{});
}
