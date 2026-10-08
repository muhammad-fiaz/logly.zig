---
title: Configuration Guide
description: Complete guide to configuring Logly.zig. Learn about log levels, output formats, JSON logging, color settings, async configuration, thread pools, compression, and enterprise features like filtering, sampling, and redaction.
head:
  - - meta
    - name: keywords
      content: logly configuration, zig logger config, logging settings, json logging config, async logging config, log level configuration
---

# Configuration

Logly.zig offers a comprehensive and flexible configuration system, allowing you to tailor every aspect of the logging behavior to your application's needs.

## Basic Configuration

The `Config` struct is the primary interface for global settings. You can start with a default configuration and modify it as needed.

```zig
var config = logly.Config.default();

// Global controls
config.globalColorDisplay = true;
config.globalConsoleDisplay = true;
config.globalFileStorage = true;

// Log level
config.level = .debug;

// Display options
config.showTime = true;
config.showModule = true;
config.showFunction = false;
config.showFilename = true; // Useful for debugging
config.showLineno = true;   // Pinpoint the exact line
config.includeHostname = true; // Add hostname to logs
config.includePid = true;      // Add process ID

// Output format
config.prettyJson = false;
config.color = true;

// Features
config.enableCallbacks = false;  // Enable only when using callbacks
config.enableExceptionHandling = true;

logger.configure(config);
```

## Configuration Options

| Option                   | Type          | Default                 | Description                                          |
| :----------------------- | :------------ | :---------------------- | :--------------------------------------------------- |
| `level`                  | `Level`       | `.info`                 | Minimum log level to output.                         |
| `globalColorDisplay`   | `bool`        | `true`                  | Globally enable/disable colored output.              |
| `globalConsoleDisplay` | `bool`        | `true`                  | Globally enable/disable console output.              |
| `globalFileStorage`    | `bool`        | `true`                  | Globally enable/disable file output.                 |
| `json`                   | `bool`        | `false`                 | Format logs as JSON objects.                         |
| `prettyJson`            | `bool`        | `false`                 | Pretty-print JSON output (indented).                 |
| `color`                  | `bool`        | `true`                  | Enable ANSI color codes.                             |
| `showTime`              | `bool`        | `true`                  | Include timestamp in log output.                     |
| `showModule`            | `bool`        | `true`                  | Include the module name.                             |
| `showFunction`          | `bool`        | `false`                 | Include the function name.                           |
| `showFilename`          | `bool`        | `false`                 | Include the source filename.                         |
| `showLineno`            | `bool`        | `false`                 | Include the source line number.                      |
| `includeHostname`       | `bool`        | `false`                 | Include the system hostname.                         |
| `includePid`            | `bool`        | `false`                 | Include the process ID.                              |
| `captureStackTrace`    | `bool`        | `false`                 | Capture stack traces for Error/Critical logs.        |
| `symbolizeStackTrace`  | `bool`        | `false`                 | Resolve stack trace addresses to symbols.            |
| `autoSink`              | `bool`        | `true`                  | Automatically add a console sink on init             |
| `enableCallbacks`       | `bool`        | `false`                 | Enable log callbacks (only when using callbacks)     |
| `logFormat`             | `?[]const u8` | `null`                  | Custom log format string (e.g. `"{time} {message}"`) |
| `timeFormat`            | `[]const u8`  | `"YYYY-MM-DD HH:mm:ss.SSS"` | Timestamp format                                 |
| `timezone`               | `enum`        | `.local`                | Timezone for timestamps (`.local` or `.utc`)         |
| `autoFlush`             | `bool`        | `false`                 | Auto-flush sinks (set true only when immediate output is critical) |
| `logsRootPath`         | `?[]const u8` | `null`                  | Root directory for log files                        |
| `debugMode`             | `bool`        | `false`                 | Enable debug output for troubleshooting             |
| `errorHandling`         | `enum`        | `.logAndContinue`     | Error handling strategy (`.silent`, `.logAndContinue`, `.failFast`, `.callback`) |

## Module Configuration

The `Config` struct provides settings for various logging modules. Each module can be enabled and configured through its respective config section:

### Distributed Configuration (Microservices)

```zig
var config = logly.Config.default();
config.distributed = .{
    .enabled = true,
    .serviceName = "payment-service",  // Your service name
    .region = "us-east-1",              // Deployment region
    .environment = "production",        // Service environment (dev/prod/staging)
    .traceHeader = "X-Trace-ID",       // Header key for Trace ID
    .spanHeader = "X-Span-ID",         // Header key for Span ID
};
```

### Telemetry

OpenTelemetry-specific configuration is available via the `telemetry` field on `Config`. Use built-in presets (`TelemetryConfig.jaeger()`, `TelemetryConfig.zipkin()`, `TelemetryConfig.file(path)`, `TelemetryConfig.highThroughput()`, `TelemetryConfig.development()`, etc.) or customize the fields directly.

```zig
var config = logly.Config.default();

// Use a preset for Jaeger and tweak batching
config.telemetry = logly.TelemetryConfig.jaeger();
config.telemetry.spanProcessorType = .batch; // Auto-export when thresholds hit
config.telemetry.batchSize = 1024;
config.telemetry.batchTimeoutMs = 2000;

// Or use file-based development preset
config.telemetry = logly.TelemetryConfig.development();
```

Notes:
- `spanProcessorType` semantics:
  - `.simple`: Completed spans are kept pending until you explicitly call `telemetry.exportSpans()` or `telemetry.flush()`. Use this when you want to control export timing (e.g., at request boundaries).
  - `.batch` : Spans are buffered and automatically exported when `batchSize` or `batchTimeoutMs` thresholds are reached.
- `metricsFilePath` overrides `exporterFilePath` for JSON/Prometheus metric exports.
- Default telemetry values (batch size, timeouts, headers) are centralized in `Constants.TelemetryDefaults`.
- v0.1.8: Fixed an OTLP exporter compile-time issue (removed an unnecessary discard in `writeOtlpSpan`) so telemetry builds cleanly across targets.

### Thread Pool Configuration

```zig
var config = logly.Config.default();
config.threadPool = .{
    .enabled = true,              // Enable thread pool
    .threadCount = 4,            // Number of worker threads (0 = auto)
    .queueSize = 10000,          // Max queued tasks
    .stackSize = 1024 * 1024,    // Stack size per thread
    .workStealing = true,        // Enable work stealing
};
```

### Scheduler Configuration

```zig
var config = logly.Config.default();
config.scheduler = .{
    .enabled = true,              // Enable scheduler
    .cleanupMaxAgeDays = 7,    // Delete logs older than 7 days
    .maxFiles = 10,              // Keep max 10 rotated files
    .compressBeforeCleanup = true, // Compress before deleting
    .filePattern = "*.log",      // Pattern for log files
};
```

### Compression Configuration

```zig
var config = logly.Config.default();
config.compression = .{
    .enabled = true,              // Enable compression
    .algorithm = .deflate,        // Compression algorithm
    .level = .default,            // Compression level
    .onRotation = true,          // Compress on rotation
    .keepOriginal = false,       // Delete original after compression
    .extension = ".gz",           // Compressed file extension
};
```

### Async Configuration

```zig
var config = logly.Config.default();
config.asyncConfig = .{
    .enabled = true,              // Enable async logging
    .bufferSize = 8192,          // Ring buffer size
    .batchSize = 100,            // Messages per batch
    .flushIntervalMs = 100,     // Auto-flush interval
    .minFlushIntervalMs = 10,  // Min interval between flushes
    .maxLatencyMs = 5000,       // Max latency before forced flush
    .overflowPolicy = .dropOldest, // On buffer overflow
    .backgroundWorker = true,    // Auto-start worker thread
};
```

### Helper Methods

Use helper methods for cleaner configuration:

```zig
// Enable async logging
var config = logly.Config.default().withAsync(.{
    .enabled = true,
    .bufferSize = 8192,
});

// Enable compression
var config2 = logly.Config.default().withCompression(logly.CompressionConfig.production());

// Chain multiple features
var config6 = logly.Config.default()
    .withAsync(.{ .enabled = true, .bufferSize = 8192 })
    .withCompression(logly.CompressionConfig.production())
    .withThreadPool(.{ .enabled = true, .threadCount = 0 }); // Auto-detect CPU cores
```

### Allocator Configuration

Pass your own allocator to `Logger.initWithConfig(allocator, config)` directly. Standard `std.heap.DebugAllocator` is recommended for general-purpose ownership and leak detection.

## Configuration Presets

Logly provides pre-configured presets for common scenarios:

```zig
// Production: JSON output, sampling, compression, scheduler enabled
const prodConfig = logly.ConfigPresets.production();

// Development: DEBUG level, colors, source location shown
const devConfig = logly.ConfigPresets.development();

// High Throughput: Async, thread pool, rate limiting enabled
const perf_config = logly.ConfigPresets.highThroughput();

// Secure: Redaction enabled, no hostname/PID in output
const secureConfig = logly.ConfigPresets.secure();

// Log-only mode (no console output)
const logOnly = logly.Config.logOnly();

// Display-only mode (console only, no files)
const displayOnly = logly.Config.displayOnly();

// Custom display/storage settings
const custom = logly.Config.withDisplayStorage(true, true, true);
```

### How `autoSink`, `globalConsoleDisplay` and `globalFileStorage` interact

`autoSink` adds a console sink at logger creation, but only when
`globalConsoleDisplay` is also on. The two flags are independent, so a
contradictory pairing is simply inert rather than an error:

| `globalConsoleDisplay` | `globalFileStorage` | `autoSink` | Result |
|:--|:--|:--|:--|
| true | true | true | Console sink added; file sinks allowed |
| true | false | true | Console sink added; file sinks rejected |
| false | true | true | **No** console sink (display is off); file sinks allowed |
| false | false | true | No console sink; file sinks rejected |

Adding a sink that contradicts the active flags returns an error instead of
silently creating an empty file or a dead console target:

```zig
const logger = try logly.Logger.initWithConfig(allocator, logly.Config.displayOnly());
try std.testing.expectError(
    error.FileStorageDisabled,
    logger.addSink(.{ .path = "app.log" }),
);

const file_logger = try logly.Logger.initWithConfig(allocator, logly.Config.logOnly());
try std.testing.expectError(
    error.ConsoleDisplayDisabled,
    file_logger.addSink(logly.SinkConfig.console()),
);
```

The null device is always permitted, even with file storage disabled, because
it discards output without creating a file. Matching is case-insensitive on
Windows, so `NUL`, `nul`, and `/dev/null` are all accepted.

### JSON file sinks are array documents

A JSON file sink writes one array rather than one object per line, so a file
holds a single valid document:

```json
[
  { "timestamp": ..., "level": "INFO", "message": "first" },
  { "timestamp": ..., "level": "INFO", "message": "second" }
]
```

The closing `]` is written when the sink closes, so the document is only
complete after `logger.deinit()`. Reading the file while the logger is still
open yields an unterminated array. Append mode rewinds over the existing tail
and continues the array; a file containing unrelated content is rejected with
`error.JsonArrayAppendUnsupported` rather than being silently corrupted.

### `autoFlush`

`autoFlush` flushes after every record. It is off by default because flushing
costs a syscall per log line:

```zig
var config = logly.Config.default();
config.autoFlush = true;   // immediate output, lower throughput
```

Prefer an explicit `logger.flush()`, a sink `bufferSize` threshold, or relying
on `deinit` for the common case.

### Using Presets

```zig
var logger = try logly.Logger.initWithConfig(allocator, logly.ConfigPresets.production());
```

## Advanced Configuration

### Custom Log Format

You can customize the log output format using the `logFormat` option. The following placeholders are supported:

- `{time}`: Timestamp (formatted according to `timeFormat`)
- `{level}`: Log level
- `{message}`: Log message
- `{module}`: Module name
- `{function}`: Function name
- `{file}`: Filename (clickable in supported terminals)
- `{line}`: Line number
- `{traceId}`: Distributed trace ID
- `{spanId}`: Span ID

```zig
config.logFormat = "{time} | {level} | {message}";
```

### Clickable Links

To enable clickable file links in your terminal (like VS Code), enable filename and line number display:

```zig
config.showFilename = true;
config.showLineno = true;
```

This will output the location in `path/to/file:line` format.

### Time Configuration

Logly supports multiple timestamp formats:

| Format | Example Output | Description |
|--------|----------------|-------------|
| `YYYY-MM-DD HH:mm:ss.SSS` | `2025-12-04 06:39:53.091` | Default human-readable |
| `ISO8601` | `2025-12-04T06:39:53.091Z` | ISO 8601 format |
| `RFC3339` | `2025-12-04T06:39:53+00:00` | RFC 3339 format |
| `YYYY-MM-DD` | `2025-12-04` | Date only |
| `HH:mm:ss` | `06:39:53` | Time only |
| `HH:mm:ss.SSS` | `06:39:53.091` | Time with milliseconds |
| `unix` | `1764830393` | Unix timestamp (seconds) |
| `unixMs` | `1764830393091` | Unix timestamp (milliseconds) |

```zig
// Use ISO8601 format
config.timeFormat = logly.Config.TimeFormat.iso8601;

// Use Unix timestamp
config.timeFormat = logly.Config.TimeFormat.unix;

// Use canonical default pattern
config.timeFormat = logly.Config.TimeFormat.defaultPattern;

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
var rateSampler = Sampler.init(allocator, .{ .rateLimit = .{
    .maxRecords = 100,
    .windowMs = 1000,
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
        metrics.totalRecords,
        metrics.errorCount,
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
config.globalColorDisplay = false;

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
    .format = .json,
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

### Level Colors Configuration
 
You can customize the colors for standard levels using the `levelColors` configuration:
 
```zig
var config = logly.Config.default();
 
// Use a built-in theme
config.levelColors.themePreset = .neon; // .bright, .dim, .neon, .pastel, .dark, etc.
 
// Override specific level colors (ANSI codes)
config.levelColors.infoColor = logly.Color.parse("36").?;    // Cyan
config.levelColors.warningColor = logly.Color.parse("33").?; // Yellow
config.levelColors.errorColor = logly.Color.parse("31").?;   // Red
 
logger.configure(config);
```
 
Available theme presets:
- `.default`: Standard ANSI colors
- `.bright`: Bold/bright variants
- `.dim`: Dim variants
- `.minimal`: Gray-scale theme
- `.neon`: Vivid 256-color palette
- `.pastel`: Soft pastel colors
- `.dark`: Optimized for dark terminals
- `.light`: Optimized for light terminals
- `.none`: No colors
 
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
config.globalColorDisplay = false;  // Master switch
config.color = false;                  // Disable ANSI codes
logger.configure(config);
```

## Performance Configuration

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
config.format = .json;
logger.configure(config);

try logger.info("Application started");
// Output: {"timestamp":"...","level":"INFO","message":"Application started"}
```

### Pretty JSON

Enable indented, human-readable JSON:

```zig
var config = logly.Config.default();
config.format = .json;
config.prettyJson = true;
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

## Invoke System Configuration

The Invoke System attaches extra messages to log records when conditions match.

```zig
var config = logly.Config.default();
config.rules.enabled = true;
```

## Advanced Features

For more advanced customizations like custom themes, scoped context, and advanced redaction, check out the [Advanced Features Example](../../examples/advanced_features.zig) and the [Context Guide](./context.md).

> [!TIP]
> Logly uses `std.math.clamp` internally to clamp compression levels to valid ranges when converting between enum levels and numeric values (e.g., zstd levels 1-22). You don't need to clamp values yourself — invalid levels are automatically clamped to the nearest valid bound.

## See Also

- [Sinks](./sinks.md) - Configure output destinations (Console, File, Network)
- [Network Logging](../examples/network-logging.md) - Detailed guide on TCP/UDP logging
- [Compression](./compression.md) - Configure log compression

