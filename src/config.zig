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

    /// Thread pool configuration.
    thread_pool: ThreadPoolConfig = .{},

    /// Scheduler configuration.
    scheduler: SchedulerConfig = .{},

    /// Compression configuration.
    compression: CompressionConfig = .{},

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
};
