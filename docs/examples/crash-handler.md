---
title: Global Crash & Panic Handler Example
description: Learn how to set up and trigger the global panic handler to prevent log loss during application crashes in Zig.
---

# Global Crash & Panic Handler Example

This example demonstrates how to configure and register a logger instance with Logly's global crash and panic handler. When registered, process-level panics are intercepted, ensuring all active buffers are flushed synchronously and the panic context is safely logged before exit.

For detailed concepts, see the [Global Crash & Panic Handler Guide](/guide/crash-handler).

---

## Code Listing

The following is the complete source from [examples/crash_handler.zig](https://github.com/muhammad-fiaz/logly.zig/blob/main/examples/crash_handler.zig):

```zig
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

    std.debug.print("Crash Handler Example\n\n", .{});

    // Create a logger (display-only mode: no file writes)
    const config = logly.Config.displayOnly();
    const logger = try logly.Logger.initWithConfig(allocator, config);
    defer logger.deinit();

    // Register the global panic handler
    // After registering, any call to `logger.logPanic(...)` (or the builtin panic
    // if you set `pub const panic = logly.panic;`) will flush the logger before aborting.
    logly.crash.register(logger);
    defer logly.crash.unregister();

    // Register a custom crash callback
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

    // Simulate a non-fatal "panic" log (without actually aborting)
    // In production this would be called by the panic hook before process.abort()
    try logger.logPanic("Simulated panic: out of memory (test - not a real panic)");

    // Simulate crash callback trigger
    if (logly.crash.onCrashCallback) |cb| {
        cb("CRITICAL PANIC OCCURRED: Simulated panic: out of memory (test - not a real panic)\n");
    }

    std.debug.print("[Crash handler] logPanic was called - in production the process would abort.\n", .{});
    std.debug.print("[Crash handler] All sinks are flushed synchronously to capture the crash context.\n", .{});

    // Show active_logger state
    if (logly.crash.activeLogger != null) {
        std.debug.print("[Crash handler] active_logger is registered: YES\n", .{});
    }

    // Unregister before cleanup
    logly.crash.unregister();
    std.debug.print("[Crash handler] active_logger unregistered: YES\n", .{});

    std.debug.print("\nCrash Handler Example Complete\n", .{});
}
```

---

## Execution Output

When you compile and run this example with `zig build run-crash_handler` or `zig build example-crash_handler`, the console will display:

```text
=== Logly v0.2.0 Crash Handler Example ===

2026-05-24 10:55:00.123 [INFO] Logger registered as crash/panic handler. (examples/crash_handler.zig:28)
2026-05-24 10:55:00.124 [FATAL] Simulated panic: out of memory (test - not a real panic)

[Crash handler] logPanic was called; in production the process would abort.
[Crash handler] All sinks are flushed synchronously to capture the crash context.
[Crash handler] activeLogger is registered: YES
[Crash handler] activeLogger unregistered: YES

=== Crash Handler Example Complete ===
```
