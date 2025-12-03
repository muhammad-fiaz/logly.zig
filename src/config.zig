const std = @import("std");
const Level = @import("level.zig").Level;

/// Configuration options for the Logger.
///
/// This struct controls the global behavior of the logging system, including:
///   - Log levels and filtering.
///   - Output formatting (JSON, text, custom patterns).
///   - Display options (colors, timestamps, file info).
///   - Feature toggles (callbacks, exception handling).
///   - Enterprise features (sampling, rate limiting, redaction).
pub const Config = struct {
    /// Minimum log level. Only logs at this level or higher will be processed.
    level: Level = .info,

    /// Global display controls for all sinks.
    global_color_display: bool = true,
    global_console_display: bool = true,
    global_file_storage: bool = true,

    /// Enable or disable ANSI color codes in output.
    color: bool = true,

    /// Output format settings.
    json: bool = false,
    pretty_json: bool = false,
    log_compact: bool = false,

    /// Custom format string for log messages.
    /// Available placeholders: {time}, {level}, {message}, {module}, {function}, {file}, {line},
    /// {trace_id}, {span_id}, {caller}, {thread}
    log_format: ?[]const u8 = null,

    /// Time format string.
    /// Supports: "YYYY-MM-DD HH:mm:ss", "ISO8601", "RFC3339", "unix", "unix_ms"
    time_format: []const u8 = "YYYY-MM-DD HH:mm:ss",

    /// Timezone for timestamp formatting.
    timezone: Timezone = .local,

    /// Display options for metadata in log output.
    console: bool = true,
    show_time: bool = true,
    show_module: bool = true,
    show_function: bool = false,
    show_filename: bool = false,
    show_lineno: bool = false,
    show_thread_id: bool = false,
    show_process_id: bool = false,

    /// Include hostname in logs (useful for distributed systems).
    include_hostname: bool = false,

    /// Include process ID in logs.
    include_pid: bool = false,

    /// Automatically add a console sink on logger initialization.
    auto_sink: bool = true,

    /// Enable callback invocation for log events.
    enable_callbacks: bool = true,

    /// Enable exception/error handling within the logger.
    enable_exception_handling: bool = true,

    /// Enable version checking (for update notifications).
    enable_version_check: bool = false,

    /// Debug mode for internal logger diagnostics.
    debug_mode: bool = false,

    /// Path for internal debug log file.
    debug_log_file: ?[]const u8 = null,

    /// Sampling configuration for high-throughput scenarios.
    sampling: SamplingConfig = .{},

    /// Rate limiting configuration to prevent log flooding.
    rate_limit: RateLimitConfig = .{},

    /// Redaction settings for sensitive data.
    redaction: RedactionConfig = .{},

    /// Error handling behavior.
    error_handling: ErrorHandling = .log_and_continue,

    /// Maximum message length (truncate if exceeded).
    max_message_length: ?usize = null,

    /// Enable structured logging with automatic context propagation.
    structured: bool = false,

    /// Default context fields to include with every log.
    default_fields: ?[]const DefaultField = null,

    /// Application name for identification in distributed systems.
    app_name: ?[]const u8 = null,

    /// Application version for tracing.
    app_version: ?[]const u8 = null,

    /// Environment identifier (e.g., "production", "staging", "development").
    environment: ?[]const u8 = null,

    /// Enable distributed tracing support.
    enable_tracing: bool = false,

    /// Trace ID header name for distributed tracing.
    trace_header: []const u8 = "X-Trace-ID",

    /// Enable metrics collection.
    enable_metrics: bool = false,

    /// Buffer configuration for async operations.
    buffer_config: BufferConfig = .{},

    /// Timezone options.
    pub const Timezone = enum {
        local,
        utc,
    };

    /// Sampling configuration.
    pub const SamplingConfig = struct {
        enabled: bool = false,
        rate: f64 = 1.0,
        strategy: SamplingStrategy = .probability,

        pub const SamplingStrategy = enum {
            probability,
            rate_limit,
            adaptive,
            every_n,
        };
    };

    /// Rate limiting configuration.
    pub const RateLimitConfig = struct {
        enabled: bool = false,
        max_per_second: u32 = 1000,
        burst_size: u32 = 100,
        per_level: bool = false,
    };

    /// Redaction configuration.
    pub const RedactionConfig = struct {
        enabled: bool = false,
        fields: ?[]const []const u8 = null,
        patterns: ?[]const []const u8 = null,
        replacement: []const u8 = "[REDACTED]",
    };

    /// Error handling behavior.
    pub const ErrorHandling = enum {
        silent,
        log_and_continue,
        fail_fast,
        callback,
    };

    /// Default field configuration.
    pub const DefaultField = struct {
        key: []const u8,
        value: []const u8,
    };

    /// Buffer configuration for async operations.
    pub const BufferConfig = struct {
        size: usize = 8192,
        flush_interval_ms: u64 = 1000,
        max_pending: usize = 10000,
        overflow_strategy: OverflowStrategy = .drop_oldest,

        pub const OverflowStrategy = enum {
            drop_oldest,
            drop_newest,
            block,
        };
    };

    /// Returns the default configuration.
    ///
    /// The default configuration is:
    ///   - Level: INFO
    ///   - Output: Console with colors
    ///   - Format: Standard text
    ///   - Features: Callbacks and exception handling enabled
    pub fn default() Config {
        return .{};
    }

    /// Returns a configuration optimized for production environments.
    ///
    /// Features:
    ///   - INFO level minimum
    ///   - JSON output enabled
    ///   - No colors
    ///   - Sampling enabled at 10%
    ///   - Metrics enabled
    pub fn production() Config {
        return .{
            .level = .info,
            .json = true,
            .color = false,
            .global_color_display = false,
            .sampling = .{ .enabled = true, .rate = 0.1 },
            .enable_metrics = true,
            .structured = true,
        };
    }

    /// Returns a configuration optimized for development environments.
    ///
    /// Features:
    ///   - DEBUG level minimum
    ///   - Colors enabled
    ///   - Source location shown
    ///   - Debug mode enabled
    pub fn development() Config {
        return .{
            .level = .debug,
            .color = true,
            .show_function = true,
            .show_filename = true,
            .show_lineno = true,
            .debug_mode = true,
        };
    }

    /// Returns a configuration for high-throughput scenarios.
    ///
    /// Features:
    ///   - WARNING level minimum
    ///   - Async buffering optimized
    ///   - Rate limiting enabled
    ///   - Adaptive sampling
    pub fn highThroughput() Config {
        return .{
            .level = .warning,
            .sampling = .{ .enabled = true, .strategy = .adaptive, .rate = 0.5 },
            .rate_limit = .{ .enabled = true, .max_per_second = 10000 },
            .buffer_config = .{
                .size = 65536,
                .flush_interval_ms = 500,
                .max_pending = 100000,
            },
        };
    }

    /// Returns a configuration compliant with common security standards.
    ///
    /// Features:
    ///   - Redaction enabled
    ///   - No sensitive data in output
    ///   - Structured logging
    pub fn secure() Config {
        return .{
            .redaction = .{ .enabled = true },
            .structured = true,
            .include_hostname = false,
            .include_pid = false,
        };
    }

    /// Merges another configuration into this one.
    ///
    /// Non-default values from the other configuration will override this one.
    ///
    /// Arguments:
    ///     other: The configuration to merge from.
    ///
    /// Returns:
    ///     A new configuration with merged values.
    pub fn merge(self: Config, other: Config) Config {
        var result = self;
        if (other.level != .info) result.level = other.level;
        if (other.json) result.json = true;
        if (other.pretty_json) result.pretty_json = true;
        if (other.log_format != null) result.log_format = other.log_format;
        if (other.app_name != null) result.app_name = other.app_name;
        if (other.app_version != null) result.app_version = other.app_version;
        if (other.environment != null) result.environment = other.environment;
        if (other.sampling.enabled) result.sampling = other.sampling;
        if (other.rate_limit.enabled) result.rate_limit = other.rate_limit;
        if (other.redaction.enabled) result.redaction = other.redaction;
        return result;
    }
};
