//! Logly: structured logging for Zig.
//!
//! Start with Logger.init and logger.info. See Config for options.
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
pub const SinkGroup = @import("sink.zig").SinkGroup;
pub const Record = @import("record.zig").Record;
pub const Formatter = @import("formatter.zig").Formatter;
pub const Rotation = @import("rotation.zig").Rotation;
pub const Constants = @import("constants.zig");
pub const Utils = @import("utils.zig");
pub const utils = Utils;
pub const Color = @import("color.zig");
/// Direct access to the tint.zig color engine backing `Color`.
pub const tint = @import("tint");

// Nested config types (convenience re-exports from Config)
pub const Format = Config.Format;
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

pub const Invoke = @import("invoke.zig").Invoke;
pub const InvokeMessage = Invoke.Message;

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
pub const crash = @import("crash.zig");
pub const panic = crash.panic;

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

    pub fn development() Config {
        return Config.development();
    }

    pub fn highThroughput() Config {
        return Config.highThroughput();
    }

    pub fn secure() Config {
        return Config.secure();
    }

    /// Log-only mode (no console display, only file storage)
    pub fn logOnly() Config {
        return Config.logOnly();
    }

    /// Display-only mode (console display, no file storage)
    pub fn displayOnly() Config {
        return Config.displayOnly();
    }

    /// Custom display and storage settings
    pub fn withDisplayStorage(console: bool, file: bool, autoSink: bool) Config {
        return Config.withDisplayStorage(console, file, autoSink);
    }
};

// Sink configuration helpers
pub const SinkPresets = struct {
    pub fn console() SinkConfig {
        return SinkConfig.console();
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

    pub fn network(uri: []const u8) SinkConfig {
        return SinkConfig.network(uri);
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
            return colorEnabled;
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
            return colorEnabled;
        }

        if (builtin.os.tag == .windows) {
            return detectWindowsAnsiSupport();
        }

        // Check TERM environment variable on Unix-like systems.
        if (std.posix.getenv("TERM")) |term| {
            // Known color-capable terminals (prefix match).
            const colorTerms = [_][]const u8{
                // xterm family.
                "xterm",
                "xterm-256color",
                "xterm-color",
                "xterm-direct",
                "xterm-kitty",
                // GNU screen / tmux.
                "screen",
                "screen-256color",
                "screen-256color-bce",
                "tmux",
                "tmux-256color",
                "tmux-direct",
                // Modern GPU terminals.
                "alacritty",
                "kitty",
                "wezterm",
                "foot",
                "contour",
                "rio",
                "ghostty",
                "warp",
                // Linux console and classic terminals.
                "linux",
                "vt100",
                "vt220",
                "rxvt",
                "rxvt-unicode",
                "ansi",
                // Desktop environments and emulators.
                "cygwin",
                "putty",
                "konsole",
                "gnome",
                "gnome-256color",
                "xfce",
                "terminator",
                "st",
                "st-256color",
                "mlterm",
                "Terminology",
                "iterm",
                "Apple_Terminal",
                "vscode",
            };
            for (colorTerms) |ct| {
                if (std.mem.startsWith(u8, term, ct)) return true;
            }
            // Generic fallback: names mentioning color depth.
            if (std.mem.indexOf(u8, term, "color") != null) return true;
            if (std.mem.indexOf(u8, term, "256") != null) return true;
            if (std.mem.indexOf(u8, term, "truecolor") != null) return true;
            if (std.mem.indexOf(u8, term, "direct") != null) return true;
            // Explicitly monochrome terminals.
            if (std.mem.eql(u8, term, "dumb")) return false;
        }

        // Check for known color-supporting environment variables
        if (std.posix.getenv("COLORTERM")) |_| return true;
        if (std.posix.getenv("FORCE_COLOR")) |_| return true;

        return true; // Default to enabled on Unix-like systems
    }

    /// Explicitly enable or disable colors (useful for bare metal or testing).
    var colorEnabled: bool = true;

    pub fn setColorEnabled(enabled: bool) void {
        colorEnabled = enabled;
    }

    pub fn isColorEnabled() bool {
        return colorEnabled and supportsAnsiColors();
    }

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
