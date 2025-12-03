# Config API

The `Config` struct controls the behavior of the logger.

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
- `"YYYY-MM-DD HH:mm:ss"` - Default
- `"ISO8601"` - ISO 8601 format
- `"RFC3339"` - RFC 3339 format
- `"unix"` - Unix timestamp
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

### Enterprise Settings

#### `sampling: SamplingConfig`

Sampling configuration for high-throughput scenarios.

```zig
pub const SamplingConfig = struct {
    enabled: bool = false,
    strategy: SamplingStrategy = .probability,
    sample_rate: f32 = 1.0,
    debug_rate: f32 = 1.0,
    info_rate: f32 = 1.0,
    warning_rate: f32 = 1.0,
    error_rate: f32 = 1.0,
};
```

#### `rate_limit: RateLimitConfig`

Rate limiting configuration to prevent log flooding.

```zig
pub const RateLimitConfig = struct {
    enabled: bool = false,
    max_per_second: u32 = 1000,
    burst_size: u32 = 100,
};
```

#### `redaction: RedactionConfig`

Sensitive data redaction configuration.

```zig
pub const RedactionConfig = struct {
    enabled: bool = false,
    patterns: ?[]const RedactionPattern = null,
};
```

#### `buffer: BufferConfig`

Buffer configuration for async writing.

```zig
pub const BufferConfig = struct {
    size: usize = 8192,
    flush_interval_ms: u64 = 1000,
    max_records: usize = 1000,
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

```zig
const config = logly.Config.production();
```

### `development() Config`

Returns a development-friendly configuration:
- Level: `.debug`
- Colors enabled
- Source location shown
- No sampling

```zig
const config = logly.Config.development();
```

### `highThroughput() Config`

Returns a high-throughput optimized configuration:
- Large buffers
- Aggressive sampling
- Rate limiting enabled

```zig
const config = logly.Config.highThroughput();
```

### `secure() Config`

Returns a security-focused configuration:
- PII redaction enabled
- Strict error handling
- Audit logging

```zig
const config = logly.Config.secure();
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

## Example Usage

```zig
const logly = @import("logly");

const logger = try logly.Logger.init(allocator);
defer logger.deinit();

// Configure with custom settings
var config = logly.Config.default();
config.level = .debug;
config.json = true;
config.show_filename = true;
config.time_format = "ISO8601";

// Apply configuration
logger.configure(config);
```
