//! Crash and panic handling.
//!
//! Flushes sinks on panic, POSIX signals, or Windows exceptions.
const std = @import("std");
const builtin = @import("builtin");
const Logger = @import("logger.zig").Logger;
const Constants = @import("constants.zig");
const Utils = @import("utils.zig");

/// Global reference to the active logger for panic and crash handling.
pub var activeLogger: ?*Logger = null;

/// User-defined callback invoked immediately when a panic, Windows VEH exception, or POSIX signal occurs.
pub var onCrashCallback: ?*const fn (message: []const u8) void = null;

/// Sets the global crash/panic callback.
pub fn setCrashCallback(callback: ?*const fn (message: []const u8) void) void {
    onCrashCallback = callback;
}

// Ergonomic aliases

/// A flag to prevent re-entrant crashes during handler execution.
var isHandlingCrash: std.atomic.Value(bool) = std.atomic.Value(bool).init(false);

/// Windows Exception Record structure definition.
/// Conforms to Win32 EXCEPTION_RECORD for native crash debugging.
const WinExceptionRecord = struct {
    exceptionCode: u32,
    exceptionFlags: u32,
    nextRecord: ?*WinExceptionRecord,
    exceptionAddress: ?*anyopaque,
    numberParameters: u32,
    exceptionInformation: [15]usize,
};

/// Windows Exception Pointers structure definition.
/// Conforms to Win32 EXCEPTION_POINTERS.
const WinExceptionPointers = struct {
    exceptionRecord: *WinExceptionRecord,
    contextRecord: ?*anyopaque,
};

/// Pointer type for Windows EXCEPTION_POINTERS.
const PWinExceptionPointers = *WinExceptionPointers;
/// Standard Windows i32 type for API returns.
const WinLong = i32;
/// Function signature type for Windows Vectored Exception Handlers.
const PVectoredExceptionHandler = *const fn (PWinExceptionPointers) callconv(.winapi) WinLong;

/// Win32 API to register exception handlers.
extern "kernel32" fn AddVectoredExceptionHandler(
    FirstHandler: u32,
    VectoredHandler: PVectoredExceptionHandler,
) callconv(.winapi) ?*anyopaque;

/// Registers a logger to receive panic dumps and standard OS crashes.
///
/// Bypasses standard async logging queues during failures to ensure sync logging.
pub fn register(logger: *Logger) void {
    activeLogger = logger;

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
pub fn unregister() void {
    activeLogger = null;
}

/// Helper function to translate Windows exception codes into standard human-readable tags.
fn getWindowsExceptionName(code: u32) []const u8 {
    for (Constants.CrashConstants.windowsExceptions) |ex| {
        if (ex.code == code) return ex.name;
    }
    return Constants.CrashConstants.unknownWindowsException;
}

/// Custom Windows Vectored Exception Handler to intercept CPU crashes.
fn windowsExceptionHandler(info: PWinExceptionPointers) callconv(.winapi) WinLong {
    const code = info.exceptionRecord.exceptionCode;

    // Filter out non-fatal exceptions (e.g. harmless debugger breaks or status events)
    var isFatal = false;
    for (Constants.CrashConstants.windowsExceptions) |ex| {
        if (ex.code == code) {
            isFatal = ex.isFatal;
            break;
        }
    }

    if (!isFatal) return 0; // EXCEPTION_CONTINUE_SEARCH

    // Prevent re-entrant crashes
    if (isHandlingCrash.swap(true, .acquire)) {
        return 0; // EXCEPTION_CONTINUE_SEARCH
    }

    var msgBuf: [Constants.BufferSizes.message]u8 = undefined;
    var finalMsg: []const u8 = Constants.CrashConstants.windowsFallbackMsg;

    if (activeLogger) |logger| {
        const name = getWindowsExceptionName(code);
        finalMsg = std.fmt.bufPrint(&msgBuf, Constants.CrashConstants.windowsTriggeredFmt, .{ name, code }) catch finalMsg;
        logger.logPanic(finalMsg) catch {};
    } else {
        const name = getWindowsExceptionName(code);
        finalMsg = std.fmt.bufPrint(&msgBuf, Constants.CrashConstants.windowsTriggeredFmt, .{ name, code }) catch finalMsg;
    }

    if (onCrashCallback) |cb| {
        cb(finalMsg);
    }

    // Standard stderr printing fallback using centralized constants
    std.debug.print(Constants.CrashConstants.windowsStderrFmt, .{code});

    return 0; // EXCEPTION_CONTINUE_SEARCH
}

/// Custom POSIX Signal Handler to intercept hardware and runtime abort signals.
fn posixSignalHandler(sig: std.posix.SIG) callconv(.c) void {
    // Prevent re-entrant crashes
    if (isHandlingCrash.swap(true, .acquire)) {
        std.process.abort();
    }

    var msgBuf: [Constants.BufferSizes.message]u8 = undefined;
    var finalMsg: []const u8 = Constants.CrashConstants.posixFallbackMsg;

    const sigName = switch (sig) {
        .SEGV => Constants.CrashConstants.posixSigsegv,
        .ILL => Constants.CrashConstants.posixSigill,
        .FPE => Constants.CrashConstants.posixSigfpe,
        .ABRT => Constants.CrashConstants.posixSigabrt,
        .BUS => Constants.CrashConstants.posixSigbus,
        else => Constants.CrashConstants.posixUnknownSignal,
    };

    if (activeLogger) |logger| {
        finalMsg = std.fmt.bufPrint(&msgBuf, Constants.CrashConstants.posixReceivedFmt, .{ sigName, @backingInt(sig) }) catch finalMsg;
        logger.logPanic(finalMsg) catch {};
    } else {
        finalMsg = std.fmt.bufPrint(&msgBuf, Constants.CrashConstants.posixReceivedFmt, .{ sigName, @backingInt(sig) }) catch finalMsg;
    }

    if (onCrashCallback) |cb| {
        cb(finalMsg);
    }

    // Default stderr printing fallback using centralized constants
    std.debug.print(Constants.CrashConstants.posixStderrFmt, .{@backingInt(sig)});

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
fn posixSignalHandlerDfl(sig: std.posix.SIG) callconv(.c) void {
    _ = sig;
    std.process.abort();
}

/// Global panic hook that intercepts process panics.
pub fn panic(msg: []const u8, errorReturnTrace: ?*std.builtin.StackTrace, retAddr: ?usize) noreturn {
    var msgBuf: [Constants.BufferSizes.message]u8 = undefined;
    var finalMsg: []const u8 = msg;

    if (activeLogger) |logger| {
        const prefix = Constants.CrashConstants.panicMessagePrefix;
        finalMsg = std.fmt.bufPrint(&msgBuf, "{s}{s}\n", .{ prefix, msg }) catch msg;
        logger.logPanic(finalMsg) catch {};
    }

    if (onCrashCallback) |cb| {
        cb(finalMsg);
    }

    // Default stderr printing fallback using centralized constant
    const interceptorPrefix = Constants.CrashConstants.panicInterceptorPrefix;
    std.debug.print("{s}{s}\n", .{ interceptorPrefix, msg });
    _ = errorReturnTrace;
    _ = retAddr;

    std.process.abort();
}

// Global Aliases for public interface ergonomics

test "panic and crash handler registration" {
    const allocator = std.testing.allocator;
    var logger = try Logger.init(allocator);
    defer logger.deinit();

    register(logger);
    try std.testing.expect(activeLogger == logger);

    unregister();
    try std.testing.expect(activeLogger == null);
}

test "windows exception translation" {
    try std.testing.expectEqualStrings("STATUS_ACCESS_VIOLATION (Access Violation)", getWindowsExceptionName(0xC0000005));
    try std.testing.expectEqualStrings("STATUS_INTEGER_DIVIDE_BY_ZERO (Integer Division by Zero)", getWindowsExceptionName(0xC0000094));
    try std.testing.expectEqualStrings("STATUS_ILLEGAL_INSTRUCTION (Illegal Instruction)", getWindowsExceptionName(0xC000001D));
    try std.testing.expectEqualStrings("UNKNOWN_WINDOWS_EXCEPTION", getWindowsExceptionName(0x12345678));
}

var testCrashCalled: bool = false;
fn mockCrashCallback(msg: []const u8) void {
    _ = msg;
    testCrashCalled = true;
}

test "crash callback registration and invocation" {
    testCrashCalled = false;
    setCrashCallback(&mockCrashCallback);
    try std.testing.expect(onCrashCallback != null);

    // Invoke mock callback manually
    if (onCrashCallback) |cb| {
        cb("Test crash callback");
    }
    try std.testing.expect(testCrashCalled);

    setCrashCallback(null);
    try std.testing.expect(onCrashCallback == null);
}
