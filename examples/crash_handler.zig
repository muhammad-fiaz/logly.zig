const std = @import("std");
const logly = @import("logly");

/// Register our panic handler (optional: replaces the default Zig panic handler).
/// Uncomment the line below to hook into process-level crashes:
/// pub const panic = logly.panic;
pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    _ = logly.Terminal.enableAnsiColors();

    std.debug.print("=== Logly v0.2.1 Crash Handler Example ===\n\n", .{});

    // Create a logger (display-only mode: no file writes)
    const config = logly.Config.displayOnly();
    const logger = try logly.Logger.initWithConfig(allocator, config);
    defer logger.deinit();

    // --- Register the global panic handler ---
    // After registering, any call to `logger.logPanic(...)` (or the builtin panic
    // if you set `pub const panic = logly.panic;`) will flush the logger before aborting.
    logly.crash.registerLogger(logger);
    defer logly.crash.unregisterLogger();

    // --- Register a custom crash callback ---
    const Handlers = struct {
        fn onCrash(msg: []const u8) void {
            std.debug.print("\n[Example Callback] >>> CUSTOM CRASH CALLBACK TRIGGERED! <<<\n", .{});
            std.debug.print("[Example Callback] Message received: {s}", .{msg});
            std.debug.print("[Example Callback] >>> END OF CALLBACK <<<\n\n", .{});
        }
    };
    logly.crash.setCrashCallback(Handlers.onCrash);
    defer logly.crash.setCrashCallback(null);

    try logger.info("Logger registered as crash/panic handler.", @src());

    // --- Simulate a non-fatal "panic" log (without actually aborting) ---
    // In production this would be called by the panic hook before process.abort()
    try logger.logPanic("Simulated panic: out of memory (test - not a real panic)");

    // Simulate crash callback trigger
    if (logly.crash.on_crash_callback) |cb| {
        cb("CRITICAL PANIC OCCURRED: Simulated panic: out of memory (test - not a real panic)\n");
    }

    std.debug.print("[Crash handler] logPanic was called — in production the process would abort.\n", .{});
    std.debug.print("[Crash handler] All sinks are flushed synchronously to capture the crash context.\n", .{});

    // --- Show active_logger state ---
    if (logly.crash.active_logger != null) {
        std.debug.print("[Crash handler] active_logger is registered: YES\n", .{});
    }

    // Unregister before cleanup
    logly.crash.unregisterLogger();
    std.debug.print("[Crash handler] active_logger unregistered: YES\n", .{});

    std.debug.print("\n=== Crash Handler Example Complete ===\n", .{});
}
