---
title: Log Sinks Guide
description: Configure log sinks in Logly.zig for console, file, network (TCP/UDP), and system event log output. Learn about rotation, compression, async writing, and multi-sink configurations.
head:
  - - meta
    - name: keywords
      content: log sinks, file logging, network logging, tcp logging, udp logging, console output, log rotation, multiple outputs
---

# Sinks

Sinks are destinations where log messages are written. Logly.zig supports multiple sinks, allowing you to send logs to the console, files, or custom destinations simultaneously.

## Console Sink

A console sink is automatically added when you initialize the logger, unless `autoSink` is disabled in the config.

```zig
// Add a console sink manually (both methods are equivalent)
 _ = try logger.addSink(.{});
 _ = try logger.add(.{});  // Short alias
```

> [!NOTE]
> When you manually add a console sink via `logger.add(.{})`, the `autoSink` flag is automatically disabled to prevent duplicate console output. The automatic console sink created during `Logger.init()` will not be added if you explicitly add one first.

## File Sink

File sinks write logs to a file. You can configure rotation, retention, and specific log levels for each sink.

```zig
 _ = try logger.add(.{
    .path = "logs/app.log",
});
```

## Dynamic File Paths

You can use placeholders in the file path to automatically include date and time information. This is useful for organizing logs by date or creating unique log files per session.

Supported placeholders:
- `{date}`: Current date (YYYY-MM-DD)
- `{time}`: Current time (HH-mm-ss)
- Custom formats: `{YYYY}`, `{MM}`, `{DD}`, `{HH}`, `{mm}`, `{ss}`

```zig
// Create a log file in a date-stamped directory
 _ = try logger.addSink(.{
    .path = "logs/{date}/app.log", // e.g., logs/2025-12-08/app.log
});

// Create a unique log file with full timestamp
 _ = try logger.addSink(.{
    .path = "logs/session-{YYYY}-{MM}-{DD}_{HH}-{mm}-{ss}.log",
});

// Use custom separators
 _ = try logger.addSink(.{
    .path = "logs/{YYYY}/{MM}/{DD}/app.log",
});
```

## Network Sinks

Logly supports sending logs over the network via TCP or UDP. This is useful for centralized logging, log aggregation services (like Logstash, Fluentd), or remote debugging.

### TCP Sink

TCP sinks provide reliable, connection-oriented logging. If the connection is lost, the sink will attempt to reconnect.

```zig
// TCP Sink with standard text format
 _ = try logger.addSink(.{
    .path = "tcp://localhost:8080",
});

// TCP Sink with JSON format (recommended for aggregators)
 _ = try logger.addSink(.{
    .path = "tcp://localhost:8080",
    .format = .json,
});
```

### UDP Sink

UDP sinks provide "fire-and-forget" logging. They are faster and have less overhead but do not guarantee delivery.

```zig
// UDP Sink
 _ = try logger.addSink(.{
    .path = "udp://localhost:9090",
    .format = .json,
});
```

### Network Compression

You can enable compression for network sinks to reduce bandwidth usage. This uses the DEFLATE algorithm to compress log batches before sending.

```zig
var sinkConfig = logly.SinkConfig.network("tcp://localhost:8080");
sinkConfig.compression = .{
    .enabled = true,
    .algorithm = .deflate,
    .level = .best_compression,
};
 _ = try logger.addSink(sinkConfig);
```

### Distributed Context

Network sinks are ideal for distributed environments. When used with `DistributedConfig`, logs sent over the network automatically include:
- `serviceName`
- `region`
- `environment`
- `traceId`
- `spanId`

This makes integration with aggregators (ELK, Splunk, Datadog) seamless as correlation IDs are already present in the JSON payload.

## System Event Log

You can enable logging to the system event log (Windows Event Log or Syslog).

On Windows, when `eventLog` is enabled the sink will send entries to the Windows Event Viewer using the native `ReportEvent` API. Log level → event type mapping:

- Error / Critical / Fail / Fatal → `eventlogErrorType` (`Constants.EventLogConstants.errorType`)
- Warning → `eventlogWarningType` (`Constants.EventLogConstants.warningType`)
- Notice / Info / Success → `eventlogInformationType` (`Constants.EventLogConstants.informationType`)

These values are centralized in `Constants.EventLogConstants` and are reused by the sink implementation for consistency.

Example (enable event log):
```zig
 _ = try logger.addSink(.{
    .eventLog = true,
    .level = .err, // Typically used for critical errors
});
```

On POSIX systems `eventLog` maps to Syslog using the standard facility and severity mappings. See the Constants API (`EventLogConstants`, `SyslogConstants`) for canonical values and mappings.

## Multiple Sinks

You can add as many sinks as you need.

```zig
// Console
 _ = try logger.add(.{});

// Application logs
 _ = try logger.add(.{
    .path = "logs/app.log",
    .rotation = "daily",
    .retention = 7,
});

// Error-only file
 _ = try logger.add(.{
    .path = "logs/errors.log",
    .level = .err, // Only ERROR and above
});
```

## Sink Management

```zig
// Add sinks
const sink_id = try logger.add(.{ .path = "app.log" });

// Get sink count
const count = logger.count();  // or logger.getSinkCount()

// Remove specific sink
logger.remove(sink_id);  // or logger.removeSink(sink_id)

// Remove all sinks
 _ = logger.clear();  // or logger.removeAll() or logger.removeAllSinks()
```

## Sink Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `path` | `?[]const u8` | `null` | Path to the log file (null for console) |
| `name` | `?[]const u8` | `null` | Sink identifier for metrics/debugging |
| `rotation` | `?[]const u8` | `null` | Rotation interval ("minutely", "hourly", "daily", "weekly", "monthly", "yearly") |
| `sizeLimit` | `?u64` | `null` | Max file size in bytes for rotation |
| `sizeLimitStr` | `?[]const u8` | `null` | Max file size as string (e.g. "10MB", "1GB") |
| `retention` | `?usize` | `null` | Number of rotated files to keep |
| `level` | `?Level` | `null` | Minimum log level for this sink (overrides global) |
| `maxLevel` | `?Level` | `null` | Maximum log level (creates level range filter) |
| `asyncWrite` | `bool` | `true` | Enable async writing (buffered) |
| `bufferSize` | `usize` | `8192` | Buffer size for async writing |
| `json` | `bool` | `false` | Force JSON output for this sink |
| `prettyJson` | `bool` | `false` | Pretty print JSON output |
| `color` | `?bool` | `null` | Enable/disable colors (null = auto-detect) |
| `enabled` | `bool` | `true` | Enable/disable sink initially |
| `includeTimestamp` | `bool` | `true` | Include timestamp in output |
| `includeLevel` | `bool` | `true` | Include log level in output |
| `includeSource` | `bool` | `false` | Include source location |
| `includeTraceId` | `bool` | `false` | Include trace IDs (distributed tracing) |
| `eventLog` | `bool` | `false` | Enable system event log (Windows Event Log/Syslog) |
| `compression` | `?CompressionConfig` | `null` | Network compression settings |
| `writeMode` | `WriteMode` | `.append` | File write mode: `.append`, `.overwrite`, `.appendRotate` |

## Color Control

### Per-Sink Color Control

Each sink can have its own color setting. Colors apply to the **entire log line** (timestamp, level, and message):

```zig
// Console with colors (entire line colored)
 _ = try logger.addSink(.{
    .color = true,
});

// File without colors (recommended for files)
 _ = try logger.addSink(.{
    .path = "logs/app.log",
    .color = false,
});
```

### Windows Color Support

On Windows, enable ANSI color support at application startup:

```zig
 _ = logly.Terminal.enableAnsiColors(); // No-op on Linux/macOS
```

### Auto-Detection

When `color` is `null` (default):
- Console sinks: Colors enabled if terminal supports ANSI
- File sinks: Colors disabled

### Global Color Control

```zig
var config = logly.Config.default();
config.globalColorDisplay = false; // Disable colors globally
logger.configure(config);
```

### Level Colors

| Level | Color | ANSI Code |
|-------|-------|-----------|
| TRACE | Cyan | 36 |
| DEBUG | Blue | 34 |
| INFO | White | 37 |
| SUCCESS | Green | 32 |
| WARNING | Yellow | 33 |
| ERROR | Red | 31 |
| FAIL | Magenta | 35 |
| CRITICAL | Bright Red | 91 |

## Runtime Control

You can enable or disable specific sinks at runtime using their ID (returned by `addSink`).

```zig
const sink_id = try logger.addSink(.{ .path = "logs/app.log" });

// Disable sink temporarily
logger.disableSink(sink_id);

// Enable it back
logger.enableSink(sink_id);
```

## Level Range Filtering

Create sinks that only accept a specific range of levels:

```zig
// Only INFO and SUCCESS (no warnings/errors)
 _ = try logger.addSink(.{
    .path = "logs/info.log",
    .level = .info,
    .maxLevel = .success,
});

// Only ERROR, FAIL, CRITICAL
 _ = try logger.addSink(.{
    .path = "logs/errors.log",
    .level = .err,
});
```

## JSON Output

Configure JSON output per sink:

```zig
// Pretty JSON for development
 _ = try logger.addSink(.{
    .path = "logs/dev.json",
    .format = .json,
    .prettyJson = true,
});

// Compact JSON for production
 _ = try logger.addSink(.{
    .path = "logs/prod.json",
    .format = .json,
    .includeTraceId = true,
});
```

## High-Throughput Configuration

For high-volume logging:

```zig
 _ = try logger.addSink(.{
    .path = "logs/high-volume.log",
    .asyncWrite = true,
    .bufferSize = 65536, // 64KB buffer
    .rotation = "hourly",
    .sizeLimitStr = "500MB",
    .retention = 24,
});

## Memory-Mapped (mmap) Sinks (v0.2.0)

To achieve extreme microsecond-level write performance, you can enable virtual memory mapping (`mmap`) on file sinks. This maps files directly to physical memory blocks, bypassing heavy filesystem context switches and kernel write system calls.

```zig
var mmap_sink = logly.SinkConfig.file("logs/perf.log");
mmap_sink.mmap = true; // [!code hl] // Enable zero-copy mmap writes!
 _ = try logger.addSink(mmap_sink);
```

## Cryptographic Tamper-Evident Chaining (v0.2.0)

For high-security audit log systems (PCI-DSS/GDPR compliance), you can protect files with native SHA-256 cryptographic chaining. Every log line is cryptographically signed with a SHA-256 hash containing its own message, timestamp, and the signature of the *preceding* line. Any unauthorized insertion, edit, or deletion breaks the signature chain instantly.

```zig
var secure_sink = logly.SinkConfig.file("logs/secure_audit.log");
secure_sink.tamperEvident = true; // [!code hl] // Enable cryptographic chain!
 _ = try logger.addSink(secure_sink);
```

## See Also
- [Sink API](/api/sink) - Sinks reference API
- [Memory Mapped Sink Example](/examples/mmap) - Zero-copy I/O example
- [Network Logging](/guide/network-logging) - Remote TCP/UDP sinks guide
```
