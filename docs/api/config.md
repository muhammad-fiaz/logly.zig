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
- `{trace_id}` - Trace ID
- `{span_id}` - Span ID
- `{caller}` - Caller info
- `{thread}` - Thread ID

Default: `null` (uses default format).

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

Default: `"YYYY-MM-DD HH:mm:ss"`.

#### `timezone: Timezone`

Timezone for timestamps. Options: `.local`, `.utc`. Default: `.local`.

### Sink Settings

#### `auto_sink: bool`

Automatically add a console sink on init. Default: `true`.

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
    /// What to do when buffer is full.
    overflow_policy: OverflowPolicy = .drop_oldest,
    /// Auto-start worker thread.
    auto_start: bool = true,

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

### `withAsync() Config`

Returns a configuration with async logging enabled.

```zig
const config = logly.Config.default().withAsync();
```

### `withCompression() Config`

Returns a configuration with compression enabled.

```zig
const config = logly.Config.default().withCompression();
```

### `withThreadPool(thread_count) Config`

Returns a configuration with thread pool enabled.

```zig
const config = logly.Config.default().withThreadPool(4);
```

### `withScheduler() Config`

Returns a configuration with scheduler enabled.

```zig
const config = logly.Config.default().withScheduler();
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
