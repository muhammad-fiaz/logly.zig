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

#### `globalColorDisplay: bool`

Enable colored output globally. Default: `true`.

#### `globalConsoleDisplay: bool`

Enable console output globally. Default: `true`.

#### `globalFileStorage: bool`

Enable file output globally. Default: `true`.

#### `format: Format`

Output format selection. Each sink renders exactly one format; a null
per-sink format inherits this logger-wide value. Default: `.text`.

Supported values (`Config.Format`):

* `.text` — human-readable text with optional color and custom templates.
* `.json` — JSON document (array framing for file sinks).
* `.ndjson` — JSON Lines, one object per line for streaming.
* `.logfmt` — logfmt `key=value` pairs.
* `.syslog` — RFC5424 syslog framing with UTC RFC3339 timestamps.
* `.syslog3164` — RFC3164 (BSD) syslog framing.
* `.msgpack` — binary MessagePack records (length-framed on streams).

Parse names with `Config.Format.fromString()` (case-insensitive); unknown
names are rejected. `SinkConfig.format` is `?Format` (`null` inherits).

#### `prettyJson: bool`

Pretty print JSON output. Default: `false`.

#### `color: bool`

Enable ANSI colors. Default: `true`.

#### `tamperEvident: bool`

Enable cryptographic log chaining where each record includes the SHA-256 hash signature of the preceding record to prevent log tampering. Default: `false`.

#### `logsRootPath: ?[]const u8`

Optional global root path for all log files. If set, file sinks will be stored relative to this path. Default: `null`.

#### `autoFlush: bool`

Automatically flush sinks after every log operation. Creates immediate output but **significantly impacts performance** in high-throughput applications. Default: `false` (for performance). Set to `true` only when immediate output visibility is critical.

> [!IMPORTANT]
> `autoFlush` and `asyncConfig` are **independent settings** that control different aspects of the logging pipeline:
> - **`autoFlush`** controls whether sinks are flushed after each log record (sync path) or after each batch (async path).
> - **`asyncConfig`** enables asynchronous logging with ring buffers and background worker threads.
> - **Thread pool dispatch does NOT flush when `autoFlush` is true** — the task is queued to the worker pool but not yet written to sinks, so no flush occurs at submission time.
>
> If you need immediate output visibility, enable `autoFlush` without async. If you need high throughput without blocking, use `asyncConfig` without `autoFlush` (relying on batch/interval flushing instead).

### Distributed Logging

#### `distributed: DistributedConfig`

Configuration for distributed tracing and service identification. Contains:
*   `enabled: bool`: Enable distributed context features.
*   `serviceName: ?[]const u8`: Name of the service (e.g. "auth-service").
*   `serviceVersion: ?[]const u8`: Version of the service.
*   `environment: ?[]const u8`: Environment (e.g. "production", "staging").
*   `datacenter: ?[]const u8`: Datacenter identifier.
*   `region: ?[]const u8`: Cloud region (e.g. "us-east-1").
*   `instanceId: ?[]const u8`: Unique instance identifier.
*   `traceHeader: []const u8`: HTTP header for Trace ID (default: `Constants.ConfigDefaults.distributedTraceHeader`).
*   `spanHeader: []const u8`: HTTP header for Span ID (default: `Constants.ConfigDefaults.distributedSpanHeader`).
*   `parentHeader: []const u8`: HTTP header for Parent Span ID (default: `Constants.ConfigDefaults.distributedParentHeader`).
*   `baggageHeader: []const u8`: HTTP header for Baggage/Correlation Context (default: `Constants.ConfigDefaults.distributedBaggageHeader`).
*   `traceSamplingRate: f64`: Sampling rate for distributed tracing 0.0 to 1.0 (default: 1.0).

Defaults for distributed headers are centralized in `Constants.ConfigDefaults` to prevent string-literal drift.

### Telemetry

#### `telemetry: TelemetryConfig`

OpenTelemetry integration configuration for trace and metric export. This section controls OTLP/Jaeger/Zipkin/Datadog/Azure/Google providers and local file exporters.

Key fields:
*   `enabled: bool` -  Enable OpenTelemetry integration (default: `false`).
*   `provider: Provider` - Provider enum (`.none`, `.jaeger`, `.zipkin`, `.datadog`, `.googleCloud`, `.googleAnalytics`, `.googleTagManager`, `.awsXray`, `.azure`, `.generic`, `.file`, `.custom`).
*   `exporterEndpoint: ?[]const u8` -  Exporter endpoint URL for HTTP/gRPC exporters (e.g., `"http://localhost:4317"`).
*   `apiKey: ?[]const u8` -  API key for providers that require authentication.
*   `connectionString: ?[]const u8` -  Connection string for Azure Application Insights.
*   `exporterFilePath: ?[]const u8` -  File path for JSONL file exporter.
*   `metricsFilePath: ?[]const u8` -  File path override for JSON/Prometheus metric exports.
*   `batchSize: usize = Constants.TelemetryDefaults.batchSize` -  Batch span export size (default: 256).
*   `batchTimeoutMs: u64 = Constants.TelemetryDefaults.batchTimeoutMs` -  Batch export timeout in ms (default: 5000).
*   `samplingStrategy: SamplingStrategy` -  Sampling strategy (`.alwaysOn`, `.alwaysOff`, `.traceIdRatio`, `.parentBased`).
*   `samplingRate: f64 = Constants.TelemetryDefaults.samplingRate` -  Sampling rate used when `traceIdRatio` is selected.
*   `serviceName`, `serviceVersion`, `environment`, `datacenter` -  Resource identification fields.
*   `spanProcessorType: SpanProcessorType = .simple` -  Span processor: `.simple` keeps completed spans pending until an explicit `exportSpans()` or `flush()` call; `.batch` will automatically export spans when the configured batch size or timeout is reached.
*   `metricFormat: MetricFormat` -  Format for metrics export (e.g., `.otlp`, `.prometheus`, `.json`).
*   `compressExports: bool` -  Whether to compress span export payloads.
*   `customExporterFn: ?*const fn () anyerror!void` -  Optional custom exporter callback for user-defined exporters.
*   `onSpanStart`, `onSpanEnd`, `onMetricRecorded`, `onError` -  Lifecycle callbacks for telemetry events.
*   `autoContextPropagation: bool` -  Automatically propagate trace/context headers (default: `true`).
*   `traceHeader: []const u8 = Constants.TelemetryDefaults.traceHeader` -  Trace header name (default: `"traceparent"`).
*   `baggageHeader: []const u8 = Constants.TelemetryDefaults.baggageHeader` -  Baggage header name (default: `"baggage"`).

Presets and factory helpers:
* `TelemetryConfig.jaeger()`, `TelemetryConfig.zipkin()`, `TelemetryConfig.datadog(apiKey)`,
  `TelemetryConfig.googleCloud(projectId, apiKey)`, `TelemetryConfig.googleAnalytics(id, secret)`,
  `TelemetryConfig.googleTagManager(url, key)`, `TelemetryConfig.awsXray(region)`,
  `TelemetryConfig.azure(connectionString)`, `TelemetryConfig.otelCollector(endpoint)`,
  `TelemetryConfig.file(path)`, `TelemetryConfig.custom(exporterFn)`,
  `TelemetryConfig.highThroughput()`, `TelemetryConfig.development()`.

Notes:
* Use `.simple` when you prefer explicit export control (call `exportSpans()` at safe points in your application). Use `.batch` for automatic behavior when you want the library to flush spans based on batch size or timeout.
* Defaults are centralized in `Constants.TelemetryDefaults` (batch size, timeout, header defaults, etc.).
* v0.1.8 includes a small OTLP exporter fix: a compile-time issue in the OTLP span writer (`writeOtlpSpan`) was resolved so the telemetry feature builds cleanly across targets.


### Display Options

#### `showTime: bool`

Show timestamp in logs. Default: `true`.

#### `showModule: bool`

Show module name. Default: `true`.

#### `showFunction: bool`

Show function name. Default: `false`.

#### `showFilename: bool`

Show filename. Default: `false`.

#### `showLineno: bool`

Show line number. Default: `false`.

#### `showThreadId: bool`

Show thread ID. Default: `false`.

#### `showProcessId: bool`

Show process ID. Default: `false`.

#### `includeHostname: bool`

Include hostname in logs (for distributed systems). Default: `false`.

#### `includePid: bool`

Include process ID in logs. Default: `false`.

#### `captureStackTrace: bool`

Capture stack traces for Error and Critical log levels. If false, stack traces will not be collected or displayed. Default: `false`.

#### `symbolizeStackTrace: bool`

Resolve memory addresses in stack traces to function names and file locations. This provides human-readable stack traces but has a performance cost. Default: `false`.

### Format Settings

#### `logFormat: ?[]const u8`

Custom format string for log messages. Available placeholders:
- `{time}` - Timestamp
- `{level}` - Log level
- `{message}` - Log message
- `{module}` - Module name
- `{function}` - Function name
- `{file}` - Filename
- `{line}` - Line number
- `{threadId}` - Thread ID
- `{pid}` - Process ID
- `{host}` - Hostname

#### `timeFormat: []const u8`

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
config.timeFormat = logly.Config.TimeFormat.iso8601;
config.timeFormat = logly.Config.TimeFormat.defaultPattern;
```

`ZZZ` and `ZZ` are important when using custom patterns in distributed systems because they preserve explicit timezone context for parsing, correlation, and incident timelines.

Default: `"YYYY-MM-DD HH:mm:ss.SSS"`.

#### `timezone: Timezone`

Timezone for timestamps. Options: `.local`, `.utc`. Default: `.local`.

Behavior details:
- `.utc`: `ISO8601` ends with `Z`, `RFC3339` uses `+00:00`.
- `.local`: uses process/system local timezone when available and emits `+/-HH:MM` offsets for `ISO8601`/`RFC3339`.

#### `formatStructure: FormatStructureConfig`

Custom format structure configuration.
- `messagePrefix`: Prefix to add before each log message.
- `messageSuffix`: Suffix to add after each log message.
- `fieldSeparator`: Separator between log fields/components.
- `enableNesting`: Enable nested/hierarchical formatting for structured logs.
- `nestingIndent`: Indentation for nested fields.
- `fieldOrder`: Custom field order.
- `includeEmptyFields`: Whether to include empty/null fields in output.
- `placeholderOpen`: Custom placeholder prefix.
- `placeholderClose`: Custom placeholder suffix.

#### `levelColors: LevelColorConfig`

Level-specific color customization with theme presets (v0.1.8).
- `themePreset`: Theme preset for base colors (`.default`, `.bright`, `.dim`, `.minimal`, `.neon`, `.pastel`, `.dark`, `.light`, `.none`).
- `traceColor`, `debugColor`, `infoColor`, `noticeColor`, `successColor`, `warningColor`, `errorColor`, `failColor`, `criticalColor`, `fatalColor`: Individual color overrides (take precedence over theme).
- `useRgb`: Use RGB color mode.
- `supportBackground`: Background color support.
- `resetCode`: Reset code at end of each log.
- `getColorForLevel(level)`: Returns the effective color (override or theme-based).

#### `highlighters: HighlighterConfig`

Highlighter patterns and alert configuration.
- `enabled`: Enable highlighter system.
- `patterns`: Pattern-based highlighters.
- `alertOnMatch`: Alert callbacks for matched patterns.
- `alertMinSeverity`: Severity level that triggers alerts.
- `alertCallback`: Custom callback function name for alerts.
- `maxMatchesPerMessage`: Maximum number of highlighter matches to track per message.
- `logMatches`: Whether to log highlighter matches as separate records.

### Feature Toggles

#### `autoSink: bool`

Automatically add a console sink on init. Default: `true`.

#### `enableCallbacks: bool`

Enable callback invocation for log events. Default: `false` (for performance). Enable only when using log callbacks.

#### `enableExceptionHandling: bool`

Enable exception/error handling within the logger. Default: `true`.

#### `enableVersionCheck: bool`

Enable version checking (for update notifications). Default: `false`.

#### `debugMode: bool`

Debug mode for internal logger diagnostics. Default: `false`.

#### `debugLogFile: ?[]const u8`

Path for internal debug log file. Default: `null`.

#### `enableTracing: bool`

Enable distributed tracing support. Default: `false`.

#### `traceHeader: []const u8`

Trace ID header name for distributed tracing. Default: `X-Trace-ID`.

#### `enableMetrics: bool`

Enable metrics collection. Default: `false`.

### Enterprise Features

#### `sampling: SamplingConfig`

Sampling configuration for high-throughput scenarios.
- `enabled`: Enable sampling.
- `strategy`: Sampling strategy (`.none`, `.probability`, `.rateLimit`, `.everyN`, `.adaptive`).

#### `rateLimit: RateLimitConfig`

Rate limiting configuration to prevent log flooding.
- `enabled`: Enable rate limiting.
- `maxPerSecond`: Maximum records per second.
- `burstSize`: Burst size.
- `perLevel`: Apply rate limiting per log level.

#### `redaction: RedactionConfig`

Redaction settings for sensitive data.
- `enabled`: Enable redaction.
- `fields`: Fields to redact.
- `patterns`: Regex patterns to redact.
- `replacement`: Replacement string.

#### `errorHandling: ErrorHandling`

Error handling behavior. Options: `.silent`, `.logAndContinue`, `.failFast`, `.callback`. Default: `.logAndContinue`.

#### `maxMessageLength: ?usize`

Maximum message length (truncate if exceeded). Default: `null`.

#### `structured: bool`

Enable structured logging with automatic context propagation. Default: `false`.

#### `defaultFields: ?[]const DefaultField`

Default context fields to include with every log.

#### `appName: ?[]const u8`

Application name for identification in distributed systems.

#### `appVersion: ?[]const u8`

Application version for tracing.

#### `environment: ?[]const u8`

Environment identifier (e.g., "production", "staging", "development").

#### `stackSize: usize`

Stack size for capturing stack traces. Default: `1MB`.

### Advanced Configuration

#### `bufferConfig: BufferConfig`

Buffer configuration for async operations.
- `size`: Buffer size.
- `flushIntervalMs`: Flush interval.
- `maxPending`: Max pending records.
- `overflowStrategy`: Overflow strategy (`.dropOldest`, `.dropNewest`, `.block`).

#### `asyncConfig: AsyncConfig`

Async logging configuration.
- `enabled`: Enable async logging.
- `bufferSize`: Buffer size for async queue.
- `batchSize`: Batch size for flushing.
- `flushIntervalMs`: Flush interval.
- `minFlushIntervalMs`: Minimum time between flushes.
- `maxLatencyMs`: Maximum latency before forcing a flush.
- `overflowPolicy`: Overflow policy (`.dropOldest`, `.dropNewest`, `.block`).
- `backgroundWorker`: Auto-start worker thread.

#### `rules: RulesConfig`

Invoke system configuration. Controls extra message display on log records.

- `enabled`: Master switch for invoke system. Default: `false`.
- `clientRulesEnabled`: Enable client-defined triggers. Default: `true`.
- `builtinRulesEnabled`: Enable built-in triggers (reserved). Default: `true`.
- `enableColors`: ANSI colors in output. Default: `true`.
- `indent`: Message indent. Default: `"    "`.
- `includeInJson`: Include in JSON output. Default: `true`.
- `consoleOutput`: Output to console (AND'd with `globalConsoleDisplay`). Default: `true`.
- `fileOutput`: Output to files (AND'd with `globalFileStorage`). Default: `true`.
- `maxRules`: Maximum triggers allowed. Default: `1000`.
- `maxMessagesPerRule`: Max messages to show per match. Default: `10`.

**Presets:**
- `RulesConfig.development()`: Colors enabled.
- `RulesConfig.production()`: No colors.
- `RulesConfig.disabled()`: Zero overhead.

#### `threadPool: ThreadPoolConfig`

Thread pool configuration.
- `enabled`: Enable thread pool.
- `threadCount`: Number of worker threads.
- `queueSize`: Maximum queue size.
- `stackSize`: Stack size per thread.
- `workStealing`: Enable work stealing.
- `threadNamePrefix`: Thread naming prefix.
- `keepAliveMs`: Keep alive time for idle threads.
- `threadAffinity`: Enable thread affinity.

#### `scheduler: SchedulerConfig`

Scheduler configuration.
- `enabled`: Enable scheduler.
- `cleanupMaxAgeDays`: Default cleanup max age.
- `maxFiles`: Default max files to keep.
- `compressBeforeCleanup`: Enable compression before cleanup.
- `filePattern`: Default file pattern for cleanup.

#### `compression: CompressionConfig`

Compression configuration.
- `enabled`: Enable compression.
- `algorithm`: Compression algorithm (`.none`, `.deflate`, `.zlib`, `.rawDeflate`, `.gzip`, `.zstd`, `.lzma`, `.lzma2`, `.xz`, `.zip`, `.tarGz`, `.lz4`).
- `level`: Compression level (`.none`, `.fastest`, `.fast`, `.default`, `.best`).
- `onRotation`: Compress on rotation.
- `keepOriginal`: Keep original file after compression.
- `mode`: Compression mode (`.disabled`, `.onRotation`, `.onSizeThreshold`, `.scheduled`, `.streaming`).
- `sizeThreshold`: Size threshold for onSizeThreshold mode.
- `bufferSize`: Buffer size for streaming compression.
- `strategy`: Compression strategy.
- `extension`: File extension for compressed files.
- `deleteAfter`: Delete files older than this after compression.
- `checksum`: Enable checksum validation.
- `streaming`: Enable streaming compression.
- `background`: Use background thread for compression.
- `dictionary`: Dictionary for compression.
- `parallel`: Enable multi-threaded compression.
- `memoryLimit`: Memory limit for compression.

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
    \\  "format": "json",
    \\  "prettyJson": false
    \\}
;

const config = try logly.Config.loadFromJson(allocator, json_data);
```

### `loadFromFile(allocator: std.mem.Allocator, filePath: []const u8) !Config`

Reads a JSON file from disk and parses it into a `Config` object.

**Example:**
```zig
const config = try logly.Config.loadFromFile(allocator, "config.json");
```

#### `enableCallbacks: bool`

Enable log callbacks. Default: `false`. Set to `true` only when using log callbacks.

#### `enableExceptionHandling: bool`

Enable exception handling within the logger. Default: `true`.

### Sampling Configuration

#### `sampling: SamplingConfig`

Sampling configuration for high-throughput scenarios.

```zig
pub const SamplingConfig = struct {
    enabled: bool = false,
    strategy: Strategy = .{ .probability = 1.0 },
    bypassLevels: ?LevelMask = null,

    pub const Strategy = union(enum) {
        none: void,
        probability: f64,
        rateLimit: SamplingRateLimitConfig,
        everyN: u32,
        adaptive: AdaptiveConfig,
        tokenBucket: TokenBucketConfig,
    };

    pub const SamplingRateLimitConfig = struct {
        maxRecords: u32,
        windowMs: u64,
    };

    pub const AdaptiveConfig = struct {
        targetRate: u32,
        minSampleRate: f64,
        maxSampleRate: f64,
        adjustmentIntervalMs: u64,
    };

    pub const TokenBucketConfig = struct {
        burstCapacity: u32,
        refillRatePerSec: u32,
    };
};
```

### Rate Limiting Configuration

#### `rateLimit: RateLimitConfig`

Rate limiting configuration to prevent log flooding.

```zig
pub const RateLimitConfig = struct {
    enabled: bool = false,
    maxPerSecond: u32 = 1000,
    burstSize: u32 = 100,
    perLevel: bool = false,
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
    defaultType: RedactionType = .full,
    enableRegex: bool = false,
    hashAlgorithm: HashAlgorithm = .sha256,
    partialStartChars: u8 = 2,
    partialEndChars: u8 = 2,
    maskChar: u8 = '*',
    truncateLength: usize = 10,
    truncateSuffix: []const u8 = "...",
    caseInsensitive: bool = true,
    auditRedactions: bool = false,
    compliancePreset: ?CompliancePreset = null,

    pub const RedactionType = enum { full, partialStart, partialEnd, hash, maskMiddle, truncate };
    pub const HashAlgorithm = enum { sha256, sha512, md5 };
    pub const CompliancePreset = enum { pciDss, hipaa, gdpr, sox, custom };

    pub fn default() RedactionConfig;
    pub fn pciDss() RedactionConfig;
    pub fn hipaa() RedactionConfig;
    pub fn gdpr() RedactionConfig;
    pub fn strict() RedactionConfig;
};
```

### Buffer Configuration

#### `bufferConfig: BufferConfig`

Buffer configuration for async writing.

```zig
pub const BufferConfig = struct {
    size: usize = 8192,
    flushIntervalMs: u64 = 1000,
    maxPending: usize = 10000,
    overflowStrategy: OverflowStrategy = .dropOldest,

    pub const OverflowStrategy = enum {
        dropOldest,
        dropNewest,
        block,
    };
};
```

### Thread Pool Configuration

#### `threadPool: ThreadPoolConfig`

Centralized thread pool configuration for parallel processing.

```zig
pub const ThreadPoolConfig = struct {
    /// Enable thread pool for parallel processing.
    enabled: bool = false,
    /// Number of worker threads (0 = auto-detect based on CPU cores).
    threadCount: usize = 0,
    /// Maximum queue size for pending tasks.
    queueSize: usize = 10000,
    /// Stack size per thread in bytes.
    stackSize: usize = 1024 * 1024,
    /// Enable work stealing between threads.
    workStealing: bool = true,
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
    cleanupMaxAgeDays: u64 = 7,
    /// Default max files to keep.
    maxFiles: ?usize = null,
    /// Enable compression before cleanup.
    compressBeforeCleanup: bool = false,
    /// Default file pattern for cleanup.
    filePattern: []const u8 = "*.log",
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
    customZstdLevel: ?i32 = null,
    /// Compress on rotation.
    onRotation: bool = true,
    /// Keep original file after compression.
    keepOriginal: bool = false,
    /// Compression mode.
    mode: Mode = .onRotation,
    /// Size threshold in bytes for on_size_threshold mode.
    sizeThreshold: u64 = 10 * 1024 * 1024,
    /// Buffer size for streaming compression.
    bufferSize: usize = 32 * 1024,
    /// Compression strategy.
    strategy: Strategy = .default,
    /// File extension for compressed files.
    extension: []const u8 = ".gz",
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
    /// Custom prefix for compressed file names
    filePrefix: ?[]const u8 = null,
    /// Custom suffix before extension
    fileSuffix: ?[]const u8 = null,
    /// Root directory for all compressed files
    archiveRootDir: ?[]const u8 = null,
    /// Create date-based subdirectories in archive root
    createDateSubdirs: bool = false,
    /// Preserve original directory structure when archiving to root dir.
    preserveDirStructure: bool = true,
    /// Custom naming pattern for compressed files.
    namingPattern: ?[]const u8 = null,

    pub const CompressionAlgorithm = enum {
        none,
        deflate,
        zlib,
        rawDeflate,
        gzip,
        zstd,
        lzma,
        lzma2,
        xz,
        tarGz,
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
    sizeLimit: ?u64 = null,

    /// Maximum number of rotated files to retain.
    retentionCount: ?usize = null,

    /// Maximum age of rotated files in seconds.
    maxAgeSeconds: ?i64 = null,

    /// Strategy for naming rotated files.
    namingStrategy: NamingStrategy = .timestamp,

    /// Optional directory to move rotated files to.
    archiveDir: ?[]const u8 = null,

    /// Whether to remove empty directories after cleanup.
    cleanEmptyDirs: bool = false,

    pub const NamingStrategy = enum {
        timestamp,
        date,
        isoDatetime,
        index,
    };
};
```

### Async Logging Configuration

#### `asyncConfig: AsyncConfig`

Centralized async logging configuration. When `asyncConfig.enabled` is `true`, the logger uses the AsyncLogger internally for high-performance buffered logging.

**Priority Order:**
1. **AsyncLogger** (when `asyncConfig.enabled = true`) - Highest performance, buffered I/O
2. **Thread Pool** (when `threadPool.enabled = true`) - Parallel processing for sync sinks  
3. **Direct Sinks** - Synchronous logging to all sinks

**Auto-flush Behavior:**
- When using AsyncLogger, `autoFlush` controls whether to flush after each log operation
- When using thread pools, flushing happens in the worker threads
- When using direct sinks, `autoFlush` triggers immediate sink flushing

**Auto-sink Integration:**
- `autoSink` works with all logging backends
- Sinks are automatically added to the appropriate backend (AsyncLogger, thread pool, or direct)

```zig
pub const AsyncConfig = struct {
    /// Enable async logging.
    enabled: bool = false,
    /// Buffer size for async queue.
    bufferSize: usize = 8192,
    /// Batch size for flushing.
    batchSize: usize = 100,
    /// Flush interval in milliseconds.
    flushIntervalMs: u64 = 100,
    /// Minimum time between flushes to avoid thrashing.
    minFlushIntervalMs: u64 = 0,
    /// Maximum latency before forcing a flush.
    maxLatencyMs: u64 = 5000,
    /// What to do when buffer is full.
    overflowPolicy: OverflowPolicy = .dropOldest,
    /// Auto-start worker thread.
    backgroundWorker: bool = true,

    pub const OverflowPolicy = enum {
        dropOldest,
        dropNewest,
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
    .bufferSize = 16384,
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
    .threadCount = 4,
});
```

### `withScheduler(config) Config`

Returns a configuration with scheduler enabled.

```zig
const config = logly.Config.default().withScheduler(.{
    .cleanupMaxAgeDays = 7,
});
```

### `merge(other) Config`

Merges another configuration into this one. Non-default values from `other` override.

```zig
const base = logly.Config.development();
const extra = logly.Config{ .format = .json };
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
config.format = .json;
config.showFilename = true;
config.timeFormat = "unix";

// Apply configuration
logger.configure(config);
```

### Production with All Features

```zig
const logly = @import("logly");

// Start with production preset and enable additional features
var config = logly.Config.production();

// Enable thread pool with 4 workers
config.threadPool = .{
    .enabled = true,
    .threadCount = 4,
    .workStealing = true,
};

// Enable async logging
config.asyncConfig = .{
    .enabled = true,
    .bufferSize = 16384,
    .batchSize = 128,
};

// Enable compression
config.compression = .{
    .enabled = true,
    .level = .best,
    .onRotation = true,
};

// Enable scheduler for maintenance
config.scheduler = .{
    .enabled = true,
    .cleanupMaxAgeDays = 14,
    .compressBeforeCleanup = true,
};

const logger = try logly.Logger.initWithConfig(allocator, config);
defer logger.deinit();
```

### Custom Log Format

```zig
var config = logly.Config.default();

// Custom format with timestamp and level
config.logFormat = "{time} | {level} | {message}";
config.timeFormat = "unix"; // Unix timestamp in seconds

logger.configure(config);
try logger.info("Formatted message", @src());
// Output: 1733299823 | INFO | Formatted message
```
