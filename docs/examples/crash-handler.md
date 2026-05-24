---
title: Global Crash & Panic Handler Example
description: Learn how to set up and trigger the global panic handler to prevent log loss during application crashes in Zig.
---

# Global Crash & Panic Handler Example

This example demonstrates how to configure and register a logger instance with Logly's global crash and panic handler. When registered, process-level panics are intercepted, ensuring all active buffers are flushed synchronously and the panic context is safely logged before exit.

For detailed concepts, see the [Global Crash & Panic Handler Guide](/guide/crash-handler).

---

## Code Listing

The following is the complete source from [examples/crash_handler.zig](file:///c:/Users/smuha/Downloads/logly.zig/examples/crash_handler.zig):

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

    std.debug.print("=== Logly v0.2.0 Crash Handler Example ===\n\n", .{});

    // Create a logger (display-only mode: no file writes)
    const config = logly.Config.displayOnly();
    const logger = try logly.Logger.initWithConfig(allocator, config);
    defer logger.deinit();

    // --- Register the global panic handler ---
    // After registering, any call to `logger.logPanic(...)` (or the builtin panic
    // if you set `pub const panic = logly.panic;`) will flush the logger before aborting.
    logly.crash.registerLogger(logger);
    defer logly.crash.unregisterLogger();

    try logger.info("Logger registered as crash/panic handler.", @src());

    // --- Simulate a non-fatal "panic" log (without actually aborting) ---
    // In production this would be called by the panic hook before process.abort()
    try logger.logPanic("Simulated panic: out of memory (test - not a real panic)");

    std.debug.print("\n[Crash handler] logPanic was called — in production the process would abort.\n", .{});
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
```

---

## Execution Output

When you compile and run this example with `zig build run-crash_handler` or `zig build example-crash_handler`, the console will display:

```text
=== Logly v0.2.0 Crash Handler Example ===

2026-05-24 10:55:00.123 [INFO] Logger registered as crash/panic handler. (examples/crash_handler.zig:28)
2026-05-24 10:55:00.124 [FATAL] Simulated panic: out of memory (test - not a real panic)

[Crash handler] logPanic was called — in production the process would abort.
[Crash handler] All sinks are flushed synchronously to capture the crash context.
[Crash handler] active_logger is registered: YES
[Crash handler] active_logger unregistered: YES

=== Crash Handler Example Complete ===
```
