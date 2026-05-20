//! # Logly Documentations
//!
//! A fast, high-performance structured logging library for Zig.
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
//! const std = @import("std");
//! const logly = @import("logly");
//!
//! pub fn main() !void {
//!     var gpa = std.heap.DebugAllocator(.{}){};
//!     defer _ = gpa.deinit();
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
//! var config = logly.Config.production();
//! config.use_arena_allocator = true; // optional high-throughput scratch arena
//! const logger = try logly.Logger.initWithConfig(allocator, config);
//! ```
//!
//! ## Log-Only and Display-Only Modes
//!
//! ```zig
//! // Log-only mode (files only, no console)
//! const log_config = logly.Config.logOnly();
//! const log_logger = try logly.Logger.initWithConfig(allocator, log_config);
//!
//! // Display-only mode (console only, no files)
//! const display_config = logly.Config.displayOnly();
//! const display_logger = try logly.Logger.initWithConfig(allocator, display_config);
//! ```
//!
//! ## Distributed Tracing
//!
//! ```zig
//! try logger.setTraceContext("trace-123", "span-456");
//! try logger.info("Request processed");
//! ```
//!
//! For detailed documentation, visit: https://muhammad-fiaz.github.io/logly.zig/
//!
//! For source code and examples, visit: https://github.com/muhammad-fiaz/logly.zig

pub const version = @import("version.zig").version;

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
pub const Constants = @import("constants.zig");
pub const Utils = @import("utils.zig");
pub const utils = Utils;

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
pub const Rules = @import("rules.zig").Rules;
pub const RulesConfig = Rules.RulesConfig;
pub const RuleMessage = Rules.RuleMessage;
pub const RuleMessageBuilder = @import("rules.zig").RuleMessageBuilder;
pub const LevelMatchBuilder = @import("rules.zig").LevelMatchBuilder;
pub const UpdateChecker = @import("update_checker.zig"); // Added alias

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
pub const Network = @import("network.zig");

// Utility components
pub const TelemetryConfig = @import("config.zig").TelemetryConfig;

// OpenTelemetry integration
pub const Telemetry = @import("telemetry.zig").Telemetry;
pub const Span = @import("telemetry.zig").Span;
pub const SpanAttribute = @import("telemetry.zig").SpanAttribute;
pub const SpanEvent = @import("telemetry.zig").SpanEvent;
pub const SpanKind = @import("telemetry.zig").SpanKind;
pub const SpanStatus = @import("telemetry.zig").SpanStatus;
pub const SpanOptions = @import("telemetry.zig").SpanOptions;
pub const Metric = @import("telemetry.zig").Metric;
pub const MetricKind = @import("telemetry.zig").MetricKind;
pub const MetricOptions = @import("telemetry.zig").MetricOptions;
pub const Resource = @import("telemetry.zig").Resource;
pub const TelemetrySampler = @import("telemetry.zig").TelemetrySampler;
pub const Baggage = @import("telemetry.zig").Baggage;
pub const TraceContext = @import("telemetry.zig").TraceContext;
pub const ExporterStats = @import("telemetry.zig").ExporterStats;
pub const NetworkProtocol = @import("telemetry.zig").NetworkProtocol;
pub const ExportMode = @import("telemetry.zig").ExportMode;
pub const TelemetryStats = @import("telemetry.zig").TelemetryStats;

// Re-export ParallelConfig from Config
pub const ParallelConfig = Config.ParallelConfig;

// Configuration presets
pub const ConfigPresets = struct {
    pub fn production() Config {
        return Config.production();
    }

    /// Alias for production
    pub const prod = production;

    pub fn development() Config {
        return Config.development();
    }

    /// Alias for development
    pub const dev = development;

    pub fn highThroughput() Config {
        return Config.highThroughput();
    }

    /// Alias for highThroughput
    pub const fast = highThroughput;
    pub const throughput = highThroughput;

    pub fn secure() Config {
        return Config.secure();
    }

    /// Alias for secure
    pub const security = secure;

    /// Log-only mode (no console display, only file storage)
    pub fn logOnly() Config {
        return Config.logOnly();
    }

    /// Alias for logOnly
    pub const filesOnly = logOnly;

    /// Display-only mode (console display, no file storage)
    pub fn displayOnly() Config {
        return Config.displayOnly();
    }

    /// Alias for displayOnly
    pub const consoleOnly = displayOnly;

    /// Custom display and storage settings
    pub fn withDisplayStorage(console: bool, file: bool, auto_sink: bool) Config {
        return Config.withDisplayStorage(console, file, auto_sink);
    }

    /// Alias for withDisplayStorage
    pub const custom = withDisplayStorage;
    pub const withStorage = withDisplayStorage;
};

// Sink configuration helpers
pub const SinkPresets = struct {
    pub fn console() SinkConfig {
        return SinkConfig.console();
    }

    /// Alias for console
    pub const stdout = console;
    pub const terminal = console;

    pub fn file(path: []const u8) SinkConfig {
        return SinkConfig.file(path);
    }

    /// Alias for file
    pub const toFile = file;

    pub fn jsonFile(path: []const u8) SinkConfig {
        return SinkConfig.jsonFile(path);
    }

    /// Alias for jsonFile
    pub const json = jsonFile;
    pub const toJsonFile = jsonFile;

    pub fn rotating(path: []const u8, interval: []const u8, retention: usize) SinkConfig {
        return SinkConfig.rotating(path, interval, retention);
    }

    /// Alias for rotating
    pub const rotate = rotating;
    pub const rotatingFile = rotating;

    pub fn errorOnly(path: []const u8) SinkConfig {
        return SinkConfig.errorOnly(path);
    }

    /// Alias for errorOnly
    pub const errors = errorOnly;
    pub const errorFile = errorOnly;

    pub fn network(uri: []const u8) SinkConfig {
        return SinkConfig.network(uri);
    }

    /// Alias for network
    pub const remote = network;
    pub const net = network;
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

    /// Alias for enableAnsiColors
    pub const enableColors = enableAnsiColors;
    pub const ansi = enableAnsiColors;

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

    /// Alias for supportsAnsiColors
    pub const supportsColors = supportsAnsiColors;
    pub const hasAnsi = supportsAnsiColors;

    /// Explicitly enable or disable colors (useful for bare metal or testing).
    var color_enabled: bool = true;

    pub fn setColorEnabled(enabled: bool) void {
        color_enabled = enabled;
    }

    /// Alias for setColorEnabled
    pub const setColors = setColorEnabled;
    pub const enable = setColorEnabled;

    pub fn isColorEnabled() bool {
        return color_enabled and supportsAnsiColors();
    }

    /// Alias for isColorEnabled
    pub const colorsEnabled = isColorEnabled;
    pub const isEnabled = isColorEnabled;

    fn enableWindowsAnsi() bool {
        const builtin = @import("builtin");
        if (builtin.os.tag != .windows) return true;

        std.Io.File.stdout().enableAnsiEscapeCodes(Utils.io()) catch return false;
        std.Io.File.stderr().enableAnsiEscapeCodes(Utils.io()) catch {};

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
