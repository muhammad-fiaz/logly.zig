//! # Logly
//!
//! A high-performance, enterprise-grade structured logging library for Zig.
//!
//! Logly provides a clean, intuitive API for logging with support for:
//! - Colored console output with customizable themes
//! - JSON and structured log formatting
//! - File rotation with size and time-based policies
//! - Asynchronous I/O with configurable buffering
//! - Context binding for structured logging
//! - Custom log levels with configurable priorities
//! - Distributed tracing with trace/span propagation
//! - Sampling and rate limiting for high-throughput systems
//! - Sensitive data redaction for compliance
//! - Metrics collection and observability
//!
//! ## Quick Start
//!
//! ```zig
//! const logly = @import("logly");
//!
//! pub fn main() !void {
//!     var gpa = std.heap.GeneralPurposeAllocator(.{}){};
//!     const allocator = gpa.allocator();
//!
//!     const logger = try logly.Logger.init(allocator);
//!     defer logger.deinit();
//!
//!     try logger.info("Application started");
//!     try logger.infof("Processing {d} items", .{42});
//! }
//! ```
//!
//! ## Production Configuration
//!
//! ```zig
//! const config = logly.Config.production();
//! const logger = try logly.Logger.initWithConfig(allocator, config);
//! ```
//!
//! ## Distributed Tracing
//!
//! ```zig
//! try logger.setTraceContext("trace-123", "span-456");
//! try logger.info("Request processed");
//! ```

const std = @import("std");

// Core components
pub const Level = @import("level.zig").Level;
pub const CustomLevel = @import("level.zig").CustomLevel;
pub const Logger = @import("logger.zig").Logger;
pub const ScopedLogger = @import("logger.zig").ScopedLogger;
pub const SpanContext = @import("logger.zig").SpanContext;
pub const Config = @import("config.zig").Config;
pub const Sink = @import("sink.zig").Sink;
pub const SinkConfig = @import("sink.zig").SinkConfig;
pub const Record = @import("record.zig").Record;
pub const Formatter = @import("formatter.zig").Formatter;
pub const Rotation = @import("rotation.zig").Rotation;

// Enterprise components
pub const Filter = @import("filter.zig").Filter;
pub const FilterRule = Filter.FilterRule;
pub const FilterPresets = @import("filter.zig").FilterPresets;
pub const Sampler = @import("sampler.zig").Sampler;
pub const SamplerPresets = @import("sampler.zig").SamplerPresets;
pub const Redactor = @import("redactor.zig").Redactor;
pub const RedactionPresets = @import("redactor.zig").RedactionPresets;
pub const Metrics = @import("metrics.zig").Metrics;

// Configuration presets
pub const ConfigPresets = struct {
    pub fn production() Config {
        return Config.production();
    }

    pub fn development() Config {
        return Config.development();
    }

    pub fn highThroughput() Config {
        return Config.highThroughput();
    }

    pub fn secure() Config {
        return Config.secure();
    }
};

// Sink configuration helpers
pub const SinkPresets = struct {
    pub fn console() SinkConfig {
        return SinkConfig.default();
    }

    pub fn file(path: []const u8) SinkConfig {
        return SinkConfig.file(path);
    }

    pub fn jsonFile(path: []const u8) SinkConfig {
        return SinkConfig.jsonFile(path);
    }

    pub fn rotating(path: []const u8, interval: []const u8, retention: usize) SinkConfig {
        return SinkConfig.rotating(path, interval, retention);
    }

    pub fn errorOnly(path: []const u8) SinkConfig {
        return SinkConfig.errorOnly(path);
    }
};

/// Platform utilities for terminal/console support.
pub const Terminal = struct {
    /// Enable ANSI color support on Windows consoles.
    /// On other platforms, this is a no-op as ANSI is supported by default.
    ///
    /// Call this at the start of your program if you want colors on Windows:
    /// ```zig
    /// logly.Terminal.enableAnsiColors();
    /// ```
    ///
    /// Returns true if colors are enabled/supported, false otherwise.
    pub fn enableAnsiColors() bool {
        const builtin = @import("builtin");
        if (builtin.os.tag == .windows) {
            return enableWindowsAnsi();
        }
        // Linux, macOS, and other Unix-like systems support ANSI by default
        return true;
    }

    /// Check if the current terminal supports ANSI colors.
    pub fn supportsAnsiColors() bool {
        const builtin = @import("builtin");
        if (builtin.os.tag == .windows) {
            // On Windows, try to detect if we're in a modern terminal
            return detectWindowsAnsiSupport();
        }
        // Check TERM environment variable on Unix-like systems
        if (std.posix.getenv("TERM")) |term| {
            // Most common terminals that support color
            const color_terms = [_][]const u8{
                "xterm",         "xterm-256color",  "xterm-color",
                "screen",        "screen-256color", "tmux",
                "tmux-256color", "linux",           "vt100",
                "vt220",         "rxvt",            "ansi",
                "cygwin",        "putty",
            };
            for (color_terms) |ct| {
                if (std.mem.startsWith(u8, term, ct)) return true;
            }
            // Also check for "color" in the term name
            if (std.mem.indexOf(u8, term, "color") != null) return true;
        }
        // Fallback: assume color support on non-Windows platforms
        return true;
    }

    fn enableWindowsAnsi() bool {
        const builtin = @import("builtin");
        if (builtin.os.tag != .windows) return true;

        const windows = std.os.windows;
        const kernel32 = windows.kernel32;

        // Get stdout handle
        const stdout_handle = kernel32.GetStdHandle(windows.STD_OUTPUT_HANDLE);
        if (stdout_handle == windows.INVALID_HANDLE_VALUE) return false;

        // Handle can be null if there's no console
        const handle = stdout_handle orelse return false;

        // Get current console mode
        var mode: windows.DWORD = 0;
        if (kernel32.GetConsoleMode(handle, &mode) == 0) {
            // Not a console (e.g., redirected to file) - that's fine
            return false;
        }

        // Enable virtual terminal processing
        const ENABLE_VIRTUAL_TERMINAL_PROCESSING: windows.DWORD = 0x0004;
        const new_mode = mode | ENABLE_VIRTUAL_TERMINAL_PROCESSING;
        if (kernel32.SetConsoleMode(handle, new_mode) == 0) {
            // Failed to set mode - older Windows version?
            return false;
        }

        // Also enable for stderr
        const stderr_handle = kernel32.GetStdHandle(windows.STD_ERROR_HANDLE);
        if (stderr_handle != windows.INVALID_HANDLE_VALUE) {
            if (stderr_handle) |stderr| {
                var stderr_mode: windows.DWORD = 0;
                if (kernel32.GetConsoleMode(stderr, &stderr_mode) != 0) {
                    _ = kernel32.SetConsoleMode(stderr, stderr_mode | ENABLE_VIRTUAL_TERMINAL_PROCESSING);
                }
            }
        }

        return true;
    }

    fn detectWindowsAnsiSupport() bool {
        const builtin = @import("builtin");
        if (builtin.os.tag != .windows) return true;

        // Check if we're in Windows Terminal, VS Code, or other modern terminals
        if (std.posix.getenv("WT_SESSION")) |_| return true; // Windows Terminal
        if (std.posix.getenv("TERM_PROGRAM")) |prog| {
            if (std.mem.eql(u8, prog, "vscode")) return true;
        }
        if (std.posix.getenv("ANSICON")) |_| return true; // ANSICON

        // Try to enable and test
        return enableWindowsAnsi();
    }
};

test {
    std.testing.refAllDecls(@This());
}
