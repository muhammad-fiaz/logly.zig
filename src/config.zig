//! Logger configuration.
//!
//! All settings live in Config; use presets like .production() to start.
const std = @import("std");
const Level = @import("level.zig").Level;
const Constants = @import("constants.zig");
const ThreadPool = @import("thread_pool.zig").ThreadPool;
const Utils = @import("utils.zig");
const Color = @import("color.zig");

/// Configuration options for the Logger.
pub const Config = struct {
    /// Minimum log level. Only logs at this level or higher will be processed.
    level: Level = .info,

    /// Explicit Io handle. When null, uses default stateless Io.
    io: ?std.Io = null,

    /// Global display controls for all sinks.
    globalColorDisplay: bool = true,
    globalConsoleDisplay: bool = true,
    globalFileStorage: bool = true,

    /// Enable or disable ANSI color codes in output.
    color: bool = true,

    /// How colors apply to rendered records.
    ///
    /// - `.none`: no terminal colors (same as `color = false` for rendering).
    /// - `.horizontal`: the resolved level color applies to the complete record.
    /// - `.vertical`: configured column colors apply per field; the level
    ///   field uses the resolved level color unless `columnColors.level` is set.
    ///
    /// Precedence: `color == false` or `globalColorDisplay == false` disables
    /// all coloring first; then `colorMode`; then column colors; then level
    /// colors; then defaults. JSON output uses horizontal whole-block coloring
    /// only, so column colors do not affect JSON validity.
    colorMode: ColorMode = .horizontal,

    /// Per-column tint colors for `.vertical` mode.
    ///
    /// Unset columns render uncolored (except `level`, which falls back to
    /// the resolved level color). All values are tint `Color`s processed by
    /// `tint.zig`; no other color representation is used.
    columnColors: ColumnColors = .{},

    /// Check for updates on startup.
    /// Output format selection. Each sink renders exactly one format: a
    /// null per-sink format inherits this logger-wide value, so there are
    /// never competing flags to resolve.
    format: Format = .text,
    /// Pretty-print JSON document output (applies to .json file documents).
    prettyJson: bool = false,
    tamperEvident: bool = false,

    /// Custom format string for log messages.
    /// Available placeholders: {time}, {level}, {message}, {module}, {function}, {file}, {line},
    /// {trace_id}, {span_id}, {caller}, {thread}
    logFormat: ?[]const u8 = null,

    /// Timestamp format. Named presets: `"ISO8601"`, `"RFC3339"`, `"unix"`,
    /// `"unix_ms"`, `"default"`. Any separator is allowed in a custom pattern.
    ///
    /// | Token | Meaning      | Token  | Meaning          |
    /// |-------|--------------|--------|------------------|
    /// | YYYY  | year, 4-digit| SSS    | millisecond      |
    /// | YY    | year, 2-digit| ZZZ    | offset, +05:30   |
    /// | MM/M  | month        | ZZ     | offset, +0530    |
    /// | DD/D  | day          | HH/hh  | hour 24h / 12h   |
    /// | mm    | minute       | ss     | second           |
    ///
    /// e.g. `"YYYY-MM-DD HH:mm:ss.SSS"` (default), `"DD/MM/YYYY hh:mm:ss"`,
    /// `"HH:mm:ss"`, `"YYYY-MM-DD HH:mm:ss ZZZ"`.
    ///
    /// Prefer the `Config.TimeFormat.*` constants in application code.
    timeFormat: []const u8 = Constants.TimeConstants.defaultTimePattern,

    /// Timezone for timestamp formatting.
    timezone: Timezone = .local,

    /// Display options for metadata in log output.
    console: bool = true,
    showTime: bool = true,
    showModule: bool = true,
    showFunction: bool = false,
    showFilename: bool = false,
    showLineno: bool = false,
    showThreadId: bool = false,
    showProcessId: bool = false,

    /// Include hostname in logs (useful for distributed systems).
    includeHostname: bool = false,

    /// Include process ID in logs.
    includePid: bool = false,

    /// Include trace ID in logs (useful for distributed tracing).
    includeTraceId: bool = false,

    /// Capture stack traces for Error and Critical log levels.
    /// If false, stack traces will not be collected or displayed.
    captureStackTrace: bool = false,

    /// Resolve memory addresses in stack traces to function names and file locations.
    /// Requires `capture_stack_trace` to be true (or implicit capture for Error/Critical).
    /// This provides human-readable stack traces but has a performance cost.
    symbolizeStackTrace: bool = false,

    /// Automatically flush sinks after every log operation.
    /// Creates immediate output but significantly impacts performance in high-throughput applications.
    /// Default: false (for performance). Set to true only when immediate output visibility is critical.
    autoFlush: bool = false,

    /// Automatically add a console sink on logger initialization.
    /// Only creates sink when both auto_sink=true and global_console_display=true.
    autoSink: bool = true,

    /// Enable callback invocation for log events.
    /// Default: false (for performance). Enable only when using log callbacks.
    enableCallbacks: bool = false,

    /// Enable exception/error handling within the logger.
    enableExceptionHandling: bool = true,

    /// Enable version checking (for update notifications).
    enableVersionCheck: bool = false,

    /// Debug mode for internal logger diagnostics.
    debugMode: bool = false,

    /// Path for internal debug log file.
    debugLogFile: ?[]const u8 = null,

    /// Sampling configuration for high-throughput scenarios.
    sampling: SamplingConfig = .{},

    /// Rate limiting configuration to prevent log flooding.
    rateLimit: RateLimitConfig = .{},

    /// Redaction settings for sensitive data.
    redaction: RedactionConfig = .{},

    /// Error handling behavior.
    errorHandling: ErrorHandling = .logAndContinue,

    /// Maximum message length (truncate if exceeded).
    maxMessageLength: ?usize = null,

    /// Enable structured logging with automatic context propagation.
    structured: bool = false,

    /// Default context fields to include with every log.
    defaultFields: ?[]const DefaultField = null,

    /// Application name for identification in distributed systems.
    appName: ?[]const u8 = null,

    /// Application version for tracing.
    appVersion: ?[]const u8 = null,

    /// Environment identifier (e.g., "production", "staging", "development").
    environment: ?[]const u8 = null,

    /// Stack size for capturing stack traces (default 1MB).
    stackSize: usize = Constants.ConfigDefaults.stackSize,

    /// Enable distributed tracing support.
    enableTracing: bool = false,

    /// Trace ID header name for distributed tracing.
    traceHeader: []const u8 = Constants.ConfigDefaults.distributedTraceHeader,

    /// Enable metrics collection.
    enableMetrics: bool = false,

    /// Metrics configuration.
    metrics: MetricsConfig = .{},

    /// Buffer configuration for async operations.
    bufferConfig: BufferConfig = .{},

    /// Async logging configuration.
    asyncConfig: AsyncConfig = .{},

    /// Rules system configuration.
    rules: RulesConfig = .{},

    /// Thread pool configuration.
    threadPool: ThreadPoolConfig = .{},

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
    logsRootPath: ?[]const u8 = null,

    /// Custom format structure configuration.
    formatStructure: FormatStructureConfig = .{},

    /// Level-specific color customization.
    levelColors: LevelColorConfig = .{},

    /// Distributed systems configuration.
    distributed: DistributedConfig = .{},

    /// Highlighter and alert configuration.
    highlighters: HighlighterConfig = .{},

    /// Log record output format.
    ///
    /// Core set only: plain text, JSON document, JSON lines, logfmt,
    /// syslog (RFC5424 and BSD), MessagePack, plus template customization
    /// of text output through Config.logFormat. Each sink renders exactly
    /// one format value; SinkConfig.format overrides this logger-wide
    /// selection per sink (null inherits).
    pub const Format = enum {
        /// Human-readable text with optional color and custom templates.
        text,
        /// JSON document (array framing for file sinks).
        json,
        /// JSON Lines: one object per line for streaming.
        ndjson,
        /// Logfmt key=value pairs for human-readable structured logging.
        logfmt,
        /// RFC5424 syslog framing with UTC RFC3339 timestamps.
        syslog,
        /// RFC3164 (BSD) syslog framing.
        syslog3164,
        /// Binary MessagePack records with length framing on streams.
        msgpack,

        /// Parses a format name (case-insensitive). Pretty printing is not
        /// a format value: it stays the separate prettyJson modifier on
        /// .json document output.
        pub fn fromString(s: []const u8) ?Format {
            if (std.ascii.eqlIgnoreCase(s, "text")) return .text;
            if (std.ascii.eqlIgnoreCase(s, "json")) return .json;
            if (std.ascii.eqlIgnoreCase(s, "ndjson") or std.ascii.eqlIgnoreCase(s, "jsonlines") or std.ascii.eqlIgnoreCase(s, "json_lines")) return .ndjson;
            if (std.ascii.eqlIgnoreCase(s, "logfmt")) return .logfmt;
            if (std.ascii.eqlIgnoreCase(s, "syslog")) return .syslog;
            if (std.ascii.eqlIgnoreCase(s, "syslog3164") or std.ascii.eqlIgnoreCase(s, "bsd") or std.ascii.eqlIgnoreCase(s, "rfc3164")) return .syslog3164;
            if (std.ascii.eqlIgnoreCase(s, "msgpack") or std.ascii.eqlIgnoreCase(s, "messagepack")) return .msgpack;
            return null;
        }

        /// Whether this format is line-delimited text (one record per line).
        pub fn isLineDelimited(self: Format) bool {
            return switch (self) {
                .text, .ndjson, .logfmt, .syslog, .syslog3164 => true,
                .json, .msgpack => false,
            };
        }

        /// Whether this format is binary (never receives ANSI color or a
        /// text line terminator).
        pub fn isBinary(self: Format) bool {
            return self == .msgpack;
        }
    };

    /// Named time-format presets and identifiers.
    ///
    /// Use these constants instead of string literals to keep configuration
    /// values centralized and avoid typos in production code.
    pub const TimeFormat = struct {
        /// Default human-readable pattern.
        pub const defaultPattern: []const u8 = Constants.TimeConstants.defaultTimePattern;
        /// Alias that resolves to `default_pattern` in the formatter.
        pub const defaultAlias: []const u8 = "default";
        /// ISO 8601 timestamp format.
        pub const iso8601: []const u8 = "ISO8601";
        /// RFC 3339 timestamp format.
        pub const rfc3339: []const u8 = "RFC3339";
        /// Unix timestamp in seconds.
        pub const unix: []const u8 = "unix";
        /// Unix timestamp in milliseconds.
        pub const unixMs: []const u8 = "unix_ms";
    };

    /// Custom log format structure configuration.
    pub const FormatStructureConfig = struct {
        /// Prefix to add before each log message (e.g., ">>> ").
        messagePrefix: ?[]const u8 = null,

        /// Suffix to add after each log message (e.g., " <<<").
        messageSuffix: ?[]const u8 = null,

        /// Separator between log fields/components.
        fieldSeparator: []const u8 = " | ",

        /// Enable nested/hierarchical formatting for structured logs.
        enableNesting: bool = false,

        /// Indentation for nested fields (spaces or tabs).
        nestingIndent: []const u8 = "  ",

        /// Custom field order: which fields appear first in output.
        /// If null, uses default order: [time, level, message, context].
        fieldOrder: ?[]const []const u8 = null,

        /// Whether to include empty/null fields in output.
        includeEmptyFields: bool = false,

        /// Custom placeholder prefix/suffix (default: {}, can be changed to [[]], etc.)
        placeholderOpen: []const u8 = "{",
        placeholderClose: []const u8 = "}",
    };

    /// Distributed configuration for microservices and cluster environments.
    pub const DistributedConfig = struct {
        /// Enable distributed logging features.
        enabled: bool = false,

        /// Service name/Application identifier.
        serviceName: ?[]const u8 = null,

        /// Service version/Semantic version of the running artifact.
        serviceVersion: ?[]const u8 = null,

        /// Environment name (e.g., "prod", "staging", "dev").
        environment: ?[]const u8 = null,

        /// Datacenter or Availability Zone identifier (e.g., "us-east-1a").
        datacenter: ?[]const u8 = null,

        /// Region identifier (e.g., "us-east-1").
        region: ?[]const u8 = null,

        /// Unique Instance ID (e.g., Kubernetes Pod ID, EC2 Instance ID).
        instanceId: ?[]const u8 = null,

        /// HTTP header name for Trace ID propagation.
        traceHeader: []const u8 = Constants.ConfigDefaults.distributedTraceHeader,

        /// HTTP header name for Span ID propagation.
        spanHeader: []const u8 = Constants.ConfigDefaults.distributedSpanHeader,

        /// HTTP header name for Parent Span ID propagation.
        parentHeader: []const u8 = Constants.ConfigDefaults.distributedParentHeader,

        /// HTTP header name for Baggage/Correlation Context.
        baggageHeader: []const u8 = Constants.ConfigDefaults.distributedBaggageHeader,

        /// Sampling rate for distributed tracing (0.0 to 1.0).
        traceSamplingRate: f64 = 1.0,

        /// Optional callback when a new trace is initialized.
        onTraceCreated: ?*const fn (traceId: []const u8) void = null,

        /// Optional callback when a new span is started.
        onSpanCreated: ?*const fn (spanId: []const u8, name: []const u8) void = null,
    };

    /// Per-level color customization, backed by tint.zig.
    ///
    /// Terminal color rendering mode.
    pub const ColorMode = enum {
        /// No colors.
        none,
        /// One level color for the whole record.
        horizontal,
        /// Independent colors per formatted field.
        vertical,
    };

    /// Per-field tint colors for vertical mode. All fields optional.
    pub const ColumnColors = struct {
        timestamp: ?Color.Color = null,
        level: ?Color.Color = null,
        module: ?Color.Color = null,
        function: ?Color.Color = null,
        filename: ?Color.Color = null,
        line: ?Color.Color = null,
        message: ?Color.Color = null,
        context: ?Color.Color = null,
    };

    /// Per-level color customization, backed by tint.zig.
    ///
    /// Stores tint `Color` values (plain data, no allocation). Per-level
    /// overrides take precedence over the selected theme preset. Render via
    /// `color.sequence(color, capability)` and write `Sequence.slice()`.
    pub const LevelColorConfig = struct {
        /// Theme preset to use as base colors.
        /// Individual color overrides below will take precedence over theme colors.
        themePreset: ThemePreset = .default,

        /// Custom color for TRACE level (null = use theme default).
        traceColor: ?Color.Color = null,

        /// Custom color for DEBUG level.
        debugColor: ?Color.Color = null,

        /// Custom color for INFO level.
        infoColor: ?Color.Color = null,

        /// Custom color for NOTICE level.
        noticeColor: ?Color.Color = null,

        /// Custom color for SUCCESS level.
        successColor: ?Color.Color = null,

        /// Custom color for WARNING level.
        warningColor: ?Color.Color = null,

        /// Custom color for ERROR level.
        errorColor: ?Color.Color = null,

        /// Custom color for FAIL level.
        failColor: ?Color.Color = null,

        /// Custom color for CRITICAL level.
        criticalColor: ?Color.Color = null,

        /// Custom color for FATAL level.
        fatalColor: ?Color.Color = null,

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
        ///
        /// Returns a tint `Color` value. The `.none` preset yields the
        /// terminal default color. No allocation; safe to call per record.
        pub fn getColorForLevel(self: LevelColorConfig, level: Level) Color.Color {
            if (self.getOverrideForLevel(level)) |color| return color;
            return themeColor(self.themePreset, level);
        }

        /// Returns the explicit per-level color override, if one is configured.
        pub fn getOverrideForLevel(self: LevelColorConfig, level: Level) ?Color.Color {
            return switch (level) {
                .trace => self.traceColor,
                .debug => self.debugColor,
                .info => self.infoColor,
                .notice => self.noticeColor,
                .success => self.successColor,
                .warning => self.warningColor,
                .err => self.errorColor,
                .fail => self.failColor,
                .critical => self.criticalColor,
                .fatal => self.fatalColor,
            };
        }

        /// Returns true when a level has an explicit per-level color override.
        pub fn hasOverrideForLevel(self: LevelColorConfig, level: Level) bool {
            return self.getOverrideForLevel(level) != null;
        }

        /// Returns true when the color configuration is still using the default theme.
        pub fn usesDefaultTheme(self: LevelColorConfig) bool {
            return self.themePreset == .default;
        }

        /// Returns true when no explicit theme or per-level override is configured.
        pub fn isDefault(self: LevelColorConfig) bool {
            return self.usesDefaultTheme() and
                self.traceColor == null and
                self.debugColor == null and
                self.infoColor == null and
                self.noticeColor == null and
                self.successColor == null and
                self.warningColor == null and
                self.errorColor == null and
                self.failColor == null and
                self.criticalColor == null and
                self.fatalColor == null;
        }

        /// Theme palette: the base `Color` for a preset and level.
        fn themeColor(preset: ThemePreset, level: Level) Color.Color {
            const ansi4 = Color.Tint.color.ansi4;
            const ansi256 = Color.Tint.color.ansi256;
            return switch (preset) {
                .default => Color.levelColor(level),
                .bright => switch (level) {
                    .trace => ansi4.brightCyan,
                    .debug => ansi4.brightBlue,
                    .info => ansi4.brightWhite,
                    .notice => ansi4.brightCyan,
                    .success => ansi4.brightGreen,
                    .warning => ansi4.brightYellow,
                    .err => ansi4.brightRed,
                    .fail => ansi4.brightMagenta,
                    .critical => ansi4.brightRed,
                    .fatal => ansi4.brightWhite,
                },
                .dim => Color.levelColor(level),
                .minimal => switch (level) {
                    .trace, .debug => ansi4.brightBlack,
                    .info, .notice, .success => ansi4.white,
                    .warning => ansi4.yellow,
                    .err, .fail => ansi4.red,
                    .critical, .fatal => ansi4.brightRed,
                },
                .neon => switch (level) {
                    .trace => ansi256.index(51),
                    .debug => ansi256.index(33),
                    .info => ansi256.index(255),
                    .notice => ansi256.index(123),
                    .success => ansi256.index(46),
                    .warning => ansi256.index(226),
                    .err => ansi256.index(196),
                    .fail => ansi256.index(201),
                    .critical => ansi256.index(196),
                    .fatal => ansi256.index(231),
                },
                .pastel => switch (level) {
                    .trace => ansi256.index(159),
                    .debug => ansi256.index(117),
                    .info => ansi256.index(188),
                    .notice => ansi256.index(153),
                    .success => ansi256.index(157),
                    .warning => ansi256.index(222),
                    .err => ansi256.index(210),
                    .fail => ansi256.index(218),
                    .critical => ansi256.index(203),
                    .fatal => ansi256.index(231),
                },
                .dark => switch (level) {
                    .trace => ansi256.index(244),
                    .debug => ansi256.index(75),
                    .info => ansi256.index(252),
                    .notice => ansi256.index(81),
                    .success => ansi256.index(114),
                    .warning => ansi256.index(220),
                    .err => ansi256.index(203),
                    .fail => ansi256.index(168),
                    .critical => ansi256.index(196),
                    .fatal => ansi256.index(231),
                },
                .light => switch (level) {
                    .trace => ansi256.index(242),
                    .debug => ansi256.index(24),
                    .info => ansi256.index(235),
                    .notice => ansi256.index(30),
                    .success => ansi256.index(28),
                    .warning => ansi256.index(130),
                    .err => ansi256.index(124),
                    .fail => ansi256.index(127),
                    .critical => ansi256.index(160),
                    .fatal => ansi256.index(160),
                },
                .none => ansi4.default,
            };
        }
    };

    /// Highlighter patterns and alert configuration.
    pub const HighlighterConfig = struct {
        /// Enable highlighter system.
        enabled: bool = false,

        /// Pattern-based highlighters.
        patterns: ?[]const HighlightPattern = null,

        /// Alert callbacks for matched patterns.
        alertOnMatch: bool = false,

        /// Severity level that triggers alerts.
        alertMinSeverity: AlertSeverity = .warning,

        /// Custom callback function name for alerts (optional).
        alertCallback: ?[]const u8 = null,

        /// Maximum number of highlighter matches to track per message.
        maxMatchesPerMessage: usize = 10,

        /// Whether to log highlighter matches as separate records.
        logMatches: bool = false,

        /// Severity attached to an alert record.
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

        /// Literal or pattern match used to highlight log text.
        pub const HighlightPattern = struct {
            /// Pattern name/label.
            name: []const u8,

            /// Pattern to match (regex or substring).
            pattern: []const u8,

            /// Is this a regex pattern (true) or substring match (false)?
            isRegex: bool = false,

            /// Highlight color (tint value; rendered via `Color.sequence`).
            highlightColor: Color.Color = Color.Tint.color.ansi4.brightYellow,

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
        bypassLevels: ?@import("level.zig").LevelMask = null,

        /// Sampling strategy configuration.
        pub const Strategy = union(enum) {
            /// Allow all records through (no sampling).
            none: void,

            /// Random probability-based sampling.
            /// Value is the probability (0.0 to 1.0) of allowing a record.
            probability: f64,

            /// Rate limiting: allow N records per time window.
            rateLimit: SamplingRateLimitConfig,

            /// Sample 1 out of every N records.
            everyN: u32,

            /// Adaptive sampling based on throughput.
            adaptive: AdaptiveConfig,

            /// Token bucket rate limiting (allows initial bursts).
            tokenBucket: TokenBucketConfig,
        };

        /// Configuration for rate limiting strategy.
        pub const SamplingRateLimitConfig = struct {
            /// Maximum records allowed per window.
            maxRecords: u32,
            /// Time window in milliseconds.
            windowMs: u64,
        };

        /// Configuration for adaptive sampling strategy.
        ///
        /// Automatically adjusts the sampling rate based on the current
        /// record throughput to maintain a target rate.
        pub const AdaptiveConfig = struct {
            /// Target records per second.
            targetRate: u32,
            /// Minimum sample rate (don't drop below this).
            minSampleRate: f64 = Constants.SamplingDefaults.adaptiveMinRate,
            /// Maximum sample rate (don't go above this).
            maxSampleRate: f64 = Constants.SamplingDefaults.adaptiveMaxRate,
            /// How often to adjust rate (milliseconds).
            adjustmentIntervalMs: u64 = Constants.SamplingDefaults.adaptiveAdjustmentIntervalMs,
        };

        /// Configuration for token bucket rate limiting strategy.
        ///
        /// The token bucket algorithm facilitates burstable sampling operations by allowing
        /// transient spikes in log throughput while enforcing a long-term average rate limit.
        pub const TokenBucketConfig = struct {
            /// Maximum capacity of the token bucket, representing the permissible burst size.
            burstCapacity: u32,
            /// Steady-state replenishment rate for the token bucket (tokens accrued per second).
            refillRatePerSec: u32,
        };
    };

    /// Rate limiting configuration.
    /// Rate limiting configuration for loggers (not sampling).
    pub const RateLimitConfig = struct {
        /// Enable rate limiting.
        enabled: bool = false,
        /// Maximum requests per second.
        maxPerSecond: u32 = Constants.RateLimitDefaults.maxPerSecond,
        /// Burst size (token bucket capacity).
        burstSize: u32 = Constants.RateLimitDefaults.burstSize,
        /// Whether to apply limits per log level independently.
        perLevel: bool = false,
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
        defaultType: RedactionType = .full,
        /// Enable regex pattern matching.
        enableRegex: bool = false,
        /// Hash algorithm for hash redaction type.
        hashAlgorithm: HashAlgorithm = .sha256,
        /// Characters to reveal at start for partial redaction.
        partialStartChars: u8 = Constants.RedactionDefaults.partialStartChars,
        /// Characters to reveal at end for partial redaction.
        partialEndChars: u8 = Constants.RedactionDefaults.partialEndChars,
        /// Mask character for redacted content.
        maskChar: u8 = Constants.RedactionDefaults.maskChar,
        /// Max characters to keep when using truncate redaction.
        truncateLength: usize = Constants.RedactionDefaults.truncateLength,
        /// Suffix appended when values are truncated.
        truncateSuffix: []const u8 = Constants.RedactionDefaults.truncateSuffix,
        /// Enable case-insensitive field matching.
        caseInsensitive: bool = true,
        /// Log when redaction is applied (for audit).
        auditRedactions: bool = false,
        /// Compliance preset to use (null for custom).
        compliancePreset: ?CompliancePreset = null,

        /// Enum defining the method used for redacting content.
        pub const RedactionType = enum {
            /// Replaces the entire value with "[REDACTED]" or similar.
            full,
            /// Shows the start of the string, masking the rest.
            partialStart,
            /// Shows the end of the string, masking the beginning.
            partialEnd,
            /// Replaces the value with a cryptographic hash.
            hash,
            /// Masks the middle part of the string (e.g. for credit cards).
            maskMiddle,
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
            pciDss,
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
        pub fn default() RedactionConfig {
            return .{};
        }

        /// Returns redaction settings compliant with PCI-DSS standards.
        /// Enables middle masking for credit cards etc.
        pub fn pciDss() RedactionConfig {
            return .{
                .enabled = true,
                .compliancePreset = .pciDss,
                .defaultType = .maskMiddle,
                .auditRedactions = true,
            };
        }

        /// Returns redaction settings compliant with HIPAA standards.
        /// Uses secure hashing (SHA-256) for identifiers.
        pub fn hipaa() RedactionConfig {
            return .{
                .enabled = true,
                .compliancePreset = .hipaa,
                .defaultType = .hash,
                .hashAlgorithm = .sha256,
                .auditRedactions = true,
            };
        }

        /// Returns redaction settings compliant with GDPR.
        /// Uses partial redaction to balance utility and privacy.
        pub fn gdpr() RedactionConfig {
            return .{
                .enabled = true,
                .compliancePreset = .gdpr,
                .defaultType = .partialEnd,
            };
        }

        /// Returns strict redaction settings (full redaction).
        /// Case-insensitive matching enabled.
        pub fn strict() RedactionConfig {
            return .{
                .enabled = true,
                .defaultType = .full,
                .caseInsensitive = true,
                .auditRedactions = true,
            };
        }
    };

    /// Error handling behavior.
    pub const ErrorHandling = enum {
        silent,
        logAndContinue,
        failFast,
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
        flushIntervalMs: u64 = Constants.TimeDefaults.flushIntervalMs,
        maxPending: usize = Constants.Limits.maxAsyncQueueSize,
        overflowStrategy: OverflowStrategy = .dropOldest,

        /// What to do when a buffer or queue is full.
        pub const OverflowStrategy = enum {
            dropOldest,
            dropNewest,
            block,
        };
    };

    /// Thread pool configuration.
    pub const ThreadPoolConfig = struct {
        /// Enable thread pool for parallel processing.
        enabled: bool = false,
        /// Explicit Io handle for pool synchronization. When null, uses default stateless Io.
        io: ?std.Io = null,
        /// Number of worker threads (0 = auto-detect based on CPU cores).
        threadCount: usize = Constants.ThreadDefaults.threadCount,
        /// Maximum queue size for pending tasks.
        queueSize: usize = Constants.ThreadDefaults.maxTasks,
        /// Stack size per thread in bytes.
        stackSize: usize = Constants.ThreadDefaults.stackSize,
        /// Enable work stealing between threads.
        workStealing: bool = true,
        /// Thread naming prefix.
        threadNamePrefix: []const u8 = Constants.ThreadDefaults.threadNamePrefix,
        /// Keep alive time for idle threads (milliseconds).
        keepAliveMs: u64 = Constants.TimeConstants.secondsPerMinute * Constants.TimeConstants.msPerSecond,
        /// Enable thread affinity (pin threads to CPUs).
        threadAffinity: bool = false,

        /// Returns a thread-pool configuration optimized for general use.
        pub fn default() ThreadPoolConfig {
            return .{};
        }

        /// Returns a thread-pool configuration for sustained logging throughput.
        pub fn highThroughput() ThreadPoolConfig {
            return .{
                .enabled = true,
                .threadCount = Constants.ThreadDefaults.threadCount,
                .queueSize = Constants.ThreadDefaults.maxTasks,
                .stackSize = Constants.ThreadDefaults.highThroughputStackSize,
                .workStealing = true,
            };
        }

        /// Returns a thread-pool configuration for disk and network-heavy logging.
        pub fn ioBound() ThreadPoolConfig {
            return .{
                .enabled = true,
                .threadCount = Constants.ThreadDefaults.ioBoundThreadCount(),
                .queueSize = Constants.ThreadDefaults.ioBoundQueueSize,
                .workStealing = true,
            };
        }

        /// Returns a thread-pool configuration for CPU-heavy formatting/compression.
        pub fn cpuBound() ThreadPoolConfig {
            return .{
                .enabled = true,
                .threadCount = Constants.ThreadDefaults.cpuBoundThreadCount(),
                .queueSize = Constants.ThreadDefaults.queueSize,
                .workStealing = false,
            };
        }

        /// Returns a small thread-pool configuration for constrained targets.
        pub fn lowResource() ThreadPoolConfig {
            return .{
                .enabled = true,
                .threadCount = Constants.ThreadDefaults.lowLatencyThreadCount,
                .queueSize = Constants.ThreadDefaults.queueSizeLow,
                .stackSize = Constants.ThreadDefaults.lowResourceStackSize,
                .workStealing = false,
            };
        }

        /// Returns a copy with the worker count changed.
        pub fn withThreadCount(self: ThreadPoolConfig, count: usize) ThreadPoolConfig {
            var cfg = self;
            cfg.threadCount = count;
            cfg.enabled = true;
            return cfg;
        }

        /// Returns a copy with queue size changed.
        pub fn withQueueSize(self: ThreadPoolConfig, size: usize) ThreadPoolConfig {
            var cfg = self;
            cfg.queueSize = size;
            return cfg;
        }
    };

    /// Parallel sink writing configuration.
    pub const ParallelConfig = struct {
        /// Maximum concurrent writes allowed at once.
        maxConcurrent: usize = Constants.ParallelDefaults.maxConcurrent,
        /// Timeout for each write operation (ms).
        writeTimeoutMs: u64 = Constants.ParallelDefaults.writeTimeoutMs,
        /// Retry failed writes automatically.
        retryOnFailure: bool = true,
        /// Maximum number of retry attempts.
        maxRetries: u3 = Constants.ParallelDefaults.maxRetries,
        /// Fail-fast mode: abort on any sink error.
        failFast: bool = false,
        /// Buffer writes before parallel dispatch.
        buffered: bool = true,
        /// Buffer size for buffered writes.
        bufferSize: usize = Constants.ParallelDefaults.bufferSize,

        /// Returns default parallel configuration.
        pub fn default() ParallelConfig {
            return .{};
        }

        /// Returns configuration optimized for high throughput.
        /// Increases concurrency and buffering, disables retries.
        pub fn highThroughput() ParallelConfig {
            return .{
                .maxConcurrent = Constants.ParallelDefaults.highThroughputMaxConcurrent,
                .buffered = true,
                .bufferSize = Constants.ParallelDefaults.highThroughputBufferSize,
                .retryOnFailure = false,
                .failFast = false,
            };
        }

        /// Returns configuration optimized for low latency.
        /// Low concurrency, no buffering, short timeouts.
        pub fn lowLatency() ParallelConfig {
            return .{
                .maxConcurrent = Constants.ParallelDefaults.lowLatencyMaxConcurrent,
                .buffered = false,
                .writeTimeoutMs = Constants.ParallelDefaults.lowLatencyTimeoutMs,
                .retryOnFailure = false,
                .failFast = true,
            };
        }

        /// Returns configuration optimized for reliability.
        /// Enabled retries and longer timeouts.
        pub fn reliable() ParallelConfig {
            return .{
                .maxConcurrent = Constants.ParallelDefaults.reliableMaxConcurrent,
                .retryOnFailure = true,
                .maxRetries = Constants.ParallelDefaults.reliableMaxRetries,
                .writeTimeoutMs = Constants.ParallelDefaults.reliableTimeoutMs,
                .failFast = false,
            };
        }
    };

    /// Scheduler configuration.
    pub const SchedulerConfig = struct {
        /// Optional explicit I/O handle. If null, single-threaded standard I/O is used.
        io: ?std.Io = null,
        /// Enable the scheduler.
        enabled: bool = false,
        /// Default cleanup max age in days.
        cleanupMaxAgeDays: u64 = Constants.SchedulerDefaults.maxAgeSeconds / Constants.TimeConstants.secondsPerDay,
        /// Default max files to keep.
        maxFiles: ?usize = null,
        /// Enable compression before cleanup.
        compressBeforeCleanup: bool = false,
        /// Default file pattern for cleanup.
        filePattern: []const u8 = "*.log",
        /// Root directory for compressed/archived files.
        archiveRootDir: ?[]const u8 = null,
        /// Create date-based subdirectories (YYYY/MM/DD).
        createDateSubdirs: bool = false,
        /// Compression algorithm for scheduled compression tasks.
        compressionAlgorithm: CompressionConfig.CompressionAlgorithm = .gzip,
        /// Compression level for scheduled tasks.
        compressionLevel: CompressionConfig.CompressionLevel = .default,
        /// Keep original files after scheduled compression.
        keepOriginals: bool = false,
        /// Custom prefix for archived file names.
        archiveFilePrefix: ?[]const u8 = null,
        /// Custom suffix for archived file names.
        archiveFileSuffix: ?[]const u8 = null,
        /// Preserve directory structure in archive root.
        preserveDirStructure: bool = true,
        /// Delete empty directories after cleanup.
        cleanEmptyDirs: bool = false,
        /// Minimum file age in days before compression.
        minAgeDaysForCompression: u64 = 1,
        /// Maximum concurrent compression tasks.
        maxConcurrentCompressions: usize = 2,

        /// Returns scheduler settings for routine log maintenance.
        pub fn maintenance(logsPath: []const u8) SchedulerConfig {
            return .{
                .enabled = true,
                .filePattern = "*.log",
                .archiveRootDir = logsPath,
                .compressBeforeCleanup = true,
                .cleanEmptyDirs = true,
            };
        }

        /// Returns a copy configured for cleanup after `days`.
        pub fn withCleanupDays(self: SchedulerConfig, days: u64) SchedulerConfig {
            var cfg = self;
            cfg.enabled = true;
            cfg.cleanupMaxAgeDays = days;
            return cfg;
        }

        /// Returns a copy configured to keep at most `count` files.
        pub fn withMaxFiles(self: SchedulerConfig, count: usize) SchedulerConfig {
            var cfg = self;
            cfg.enabled = true;
            cfg.maxFiles = count;
            return cfg;
        }

        /// Returns a copy with scheduled compression enabled.
        pub fn withCompression(self: SchedulerConfig, algorithm: CompressionConfig.CompressionAlgorithm) SchedulerConfig {
            var cfg = self;
            cfg.enabled = true;
            cfg.compressBeforeCleanup = true;
            cfg.compressionAlgorithm = algorithm;
            return cfg;
        }
    };

    /// Metrics collection configuration.
    pub const MetricsConfig = struct {
        /// Enable metrics collection.
        enabled: bool = false,
        /// Track per-level counts.
        trackLevels: bool = true,
        /// Track per-sink metrics.
        trackSinks: bool = true,
        /// Calculate throughput (records/sec, bytes/sec).
        trackThroughput: bool = true,
        /// Track latency statistics.
        trackLatency: bool = false,
        /// Snapshot interval in milliseconds (0 = disabled).
        snapshotIntervalMs: u64 = 0,
        /// Alert threshold for error rate (0.0-1.0, 0 = disabled).
        errorRateThreshold: f32 = 0.0,
        /// Alert threshold for drop rate (0.0-1.0, 0 = disabled).
        dropRateThreshold: f32 = 0.0,
        /// Maximum records/sec before alerting (0 = disabled).
        maxRecordsPerSecond: u64 = 0,
        /// Export format for metrics.
        exportFormat: ExportFormat = .text,
        /// Enable histogram for latency distribution.
        enableHistogram: bool = false,
        /// Number of histogram buckets.
        histogramBuckets: u8 = 10,
        /// Retain metrics history (in snapshots).
        historySize: u16 = 0,
        /// Prefix/namespace used by exported metric names.
        metricPrefix: []const u8 = Constants.MetricsConstants.defaultPrefix,
        /// Separator used when joining metric prefix and metric name.
        metricSeparator: []const u8 = Constants.MetricsConstants.prometheusSeparator,
        /// Separator used by StatsD exports.
        statsdSeparator: []const u8 = Constants.MetricsConstants.statsdSeparator,
        /// Sanitize exported metric names for the target exporter.
        sanitizeNames: bool = Constants.MetricsConstants.sanitizeNames,
        /// Include per-level counters in metrics exports.
        exportLevelBreakdown: bool = Constants.MetricsConstants.includeLevelBreakdown,
        /// Include per-sink counters in metrics exports.
        exportSinkBreakdown: bool = Constants.MetricsConstants.includeSinkBreakdown,

        /// Encoding used when exporting metrics.
        pub const ExportFormat = enum {
            text,
            json,
            prometheus,
            statsd,
        };

        /// Returns default metrics configuration (disabled).
        pub fn default() MetricsConfig {
            return .{};
        }

        /// Returns metrics configuration suitable for production monitoring.
        /// Tracks throughput, levels, and sinks with specific error thresholds.
        pub fn production() MetricsConfig {
            return .{
                .enabled = true,
                .trackLevels = true,
                .trackSinks = true,
                .trackThroughput = true,
                .errorRateThreshold = 0.01,
                .dropRateThreshold = 0.001,
            };
        }

        /// Returns minimal metrics configuration.
        /// Enables system but disables per-level/sink tracking to save memory.
        pub fn minimal() MetricsConfig {
            return .{
                .enabled = true,
                .trackLevels = false,
                .trackSinks = false,
                .trackThroughput = false,
            };
        }

        /// Returns detailed metrics configuration for debugging/profiling.
        /// Enables latency tracking, histograms, and history retention.
        pub fn detailed() MetricsConfig {
            return .{
                .enabled = true,
                .trackLevels = true,
                .trackSinks = true,
                .trackThroughput = true,
                .trackLatency = true,
                .enableHistogram = true,
                .histogramBuckets = 20,
                .historySize = 60,
            };
        }

        /// Returns a copy configured for a specific export format.
        pub fn withExport(self: MetricsConfig, format: ExportFormat) MetricsConfig {
            var cfg = self;
            cfg.enabled = true;
            cfg.exportFormat = format;
            return cfg;
        }

        /// Returns a copy configured for Prometheus export naming.
        pub fn prometheus(self: MetricsConfig) MetricsConfig {
            var cfg = self.withExport(.prometheus);
            cfg.metricSeparator = Constants.MetricsConstants.prometheusSeparator;
            cfg.sanitizeNames = true;
            return cfg;
        }

        /// Returns a copy configured for StatsD export naming.
        pub fn statsd(self: MetricsConfig) MetricsConfig {
            var cfg = self.withExport(.statsd);
            cfg.metricSeparator = cfg.statsdSeparator;
            cfg.sanitizeNames = false;
            return cfg;
        }

        /// Returns a copy with an exported metric prefix/namespace.
        pub fn withPrefix(self: MetricsConfig, metricPrefixValue: []const u8) MetricsConfig {
            var cfg = self;
            cfg.metricPrefix = metricPrefixValue;
            return cfg;
        }

        /// Returns a copy with latency histograms enabled.
        pub fn withLatencyHistogram(self: MetricsConfig, buckets: u8) MetricsConfig {
            var cfg = self;
            cfg.enabled = true;
            cfg.trackLatency = true;
            cfg.enableHistogram = true;
            cfg.histogramBuckets = buckets;
            return cfg;
        }

        /// Returns a copy with error/drop alert thresholds.
        pub fn withAlerts(self: MetricsConfig, errorRate: f32, dropRate: f32) MetricsConfig {
            var cfg = self;
            cfg.enabled = true;
            cfg.errorRateThreshold = errorRate;
            cfg.dropRateThreshold = dropRate;
            return cfg;
        }

        /// Returns a copy with level/sink export breakdowns enabled or disabled.
        pub fn withBreakdowns(self: MetricsConfig, levels: bool, sinks: bool) MetricsConfig {
            var cfg = self;
            cfg.exportLevelBreakdown = levels;
            cfg.exportSinkBreakdown = sinks;
            return cfg;
        }
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
        customZstdLevel: ?i32 = null,
        /// Custom Brotli level (0-11). If set, overrides the level enum for Brotli.
        /// Use this for fine-grained control over Brotli compression levels.
        /// v0.2.1+
        customBrotliLevel: ?i32 = null,
        /// Compress on rotation.
        onRotation: bool = true,
        /// Keep original file after compression.
        keepOriginal: bool = false,
        /// Compression mode.
        mode: Mode = .onRotation,
        /// Size threshold in bytes for on_size_threshold mode.
        sizeThreshold: u64 = Constants.RotationConstants.defaultMaxSize,
        /// Buffer size for streaming compression.
        bufferSize: usize = Constants.BufferSizes.compression,
        /// Compression strategy.
        strategy: Strategy = .default,
        /// File extension for compressed files.
        extension: []const u8 = Constants.RotationConstants.compressedExt,
        /// Delete files older than this after compression (in seconds, 0 = never).
        deleteAfter: u64 = 0,
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
        memoryLimit: usize = 0,
        /// Custom prefix for compressed file names (e.g., "archive_" -> "archive_app.log.gz").
        filePrefix: ?[]const u8 = null,
        /// Custom suffix before extension (e.g., "_compressed" -> "app_compressed.log.gz").
        fileSuffix: ?[]const u8 = null,
        /// Root directory for all compressed files (centralized archive location).
        /// If set, all compressed files will be stored here instead of alongside originals.
        archiveRootDir: ?[]const u8 = null,
        /// Create date-based subdirectories in archive root (YYYY/MM/DD structure).
        createDateSubdirs: bool = false,
        /// Preserve original directory structure when archiving to root dir.
        preserveDirStructure: bool = true,
        /// Custom naming pattern for compressed files.
        /// Placeholders: {base}, {ext}, {date}, {time}, {timestamp}, {index}
        namingPattern: ?[]const u8 = null,
        /// Zstd dictionary for compression.
        zstdDict: ?[]const u8 = null,
        /// Thread pool for asynchronous compression tasks.
        threadPool: ?*ThreadPool = null,

        /// Compression algorithms available for rotated logs.
        pub const CompressionAlgorithm = enum {
            none,
            deflate,
            zlib,
            rawDeflate,
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
            tarGz,
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

        /// Speed/ratio trade-off for compression.
        pub const CompressionLevel = enum {
            none,
            fastest,
            fast,
            default,
            best,

            /// Converts the enum to its corresponding zlib/deflate compression integer level (0-9).
            /// For zstd, use toZstdLevel() instead.
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

        /// Operating mode for a component.
        pub const Mode = enum {
            disabled,
            onRotation,
            onSizeThreshold,
            scheduled,
            streaming,
        };

        pub const Strategy = enum {
            default,
            text,
            binary,
            huffmanOnly,
            rleOnly,
            adaptive,
        };

        /// Returns a minimal compression config with compression enabled.
        /// Use this for the simplest one-liner compression setup.
        ///
        /// Example:
        /// ```zig
        /// const config = Config.default().withCompression(CompressionConfig.enable());
        /// ```
        pub fn enable() CompressionConfig {
            return .{ .enabled = true };
        }

        /// Alias for enable(). Returns a minimal compression config with compression enabled.
        ///
        /// Example:
        /// ```zig
        /// const config = Config.default().withCompression(CompressionConfig.basic());
        /// ```
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
        pub fn implicit() CompressionConfig {
            return .{
                .enabled = true,
                .mode = .onRotation,
                .onRotation = true,
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
        pub fn explicit() CompressionConfig {
            return .{
                .enabled = true,
                .mode = .disabled,
                .onRotation = false,
            };
        }

        /// Returns a streaming compression config.
        /// Compresses data as it's written - useful for real-time compression.
        ///
        /// Example:
        /// ```zig
        /// const config = Config.default().withCompression(CompressionConfig.streaming());
        /// ```
        pub fn streamingMode() CompressionConfig {
            return .{
                .enabled = true,
                .mode = .streaming,
                .streaming = true,
                .onRotation = false,
            };
        }

        /// Returns a background compression config.
        /// Compression runs in a separate thread for non-blocking operation.
        ///
        /// Example:
        /// ```zig
        /// const config = Config.default().withCompression(CompressionConfig.background());
        /// ```
        pub fn backgroundMode() CompressionConfig {
            return .{
                .enabled = true,
                .background = true,
                .onRotation = true,
            };
        }

        /// Returns a fast compression config (prioritize speed over ratio).
        ///
        /// Example:
        /// ```zig
        /// const config = Config.default().withCompression(CompressionConfig.fast());
        /// ```
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
        pub fn forLogs() CompressionConfig {
            return .{
                .enabled = true,
                .level = .default,
                .algorithm = .gzip,
                .strategy = .text,
                .onRotation = true,
            };
        }

        /// Returns a compression config with archival settings (compress + delete original).
        ///
        /// Example:
        /// ```zig
        /// const config = Config.default().withCompression(CompressionConfig.archive());
        /// ```
        pub fn archive() CompressionConfig {
            return .{
                .enabled = true,
                .level = .best,
                .algorithm = .gzip,
                .keepOriginal = false,
                .onRotation = true,
            };
        }

        /// Returns a compression config that keeps originals after compression.
        ///
        /// Example:
        /// ```zig
        /// const config = Config.default().withCompression(CompressionConfig.keepOriginals());
        /// ```
        pub fn keepOriginals() CompressionConfig {
            return .{
                .enabled = true,
                .keepOriginal = true,
                .onRotation = true,
            };
        }

        /// Returns a compression config with size-threshold trigger.
        /// Compresses files when they exceed the specified size.
        ///
        /// Example:
        /// ```zig
        /// const config = Config.default().withCompression(CompressionConfig.onSize(5 * 1024 * 1024)); // 5MB
        /// ```
        pub fn onSize(thresholdBytes: u64) CompressionConfig {
            return .{
                .enabled = true,
                .mode = .onSizeThreshold,
                .sizeThreshold = thresholdBytes,
                .onRotation = false,
            };
        }

        /// Returns a production-ready compression config.
        /// Balanced performance with background processing and checksums.
        ///
        /// Example:
        /// ```zig
        /// const config = Config.default().withCompression(CompressionConfig.production());
        /// ```
        pub fn production() CompressionConfig {
            return .{
                .enabled = true,
                .level = .default,
                .algorithm = .gzip,
                .background = true,
                .checksum = true,
                .onRotation = true,
                .keepOriginal = false,
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
        /// v0.1.5+
        pub fn zstd() CompressionConfig {
            return .{
                .enabled = true,
                .level = .default,
                .algorithm = .zstd,
                .onRotation = true,
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
        /// v0.1.5+
        pub fn zstdFast() CompressionConfig {
            return .{
                .enabled = true,
                .level = .fastest,
                .algorithm = .zstd,
                .onRotation = true,
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
        /// v0.1.5+
        pub fn zstdBest() CompressionConfig {
            return .{
                .enabled = true,
                .level = .best,
                .algorithm = .zstd,
                .onRotation = true,
                .checksum = true,
                .keepOriginal = false,
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
        /// v0.1.5+
        pub fn zstdProduction() CompressionConfig {
            return .{
                .enabled = true,
                .level = .default,
                .algorithm = .zstd,
                .background = true,
                .checksum = true,
                .onRotation = true,
                .keepOriginal = false,
                .extension = Constants.CompressionConstants.ArchivingExtensions.zstd,
            };
        }

        /// Returns a zstd compression config with a custom compression level.
        /// Allows fine-grained control over zstd compression (levels 1-22).
        /// Higher levels provide better compression but slower speed.
        ///
        /// Example:
        /// ```zig
        /// const config = Config.default().withCompression(CompressionConfig.zstdWithLevel(12));
        /// ```
        ///
        /// v0.1.5+
        pub fn zstdWithLevel(customLevel: i32) CompressionConfig {
            // Clamp to valid zstd range (1-22)
            const clampedLevel = std.math.clamp(customLevel, 1, 22);
            return .{
                .enabled = true,
                .level = .default,
                .customZstdLevel = clampedLevel,
                .algorithm = .zstd,
                .onRotation = true,
                .checksum = true,
                .extension = Constants.CompressionConstants.ArchivingExtensions.zstd,
            };
        }

        /// Alias for zstd(). Returns a zstd compression config with default settings.
        /// v0.1.5+
        /// Alias for zstdFast(). Returns a fast zstd compression config.
        /// v0.1.5+
        /// Alias for zstdBest(). Returns a high-ratio zstd compression config.
        /// v0.1.5+
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
                .algorithm = .tarGz,
                .extension = Constants.CompressionConstants.ArchivingExtensions.tarGz,
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
        /// v0.2.1+
        pub fn getEffectiveBrotliLevel(self: *const CompressionConfig) i32 {
            if (self.customBrotliLevel) |custom| {
                return custom;
            }
            return self.level.toBrotliLevel();
        }

        /// Returns the effective zstd compression level.
        /// If custom_zstd_level is set, uses that; otherwise maps from level enum.
        ///
        /// v0.1.5+
        pub fn getEffectiveZstdLevel(self: *const CompressionConfig) i32 {
            if (self.customZstdLevel) |custom| {
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
        pub fn development() CompressionConfig {
            return .{
                .enabled = true,
                .level = .fastest,
                .algorithm = .deflate,
                .keepOriginal = true,
                .checksum = true,
            };
        }

        /// Returns a disabled compression config.
        ///
        /// Example:
        /// ```zig
        /// const config = Config.default().withCompression(CompressionConfig.disable());
        /// ```
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
        sizeLimit: ?u64 = null,

        /// Default size limit as string (e.g., "10MB").
        /// Only used if sink doesn't specify size limit.
        sizeLimitStr: ?[]const u8 = null,

        /// Maximum number of rotated files to retain.
        /// Older files will be deleted during rotation.
        retentionCount: ?usize = null,

        /// Maximum age of rotated files in seconds.
        /// Files older than this will be deleted during rotation.
        maxAgeSeconds: ?i64 = null,

        /// Maximum total size of all rotated files in bytes.
        /// Oldest rotated files will be deleted when total size exceeds this.
        maxTotalSize: ?u64 = null,

        /// Maximum total size as a string (e.g. "100MB").
        maxTotalSizeStr: ?[]const u8 = null,

        /// Custom rotation callback.
        onRotate: ?*const fn (oldPath: []const u8, newPath: []const u8) void = null,

        /// Strategy for naming rotated files.
        /// Strategy for naming rotated files.
        namingStrategy: NamingStrategy = .timestamp,

        /// Custom format string for rotated files.
        /// Used when naming_strategy is .custom.
        /// Placeholders: {base}, {ext}, {timestamp}, {date}, {iso}, {index}
        namingFormat: ?[]const u8 = null,

        /// Optional directory to move rotated files to.
        /// If null, files remain in the same directory as the log.
        archiveDir: ?[]const u8 = null,

        /// Whether to remove empty directories after cleanup.
        cleanEmptyDirs: bool = false,

        /// Whether to perform cleanup asynchronously.
        asyncCleanup: bool = false,

        /// Keep original file after compression (default: false - delete original).
        keepOriginal: bool = false,

        /// Compress files during retention cleanup instead of deleting them.
        /// When true, old files exceeding retention limits are compressed rather than deleted.
        compressOnRetention: bool = false,

        /// Delete files after compression during retention (only applies when compress_on_retention is true).
        /// When false, compressed files are kept; when true, originals are deleted after compression.
        deleteAfterRetentionCompress: bool = true,
        /// Root directory for all rotated/compressed files (centralized archive).
        archiveRootDir: ?[]const u8 = null,
        /// Create date-based subdirectories in archive (YYYY/MM/DD structure).
        createDateSubdirs: bool = false,
        /// Custom prefix for rotated file names.
        filePrefix: ?[]const u8 = null,
        /// Custom suffix for rotated file names (before extension).
        fileSuffix: ?[]const u8 = null,
        /// Compression algorithm for rotation.
        compressionAlgorithm: CompressionConfig.CompressionAlgorithm = .gzip,
        /// Compression level for rotation.
        compressionLevel: CompressionConfig.CompressionLevel = .default,

        pub const NamingStrategy = enum {
            /// Append timestamp: logly.log -> logly.log.1678888888
            timestamp,
            /// Append date: logly.log -> logly.log.2023-01-01
            date,
            /// Append ISO datetime: logly.log -> logly.log.2023-01-01T12-00-00
            isoDatetime,
            /// Rolling index: logly.log -> logly.log.1 (renames existing)
            index,
            /// Custom format string (requires naming_format to be set)
            custom,
        };

        /// Returns a size-based rotation configuration.
        pub fn bySize(sizeBytes: u64, retention: usize) RotationConfig {
            return .{
                .enabled = true,
                .sizeLimit = sizeBytes,
                .retentionCount = retention,
            };
        }

        /// Returns a size-based rotation configuration parsed from a size string (e.g. "10MB").
        pub fn fromSize(sizeStr: []const u8) RotationConfig {
            return .{
                .enabled = true,
                .sizeLimitStr = sizeStr,
            };
        }

        /// Returns a time-based rotation configuration.
        pub fn byInterval(intervalName: []const u8, retention: usize) RotationConfig {
            return .{
                .enabled = true,
                .interval = intervalName,
                .retentionCount = retention,
            };
        }

        /// Returns a time-based rotation configuration parsed from an interval name or duration string (e.g. "24h").
        pub fn fromInterval(durStr: []const u8) RotationConfig {
            return .{
                .enabled = true,
                .interval = durStr,
            };
        }

        /// Returns a daily rotation configuration.
        pub fn daily(retentionDays: usize) RotationConfig {
            return byInterval("daily", retentionDays);
        }

        /// Returns a copy with compression enabled for rotated files.
        pub fn withCompression(self: RotationConfig, algorithm: CompressionConfig.CompressionAlgorithm) RotationConfig {
            var cfg = self;
            cfg.enabled = true;
            cfg.compressionAlgorithm = algorithm;
            cfg.compressOnRetention = true;
            return cfg;
        }

        /// Returns a copy with archive directory controls configured.
        pub fn withArchive(self: RotationConfig, dir: []const u8, dateSubdirs: bool) RotationConfig {
            var cfg = self;
            cfg.enabled = true;
            cfg.archiveDir = dir;
            cfg.archiveRootDir = dir;
            cfg.createDateSubdirs = dateSubdirs;
            return cfg;
        }
    };

    /// Invoke system configuration. Controls extra message display on log records.
    pub const RulesConfig = struct {
        /// Master switch for invoke system.
        enabled: bool = false,

        /// Enable/disable client-defined triggers.
        clientRulesEnabled: bool = true,

        /// Enable/disable built-in triggers (reserved for future use).
        builtinRulesEnabled: bool = true,

        /// Enable ANSI colors in invoke message output.
        enableColors: bool = true,

        /// Indent string for invoke messages.
        indent: []const u8 = "    ",

        /// Include invoke messages in JSON output.
        includeInJson: bool = true,

        /// Maximum number of triggers allowed.
        maxRules: usize = Constants.InvokeConstants.defaultMaxRules,

        /// Maximum messages per trigger to display.
        maxMessagesPerRule: usize = Constants.InvokeConstants.defaultMaxMessages,

        /// Display invoke messages on console (respects global_console_display).
        consoleOutput: bool = true,

        /// Write invoke messages to file sinks (respects global_file_storage).
        fileOutput: bool = true,

        /// Preset configurations for various environments.
        /// Returns minimal configuration with basic settings.
        pub fn minimal() RulesConfig {
            return .{ .enabled = true, .enableColors = true };
        }

        /// Returns production configuration.
        /// No colors, minimal overhead.
        pub fn production() RulesConfig {
            return .{
                .enabled = true,
                .enableColors = false,
            };
        }

        /// Returns development configuration.
        /// Colors enabled for full debugging.
        pub fn development() RulesConfig {
            return .{
                .enabled = true,
                .enableColors = true,
            };
        }

        /// Returns disabled configuration.
        /// Zero overhead as invoke system is bypassed.
        pub fn disabled() RulesConfig {
            return .{ .enabled = false };
        }

        /// Returns silent rule configuration.
        /// Rules are evaluated but no output is generated (silent evaluation).
        pub fn silent() RulesConfig {
            return .{ .enabled = true, .consoleOutput = false, .fileOutput = false };
        }

        /// Returns console-only rule configuration.
        pub fn consoleOnly() RulesConfig {
            return .{ .enabled = true, .consoleOutput = true, .fileOutput = false };
        }

        /// Returns file-only rule configuration.
        pub fn fileOnly() RulesConfig {
            return .{ .enabled = true, .consoleOutput = false, .fileOutput = true };
        }
    };

    /// Async logging configuration.
    pub const AsyncConfig = struct {
        /// Enable async logging.
        enabled: bool = false,
        /// Buffer size for async queue.
        bufferSize: usize = Constants.BufferSizes.asyncQueue,
        /// Batch size for flushing.
        batchSize: usize = Constants.AsyncConstants.batchSize,
        /// Flush interval in milliseconds.
        flushIntervalMs: u64 = Constants.TimeDefaults.retryDelayMs,
        /// Minimum time between flushes to avoid thrashing.
        minFlushIntervalMs: u64 = 0,
        /// Maximum latency before forcing a flush.
        maxLatencyMs: u64 = Constants.TimeDefaults.writeTimeoutMs,
        /// What to do when buffer is full.
        overflowPolicy: OverflowPolicy = .dropOldest,
        /// Auto-start worker thread.
        backgroundWorker: bool = true,
        /// Queue utilization ratio that records a backpressure event.
        backpressureThreshold: f64 = Constants.AsyncConstants.backpressureThresholdRatio,
        /// Default timeout for explicit drain waits.
        drainTimeoutMs: u64 = Constants.AsyncConstants.drainTimeoutMs,
        /// Shutdown grace period timeout in milliseconds.
        shutdownTimeoutMs: u64 = Constants.AsyncConstants.drainTimeoutMs,
        /// Explicit I/O handle. When null, inherits from Logger or defaults to stateless I/O.
        io: ?std.Io = null,

        pub const OverflowPolicy = enum {
            dropOldest,
            dropNewest,
            block,
        };

        /// Returns async settings for high-throughput buffered logging.
        pub fn highThroughput() AsyncConfig {
            return .{
                .enabled = true,
                .bufferSize = Constants.AsyncPresetDefaults.highThroughputBufferSize,
                .batchSize = Constants.AsyncPresetDefaults.highThroughputBatchSize,
                .flushIntervalMs = Constants.AsyncPresetDefaults.highThroughputFlushIntervalMs,
                .minFlushIntervalMs = Constants.AsyncPresetDefaults.highThroughputMinFlushIntervalMs,
                .maxLatencyMs = Constants.AsyncPresetDefaults.highThroughputMaxLatencyMs,
                .overflowPolicy = .dropOldest,
                .backgroundWorker = true,
            };
        }

        /// Returns async settings for low-latency logging.
        pub fn lowLatency() AsyncConfig {
            return .{
                .enabled = true,
                .bufferSize = Constants.AsyncPresetDefaults.lowLatencyBufferSize,
                .batchSize = Constants.AsyncPresetDefaults.lowLatencyBatchSize,
                .flushIntervalMs = Constants.AsyncPresetDefaults.lowLatencyFlushIntervalMs,
                .minFlushIntervalMs = Constants.AsyncPresetDefaults.lowLatencyMinFlushIntervalMs,
                .maxLatencyMs = Constants.AsyncPresetDefaults.lowLatencyMaxLatencyMs,
                .overflowPolicy = .block,
                .backgroundWorker = true,
            };
        }

        /// Returns async settings that prefer blocking over dropping records.
        pub fn reliable() AsyncConfig {
            return .{
                .enabled = true,
                .flushIntervalMs = Constants.AsyncPresetDefaults.balancedFlushIntervalMs,
                .minFlushIntervalMs = Constants.AsyncPresetDefaults.balancedMinFlushIntervalMs,
                .maxLatencyMs = Constants.AsyncPresetDefaults.balancedMaxLatencyMs,
                .overflowPolicy = .block,
                .backgroundWorker = true,
            };
        }

        /// Returns a copy with a specific queue size.
        pub fn withBufferSize(self: AsyncConfig, size: usize) AsyncConfig {
            var cfg = self;
            cfg.enabled = true;
            cfg.bufferSize = size;
            return cfg;
        }

        /// Returns a copy with a specific batch size.
        pub fn withBatchSize(self: AsyncConfig, size: usize) AsyncConfig {
            var cfg = self;
            cfg.batchSize = size;
            return cfg;
        }

        /// Returns a copy with a specific overflow policy.
        pub fn withOverflowPolicy(self: AsyncConfig, policy: OverflowPolicy) AsyncConfig {
            var cfg = self;
            cfg.overflowPolicy = policy;
            return cfg;
        }

        /// Returns a copy with a clamped backpressure threshold.
        pub fn withBackpressureThreshold(self: AsyncConfig, threshold: f64) AsyncConfig {
            var cfg = self;
            cfg.backpressureThreshold = if (threshold < 0.0) 0.0 else if (threshold > 1.0) 1.0 else threshold;
            return cfg;
        }
    };

    /// Returns the default configuration.
    ///
    /// Defaults:
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
            .format = .json,
            .color = false,
            .globalColorDisplay = false,
            .sampling = .{ .enabled = true, .strategy = .{ .probability = 0.1 } },
            .enableMetrics = true,
            .structured = true,
            .compression = .{
                .enabled = true,
                .level = .default,
                .onRotation = true,
            },
            .rotation = .{
                .enabled = true,
                .retentionCount = 30,
                .maxAgeSeconds = 30 * Constants.TimeConstants.secondsPerDay,
            },
            .scheduler = .{
                .enabled = true,
                .cleanupMaxAgeDays = 30,
                .compressBeforeCleanup = true,
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
            .showFunction = true,
            .showFilename = true,
            .showLineno = true,
            .debugMode = true,
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
            .sampling = .{ .enabled = true, .strategy = .{ .adaptive = .{ .targetRate = Constants.ConfigPresetDefaults.highThroughputSamplingTargetRate } } },
            .rateLimit = .{ .enabled = true, .maxPerSecond = Constants.ConfigPresetDefaults.highThroughputRateLimitPerSecond },
            .bufferConfig = .{
                .size = Constants.ConfigPresetDefaults.highThroughputBufferSize,
                .flushIntervalMs = Constants.ConfigPresetDefaults.highThroughputBufferFlushIntervalMs,
                .maxPending = Constants.ConfigPresetDefaults.highThroughputMaxPending,
            },
            .threadPool = .{
                .enabled = true,
                .threadCount = Constants.ThreadDefaults.threadCount, // auto-detect
                .queueSize = Constants.ConfigPresetDefaults.highThroughputThreadPoolQueueSize,
                .workStealing = true,
            },
            .asyncConfig = .{
                .enabled = true,
                .bufferSize = Constants.ConfigPresetDefaults.highThroughputAsyncBufferSize,
                .batchSize = Constants.ConfigPresetDefaults.highThroughputAsyncBatchSize,
                .flushIntervalMs = Constants.ConfigPresetDefaults.highThroughputAsyncFlushIntervalMs,
            },
            .rotation = .{
                .enabled = true,
                .namingStrategy = .timestamp,
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
            .includeHostname = false,
            .includePid = false,
        };
    }

    /// Merges another configuration into this one.
    ///
    /// The `other` configuration takes precedence for non-default values.
    /// Used to layer configurations (e.g., specific override over base profile).
    pub fn merge(self: Config, other: Config) Config {
        var result = self;
        if (other.level != .info) result.level = other.level;
        if (other.format != .text) result.format = other.format;
        if (other.prettyJson) result.prettyJson = true;
        if (other.includeTraceId) result.includeTraceId = true;
        if (other.includePid) result.includePid = true;
        if (other.includeHostname) result.includeHostname = true;
        if (other.logFormat != null) result.logFormat = other.logFormat;
        if (other.appName != null) result.appName = other.appName;
        if (other.appVersion != null) result.appVersion = other.appVersion;
        if (other.environment != null) result.environment = other.environment;
        if (other.sampling.enabled) result.sampling = other.sampling;
        if (other.rateLimit.enabled) result.rateLimit = other.rateLimit;
        if (other.redaction.enabled) result.redaction = other.redaction;
        if (other.threadPool.enabled) result.threadPool = other.threadPool;
        if (other.scheduler.enabled) result.scheduler = other.scheduler;
        if (other.compression.enabled) result.compression = other.compression;
        if (other.asyncConfig.enabled) result.asyncConfig = other.asyncConfig;
        return result;
    }

    /// Returns a configuration with async logging enabled.
    ///
    /// Builder pattern method to enable async logging with a specific configuration.
    pub fn withAsync(self: Config, config: AsyncConfig) Config {
        var result = self;
        result.asyncConfig = config;
        result.asyncConfig.enabled = true;
        return result;
    }

    /// Returns a copy with metrics configuration applied and top-level metrics enabled.
    ///
    /// Use this to keep `enable_metrics` synchronized with the detailed
    /// `metrics` block when composing production profiles.
    pub fn withMetrics(self: Config, config: MetricsConfig) Config {
        var result = self;
        result.metrics = config;
        result.enableMetrics = config.enabled;
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
        result.asyncConfig = AsyncConfig.highThroughput();
        result.threadPool = ThreadPoolConfig.highThroughput();
        result.metrics = MetricsConfig.production().withLatencyHistogram(20).prometheus();
        result.enableMetrics = true;
        return result;
    }

    /// Returns a copy with metrics, rules, and maintenance controls enabled.
    pub fn withObservability(self: Config, metricPrefix: []const u8) Config {
        var result = self;
        result.metrics = MetricsConfig.detailed().prometheus().withPrefix(metricPrefix);
        result.enableMetrics = true;
        result.rules = RulesConfig.production();
        result.scheduler.enabled = true;
        return result;
    }

    /// Returns a configuration with compression enabled.
    ///
    /// Builder pattern method to enable compression.
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
    pub fn withExplicitCompression(self: Config) Config {
        return self.withCompression(CompressionConfig.explicit());
    }

    /// Returns a configuration with fast compression (speed over ratio).
    ///
    /// Example:
    /// ```zig
    /// const config = Config.default().withFastCompression();
    /// ```
    pub fn withFastCompression(self: Config) Config {
        return self.withCompression(CompressionConfig.fast());
    }

    /// Returns a configuration with best compression (ratio over speed).
    ///
    /// Example:
    /// ```zig
    /// const config = Config.default().withBestCompression();
    /// ```
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
    pub fn withBackgroundCompression(self: Config) Config {
        return self.withCompression(CompressionConfig.backgroundMode());
    }

    /// Returns a configuration optimized for log file compression.
    ///
    /// Example:
    /// ```zig
    /// const config = Config.default().withLogCompression();
    /// ```
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
    pub fn withBrotliCompression(self: Config) Config {
        return self.withCompression(CompressionConfig.brotli());
    }

    /// Returns a configuration with thread pool enabled.
    ///
    /// Builder pattern method to enable thread pool support.
    pub fn withThreadPool(self: Config, config: ThreadPoolConfig) Config {
        var result = self;
        result.threadPool = config;
        result.threadPool.enabled = true;
        return result;
    }

    /// Returns a configuration with scheduler enabled.
    ///
    /// Builder pattern method to enable the background scheduler.
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
    pub fn logOnly() Config {
        var result = Config.default();
        result.globalConsoleDisplay = false;
        result.globalFileStorage = true;
        result.autoSink = false; // Disable auto console sink
        return result;
    }

    /// Returns a configuration for display-only mode (console display, no file storage).
    ///
    /// Enables console output while disabling file storage.
    /// Useful for development or debugging where you only want to see logs in the console.
    pub fn displayOnly() Config {
        var result = Config.default();
        result.globalConsoleDisplay = true;
        result.globalFileStorage = false;
        result.autoSink = true; // Enable auto console sink
        return result;
    }

    /// Returns a configuration with custom display and storage settings.
    ///
    /// Allows fine-grained control over console display and file storage.
    pub fn withDisplayStorage(console: bool, file: bool, autoSink: bool) Config {
        var result = Config.default();
        result.globalConsoleDisplay = console;
        result.globalFileStorage = file;
        result.autoSink = autoSink;
        return result;
    }

    /// Partial configuration structure for runtime overrides.
    pub const ConfigOverride = struct {
        level: ?Level = null,
        color: ?bool = null,
        colorMode: ?ColorMode = null,
        format: ?Format = null,
        prettyJson: ?bool = null,
        tamperEvident: ?bool = null,
        logFormat: ?[]const u8 = null,
        timeFormat: ?[]const u8 = null,
        timezone: ?Timezone = null,
        autoFlush: ?bool = null,
        globalColorDisplay: ?bool = null,
        globalConsoleDisplay: ?bool = null,
        globalFileStorage: ?bool = null,
        captureStackTrace: ?bool = null,
        symbolizeStackTrace: ?bool = null,
        appName: ?[]const u8 = null,
        appVersion: ?[]const u8 = null,
        environment: ?[]const u8 = null,
        maxMessageLength: ?usize = null,
        structured: ?bool = null,
        debugMode: ?bool = null,
        showTime: ?bool = null,
        showModule: ?bool = null,
        showFunction: ?bool = null,
        showFilename: ?bool = null,
        showLineno: ?bool = null,
        showThreadId: ?bool = null,
        showProcessId: ?bool = null,
        includeHostname: ?bool = null,
        includePid: ?bool = null,
        includeTraceId: ?bool = null,
    };

    /// Resolves configuration conflicts and ensures internal consistency.
    pub fn resolveConflicts(self: *Config) void {
        // Color consistency: if color is false or mode is .none, disable color display
        if (!self.color or self.colorMode == .none) {
            self.color = false;
            self.globalColorDisplay = false;
        } else if (!self.globalColorDisplay) {
            self.color = false;
        }

        // Stack trace capture vs symbolization: symbolization requires capture
        if (self.symbolizeStackTrace) {
            self.captureStackTrace = true;
        }

        // Format vs prettyJson: pretty-printing only applies to JSON documents
        if (self.format != .json) {
            self.prettyJson = false;
        }

        // Rate limit sanity
        if (self.rateLimit.enabled and self.rateLimit.maxPerSecond == 0) {
            self.rateLimit.maxPerSecond = Constants.RateLimitDefaults.maxPerSecond;
        }

        // Buffer size sanity
        if (self.asyncConfig.enabled and self.bufferConfig.size == 0) {
            self.bufferConfig.size = Constants.BufferSizes.format;
        }
    }

    /// Merges partial override settings into this configuration and resolves conflicts.
    pub fn applyOverride(self: *Config, override: ConfigOverride) void {
        if (override.level) |v| self.level = v;
        if (override.color) |v| self.color = v;
        if (override.colorMode) |v| self.colorMode = v;
        if (override.format) |v| self.format = v;
        if (override.prettyJson) |v| self.prettyJson = v;
        if (override.tamperEvident) |v| self.tamperEvident = v;
        if (override.logFormat) |v| self.logFormat = v;
        if (override.timeFormat) |v| self.timeFormat = v;
        if (override.timezone) |v| self.timezone = v;
        if (override.autoFlush) |v| self.autoFlush = v;
        if (override.globalColorDisplay) |v| self.globalColorDisplay = v;
        if (override.globalConsoleDisplay) |v| self.globalConsoleDisplay = v;
        if (override.globalFileStorage) |v| self.globalFileStorage = v;
        if (override.captureStackTrace) |v| self.captureStackTrace = v;
        if (override.symbolizeStackTrace) |v| self.symbolizeStackTrace = v;
        if (override.appName) |v| self.appName = v;
        if (override.appVersion) |v| self.appVersion = v;
        if (override.environment) |v| self.environment = v;
        if (override.maxMessageLength) |v| self.maxMessageLength = v;
        if (override.structured) |v| self.structured = v;
        if (override.debugMode) |v| self.debugMode = v;
        if (override.showTime) |v| self.showTime = v;
        if (override.showModule) |v| self.showModule = v;
        if (override.showFunction) |v| self.showFunction = v;
        if (override.showFilename) |v| self.showFilename = v;
        if (override.showLineno) |v| self.showLineno = v;
        if (override.showThreadId) |v| self.showThreadId = v;
        if (override.showProcessId) |v| self.showProcessId = v;
        if (override.includeHostname) |v| self.includeHostname = v;
        if (override.includePid) |v| self.includePid = v;
        if (override.includeTraceId) |v| self.includeTraceId = v;

        self.resolveConflicts();
    }

    const JsonConfig = struct {
        level: ?[]const u8 = null,
        color: ?bool = null,
        colorMode: ?[]const u8 = null,
        format: ?[]const u8 = null,
        prettyJson: ?bool = null,
        tamperEvident: ?bool = null,
        autoFlush: ?bool = null,
        autoSink: ?bool = null,
        globalColorDisplay: ?bool = null,
        globalConsoleDisplay: ?bool = null,
        globalFileStorage: ?bool = null,
        captureStackTrace: ?bool = null,
        symbolizeStackTrace: ?bool = null,
        timeFormat: ?[]const u8 = null,
        timezone: ?[]const u8 = null,
        showTime: ?bool = null,
        showModule: ?bool = null,
        showFunction: ?bool = null,
        showFilename: ?bool = null,
        showLineno: ?bool = null,
        showThreadId: ?bool = null,
        showProcessId: ?bool = null,
        includeHostname: ?bool = null,
        includePid: ?bool = null,
        includeTraceId: ?bool = null,
        maxMessageLength: ?usize = null,
        structured: ?bool = null,
        debugMode: ?bool = null,
        enableMetrics: ?bool = null,
        enableTracing: ?bool = null,
    };

    /// Parses a JSON string to create a Config instance.
    pub fn loadFromJson(allocator: std.mem.Allocator, jsonBytes: []const u8) !Config {
        const parsed = try std.json.parseFromSlice(JsonConfig, allocator, jsonBytes, .{
            .ignore_unknown_fields = true,
        });
        defer parsed.deinit();

        var config = Config.default();
        const j = parsed.value;

        if (j.level) |lvl| {
            config.level = if (std.ascii.eqlIgnoreCase(lvl, "trace") or std.ascii.eqlIgnoreCase(lvl, "trc")) .trace else if (std.ascii.eqlIgnoreCase(lvl, "debug") or std.ascii.eqlIgnoreCase(lvl, "dbg")) .debug else if (std.ascii.eqlIgnoreCase(lvl, "info")) .info else if (std.ascii.eqlIgnoreCase(lvl, "notice") or std.ascii.eqlIgnoreCase(lvl, "note")) .notice else if (std.ascii.eqlIgnoreCase(lvl, "success") or std.ascii.eqlIgnoreCase(lvl, "ok")) .success else if (std.ascii.eqlIgnoreCase(lvl, "warning") or std.ascii.eqlIgnoreCase(lvl, "warn")) .warning else if (std.ascii.eqlIgnoreCase(lvl, "err") or std.ascii.eqlIgnoreCase(lvl, "error")) .err else if (std.ascii.eqlIgnoreCase(lvl, "fail")) .fail else if (std.ascii.eqlIgnoreCase(lvl, "critical") or std.ascii.eqlIgnoreCase(lvl, "crit")) .critical else if (std.ascii.eqlIgnoreCase(lvl, "fatal") or std.ascii.eqlIgnoreCase(lvl, "panic")) .fatal else Level.fromString(lvl) orelse return error.InvalidLogLevel;
        }
        if (j.color) |val| config.color = val;
        if (j.colorMode) |cm| {
            if (std.ascii.eqlIgnoreCase(cm, "horizontal")) {
                config.colorMode = .horizontal;
            } else if (std.ascii.eqlIgnoreCase(cm, "vertical")) {
                config.colorMode = .vertical;
            } else if (std.ascii.eqlIgnoreCase(cm, "none")) {
                config.colorMode = .none;
            }
        }
        if (j.format) |name| {
            config.format = Format.fromString(name) orelse return error.InvalidFormat;
        }
        if (j.prettyJson) |val| config.prettyJson = val;
        if (j.tamperEvident) |val| config.tamperEvident = val;
        if (j.autoFlush) |val| config.autoFlush = val;
        if (j.autoSink) |val| config.autoSink = val;
        if (j.globalColorDisplay) |val| config.globalColorDisplay = val;
        if (j.globalConsoleDisplay) |val| config.globalConsoleDisplay = val;
        if (j.globalFileStorage) |val| config.globalFileStorage = val;
        if (j.captureStackTrace) |val| config.captureStackTrace = val;
        if (j.symbolizeStackTrace) |val| config.symbolizeStackTrace = val;
        if (j.showTime) |val| config.showTime = val;
        if (j.showModule) |val| config.showModule = val;
        if (j.showFunction) |val| config.showFunction = val;
        if (j.showFilename) |val| config.showFilename = val;
        if (j.showLineno) |val| config.showLineno = val;
        if (j.showThreadId) |val| config.showThreadId = val;
        if (j.showProcessId) |val| config.showProcessId = val;
        if (j.includeHostname) |val| config.includeHostname = val;
        if (j.includePid) |val| config.includePid = val;
        if (j.includeTraceId) |val| config.includeTraceId = val;
        if (j.maxMessageLength) |val| config.maxMessageLength = val;
        if (j.structured) |val| config.structured = val;
        if (j.debugMode) |val| config.debugMode = val;
        if (j.enableMetrics) |val| config.enableMetrics = val;
        if (j.enableTracing) |val| config.enableTracing = val;
        if (j.timeFormat) |tf| {
            if (std.ascii.eqlIgnoreCase(tf, "iso8601")) {
                config.timeFormat = TimeFormat.iso8601;
            } else if (std.ascii.eqlIgnoreCase(tf, "rfc3339")) {
                config.timeFormat = TimeFormat.rfc3339;
            } else if (std.ascii.eqlIgnoreCase(tf, "unix")) {
                config.timeFormat = TimeFormat.unix;
            } else if (std.ascii.eqlIgnoreCase(tf, "unix_ms")) {
                config.timeFormat = TimeFormat.unixMs;
            } else if (std.ascii.eqlIgnoreCase(tf, "default")) {
                config.timeFormat = TimeFormat.defaultPattern;
            }
        }
        if (j.timezone) |tz| {
            if (std.ascii.eqlIgnoreCase(tz, "utc")) {
                config.timezone = .utc;
            } else if (std.ascii.eqlIgnoreCase(tz, "local")) {
                config.timezone = .local;
            }
        }

        config.resolveConflicts();
        return config;
    }

    /// Loads the configuration from a JSON file with explicit I/O.
    ///
    /// Files larger than 64KB are rejected instead of being silently
    /// truncated into a partial configuration.
    pub fn loadFromFileWithIo(allocator: std.mem.Allocator, io_handle: std.Io, filePath: []const u8) !Config {
        const file = try std.Io.Dir.cwd().openFile(io_handle, filePath, .{});
        defer file.close(io_handle);

        // Read entire file (up to 64KB)
        const buf = try allocator.alloc(u8, 65536);
        defer allocator.free(buf);

        var fileBuffer: [4096]u8 = undefined;
        var reader = file.reader(io_handle, &fileBuffer);
        const len = try reader.interface.readSliceShort(buf);
        // A full buffer may mean truncation: prove EOF before parsing.
        if (len == buf.len) {
            var probe: [1]u8 = undefined;
            const extra = try reader.interface.readSliceShort(&probe);
            if (extra > 0) return error.ConfigTooLarge;
        }
        const jsonBytes = buf[0..len];

        return try loadFromJson(allocator, jsonBytes);
    }

    /// Loads the configuration from a JSON file.
    pub fn loadFromFile(allocator: std.mem.Allocator, filePath: []const u8) !Config {
        return loadFromFileWithIo(allocator, Utils.defaultIo(), filePath);
    }
};

test "config JSON load and parse" {
    const allocator = std.testing.allocator;

    const jsonStr = "{\"level\": \"debug\", \"color\": false}";
    const config = try Config.loadFromJson(allocator, jsonStr);
    try std.testing.expectEqual(Level.debug, config.level);
    try std.testing.expect(!config.color);

    // Test writing and loading from file using std.Io
    const testFilePath = "test_config_temp.json";
    const io = Utils.defaultIo();
    const file = try std.Io.Dir.cwd().createFile(io, testFilePath, .{});
    try file.writeStreamingAll(io, jsonStr);
    file.close(io);
    defer std.Io.Dir.cwd().deleteFile(io, testFilePath) catch {};

    const config2 = try Config.loadFromFile(allocator, testFilePath);
    try std.testing.expectEqual(Level.debug, config2.level);
    try std.testing.expect(!config2.color);
}

test "config default values" {
    const config = Config.default();
    try std.testing.expectEqual(Level.info, config.level);
    try std.testing.expect(config.globalColorDisplay);
    try std.testing.expect(config.globalConsoleDisplay);
    try std.testing.expect(config.globalFileStorage);
    try std.testing.expect(config.color);
    try std.testing.expect(config.format == .text);
    try std.testing.expect(config.autoSink);
    try std.testing.expectEqualStrings(Constants.ConfigDefaults.distributedTraceHeader, config.traceHeader);
    try std.testing.expectEqualStrings(Constants.ConfigDefaults.distributedTraceHeader, config.distributed.traceHeader);
    try std.testing.expectEqualStrings(Constants.ConfigDefaults.distributedSpanHeader, config.distributed.spanHeader);
    try std.testing.expectEqualStrings(Constants.ConfigDefaults.distributedParentHeader, config.distributed.parentHeader);
    try std.testing.expectEqualStrings(Constants.ConfigDefaults.distributedBaggageHeader, config.distributed.baggageHeader);
}

test "config time format constants are centralized" {
    try std.testing.expectEqualStrings(Constants.TimeConstants.defaultTimePattern, Config.TimeFormat.defaultPattern);
    try std.testing.expectEqualStrings("default", Config.TimeFormat.defaultAlias);
    try std.testing.expectEqualStrings("ISO8601", Config.TimeFormat.iso8601);
    try std.testing.expectEqualStrings("RFC3339", Config.TimeFormat.rfc3339);
    try std.testing.expectEqualStrings("unix", Config.TimeFormat.unix);
    try std.testing.expectEqualStrings("unix_ms", Config.TimeFormat.unixMs);
}

test "config presets" {
    // Production preset
    const prodConfig = Config.production();
    try std.testing.expectEqual(Level.info, prodConfig.level);
    try std.testing.expect(!prodConfig.color);
    try std.testing.expect(prodConfig.format == .json);

    // Development preset
    const devConfig = Config.development();
    try std.testing.expectEqual(Level.debug, devConfig.level);
    try std.testing.expect(devConfig.color);

    // High throughput preset
    const htConfig = Config.highThroughput();
    try std.testing.expectEqual(Level.warning, htConfig.level);
    try std.testing.expect(htConfig.threadPool.enabled);
    try std.testing.expect(htConfig.asyncConfig.enabled);

    // Secure preset
    const secureConfig = Config.secure();
    try std.testing.expect(secureConfig.redaction.enabled);
    try std.testing.expect(secureConfig.structured);

    // Log only preset
    const logOnly = Config.logOnly();
    try std.testing.expect(!logOnly.globalConsoleDisplay);
    try std.testing.expect(logOnly.globalFileStorage);

    // Display only preset
    const displayOnly = Config.displayOnly();
    try std.testing.expect(displayOnly.globalConsoleDisplay);
    try std.testing.expect(!displayOnly.globalFileStorage);
}

test "config format selection" {
    try std.testing.expectEqual(Config.Format.text, Config.default().format);
    try std.testing.expectEqual(Config.Format.json, Config.Format.fromString("json").?);
    try std.testing.expectEqual(Config.Format.ndjson, Config.Format.fromString("JSONLines").?);
    try std.testing.expectEqual(Config.Format.syslog3164, Config.Format.fromString("bsd").?);
    try std.testing.expect(Config.Format.fromString("csv") == null);
    try std.testing.expect(Config.Format.fromString("yaml") == null);
    try std.testing.expect(!Config.Format.msgpack.isLineDelimited());
    try std.testing.expect(Config.Format.ndjson.isLineDelimited());
    try std.testing.expect(Config.Format.msgpack.isBinary());
    try std.testing.expect(!Config.Format.json.isBinary());

    // Merge carries an explicit non-default format, never resets to text.
    var base = Config.default();
    base.format = .json;
    const overlay = Config.default();
    try std.testing.expectEqual(Config.Format.json, base.merge(overlay).format);
    var ndjson = Config.default();
    ndjson.format = .ndjson;
    try std.testing.expectEqual(Config.Format.ndjson, base.merge(ndjson).format);

    // JSON config load rejects unknown format names.
    const bad = Config.loadFromJson(std.testing.allocator, "{\"format\": \"yaml\"}");
    try std.testing.expectError(error.InvalidFormat, bad);
    const good = try Config.loadFromJson(std.testing.allocator, "{\"format\": \"syslog\"}");
    try std.testing.expectEqual(Config.Format.syslog, good.format);
    // Removed per-format flags are simply unknown fields and ignored.
    const legacy = try Config.loadFromJson(std.testing.allocator, "{\"json\": true}");
    try std.testing.expectEqual(Config.Format.text, legacy.format);
}

test "config with display storage" {
    // Console only
    const consoleOnly = Config.withDisplayStorage(true, false, true);
    try std.testing.expect(consoleOnly.globalConsoleDisplay);
    try std.testing.expect(!consoleOnly.globalFileStorage);
    try std.testing.expect(consoleOnly.autoSink);

    // File only
    const fileOnly = Config.withDisplayStorage(false, true, false);
    try std.testing.expect(!fileOnly.globalConsoleDisplay);
    try std.testing.expect(fileOnly.globalFileStorage);
    try std.testing.expect(!fileOnly.autoSink);

    // Both enabled
    const both = Config.withDisplayStorage(true, true, true);
    try std.testing.expect(both.globalConsoleDisplay);
    try std.testing.expect(both.globalFileStorage);
}

test "config pipeline builders enable related features" {
    const cfg = Config.default()
        .withHighThroughputPipeline()
        .withObservability("svc.api")
        .withRotation(Config.RotationConfig.daily(7).withCompression(.zstd));

    try std.testing.expect(cfg.asyncConfig.enabled);
    try std.testing.expect(cfg.threadPool.enabled);
    try std.testing.expect(cfg.enableMetrics);
    try std.testing.expect(cfg.metrics.enabled);
    try std.testing.expectEqual(Config.MetricsConfig.ExportFormat.prometheus, cfg.metrics.exportFormat);
    try std.testing.expectEqualStrings("svc.api", cfg.metrics.metricPrefix);
    try std.testing.expect(cfg.rules.enabled);
    try std.testing.expect(cfg.scheduler.enabled);
    try std.testing.expect(cfg.rotation.enabled);
    try std.testing.expectEqual(Config.CompressionConfig.CompressionAlgorithm.zstd, cfg.rotation.compressionAlgorithm);
}

test "config async metrics and threadpool helper aliases" {
    const asyncCfg = Config.AsyncConfig.lowLatency()
        .withBufferSize(128)
        .withBatchSize(8)
        .withOverflowPolicy(.dropNewest)
        .withBackpressureThreshold(2.0);
    try std.testing.expect(asyncCfg.enabled);
    try std.testing.expectEqual(@as(usize, 128), asyncCfg.bufferSize);
    try std.testing.expectEqual(@as(usize, 8), asyncCfg.batchSize);
    try std.testing.expectEqual(Config.AsyncConfig.OverflowPolicy.dropNewest, asyncCfg.overflowPolicy);
    try std.testing.expectEqual(@as(f64, 1.0), asyncCfg.backpressureThreshold);

    const metricsCfg = Config.MetricsConfig.minimal()
        .withExport(.prometheus)
        .withPrefix("worker")
        .withLatencyHistogram(12)
        .withAlerts(0.1, 0.2)
        .withBreakdowns(false, true);
    try std.testing.expect(metricsCfg.enabled);
    try std.testing.expectEqual(Config.MetricsConfig.ExportFormat.prometheus, metricsCfg.exportFormat);
    try std.testing.expectEqualStrings("worker", metricsCfg.metricPrefix);
    try std.testing.expect(metricsCfg.trackLatency);
    try std.testing.expect(metricsCfg.enableHistogram);
    try std.testing.expectEqual(@as(u8, 12), metricsCfg.histogramBuckets);
    try std.testing.expect(!metricsCfg.exportLevelBreakdown);
    try std.testing.expect(metricsCfg.exportSinkBreakdown);

    const poolCfg = Config.ThreadPoolConfig.ioBound().withThreadCount(4).withQueueSize(256);
    try std.testing.expect(poolCfg.enabled);
    try std.testing.expectEqual(@as(usize, 4), poolCfg.threadCount);
    try std.testing.expectEqual(@as(usize, 256), poolCfg.queueSize);
}

test "rules config default values" {
    const rulesConfig = Config.RulesConfig{};
    try std.testing.expect(!rulesConfig.enabled);
    try std.testing.expect(rulesConfig.clientRulesEnabled);
    try std.testing.expect(rulesConfig.builtinRulesEnabled);
    try std.testing.expect(rulesConfig.enableColors);
    try std.testing.expect(rulesConfig.includeInJson);
    try std.testing.expectEqual(Constants.InvokeConstants.defaultMaxRules, rulesConfig.maxRules);
    try std.testing.expectEqual(Constants.InvokeConstants.defaultMaxMessages, rulesConfig.maxMessagesPerRule);
    try std.testing.expect(rulesConfig.consoleOutput);
    try std.testing.expect(rulesConfig.fileOutput);
}

test "rules config presets" {
    // Development preset
    const dev = Config.RulesConfig.development();
    try std.testing.expect(dev.enabled);
    try std.testing.expect(dev.enableColors);

    // Production preset
    const prod = Config.RulesConfig.production();
    try std.testing.expect(prod.enabled);
    try std.testing.expect(!prod.enableColors);

    // Disabled preset
    const dis = Config.RulesConfig.disabled();
    try std.testing.expect(!dis.enabled);

    // Silent preset
    const silent = Config.RulesConfig.silent();
    try std.testing.expect(silent.enabled);
    try std.testing.expect(!silent.consoleOutput);
    try std.testing.expect(!silent.fileOutput);

    // Console only preset
    const consoleOnly = Config.RulesConfig.consoleOnly();
    try std.testing.expect(consoleOnly.enabled);
    try std.testing.expect(consoleOnly.consoleOutput);
    try std.testing.expect(!consoleOnly.fileOutput);

    // File only preset
    const fileOnly = Config.RulesConfig.fileOnly();
    try std.testing.expect(fileOnly.enabled);
    try std.testing.expect(!fileOnly.consoleOutput);
    try std.testing.expect(fileOnly.fileOutput);
}

test "config with rules" {
    var config = Config.default();
    config.rules = Config.RulesConfig.development();

    try std.testing.expect(config.rules.enabled);
    try std.testing.expect(config.rules.enableColors);
}

test "config global switches affect rules" {
    // Test that rules config fields exist for global switch integration
    var config = Config.default();
    config.globalConsoleDisplay = false;
    config.globalFileStorage = false;
    config.globalColorDisplay = false;

    // Verify rules config has corresponding fields
    try std.testing.expect(config.rules.consoleOutput);
    try std.testing.expect(config.rules.fileOutput);
    try std.testing.expect(config.rules.enableColors);

    // The actual AND logic happens in the formatter/sink at runtime
    // Here we just verify the fields exist and can be set
    config.rules.consoleOutput = false;
    config.rules.fileOutput = false;
    config.rules.enableColors = false;

    try std.testing.expect(!config.rules.consoleOutput);
    try std.testing.expect(!config.rules.fileOutput);
    try std.testing.expect(!config.rules.enableColors);
}

test "compression config presets" {
    // Test enable() preset
    const enableCfg = Config.CompressionConfig.enable();
    try std.testing.expect(enableCfg.enabled);

    // Test basic() is alias for enable()
    const basicCfg = Config.CompressionConfig.basic();
    try std.testing.expect(basicCfg.enabled);

    // Test implicit() preset
    const implicitCfg = Config.CompressionConfig.implicit();
    try std.testing.expect(implicitCfg.enabled);
    try std.testing.expect(implicitCfg.onRotation);
    try std.testing.expectEqual(implicitCfg.mode, .onRotation);

    // Test explicit() preset
    const explicitCfg = Config.CompressionConfig.explicit();
    try std.testing.expect(explicitCfg.enabled);
    try std.testing.expect(!explicitCfg.onRotation);
    try std.testing.expectEqual(explicitCfg.mode, .disabled);

    // Test fast() preset
    const fastCfg = Config.CompressionConfig.fast();
    try std.testing.expect(fastCfg.enabled);
    try std.testing.expectEqual(fastCfg.level, .fastest);

    // Test balanced() preset
    const balancedCfg = Config.CompressionConfig.balanced();
    try std.testing.expect(balancedCfg.enabled);
    try std.testing.expectEqual(balancedCfg.level, .default);

    // Test best() preset
    const bestCfg = Config.CompressionConfig.best();
    try std.testing.expect(bestCfg.enabled);
    try std.testing.expectEqual(bestCfg.level, .best);
    try std.testing.expectEqual(bestCfg.algorithm, .gzip);

    // Test forLogs() preset
    const logsCfg = Config.CompressionConfig.forLogs();
    try std.testing.expect(logsCfg.enabled);
    try std.testing.expectEqual(logsCfg.strategy, .text);

    // Test archive() preset
    const archiveCfg = Config.CompressionConfig.archive();
    try std.testing.expect(archiveCfg.enabled);
    try std.testing.expect(!archiveCfg.keepOriginal);
    try std.testing.expectEqual(archiveCfg.level, .best);

    // Test keepOriginals() preset
    const keepCfg = Config.CompressionConfig.keepOriginals();
    try std.testing.expect(keepCfg.enabled);
    try std.testing.expect(keepCfg.keepOriginal);

    // Test onSize() preset
    const sizeCfg = Config.CompressionConfig.onSize(5 * Constants.SizeConstants.bytesPerMb);
    try std.testing.expect(sizeCfg.enabled);
    try std.testing.expectEqual(sizeCfg.mode, .onSizeThreshold);
    try std.testing.expectEqual(sizeCfg.sizeThreshold, 5 * Constants.SizeConstants.bytesPerMb);

    // Test production() preset
    const prodCfg = Config.CompressionConfig.production();
    try std.testing.expect(prodCfg.enabled);
    try std.testing.expect(prodCfg.background);
    try std.testing.expect(prodCfg.checksum);

    // Test development() preset
    const devCfg = Config.CompressionConfig.development();
    try std.testing.expect(devCfg.enabled);
    try std.testing.expect(devCfg.keepOriginal);
    try std.testing.expectEqual(devCfg.level, .fastest);

    // Test disable() preset
    const disableCfg = Config.CompressionConfig.disable();
    try std.testing.expect(!disableCfg.enabled);

    // Test streamingMode() preset
    const streamCfg = Config.CompressionConfig.streamingMode();
    try std.testing.expect(streamCfg.enabled);
    try std.testing.expect(streamCfg.streaming);
    try std.testing.expectEqual(streamCfg.mode, .streaming);

    // Test backgroundMode() preset
    const bgCfg = Config.CompressionConfig.backgroundMode();
    try std.testing.expect(bgCfg.enabled);
    try std.testing.expect(bgCfg.background);

    // Test zstd() preset (v0.1.5+)
    const zstdCfg = Config.CompressionConfig.zstd();
    try std.testing.expect(zstdCfg.enabled);
    try std.testing.expectEqual(zstdCfg.algorithm, .zstd);
    try std.testing.expectEqual(zstdCfg.level, .default);
    try std.testing.expectEqualStrings(".zst", zstdCfg.extension);
    try std.testing.expect(zstdCfg.checksum);

    // Test zstdFast() preset (v0.1.5+)
    const zstdFastCfg = Config.CompressionConfig.zstdFast();
    try std.testing.expect(zstdFastCfg.enabled);
    try std.testing.expectEqual(zstdFastCfg.algorithm, .zstd);
    try std.testing.expectEqual(zstdFastCfg.level, .fastest);
    try std.testing.expectEqualStrings(".zst", zstdFastCfg.extension);

    // Test zstdBest() preset (v0.1.5+)
    const zstdBestCfg = Config.CompressionConfig.zstdBest();
    try std.testing.expect(zstdBestCfg.enabled);
    try std.testing.expectEqual(zstdBestCfg.algorithm, .zstd);
    try std.testing.expectEqual(zstdBestCfg.level, .best);
    try std.testing.expect(!zstdBestCfg.keepOriginal);

    // Test zstdProduction() preset (v0.1.5+)
    const zstdProdCfg = Config.CompressionConfig.zstdProduction();
    try std.testing.expect(zstdProdCfg.enabled);
    try std.testing.expectEqual(zstdProdCfg.algorithm, .zstd);
    try std.testing.expect(zstdProdCfg.background);
    try std.testing.expect(zstdProdCfg.checksum);
    try std.testing.expect(!zstdProdCfg.keepOriginal);

    // Test zstdWithLevel() preset (v0.1.5+)
    const zstdCustomCfg = Config.CompressionConfig.zstdWithLevel(15);
    try std.testing.expect(zstdCustomCfg.enabled);
    try std.testing.expectEqual(zstdCustomCfg.algorithm, .zstd);
    try std.testing.expectEqual(zstdCustomCfg.customZstdLevel.?, 15);
    try std.testing.expectEqual(zstdCustomCfg.getEffectiveZstdLevel(), 15);

    // Test zstd aliases (v0.1.5+)
    const zstdDefaultCfg = Config.CompressionConfig.zstd();
    try std.testing.expectEqual(zstdDefaultCfg.algorithm, .zstd);

    const zstdSpeedCfg = Config.CompressionConfig.zstdFast();
    try std.testing.expectEqual(zstdSpeedCfg.level, .fastest);

    const zstdMaxCfg = Config.CompressionConfig.zstdBest();
    try std.testing.expectEqual(zstdMaxCfg.level, .best);
}

test "compression config customization fields" {
    // Test file name customization options
    const cfg = Config.CompressionConfig{
        .enabled = true,
        .filePrefix = "archive_",
        .fileSuffix = "_compressed",
        .archiveRootDir = "logs/archive",
        .createDateSubdirs = true,
        .preserveDirStructure = false,
        .namingPattern = "{base}_{date}{ext}",
    };

    try std.testing.expect(cfg.enabled);
    try std.testing.expectEqualStrings("archive_", cfg.filePrefix.?);
    try std.testing.expectEqualStrings("_compressed", cfg.fileSuffix.?);
    try std.testing.expectEqualStrings("logs/archive", cfg.archiveRootDir.?);
    try std.testing.expect(cfg.createDateSubdirs);
    try std.testing.expect(!cfg.preserveDirStructure);
    try std.testing.expectEqualStrings("{base}_{date}{ext}", cfg.namingPattern.?);
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
    const cfgLow = Config.CompressionConfig.zstdWithLevel(-5);
    try std.testing.expectEqual(cfgLow.customZstdLevel.?, 1); // Clamped to 1

    const cfgHigh = Config.CompressionConfig.zstdWithLevel(100);
    try std.testing.expectEqual(cfgHigh.customZstdLevel.?, 22); // Clamped to 22

    const cfgValid = Config.CompressionConfig.zstdWithLevel(10);
    try std.testing.expectEqual(cfgValid.customZstdLevel.?, 10); // No clamping needed
}

test "getEffectiveZstdLevel priority" {
    // When custom_zstd_level is set, it takes priority
    var cfg = Config.CompressionConfig.zstd();
    try std.testing.expectEqual(@as(i32, 6), cfg.getEffectiveZstdLevel()); // Default enum

    cfg.customZstdLevel = 12;
    try std.testing.expectEqual(@as(i32, 12), cfg.getEffectiveZstdLevel()); // Custom takes priority

    cfg.customZstdLevel = null;
    try std.testing.expectEqual(@as(i32, 6), cfg.getEffectiveZstdLevel()); // Falls back to enum
}

test "scheduler config customization fields" {
    // Test scheduler compression customization options
    const cfg = Config.SchedulerConfig{
        .enabled = true,
        .archiveRootDir = "logs/scheduled_archive",
        .createDateSubdirs = true,
        .compressionAlgorithm = .gzip,
        .compressionLevel = .best,
        .keepOriginals = true,
        .archiveFilePrefix = "scheduled_",
        .archiveFileSuffix = "_archived",
        .preserveDirStructure = false,
        .cleanEmptyDirs = true,
        .minAgeDaysForCompression = 3,
        .maxConcurrentCompressions = 4,
    };

    try std.testing.expect(cfg.enabled);
    try std.testing.expectEqualStrings("logs/scheduled_archive", cfg.archiveRootDir.?);
    try std.testing.expect(cfg.createDateSubdirs);
    try std.testing.expectEqual(cfg.compressionAlgorithm, .gzip);
    try std.testing.expectEqual(cfg.compressionLevel, .best);
    try std.testing.expect(cfg.keepOriginals);
    try std.testing.expectEqualStrings("scheduled_", cfg.archiveFilePrefix.?);
    try std.testing.expectEqualStrings("_archived", cfg.archiveFileSuffix.?);
    try std.testing.expect(!cfg.preserveDirStructure);
    try std.testing.expect(cfg.cleanEmptyDirs);
    try std.testing.expectEqual(cfg.minAgeDaysForCompression, 3);
    try std.testing.expectEqual(cfg.maxConcurrentCompressions, 4);
}

test "rotation config customization fields" {
    // Test rotation compression customization options
    const cfg = Config.RotationConfig{
        .enabled = true,
        .archiveRootDir = "logs/rotated_archive",
        .createDateSubdirs = true,
        .filePrefix = "rotated_",
        .fileSuffix = "_old",
        .compressionAlgorithm = .deflate,
        .compressionLevel = .fast,
        .keepOriginal = true,
        .compressOnRetention = true,
        .deleteAfterRetentionCompress = false,
    };

    try std.testing.expect(cfg.enabled);
    try std.testing.expectEqualStrings("logs/rotated_archive", cfg.archiveRootDir.?);
    try std.testing.expect(cfg.createDateSubdirs);
    try std.testing.expectEqualStrings("rotated_", cfg.filePrefix.?);
    try std.testing.expectEqualStrings("_old", cfg.fileSuffix.?);
    try std.testing.expectEqual(cfg.compressionAlgorithm, .deflate);
    try std.testing.expectEqual(cfg.compressionLevel, .fast);
    try std.testing.expect(cfg.keepOriginal);
    try std.testing.expect(cfg.compressOnRetention);
    try std.testing.expect(!cfg.deleteAfterRetentionCompress);
}

test "level color config theme presets" {
    const cfgDefault = Config.LevelColorConfig{};
    try std.testing.expectEqual(cfgDefault.themePreset, .default);
    try std.testing.expect(cfgDefault.traceColor == null);

    const cfgNeon = Config.LevelColorConfig{ .themePreset = .neon };
    try std.testing.expectEqual(cfgNeon.themePreset, .neon);

    const cfgDark = Config.LevelColorConfig{ .themePreset = .dark };
    try std.testing.expectEqual(cfgDark.themePreset, .dark);

    const cfgLight = Config.LevelColorConfig{ .themePreset = .light };
    try std.testing.expectEqual(cfgLight.themePreset, .light);

    const cfgPastel = Config.LevelColorConfig{ .themePreset = .pastel };
    try std.testing.expectEqual(cfgPastel.themePreset, .pastel);
}

test "level color config individual overrides" {
    const cfg = Config.LevelColorConfig{
        .themePreset = .default,
        .traceColor = Color.Tint.color.ansi256.index(51),
        .errorColor = Color.Tint.color.ansi4.brightRed,
        .noticeColor = Color.Tint.color.ansi4.brightCyan,
        .fatalColor = Color.Tint.color.ansi4.brightWhite,
    };

    try std.testing.expectEqual(Color.Tint.color.ansi256.index(51), cfg.traceColor.?);
    try std.testing.expectEqual(Color.Tint.color.ansi4.brightRed, cfg.errorColor.?);
    try std.testing.expectEqual(Color.Tint.color.ansi4.brightCyan, cfg.noticeColor.?);
    try std.testing.expectEqual(Color.Tint.color.ansi4.brightWhite, cfg.fatalColor.?);
    try std.testing.expect(cfg.debugColor == null);
    try std.testing.expect(cfg.infoColor == null);
}

test "level color config getColorForLevel" {
    const cfgDefault = Config.LevelColorConfig{};
    try std.testing.expectEqual(Color.levelColor(.trace), cfgDefault.getColorForLevel(.trace));
    try std.testing.expectEqual(Color.levelColor(.debug), cfgDefault.getColorForLevel(.debug));
    try std.testing.expectEqual(Color.levelColor(.err), cfgDefault.getColorForLevel(.err));

    const cfgWithOverride = Config.LevelColorConfig{
        .themePreset = .default,
        .traceColor = Color.Tint.color.ansi256.index(99),
    };
    try std.testing.expectEqual(Color.Tint.color.ansi256.index(99), cfgWithOverride.getColorForLevel(.trace));
    try std.testing.expectEqual(Color.levelColor(.debug), cfgWithOverride.getColorForLevel(.debug));

    const cfgBright = Config.LevelColorConfig{ .themePreset = .bright };
    try std.testing.expectEqual(Color.Tint.color.ansi4.brightCyan, cfgBright.getColorForLevel(.trace));
    try std.testing.expectEqual(Color.Tint.color.ansi4.brightRed, cfgBright.getColorForLevel(.err));

    const cfgDim = Config.LevelColorConfig{ .themePreset = .dim };
    try std.testing.expectEqual(Color.levelColor(.trace), cfgDim.getColorForLevel(.trace));
}

test "level color config none theme" {
    const cfgNone = Config.LevelColorConfig{ .themePreset = .none };
    try std.testing.expectEqual(Color.Tint.color.ansi4.default, cfgNone.getColorForLevel(.trace));
    try std.testing.expectEqual(Color.Tint.color.ansi4.default, cfgNone.getColorForLevel(.err));
}

test "telemetry metric export helpers" {
    const base = TelemetryConfig.development();

    const jsonCfg = base.withJsonMetrics("metrics.jsonl");
    try std.testing.expectEqual(TelemetryConfig.MetricFormat.json, jsonCfg.metricFormat);
    try std.testing.expectEqualStrings("metrics.jsonl", jsonCfg.metricsFilePath.?);

    const promCfg = base.withPrometheusMetrics("metrics.prom").withMetricPrefix("api");
    try std.testing.expectEqual(TelemetryConfig.MetricFormat.prometheus, promCfg.metricFormat);
    try std.testing.expectEqualStrings("metrics.prom", promCfg.metricsFilePath.?);
    try std.testing.expectEqualStrings("api", promCfg.metricPrefix);
    try std.testing.expect(promCfg.sanitizeMetricNames);

    const rawCfg = promCfg.withMetricNameSanitization(false);
    try std.testing.expect(!rawCfg.sanitizeMetricNames);
}

/// OpenTelemetry telemetry configuration options.
pub const TelemetryConfig = struct {
    /// Optional explicit I/O handle. If null, single-threaded standard I/O is used.
    io: ?std.Io = null,

    /// Enable OpenTelemetry integration.
    enabled: bool = false,

    /// OpenTelemetry provider.
    provider: Provider = .none,

    /// Exporter endpoint URL (HTTP/gRPC endpoint).
    exporterEndpoint: ?[]const u8 = null,

    /// API key for authentication.
    apiKey: ?[]const u8 = null,

    /// Connection string (for Azure Application Insights).
    connectionString: ?[]const u8 = null,

    /// Project ID (for Google Cloud, AWS, Azure).
    projectId: ?[]const u8 = null,

    /// Region (for AWS, Azure, Google Cloud).
    region: ?[]const u8 = null,

    /// File path for file-based exporter (JSONL format).
    exporterFilePath: ?[]const u8 = null,

    /// File path for metrics export when using JSON/Prometheus formats.
    metricsFilePath: ?[]const u8 = null,

    /// Batch span export size.
    batchSize: usize = 1,

    /// Batch export timeout in milliseconds.
    batchTimeoutMs: u64 = Constants.TelemetryDefaults.batchTimeoutMs,

    /// Flush interval in milliseconds.
    flushIntervalMs: u64 = 0,

    /// Sampling strategy configuration.
    samplingStrategy: SamplingStrategy = .alwaysOn,

    /// Sampling rate (0.0 to 1.0) when using trace_id_ratio strategy.
    samplingRate: f64 = Constants.TelemetryDefaults.samplingRate,

    /// Service name for resource identification.
    serviceName: ?[]const u8 = null,

    /// Service version for resource identification.
    serviceVersion: ?[]const u8 = null,

    /// Environment name (e.g., "production", "staging", "development").
    environment: ?[]const u8 = null,

    /// Datacenter or region identifier.
    datacenter: ?[]const u8 = null,

    /// Span processor type.
    spanProcessorType: SpanProcessorType = .simple,

    /// Metric exporter format.
    metricFormat: MetricFormat = .otlp,

    /// Optional prefix applied to exported metric names.
    metricPrefix: []const u8 = Constants.TelemetryDefaults.metricPrefix,

    /// Separator inserted between `metric_prefix` and the original metric name.
    metricPrefixSeparator: []const u8 = Constants.TelemetryDefaults.metricPrefixSeparator,

    /// Sanitize metric names for exporter compatibility.
    sanitizeMetricNames: bool = Constants.TelemetryDefaults.sanitizeMetricNames,

    /// Compress span exports.
    compressExports: bool = false,

    /// Custom exporter initialization callback.
    customExporterFn: ?*const fn () anyerror!void = null,

    /// Span start event callback (span_id, name).
    onSpanStart: ?*const fn ([]const u8, []const u8) void = null,

    /// Span end event callback (span_id, duration_ns).
    onSpanEnd: ?*const fn ([]const u8, u64) void = null,

    /// Metric recorded callback (name, value).
    onMetricRecorded: ?*const fn ([]const u8, f64) void = null,

    /// Error callback (error_msg).
    onError: ?*const fn ([]const u8) void = null,

    /// Enable automatic context propagation in HTTP headers.
    autoContextPropagation: bool = true,

    /// W3C Trace Context header name for trace IDs.
    traceHeader: []const u8 = Constants.TelemetryDefaults.traceHeader,

    /// Baggage/Correlation context header name.
    baggageHeader: []const u8 = Constants.TelemetryDefaults.baggageHeader,

    /// Export format configuration.
    exportFormat: ExportFormat = .json,

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
        googleCloud,
        /// Google Analytics 4 (Measurement Protocol).
        googleAnalytics,
        /// Google Tag Manager (Server-Side).
        googleTagManager,
        /// AWS X-Ray.
        awsXray,
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
        alwaysOn,
        /// Never sample any traces.
        alwaysOff,
        /// Sample based on trace ID hash (use sampling_rate field).
        traceIdRatio,
        /// Sample based on parent decision (W3C TraceFlags).
        parentBased,
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
            .exporterEndpoint = "http://localhost:6831",
            .spanProcessorType = .batch,
            .batchSize = Constants.TelemetryDefaults.batchSize,
            .samplingStrategy = .traceIdRatio,
            .samplingRate = 0.1,
        };
    }

    /// Returns configuration for Zipkin.
    pub fn zipkin() TelemetryConfig {
        return .{
            .enabled = true,
            .provider = .zipkin,
            .exporterEndpoint = "http://localhost:9411/api/v2/spans",
            .spanProcessorType = .batch,
            .batchSize = Constants.TelemetryDefaults.zipkinBatchSize,
        };
    }

    /// Returns configuration for Datadog APM.
    pub fn datadog(apiKey: []const u8) TelemetryConfig {
        return .{
            .enabled = true,
            .provider = .datadog,
            .exporterEndpoint = "http://localhost:8126/v0.3/traces",
            .apiKey = apiKey,
            .spanProcessorType = .batch,
        };
    }

    /// Returns configuration for Google Cloud Trace.
    pub fn googleCloud(projectId: []const u8, apiKey: []const u8) TelemetryConfig {
        return .{
            .enabled = true,
            .provider = .googleCloud,
            .projectId = projectId,
            .apiKey = apiKey,
            .exporterEndpoint = "https://cloudtrace.googleapis.com/v2",
            .spanProcessorType = .batch,
        };
    }

    /// Returns configuration for AWS X-Ray.
    pub fn awsXray(region: []const u8) TelemetryConfig {
        return .{
            .enabled = true,
            .provider = .awsXray,
            .region = region,
            .exporterEndpoint = "http://localhost:2000",
            .spanProcessorType = .batch,
        };
    }

    /// Returns configuration for Azure Application Insights.
    pub fn azure(connectionString: []const u8) TelemetryConfig {
        return .{
            .enabled = true,
            .provider = .azure,
            .connectionString = connectionString,
            .exporterEndpoint = "https://dc.applicationinsights.azure.com/v2.1/track",
            .spanProcessorType = .batch,
        };
    }

    /// Returns configuration for Google Analytics 4 (Measurement Protocol).
    /// measurement_id: GA4 Measurement ID (e.g., "G-XXXXXXXXXX")
    /// api_secret: GA4 Measurement Protocol API secret
    pub fn googleAnalytics(measurementId: []const u8, apiSecret: []const u8) TelemetryConfig {
        return .{
            .enabled = true,
            .provider = .googleAnalytics,
            .projectId = measurementId,
            .apiKey = apiSecret,
            .exporterEndpoint = "https://www.google-analytics.com/mp/collect",
            .spanProcessorType = .batch,
            .batchSize = Constants.TelemetryDefaults.googleAnalyticsBatchLimit,
        };
    }

    /// Returns configuration for Google Tag Manager Server-Side.
    /// container_url: Server-side GTM container URL
    /// api_key: Optional API key for authentication
    pub fn googleTagManager(containerUrl: []const u8, apiKey: ?[]const u8) TelemetryConfig {
        return .{
            .enabled = true,
            .provider = .googleTagManager,
            .exporterEndpoint = containerUrl,
            .apiKey = apiKey,
            .spanProcessorType = .batch,
        };
    }

    /// Returns configuration for generic OpenTelemetry Collector.
    pub fn otelCollector(endpoint: []const u8) TelemetryConfig {
        return .{
            .enabled = true,
            .provider = .generic,
            .exporterEndpoint = endpoint,
            .spanProcessorType = .batch,
            .batchSize = Constants.TelemetryDefaults.collectorBatchSize,
        };
    }

    /// Returns configuration for file-based exporter (development/testing).
    pub fn file(path: []const u8) TelemetryConfig {
        return .{
            .enabled = true,
            .provider = .file,
            .exporterFilePath = path,
            .spanProcessorType = .simple,
        };
    }

    /// Returns configuration with custom exporter.
    pub fn custom(exporterFn: *const fn () anyerror!void) TelemetryConfig {
        return .{
            .enabled = true,
            .provider = .custom,
            .customExporterFn = exporterFn,
            .spanProcessorType = .simple,
        };
    }

    /// Returns high-throughput telemetry configuration with sampling.
    pub fn highThroughput() TelemetryConfig {
        return .{
            .enabled = true,
            .provider = .jaeger,
            .exporterEndpoint = "http://localhost:6831",
            .spanProcessorType = .batch,
            .batchSize = Constants.TelemetryDefaults.highThroughputBatchSize,
            .batchTimeoutMs = Constants.TelemetryDefaults.highThroughputBatchTimeoutMs,
            .samplingStrategy = .traceIdRatio,
            .samplingRate = Constants.TelemetryDefaults.highThroughputSamplingRate,
        };
    }

    /// Returns development telemetry configuration (file-based, detailed).
    pub fn development() TelemetryConfig {
        return .{
            .enabled = true,
            .provider = .file,
            .exporterFilePath = "telemetry_spans.jsonl",
            .spanProcessorType = .simple,
            .samplingStrategy = .alwaysOn,
        };
    }

    /// Returns a copy with a metric export format and path configured.
    pub fn withMetricExport(self: TelemetryConfig, format: MetricFormat, path: []const u8) TelemetryConfig {
        var cfg = self;
        cfg.metricFormat = format;
        cfg.metricsFilePath = path;
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
        cfg.metricPrefix = prefix;
        return cfg;
    }

    /// Returns a copy that controls metric name sanitization.
    pub fn withMetricNameSanitization(self: TelemetryConfig, enabled: bool) TelemetryConfig {
        var cfg = self;
        cfg.sanitizeMetricNames = enabled;
        return cfg;
    }
};
