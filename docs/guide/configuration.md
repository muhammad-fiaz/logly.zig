# Configuration

Logly-Zig offers a comprehensive and flexible configuration system, allowing you to tailor every aspect of the logging behavior to your application's needs.

## Basic Configuration

The `Config` struct is the primary interface for global settings. You can start with a default configuration and modify it as needed.

```zig
var config = logly.Config.default();

// 🎚️ Global controls
config.global_color_display = true;
config.global_console_display = true;
config.global_file_storage = true;

// 🔍 Log level
config.level = .debug;

// 👁️ Display options
config.show_time = true;
config.show_module = true;
config.show_function = false;
config.show_filename = true; // Useful for debugging
config.show_lineno = true;   // Pinpoint the exact line
config.include_hostname = true; // Add hostname to logs
config.include_pid = true;      // Add process ID

// 📝 Output format
config.json = false;
config.pretty_json = false;
config.color = true;

// ⚡ Features
config.enable_callbacks = true;
config.enable_exception_handling = true;

logger.configure(config);
```

## Configuration Options

| Option                   | Type          | Default                 | Description                                          |
| :----------------------- | :------------ | :---------------------- | :--------------------------------------------------- |
| `level`                  | `Level`       | `.info`                 | Minimum log level to output.                         |
| `global_color_display`   | `bool`        | `true`                  | Globally enable/disable colored output.              |
| `global_console_display` | `bool`        | `true`                  | Globally enable/disable console output.              |
| `global_file_storage`    | `bool`        | `true`                  | Globally enable/disable file output.                 |
| `json`                   | `bool`        | `false`                 | Format logs as JSON objects.                         |
| `pretty_json`            | `bool`        | `false`                 | Pretty-print JSON output (indented).                 |
| `color`                  | `bool`        | `true`                  | Enable ANSI color codes.                             |
| `show_time`              | `bool`        | `true`                  | Include timestamp in log output.                     |
| `show_module`            | `bool`        | `true`                  | Include the module name.                             |
| `show_function`          | `bool`        | `false`                 | Include the function name.                           |
| `show_filename`          | `bool`        | `false`                 | Include the source filename.                         |
| `show_lineno`            | `bool`        | `false`                 | Include the source line number.                      |
| `include_hostname`       | `bool`        | `false`                 | Include the system hostname.                         |
| `include_pid`            | `bool`        | `false`                 | Include the process ID.                              |
| `capture_stack_trace`    | `bool`        | `false`                 | Capture stack traces for Error/Critical logs.        |
| `symbolize_stack_trace`  | `bool`        | `false`                 | Resolve stack trace addresses to symbols.            |
| `show_lineno`            | `bool`        | `false`                 | Show line number                                     |
| `auto_sink`              | `bool`        | `true`                  | Automatically add a console sink on init             |
| `check_for_updates`      | `bool`        | `true`                  | Check for updates on startup                         |
| `enable_callbacks`       | `bool`        | `true`                  | Enable log callbacks                                 |
| `log_format`             | `?[]const u8` | `null`                  | Custom log format string (e.g. `"{time} {message}"`) |
| `time_format`            | `[]const u8`  | `"YYYY-MM-DD HH:mm:ss"` | Timestamp format                                     |
| `timezone`               | `enum`        | `.local`                | Timezone for timestamps (`.local` or `.utc`)         |

## Module Configuration

The `Config` struct provides settings for various logging modules. Each module can be enabled and configured through its respective config section:

### Thread Pool Configuration

```zig
var config = logly.Config.default();
config.thread_pool = .{
    .enabled = true,              // Enable thread pool
    .thread_count = 4,            // Number of worker threads (0 = auto)
    .queue_size = 10000,          // Max queued tasks
    .stack_size = 1024 * 1024,    // Stack size per thread
    .work_stealing = true,        // Enable work stealing
};
```

### Scheduler Configuration

```zig
var config = logly.Config.default();
config.scheduler = .{
    .enabled = true,              // Enable scheduler
    .cleanup_max_age_days = 7,    // Delete logs older than 7 days
    .max_files = 10,              // Keep max 10 rotated files
    .compress_before_cleanup = true, // Compress before deleting
    .file_pattern = "*.log",      // Pattern for log files
};
```

### Compression Configuration

```zig
var config = logly.Config.default();
config.compression = .{
    .enabled = true,              // Enable compression
    .algorithm = .deflate,        // Compression algorithm
    .level = .default,            // Compression level
    .on_rotation = true,          // Compress on rotation
    .keep_original = false,       // Delete original after compression
    .extension = ".gz",           // Compressed file extension
};
```

### Async Configuration

```zig
var config = logly.Config.default();
config.async_config = .{
    .enabled = true,              // Enable async logging
    .buffer_size = 8192,          // Ring buffer size
    .batch_size = 100,            // Messages per batch
    .flush_interval_ms = 100,     // Auto-flush interval
    .min_flush_interval_ms = 10,  // Min interval between flushes
    .max_latency_ms = 5000,       // Max latency before forced flush
    .overflow_policy = .drop_oldest, // On buffer overflow
    .background_worker = true,    // Auto-start worker thread
};
```

### Helper Methods

Use helper methods for cleaner configuration:

```zig
var config = logly.Config.default()
```zig
// Enable async logging
var config = logly.Config.default().withAsync();

// Enable compression
var config2 = logly.Config.default().withCompression();

// Enable thread pool with specific thread count
var config3 = logly.Config.default().withThreadPool(4);

// Enable scheduler
var config4 = logly.Config.default().withScheduler();
```

## Configuration Presets

Logly provides pre-configured presets for common scenarios:

```zig
// Production: JSON output, sampling, compression, scheduler enabled
const prod_config = logly.Config.production();

// Development: DEBUG level, colors, source location shown
const dev_config = logly.Config.development();

// High Throughput: Async, thread pool, rate limiting enabled
const perf_config = logly.Config.highThroughput();

// Secure: Redaction enabled, no hostname/PID in output
const secure_config = logly.Config.secure();
```

### Using Presets

```zig
var logger = try logly.Logger.initWithConfig(allocator, logly.Config.production());
```

## Advanced Configuration

### Custom Log Format

You can customize the log output format using the `log_format` option. The following placeholders are supported:

- `{time}`: Timestamp (formatted according to `time_format`)
- `{level}`: Log level
- `{message}`: Log message
- `{module}`: Module name
- `{function}`: Function name
- `{file}`: Filename (clickable in supported terminals)
- `{line}`: Line number
- `{trace_id}`: Distributed trace ID
- `{span_id}`: Span ID

```zig
config.log_format = "{time} | {level} | {message}";
```

### Clickable Links

To enable clickable file links in your terminal (like VS Code), enable filename and line number display:

```zig
config.show_filename = true;
config.show_lineno = true;
```

This will output the location in `path/to/file:line` format.

### Time Configuration

Logly supports multiple timestamp formats:

| Format | Example Output | Description |
|--------|----------------|-------------|
| `YYYY-MM-DD HH:mm:ss` | `2025-12-04 06:39:53.091` | Default human-readable |
| `ISO8601` | `2025-12-04T06:39:53.091Z` | ISO 8601 format |
| `RFC3339` | `2025-12-04T06:39:53+00:00` | RFC 3339 format |
| `YYYY-MM-DD` | `2025-12-04` | Date only |
| `HH:mm:ss` | `06:39:53` | Time only |
| `HH:mm:ss.SSS` | `06:39:53.091` | Time with milliseconds |
| `unix` | `1764830393` | Unix timestamp (seconds) |
| `unix_ms` | `1764830393091` | Unix timestamp (milliseconds) |

```zig
// Use ISO8601 format
config.time_format = "ISO8601";

// Use Unix timestamp
config.time_format = "unix";

// Configure timezone
config.timezone = .utc;   // Use UTC
config.timezone = .local; // Use local time (default)
```

## Enterprise Configuration

### Filtering

Configure rule-based log filtering:

```zig
const Filter = logly.Filter;

var filter = Filter.init(allocator);
defer filter.deinit();

// Only allow warning and above
try filter.addMinLevel(.warning);

// Filter by module prefix
try filter.addModulePrefix("database");

// Filter by message content
try filter.addMessageFilter("heartbeat", .deny);

logger.setFilter(&filter);
```

### Sampling

Configure log sampling for high-volume scenarios:

```zig
const Sampler = logly.Sampler;
const SamplerPresets = logly.SamplerPresets;

// Use preset: 10% sampling
var sampler = SamplerPresets.sample10Percent(allocator);
defer sampler.deinit();
logger.setSampler(&sampler);

// Or custom: rate limit to 100 per second
var rate_sampler = Sampler.init(allocator, .{ .rate_limit = .{
    .max_records = 100,
    .window_ms = 1000,
}});
```

### Redaction

Configure sensitive data masking:

```zig
const Redactor = logly.Redactor;

var redactor = Redactor.init(allocator);
defer redactor.deinit();

// Mask passwords by keyword
try redactor.addPattern("password", .keyword, "password", "[REDACTED]");

// Mask credit card patterns
try redactor.addPattern("card", .contains, "card=", "[CARD-REDACTED]");

logger.setRedactor(&redactor);
```

### Metrics

Enable logging metrics collection:

```zig
logger.enableMetrics();

// ... later ...
if (logger.getMetrics()) |metrics| {
    std.debug.print("Total: {}, Errors: {}\n", .{
        metrics.total_records,
        metrics.error_count,
    });
}
```

### Distributed Tracing

Configure distributed tracing context:

```zig
// Set trace context from incoming request
try logger.setTraceContext("trace-abc-123", "span-parent-456");

// Or set correlation ID
try logger.setCorrelationId("request-789");

// Create spans for operations
const span = try logger.startSpan("database_query");
defer span.end(null) catch {};

try logger.info("Executing query");
```

## Color Configuration

### Global Color Control

Control colors globally across all sinks:

```zig
var config = logly.Config.default();

// Disable all colors globally
config.global_color_display = false;

// Or enable colors per output type
config.color = true;  // Enable ANSI color codes

logger.configure(config);
```

### Per-Sink Color Control

Each sink can have independent color settings:

```zig
// Console with colors enabled
_ = try logger.addSink(.{
    .color = true,  // Explicit colors on
});

// File sink with colors disabled (recommended for files)
_ = try logger.addSink(.{
    .path = "logs/app.log",
    .color = false,  // No ANSI codes in files
});

// JSON file (colors don't apply to JSON structure)
_ = try logger.addSink(.{
    .path = "logs/app.json",
    .json = true,
    .color = false,
});
```

### Windows Color Support

Enable ANSI colors on Windows at application startup:

```zig
pub fn main() !void {
    // Enable Virtual Terminal Processing on Windows
    // This is a no-op on Linux/macOS
    _ = logly.Terminal.enableAnsiColors();
    
    // ... rest of initialization
}
```

### Built-in Level Colors

| Level | Color | ANSI Code | Description |
|-------|-------|-----------|-------------|
| TRACE | Cyan | 36 | Detailed tracing |
| DEBUG | Blue | 34 | Debug information |
| INFO | White | 37 | General info |
| SUCCESS | Green | 32 | Success messages |
| WARNING | Yellow | 33 | Warnings |
| ERROR | Red | 31 | Errors |
| FAIL | Magenta | 35 | Failures |
| CRITICAL | Bright Red | 91 | Critical errors |

### Custom Level Colors

Define custom levels with your own colors:

```zig
// Basic custom colors
try logger.addCustomLevel("audit", 35, "35");       // Magenta
try logger.addCustomLevel("security", 55, "91");   // Bright Red

// With modifiers (bold, underline, reverse)
try logger.addCustomLevel("notice", 22, "36;1");   // Bold Cyan
try logger.addCustomLevel("alert", 48, "31;4");    // Underline Red
try logger.addCustomLevel("highlight", 38, "33;7"); // Reverse Yellow

// Use custom levels
try logger.custom("audit", "User login detected");
try logger.customf("security", "Access from IP: {s}", .{"10.0.0.1"});
```

### Color Modifiers

Combine base colors with modifiers:

| Modifier | Code | Example | Result |
|----------|------|---------|--------|
| Bold | `1` | `31;1` | Bold Red |
| Underline | `4` | `34;4` | Underline Blue |
| Reverse | `7` | `32;7` | Reverse Green |
| Bright | `9x` | `91` | Bright Red |

### Disabling Colors Completely

To completely disable colors (useful for CI/CD or log files):

```zig
var config = logly.Config.default();
config.global_color_display = false;  // Master switch
config.color = false;                  // Disable ANSI codes
logger.configure(config);
```

## Performance Configuration

### Arena Allocator

For high-throughput logging scenarios, enable the arena allocator to reduce allocation overhead:

```zig
var config = logly.Config.default();

// Enable arena allocator for temporary allocations
config.use_arena_allocator = true;

// Optionally set the reset threshold (default: 64KB)
config.arena_reset_threshold = 128 * 1024;  // 128KB

const logger = try logly.Logger.initWithConfig(allocator, config);
defer logger.deinit();
```

Or use the convenience method:

```zig
const config = logly.Config.default().withArenaAllocation();
const logger = try logly.Logger.initWithConfig(allocator, config);
```

**Benefits:**
- Reduces allocation overhead for formatting operations
- Better cache locality for temporary buffers
- Faster logging in high-frequency scenarios

**Manual Arena Reset:**

For long-running applications, you can manually reset the arena to prevent memory growth:

```zig
// Reset periodically in high-throughput scenarios
logger.resetArena();
```

### Cross-Platform Colors

Logly automatically handles ANSI color support across platforms:

```zig
// Enable colors (call at startup)
_ = logly.Terminal.enableAnsiColors();

// Check if colors are supported
if (logly.Terminal.supportsAnsiColors()) {
    // Terminal supports colors
}

// Explicitly enable/disable colors (useful for bare metal)
logly.Terminal.setColorEnabled(true);  // or false

// Check effective color status
if (logly.Terminal.isColorEnabled()) {
    // Colors are available
}
```

**Platform Support:**
- **Windows**: Automatically enables Virtual Terminal Processing
- **Linux/macOS**: ANSI colors natively supported
- **Bare Metal/Freestanding**: Controllable via `setColorEnabled()`

## JSON Configuration

### Basic JSON Logging

```zig
var config = logly.Config.default();
config.json = true;
logger.configure(config);

try logger.info("Application started");
// Output: {"timestamp":"...","level":"INFO","message":"Application started"}
```

### Pretty JSON

Enable indented, human-readable JSON:

```zig
var config = logly.Config.default();
config.json = true;
config.pretty_json = true;
logger.configure(config);
```

Output:
```json
{
  "timestamp": "2024-01-15 10:30:45.000",
  "level": "INFO",
  "message": "Application started"
}
```

### JSON with Custom Levels

Custom level names appear in JSON output:

```zig
try logger.addCustomLevel("audit", 35, "35");
try logger.custom("audit", "Security event");
// Output: {"timestamp":"...","level":"AUDIT","message":"Security event"}
```

## Advanced Features

For more advanced customizations like custom themes, scoped context, and advanced redaction, check out the [Advanced Features Example](../../examples/advanced_features.zig) and the [Context Guide](./context.md).

## See Also

- [Sinks](./sinks.md) - Configure output destinations (Console, File, Network)
- [Network Logging](../examples/network-logging.md) - Detailed guide on TCP/UDP logging
- [Compression](./compression.md) - Configure log compression

