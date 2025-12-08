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

// Nested config types (convenience re-exports from Config)
pub const ThreadPoolConfig = Config.ThreadPoolConfig;
pub const SchedulerConfig = Config.SchedulerConfig;
pub const CompressionConfig = Config.CompressionConfig;
pub const CompressionAlgorithm = Config.CompressionConfig.CompressionAlgorithm;
pub const CompressionLevel = Config.CompressionConfig.CompressionLevel;
pub const AsyncConfig = Config.AsyncConfig;
pub const SamplingConfig = Config.SamplingConfig;
pub const RateLimitConfig = Config.RateLimitConfig;
pub const RedactionConfig = Config.RedactionConfig;
pub const BufferConfig = Config.BufferConfig;
pub const ErrorHandling = Config.ErrorHandling;
pub const Timezone = Config.Timezone;

// Enterprise components
pub const Filter = @import("filter.zig").Filter;
pub const FilterRule = Filter.FilterRule;
pub const FilterPresets = @import("filter.zig").FilterPresets;
pub const Sampler = @import("sampler.zig").Sampler;
pub const SamplerPresets = @import("sampler.zig").SamplerPresets;
pub const Redactor = @import("redactor.zig").Redactor;
pub const RedactionPresets = @import("redactor.zig").RedactionPresets;
pub const Metrics = @import("metrics.zig").Metrics;
pub const Diagnostics = @import("diagnostics.zig");

// Advanced I/O components
pub const Compression = @import("compression.zig").Compression;
pub const CompressionPresets = @import("compression.zig").CompressionPresets;
pub const AsyncLogger = @import("async.zig").AsyncLogger;
pub const AsyncFileWriter = @import("async.zig").AsyncFileWriter;
pub const AsyncPresets = @import("async.zig").AsyncPresets;
pub const Scheduler = @import("scheduler.zig").Scheduler;
pub const SchedulerPresets = @import("scheduler.zig").SchedulerPresets;
pub const ThreadPool = @import("thread_pool.zig").ThreadPool;
pub const ThreadPoolPresets = @import("thread_pool.zig").ThreadPoolPresets;

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

/// Platform utilities for terminal and console support.
/// Handles ANSI color detection and enablement across all platforms.
pub const Terminal = struct {
    /// Enable ANSI color codes for the current terminal.
    ///
    /// - Windows: Enables Virtual Terminal Processing in the console
    /// - Linux/macOS/Unix: Returns true (ANSI supported natively)
    /// - Bare metal/freestanding: Returns based on color_enabled flag
    ///
    /// Returns true if colors are available, false otherwise.
    pub fn enableAnsiColors() bool {
        const builtin = @import("builtin");

        // Bare metal / freestanding - no terminal, but allow if explicitly enabled
        if (builtin.os.tag == .freestanding) {
            return color_enabled;
        }

        // Windows requires explicit enablement
        if (builtin.os.tag == .windows) {
            return enableWindowsAnsi();
        }

        // Unix-like systems (Linux, macOS, BSD, etc.) support ANSI natively
        return true;
    }

    /// Check if the terminal likely supports ANSI color codes.
    pub fn supportsAnsiColors() bool {
        const builtin = @import("builtin");

        if (builtin.os.tag == .freestanding) {
            return color_enabled;
        }

        if (builtin.os.tag == .windows) {
            return detectWindowsAnsiSupport();
        }

        // Check TERM environment variable on Unix-like systems
        if (std.posix.getenv("TERM")) |term| {
            const color_terms = [_][]const u8{
                "xterm",         "xterm-256color",  "xterm-color",
                "screen",        "screen-256color", "tmux",
                "tmux-256color", "linux",           "vt100",
                "vt220",         "rxvt",            "ansi",
                "cygwin",        "putty",           "konsole",
                "gnome",         "alacritty",       "kitty",
            };
            for (color_terms) |ct| {
                if (std.mem.startsWith(u8, term, ct)) return true;
            }
            if (std.mem.indexOf(u8, term, "color") != null) return true;
        }

        // Check for known color-supporting environment variables
        if (std.posix.getenv("COLORTERM")) |_| return true;
        if (std.posix.getenv("FORCE_COLOR")) |_| return true;

        return true; // Default to enabled on Unix-like systems
    }

    /// Explicitly enable or disable colors (useful for bare metal or testing).
    var color_enabled: bool = true;

    pub fn setColorEnabled(enabled: bool) void {
        color_enabled = enabled;
    }

    pub fn isColorEnabled() bool {
        return color_enabled and supportsAnsiColors();
    }

    fn enableWindowsAnsi() bool {
        const builtin = @import("builtin");
        if (builtin.os.tag != .windows) return true;

        const windows = std.os.windows;
        const kernel32 = windows.kernel32;

        const stdout_handle = kernel32.GetStdHandle(windows.STD_OUTPUT_HANDLE);
        if (stdout_handle == windows.INVALID_HANDLE_VALUE) return false;

        const handle = stdout_handle orelse return false;

        var mode: windows.DWORD = 0;
        if (kernel32.GetConsoleMode(handle, &mode) == 0) {
            return false;
        }

        const ENABLE_VIRTUAL_TERMINAL_PROCESSING: windows.DWORD = 0x0004;
        const new_mode = mode | ENABLE_VIRTUAL_TERMINAL_PROCESSING;
        if (kernel32.SetConsoleMode(handle, new_mode) == 0) {
            return false;
        }

        // Enable for stderr as well
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

        // Modern Windows terminals
        if (std.posix.getenv("WT_SESSION")) |_| return true;
        if (std.posix.getenv("TERM_PROGRAM")) |prog| {
            if (std.mem.eql(u8, prog, "vscode")) return true;
        }
        if (std.posix.getenv("ANSICON")) |_| return true;
        if (std.posix.getenv("ConEmuANSI")) |v| {
            if (std.mem.eql(u8, v, "ON")) return true;
        }

        return enableWindowsAnsi();
    }
};

test {
    std.testing.refAllDecls(@This());
}
