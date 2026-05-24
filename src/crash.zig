//! Global Crash & Panic Interception Subsystem
//!
//! Provides portable, zero-allocation hooks to catch process-level panics,
//! POSIX signal aborts, and Windows Vectored Exceptions (VEH). Synchronously
//! flushes all active sinks before process shutdown to ensure in-flight logs
//! are fully persisted.

const std = @import("std");
const builtin = @import("builtin");
const Logger = @import("logger.zig").Logger;
const Constants = @import("constants.zig");
const Utils = @import("utils.zig");

/// Global reference to the active logger for panic and crash handling.
pub var active_logger: ?*Logger = null;

/// User-defined callback invoked immediately when a panic, Windows VEH exception, or POSIX signal occurs.
pub var on_crash_callback: ?*const fn (message: []const u8) void = null;

/// Sets the global crash/panic callback.
pub fn setCrashCallback(callback: ?*const fn (message: []const u8) void) void {
    on_crash_callback = callback;
}

// Ergonomic aliases
pub const onCrash = setCrashCallback;
pub const setCallback = setCrashCallback;

/// A flag to prevent re-entrant crashes during handler execution.
var is_handling_crash: std.atomic.Value(bool) = std.atomic.Value(bool).init(false);

/// Windows Exception Record structure definition.
/// Conforms to Win32 EXCEPTION_RECORD for native crash debugging.
const EXCEPTION_RECORD = struct {
    ExceptionCode: u32,
    ExceptionFlags: u32,
    ExceptionRecord: ?*EXCEPTION_RECORD,
    ExceptionAddress: ?*anyopaque,
    NumberParameters: u32,
    ExceptionInformation: [15]usize,
};

/// Windows Exception Pointers structure definition.
/// Conforms to Win32 EXCEPTION_POINTERS.
const EXCEPTION_POINTERS = struct {
    ExceptionRecord: *EXCEPTION_RECORD,
    ContextRecord: ?*anyopaque,
};

/// Pointer type for Windows EXCEPTION_POINTERS.
const PEXCEPTION_POINTERS = *EXCEPTION_POINTERS;
/// Standard Windows i32 type for API returns.
const LONG = i32;
/// Function signature type for Windows Vectored Exception Handlers.
const PVECTORED_EXCEPTION_HANDLER = *const fn (PEXCEPTION_POINTERS) callconv(.winapi) LONG;

/// Win32 API to register exception handlers.
extern "kernel32" fn AddVectoredExceptionHandler(
    FirstHandler: u32,
    VectoredHandler: PVECTORED_EXCEPTION_HANDLER,
) callconv(.winapi) ?*anyopaque;

/// Registers a logger to receive panic dumps and standard OS crashes.
///
/// Bypasses standard async logging queues during failures to ensure sync logging.
///
/// Arguments:
///     logger: The active Logger instance.
pub fn registerLogger(logger: *Logger) void {
    active_logger = logger;

    // Register standard OS crash traps
    if (builtin.os.tag == .windows) {
        _ = AddVectoredExceptionHandler(1, windowsExceptionHandler);
    } else {
        const signals = [_]std.posix.SIG{
            .SEGV,
            .ILL,
            .FPE,
            .ABRT,
            .BUS,
        };

        const sigaction = std.posix.Sigaction{
            .handler = .{ .handler = posixSignalHandler },
            .mask = std.mem.zeroes(std.posix.sigset_t),
            .flags = 0,
        };

        for (signals) |sig| {
            std.posix.sigaction(sig, &sigaction, null);
        }
    }
}

/// Unregisters the active logger.
pub fn unregisterLogger() void {
    active_logger = null;
}

/// Helper function to translate Windows exception codes into standard human-readable tags.
///
/// Arguments:
///     code: Windows NTSTATUS exception code.
///
/// Returns:
///     Human-readable name or UNKNOWN_WINDOWS_EXCEPTION.
fn getWindowsExceptionName(code: u32) []const u8 {
    for (Constants.CrashConstants.windows_exceptions) |ex| {
        if (ex.code == code) return ex.name;
    }
    return Constants.CrashConstants.unknown_windows_exception;
}

/// Custom Windows Vectored Exception Handler to intercept CPU crashes.
///
/// Arguments:
///     info: Windows exception pointer block.
///
/// Returns:
///     win32 LONG code (0 to continue search, -1 to execute handler).
fn windowsExceptionHandler(info: PEXCEPTION_POINTERS) callconv(.winapi) LONG {
    const code = info.ExceptionRecord.ExceptionCode;

    // Filter out non-fatal exceptions (e.g. harmless debugger breaks or status events)
    var is_fatal = false;
    for (Constants.CrashConstants.windows_exceptions) |ex| {
        if (ex.code == code) {
            is_fatal = ex.is_fatal;
            break;
        }
    }

    if (!is_fatal) return 0; // EXCEPTION_CONTINUE_SEARCH

    // Prevent re-entrant crashes
    if (is_handling_crash.swap(true, .acquire)) {
        return 0; // EXCEPTION_CONTINUE_SEARCH
    }

    var msg_buf: [Constants.BufferSizes.message]u8 = undefined;
    var final_msg: []const u8 = Constants.CrashConstants.windows_fallback_msg;

    if (active_logger) |logger| {
        const name = getWindowsExceptionName(code);
        final_msg = std.fmt.bufPrint(&msg_buf, Constants.CrashConstants.windows_triggered_fmt, .{ name, code }) catch final_msg;
        logger.logPanic(final_msg) catch {};
    } else {
        const name = getWindowsExceptionName(code);
        final_msg = std.fmt.bufPrint(&msg_buf, Constants.CrashConstants.windows_triggered_fmt, .{ name, code }) catch final_msg;
    }

    if (on_crash_callback) |cb| {
        cb(final_msg);
    }

    // Standard stderr printing fallback using centralized constants
    std.debug.print(Constants.CrashConstants.windows_stderr_fmt, .{code});

    return 0; // EXCEPTION_CONTINUE_SEARCH
}

/// Custom POSIX Signal Handler to intercept hardware and runtime abort signals.
///
/// Arguments:
///     sig: The POSIX signal received.
fn posixSignalHandler(sig: std.posix.SIG) callconv(.c) void {
    // Prevent re-entrant crashes
    if (is_handling_crash.swap(true, .acquire)) {
        std.process.abort();
    }

    var msg_buf: [Constants.BufferSizes.message]u8 = undefined;
    var final_msg: []const u8 = Constants.CrashConstants.posix_fallback_msg;

    const sig_name = switch (sig) {
        .SEGV => Constants.CrashConstants.posix_sigsegv,
        .ILL => Constants.CrashConstants.posix_sigill,
        .FPE => Constants.CrashConstants.posix_sigfpe,
        .ABRT => Constants.CrashConstants.posix_sigabrt,
        .BUS => Constants.CrashConstants.posix_sigbus,
        else => Constants.CrashConstants.posix_unknown_signal,
    };

    if (active_logger) |logger| {
        final_msg = std.fmt.bufPrint(&msg_buf, Constants.CrashConstants.posix_received_fmt, .{ sig_name, @intFromEnum(sig) }) catch final_msg;
        logger.logPanic(final_msg) catch {};
    } else {
        final_msg = std.fmt.bufPrint(&msg_buf, Constants.CrashConstants.posix_received_fmt, .{ sig_name, @intFromEnum(sig) }) catch final_msg;
    }

    if (on_crash_callback) |cb| {
        cb(final_msg);
    }

    // Default stderr printing fallback using centralized constants
    std.debug.print(Constants.CrashConstants.posix_stderr_fmt, .{@intFromEnum(sig)});

    // Restore default handler and let it re-raise cleanly for standard OS reporting / core dumps
    const sigaction = std.posix.Sigaction{
        .handler = .{ .handler = posixSignalHandlerDfl },
        .mask = std.mem.zeroes(std.posix.sigset_t),
        .flags = 0,
    };
    std.posix.sigaction(sig, &sigaction, null);

    // For synchronous signals (SEGV, FPE, ILL, BUS), returning automatically re-executes and crashes cleanly.
    // For asynchronous signals, we abort.
    switch (sig) {
        .SEGV, .ILL, .FPE, .BUS => return,
        else => std.process.abort(),
    }
}

/// Default POSIX signal handler fallback to abort immediately.
///
/// Arguments:
///     sig: Standard POSIX signal.
fn posixSignalHandlerDfl(sig: std.posix.SIG) callconv(.c) void {
    _ = sig;
    std.process.abort();
}

/// Global panic hook that intercepts process panics.
///
/// Arguments:
///     msg: Panic payload message.
///     error_return_trace: Trace metadata.
///     ret_addr: Return instruction address.
pub fn panic(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    var msg_buf: [Constants.BufferSizes.message]u8 = undefined;
    var final_msg: []const u8 = msg;

    if (active_logger) |logger| {
        const prefix = Constants.CrashConstants.panic_message_prefix;
        final_msg = std.fmt.bufPrint(&msg_buf, "{s}{s}\n", .{ prefix, msg }) catch msg;
        logger.logPanic(final_msg) catch {};
    }

    if (on_crash_callback) |cb| {
        cb(final_msg);
    }

    // Default stderr printing fallback using centralized constant
    const interceptor_prefix = Constants.CrashConstants.panic_interceptor_prefix;
    std.debug.print("{s}{s}\n", .{ interceptor_prefix, msg });
    _ = error_return_trace;
    _ = ret_addr;

    std.process.abort();
}

// Global Aliases for public interface ergonomics
pub const register = registerLogger;
pub const unregister = unregisterLogger;
pub const init = registerLogger;
pub const deinit = unregisterLogger;
pub const setup = registerLogger;
pub const reset = unregisterLogger;

test "panic and crash handler registration" {
    const allocator = std.testing.allocator;
    var logger = try Logger.init(allocator);
    defer logger.deinit();

    register(logger);
    try std.testing.expect(active_logger == logger);

    unregister();
    try std.testing.expect(active_logger == null);
}

test "windows exception translation" {
    try std.testing.expectEqualStrings("STATUS_ACCESS_VIOLATION (Access Violation)", getWindowsExceptionName(0xC0000005));
    try std.testing.expectEqualStrings("STATUS_INTEGER_DIVIDE_BY_ZERO (Integer Division by Zero)", getWindowsExceptionName(0xC0000094));
    try std.testing.expectEqualStrings("STATUS_ILLEGAL_INSTRUCTION (Illegal Instruction)", getWindowsExceptionName(0xC000001D));
    try std.testing.expectEqualStrings("UNKNOWN_WINDOWS_EXCEPTION", getWindowsExceptionName(0x12345678));
}

var test_crash_called: bool = false;
fn mockCrashCallback(msg: []const u8) void {
    _ = msg;
    test_crash_called = true;
}

test "crash callback registration and invocation" {
    test_crash_called = false;
    setCrashCallback(&mockCrashCallback);
    try std.testing.expect(on_crash_callback != null);

    // Invoke mock callback manually
    if (on_crash_callback) |cb| {
        cb("Test crash callback");
    }
    try std.testing.expect(test_crash_called);

    setCrashCallback(null);
    try std.testing.expect(on_crash_callback == null);
}
