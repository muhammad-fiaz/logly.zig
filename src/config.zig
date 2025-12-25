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
///
/// Usage:
/// ```zig
/// const config = logly.Config{
///     .level = .debug,
///     .json = true,
///     .include_hostname = true,
///     .time_format = "YYYY-MM-DD HH:mm:ss",
/// };
/// var logger = try logly.Logger.init(allocator, config);
/// ```
pub const Config = struct {
    /// Minimum log level. Only logs at this level or higher will be processed.
    level: Level = .info,

    /// Global display controls for all sinks.
    global_color_display: bool = true,
    global_console_display: bool = true,
    global_file_storage: bool = true,

    /// Enable or disable ANSI color codes in output.
    color: bool = true,

    /// Check for updates on startup.
    check_for_updates: bool = true,

    /// Emit system diagnostics on startup (OS, CPU, memory, drives).
    emit_system_diagnostics_on_init: bool = false,
    /// Include per-drive storage information when emitting diagnostics.
    include_drive_diagnostics: bool = true,

    /// Output format settings.
    json: bool = false,
    pretty_json: bool = false,
    log_compact: bool = false,

    /// Custom format string for log messages.
    /// Available placeholders: {time}, {level}, {message}, {module}, {function}, {file}, {line},
    /// {trace_id}, {span_id}, {caller}, {thread}
    log_format: ?[]const u8 = null,

    /// Time format string - supports custom formats with any separators.
    ///
    /// Predefined formats:
    ///   - "ISO8601" - ISO 8601 format (2025-12-04T06:39:53.091Z)
    ///   - "RFC3339" - RFC 3339 format (2025-12-04T06:39:53+00:00)
    ///   - "unix" - Unix timestamp in seconds
    ///   - "unix_ms" - Unix timestamp in milliseconds
    ///
    /// Custom format placeholders (any separator allowed: -, /, ., :, space, etc.):
    ///   - YYYY = 4-digit year (2025)
    ///   - YY = 2-digit year (25)
    ///   - MM = 2-digit month (01-12)
    ///   - M = 1-2 digit month (1-12)
    ///   - DD = 2-digit day (01-31)
    ///   - D = 1-2 digit day (1-31)
    ///   - HH = 2-digit hour 24h (00-23)
    ///   - hh = 2-digit hour 12h (01-12)
    ///   - mm = 2-digit minute (00-59)
    ///   - ss = 2-digit second (00-59)
    ///   - SSS = 3-digit millisecond (000-999)
    ///
    /// Examples:
    ///   - "YYYY-MM-DD HH:mm:ss.SSS" (default)
    ///   - "YYYY/MM/DD HH:mm:ss"
    ///   - "DD-MM-YYYY HH:mm:ss"
    ///   - "MM/DD/YYYY hh:mm:ss"
    ///   - "YY.MM.DD"
    ///   - "HH:mm:ss"
    ///   - "HH:mm:ss.SSS"
    time_format: []const u8 = "YYYY-MM-DD HH:mm:ss.SSS",

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

    /// Capture stack traces for Error and Critical log levels.
    /// If false, stack traces will not be collected or displayed.
    capture_stack_trace: bool = false,

    /// Resolve memory addresses in stack traces to function names and file locations.
    /// Requires `capture_stack_trace` to be true (or implicit capture for Error/Critical).
    /// This provides human-readable stack traces but has a performance cost.
    symbolize_stack_trace: bool = false,

    /// Automatically add a console sink on logger initialization.
    /// Only creates sink when both auto_sink=true and global_console_display=true.
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

    /// Stack size for capturing stack traces (default 1MB).
    stack_size: usize = 1024 * 1024,

    /// Enable distributed tracing support.
    enable_tracing: bool = false,

    /// Trace ID header name for distributed tracing.
    trace_header: []const u8 = "X-Trace-ID",

    /// Enable metrics collection.
    enable_metrics: bool = false,

    /// Buffer configuration for async operations.
    buffer_config: BufferConfig = .{},

    /// Async logging configuration.
    async_config: AsyncConfig = .{},

    /// Rules system configuration.
    rules: RulesConfig = .{},

    /// Thread pool configuration.
    thread_pool: ThreadPoolConfig = .{},

    /// Scheduler configuration.
    scheduler: SchedulerConfig = .{},

    /// Compression configuration.
    compression: CompressionConfig = .{},

    /// Rotation configuration.
    rotation: RotationConfig = .{},

    /// Use arena allocator for internal temporary allocations.
    /// Improves performance by batching allocations and reducing malloc overhead.
    use_arena_allocator: bool = false,

    /// Arena reset threshold in bytes. When arena reaches this size, it resets.
    arena_reset_threshold: usize = 64 * 1024,

    /// Optional global root path for all log files.
    /// If set, file sinks will be stored relative to this path.
    /// The directory will be auto-created if it doesn't exist.
    /// If the path cannot be created, a warning is emitted but logging continues.
    logs_root_path: ?[]const u8 = null,

    /// Optional custom path for diagnostics logs.
    /// If set, system diagnostics will be stored at this path.
    /// If null, diagnostics will use logs_root_path or default behavior.
    diagnostics_output_path: ?[]const u8 = null,

    /// Custom format structure configuration.
    format_structure: FormatStructureConfig = .{},

    /// Level-specific color customization.
    level_colors: LevelColorConfig = .{},

    /// Highlighter and alert configuration.
    highlighters: HighlighterConfig = .{},

    /// Custom log format structure configuration.
    pub const FormatStructureConfig = struct {
        /// Prefix to add before each log message (e.g., ">>> ").
        message_prefix: ?[]const u8 = null,

        /// Suffix to add after each log message (e.g., " <<<").
        message_suffix: ?[]const u8 = null,

        /// Separator between log fields/components.
        field_separator: []const u8 = " | ",

        /// Enable nested/hierarchical formatting for structured logs.
        enable_nesting: bool = false,

        /// Indentation for nested fields (spaces or tabs).
        nesting_indent: []const u8 = "  ",

        /// Custom field order: which fields appear first in output.
        /// If null, uses default order: [time, level, message, context].
        field_order: ?[]const []const u8 = null,

        /// Whether to include empty/null fields in output.
        include_empty_fields: bool = false,

        /// Custom placeholder prefix/suffix (default: {}, can be changed to [[]], etc.)
        placeholder_open: []const u8 = "{",
        placeholder_close: []const u8 = "}",
    };

    /// Per-level color customization.
    pub const LevelColorConfig = struct {
        /// Custom ANSI color code for TRACE level (null = use default).
        /// Format: ANSI escape code like "\x1b[36m" (cyan) or RGB tuple.
        trace_color: ?[]const u8 = null,

        /// Custom ANSI color code for DEBUG level.
        debug_color: ?[]const u8 = null,

        /// Custom ANSI color code for INFO level.
        info_color: ?[]const u8 = null,

        /// Custom ANSI color code for SUCCESS level.
        success_color: ?[]const u8 = null,

        /// Custom ANSI color code for WARNING level.
        warning_color: ?[]const u8 = null,

        /// Custom ANSI color code for ERROR level.
        error_color: ?[]const u8 = null,

        /// Custom ANSI color code for FAIL level.
        fail_color: ?[]const u8 = null,

        /// Custom ANSI color code for CRITICAL level.
        critical_color: ?[]const u8 = null,

        /// Use RGB color mode (true) instead of standard ANSI codes.
        use_rgb: bool = false,

        /// Background color support (true = color backgrounds, false = only text).
        support_background: bool = false,

        /// Reset code at end of each log (default: "\x1b[0m").
        reset_code: []const u8 = "\x1b[0m",
    };

    /// Highlighter patterns and alert configuration.
    pub const HighlighterConfig = struct {
        /// Enable highlighter system.
        enabled: bool = false,

        /// Pattern-based highlighters.
        patterns: ?[]const HighlightPattern = null,

        /// Alert callbacks for matched patterns.
        alert_on_match: bool = false,

        /// Severity level that triggers alerts.
        alert_min_severity: AlertSeverity = .warning,

        /// Custom callback function name for alerts (optional).
        alert_callback: ?[]const u8 = null,

        /// Maximum number of highlighter matches to track per message.
        max_matches_per_message: usize = 10,

        /// Whether to log highlighter matches as separate records.
        log_matches: bool = false,

        pub const AlertSeverity = enum {
            trace,
            debug,
            info,
            success,
            warning,
            err,
            fail,
            critical,
        };

        pub const HighlightPattern = struct {
            /// Pattern name/label.
            name: []const u8,

            /// Pattern to match (regex or substring).
            pattern: []const u8,

            /// Is this a regex pattern (true) or substring match (false)?
            is_regex: bool = false,

            /// Color to highlight with (ANSI code).
            highlight_color: []const u8 = "\x1b[1;93m", // bright yellow

            /// Severity level of this pattern.
            severity: AlertSeverity = .warning,

            /// Custom data associated with pattern (e.g., metric name, callback).
            metadata: ?[]const u8 = null,
        };
    };

    /// Timezone options.
    pub const Timezone = enum {
        local,
        utc,
    };

    /// Sampling configuration.
    pub const SamplingConfig = struct {
        enabled: bool = false,
        strategy: Strategy = .{ .probability = 1.0 },

        /// Sampling strategy configuration.
        pub const Strategy = union(enum) {
            /// Allow all records through (no sampling).
            none: void,

            /// Random probability-based sampling.
            /// Value is the probability (0.0 to 1.0) of allowing a record.
            probability: f64,

            /// Rate limiting: allow N records per time window.
            rate_limit: SamplingRateLimitConfig,

            /// Sample 1 out of every N records.
            every_n: u32,

            /// Adaptive sampling based on throughput.
            adaptive: AdaptiveConfig,
        };

        /// Configuration for rate limiting strategy
        pub const SamplingRateLimitConfig = struct {
            /// Maximum records allowed per window
            max_records: u32,
            /// Time window in milliseconds
            window_ms: u64,
        };

        /// Configuration for adaptive sampling strategy
        pub const AdaptiveConfig = struct {
            /// Target records per second
            target_rate: u32,
            /// Minimum sample rate (don't drop below this)
            min_sample_rate: f64 = 0.01,
            /// Maximum sample rate (don't go above this)
            max_sample_rate: f64 = 1.0,
            /// How often to adjust rate (milliseconds)
            adjustment_interval_ms: u64 = 1000,
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

    /// Thread pool configuration.
    pub const ThreadPoolConfig = struct {
        /// Enable thread pool for parallel processing.
        enabled: bool = false,
        /// Number of worker threads (0 = auto-detect based on CPU cores).
        thread_count: usize = 0,
        /// Maximum queue size for pending tasks.
        queue_size: usize = 10000,
        /// Stack size per thread in bytes.
        stack_size: usize = 1024 * 1024,
        /// Enable work stealing between threads.
        work_stealing: bool = true,
        /// Enable per-worker arena allocator for temporary allocations.
        enable_arena: bool = false,
        /// Thread naming prefix.
        thread_name_prefix: []const u8 = "logly-worker",
        /// Keep alive time for idle threads (milliseconds).
        keep_alive_ms: u64 = 60000,
        /// Enable thread affinity (pin threads to CPUs).
        thread_affinity: bool = false,
    };

    /// Scheduler configuration.
    pub const SchedulerConfig = struct {
        /// Enable the scheduler.
        enabled: bool = false,
        /// Default cleanup max age in days.
        cleanup_max_age_days: u64 = 7,
        /// Default max files to keep.
        max_files: ?usize = null,
        /// Enable compression before cleanup.
        compress_before_cleanup: bool = false,
        /// Default file pattern for cleanup.
        file_pattern: []const u8 = "*.log",
    };

    /// Compression configuration.
    pub const CompressionConfig = struct {
        /// Enable compression.
        enabled: bool = false,
        /// Compression algorithm.
        algorithm: CompressionAlgorithm = .deflate,
        /// Compression level.
        level: CompressionLevel = .default,
        /// Compress on rotation.
        on_rotation: bool = true,
        /// Keep original file after compression.
        keep_original: bool = false,
        /// Compression mode.
        mode: Mode = .on_rotation,
        /// Size threshold in bytes for on_size_threshold mode.
        size_threshold: u64 = 10 * 1024 * 1024,
        /// Buffer size for streaming compression.
        buffer_size: usize = 32 * 1024,
        /// Compression strategy.
        strategy: Strategy = .default,
        /// File extension for compressed files.
        extension: []const u8 = ".gz",
        /// Delete files older than this after compression (in seconds, 0 = never).
        delete_after: u64 = 0,
        /// Enable checksum validation.
        checksum: bool = true,
        /// Enable streaming compression (compress while writing).
        streaming: bool = false,
        /// Use background thread for compression.
        background: bool = false,
        /// Dictionary for compression (pre-trained patterns).
        dictionary: ?[]const u8 = null,
        /// Enable multi-threaded compression (for large files).
        parallel: bool = false,
        /// Memory limit for compression (bytes, 0 = unlimited).
        memory_limit: usize = 0,

        pub const CompressionAlgorithm = enum {
            none,
            deflate,
            zlib,
            raw_deflate,
        };

        pub const CompressionLevel = enum {
            none,
            fastest,
            fast,
            default,
            best,

            pub fn toInt(self: CompressionLevel) u4 {
                return switch (self) {
                    .none => 0,
                    .fastest => 1,
                    .fast => 3,
                    .default => 6,
                    .best => 9,
                };
            }
        };

        pub const Mode = enum {
            disabled,
            on_rotation,
            on_size_threshold,
            scheduled,
            streaming,
        };

        pub const Strategy = enum {
            default,
            text,
            binary,
            huffman_only,
            rle_only,
            adaptive,
        };
    };

    /// Rotation and retention configuration.
    pub const RotationConfig = struct {
        /// Enable default rotation for file sinks that don't specify it.
        enabled: bool = false,

        /// Default rotation interval (e.g., "daily", "hourly").
        /// Only used if sink doesn't specify rotation.
        interval: ?[]const u8 = null,

        /// Default size limit for rotation (in bytes).
        /// Only used if sink doesn't specify size limit.
        size_limit: ?u64 = null,

        /// Default size limit as string (e.g., "10MB").
        /// Only used if sink doesn't specify size limit.
        size_limit_str: ?[]const u8 = null,

        /// Maximum number of rotated files to retain.
        /// Older files will be deleted during rotation.
        retention_count: ?usize = null,

        /// Maximum age of rotated files in seconds.
        /// Files older than this will be deleted during rotation.
        max_age_seconds: ?i64 = null,

        /// Strategy for naming rotated files.
        /// Strategy for naming rotated files.
        naming_strategy: NamingStrategy = .timestamp,

        /// Custom format string for rotated files.
        /// Used when naming_strategy is .custom.
        /// Placeholders: {base}, {ext}, {timestamp}, {date}, {iso}, {index}
        naming_format: ?[]const u8 = null,

        /// Optional directory to move rotated files to.
        /// If null, files remain in the same directory as the log.
        archive_dir: ?[]const u8 = null,

        /// Whether to remove empty directories after cleanup.
        clean_empty_dirs: bool = false,

        /// Whether to perform cleanup asynchronously.
        async_cleanup: bool = false,

        pub const NamingStrategy = enum {
            /// Append timestamp: logly.log -> logly.log.1678888888
            timestamp,
            /// Append date: logly.log -> logly.log.2023-01-01
            date,
            /// Append ISO datetime: logly.log -> logly.log.2023-01-01T12-00-00
            iso_datetime,
            /// Rolling index: logly.log -> logly.log.1 (renames existing)
            index,
            /// Custom format string (requires naming_format to be set)
            custom,
        };
    };

    /// Rules system configuration for compiler-style guided diagnostics.
    pub const RulesConfig = struct {
        /// Master switch for rules system.
        enabled: bool = false,

        /// Enable/disable client-defined rules.
        client_rules_enabled: bool = true,

        /// Enable/disable built-in rules (reserved for future use).
        builtin_rules_enabled: bool = true,

        /// Use Unicode symbols in output (set to false for ASCII-only terminals).
        use_unicode: bool = true,

        /// Enable ANSI colors in rule message output.
        enable_colors: bool = true,

        /// Show rule IDs in output (useful for debugging).
        show_rule_id: bool = false,

        /// Include rule ID prefix like "R0001:" in output.
        include_rule_id_prefix: bool = false,

        /// Custom rule ID format string.
        rule_id_format: []const u8 = "R{d}",

        /// Indent string for rule messages.
        indent: []const u8 = "    ",

        /// Message prefix character/string.
        message_prefix: []const u8 = "↳",

        /// Include rule messages in JSON output.
        include_in_json: bool = true,

        /// Maximum number of rules allowed.
        max_rules: usize = 1000,

        /// Maximum messages per rule to display.
        max_messages_per_rule: usize = 10,

        /// Display rule messages on console (respects global_console_display).
        console_output: bool = true,

        /// Write rule messages to file sinks (respects global_file_storage).
        file_output: bool = true,

        /// Enable verbose mode with full context.
        verbose: bool = false,

        /// Sort messages by severity.
        sort_by_severity: bool = false,

        /// Preset configurations
        /// Minimal configuration with rules enabled.
        pub fn minimal() RulesConfig {
            return .{ .enabled = true, .use_unicode = true, .enable_colors = true };
        }

        /// Production configuration: no colors, no verbose, minimal output.
        pub fn production() RulesConfig {
            return .{
                .enabled = true,
                .use_unicode = false,
                .enable_colors = false,
                .show_rule_id = false,
                .verbose = false,
            };
        }

        /// Development configuration: full debugging with colors and Unicode.
        pub fn development() RulesConfig {
            return .{
                .enabled = true,
                .use_unicode = true,
                .enable_colors = true,
                .show_rule_id = true,
                .verbose = true,
            };
        }

        /// ASCII-only configuration for terminals without Unicode support.
        pub fn ascii() RulesConfig {
            return .{ .enabled = true, .use_unicode = false, .enable_colors = true };
        }

        /// Disabled configuration: zero overhead.
        pub fn disabled() RulesConfig {
            return .{ .enabled = false };
        }

        /// Silent mode: rules evaluate but don't output.
        pub fn silent() RulesConfig {
            return .{ .enabled = true, .console_output = false, .file_output = false };
        }

        /// Console only: no file output.
        pub fn consoleOnly() RulesConfig {
            return .{ .enabled = true, .console_output = true, .file_output = false };
        }

        /// File only: no console output.
        pub fn fileOnly() RulesConfig {
            return .{ .enabled = true, .console_output = false, .file_output = true };
        }
    };

    /// Async logging configuration.
    pub const AsyncConfig = struct {
        /// Enable async logging.
        enabled: bool = false,
        /// Buffer size for async queue.
        buffer_size: usize = 8192,
        /// Batch size for flushing.
        batch_size: usize = 100,
        /// Flush interval in milliseconds.
        flush_interval_ms: u64 = 100,
        /// Minimum time between flushes to avoid thrashing.
        min_flush_interval_ms: u64 = 0,
        /// Maximum latency before forcing a flush.
        max_latency_ms: u64 = 5000,
        /// What to do when buffer is full.
        overflow_policy: OverflowPolicy = .drop_oldest,
        /// Auto-start worker thread.
        background_worker: bool = true,

        pub const OverflowPolicy = enum {
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
    ///   - Compression enabled (on rotation)
    ///   - Scheduler enabled (auto cleanup)
    pub fn production() Config {
        return .{
            .level = .info,
            .json = true,
            .color = false,
            .global_color_display = false,
            .sampling = .{ .enabled = true, .strategy = .{ .probability = 0.1 } },
            .enable_metrics = true,
            .structured = true,
            .compression = .{
                .enabled = true,
                .level = .default,
                .on_rotation = true,
            },
            .rotation = .{
                .enabled = true,
                .retention_count = 30,
                .max_age_seconds = 30 * 24 * 3600,
            },
            .scheduler = .{
                .enabled = true,
                .cleanup_max_age_days = 30,
                .compress_before_cleanup = true,
            },
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
    ///   - Thread pool enabled
    ///   - Async logging enabled
    pub fn highThroughput() Config {
        return .{
            .level = .warning,
            .sampling = .{ .enabled = true, .strategy = .{ .adaptive = .{ .target_rate = 1000 } } },
            .rate_limit = .{ .enabled = true, .max_per_second = 10000 },
            .buffer_config = .{
                .size = 65536,
                .flush_interval_ms = 500,
                .max_pending = 100000,
            },
            .thread_pool = .{
                .enabled = true,
                .thread_count = 0, // auto-detect
                .queue_size = 50000,
                .work_stealing = true,
            },
            .async_config = .{
                .enabled = true,
                .buffer_size = 32768,
                .batch_size = 256,
                .flush_interval_ms = 50,
            },
            .rotation = .{
                .enabled = true,
                .naming_strategy = .timestamp,
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
        if (other.thread_pool.enabled) result.thread_pool = other.thread_pool;
        if (other.scheduler.enabled) result.scheduler = other.scheduler;
        if (other.compression.enabled) result.compression = other.compression;
        if (other.async_config.enabled) result.async_config = other.async_config;
        return result;
    }

    /// Returns a configuration with async logging enabled.
    pub fn withAsync(self: Config, config: AsyncConfig) Config {
        var result = self;
        result.async_config = config;
        result.async_config.enabled = true;
        return result;
    }

    /// Returns a configuration with compression enabled.
    pub fn withCompression(self: Config, config: CompressionConfig) Config {
        var result = self;
        result.compression = config;
        result.compression.enabled = true;
        return result;
    }

    /// Returns a configuration with thread pool enabled.
    pub fn withThreadPool(self: Config, config: ThreadPoolConfig) Config {
        var result = self;
        result.thread_pool = config;
        result.thread_pool.enabled = true;
        return result;
    }

    /// Returns a configuration with scheduler enabled.
    pub fn withScheduler(self: Config, config: SchedulerConfig) Config {
        var result = self;
        result.scheduler = config;
        result.scheduler.enabled = true;
        return result;
    }

    /// Returns a configuration with arena allocator hint enabled.
    /// When set, the logger will use an arena for internal temporary allocations
    /// which can improve performance by reducing allocation overhead.
    pub fn withArenaAllocation(self: Config) Config {
        var result = self;
        result.use_arena_allocator = true;
        return result;
    }

    /// Returns a configuration for log-only mode (no console display, only file storage).
    /// Disables console output while keeping file storage enabled.
    /// Useful for production environments where logs should only be written to files.
    pub fn logOnly() Config {
        var result = Config.default();
        result.global_console_display = false;
        result.global_file_storage = true;
        result.auto_sink = false; // Disable auto console sink
        return result;
    }

    /// Returns a configuration for display-only mode (console display, no file storage).
    /// Enables console output while disabling file storage.
    /// Useful for development or debugging where you only want to see logs in the console.
    pub fn displayOnly() Config {
        var result = Config.default();
        result.global_console_display = true;
        result.global_file_storage = false;
        result.auto_sink = true; // Enable auto console sink
        return result;
    }

    /// Returns a configuration with custom display and storage settings.
    /// Allows fine-grained control over console display and file storage.
    ///
    /// Arguments:
    ///     console: Enable/disable console display
    ///     file: Enable/disable file storage
    ///     auto_sink: Enable/disable automatic console sink creation
    pub fn withDisplayStorage(console: bool, file: bool, auto_sink: bool) Config {
        var result = Config.default();
        result.global_console_display = console;
        result.global_file_storage = file;
        result.auto_sink = auto_sink;
        return result;
    }
};

test "config default values" {
    const config = Config.default();
    try std.testing.expectEqual(Level.info, config.level);
    try std.testing.expect(config.global_color_display);
    try std.testing.expect(config.global_console_display);
    try std.testing.expect(config.global_file_storage);
    try std.testing.expect(config.color);
    try std.testing.expect(!config.json);
    try std.testing.expect(config.auto_sink);
}

test "config presets" {
    // Production preset
    const prod_config = Config.production();
    try std.testing.expectEqual(Level.info, prod_config.level);
    try std.testing.expect(!prod_config.color);
    try std.testing.expect(prod_config.json);

    // Development preset
    const dev_config = Config.development();
    try std.testing.expectEqual(Level.debug, dev_config.level);
    try std.testing.expect(dev_config.color);

    // High throughput preset
    const ht_config = Config.highThroughput();
    try std.testing.expectEqual(Level.warning, ht_config.level);
    try std.testing.expect(ht_config.thread_pool.enabled);
    try std.testing.expect(ht_config.async_config.enabled);

    // Secure preset
    const secure_config = Config.secure();
    try std.testing.expect(secure_config.redaction.enabled);
    try std.testing.expect(secure_config.structured);

    // Log only preset
    const log_only = Config.logOnly();
    try std.testing.expect(!log_only.global_console_display);
    try std.testing.expect(log_only.global_file_storage);

    // Display only preset
    const display_only = Config.displayOnly();
    try std.testing.expect(display_only.global_console_display);
    try std.testing.expect(!display_only.global_file_storage);
}

test "config with display storage" {
    // Console only
    const console_only = Config.withDisplayStorage(true, false, true);
    try std.testing.expect(console_only.global_console_display);
    try std.testing.expect(!console_only.global_file_storage);
    try std.testing.expect(console_only.auto_sink);

    // File only
    const file_only = Config.withDisplayStorage(false, true, false);
    try std.testing.expect(!file_only.global_console_display);
    try std.testing.expect(file_only.global_file_storage);
    try std.testing.expect(!file_only.auto_sink);

    // Both enabled
    const both = Config.withDisplayStorage(true, true, true);
    try std.testing.expect(both.global_console_display);
    try std.testing.expect(both.global_file_storage);
}

test "rules config default values" {
    const rules_config = Config.RulesConfig{};
    try std.testing.expect(!rules_config.enabled);
    try std.testing.expect(rules_config.client_rules_enabled);
    try std.testing.expect(rules_config.builtin_rules_enabled);
    try std.testing.expect(rules_config.use_unicode);
    try std.testing.expect(rules_config.enable_colors);
    try std.testing.expect(!rules_config.show_rule_id);
    try std.testing.expect(!rules_config.include_rule_id_prefix);
    try std.testing.expect(rules_config.include_in_json);
    try std.testing.expectEqual(@as(usize, 1000), rules_config.max_rules);
    try std.testing.expectEqual(@as(usize, 10), rules_config.max_messages_per_rule);
    try std.testing.expect(rules_config.console_output);
    try std.testing.expect(rules_config.file_output);
    try std.testing.expect(!rules_config.verbose);
    try std.testing.expect(!rules_config.sort_by_severity);
}

test "rules config presets" {
    // Development preset
    const dev = Config.RulesConfig.development();
    try std.testing.expect(dev.enabled);
    try std.testing.expect(dev.use_unicode);
    try std.testing.expect(dev.enable_colors);
    try std.testing.expect(dev.show_rule_id);
    try std.testing.expect(dev.verbose);

    // Production preset
    const prod = Config.RulesConfig.production();
    try std.testing.expect(prod.enabled);
    try std.testing.expect(!prod.use_unicode);
    try std.testing.expect(!prod.enable_colors);
    try std.testing.expect(!prod.show_rule_id);
    try std.testing.expect(!prod.verbose);

    // ASCII preset
    const ascii = Config.RulesConfig.ascii();
    try std.testing.expect(ascii.enabled);
    try std.testing.expect(!ascii.use_unicode);
    try std.testing.expect(ascii.enable_colors);

    // Disabled preset
    const disabled = Config.RulesConfig.disabled();
    try std.testing.expect(!disabled.enabled);

    // Silent preset
    const silent = Config.RulesConfig.silent();
    try std.testing.expect(silent.enabled);
    try std.testing.expect(!silent.console_output);
    try std.testing.expect(!silent.file_output);

    // Console only preset
    const console_only = Config.RulesConfig.consoleOnly();
    try std.testing.expect(console_only.enabled);
    try std.testing.expect(console_only.console_output);
    try std.testing.expect(!console_only.file_output);

    // File only preset
    const file_only = Config.RulesConfig.fileOnly();
    try std.testing.expect(file_only.enabled);
    try std.testing.expect(!file_only.console_output);
    try std.testing.expect(file_only.file_output);
}

test "config with rules" {
    var config = Config.default();
    config.rules = Config.RulesConfig.development();

    try std.testing.expect(config.rules.enabled);
    try std.testing.expect(config.rules.verbose);
    try std.testing.expect(config.rules.show_rule_id);
}

test "config global switches affect rules" {
    // Test that rules config fields exist for global switch integration
    var config = Config.default();
    config.global_console_display = false;
    config.global_file_storage = false;
    config.global_color_display = false;

    // Verify rules config has corresponding fields
    try std.testing.expect(config.rules.console_output);
    try std.testing.expect(config.rules.file_output);
    try std.testing.expect(config.rules.enable_colors);

    // The actual AND logic happens in the formatter/sink at runtime
    // Here we just verify the fields exist and can be set
    config.rules.console_output = false;
    config.rules.file_output = false;
    config.rules.enable_colors = false;

    try std.testing.expect(!config.rules.console_output);
    try std.testing.expect(!config.rules.file_output);
    try std.testing.expect(!config.rules.enable_colors);
}
