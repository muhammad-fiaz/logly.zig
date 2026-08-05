//! Logger Configuration Module
//!
//! Defines the Config struct that controls all aspects of the logging system.
//! Configuration can be applied at initialization or updated at runtime.
//!
//! Configuration Categories:
//! - Log Levels: Minimum level filtering
//! - Display: Colors, console output, ANSI support
//! - Output Format: JSON, text, custom patterns
//! - Time: Formats, timezones, timestamps
//! - Metadata: Hostname, PID, source location, traces
//! - Features: Sampling, rate limiting, redaction
//! - Async: Buffer sizes, thread pools, schedulers
//! - Rotation: Size/time-based file rotation
//! - Compression: Archived log compression
//!
//! Presets are available for common use cases:
//! - Config.default(): Standard development settings
//! - Config.production(): Optimized for production
//! - Config.development(): Verbose debugging
//! - Config.highThroughput(): Maximum performance
//! - Config.secure(): Security-focused logging

const std = @import("std");
const Level = @import("level.zig").Level;
const Constants = @import("constants.zig");
const ThreadPool = @import("thread_pool.zig").ThreadPool;
const Utils = @import("utils.zig");

/// Configuration options for the Logger.
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
    /// Output format settings.
    json: bool = false,
    pretty_json: bool = false,
    log_compact: bool = false,
    ndjson: bool = false,
    logfmt: bool = false,
    cef: bool = false,
    align_fields: bool = false,
    tamper_evident: bool = false,
    msgpack: bool = false,

    /// Custom format string for log messages.
    /// Available placeholders: {time}, {level}, {message}, {module}, {function}, {file}, {line},
    /// {trace_id}, {span_id}, {caller}, {thread}
    log_format: ?[]const u8 = null,

    /// Time format string - supports custom formats with any separators.
    /// Prefer `Config.TimeFormat.*` constants in application code.
    ///
    /// Predefined formats:
    ///   - "ISO8601" - ISO 8601 format (2025-12-04T06:39:53.091Z)
    ///   - "RFC3339" - RFC 3339 format (2025-12-04T06:39:53+00:00)
    ///   - "unix" - Unix timestamp in seconds
    ///   - "unix_ms" - Unix timestamp in milliseconds
    ///   - "default" - Alias for default pattern (YYYY-MM-DD HH:mm:ss.SSS)
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
    ///   - ZZZ = timezone offset with colon (+05:30)
    ///   - ZZ = compact timezone offset (+0530)
    ///
    /// Examples:
    ///   - "YYYY-MM-DD HH:mm:ss.SSS" (default)
    ///   - "YYYY/MM/DD HH:mm:ss"
    ///   - "DD-MM-YYYY HH:mm:ss"
    ///   - "MM/DD/YYYY hh:mm:ss"
    ///   - "YY.MM.DD"
    ///   - "HH:mm:ss"
    ///   - "HH:mm:ss.SSS"
    ///   - "YYYY-MM-DD HH:mm:ss ZZZ"
    ///   - "YYYY-MM-DD HH:mm:ss ZZ"
    time_format: []const u8 = Constants.TimeConstants.default_time_pattern,

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

    /// Include trace ID in logs (useful for distributed tracing).
    include_trace_id: bool = false,

    /// Capture stack traces for Error and Critical log levels.
    /// If false, stack traces will not be collected or displayed.
    capture_stack_trace: bool = false,

    /// Resolve memory addresses in stack traces to function names and file locations.
    /// Requires `capture_stack_trace` to be true (or implicit capture for Error/Critical).
    /// This provides human-readable stack traces but has a performance cost.
    symbolize_stack_trace: bool = false,

    /// Automatically flush sinks after every log operation.
    /// Creates immediate output but significantly impacts performance in high-throughput applications.
    /// Default: false (for performance). Set to true only when immediate output visibility is critical.
    auto_flush: bool = false,

    /// Automatically add a console sink on logger initialization.
    /// Only creates sink when both auto_sink=true and global_console_display=true.
    auto_sink: bool = true,

    /// Enable callback invocation for log events.
    /// Default: false (for performance). Enable only when using log callbacks.
    enable_callbacks: bool = false,

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
    stack_size: usize = Constants.ConfigDefaults.stack_size,

    /// Enable distributed tracing support.
    enable_tracing: bool = false,

    /// Trace ID header name for distributed tracing.
    trace_header: []const u8 = Constants.ConfigDefaults.distributed_trace_header,

    /// Enable metrics collection.
    enable_metrics: bool = false,

    /// Metrics configuration.
    metrics: MetricsConfig = .{},

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

    /// OpenTelemetry telemetry configuration.
    telemetry: TelemetryConfig = .{},

    /// Optional global root path for all log files.
    /// If set, file sinks will be stored relative to this path.
    /// The directory will be auto-created if it doesn't exist.
    /// If the path cannot be created, a warning is emitted but logging continues.
    logs_root_path: ?[]const u8 = null,

    /// Custom format structure configuration.
    format_structure: FormatStructureConfig = .{},

    /// Level-specific color customization.
    level_colors: LevelColorConfig = .{},

    /// Distributed systems configuration.
    distributed: DistributedConfig = .{},

    /// Highlighter and alert configuration.
    highlighters: HighlighterConfig = .{},

    /// Named time-format presets and identifiers.
    ///
    /// Use these constants instead of string literals to keep configuration
    /// values centralized and avoid typos in production code.
    pub const TimeFormat = struct {
        /// Default human-readable pattern.
        pub const default_pattern: []const u8 = Constants.TimeConstants.default_time_pattern;
        /// Alias that resolves to `default_pattern` in the formatter.
        pub const default_alias: []const u8 = "default";
        /// ISO 8601 timestamp format.
        pub const iso8601: []const u8 = "ISO8601";
        /// RFC 3339 timestamp format.
        pub const rfc3339: []const u8 = "RFC3339";
        /// Unix timestamp in seconds.
        pub const unix: []const u8 = "unix";
        /// Unix timestamp in milliseconds.
        pub const unix_ms: []const u8 = "unix_ms";
    };

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

    /// Distributed configuration for microservices and cluster environments.
    pub const DistributedConfig = struct {
        /// Enable distributed logging features.
        enabled: bool = false,

        /// Service name/Application identifier.
        service_name: ?[]const u8 = null,

        /// Service version/Semantic version of the running artifact.
        service_version: ?[]const u8 = null,

        /// Environment name (e.g., "prod", "staging", "dev").
        environment: ?[]const u8 = null,

        /// Datacenter or Availability Zone identifier (e.g., "us-east-1a").
        datacenter: ?[]const u8 = null,

        /// Region identifier (e.g., "us-east-1").
        region: ?[]const u8 = null,

        /// Unique Instance ID (e.g., Kubernetes Pod ID, EC2 Instance ID).
        instance_id: ?[]const u8 = null,

        /// HTTP header name for Trace ID propagation.
        trace_header: []const u8 = Constants.ConfigDefaults.distributed_trace_header,

        /// HTTP header name for Span ID propagation.
        span_header: []const u8 = Constants.ConfigDefaults.distributed_span_header,

        /// HTTP header name for Parent Span ID propagation.
        parent_header: []const u8 = Constants.ConfigDefaults.distributed_parent_header,

        /// HTTP header name for Baggage/Correlation Context.
        baggage_header: []const u8 = Constants.ConfigDefaults.distributed_baggage_header,

        /// Sampling rate for distributed tracing (0.0 to 1.0).
        trace_sampling_rate: f64 = 1.0,

        /// Optional callback when a new trace is initialized.
        on_trace_created: ?*const fn (trace_id: []const u8) void = null,

        /// Optional callback when a new span is started.
        on_span_created: ?*const fn (span_id: []const u8, name: []const u8) void = null,
    };

    /// Per-level color customization.
    /// Supports both theme-based presets and individual per-level color overrides.
    pub const LevelColorConfig = struct {
        /// Theme preset to use as base colors.
        /// Individual color overrides below will take precedence over theme colors.
        theme_preset: ThemePreset = .default,

        /// Custom ANSI color code for TRACE level (null = use theme default).
        /// Format: ANSI code like "36" (cyan) or "38;5;51" (256-color).
        trace_color: ?[]const u8 = null,

        /// Custom ANSI color code for DEBUG level.
        debug_color: ?[]const u8 = null,

        /// Custom ANSI color code for INFO level.
        info_color: ?[]const u8 = null,

        /// Custom ANSI color code for NOTICE level.
        notice_color: ?[]const u8 = null,

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

        /// Custom ANSI color code for FATAL level.
        fatal_color: ?[]const u8 = null,

        /// Use RGB color mode (true) instead of standard ANSI codes.
        use_rgb: bool = false,

        /// Background color support (true = color backgrounds, false = only text).
        support_background: bool = false,

        /// Reset code at end of each log (default: "\x1b[0m").
        reset_code: []const u8 = "\x1b[0m",

        /// Available theme presets.
        pub const ThemePreset = enum {
            /// Standard ANSI colors.
            default,
            /// Bold/bright color variants.
            bright,
            /// Dim color variants.
            dim,
            /// Minimal gray-scale theme.
            minimal,
            /// Vivid 256-color palette.
            neon,
            /// Soft pastel colors.
            pastel,
            /// Optimized for dark terminals.
            dark,
            /// Optimized for light terminals.
            light,
            /// No colors (plain text).
            none,
        };

        /// Get the effective color for a level, considering theme and overrides.
        pub fn getColorForLevel(self: LevelColorConfig, level: Level) []const u8 {
            // Check individual overrides first
            const override = self.getOverrideForLevel(level);
            if (override) |color| return color;

            // Fall back to theme colors
            return switch (self.theme_preset) {
                .default => level.defaultColor(),
                .bright => level.brightColor(),
                .dim => level.dimColor(),
                .minimal => switch (level) {
                    .trace, .debug => Constants.Colors.BrightFg.black,
                    .info, .notice, .success => Constants.Colors.Fg.white,
                    .warning => Constants.Colors.Fg.yellow,
                    .err, .fail => Constants.Colors.Fg.red,
                    .critical, .fatal => Constants.Colors.BrightFg.red,
                },
                .neon => level.color256(),
                .pastel => switch (level) {
                    .trace => Constants.Colors.Themes.pastel.trace,
                    .debug => Constants.Colors.Themes.pastel.debug,
                    .info => Constants.Colors.Themes.pastel.info,
                    .notice => Constants.Colors.Themes.pastel.notice,
                    .success => Constants.Colors.Themes.pastel.success,
                    .warning => Constants.Colors.Themes.pastel.warning,
                    .err => Constants.Colors.Themes.pastel.err,
                    .fail => Constants.Colors.Themes.pastel.fail,
                    .critical => Constants.Colors.Themes.pastel.critical,
                    .fatal => Constants.Colors.Themes.pastel.fatal,
                },
                .dark => switch (level) {
                    .trace => Constants.Colors.Themes.dark.trace,
                    .debug => Constants.Colors.Themes.dark.debug,
                    .info => Constants.Colors.Themes.dark.info,
                    .notice => Constants.Colors.Themes.dark.notice,
                    .success => Constants.Colors.Themes.dark.success,
                    .warning => Constants.Colors.Themes.dark.warning,
                    .err => Constants.Colors.Themes.dark.err,
                    .fail => Constants.Colors.Themes.dark.fail,
                    .critical => Constants.Colors.Themes.dark.critical,
                    .fatal => Constants.Colors.Themes.dark.fatal,
                },
                .light => switch (level) {
                    .trace => Constants.Colors.Themes.light.trace,
                    .debug => Constants.Colors.Themes.light.debug,
                    .info => Constants.Colors.Themes.light.info,
                    .notice => Constants.Colors.Themes.light.notice,
                    .success => Constants.Colors.Themes.light.success,
                    .warning => Constants.Colors.Themes.light.warning,
                    .err => Constants.Colors.Themes.light.err,
                    .fail => Constants.Colors.Themes.light.fail,
                    .critical => Constants.Colors.Themes.light.critical,
                    .fatal => Constants.Colors.Themes.light.fatal,
                },
                .none => "",
            };
        }

        /// Returns the explicit per-level color override, if one is configured.
        pub fn getOverrideForLevel(self: LevelColorConfig, level: Level) ?[]const u8 {
            return switch (level) {
                .trace => self.trace_color,
                .debug => self.debug_color,
                .info => self.info_color,
                .notice => self.notice_color,
                .success => self.success_color,
                .warning => self.warning_color,
                .err => self.error_color,
                .fail => self.fail_color,
                .critical => self.critical_color,
                .fatal => self.fatal_color,
            };
        }

        /// Returns true when a level has an explicit per-level color override.
        pub fn hasOverrideForLevel(self: LevelColorConfig, level: Level) bool {
            return self.getOverrideForLevel(level) != null;
        }

        /// Returns true when the color configuration is still using the default theme.
        pub fn usesDefaultTheme(self: LevelColorConfig) bool {
            return self.theme_preset == .default;
        }

        /// Returns true when no explicit theme or per-level override is configured.
        pub fn isDefault(self: LevelColorConfig) bool {
            return self.usesDefaultTheme() and
                self.trace_color == null and
                self.debug_color == null and
                self.info_color == null and
                self.notice_color == null and
                self.success_color == null and
                self.warning_color == null and
                self.error_color == null and
                self.fail_color == null and
                self.critical_color == null and
                self.fatal_color == null;
        }
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

    /// Sampling configuration for controlling log volume.
    ///
    /// Sampling allows reducing the volume of logs by dropping a percentage
    /// of records based on various strategies (probability, rate limiting, etc.).
    pub const SamplingConfig = struct {
        /// Enable sampling.
        enabled: bool = false,
        /// The sampling strategy to use.
        strategy: Strategy = .{ .probability = 1.0 },
        /// Defines an exclusion mask of log levels that are categorically exempt from sampling logic.
        /// Useful for guaranteeing that critical anomalies (e.g. fatal errors, panics) are deterministically logged
        /// irrespective of the active rate-limiting or probability-based suppression rules.
        bypass_levels: ?@import("level.zig").LevelMask = null,

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

            /// Token bucket rate limiting (allows initial bursts).
            token_bucket: TokenBucketConfig,
        };

        /// Configuration for rate limiting strategy.
        pub const SamplingRateLimitConfig = struct {
            /// Maximum records allowed per window.
            max_records: u32,
            /// Time window in milliseconds.
            window_ms: u64,
        };

        /// Configuration for adaptive sampling strategy.
        ///
        /// Automatically adjusts the sampling rate based on the current
        /// record throughput to maintain a target rate.
        pub const AdaptiveConfig = struct {
            /// Target records per second.
            target_rate: u32,
            /// Minimum sample rate (don't drop below this).
            min_sample_rate: f64 = Constants.SamplingDefaults.adaptive_min_rate,
            /// Maximum sample rate (don't go above this).
            max_sample_rate: f64 = Constants.SamplingDefaults.adaptive_max_rate,
            /// How often to adjust rate (milliseconds).
            adjustment_interval_ms: u64 = Constants.SamplingDefaults.adaptive_adjustment_interval_ms,
        };

        /// Configuration for token bucket rate limiting strategy.
        ///
        /// The token bucket algorithm facilitates burstable sampling operations by allowing
        /// transient spikes in log throughput while enforcing a long-term average rate limit.
        pub const TokenBucketConfig = struct {
            /// Maximum capacity of the token bucket, representing the permissible burst size.
            burst_capacity: u32,
            /// Steady-state replenishment rate for the token bucket (tokens accrued per second).
            refill_rate_per_sec: u32,
        };
    };

    /// Rate limiting configuration.
    /// Rate limiting configuration for loggers (not sampling).
    pub const RateLimitConfig = struct {
        /// Enable rate limiting.
        enabled: bool = false,
        /// Maximum requests per second.
        max_per_second: u32 = Constants.RateLimitDefaults.max_per_second,
        /// Burst size (token bucket capacity).
        burst_size: u32 = Constants.RateLimitDefaults.burst_size,
        /// Whether to apply limits per log level independently.
        per_level: bool = false,
    };

    /// Redaction configuration for sensitive data masking.
    pub const RedactionConfig = struct {
        /// Enable redaction system.
        enabled: bool = false,
        /// Fields to redact (by name).
        fields: ?[]const []const u8 = null,
        /// Patterns to redact (string patterns).
        patterns: ?[]const []const u8 = null,
        /// Default replacement text.
        replacement: []const u8 = Constants.RedactionDefaults.replacement,
        /// Default redaction type for fields.
        default_type: RedactionType = .full,
        /// Enable regex pattern matching.
        enable_regex: bool = false,
        /// Hash algorithm for hash redaction type.
        hash_algorithm: HashAlgorithm = .sha256,
        /// Characters to reveal at start for partial redaction.
        partial_start_chars: u8 = Constants.RedactionDefaults.partial_start_chars,
        /// Characters to reveal at end for partial redaction.
        partial_end_chars: u8 = Constants.RedactionDefaults.partial_end_chars,
        /// Mask character for redacted content.
        mask_char: u8 = Constants.RedactionDefaults.mask_char,
        /// Max characters to keep when using truncate redaction.
        truncate_length: usize = Constants.RedactionDefaults.truncate_length,
        /// Suffix appended when values are truncated.
        truncate_suffix: []const u8 = Constants.RedactionDefaults.truncate_suffix,
        /// Enable case-insensitive field matching.
        case_insensitive: bool = true,
        /// Log when redaction is applied (for audit).
        audit_redactions: bool = false,
        /// Compliance preset to use (null for custom).
        compliance_preset: ?CompliancePreset = null,

        /// Enum defining the method used for redacting content.
        pub const RedactionType = enum {
            /// Replaces the entire value with "[REDACTED]" or similar.
            full,
            /// Shows the start of the string, masking the rest.
            partial_start,
            /// Shows the end of the string, masking the beginning.
            partial_end,
            /// Replaces the value with a cryptographic hash.
            hash,
            /// Masks the middle part of the string (e.g. for credit cards).
            mask_middle,
            /// Truncates the string to a fixed length.
            truncate,
        };

        /// Enum determining the algorithm used for hashing redaction.
        pub const HashAlgorithm = enum {
            /// SHA-256 algorithm (secure default).
            sha256,
            /// SHA-512 algorithm (more secure, slower).
            sha512,
            /// MD5 algorithm (fast, less secure).
            md5,
        };

        /// Predefined compliance presets to automatically configure redaction rules.
        pub const CompliancePreset = enum {
            /// Payment Card Industry Data Security Standard (PCI-DSS).
            pci_dss,
            /// Health Insurance Portability and Accountability Act (HIPAA).
            hipaa,
            /// General Data Protection Regulation (GDPR).
            gdpr,
            /// Sarbanes-Oxley Act (SOX).
            sox,
            /// Custom user-defined compliance rules.
            custom,
        };

        /// Returns default redaction settings (disabled).
        ///
        /// Complexity: O(1)
        pub fn default() RedactionConfig {
            return .{};
        }

        /// Returns redaction settings compliant with PCI-DSS standards.
        /// Enables middle masking for credit cards etc.
        ///
        /// Complexity: O(1)
        pub fn pciDss() RedactionConfig {
            return .{
                .enabled = true,
                .compliance_preset = .pci_dss,
                .default_type = .mask_middle,
                .audit_redactions = true,
            };
        }

        /// Returns redaction settings compliant with HIPAA standards.
        /// Uses secure hashing (SHA-256) for identifiers.
        ///
        /// Complexity: O(1)
        pub fn hipaa() RedactionConfig {
            return .{
                .enabled = true,
                .compliance_preset = .hipaa,
                .default_type = .hash,
                .hash_algorithm = .sha256,
                .audit_redactions = true,
            };
        }

        /// Returns redaction settings compliant with GDPR.
        /// Uses partial redaction to balance utility and privacy.
        ///
        /// Complexity: O(1)
        pub fn gdpr() RedactionConfig {
            return .{
                .enabled = true,
                .compliance_preset = .gdpr,
                .default_type = .partial_end,
            };
        }

        /// Returns strict redaction settings (full redaction).
        /// Case-insensitive matching enabled.
        ///
        /// Complexity: O(1)
        pub fn strict() RedactionConfig {
            return .{
                .enabled = true,
                .default_type = .full,
                .case_insensitive = true,
                .audit_redactions = true,
            };
        }
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
        size: usize = Constants.BufferSizes.format,
        flush_interval_ms: u64 = Constants.TimeDefaults.flush_interval_ms,
        max_pending: usize = Constants.Limits.max_async_queue_size,
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
        thread_count: usize = Constants.ThreadDefaults.thread_count,
        /// Maximum queue size for pending tasks.
        queue_size: usize = Constants.ThreadDefaults.max_tasks,
        /// Stack size per thread in bytes.
        stack_size: usize = Constants.ThreadDefaults.stack_size,
        /// Enable work stealing between threads.
        work_stealing: bool = true,
        /// Thread naming prefix.
        thread_name_prefix: []const u8 = Constants.ThreadDefaults.thread_name_prefix,
        /// Keep alive time for idle threads (milliseconds).
        keep_alive_ms: u64 = Constants.TimeConstants.seconds_per_minute * Constants.TimeConstants.ms_per_second,
        /// Enable thread affinity (pin threads to CPUs).
        thread_affinity: bool = false,

        /// Returns a thread-pool configuration optimized for general use.
        pub fn default() ThreadPoolConfig {
            return .{};
        }

        /// Returns a thread-pool configuration for sustained logging throughput.
        pub fn highThroughput() ThreadPoolConfig {
            return .{
                .enabled = true,
                .thread_count = Constants.ThreadDefaults.thread_count,
                .queue_size = Constants.ThreadDefaults.max_tasks,
                .stack_size = Constants.ThreadDefaults.high_throughput_stack_size,
                .work_stealing = true,
            };
        }

        /// Returns a thread-pool configuration for disk and network-heavy logging.
        pub fn ioBound() ThreadPoolConfig {
            return .{
                .enabled = true,
                .thread_count = Constants.ThreadDefaults.ioBoundThreadCount(),
                .queue_size = Constants.ThreadDefaults.io_bound_queue_size,
                .work_stealing = true,
            };
        }

        /// Returns a thread-pool configuration for CPU-heavy formatting/compression.
        pub fn cpuBound() ThreadPoolConfig {
            return .{
                .enabled = true,
                .thread_count = Constants.ThreadDefaults.cpuBoundThreadCount(),
                .queue_size = Constants.ThreadDefaults.queue_size,
                .work_stealing = false,
            };
        }

        /// Returns a small thread-pool configuration for constrained targets.
        pub fn lowResource() ThreadPoolConfig {
            return .{
                .enabled = true,
                .thread_count = Constants.ThreadDefaults.low_latency_thread_count,
                .queue_size = Constants.ThreadDefaults.queue_size_low,
                .stack_size = Constants.ThreadDefaults.low_resource_stack_size,
                .work_stealing = false,
            };
        }

        /// Returns a copy with the worker count changed.
        pub fn withThreadCount(self: ThreadPoolConfig, count: usize) ThreadPoolConfig {
            var cfg = self;
            cfg.thread_count = count;
            cfg.enabled = true;
            return cfg;
        }

        /// Returns a copy with queue size changed.
        pub fn withQueueSize(self: ThreadPoolConfig, size: usize) ThreadPoolConfig {
            var cfg = self;
            cfg.queue_size = size;
            return cfg;
        }

        /// Alias for `withThreadCount`.
        pub const threads = withThreadCount;
        /// Alias for `withQueueSize`.
        pub const queue = withQueueSize;
    };

    /// Parallel sink writing configuration.
    pub const ParallelConfig = struct {
        /// Maximum concurrent writes allowed at once.
        max_concurrent: usize = Constants.ParallelDefaults.max_concurrent,
        /// Timeout for each write operation (ms).
        write_timeout_ms: u64 = Constants.ParallelDefaults.write_timeout_ms,
        /// Retry failed writes automatically.
        retry_on_failure: bool = true,
        /// Maximum number of retry attempts.
        max_retries: u3 = Constants.ParallelDefaults.max_retries,
        /// Fail-fast mode: abort on any sink error.
        fail_fast: bool = false,
        /// Buffer writes before parallel dispatch.
        buffered: bool = true,
        /// Buffer size for buffered writes.
        buffer_size: usize = Constants.ParallelDefaults.buffer_size,

        /// Returns default parallel configuration.
        ///
        /// Complexity: O(1)
        pub fn default() ParallelConfig {
            return .{};
        }

        /// Returns configuration optimized for high throughput.
        /// Increases concurrency and buffering, disables retries.
        ///
        /// Complexity: O(1)
        pub fn highThroughput() ParallelConfig {
            return .{
                .max_concurrent = Constants.ParallelDefaults.high_throughput_max_concurrent,
                .buffered = true,
                .buffer_size = Constants.ParallelDefaults.high_throughput_buffer_size,
                .retry_on_failure = false,
                .fail_fast = false,
            };
        }

        /// Returns configuration optimized for low latency.
        /// Low concurrency, no buffering, short timeouts.
        ///
        /// Complexity: O(1)
        pub fn lowLatency() ParallelConfig {
            return .{
                .max_concurrent = Constants.ParallelDefaults.low_latency_max_concurrent,
                .buffered = false,
                .write_timeout_ms = Constants.ParallelDefaults.low_latency_timeout_ms,
                .retry_on_failure = false,
                .fail_fast = true,
            };
        }

        /// Returns configuration optimized for reliability.
        /// Enabled retries and longer timeouts.
        ///
        /// Complexity: O(1)
        pub fn reliable() ParallelConfig {
            return .{
                .max_concurrent = Constants.ParallelDefaults.reliable_max_concurrent,
                .retry_on_failure = true,
                .max_retries = Constants.ParallelDefaults.reliable_max_retries,
                .write_timeout_ms = Constants.ParallelDefaults.reliable_timeout_ms,
                .fail_fast = false,
            };
        }
    };

    /// Scheduler configuration.
    pub const SchedulerConfig = struct {
        /// Enable the scheduler.
        enabled: bool = false,
        /// Default cleanup max age in days.
        cleanup_max_age_days: u64 = Constants.SchedulerDefaults.max_age_seconds / Constants.TimeConstants.seconds_per_day,
        /// Default max files to keep.
        max_files: ?usize = null,
        /// Enable compression before cleanup.
        compress_before_cleanup: bool = false,
        /// Default file pattern for cleanup.
        file_pattern: []const u8 = "*.log",
        /// Root directory for compressed/archived files.
        archive_root_dir: ?[]const u8 = null,
        /// Create date-based subdirectories (YYYY/MM/DD).
        create_date_subdirs: bool = false,
        /// Compression algorithm for scheduled compression tasks.
        compression_algorithm: CompressionConfig.CompressionAlgorithm = .gzip,
        /// Compression level for scheduled tasks.
        compression_level: CompressionConfig.CompressionLevel = .default,
        /// Keep original files after scheduled compression.
        keep_originals: bool = false,
        /// Custom prefix for archived file names.
        archive_file_prefix: ?[]const u8 = null,
        /// Custom suffix for archived file names.
        archive_file_suffix: ?[]const u8 = null,
        /// Preserve directory structure in archive root.
        preserve_dir_structure: bool = true,
        /// Delete empty directories after cleanup.
        clean_empty_dirs: bool = false,
        /// Minimum file age in days before compression.
        min_age_days_for_compression: u64 = 1,
        /// Maximum concurrent compression tasks.
        max_concurrent_compressions: usize = 2,

        /// Returns scheduler settings for routine log maintenance.
        pub fn maintenance(logs_path: []const u8) SchedulerConfig {
            return .{
                .enabled = true,
                .file_pattern = "*.log",
                .archive_root_dir = logs_path,
                .compress_before_cleanup = true,
                .clean_empty_dirs = true,
            };
        }

        /// Returns a copy configured for cleanup after `days`.
        pub fn withCleanupDays(self: SchedulerConfig, days: u64) SchedulerConfig {
            var cfg = self;
            cfg.enabled = true;
            cfg.cleanup_max_age_days = days;
            return cfg;
        }

        /// Returns a copy configured to keep at most `count` files.
        pub fn withMaxFiles(self: SchedulerConfig, count: usize) SchedulerConfig {
            var cfg = self;
            cfg.enabled = true;
            cfg.max_files = count;
            return cfg;
        }

        /// Returns a copy with scheduled compression enabled.
        pub fn withCompression(self: SchedulerConfig, algorithm: CompressionConfig.CompressionAlgorithm) SchedulerConfig {
            var cfg = self;
            cfg.enabled = true;
            cfg.compress_before_cleanup = true;
            cfg.compression_algorithm = algorithm;
            return cfg;
        }

        /// Alias for `withCleanupDays`.
        pub const cleanupDays = withCleanupDays;
        /// Alias for `withMaxFiles`.
        pub const retainFiles = withMaxFiles;
        /// Alias for `withCompression`.
        pub const compressBeforeCleanup = SchedulerConfig.withCompression;
    };

    /// Metrics collection configuration.
    pub const MetricsConfig = struct {
        /// Enable metrics collection.
        enabled: bool = false,
        /// Track per-level counts.
        track_levels: bool = true,
        /// Track per-sink metrics.
        track_sinks: bool = true,
        /// Calculate throughput (records/sec, bytes/sec).
        track_throughput: bool = true,
        /// Track latency statistics.
        track_latency: bool = false,
        /// Snapshot interval in milliseconds (0 = disabled).
        snapshot_interval_ms: u64 = 0,
        /// Alert threshold for error rate (0.0-1.0, 0 = disabled).
        error_rate_threshold: f32 = 0.0,
        /// Alert threshold for drop rate (0.0-1.0, 0 = disabled).
        drop_rate_threshold: f32 = 0.0,
        /// Maximum records/sec before alerting (0 = disabled).
        max_records_per_second: u64 = 0,
        /// Export format for metrics.
        export_format: ExportFormat = .text,
        /// Enable histogram for latency distribution.
        enable_histogram: bool = false,
        /// Number of histogram buckets.
        histogram_buckets: u8 = 10,
        /// Retain metrics history (in snapshots).
        history_size: u16 = 0,
        /// Prefix/namespace used by exported metric names.
        metric_prefix: []const u8 = Constants.MetricsConstants.default_prefix,
        /// Separator used when joining metric prefix and metric name.
        metric_separator: []const u8 = Constants.MetricsConstants.prometheus_separator,
        /// Separator used by StatsD exports.
        statsd_separator: []const u8 = Constants.MetricsConstants.statsd_separator,
        /// Sanitize exported metric names for the target exporter.
        sanitize_names: bool = Constants.MetricsConstants.sanitize_names,
        /// Include per-level counters in metrics exports.
        export_level_breakdown: bool = Constants.MetricsConstants.include_level_breakdown,
        /// Include per-sink counters in metrics exports.
        export_sink_breakdown: bool = Constants.MetricsConstants.include_sink_breakdown,

        pub const ExportFormat = enum {
            text,
            json,
            prometheus,
            statsd,
        };

        /// Returns default metrics configuration (disabled).
        ///
        /// Complexity: O(1)
        pub fn default() MetricsConfig {
            return .{};
        }

        /// Returns metrics configuration suitable for production monitoring.
        /// Tracks throughput, levels, and sinks with specific error thresholds.
        ///
        /// Complexity: O(1)
        pub fn production() MetricsConfig {
            return .{
                .enabled = true,
                .track_levels = true,
                .track_sinks = true,
                .track_throughput = true,
                .error_rate_threshold = 0.01,
                .drop_rate_threshold = 0.001,
            };
        }

        /// Returns minimal metrics configuration.
        /// Enables system but disables per-level/sink tracking to save memory.
        ///
        /// Complexity: O(1)
        pub fn minimal() MetricsConfig {
            return .{
                .enabled = true,
                .track_levels = false,
                .track_sinks = false,
                .track_throughput = false,
            };
        }

        /// Returns detailed metrics configuration for debugging/profiling.
        /// Enables latency tracking, histograms, and history retention.
        ///
        /// Complexity: O(1)
        pub fn detailed() MetricsConfig {
            return .{
                .enabled = true,
                .track_levels = true,
                .track_sinks = true,
                .track_throughput = true,
                .track_latency = true,
                .enable_histogram = true,
                .histogram_buckets = 20,
                .history_size = 60,
            };
        }

        /// Returns a copy configured for a specific export format.
        pub fn withExport(self: MetricsConfig, format: ExportFormat) MetricsConfig {
            var cfg = self;
            cfg.enabled = true;
            cfg.export_format = format;
            return cfg;
        }

        /// Returns a copy configured for Prometheus export naming.
        pub fn prometheus(self: MetricsConfig) MetricsConfig {
            var cfg = self.withExport(.prometheus);
            cfg.metric_separator = Constants.MetricsConstants.prometheus_separator;
            cfg.sanitize_names = true;
            return cfg;
        }

        /// Returns a copy configured for StatsD export naming.
        pub fn statsd(self: MetricsConfig) MetricsConfig {
            var cfg = self.withExport(.statsd);
            cfg.metric_separator = cfg.statsd_separator;
            cfg.sanitize_names = false;
            return cfg;
        }

        /// Returns a copy with an exported metric prefix/namespace.
        pub fn withPrefix(self: MetricsConfig, metric_prefix_value: []const u8) MetricsConfig {
            var cfg = self;
            cfg.metric_prefix = metric_prefix_value;
            return cfg;
        }

        /// Returns a copy with latency histograms enabled.
        pub fn withLatencyHistogram(self: MetricsConfig, buckets: u8) MetricsConfig {
            var cfg = self;
            cfg.enabled = true;
            cfg.track_latency = true;
            cfg.enable_histogram = true;
            cfg.histogram_buckets = buckets;
            return cfg;
        }

        /// Returns a copy with error/drop alert thresholds.
        pub fn withAlerts(self: MetricsConfig, error_rate: f32, drop_rate: f32) MetricsConfig {
            var cfg = self;
            cfg.enabled = true;
            cfg.error_rate_threshold = error_rate;
            cfg.drop_rate_threshold = drop_rate;
            return cfg;
        }

        /// Returns a copy with level/sink export breakdowns enabled or disabled.
        pub fn withBreakdowns(self: MetricsConfig, levels: bool, sinks: bool) MetricsConfig {
            var cfg = self;
            cfg.export_level_breakdown = levels;
            cfg.export_sink_breakdown = sinks;
            return cfg;
        }

        /// Alias for `withExport`.
        pub const exportAs = withExport;
        /// Alias for `withPrefix`.
        pub const prefix = withPrefix;
        /// Alias for `withLatencyHistogram`.
        pub const histogram = withLatencyHistogram;
        /// Alias for `withAlerts`.
        pub const alerts = withAlerts;
        /// Alias for `withBreakdowns`.
        pub const breakdowns = withBreakdowns;
    };

    /// Compression configuration.
    pub const CompressionConfig = struct {
        /// Enable compression.
        enabled: bool = false,
        /// Compression algorithm.
        algorithm: CompressionAlgorithm = .deflate,
        /// Compression level.
        level: CompressionLevel = .default,
        /// Custom zstd level (1-22). If set, overrides the level enum for zstd.
        /// Use this for fine-grained control over zstd compression levels.
        /// v0.1.5+
        custom_zstd_level: ?i32 = null,
        /// Custom Brotli level (0-11). If set, overrides the level enum for Brotli.
        /// Use this for fine-grained control over Brotli compression levels.
        /// v0.2.1+
        custom_brotli_level: ?i32 = null,
        /// Compress on rotation.
        on_rotation: bool = true,
        /// Keep original file after compression.
        keep_original: bool = false,
        /// Compression mode.
        mode: Mode = .on_rotation,
        /// Size threshold in bytes for on_size_threshold mode.
        size_threshold: u64 = Constants.RotationConstants.default_max_size,
        /// Buffer size for streaming compression.
        buffer_size: usize = Constants.BufferSizes.compression,
        /// Compression strategy.
        strategy: Strategy = .default,
        /// File extension for compressed files.
        extension: []const u8 = Constants.RotationConstants.compressed_ext,
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
        /// Custom prefix for compressed file names (e.g., "archive_" -> "archive_app.log.gz").
        file_prefix: ?[]const u8 = null,
        /// Custom suffix before extension (e.g., "_compressed" -> "app_compressed.log.gz").
        file_suffix: ?[]const u8 = null,
        /// Root directory for all compressed files (centralized archive location).
        /// If set, all compressed files will be stored here instead of alongside originals.
        archive_root_dir: ?[]const u8 = null,
        /// Create date-based subdirectories in archive root (YYYY/MM/DD structure).
        create_date_subdirs: bool = false,
        /// Preserve original directory structure when archiving to root dir.
        preserve_dir_structure: bool = true,
        /// Custom naming pattern for compressed files.
        /// Placeholders: {base}, {ext}, {date}, {time}, {timestamp}, {index}
        naming_pattern: ?[]const u8 = null,
        /// Zstd dictionary for compression.
        zstd_dict: ?[]const u8 = null,
        /// Thread pool for asynchronous compression tasks.
        thread_pool: ?*ThreadPool = null,

        pub const CompressionAlgorithm = enum {
            none,
            deflate,
            zlib,
            raw_deflate,
            gzip,
            /// Zstandard (zstd) - Fast, high-ratio compression algorithm
            /// Provides excellent compression ratios with very fast decompression.
            /// Supports compression levels 1-22 (negative levels for faster compression).
            /// v0.1.5+
            zstd,
            /// LZMA - Lempel-Ziv-Markov chain algorithm
            lzma,
            /// LZMA2 - Improved LZMA with better multi-threading support
            lzma2,
            /// XZ - Container format using LZMA2 compression
            xz,
            /// TAR.GZ - Tar archive compressed with gzip
            tar_gz,
            /// ZIP - Popular archive format
            zip,
            /// LZ4 - Extremely fast compression/decompression
            lz4,
            /// Brotli - Google's compression algorithm, excellent for text/log data
            /// Provides very good compression ratios, especially for UTF-8 text.
            /// Supports quality levels 0-11 (default 6, best 11).
            /// v0.2.1+
            brotli,
        };

        pub const CompressionLevel = enum {
            none,
            fastest,
            fast,
            default,
            best,

            /// Converts the enum to its corresponding zlib/deflate compression integer level (0-9).
            /// For zstd, use toZstdLevel() instead.
            ///
            /// Returns:
            /// - u4 integer representation.
            ///
            /// Complexity: O(1)
            pub fn toInt(self: CompressionLevel) u4 {
                return switch (self) {
                    .none => 0,
                    .fastest => 1,
                    .fast => 3,
                    .default => 6,
                    .best => 9,
                };
            }

            /// Converts the enum to its corresponding zstd compression integer level (1-22).
            /// Zstd supports levels 1-22, with higher levels providing better compression
            /// at the cost of speed. Levels >= 20 are "ultra" and require more memory.
            ///
            /// Returns:
            /// - i32 integer representation for zstd (1-22).
            ///
            /// Complexity: O(1)
            /// v0.1.5+
            pub fn toZstdLevel(self: CompressionLevel) i32 {
                return switch (self) {
                    .none => 0,
                    .fastest => 1, // Fastest zstd compression
                    .fast => 3, // Fast compression, good ratio
                    .default => 6, // Balanced (zstd default is 3, we use 6 for better ratio)
                    .best => 19, // High compression (below ultra threshold)
                };
            }

            /// Converts the enum to its corresponding Brotli compression integer level (0-11).
            /// Brotli supports levels 0-11, with higher levels providing better compression
            /// at the cost of speed. Level 0 is fastest, 11 is best compression.
            ///
            /// Returns:
            /// - i32 integer representation for Brotli (0-11).
            ///
            /// Complexity: O(1)
            /// v0.2.1+
            pub fn toBrotliLevel(self: CompressionLevel) i32 {
                return switch (self) {
                    .none => 0,
                    .fastest => 1, // Fastest brotli compression
                    .fast => 4, // Fast compression
                    .default => 6, // Balanced (Brotli default is 6)
                    .best => 11, // Maximum compression
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

        /// Returns a minimal compression config with compression enabled.
        /// Use this for the simplest one-liner compression setup.
        ///
        /// Example:
        /// ```zig
        /// const config = Config.default().withCompression(CompressionConfig.enable());
        /// ```
        ///
        /// Complexity: O(1)
        pub fn enable() CompressionConfig {
            return .{ .enabled = true };
        }

        /// Alias for enable(). Returns a minimal compression config with compression enabled.
        ///
        /// Example:
        /// ```zig
        /// const config = Config.default().withCompression(CompressionConfig.basic());
        /// ```
        ///
        /// Complexity: O(1)
        pub fn basic() CompressionConfig {
            return enable();
        }

        /// Returns an implicit compression config (automatic compression on rotation).
        /// The library automatically compresses files during rotation - no manual intervention needed.
        ///
        /// Example:
        /// ```zig
        /// const config = Config.default().withCompression(CompressionConfig.implicit());
        /// ```
        ///
        /// Complexity: O(1)
        pub fn implicit() CompressionConfig {
            return .{
                .enabled = true,
                .mode = .on_rotation,
                .on_rotation = true,
                .background = false,
            };
        }

        /// Returns an explicit compression config (manual compression control).
        /// Use compressFile() and compressDirectory() for user-controlled compression.
        /// Disables automatic rotation-based compression.
        ///
        /// Example:
        /// ```zig
        /// const config = Config.default().withCompression(CompressionConfig.explicit());
        /// // Then manually: compression.compressFile("logs/app.log", null);
        /// ```
        ///
        /// Complexity: O(1)
        pub fn explicit() CompressionConfig {
            return .{
                .enabled = true,
                .mode = .disabled,
                .on_rotation = false,
            };
        }

        /// Returns a streaming compression config.
        /// Compresses data as it's written - useful for real-time compression.
        ///
        /// Example:
        /// ```zig
        /// const config = Config.default().withCompression(CompressionConfig.streaming());
        /// ```
        ///
        /// Complexity: O(1)
        pub fn streamingMode() CompressionConfig {
            return .{
                .enabled = true,
                .mode = .streaming,
                .streaming = true,
                .on_rotation = false,
            };
        }

        /// Returns a background compression config.
        /// Compression runs in a separate thread for non-blocking operation.
        ///
        /// Example:
        /// ```zig
        /// const config = Config.default().withCompression(CompressionConfig.background());
        /// ```
        ///
        /// Complexity: O(1)
        pub fn backgroundMode() CompressionConfig {
            return .{
                .enabled = true,
                .background = true,
                .on_rotation = true,
            };
        }

        /// Returns a fast compression config (prioritize speed over ratio).
        ///
        /// Example:
        /// ```zig
        /// const config = Config.default().withCompression(CompressionConfig.fast());
        /// ```
        ///
        /// Complexity: O(1)
        pub fn fast() CompressionConfig {
            return .{
                .enabled = true,
                .level = .fastest,
                .algorithm = .deflate,
            };
        }

        /// Returns a balanced compression config (default speed/ratio tradeoff).
        ///
        /// Example:
        /// ```zig
        /// const config = Config.default().withCompression(CompressionConfig.balanced());
        /// ```
        ///
        /// Complexity: O(1)
        pub fn balanced() CompressionConfig {
            return .{
                .enabled = true,
                .level = .default,
                .algorithm = .deflate,
            };
        }

        /// Returns a best compression config (prioritize ratio over speed).
        ///
        /// Example:
        /// ```zig
        /// const config = Config.default().withCompression(CompressionConfig.best());
        /// ```
        ///
        /// Complexity: O(1)
        pub fn best() CompressionConfig {
            return .{
                .enabled = true,
                .level = .best,
                .algorithm = .gzip,
            };
        }

        /// Returns a compression config optimized for text/log files.
        ///
        /// Example:
        /// ```zig
        /// const config = Config.default().withCompression(CompressionConfig.forLogs());
        /// ```
        ///
        /// Complexity: O(1)
        pub fn forLogs() CompressionConfig {
            return .{
                .enabled = true,
                .level = .default,
                .algorithm = .gzip,
                .strategy = .text,
                .on_rotation = true,
            };
        }

        /// Returns a compression config with archival settings (compress + delete original).
        ///
        /// Example:
        /// ```zig
        /// const config = Config.default().withCompression(CompressionConfig.archive());
        /// ```
        ///
        /// Complexity: O(1)
        pub fn archive() CompressionConfig {
            return .{
                .enabled = true,
                .level = .best,
                .algorithm = .gzip,
                .keep_original = false,
                .on_rotation = true,
            };
        }

        /// Returns a compression config that keeps originals after compression.
        ///
        /// Example:
        /// ```zig
        /// const config = Config.default().withCompression(CompressionConfig.keepOriginals());
        /// ```
        ///
        /// Complexity: O(1)
        pub fn keepOriginals() CompressionConfig {
            return .{
                .enabled = true,
                .keep_original = true,
                .on_rotation = true,
            };
        }

        /// Returns a compression config with size-threshold trigger.
        /// Compresses files when they exceed the specified size.
        ///
        /// Arguments:
        ///   - `threshold_bytes`: Size in bytes that triggers compression.
        ///
        /// Example:
        /// ```zig
        /// const config = Config.default().withCompression(CompressionConfig.onSize(5 * 1024 * 1024)); // 5MB
        /// ```
        ///
        /// Complexity: O(1)
        pub fn onSize(threshold_bytes: u64) CompressionConfig {
            return .{
                .enabled = true,
                .mode = .on_size_threshold,
                .size_threshold = threshold_bytes,
                .on_rotation = false,
            };
        }

        /// Returns a production-ready compression config.
        /// Balanced performance with background processing and checksums.
        ///
        /// Example:
        /// ```zig
        /// const config = Config.default().withCompression(CompressionConfig.production());
        /// ```
        ///
        /// Complexity: O(1)
        pub fn production() CompressionConfig {
            return .{
                .enabled = true,
                .level = .default,
                .algorithm = .gzip,
                .background = true,
                .checksum = true,
                .on_rotation = true,
                .keep_original = false,
            };
        }

        /// Returns a zstd compression config with default settings.
        /// Zstd provides excellent compression ratios with very fast decompression.
        /// Uses balanced compression level (6) for good ratio/speed tradeoff.
        ///
        /// Example:
        /// ```zig
        /// const config = Config.default().withCompression(CompressionConfig.zstd());
        /// ```
        ///
        /// Complexity: O(1)
        /// v0.1.5+
        pub fn zstd() CompressionConfig {
            return .{
                .enabled = true,
                .level = .default,
                .algorithm = .zstd,
                .on_rotation = true,
                .checksum = true,
                .extension = Constants.CompressionConstants.ArchivingExtensions.zstd,
            };
        }

        /// Returns a fast zstd compression config.
        /// Prioritizes compression speed over ratio. Great for real-time logging.
        ///
        /// Example:
        /// ```zig
        /// const config = Config.default().withCompression(CompressionConfig.zstdFast());
        /// ```
        ///
        /// Complexity: O(1)
        /// v0.1.5+
        pub fn zstdFast() CompressionConfig {
            return .{
                .enabled = true,
                .level = .fastest,
                .algorithm = .zstd,
                .on_rotation = true,
                .extension = Constants.CompressionConstants.ArchivingExtensions.zstd,
            };
        }

        /// Returns a high-ratio zstd compression config.
        /// Prioritizes compression ratio over speed. Great for archival.
        ///
        /// Example:
        /// ```zig
        /// const config = Config.default().withCompression(CompressionConfig.zstdBest());
        /// ```
        ///
        /// Complexity: O(1)
        /// v0.1.5+
        pub fn zstdBest() CompressionConfig {
            return .{
                .enabled = true,
                .level = .best,
                .algorithm = .zstd,
                .on_rotation = true,
                .checksum = true,
                .keep_original = false,
                .extension = Constants.CompressionConstants.ArchivingExtensions.zstd,
            };
        }

        /// Returns a production-ready zstd compression config.
        /// Background processing with checksums for reliability.
        ///
        /// Example:
        /// ```zig
        /// const config = Config.default().withCompression(CompressionConfig.zstdProduction());
        /// ```
        ///
        /// Complexity: O(1)
        /// v0.1.5+
        pub fn zstdProduction() CompressionConfig {
            return .{
                .enabled = true,
                .level = .default,
                .algorithm = .zstd,
                .background = true,
                .checksum = true,
                .on_rotation = true,
                .keep_original = false,
                .extension = Constants.CompressionConstants.ArchivingExtensions.zstd,
            };
        }

        /// Returns a zstd compression config with a custom compression level.
        /// Allows fine-grained control over zstd compression (levels 1-22).
        /// Higher levels provide better compression but slower speed.
        ///
        /// Arguments:
        ///     custom_level: Zstd compression level (1-22, clamped to valid range).
        ///
        /// Example:
        /// ```zig
        /// const config = Config.default().withCompression(CompressionConfig.zstdWithLevel(12));
        /// ```
        ///
        /// Complexity: O(1)
        /// v0.1.5+
        pub fn zstdWithLevel(custom_level: i32) CompressionConfig {
            // Clamp to valid zstd range (1-22)
            const clamped_level = std.math.clamp(custom_level, 1, 22);
            return .{
                .enabled = true,
                .level = .default,
                .custom_zstd_level = clamped_level,
                .algorithm = .zstd,
                .on_rotation = true,
                .checksum = true,
                .extension = Constants.CompressionConstants.ArchivingExtensions.zstd,
            };
        }

        /// Alias for zstd(). Returns a zstd compression config with default settings.
        /// v0.1.5+
        pub const zstdDefault = zstd;

        /// Alias for zstdFast(). Returns a fast zstd compression config.
        /// v0.1.5+
        pub const zstdSpeed = zstdFast;

        /// Alias for zstdBest(). Returns a high-ratio zstd compression config.
        /// v0.1.5+
        pub const zstdMax = zstdBest;

        /// Returns an lzma compression config.
        /// v0.1.6+
        pub fn lzma() CompressionConfig {
            return .{
                .enabled = true,
                .algorithm = .lzma,
                .extension = Constants.CompressionConstants.ArchivingExtensions.lzma,
            };
        }

        /// Returns an lzma2 compression config.
        /// v0.1.6+
        pub fn lzma2() CompressionConfig {
            return .{
                .enabled = true,
                .algorithm = .lzma2,
                .extension = Constants.CompressionConstants.ArchivingExtensions.lzma2,
            };
        }

        /// Returns an xz compression config.
        /// v0.1.6+
        pub fn xz() CompressionConfig {
            return .{
                .enabled = true,
                .algorithm = .xz,
                .extension = Constants.CompressionConstants.ArchivingExtensions.xz,
            };
        }

        /// Returns a tar.gz compression config.
        /// v0.1.6+
        pub fn tarGz() CompressionConfig {
            return .{
                .enabled = true,
                .algorithm = .tar_gz,
                .extension = Constants.CompressionConstants.ArchivingExtensions.tar_gz,
            };
        }

        /// Returns a zip compression config.
        /// v0.1.6+
        pub fn zip() CompressionConfig {
            return .{
                .enabled = true,
                .algorithm = .zip,
                .extension = Constants.CompressionConstants.ArchivingExtensions.zip,
            };
        }

        /// Returns an lz4 compression config.
        /// v0.1.6+
        pub fn lz4() CompressionConfig {
            return .{
                .enabled = true,
                .algorithm = .lz4,
                .extension = Constants.CompressionConstants.ArchivingExtensions.lz4,
            };
        }

        /// Returns a Brotli compression config.
        /// Brotli provides excellent compression ratios, especially for UTF-8 text.
        /// Supports quality levels 0-11 (default 6, best 11).
        /// v0.2.1+
        pub fn brotli() CompressionConfig {
            return .{
                .enabled = true,
                .algorithm = .brotli,
                .extension = Constants.CompressionConstants.ArchivingExtensions.brotli,
            };
        }

        /// Returns the effective Brotli compression level.
        /// If custom_brotli_level is set, uses that; otherwise maps from level enum.
        ///
        /// Returns:
        ///     - i32 Brotli compression level (0-11).
        ///
        /// Complexity: O(1)
        /// v0.2.1+
        pub fn getEffectiveBrotliLevel(self: *const CompressionConfig) i32 {
            if (self.custom_brotli_level) |custom| {
                return custom;
            }
            return self.level.toBrotliLevel();
        }

        /// Returns the effective zstd compression level.
        /// If custom_zstd_level is set, uses that; otherwise maps from level enum.
        ///
        /// Arguments:
        ///     self: Pointer to the compression config.
        ///
        /// Returns:
        ///     - i32 zstd compression level.
        ///
        /// Complexity: O(1)
        /// v0.1.5+
        pub fn getEffectiveZstdLevel(self: *const CompressionConfig) i32 {
            if (self.custom_zstd_level) |custom| {
                return custom;
            }
            return self.level.toZstdLevel();
        }

        /// Returns a development compression config.
        /// Fast compression with originals kept for debugging.
        ///
        /// Example:
        /// ```zig
        /// const config = Config.default().withCompression(CompressionConfig.development());
        /// ```
        ///
        /// Complexity: O(1)
        pub fn development() CompressionConfig {
            return .{
                .enabled = true,
                .level = .fastest,
                .algorithm = .deflate,
                .keep_original = true,
                .checksum = true,
            };
        }

        /// Returns a disabled compression config.
        ///
        /// Example:
        /// ```zig
        /// const config = Config.default().withCompression(CompressionConfig.disable());
        /// ```
        ///
        /// Complexity: O(1)
        pub fn disable() CompressionConfig {
            return .{ .enabled = false };
        }
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

        /// Maximum total size of all rotated files in bytes.
        /// Oldest rotated files will be deleted when total size exceeds this.
        max_total_size: ?u64 = null,

        /// Maximum total size as a string (e.g. "100MB").
        max_total_size_str: ?[]const u8 = null,

        /// Custom rotation callback.
        on_rotate: ?*const fn (old_path: []const u8, new_path: []const u8) void = null,

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

        /// Keep original file after compression (default: false - delete original).
        keep_original: bool = false,

        /// Compress files during retention cleanup instead of deleting them.
        /// When true, old files exceeding retention limits are compressed rather than deleted.
        compress_on_retention: bool = false,

        /// Delete files after compression during retention (only applies when compress_on_retention is true).
        /// When false, compressed files are kept; when true, originals are deleted after compression.
        delete_after_retention_compress: bool = true,
        /// Root directory for all rotated/compressed files (centralized archive).
        archive_root_dir: ?[]const u8 = null,
        /// Create date-based subdirectories in archive (YYYY/MM/DD structure).
        create_date_subdirs: bool = false,
        /// Custom prefix for rotated file names.
        file_prefix: ?[]const u8 = null,
        /// Custom suffix for rotated file names (before extension).
        file_suffix: ?[]const u8 = null,
        /// Compression algorithm for rotation.
        compression_algorithm: CompressionConfig.CompressionAlgorithm = .gzip,
        /// Compression level for rotation.
        compression_level: CompressionConfig.CompressionLevel = .default,

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

        /// Returns a size-based rotation configuration.
        pub fn bySize(size_bytes: u64, retention: usize) RotationConfig {
            return .{
                .enabled = true,
                .size_limit = size_bytes,
                .retention_count = retention,
            };
        }

        /// Returns a size-based rotation configuration parsed from a size string (e.g. "10MB").
        pub fn fromSize(size_str: []const u8) RotationConfig {
            return .{
                .enabled = true,
                .size_limit_str = size_str,
            };
        }

        /// Returns a time-based rotation configuration.
        pub fn byInterval(interval_name: []const u8, retention: usize) RotationConfig {
            return .{
                .enabled = true,
                .interval = interval_name,
                .retention_count = retention,
            };
        }

        /// Returns a time-based rotation configuration parsed from an interval name or duration string (e.g. "24h").
        pub fn fromInterval(dur_str: []const u8) RotationConfig {
            return .{
                .enabled = true,
                .interval = dur_str,
            };
        }

        /// Returns a daily rotation configuration.
        pub fn daily(retention_days: usize) RotationConfig {
            return byInterval("daily", retention_days);
        }

        /// Returns a copy with compression enabled for rotated files.
        pub fn withCompression(self: RotationConfig, algorithm: CompressionConfig.CompressionAlgorithm) RotationConfig {
            var cfg = self;
            cfg.enabled = true;
            cfg.compression_algorithm = algorithm;
            cfg.compress_on_retention = true;
            return cfg;
        }

        /// Returns a copy with archive directory controls configured.
        pub fn withArchive(self: RotationConfig, dir: []const u8, date_subdirs: bool) RotationConfig {
            var cfg = self;
            cfg.enabled = true;
            cfg.archive_dir = dir;
            cfg.archive_root_dir = dir;
            cfg.create_date_subdirs = date_subdirs;
            return cfg;
        }

        /// Alias for `bySize`.
        pub const size = bySize;
        /// Alias for `byInterval`.
        pub const intervalRotation = byInterval;
        /// Alias for `withArchive`.
        pub const archiveTo = withArchive;
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
        indent: []const u8 = Constants.InvokeConstants.default_indent,

        /// Message prefix character/string (deprecated, use symbols).
        message_prefix: []const u8 = Constants.InvokeConstants.default_prefix,

        /// Include rule messages in JSON output.
        include_in_json: bool = true,

        /// Maximum number of rules allowed.
        max_rules: usize = Constants.InvokeConstants.default_max_rules,

        /// Maximum messages per rule to display.
        max_messages_per_rule: usize = Constants.InvokeConstants.default_max_messages,

        /// Display rule messages on console (respects global_console_display).
        console_output: bool = true,

        /// Write rule messages to file sinks (respects global_file_storage).
        file_output: bool = true,

        /// Enable verbose mode with full context.
        verbose: bool = false,

        /// Sort messages by severity.
        sort_by_severity: bool = false,

        /// Preset configurations for various environments.
        /// Returns minimal rule configuration.
        /// Enables rules with basic settings.
        ///
        /// Complexity: O(1)
        pub fn minimal() RulesConfig {
            return .{ .enabled = true, .use_unicode = true, .enable_colors = true };
        }

        /// Returns production rule configuration.
        /// No colors, no verbose output, minimal overhead.
        ///
        /// Complexity: O(1)
        pub fn production() RulesConfig {
            return .{
                .enabled = true,
                .use_unicode = false,
                .enable_colors = false,
                .show_rule_id = false,
                .verbose = false,
            };
        }

        /// Returns development rule configuration.
        /// Full debugging info, colors, Unicode support, and verbose output.
        ///
        /// Complexity: O(1)
        pub fn development() RulesConfig {
            return .{
                .enabled = true,
                .use_unicode = true,
                .enable_colors = true,
                .show_rule_id = true,
                .verbose = true,
            };
        }

        /// Returns ASCII-only rule configuration.
        /// Useful for legacy terminals or environments without Unicode support.
        ///
        /// Complexity: O(1)
        pub fn ascii() RulesConfig {
            return .{ .enabled = true, .use_unicode = false, .enable_colors = true };
        }

        /// Returns disabled rule configuration.
        /// Zero overhead as rules system is bypassed.
        ///
        /// Complexity: O(1)
        pub fn disabled() RulesConfig {
            return .{ .enabled = false };
        }

        /// Returns silent rule configuration.
        /// Rules are evaluated but no output is generated (silent evaluation).
        ///
        /// Complexity: O(1)
        pub fn silent() RulesConfig {
            return .{ .enabled = true, .console_output = false, .file_output = false };
        }

        /// Returns console-only rule configuration.
        ///
        /// Complexity: O(1)
        pub fn consoleOnly() RulesConfig {
            return .{ .enabled = true, .console_output = true, .file_output = false };
        }

        /// Returns file-only rule configuration.
        ///
        /// Complexity: O(1)
        pub fn fileOnly() RulesConfig {
            return .{ .enabled = true, .console_output = false, .file_output = true };
        }
    };

    /// Async logging configuration.
    pub const AsyncConfig = struct {
        /// Enable async logging.
        enabled: bool = false,
        /// Buffer size for async queue.
        buffer_size: usize = Constants.BufferSizes.async_queue,
        /// Batch size for flushing.
        batch_size: usize = Constants.AsyncConstants.batch_size,
        /// Flush interval in milliseconds.
        flush_interval_ms: u64 = Constants.TimeDefaults.retry_delay_ms,
        /// Minimum time between flushes to avoid thrashing.
        min_flush_interval_ms: u64 = 0,
        /// Maximum latency before forcing a flush.
        max_latency_ms: u64 = Constants.TimeDefaults.write_timeout_ms,
        /// What to do when buffer is full.
        overflow_policy: OverflowPolicy = .drop_oldest,
        /// Auto-start worker thread.
        background_worker: bool = true,
        /// Queue utilization ratio that records a backpressure event.
        backpressure_threshold: f64 = Constants.AsyncConstants.backpressure_threshold_ratio,
        /// Default timeout for explicit drain waits.
        drain_timeout_ms: u64 = Constants.AsyncConstants.drain_timeout_ms,
        /// Shutdown grace period timeout in milliseconds.
        shutdown_timeout_ms: u64 = Constants.AsyncConstants.drain_timeout_ms,

        pub const OverflowPolicy = enum {
            drop_oldest,
            drop_newest,
            block,
        };

        /// Returns async settings for high-throughput buffered logging.
        pub fn highThroughput() AsyncConfig {
            return .{
                .enabled = true,
                .buffer_size = Constants.AsyncPresetDefaults.high_throughput_buffer_size,
                .batch_size = Constants.AsyncPresetDefaults.high_throughput_batch_size,
                .flush_interval_ms = Constants.AsyncPresetDefaults.high_throughput_flush_interval_ms,
                .min_flush_interval_ms = Constants.AsyncPresetDefaults.high_throughput_min_flush_interval_ms,
                .max_latency_ms = Constants.AsyncPresetDefaults.high_throughput_max_latency_ms,
                .overflow_policy = .drop_oldest,
                .background_worker = true,
            };
        }

        /// Returns async settings for low-latency logging.
        pub fn lowLatency() AsyncConfig {
            return .{
                .enabled = true,
                .buffer_size = Constants.AsyncPresetDefaults.low_latency_buffer_size,
                .batch_size = Constants.AsyncPresetDefaults.low_latency_batch_size,
                .flush_interval_ms = Constants.AsyncPresetDefaults.low_latency_flush_interval_ms,
                .min_flush_interval_ms = Constants.AsyncPresetDefaults.low_latency_min_flush_interval_ms,
                .max_latency_ms = Constants.AsyncPresetDefaults.low_latency_max_latency_ms,
                .overflow_policy = .block,
                .background_worker = true,
            };
        }

        /// Returns async settings that prefer blocking over dropping records.
        pub fn reliable() AsyncConfig {
            return .{
                .enabled = true,
                .flush_interval_ms = Constants.AsyncPresetDefaults.balanced_flush_interval_ms,
                .min_flush_interval_ms = Constants.AsyncPresetDefaults.balanced_min_flush_interval_ms,
                .max_latency_ms = Constants.AsyncPresetDefaults.balanced_max_latency_ms,
                .overflow_policy = .block,
                .background_worker = true,
            };
        }

        /// Returns a copy with a specific queue size.
        pub fn withBufferSize(self: AsyncConfig, size: usize) AsyncConfig {
            var cfg = self;
            cfg.enabled = true;
            cfg.buffer_size = size;
            return cfg;
        }

        /// Returns a copy with a specific batch size.
        pub fn withBatchSize(self: AsyncConfig, size: usize) AsyncConfig {
            var cfg = self;
            cfg.batch_size = size;
            return cfg;
        }

        /// Returns a copy with a specific overflow policy.
        pub fn withOverflowPolicy(self: AsyncConfig, policy: OverflowPolicy) AsyncConfig {
            var cfg = self;
            cfg.overflow_policy = policy;
            return cfg;
        }

        /// Returns a copy with a clamped backpressure threshold.
        pub fn withBackpressureThreshold(self: AsyncConfig, threshold: f64) AsyncConfig {
            var cfg = self;
            cfg.backpressure_threshold = if (threshold < 0.0) 0.0 else if (threshold > 1.0) 1.0 else threshold;
            return cfg;
        }

        /// Alias for `withBufferSize`.
        pub const buffer = withBufferSize;
        /// Alias for `withBatchSize`.
        pub const batch = withBatchSize;
        /// Alias for `withOverflowPolicy`.
        pub const overflow = withOverflowPolicy;
        /// Alias for `withBackpressureThreshold`.
        pub const backpressure = withBackpressureThreshold;
    };

    /// Returns the default configuration.
    ///
    /// Defaults:
    ///   - Level: INFO
    ///   - Output: Console with colors
    ///   - Format: Standard text
    ///   - Features: Callbacks and exception handling enabled
    ///
    /// Complexity: O(1)
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
    ///
    /// Complexity: O(1)
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
                .max_age_seconds = 30 * Constants.TimeConstants.seconds_per_day,
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
    ///
    /// Complexity: O(1)
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
    ///
    /// Complexity: O(1)
    pub fn highThroughput() Config {
        return .{
            .level = .warning,
            .sampling = .{ .enabled = true, .strategy = .{ .adaptive = .{ .target_rate = Constants.ConfigPresetDefaults.high_throughput_sampling_target_rate } } },
            .rate_limit = .{ .enabled = true, .max_per_second = Constants.ConfigPresetDefaults.high_throughput_rate_limit_per_second },
            .buffer_config = .{
                .size = Constants.ConfigPresetDefaults.high_throughput_buffer_size,
                .flush_interval_ms = Constants.ConfigPresetDefaults.high_throughput_buffer_flush_interval_ms,
                .max_pending = Constants.ConfigPresetDefaults.high_throughput_max_pending,
            },
            .thread_pool = .{
                .enabled = true,
                .thread_count = Constants.ThreadDefaults.thread_count, // auto-detect
                .queue_size = Constants.ConfigPresetDefaults.high_throughput_thread_pool_queue_size,
                .work_stealing = true,
            },
            .async_config = .{
                .enabled = true,
                .buffer_size = Constants.ConfigPresetDefaults.high_throughput_async_buffer_size,
                .batch_size = Constants.ConfigPresetDefaults.high_throughput_async_batch_size,
                .flush_interval_ms = Constants.ConfigPresetDefaults.high_throughput_async_flush_interval_ms,
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
    ///
    /// Complexity: O(1)
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
    /// The `other` configuration takes precedence for non-default values.
    /// Used to layer configurations (e.g., specific override over base profile).
    ///
    /// Algorithm:
    ///   - Checks each field in `other`.
    ///   - If `other` has a non-default or active configuration for a component, it replaces the one in `self`.
    ///
    /// Arguments:
    ///   - `other`: The configuration to merge from.
    ///
    /// Return Value:
    ///   - A new `Config` struct with merged values.
    ///
    /// Complexity: O(1)
    pub fn merge(self: Config, other: Config) Config {
        var result = self;
        if (other.level != .info) result.level = other.level;
        if (other.json) result.json = true;
        if (other.pretty_json) result.pretty_json = true;
        if (other.ndjson) result.ndjson = true;
        if (other.logfmt) result.logfmt = true;
        if (other.cef) result.cef = true;
        if (other.align_fields) result.align_fields = true;
        if (other.msgpack) result.msgpack = true;
        if (other.include_trace_id) result.include_trace_id = true;
        if (other.include_pid) result.include_pid = true;
        if (other.include_hostname) result.include_hostname = true;
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
    ///
    /// Builder pattern method to enable async logging with a specific configuration.
    ///
    /// Arguments:
    ///   - `config`: Custom `AsyncConfig`.
    ///
    /// Return Value:
    ///   - Modified `Config` with async enabled.
    ///
    /// Complexity: O(1)
    pub fn withAsync(self: Config, config: AsyncConfig) Config {
        var result = self;
        result.async_config = config;
        result.async_config.enabled = true;
        return result;
    }

    /// Returns a copy with metrics configuration applied and top-level metrics enabled.
    ///
    /// Use this to keep `enable_metrics` synchronized with the detailed
    /// `metrics` block when composing production profiles.
    pub fn withMetrics(self: Config, config: MetricsConfig) Config {
        var result = self;
        result.metrics = config;
        result.enable_metrics = config.enabled;
        return result;
    }

    /// Returns a copy with rules configuration applied.
    pub fn withRules(self: Config, config: RulesConfig) Config {
        var result = self;
        result.rules = config;
        return result;
    }

    /// Returns a copy with rotation configuration applied.
    pub fn withRotation(self: Config, config: RotationConfig) Config {
        var result = self;
        result.rotation = config;
        return result;
    }

    /// Returns a copy with a complete high-throughput async pipeline enabled.
    pub fn withHighThroughputPipeline(self: Config) Config {
        var result = self;
        result.async_config = AsyncConfig.highThroughput();
        result.thread_pool = ThreadPoolConfig.highThroughput();
        result.metrics = MetricsConfig.production().withLatencyHistogram(20).prometheus();
        result.enable_metrics = true;
        return result;
    }

    /// Returns a copy with metrics, rules, and maintenance controls enabled.
    pub fn withObservability(self: Config, metric_prefix: []const u8) Config {
        var result = self;
        result.metrics = MetricsConfig.detailed().prometheus().withPrefix(metric_prefix);
        result.enable_metrics = true;
        result.rules = RulesConfig.production();
        result.scheduler.enabled = true;
        return result;
    }

    /// Alias for `withMetrics`.
    pub const metricsConfig = withMetrics;
    /// Alias for `withRules`.
    pub const rulesConfig = withRules;
    /// Alias for `withRotation`.
    pub const rotationConfig = withRotation;
    /// Alias for `withHighThroughputPipeline`.
    pub const pipeline = withHighThroughputPipeline;
    /// Alias for `withObservability`.
    pub const observability = withObservability;

    /// Returns a configuration with compression enabled.
    ///
    /// Builder pattern method to enable compression.
    ///
    /// Arguments:
    ///   - `config`: Custom `CompressionConfig`.
    ///
    /// Return Value:
    ///   - Modified `Config` with compression enabled.
    ///
    /// Complexity: O(1)
    pub fn withCompression(self: Config, config: CompressionConfig) Config {
        var result = self;
        result.compression = config;
        result.compression.enabled = true;
        return result;
    }

    /// Returns a configuration with compression enabled using defaults.
    /// This is the simplest one-liner to enable compression.
    ///
    /// Example:
    /// ```zig
    /// const config = Config.default().withCompressionEnabled();
    /// ```
    ///
    /// Complexity: O(1)
    pub fn withCompressionEnabled(self: Config) Config {
        return self.withCompression(CompressionConfig.basic());
    }

    /// Returns a configuration with implicit (automatic) compression.
    /// Files are automatically compressed on rotation - no manual intervention needed.
    ///
    /// Example:
    /// ```zig
    /// const config = Config.default().withImplicitCompression();
    /// ```
    ///
    /// Complexity: O(1)
    pub fn withImplicitCompression(self: Config) Config {
        return self.withCompression(CompressionConfig.implicit());
    }

    /// Returns a configuration for explicit (manual) compression.
    /// Use compressFile()/compressDirectory() for user-controlled compression.
    ///
    /// Example:
    /// ```zig
    /// const config = Config.default().withExplicitCompression();
    /// ```
    ///
    /// Complexity: O(1)
    pub fn withExplicitCompression(self: Config) Config {
        return self.withCompression(CompressionConfig.explicit());
    }

    /// Returns a configuration with fast compression (speed over ratio).
    ///
    /// Example:
    /// ```zig
    /// const config = Config.default().withFastCompression();
    /// ```
    ///
    /// Complexity: O(1)
    pub fn withFastCompression(self: Config) Config {
        return self.withCompression(CompressionConfig.fast());
    }

    /// Returns a configuration with best compression (ratio over speed).
    ///
    /// Example:
    /// ```zig
    /// const config = Config.default().withBestCompression();
    /// ```
    ///
    /// Complexity: O(1)
    pub fn withBestCompression(self: Config) Config {
        return self.withCompression(CompressionConfig.best());
    }

    /// Returns a configuration with background compression.
    /// Compression runs in a separate thread for non-blocking operation.
    ///
    /// Example:
    /// ```zig
    /// const config = Config.default().withBackgroundCompression();
    /// ```
    ///
    /// Complexity: O(1)
    pub fn withBackgroundCompression(self: Config) Config {
        return self.withCompression(CompressionConfig.backgroundMode());
    }

    /// Returns a configuration optimized for log file compression.
    ///
    /// Example:
    /// ```zig
    /// const config = Config.default().withLogCompression();
    /// ```
    ///
    /// Complexity: O(1)
    pub fn withLogCompression(self: Config) Config {
        return self.withCompression(CompressionConfig.forLogs());
    }

    /// Returns a configuration for production compression.
    /// Balanced performance with background processing and checksums.
    ///
    /// Example:
    /// ```zig
    /// const config = Config.default().withProductionCompression();
    /// ```
    ///
    /// Complexity: O(1)
    pub fn withProductionCompression(self: Config) Config {
        return self.withCompression(CompressionConfig.production());
    }

    /// Returns a configuration with zstd compression enabled (default settings).
    /// Zstd provides excellent compression ratios with very fast decompression.
    ///
    /// Example:
    /// ```zig
    /// const config = Config.default().withZstdCompression();
    /// ```
    ///
    /// Complexity: O(1)
    /// v0.1.5+
    pub fn withZstdCompression(self: Config) Config {
        return self.withCompression(CompressionConfig.zstd());
    }

    /// Returns a configuration with fast zstd compression.
    /// Prioritizes speed over compression ratio.
    ///
    /// Example:
    /// ```zig
    /// const config = Config.default().withZstdFastCompression();
    /// ```
    ///
    /// Complexity: O(1)
    /// v0.1.5+
    pub fn withZstdFastCompression(self: Config) Config {
        return self.withCompression(CompressionConfig.zstdFast());
    }

    /// Returns a configuration with best zstd compression.
    /// Prioritizes compression ratio over speed.
    ///
    /// Example:
    /// ```zig
    /// const config = Config.default().withZstdBestCompression();
    /// ```
    ///
    /// Complexity: O(1)
    /// v0.1.5+
    pub fn withZstdBestCompression(self: Config) Config {
        return self.withCompression(CompressionConfig.zstdBest());
    }

    /// Returns a configuration with production-ready zstd compression.
    /// Background processing with checksums for reliability.
    ///
    /// Example:
    /// ```zig
    /// const config = Config.default().withZstdProductionCompression();
    /// ```
    ///
    /// Complexity: O(1)
    /// v0.1.5+
    pub fn withZstdProductionCompression(self: Config) Config {
        return self.withCompression(CompressionConfig.zstdProduction());
    }

    /// Returns a configuration with lzma compression enabled.
    /// v0.1.6+
    pub fn withLzmaCompression(self: Config) Config {
        return self.withCompression(CompressionConfig.lzma());
    }

    /// Returns a configuration with lzma2 compression enabled.
    /// v0.1.6+
    pub fn withLzma2Compression(self: Config) Config {
        return self.withCompression(CompressionConfig.lzma2());
    }

    /// Returns a configuration with xz compression enabled.
    /// v0.1.6+
    pub fn withXzCompression(self: Config) Config {
        return self.withCompression(CompressionConfig.xz());
    }

    /// Returns a configuration with tar.gz compression enabled.
    /// v0.1.6+
    pub fn withTarGzCompression(self: Config) Config {
        return self.withCompression(CompressionConfig.tarGz());
    }

    /// Returns a configuration with zip compression enabled.
    /// v0.1.6+
    pub fn withZipCompression(self: Config) Config {
        return self.withCompression(CompressionConfig.zip());
    }

    /// Returns a configuration with lz4 compression enabled.
    /// v0.1.6+
    pub fn withLz4Compression(self: Config) Config {
        return self.withCompression(CompressionConfig.lz4());
    }

    /// Returns a configuration with brotli compression enabled.
    ///
    /// Builder pattern method to enable brotli compression.
    ///
    /// Arguments:
    ///   - `self`: Current configuration.
    ///
    /// Return Value:
    ///   - Modified `Config` with brotli compression enabled.
    ///
    /// Complexity: O(1)
    pub fn withBrotliCompression(self: Config) Config {
        return self.withCompression(CompressionConfig.brotli());
    }

    /// Returns a configuration with thread pool enabled.
    ///
    /// Builder pattern method to enable thread pool support.
    ///
    /// Arguments:
    ///   - `config`: Custom `ThreadPoolConfig`.
    ///
    /// Return Value:
    ///   - Modified `Config` with thread pool enabled.
    ///
    /// Complexity: O(1)
    pub fn withThreadPool(self: Config, config: ThreadPoolConfig) Config {
        var result = self;
        result.thread_pool = config;
        result.thread_pool.enabled = true;
        return result;
    }

    /// Returns a configuration with scheduler enabled.
    ///
    /// Builder pattern method to enable the background scheduler.
    ///
    /// Arguments:
    ///   - `config`: Custom `SchedulerConfig`.
    ///
    /// Return Value:
    ///   - Modified `Config` with scheduler enabled.
    ///
    /// Complexity: O(1)
    pub fn withScheduler(self: Config, config: SchedulerConfig) Config {
        var result = self;
        result.scheduler = config;
        result.scheduler.enabled = true;
        return result;
    }

    /// Returns a configuration for log-only mode (no console display, only file storage).
    ///
    /// Disables console output while keeping file storage enabled.
    /// Useful for production environments where logs should only be written to files.
    ///
    /// Complexity: O(1)
    pub fn logOnly() Config {
        var result = Config.default();
        result.global_console_display = false;
        result.global_file_storage = true;
        result.auto_sink = false; // Disable auto console sink
        return result;
    }

    /// Returns a configuration for display-only mode (console display, no file storage).
    ///
    /// Enables console output while disabling file storage.
    /// Useful for development or debugging where you only want to see logs in the console.
    ///
    /// Complexity: O(1)
    pub fn displayOnly() Config {
        var result = Config.default();
        result.global_console_display = true;
        result.global_file_storage = false;
        result.auto_sink = true; // Enable auto console sink
        return result;
    }

    /// Returns a configuration with custom display and storage settings.
    ///
    /// Allows fine-grained control over console display and file storage.
    ///
    /// Arguments:
    ///   - `console`: Enable/disable console display.
    ///   - `file`: Enable/disable file storage.
    ///   - `auto_sink`: Enable/disable automatic console sink creation.
    ///
    /// Return Value:
    ///   - A `Config` with the specified display/storage settings.
    ///
    /// Complexity: O(1)
    pub fn withDisplayStorage(console: bool, file: bool, auto_sink: bool) Config {
        var result = Config.default();
        result.global_console_display = console;
        result.global_file_storage = file;
        result.auto_sink = auto_sink;
        return result;
    }

    const JsonConfig = struct {
        level: ?[]const u8 = null,
        color: ?bool = null,
        json: ?bool = null,
        pretty_json: ?bool = null,
        log_compact: ?bool = null,
        ndjson: ?bool = null,
        logfmt: ?bool = null,
        cef: ?bool = null,
        align_fields: ?bool = null,
        tamper_evident: ?bool = null,
        app_name: ?[]const u8 = null,
        app_version: ?[]const u8 = null,
        environment: ?[]const u8 = null,
    };

    /// Parses a JSON string to create a Config instance.
    pub fn loadFromJson(allocator: std.mem.Allocator, json_bytes: []const u8) !Config {
        const parsed = try std.json.parseFromSlice(JsonConfig, allocator, json_bytes, .{
            .ignore_unknown_fields = true,
        });
        defer parsed.deinit();

        var config = Config.default();
        const j = parsed.value;

        if (j.level) |lvl| {
            config.level = if (std.ascii.eqlIgnoreCase(lvl, "trace") or std.ascii.eqlIgnoreCase(lvl, "trc")) .trace
                else if (std.ascii.eqlIgnoreCase(lvl, "debug") or std.ascii.eqlIgnoreCase(lvl, "dbg")) .debug
                else if (std.ascii.eqlIgnoreCase(lvl, "info")) .info
                else if (std.ascii.eqlIgnoreCase(lvl, "notice") or std.ascii.eqlIgnoreCase(lvl, "note")) .notice
                else if (std.ascii.eqlIgnoreCase(lvl, "success") or std.ascii.eqlIgnoreCase(lvl, "ok")) .success
                else if (std.ascii.eqlIgnoreCase(lvl, "warning") or std.ascii.eqlIgnoreCase(lvl, "warn")) .warning
                else if (std.ascii.eqlIgnoreCase(lvl, "err") or std.ascii.eqlIgnoreCase(lvl, "error")) .err
                else if (std.ascii.eqlIgnoreCase(lvl, "fail")) .fail
                else if (std.ascii.eqlIgnoreCase(lvl, "critical") or std.ascii.eqlIgnoreCase(lvl, "crit")) .critical
                else if (std.ascii.eqlIgnoreCase(lvl, "fatal") or std.ascii.eqlIgnoreCase(lvl, "panic")) .fatal
                else Level.fromString(lvl) orelse .info;
        }
        if (j.color) |val| config.color = val;
        if (j.json) |val| config.json = val;
        if (j.pretty_json) |val| config.pretty_json = val;
        if (j.log_compact) |val| config.log_compact = val;
        if (j.ndjson) |val| config.ndjson = val;
        if (j.logfmt) |val| config.logfmt = val;
        if (j.cef) |val| config.cef = val;
        if (j.align_fields) |val| config.align_fields = val;
        if (j.tamper_evident) |val| config.tamper_evident = val;

        return config;
    }

    /// Loads the configuration from a JSON file.
    pub fn loadFromFile(allocator: std.mem.Allocator, file_path: []const u8) !Config {
        const io = Utils.io();
        const file = try std.Io.Dir.cwd().openFile(io, file_path, .{});
        defer file.close(io);

        // Read entire file (up to 64KB)
        const buf = try allocator.alloc(u8, 65536);
        defer allocator.free(buf);

        var file_buffer: [4096]u8 = undefined;
        var reader = file.reader(io, &file_buffer);
        const len = try reader.interface.readSliceShort(buf);
        const json_bytes = buf[0..len];

        return try loadFromJson(allocator, json_bytes);
    }
};

test "config JSON load and parse" {
    const allocator = std.testing.allocator;

    const json_str = "{\"level\": \"debug\", \"color\": false}";
    const config = try Config.loadFromJson(allocator, json_str);
    try std.testing.expectEqual(Level.debug, config.level);
    try std.testing.expect(!config.color);

    // Test writing and loading from file using std.Io
    const test_file_path = "test_config_temp.json";
    const io = Utils.io();
    const file = try std.Io.Dir.cwd().createFile(io, test_file_path, .{});
    try file.writeStreamingAll(io, json_str);
    file.close(io);
    defer std.Io.Dir.cwd().deleteFile(io, test_file_path) catch {};

    const config2 = try Config.loadFromFile(allocator, test_file_path);
    try std.testing.expectEqual(Level.debug, config2.level);
    try std.testing.expect(!config2.color);
}

test "config default values" {
    const config = Config.default();
    try std.testing.expectEqual(Level.info, config.level);
    try std.testing.expect(config.global_color_display);
    try std.testing.expect(config.global_console_display);
    try std.testing.expect(config.global_file_storage);
    try std.testing.expect(config.color);
    try std.testing.expect(!config.json);
    try std.testing.expect(config.auto_sink);
    try std.testing.expectEqualStrings(Constants.ConfigDefaults.distributed_trace_header, config.trace_header);
    try std.testing.expectEqualStrings(Constants.ConfigDefaults.distributed_trace_header, config.distributed.trace_header);
    try std.testing.expectEqualStrings(Constants.ConfigDefaults.distributed_span_header, config.distributed.span_header);
    try std.testing.expectEqualStrings(Constants.ConfigDefaults.distributed_parent_header, config.distributed.parent_header);
    try std.testing.expectEqualStrings(Constants.ConfigDefaults.distributed_baggage_header, config.distributed.baggage_header);
}

test "config time format constants are centralized" {
    try std.testing.expectEqualStrings(Constants.TimeConstants.default_time_pattern, Config.TimeFormat.default_pattern);
    try std.testing.expectEqualStrings("default", Config.TimeFormat.default_alias);
    try std.testing.expectEqualStrings("ISO8601", Config.TimeFormat.iso8601);
    try std.testing.expectEqualStrings("RFC3339", Config.TimeFormat.rfc3339);
    try std.testing.expectEqualStrings("unix", Config.TimeFormat.unix);
    try std.testing.expectEqualStrings("unix_ms", Config.TimeFormat.unix_ms);
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

test "config pipeline builders enable related features" {
    const cfg = Config.default()
        .withHighThroughputPipeline()
        .withObservability("svc.api")
        .withRotation(Config.RotationConfig.daily(7).withCompression(.zstd));

    try std.testing.expect(cfg.async_config.enabled);
    try std.testing.expect(cfg.thread_pool.enabled);
    try std.testing.expect(cfg.enable_metrics);
    try std.testing.expect(cfg.metrics.enabled);
    try std.testing.expectEqual(Config.MetricsConfig.ExportFormat.prometheus, cfg.metrics.export_format);
    try std.testing.expectEqualStrings("svc.api", cfg.metrics.metric_prefix);
    try std.testing.expect(cfg.rules.enabled);
    try std.testing.expect(cfg.scheduler.enabled);
    try std.testing.expect(cfg.rotation.enabled);
    try std.testing.expectEqual(Config.CompressionConfig.CompressionAlgorithm.zstd, cfg.rotation.compression_algorithm);
}

test "config async metrics and threadpool helper aliases" {
    const async_cfg = Config.AsyncConfig.lowLatency()
        .buffer(128)
        .batch(8)
        .overflow(.drop_newest)
        .backpressure(2.0);
    try std.testing.expect(async_cfg.enabled);
    try std.testing.expectEqual(@as(usize, 128), async_cfg.buffer_size);
    try std.testing.expectEqual(@as(usize, 8), async_cfg.batch_size);
    try std.testing.expectEqual(Config.AsyncConfig.OverflowPolicy.drop_newest, async_cfg.overflow_policy);
    try std.testing.expectEqual(@as(f64, 1.0), async_cfg.backpressure_threshold);

    const metrics_cfg = Config.MetricsConfig.minimal()
        .prometheus()
        .prefix("worker")
        .histogram(12)
        .alerts(0.1, 0.2)
        .breakdowns(false, true);
    try std.testing.expect(metrics_cfg.enabled);
    try std.testing.expectEqual(Config.MetricsConfig.ExportFormat.prometheus, metrics_cfg.export_format);
    try std.testing.expectEqualStrings("worker", metrics_cfg.metric_prefix);
    try std.testing.expect(metrics_cfg.track_latency);
    try std.testing.expect(metrics_cfg.enable_histogram);
    try std.testing.expectEqual(@as(u8, 12), metrics_cfg.histogram_buckets);
    try std.testing.expect(!metrics_cfg.export_level_breakdown);
    try std.testing.expect(metrics_cfg.export_sink_breakdown);

    const pool_cfg = Config.ThreadPoolConfig.ioBound().threads(4).queue(256);
    try std.testing.expect(pool_cfg.enabled);
    try std.testing.expectEqual(@as(usize, 4), pool_cfg.thread_count);
    try std.testing.expectEqual(@as(usize, 256), pool_cfg.queue_size);
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
    try std.testing.expectEqual(Constants.InvokeConstants.default_max_rules, rules_config.max_rules);
    try std.testing.expectEqual(Constants.InvokeConstants.default_max_messages, rules_config.max_messages_per_rule);
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

test "compression config presets" {
    // Test enable() preset
    const enable_cfg = Config.CompressionConfig.enable();
    try std.testing.expect(enable_cfg.enabled);

    // Test basic() is alias for enable()
    const basic_cfg = Config.CompressionConfig.basic();
    try std.testing.expect(basic_cfg.enabled);

    // Test implicit() preset
    const implicit_cfg = Config.CompressionConfig.implicit();
    try std.testing.expect(implicit_cfg.enabled);
    try std.testing.expect(implicit_cfg.on_rotation);
    try std.testing.expectEqual(implicit_cfg.mode, .on_rotation);

    // Test explicit() preset
    const explicit_cfg = Config.CompressionConfig.explicit();
    try std.testing.expect(explicit_cfg.enabled);
    try std.testing.expect(!explicit_cfg.on_rotation);
    try std.testing.expectEqual(explicit_cfg.mode, .disabled);

    // Test fast() preset
    const fast_cfg = Config.CompressionConfig.fast();
    try std.testing.expect(fast_cfg.enabled);
    try std.testing.expectEqual(fast_cfg.level, .fastest);

    // Test balanced() preset
    const balanced_cfg = Config.CompressionConfig.balanced();
    try std.testing.expect(balanced_cfg.enabled);
    try std.testing.expectEqual(balanced_cfg.level, .default);

    // Test best() preset
    const best_cfg = Config.CompressionConfig.best();
    try std.testing.expect(best_cfg.enabled);
    try std.testing.expectEqual(best_cfg.level, .best);
    try std.testing.expectEqual(best_cfg.algorithm, .gzip);

    // Test forLogs() preset
    const logs_cfg = Config.CompressionConfig.forLogs();
    try std.testing.expect(logs_cfg.enabled);
    try std.testing.expectEqual(logs_cfg.strategy, .text);

    // Test archive() preset
    const archive_cfg = Config.CompressionConfig.archive();
    try std.testing.expect(archive_cfg.enabled);
    try std.testing.expect(!archive_cfg.keep_original);
    try std.testing.expectEqual(archive_cfg.level, .best);

    // Test keepOriginals() preset
    const keep_cfg = Config.CompressionConfig.keepOriginals();
    try std.testing.expect(keep_cfg.enabled);
    try std.testing.expect(keep_cfg.keep_original);

    // Test onSize() preset
    const size_cfg = Config.CompressionConfig.onSize(5 * Constants.SizeConstants.bytes_per_mb);
    try std.testing.expect(size_cfg.enabled);
    try std.testing.expectEqual(size_cfg.mode, .on_size_threshold);
    try std.testing.expectEqual(size_cfg.size_threshold, 5 * Constants.SizeConstants.bytes_per_mb);

    // Test production() preset
    const prod_cfg = Config.CompressionConfig.production();
    try std.testing.expect(prod_cfg.enabled);
    try std.testing.expect(prod_cfg.background);
    try std.testing.expect(prod_cfg.checksum);

    // Test development() preset
    const dev_cfg = Config.CompressionConfig.development();
    try std.testing.expect(dev_cfg.enabled);
    try std.testing.expect(dev_cfg.keep_original);
    try std.testing.expectEqual(dev_cfg.level, .fastest);

    // Test disable() preset
    const disable_cfg = Config.CompressionConfig.disable();
    try std.testing.expect(!disable_cfg.enabled);

    // Test streamingMode() preset
    const stream_cfg = Config.CompressionConfig.streamingMode();
    try std.testing.expect(stream_cfg.enabled);
    try std.testing.expect(stream_cfg.streaming);
    try std.testing.expectEqual(stream_cfg.mode, .streaming);

    // Test backgroundMode() preset
    const bg_cfg = Config.CompressionConfig.backgroundMode();
    try std.testing.expect(bg_cfg.enabled);
    try std.testing.expect(bg_cfg.background);

    // Test zstd() preset (v0.1.5+)
    const zstd_cfg = Config.CompressionConfig.zstd();
    try std.testing.expect(zstd_cfg.enabled);
    try std.testing.expectEqual(zstd_cfg.algorithm, .zstd);
    try std.testing.expectEqual(zstd_cfg.level, .default);
    try std.testing.expectEqualStrings(".zst", zstd_cfg.extension);
    try std.testing.expect(zstd_cfg.checksum);

    // Test zstdFast() preset (v0.1.5+)
    const zstd_fast_cfg = Config.CompressionConfig.zstdFast();
    try std.testing.expect(zstd_fast_cfg.enabled);
    try std.testing.expectEqual(zstd_fast_cfg.algorithm, .zstd);
    try std.testing.expectEqual(zstd_fast_cfg.level, .fastest);
    try std.testing.expectEqualStrings(".zst", zstd_fast_cfg.extension);

    // Test zstdBest() preset (v0.1.5+)
    const zstd_best_cfg = Config.CompressionConfig.zstdBest();
    try std.testing.expect(zstd_best_cfg.enabled);
    try std.testing.expectEqual(zstd_best_cfg.algorithm, .zstd);
    try std.testing.expectEqual(zstd_best_cfg.level, .best);
    try std.testing.expect(!zstd_best_cfg.keep_original);

    // Test zstdProduction() preset (v0.1.5+)
    const zstd_prod_cfg = Config.CompressionConfig.zstdProduction();
    try std.testing.expect(zstd_prod_cfg.enabled);
    try std.testing.expectEqual(zstd_prod_cfg.algorithm, .zstd);
    try std.testing.expect(zstd_prod_cfg.background);
    try std.testing.expect(zstd_prod_cfg.checksum);
    try std.testing.expect(!zstd_prod_cfg.keep_original);

    // Test zstdWithLevel() preset (v0.1.5+)
    const zstd_custom_cfg = Config.CompressionConfig.zstdWithLevel(15);
    try std.testing.expect(zstd_custom_cfg.enabled);
    try std.testing.expectEqual(zstd_custom_cfg.algorithm, .zstd);
    try std.testing.expectEqual(zstd_custom_cfg.custom_zstd_level.?, 15);
    try std.testing.expectEqual(zstd_custom_cfg.getEffectiveZstdLevel(), 15);

    // Test zstd aliases (v0.1.5+)
    const zstd_default_cfg = Config.CompressionConfig.zstdDefault();
    try std.testing.expectEqual(zstd_default_cfg.algorithm, .zstd);

    const zstd_speed_cfg = Config.CompressionConfig.zstdSpeed();
    try std.testing.expectEqual(zstd_speed_cfg.level, .fastest);

    const zstd_max_cfg = Config.CompressionConfig.zstdMax();
    try std.testing.expectEqual(zstd_max_cfg.level, .best);
}

test "compression config customization fields" {
    // Test file name customization options
    const cfg = Config.CompressionConfig{
        .enabled = true,
        .file_prefix = "archive_",
        .file_suffix = "_compressed",
        .archive_root_dir = "logs/archive",
        .create_date_subdirs = true,
        .preserve_dir_structure = false,
        .naming_pattern = "{base}_{date}{ext}",
    };

    try std.testing.expect(cfg.enabled);
    try std.testing.expectEqualStrings("archive_", cfg.file_prefix.?);
    try std.testing.expectEqualStrings("_compressed", cfg.file_suffix.?);
    try std.testing.expectEqualStrings("logs/archive", cfg.archive_root_dir.?);
    try std.testing.expect(cfg.create_date_subdirs);
    try std.testing.expect(!cfg.preserve_dir_structure);
    try std.testing.expectEqualStrings("{base}_{date}{ext}", cfg.naming_pattern.?);
}

test "zstd compression level mapping" {
    // Test toZstdLevel() returns correct values
    try std.testing.expectEqual(@as(i32, 0), Config.CompressionConfig.CompressionLevel.none.toZstdLevel());
    try std.testing.expectEqual(@as(i32, 1), Config.CompressionConfig.CompressionLevel.fastest.toZstdLevel());
    try std.testing.expectEqual(@as(i32, 3), Config.CompressionConfig.CompressionLevel.fast.toZstdLevel());
    try std.testing.expectEqual(@as(i32, 6), Config.CompressionConfig.CompressionLevel.default.toZstdLevel());
    try std.testing.expectEqual(@as(i32, 19), Config.CompressionConfig.CompressionLevel.best.toZstdLevel());
}

test "zstd custom level clamping in config" {
    // Test that levels are clamped to valid range
    const cfg_low = Config.CompressionConfig.zstdWithLevel(-5);
    try std.testing.expectEqual(cfg_low.custom_zstd_level.?, 1); // Clamped to 1

    const cfg_high = Config.CompressionConfig.zstdWithLevel(100);
    try std.testing.expectEqual(cfg_high.custom_zstd_level.?, 22); // Clamped to 22

    const cfg_valid = Config.CompressionConfig.zstdWithLevel(10);
    try std.testing.expectEqual(cfg_valid.custom_zstd_level.?, 10); // No clamping needed
}

test "getEffectiveZstdLevel priority" {
    // When custom_zstd_level is set, it takes priority
    var cfg = Config.CompressionConfig.zstd();
    try std.testing.expectEqual(@as(i32, 6), cfg.getEffectiveZstdLevel()); // Default enum

    cfg.custom_zstd_level = 12;
    try std.testing.expectEqual(@as(i32, 12), cfg.getEffectiveZstdLevel()); // Custom takes priority

    cfg.custom_zstd_level = null;
    try std.testing.expectEqual(@as(i32, 6), cfg.getEffectiveZstdLevel()); // Falls back to enum
}

test "scheduler config customization fields" {
    // Test scheduler compression customization options
    const cfg = Config.SchedulerConfig{
        .enabled = true,
        .archive_root_dir = "logs/scheduled_archive",
        .create_date_subdirs = true,
        .compression_algorithm = .gzip,
        .compression_level = .best,
        .keep_originals = true,
        .archive_file_prefix = "scheduled_",
        .archive_file_suffix = "_archived",
        .preserve_dir_structure = false,
        .clean_empty_dirs = true,
        .min_age_days_for_compression = 3,
        .max_concurrent_compressions = 4,
    };

    try std.testing.expect(cfg.enabled);
    try std.testing.expectEqualStrings("logs/scheduled_archive", cfg.archive_root_dir.?);
    try std.testing.expect(cfg.create_date_subdirs);
    try std.testing.expectEqual(cfg.compression_algorithm, .gzip);
    try std.testing.expectEqual(cfg.compression_level, .best);
    try std.testing.expect(cfg.keep_originals);
    try std.testing.expectEqualStrings("scheduled_", cfg.archive_file_prefix.?);
    try std.testing.expectEqualStrings("_archived", cfg.archive_file_suffix.?);
    try std.testing.expect(!cfg.preserve_dir_structure);
    try std.testing.expect(cfg.clean_empty_dirs);
    try std.testing.expectEqual(cfg.min_age_days_for_compression, 3);
    try std.testing.expectEqual(cfg.max_concurrent_compressions, 4);
}

test "rotation config customization fields" {
    // Test rotation compression customization options
    const cfg = Config.RotationConfig{
        .enabled = true,
        .archive_root_dir = "logs/rotated_archive",
        .create_date_subdirs = true,
        .file_prefix = "rotated_",
        .file_suffix = "_old",
        .compression_algorithm = .deflate,
        .compression_level = .fast,
        .keep_original = true,
        .compress_on_retention = true,
        .delete_after_retention_compress = false,
    };

    try std.testing.expect(cfg.enabled);
    try std.testing.expectEqualStrings("logs/rotated_archive", cfg.archive_root_dir.?);
    try std.testing.expect(cfg.create_date_subdirs);
    try std.testing.expectEqualStrings("rotated_", cfg.file_prefix.?);
    try std.testing.expectEqualStrings("_old", cfg.file_suffix.?);
    try std.testing.expectEqual(cfg.compression_algorithm, .deflate);
    try std.testing.expectEqual(cfg.compression_level, .fast);
    try std.testing.expect(cfg.keep_original);
    try std.testing.expect(cfg.compress_on_retention);
    try std.testing.expect(!cfg.delete_after_retention_compress);
}

test "level color config theme presets" {
    const cfg_default = Config.LevelColorConfig{};
    try std.testing.expectEqual(cfg_default.theme_preset, .default);
    try std.testing.expect(cfg_default.trace_color == null);

    const cfg_neon = Config.LevelColorConfig{ .theme_preset = .neon };
    try std.testing.expectEqual(cfg_neon.theme_preset, .neon);

    const cfg_dark = Config.LevelColorConfig{ .theme_preset = .dark };
    try std.testing.expectEqual(cfg_dark.theme_preset, .dark);

    const cfg_light = Config.LevelColorConfig{ .theme_preset = .light };
    try std.testing.expectEqual(cfg_light.theme_preset, .light);

    const cfg_pastel = Config.LevelColorConfig{ .theme_preset = .pastel };
    try std.testing.expectEqual(cfg_pastel.theme_preset, .pastel);
}

test "level color config individual overrides" {
    const cfg = Config.LevelColorConfig{
        .theme_preset = .default,
        .trace_color = "38;5;51",
        .error_color = "91;1",
        .notice_color = "96",
        .fatal_color = "97;41;1",
    };

    try std.testing.expectEqualStrings("38;5;51", cfg.trace_color.?);
    try std.testing.expectEqualStrings("91;1", cfg.error_color.?);
    try std.testing.expectEqualStrings("96", cfg.notice_color.?);
    try std.testing.expectEqualStrings("97;41;1", cfg.fatal_color.?);
    try std.testing.expect(cfg.debug_color == null);
    try std.testing.expect(cfg.info_color == null);
}

test "level color config getColorForLevel" {
    const cfg_default = Config.LevelColorConfig{};
    try std.testing.expectEqualStrings("36", cfg_default.getColorForLevel(.trace));
    try std.testing.expectEqualStrings("34", cfg_default.getColorForLevel(.debug));
    try std.testing.expectEqualStrings("31", cfg_default.getColorForLevel(.err));

    const cfg_with_override = Config.LevelColorConfig{
        .theme_preset = .default,
        .trace_color = "38;5;99",
    };
    try std.testing.expectEqualStrings("38;5;99", cfg_with_override.getColorForLevel(.trace));
    try std.testing.expectEqualStrings("34", cfg_with_override.getColorForLevel(.debug));

    const cfg_bright = Config.LevelColorConfig{ .theme_preset = .bright };
    try std.testing.expectEqualStrings("96;1", cfg_bright.getColorForLevel(.trace));
    try std.testing.expectEqualStrings("91;1", cfg_bright.getColorForLevel(.err));

    const cfg_dim = Config.LevelColorConfig{ .theme_preset = .dim };
    try std.testing.expectEqualStrings("36;2", cfg_dim.getColorForLevel(.trace));
}

test "level color config none theme" {
    const cfg_none = Config.LevelColorConfig{ .theme_preset = .none };
    try std.testing.expectEqualStrings("", cfg_none.getColorForLevel(.trace));
    try std.testing.expectEqualStrings("", cfg_none.getColorForLevel(.err));
}

test "telemetry metric export helpers" {
    const base = TelemetryConfig.development();

    const json_cfg = base.withJsonMetrics("metrics.jsonl");
    try std.testing.expectEqual(TelemetryConfig.MetricFormat.json, json_cfg.metric_format);
    try std.testing.expectEqualStrings("metrics.jsonl", json_cfg.metrics_file_path.?);

    const prom_cfg = base.withPrometheusMetrics("metrics.prom").withMetricPrefix("api");
    try std.testing.expectEqual(TelemetryConfig.MetricFormat.prometheus, prom_cfg.metric_format);
    try std.testing.expectEqualStrings("metrics.prom", prom_cfg.metrics_file_path.?);
    try std.testing.expectEqualStrings("api", prom_cfg.metric_prefix);
    try std.testing.expect(prom_cfg.sanitize_metric_names);

    const raw_cfg = prom_cfg.withMetricNameSanitization(false);
    try std.testing.expect(!raw_cfg.sanitize_metric_names);
}

/// OpenTelemetry telemetry configuration options.
pub const TelemetryConfig = struct {
    /// Enable OpenTelemetry integration.
    enabled: bool = false,

    /// OpenTelemetry provider.
    provider: Provider = .none,

    /// Exporter endpoint URL (HTTP/gRPC endpoint).
    exporter_endpoint: ?[]const u8 = null,

    /// API key for authentication.
    api_key: ?[]const u8 = null,

    /// Connection string (for Azure Application Insights).
    connection_string: ?[]const u8 = null,

    /// Project ID (for Google Cloud, AWS, Azure).
    project_id: ?[]const u8 = null,

    /// Region (for AWS, Azure, Google Cloud).
    region: ?[]const u8 = null,

    /// File path for file-based exporter (JSONL format).
    exporter_file_path: ?[]const u8 = null,

    /// File path for metrics export when using JSON/Prometheus formats.
    metrics_file_path: ?[]const u8 = null,

    /// Batch span export size.
    batch_size: usize = 1,

    /// Batch export timeout in milliseconds.
    batch_timeout_ms: u64 = Constants.TelemetryDefaults.batch_timeout_ms,

    /// Flush interval in milliseconds.
    flush_interval_ms: u64 = 0,

    /// Sampling strategy configuration.
    sampling_strategy: SamplingStrategy = .always_on,

    /// Sampling rate (0.0 to 1.0) when using trace_id_ratio strategy.
    sampling_rate: f64 = Constants.TelemetryDefaults.sampling_rate,

    /// Service name for resource identification.
    service_name: ?[]const u8 = null,

    /// Service version for resource identification.
    service_version: ?[]const u8 = null,

    /// Environment name (e.g., "production", "staging", "development").
    environment: ?[]const u8 = null,

    /// Datacenter or region identifier.
    datacenter: ?[]const u8 = null,

    /// Span processor type.
    span_processor_type: SpanProcessorType = .simple,

    /// Metric exporter format.
    metric_format: MetricFormat = .otlp,

    /// Optional prefix applied to exported metric names.
    metric_prefix: []const u8 = Constants.TelemetryDefaults.metric_prefix,

    /// Separator inserted between `metric_prefix` and the original metric name.
    metric_prefix_separator: []const u8 = Constants.TelemetryDefaults.metric_prefix_separator,

    /// Sanitize metric names for exporter compatibility.
    sanitize_metric_names: bool = Constants.TelemetryDefaults.sanitize_metric_names,

    /// Compress span exports.
    compress_exports: bool = false,

    /// Custom exporter initialization callback.
    custom_exporter_fn: ?*const fn () anyerror!void = null,

    /// Span start event callback (span_id, name).
    on_span_start: ?*const fn ([]const u8, []const u8) void = null,

    /// Span end event callback (span_id, duration_ns).
    on_span_end: ?*const fn ([]const u8, u64) void = null,

    /// Metric recorded callback (name, value).
    on_metric_recorded: ?*const fn ([]const u8, f64) void = null,

    /// Error callback (error_msg).
    on_error: ?*const fn ([]const u8) void = null,

    /// Enable automatic context propagation in HTTP headers.
    auto_context_propagation: bool = true,

    /// W3C Trace Context header name for trace IDs.
    trace_header: []const u8 = Constants.TelemetryDefaults.trace_header,

    /// Baggage/Correlation context header name.
    baggage_header: []const u8 = Constants.TelemetryDefaults.baggage_header,

    /// Export format configuration.
    export_format: ExportFormat = .json,

    /// OpenTelemetry providers.
    pub const Provider = enum {
        /// No provider (disabled).
        none,
        /// Jaeger (native Thrift protocol over UDP).
        jaeger,
        /// Zipkin (JSON over HTTP).
        zipkin,
        /// Datadog APM.
        datadog,
        /// Google Cloud Trace.
        google_cloud,
        /// Google Analytics 4 (Measurement Protocol).
        google_analytics,
        /// Google Tag Manager (Server-Side).
        google_tag_manager,
        /// AWS X-Ray.
        aws_xray,
        /// Azure Application Insights.
        azure,
        /// Generic OpenTelemetry Collector (gRPC/HTTP).
        generic,
        /// File-based exporter (JSONL format, local only).
        file,
        /// Custom user-defined exporter.
        custom,
    };

    /// Sampling strategy types.
    pub const SamplingStrategy = enum {
        /// Always sample all traces.
        always_on,
        /// Never sample any traces.
        always_off,
        /// Sample based on trace ID hash (use sampling_rate field).
        trace_id_ratio,
        /// Sample based on parent decision (W3C TraceFlags).
        parent_based,
    };

    /// Span processor types.
    pub const SpanProcessorType = enum {
        /// Simple processor (keeps completed spans pending until an explicit `exportSpans()` or `flush()` call).
        simple,
        /// Batch processor (batches spans before export and may automatically export when the batch size or timeout is reached).
        batch,
    };

    /// Metric export formats.
    pub const MetricFormat = enum {
        /// OpenTelemetry Protocol format.
        otlp,
        /// Prometheus format.
        prometheus,
        /// JSON format.
        json,
    };

    /// Export format for telemetry logs.
    pub const ExportFormat = enum {
        /// JSON format.
        json,
        /// Honeycomb specific event format.
        honeycomb,
    };

    /// Returns default telemetry configuration (disabled).
    pub fn default() TelemetryConfig {
        return .{};
    }

    /// Returns production-ready telemetry configuration with Jaeger.
    pub fn jaeger() TelemetryConfig {
        return .{
            .enabled = true,
            .provider = .jaeger,
            .exporter_endpoint = "http://localhost:6831",
            .span_processor_type = .batch,
            .batch_size = Constants.TelemetryDefaults.batch_size,
            .sampling_strategy = .trace_id_ratio,
            .sampling_rate = 0.1,
        };
    }

    /// Returns configuration for Zipkin.
    pub fn zipkin() TelemetryConfig {
        return .{
            .enabled = true,
            .provider = .zipkin,
            .exporter_endpoint = "http://localhost:9411/api/v2/spans",
            .span_processor_type = .batch,
            .batch_size = Constants.TelemetryDefaults.zipkin_batch_size,
        };
    }

    /// Returns configuration for Datadog APM.
    pub fn datadog(api_key: []const u8) TelemetryConfig {
        return .{
            .enabled = true,
            .provider = .datadog,
            .exporter_endpoint = "http://localhost:8126/v0.3/traces",
            .api_key = api_key,
            .span_processor_type = .batch,
        };
    }

    /// Returns configuration for Google Cloud Trace.
    pub fn googleCloud(project_id: []const u8, api_key: []const u8) TelemetryConfig {
        return .{
            .enabled = true,
            .provider = .google_cloud,
            .project_id = project_id,
            .api_key = api_key,
            .exporter_endpoint = "https://cloudtrace.googleapis.com/v2",
            .span_processor_type = .batch,
        };
    }

    /// Returns configuration for AWS X-Ray.
    pub fn awsXray(region: []const u8) TelemetryConfig {
        return .{
            .enabled = true,
            .provider = .aws_xray,
            .region = region,
            .exporter_endpoint = "http://localhost:2000",
            .span_processor_type = .batch,
        };
    }

    /// Returns configuration for Azure Application Insights.
    pub fn azure(connection_string: []const u8) TelemetryConfig {
        return .{
            .enabled = true,
            .provider = .azure,
            .connection_string = connection_string,
            .exporter_endpoint = "https://dc.applicationinsights.azure.com/v2.1/track",
            .span_processor_type = .batch,
        };
    }

    /// Returns configuration for Google Analytics 4 (Measurement Protocol).
    /// measurement_id: GA4 Measurement ID (e.g., "G-XXXXXXXXXX")
    /// api_secret: GA4 Measurement Protocol API secret
    pub fn googleAnalytics(measurement_id: []const u8, api_secret: []const u8) TelemetryConfig {
        return .{
            .enabled = true,
            .provider = .google_analytics,
            .project_id = measurement_id,
            .api_key = api_secret,
            .exporter_endpoint = "https://www.google-analytics.com/mp/collect",
            .span_processor_type = .batch,
            .batch_size = Constants.TelemetryDefaults.google_analytics_batch_limit,
        };
    }

    /// Returns configuration for Google Tag Manager Server-Side.
    /// container_url: Server-side GTM container URL
    /// api_key: Optional API key for authentication
    pub fn googleTagManager(container_url: []const u8, api_key: ?[]const u8) TelemetryConfig {
        return .{
            .enabled = true,
            .provider = .google_tag_manager,
            .exporter_endpoint = container_url,
            .api_key = api_key,
            .span_processor_type = .batch,
        };
    }

    /// Returns configuration for generic OpenTelemetry Collector.
    pub fn otelCollector(endpoint: []const u8) TelemetryConfig {
        return .{
            .enabled = true,
            .provider = .generic,
            .exporter_endpoint = endpoint,
            .span_processor_type = .batch,
            .batch_size = Constants.TelemetryDefaults.collector_batch_size,
        };
    }

    /// Returns configuration for file-based exporter (development/testing).
    pub fn file(path: []const u8) TelemetryConfig {
        return .{
            .enabled = true,
            .provider = .file,
            .exporter_file_path = path,
            .span_processor_type = .simple,
        };
    }

    /// Returns configuration with custom exporter.
    pub fn custom(exporter_fn: *const fn () anyerror!void) TelemetryConfig {
        return .{
            .enabled = true,
            .provider = .custom,
            .custom_exporter_fn = exporter_fn,
            .span_processor_type = .simple,
        };
    }

    /// Returns high-throughput telemetry configuration with sampling.
    pub fn highThroughput() TelemetryConfig {
        return .{
            .enabled = true,
            .provider = .jaeger,
            .exporter_endpoint = "http://localhost:6831",
            .span_processor_type = .batch,
            .batch_size = Constants.TelemetryDefaults.high_throughput_batch_size,
            .batch_timeout_ms = Constants.TelemetryDefaults.high_throughput_batch_timeout_ms,
            .sampling_strategy = .trace_id_ratio,
            .sampling_rate = Constants.TelemetryDefaults.high_throughput_sampling_rate,
        };
    }

    /// Returns development telemetry configuration (file-based, detailed).
    pub fn development() TelemetryConfig {
        return .{
            .enabled = true,
            .provider = .file,
            .exporter_file_path = "telemetry_spans.jsonl",
            .span_processor_type = .simple,
            .sampling_strategy = .always_on,
        };
    }

    /// Returns a copy with a metric export format and path configured.
    pub fn withMetricExport(self: TelemetryConfig, format: MetricFormat, path: []const u8) TelemetryConfig {
        var cfg = self;
        cfg.metric_format = format;
        cfg.metrics_file_path = path;
        return cfg;
    }

    /// Returns a copy configured for JSON metrics at the given path.
    pub fn withJsonMetrics(self: TelemetryConfig, path: []const u8) TelemetryConfig {
        return self.withMetricExport(.json, path);
    }

    /// Returns a copy configured for Prometheus metrics at the given path.
    pub fn withPrometheusMetrics(self: TelemetryConfig, path: []const u8) TelemetryConfig {
        return self.withMetricExport(.prometheus, path);
    }

    /// Returns a copy that prefixes exported metric names.
    pub fn withMetricPrefix(self: TelemetryConfig, prefix: []const u8) TelemetryConfig {
        var cfg = self;
        cfg.metric_prefix = prefix;
        return cfg;
    }

    /// Returns a copy that controls metric name sanitization.
    pub fn withMetricNameSanitization(self: TelemetryConfig, enabled: bool) TelemetryConfig {
        var cfg = self;
        cfg.sanitize_metric_names = enabled;
        return cfg;
    }

    /// Alias for `withMetricPrefix`.
    pub const metricPrefix = withMetricPrefix;
    pub const prefixedMetrics = withMetricPrefix;

    /// Alias for `withPrometheusMetrics`.
    pub const prometheusMetrics = withPrometheusMetrics;

    /// Alias for `withJsonMetrics`.
    pub const jsonMetrics = withJsonMetrics;
};
