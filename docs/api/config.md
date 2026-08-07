---
title: Config API Reference
description: API reference for Logly.zig Config struct. Configure log levels, output formats, thread pools, schedulers, compression, async logging, and all enterprise features.
head:
  - - meta
    - name: keywords
      content: logly config, configuration api, logger settings, zig config struct, logging options
  - - meta
    - property: og:title
      content: Config API Reference | Logly.zig
---

# Config API

The `Config` struct controls the behavior of the logger, including all enterprise features like thread pools, schedulers, compression, and async logging through centralized configuration.

## Fields

### Core Settings

#### `level: Level`

Minimum log level to output. Default: `.info`.

#### `global_color_display: bool`

Enable colored output globally. Default: `true`.

#### `global_console_display: bool`

Enable console output globally. Default: `true`.

#### `global_file_storage: bool`

Enable file output globally. Default: `true`.

#### `json: bool`

Output logs in JSON format. Default: `false`.

#### `pretty_json: bool`

Pretty print JSON output. Default: `false`.

#### `color: bool`

Enable ANSI colors. Default: `true`.

#### `log_compact: bool`

Use compact log format. Default: `false`.

#### `msgpack: bool`

Enable MessagePack binary formatting for extremely compact log serialization. Default: `false`.

#### `tamper_evident: bool`

Enable cryptographic log chaining where each record includes the SHA-256 hash signature of the preceding record to prevent log tampering. Default: `false`.

#### `logs_root_path: ?[]const u8`

Optional global root path for all log files. If set, file sinks will be stored relative to this path. Default: `null`.

#### `auto_flush: bool`

Automatically flush sinks after every log operation. Creates immediate output but **significantly impacts performance** in high-throughput applications. Default: `false` (for performance). Set to `true` only when immediate output visibility is critical.

> [!IMPORTANT]
> `auto_flush` and `async_config` are **independent settings** that control different aspects of the logging pipeline:
> - **`auto_flush`** controls whether sinks are flushed after each log record (sync path) or after each batch (async path).
> - **`async_config`** enables asynchronous logging with ring buffers and background worker threads.
> - **Thread pool dispatch does NOT flush when `auto_flush` is true** — the task is queued to the worker pool but not yet written to sinks, so no flush occurs at submission time.
>
> If you need immediate output visibility, enable `auto_flush` without async. If you need high throughput without blocking, use `async_config` without `auto_flush` (relying on batch/interval flushing instead).

### Distributed Logging

#### `distributed: DistributedConfig`

Configuration for distributed tracing and service identification. Contains:
*   `enabled: bool`: Enable distributed context features.
*   `service_name: ?[]const u8`: Name of the service (e.g. "auth-service").
*   `service_version: ?[]const u8`: Version of the service.
*   `environment: ?[]const u8`: Environment (e.g. "production", "staging").
*   `datacenter: ?[]const u8`: Datacenter identifier.
*   `region: ?[]const u8`: Cloud region (e.g. "us-east-1").
*   `instance_id: ?[]const u8`: Unique instance identifier.
*   `trace_header: []const u8`: HTTP header for Trace ID (default: `Constants.ConfigDefaults.distributed_trace_header`).
*   `span_header: []const u8`: HTTP header for Span ID (default: `Constants.ConfigDefaults.distributed_span_header`).
*   `parent_header: []const u8`: HTTP header for Parent Span ID (default: `Constants.ConfigDefaults.distributed_parent_header`).
*   `baggage_header: []const u8`: HTTP header for Baggage/Correlation Context (default: `Constants.ConfigDefaults.distributed_baggage_header`).
*   `trace_sampling_rate: f64`: Sampling rate for distributed tracing 0.0 to 1.0 (default: 1.0).

Defaults for distributed headers are centralized in `Constants.ConfigDefaults` to prevent string-literal drift.

### Telemetry

#### `telemetry: TelemetryConfig`

OpenTelemetry integration configuration for trace and metric export. This section controls OTLP/Jaeger/Zipkin/Datadog/Azure/Google providers and local file exporters.

Key fields:
*   `enabled: bool` -  Enable OpenTelemetry integration (default: `false`).
*   `provider: Provider` - Provider enum (`.none`, `.jaeger`, `.zipkin`, `.datadog`, `.google_cloud`, `.google_analytics`, `.google_tag_manager`, `.aws_xray`, `.azure`, `.generic`, `.file`, `.custom`).
*   `exporter_endpoint: ?[]const u8` -  Exporter endpoint URL for HTTP/gRPC exporters (e.g., `"http://localhost:4317"`).
*   `api_key: ?[]const u8` -  API key for providers that require authentication.
*   `connection_string: ?[]const u8` -  Connection string for Azure Application Insights.
*   `exporter_file_path: ?[]const u8` -  File path for JSONL file exporter.
*   `metrics_file_path: ?[]const u8` -  File path override for JSON/Prometheus metric exports.
*   `batch_size: usize = Constants.TelemetryDefaults.batch_size` -  Batch span export size (default: 256).
*   `batch_timeout_ms: u64 = Constants.TelemetryDefaults.batch_timeout_ms` -  Batch export timeout in ms (default: 5000).
*   `sampling_strategy: SamplingStrategy` -  Sampling strategy (`.always_on`, `.always_off`, `.trace_id_ratio`, `.parent_based`).
*   `sampling_rate: f64 = Constants.TelemetryDefaults.sampling_rate` -  Sampling rate used when `trace_id_ratio` is selected.
*   `service_name`, `service_version`, `environment`, `datacenter` -  Resource identification fields.
*   `span_processor_type: SpanProcessorType = .simple` -  Span processor: `.simple` keeps completed spans pending until an explicit `exportSpans()` or `flush()` call; `.batch` will automatically export spans when the configured batch size or timeout is reached.
*   `metric_format: MetricFormat` -  Format for metrics export (e.g., `.otlp`, `.prometheus`, `.json`).
*   `compress_exports: bool` -  Whether to compress span export payloads.
*   `custom_exporter_fn: ?*const fn () anyerror!void` -  Optional custom exporter callback for user-defined exporters.
*   `on_span_start`, `on_span_end`, `on_metric_recorded`, `on_error` -  Lifecycle callbacks for telemetry events.
*   `auto_context_propagation: bool` -  Automatically propagate trace/context headers (default: `true`).
*   `trace_header: []const u8 = Constants.TelemetryDefaults.trace_header` -  Trace header name (default: `"traceparent"`).
*   `baggage_header: []const u8 = Constants.TelemetryDefaults.baggage_header` -  Baggage header name (default: `"baggage"`).

Presets and factory helpers:
* `TelemetryConfig.jaeger()`, `TelemetryConfig.zipkin()`, `TelemetryConfig.datadog(api_key)`,
  `TelemetryConfig.googleCloud(project_id, api_key)`, `TelemetryConfig.googleAnalytics(id, secret)`,
  `TelemetryConfig.googleTagManager(url, key)`, `TelemetryConfig.awsXray(region)`,
  `TelemetryConfig.azure(connection_string)`, `TelemetryConfig.otelCollector(endpoint)`,
  `TelemetryConfig.file(path)`, `TelemetryConfig.custom(exporter_fn)`,
  `TelemetryConfig.highThroughput()`, `TelemetryConfig.development()`.

Notes:
* Use `.simple` when you prefer explicit export control (call `exportSpans()` at safe points in your application). Use `.batch` for automatic behavior when you want the library to flush spans based on batch size or timeout.
* Defaults are centralized in `Constants.TelemetryDefaults` (batch size, timeout, header defaults, etc.).
* v0.1.8 includes a small OTLP exporter fix: a compile-time issue in the OTLP span writer (`writeOtlpSpan`) was resolved so the telemetry feature builds cleanly across targets.


### Display Options

#### `show_time: bool`

Show timestamp in logs. Default: `true`.

#### `show_module: bool`

Show module name. Default: `true`.

#### `show_function: bool`

Show function name. Default: `false`.

#### `show_filename: bool`

Show filename. Default: `false`.

#### `show_lineno: bool`

Show line number. Default: `false`.

#### `show_thread_id: bool`

Show thread ID. Default: `false`.

#### `show_process_id: bool`

Show process ID. Default: `false`.

#### `include_hostname: bool`

Include hostname in logs (for distributed systems). Default: `false`.

#### `include_pid: bool`

Include process ID in logs. Default: `false`.

#### `capture_stack_trace: bool`

Capture stack traces for Error and Critical log levels. If false, stack traces will not be collected or displayed. Default: `false`.

#### `symbolize_stack_trace: bool`

Resolve memory addresses in stack traces to function names and file locations. This provides human-readable stack traces but has a performance cost. Default: `false`.

### Format Settings

#### `log_format: ?[]const u8`

Custom format string for log messages. Available placeholders:
- `{time}` - Timestamp
- `{level}` - Log level
- `{message}` - Log message
- `{module}` - Module name
- `{function}` - Function name
- `{file}` - Filename
- `{line}` - Line number
- `{thread_id}` - Thread ID
- `{pid}` - Process ID
- `{host}` - Hostname

#### `time_format: []const u8`

Time format string. Supported formats:
- `"YYYY-MM-DD HH:mm:ss.SSS"` - Default human-readable format with milliseconds
- `"default"` - Alias that resolves to the default human-readable pattern
- `"ISO8601"` - ISO 8601 format (e.g., `2025-12-04T06:39:53.091Z`)
- `"RFC3339"` - RFC 3339 format (e.g., `2025-12-04T06:39:53+00:00`)
- `"YYYY-MM-DD"` - Date only
- `"HH:mm:ss"` - Time only
- `"HH:mm:ss.SSS"` - Time with milliseconds
- `"unix"` - Unix timestamp in seconds
- `"unix_ms"` - Unix timestamp in milliseconds
- Custom timezone placeholders are also supported in pattern formats:
    - `ZZZ` => `+HH:MM` (e.g. `+01:00`)
    - `ZZ` => `+HHMM` (e.g. `+0100`)

For production code, prefer centralized constants over raw string literals:

```zig
config.time_format = logly.Config.TimeFormat.iso8601;
config.time_format = logly.Config.TimeFormat.default_pattern;
```

`ZZZ` and `ZZ` are important when using custom patterns in distributed systems because they preserve explicit timezone context for parsing, correlation, and incident timelines.

Default: `"YYYY-MM-DD HH:mm:ss.SSS"`.

#### `timezone: Timezone`

Timezone for timestamps. Options: `.local`, `.utc`. Default: `.local`.

Behavior details:
- `.utc`: `ISO8601` ends with `Z`, `RFC3339` uses `+00:00`.
- `.local`: uses process/system local timezone when available and emits `+/-HH:MM` offsets for `ISO8601`/`RFC3339`.

#### `format_structure: FormatStructureConfig`

Custom format structure configuration.
- `message_prefix`: Prefix to add before each log message.
- `message_suffix`: Suffix to add after each log message.
- `field_separator`: Separator between log fields/components.
- `enable_nesting`: Enable nested/hierarchical formatting for structured logs.
- `nesting_indent`: Indentation for nested fields.
- `field_order`: Custom field order.
- `include_empty_fields`: Whether to include empty/null fields in output.
- `placeholder_open`: Custom placeholder prefix.
- `placeholder_close`: Custom placeholder suffix.

#### `level_colors: LevelColorConfig`

Level-specific color customization with theme presets (v0.1.8).
- `theme_preset`: Theme preset for base colors (`.default`, `.bright`, `.dim`, `.minimal`, `.neon`, `.pastel`, `.dark`, `.light`, `.none`).
- `trace_color`, `debug_color`, `info_color`, `notice_color`, `success_color`, `warning_color`, `error_color`, `fail_color`, `critical_color`, `fatal_color`: Individual color overrides (take precedence over theme).
- `use_rgb`: Use RGB color mode.
- `support_background`: Background color support.
- `reset_code`: Reset code at end of each log.
- `getColorForLevel(level)`: Returns the effective color (override or theme-based).

#### `highlighters: HighlighterConfig`

Highlighter patterns and alert configuration.
- `enabled`: Enable highlighter system.
- `patterns`: Pattern-based highlighters.
- `alert_on_match`: Alert callbacks for matched patterns.
- `alert_min_severity`: Severity level that triggers alerts.
- `alert_callback`: Custom callback function name for alerts.
- `max_matches_per_message`: Maximum number of highlighter matches to track per message.
- `log_matches`: Whether to log highlighter matches as separate records.

### Feature Toggles

#### `auto_sink: bool`

Automatically add a console sink on init. Default: `true`.

#### `enable_callbacks: bool`

Enable callback invocation for log events. Default: `false` (for performance). Enable only when using log callbacks.

#### `enable_exception_handling: bool`

Enable exception/error handling within the logger. Default: `true`.

#### `enable_version_check: bool`

Enable version checking (for update notifications). Default: `false`.

#### `debug_mode: bool`

Debug mode for internal logger diagnostics. Default: `false`.

#### `debug_log_file: ?[]const u8`

Path for internal debug log file. Default: `null`.

#### `enable_tracing: bool`

Enable distributed tracing support. Default: `false`.

#### `trace_header: []const u8`

Trace ID header name for distributed tracing. Default: `X-Trace-ID`.

#### `enable_metrics: bool`

Enable metrics collection. Default: `false`.

### Enterprise Features

#### `sampling: SamplingConfig`

Sampling configuration for high-throughput scenarios.
- `enabled`: Enable sampling.
- `strategy`: Sampling strategy (`.none`, `.probability`, `.rate_limit`, `.every_n`, `.adaptive`).

#### `rate_limit: RateLimitConfig`

Rate limiting configuration to prevent log flooding.
- `enabled`: Enable rate limiting.
- `max_per_second`: Maximum records per second.
- `burst_size`: Burst size.
- `per_level`: Apply rate limiting per log level.

#### `redaction: RedactionConfig`

Redaction settings for sensitive data.
- `enabled`: Enable redaction.
- `fields`: Fields to redact.
- `patterns`: Regex patterns to redact.
- `replacement`: Replacement string.

#### `error_handling: ErrorHandling`

Error handling behavior. Options: `.silent`, `.log_and_continue`, `.fail_fast`, `.callback`. Default: `.log_and_continue`.

#### `max_message_length: ?usize`

Maximum message length (truncate if exceeded). Default: `null`.

#### `structured: bool`

Enable structured logging with automatic context propagation. Default: `false`.

#### `default_fields: ?[]const DefaultField`

Default context fields to include with every log.

#### `app_name: ?[]const u8`

Application name for identification in distributed systems.

#### `app_version: ?[]const u8`

Application version for tracing.

#### `environment: ?[]const u8`

Environment identifier (e.g., "production", "staging", "development").

#### `stack_size: usize`

Stack size for capturing stack traces. Default: `1MB`.

### Advanced Configuration

#### `buffer_config: BufferConfig`

Buffer configuration for async operations.
- `size`: Buffer size.
- `flush_interval_ms`: Flush interval.
- `max_pending`: Max pending records.
- `overflow_strategy`: Overflow strategy (`.drop_oldest`, `.drop_newest`, `.block`).

#### `async_config: AsyncConfig`

Async logging configuration.
- `enabled`: Enable async logging.
- `buffer_size`: Buffer size for async queue.
- `batch_size`: Batch size for flushing.
- `flush_interval_ms`: Flush interval.
- `min_flush_interval_ms`: Minimum time between flushes.
- `max_latency_ms`: Maximum latency before forcing a flush.
- `overflow_policy`: Overflow policy (`.drop_oldest`, `.drop_newest`, `.block`).
- `background_worker`: Auto-start worker thread.

#### `rules: RulesConfig`

Invoke system configuration. Controls extra message display on log records.

- `enabled`: Master switch for invoke system. Default: `false`.
- `client_rules_enabled`: Enable client-defined triggers. Default: `true`.
- `builtin_rules_enabled`: Enable built-in triggers (reserved). Default: `true`.
- `enable_colors`: ANSI colors in output. Default: `true`.
- `indent`: Message indent. Default: `"    "`.
- `include_in_json`: Include in JSON output. Default: `true`.
- `console_output`: Output to console (AND'd with `global_console_display`). Default: `true`.
- `file_output`: Output to files (AND'd with `global_file_storage`). Default: `true`.
- `max_rules`: Maximum triggers allowed. Default: `1000`.
- `max_messages_per_rule`: Max messages to show per match. Default: `10`.

**Presets:**
- `RulesConfig.development()`: Colors enabled.
- `RulesConfig.production()`: No colors.
- `RulesConfig.disabled()`: Zero overhead.

#### `thread_pool: ThreadPoolConfig`

Thread pool configuration.
- `enabled`: Enable thread pool.
- `thread_count`: Number of worker threads.
- `queue_size`: Maximum queue size.
- `stack_size`: Stack size per thread.
- `work_stealing`: Enable work stealing.
- `thread_name_prefix`: Thread naming prefix.
- `keep_alive_ms`: Keep alive time for idle threads.
- `thread_affinity`: Enable thread affinity.

#### `scheduler: SchedulerConfig`

Scheduler configuration.
- `enabled`: Enable scheduler.
- `cleanup_max_age_days`: Default cleanup max age.
- `max_files`: Default max files to keep.
- `compress_before_cleanup`: Enable compression before cleanup.
- `file_pattern`: Default file pattern for cleanup.

#### `compression: CompressionConfig`

Compression configuration.
- `enabled`: Enable compression.
- `algorithm`: Compression algorithm (`.none`, `.deflate`, `.zlib`, `.raw_deflate`, `.gzip`, `.zstd`, `.lzma`, `.lzma2`, `.xz`, `.zip`, `.tar_gz`, `.lz4`).
- `level`: Compression level (`.none`, `.fastest`, `.fast`, `.default`, `.best`).
- `on_rotation`: Compress on rotation.
- `keep_original`: Keep original file after compression.
- `mode`: Compression mode (`.disabled`, `.on_rotation`, `.on_size_threshold`, `.scheduled`, `.streaming`).
- `size_threshold`: Size threshold for on_size_threshold mode.
- `buffer_size`: Buffer size for streaming compression.
- `strategy`: Compression strategy.
- `extension`: File extension for compressed files.
- `delete_after`: Delete files older than this after compression.
- `checksum`: Enable checksum validation.
- `streaming`: Enable streaming compression.
- `background`: Use background thread for compression.
- `dictionary`: Dictionary for compression.
- `parallel`: Enable multi-threaded compression.
- `memory_limit`: Memory limit for compression.

## Presets

Logly provides several configuration presets for common scenarios.

### `Config.default()`

Returns the default configuration.
- Level: `.info`
- Colors: Enabled
- Output: Console and File enabled

### `Config.production()`

Optimized for production environments.
- Level: `.info`
- Colors: Disabled (for cleaner logs)
- JSON: Enabled (for parsing)
- Async: Enabled (for performance)
- Metrics: Enabled
- Structured: Enabled
- Compression: Enabled (on rotation)
- Scheduler: Enabled (cleanup old logs)

### `Config.development()`

Optimized for development environments.
- Level: `.debug`
- Colors: Enabled
- Source Info: Function, File, Line enabled
- Debug Mode: Enabled

### `Config.highThroughput()`

Optimized for high-volume logging.
- Level: `.warning`
- Sampling: Adaptive (target 1000/sec)
- Rate Limit: 10000/sec
- Buffer: 64KB
- Thread Pool: Enabled (auto-detect threads)
- Async: Enabled (aggressive batching)

### `Config.secure()`

Compliant with security standards.
- Redaction: Enabled
- Structured: Enabled
- Hostname/PID: Disabled (minimize info leakage)

## Builder Methods

Helper methods to modify configuration fluently.

### `withAsync(config: AsyncConfig) Config`

Enables async logging with the provided configuration.

### `withCompression(config: CompressionConfig) Config`

Enables compression with the provided configuration.

### `withCompressionEnabled() Config`

Enables compression with default settings.

### `withImplicitCompression() Config`

Enables automatic compression on rotation.

### `withExplicitCompression() Config`

Enables manual compression control.

### `withFastCompression() Config`

Enables fast compression (speed priority).

### `withBestCompression() Config`

Enables best compression (ratio priority).

### `withBackgroundCompression() Config`

Enables background thread compression.

### `withLogCompression() Config`

Enables log-optimized compression (text strategy).

### `withProductionCompression() Config`

Enables production-ready compression (balanced, checksums, background).

### Zstd Compression Methods (v0.1.8+)

### `withZstdCompression() Config`

Enables default zstd compression (level 6). Uses `.zst` extension.

### `withZstdFastCompression() Config`

Enables fast zstd compression (level 1). Prioritizes speed over ratio.

### `withZstdBestCompression() Config`

Enables best zstd compression (level 19). Prioritizes ratio over speed.

### `withZstdProductionCompression() Config`

Enables production zstd compression with background processing and checksums.

### `withThreadPool(config: ThreadPoolConfig) Config`

Enables thread pool with the provided configuration.

### `withScheduler(config: SchedulerConfig) Config`

Enables scheduler with the provided configuration.

### `merge(other: Config) Config`

Merges another configuration into the current one. Non-default values from `other` override the current values.

## JSON Configuration Loading

Logly v0.2.0 supports parsing and loading configuration dynamically from JSON files and slices. Standard configurations can be easily loaded using these helpers:

### `loadFromJson(allocator: std.mem.Allocator, json_slice: []const u8) !Config`

Parses a JSON configuration string and returns a complete `Config` object initialized with those values.

- Handles case-insensitive level strings (e.g. `"DEBUG"`, `"debug"`).
- Automatically maps custom levels, sinks, formats, and basic filters.

**Example:**
```zig
const json_data = 
    \\{
    \\  "level": "debug",
    \\  "json": true,
    \\  "pretty_json": false,
    \\  "msgpack": true
    \\}
;

const config = try logly.Config.loadFromJson(allocator, json_data);
```

### `loadFromFile(allocator: std.mem.Allocator, file_path: []const u8) !Config`

Reads a JSON file from disk and parses it into a `Config` object.

**Example:**
```zig
const config = try logly.Config.loadFromFile(allocator, "config.json");
```

#### `enable_callbacks: bool`

Enable log callbacks. Default: `false`. Set to `true` only when using log callbacks.

#### `enable_exception_handling: bool`

Enable exception handling within the logger. Default: `true`.

### Sampling Configuration

#### `sampling: SamplingConfig`

Sampling configuration for high-throughput scenarios.

```zig
pub const SamplingConfig = struct {
    enabled: bool = false,
    strategy: Strategy = .{ .probability = 1.0 },
    bypass_levels: ?LevelMask = null,

    pub const Strategy = union(enum) {
        none: void,
        probability: f64,
        rate_limit: SamplingRateLimitConfig,
        every_n: u32,
        adaptive: AdaptiveConfig,
        token_bucket: TokenBucketConfig,
    };

    pub const SamplingRateLimitConfig = struct {
        max_records: u32,
        window_ms: u64,
    };

    pub const AdaptiveConfig = struct {
        target_rate: u32,
        min_sample_rate: f64,
        max_sample_rate: f64,
        adjustment_interval_ms: u64,
    };

    pub const TokenBucketConfig = struct {
        burst_capacity: u32,
        refill_rate_per_sec: u32,
    };
};
```

### Rate Limiting Configuration

#### `rate_limit: RateLimitConfig`

Rate limiting configuration to prevent log flooding.

```zig
pub const RateLimitConfig = struct {
    enabled: bool = false,
    max_per_second: u32 = 1000,
    burst_size: u32 = 100,
    per_level: bool = false,
};
```

### Redaction Configuration

#### `redaction: RedactionConfig`

Sensitive data redaction configuration.

```zig
pub const RedactionConfig = struct {
    enabled: bool = false,
    fields: ?[]const []const u8 = null,
    patterns: ?[]const []const u8 = null,
    replacement: []const u8 = "[REDACTED]",
    default_type: RedactionType = .full,
    enable_regex: bool = false,
    hash_algorithm: HashAlgorithm = .sha256,
    partial_start_chars: u8 = 2,
    partial_end_chars: u8 = 2,
    mask_char: u8 = '*',
    truncate_length: usize = 10,
    truncate_suffix: []const u8 = "...",
    case_insensitive: bool = true,
    audit_redactions: bool = false,
    compliance_preset: ?CompliancePreset = null,

    pub const RedactionType = enum { full, partial_start, partial_end, hash, mask_middle, truncate };
    pub const HashAlgorithm = enum { sha256, sha512, md5 };
    pub const CompliancePreset = enum { pci_dss, hipaa, gdpr, sox, custom };

    pub fn default() RedactionConfig;
    pub fn pciDss() RedactionConfig;
    pub fn hipaa() RedactionConfig;
    pub fn gdpr() RedactionConfig;
    pub fn strict() RedactionConfig;
};
```

### Buffer Configuration

#### `buffer_config: BufferConfig`

Buffer configuration for async writing.

```zig
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
```

### Thread Pool Configuration

#### `thread_pool: ThreadPoolConfig`

Centralized thread pool configuration for parallel processing.

```zig
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
};
```

### Scheduler Configuration

#### `scheduler: SchedulerConfig`

Centralized scheduler configuration for automated log maintenance.

```zig
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
```

### Compression Configuration

#### `compression: CompressionConfig`

Centralized compression configuration.

```zig
pub const CompressionConfig = struct {
    /// Enable compression.
    enabled: bool = false,
    /// Compression algorithm.
    algorithm: CompressionAlgorithm = .deflate,
    /// Compression level.
    level: CompressionLevel = .default,
    /// Custom zstd level (1-22). If set, overrides the level enum for zstd.
    custom_zstd_level: ?i32 = null,
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
    /// Custom prefix for compressed file names
    file_prefix: ?[]const u8 = null,
    /// Custom suffix before extension
    file_suffix: ?[]const u8 = null,
    /// Root directory for all compressed files
    archive_root_dir: ?[]const u8 = null,
    /// Create date-based subdirectories in archive root
    create_date_subdirs: bool = false,
    /// Preserve original directory structure when archiving to root dir.
    preserve_dir_structure: bool = true,
    /// Custom naming pattern for compressed files.
    naming_pattern: ?[]const u8 = null,

    pub const CompressionAlgorithm = enum {
        none,
        deflate,
        zlib,
        raw_deflate,
        gzip,
        zstd,
        lzma,
        lzma2,
        xz,
        tar_gz,
        zip,
        lz4,
    };

    pub const CompressionLevel = enum {
        none,
        fastest,
        fast,
        default,
        best,

        /// Convert to zstd compression level (1-22).
        pub fn toZstdLevel(self: CompressionLevel) i32;
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

    // Preset factory methods
    pub fn enable() CompressionConfig;
    pub fn disable() CompressionConfig;
    pub fn fast() CompressionConfig;
    pub fn balanced() CompressionConfig;
    pub fn best() CompressionConfig;
    pub fn production() CompressionConfig;
    pub fn development() CompressionConfig;
    pub fn forLogs() CompressionConfig;
    pub fn archive() CompressionConfig;
    pub fn backgroundMode() CompressionConfig;
    pub fn streamingMode() CompressionConfig;
    
    // Zstd presets
    pub fn zstd() CompressionConfig;
    pub fn zstdFast() CompressionConfig;
    pub fn zstdBest() CompressionConfig;
    pub fn zstdProduction() CompressionConfig;
    pub fn zstdWithLevel(level: i32) CompressionConfig;

    // New algorithms presets
    pub fn lzma() CompressionConfig;
    pub fn lzma2() CompressionConfig;
    pub fn xz() CompressionConfig;
    pub fn tarGz() CompressionConfig;
    pub fn zip() CompressionConfig;
    pub fn lz4() CompressionConfig;
};
```


### Rotation Configuration

#### `rotation: RotationConfig`

Global rotation and retention settings.

```zig
pub const RotationConfig = struct {
    /// Enable default rotation for file sinks.
    enabled: bool = false,

    /// Default rotation interval (e.g., "daily", "hourly").
    interval: ?[]const u8 = null,

    /// Default size limit for rotation (in bytes).
    size_limit: ?u64 = null,

    /// Maximum number of rotated files to retain.
    retention_count: ?usize = null,

    /// Maximum age of rotated files in seconds.
    max_age_seconds: ?i64 = null,

    /// Strategy for naming rotated files.
    naming_strategy: NamingStrategy = .timestamp,

    /// Optional directory to move rotated files to.
    archive_dir: ?[]const u8 = null,

    /// Whether to remove empty directories after cleanup.
    clean_empty_dirs: bool = false,

    pub const NamingStrategy = enum {
        timestamp,
        date,
        iso_datetime,
        index,
    };
};
```

### Async Logging Configuration

#### `async_config: AsyncConfig`

Centralized async logging configuration. When `async_config.enabled` is `true`, the logger uses the AsyncLogger internally for high-performance buffered logging.

**Priority Order:**
1. **AsyncLogger** (when `async_config.enabled = true`) - Highest performance, buffered I/O
2. **Thread Pool** (when `thread_pool.enabled = true`) - Parallel processing for sync sinks  
3. **Direct Sinks** - Synchronous logging to all sinks

**Auto-flush Behavior:**
- When using AsyncLogger, `auto_flush` controls whether to flush after each log operation
- When using thread pools, flushing happens in the worker threads
- When using direct sinks, `auto_flush` triggers immediate sink flushing

**Auto-sink Integration:**
- `auto_sink` works with all logging backends
- Sinks are automatically added to the appropriate backend (AsyncLogger, thread pool, or direct)

```zig
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
```

## Methods

### `default() Config`

Returns the default configuration.

```zig
const config = logly.Config.default();
```

### `merge(other: Config) void`

Merges another configuration into this one. Values from `other` take precedence over `self`.

```zig
var config = Config.default();
const overrides = Config{ .level = .debug };
config.merge(overrides);
```

### `production() Config`

Returns a production-optimized configuration:
- Level: `.info`
- JSON format enabled
- Colors disabled
- Sampling enabled (10%)
- Metrics enabled
- Structured logging
- Compression enabled (on rotation)
- Scheduler enabled (auto cleanup, 30-day retention)

```zig
const config = logly.Config.production();
```

### `development() Config`

Returns a development-friendly configuration:
- Level: `.debug`
- Colors enabled
- Source location shown
- Debug mode enabled

```zig
const config = logly.Config.development();
```

### `highThroughput() Config`

Returns a high-throughput optimized configuration:
- Level: `.warning`
- Large buffers (64KB)
- Aggressive sampling (50%, adaptive)
- Rate limiting enabled (10,000/sec)
- Thread pool enabled (auto-detect cores)
- Async logging enabled (32KB buffer, 256 batch size)

```zig
const config = logly.Config.highThroughput();
```

### `secure() Config`

Returns a security-focused configuration:
- Redaction enabled
- Structured logging
- No hostname/PID exposure

```zig
const config = logly.Config.secure();
```

### `withAsync(config) Config`

Returns a configuration with async logging enabled.

```zig
const config = logly.Config.default().withAsync(.{
    .buffer_size = 16384,
});
```

### `withCompression(config) Config`

Returns a configuration with compression enabled.

```zig
const config = logly.Config.default().withCompression(.{
    .algorithm = .deflate,
});
```

### `withThreadPool(config) Config`

Returns a configuration with thread pool enabled.

```zig
const config = logly.Config.default().withThreadPool(.{
    .thread_count = 4,
});
```

### `withScheduler(config) Config`

Returns a configuration with scheduler enabled.

```zig
const config = logly.Config.default().withScheduler(.{
    .cleanup_max_age_days = 7,
});
```

### `merge(other) Config`

Merges another configuration into this one. Non-default values from `other` override.

```zig
const base = logly.Config.development();
const extra = logly.Config{ .json = true };
const merged = base.merge(extra);
```

## ConfigPresets

Convenience wrapper for preset configurations:

```zig
const logly = @import("logly");

// Use presets
const prod = logly.ConfigPresets.production();
const dev = logly.ConfigPresets.development();
const high = logly.ConfigPresets.highThroughput();
const sec = logly.ConfigPresets.secure();
```

## Re-exported Config Types

For convenience, nested config types are re-exported from the main logly module:

```zig
const logly = @import("logly");

// All available directly
const ThreadPoolConfig = logly.ThreadPoolConfig;
const SchedulerConfig = logly.SchedulerConfig;
const CompressionConfig = logly.CompressionConfig;
const AsyncConfig = logly.AsyncConfig;
const SamplingConfig = logly.SamplingConfig;
const RateLimitConfig = logly.RateLimitConfig;
const RedactionConfig = logly.RedactionConfig;
const BufferConfig = logly.BufferConfig;
```

## Example Usage

### Basic Configuration

```zig
const logly = @import("logly");

const logger = try logly.Logger.init(allocator);
defer logger.deinit();

// Configure with custom settings
var config = logly.Config.default();
config.level = .debug;
config.json = true;
config.show_filename = true;
config.time_format = "unix";

// Apply configuration
logger.configure(config);
```

### Production with All Features

```zig
const logly = @import("logly");

// Start with production preset and enable additional features
var config = logly.Config.production();

// Enable thread pool with 4 workers
config.thread_pool = .{
    .enabled = true,
    .thread_count = 4,
    .work_stealing = true,
};

// Enable async logging
config.async_config = .{
    .enabled = true,
    .buffer_size = 16384,
    .batch_size = 128,
};

// Enable compression
config.compression = .{
    .enabled = true,
    .level = .best,
    .on_rotation = true,
};

// Enable scheduler for maintenance
config.scheduler = .{
    .enabled = true,
    .cleanup_max_age_days = 14,
    .compress_before_cleanup = true,
};

const logger = try logly.Logger.initWithConfig(allocator, config);
defer logger.deinit();
```

### Custom Log Format

```zig
var config = logly.Config.default();

// Custom format with timestamp and level
config.log_format = "{time} | {level} | {message}";
config.time_format = "unix"; // Unix timestamp in seconds

logger.configure(config);
try logger.info("Formatted message", @src());
// Output: 1733299823 | INFO | Formatted message
```
