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

#### `check_for_updates: bool`

Check GitHub for the latest Logly release on startup. Runs in a background thread and prints a highlighted notice when a newer version is available. Default: `true`.

#### `emit_system_diagnostics_on_init: bool`

Emit a single system diagnostics log (OS, arch, CPU, cores, memory) when the logger initializes. Default: `false`.

#### `include_drive_diagnostics: bool`

When emitting diagnostics, include per-drive totals and free space. Applies to startup diagnostics and manual `logSystemDiagnostics` calls. Default: `true`.

#### `log_compact: bool`

Use compact log format. Default: `false`.

#### `use_arena_allocator: bool`

Enable arena allocator for the main logger instance. When enabled, the logger uses an arena allocator for creating log records, which can improve performance by reducing memory fragmentation and allocation overhead. Default: `false`.

#### `arena_reset_threshold: usize`

Arena reset threshold in bytes. When arena reaches this size, it resets. Default: `64 * 1024`.

#### `logs_root_path: ?[]const u8`

Optional global root path for all log files. If set, file sinks will be stored relative to this path. Default: `null`.

#### `diagnostics_output_path: ?[]const u8`

If set, system diagnostics will be stored at this path. Default: `null`.

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
- `"YYYY-MM-DD HH:mm:ss"` - Default human-readable format with milliseconds
- `"ISO8601"` - ISO 8601 format (e.g., `2025-12-04T06:39:53.091Z`)
- `"RFC3339"` - RFC 3339 format (e.g., `2025-12-04T06:39:53+00:00`)
- `"YYYY-MM-DD"` - Date only
- `"HH:mm:ss"` - Time only
- `"HH:mm:ss.SSS"` - Time with milliseconds
- `"unix"` - Unix timestamp in seconds
- `"unix_ms"` - Unix timestamp in milliseconds

Default: `"YYYY-MM-DD HH:mm:ss.SSS"`.

#### `timezone: Timezone`

Timezone for timestamps. Options: `.local`, `.utc`. Default: `.local`.

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

Level-specific color customization.
- `trace_color`, `debug_color`, `info_color`, `success_color`, `warning_color`, `error_color`, `fail_color`, `critical_color`: Custom ANSI color codes.
- `use_rgb`: Use RGB color mode.
- `support_background`: Background color support.
- `reset_code`: Reset code at end of each log.

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

Enable callback invocation for log events. Default: `true`.

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

#### `thread_pool: ThreadPoolConfig`

Thread pool configuration.
- `enabled`: Enable thread pool.
- `thread_count`: Number of worker threads.
- `queue_size`: Maximum queue size.
- `stack_size`: Stack size per thread.
- `work_stealing`: Enable work stealing.
- `enable_arena`: Enable per-worker arena allocator.
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
- `algorithm`: Compression algorithm (`.none`, `.deflate`, `.zlib`, `.raw_deflate`).
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

### `withThreadPool(config: ThreadPoolConfig) Config`

Enables thread pool with the provided configuration.

### `withScheduler(config: SchedulerConfig) Config`

Enables scheduler with the provided configuration.

### `withArenaAllocation() Config`

Enables arena allocator for internal temporary allocations to improve performance.

### `merge(other: Config) Config`

Merges another configuration into the current one. Non-default values from `other` override the current values.



#### `enable_callbacks: bool`

Enable log callbacks. Default: `true`.

#### `enable_exception_handling: bool`

Enable exception handling within the logger. Default: `true`.

### Sampling Configuration

#### `sampling: SamplingConfig`

Sampling configuration for high-throughput scenarios.

```zig
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
    /// Enable per-worker arena allocator for efficient memory usage.
    enable_arena: bool = false,
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
    /// Compress on rotation.
    on_rotation: bool = true,
    /// Keep original file after compression.
    keep_original: bool = false,
    /// File extension for compressed files.
    extension: []const u8 = ".gz",

    pub const CompressionAlgorithm = enum {
        none,
        deflate,
        zlib,
        raw_deflate,
    };

    pub const CompressionLevel = enum(u4) {
        none = 0,
        fast = 1,
        default = 6,
        best = 9,
    };
};
```

### Async Logging Configuration

#### `async_config: AsyncConfig`

Centralized async logging configuration.

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
