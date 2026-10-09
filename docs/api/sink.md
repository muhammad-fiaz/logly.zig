---
title: Sink API Reference
description: API reference for Logly.zig Sink struct. Configure log destinations including console, file, network (TCP/UDP), rotation, compression, and custom outputs.
head:
  - - meta
    - name: keywords
      content: sink api, log destination, file sink, console sink, network sink, output configuration
  - - meta
    - property: og:title
      content: Sink API Reference | Logly.zig
---

# Sink API

The `Sink` struct represents a destination for log messages. Sinks can write to console, files, or custom outputs with individual configuration options.

## Quick Reference: Method Aliases

| Full Method | Alias(es) | Description |
|-------------|-----------|-------------|
| `init()` | `create()` | Initialize sink |
| `deinit()` | `destroy()`, `close()` | Deinitialize sink |
| `writeWithAllocator()` | `writeWithAlloc()` | Write with custom allocator |
| `setWriteCallback()` | `onWrite()` | Set write callback |
| `setFlushCallback()` | `onFlush()` | Set flush callback |
| `setErrorCallback()` | `onError()` | Set error callback |
| `setRotationCallback()` | `onRotation()` | Set rotation callback |
| `setStateChangeCallback()` | `onStateChange()` | Set state change callback |
| `getStats()` | `statistics()`, `stats_()` | Get sink statistics |
| `clearBuffer()` | `clear()` | Clear write buffer |
| `flush()` | `sync()` | Flush buffered data |
| `isEnabled()` | `is_enabled()` | Check if sink is enabled |
| `isAsyncEnabled()` | `asyncEnabled()` | Check if async writing is enabled |
| `flushNow()` | `flushImmediate()` | Force immediate flush |
| `getName()` | `name()` | Get sink name |

## SinkConfig

Configuration for a sink.

### Core Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `path` | `?[]const u8` | `null` | Path to log file (null for console). Supports dynamic placeholders like `{date}`, `{time}`. Also supports network schemes `tcp://host:port` and `udp://host:port`. |
| `name` | `?[]const u8` | `null` | Sink identifier for metrics and debugging |
| `enabled` | `bool` | `true` | Enable/disable sink initially |
| `eventLog` | `bool` | `false` | Enable system event log output (Windows Event Log on Windows, Syslog on POSIX). See the Windows Event Log mapping below; constants are provided by `Constants.EventLogConstants`. |
| `tamperEvident` | `bool` | `false` | Enable cryptographic SHA-256 chaining to produce tamper-evident log records. |
| `mmap` | `bool` | `false` | Enable virtual memory-mapped zero-copy file logging for microsecond-latency writes. |
| `io` | `?std.Io` | `null` | Explicit I/O handle for this sink. If `null`, inherits the logger's configured I/O handle or falls back to `logly.defaultIo()`. |

### Windows Event Log (Windows only)

When `eventLog` is enabled on Windows, log entries are sent to the Windows Event Viewer using the `ReportEventA` API. Logly maps internal log `Level` values to Windows event types as follows:

- Error / Critical / Fail / Fatal -> `eventlogErrorType` (`Constants.EventLogConstants.errorType`)
- Warning -> `eventlogWarningType` (`Constants.EventLogConstants.warningType`)
- Notice / Info / Success -> `eventlogInformationType` (`Constants.EventLogConstants.informationType`)

`eventlogSuccess` (`Constants.EventLogConstants.success`) may be used for success/audit events.

These values are centralized in `src/constants.zig` under `EventLogConstants` and are reused by the sink implementation to ensure consistency across platforms.

### Dynamic Path Formatting

The `path` field supports dynamic placeholders that are resolved when the sink is initialized:
- `{date}`: YYYY-MM-DD
- `{time}`: HH-mm-ss
- `{YYYY}`, `{MM}`, `{DD}`, `{HH}`, `{mm}`, `{ss}`: Custom date/time components.

### Level Filtering

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `level` | `?Level` | `null` | Minimum log level for this sink |
| `maxLevel` | `?Level` | `null` | Maximum log level (creates level range) |

### Output Formatting

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `format` | `?Config.Format` | `null` | Output format for this sink (`null` inherits the logger-wide `Config.format`). One sink renders exactly one format: `.text`, `.json`, `.ndjson`, `.logfmt`, `.syslog`, `.syslog3164`, `.msgpack`. |
| `prettyJson` | `bool` | `false` | Pretty print JSON with indentation |
| `color` | `?bool` | `null` | Enable/disable colors (null = auto-detect) |
| `logFormat` | `?[]const u8` | `null` | Custom log format string |
| `timeFormat` | `?[]const u8` | `null` | Custom time format for this sink |
| `theme` | `?Formatter.Theme` | `null` | Custom color theme for this sink |

Event-log sinks (`eventLog = true`) only carry text-compatible formats.
Selecting `.msgpack`, `.syslog`, or `.syslog3164` on an event-log sink
fails at creation with `error.UnsupportedFormatForSink` (binary cannot
survive NUL-terminated transports; syslog framing would be doubled by the
daemon), as does inheriting one of those logger-wide formats via
`Logger.addSink`.

JSON-array (`.json`) file sinks keep every file a valid standalone
document: the opening bracket is written at creation, an existing file
continues its array when it ends with the array tail (anything else is
rejected with `error.JsonArrayAppendUnsupported` instead of being
corrupted), rotation closes the archived document and opens a fresh one
(memory-mapped files are remapped onto the fresh handle), and shutdown
closes the active document. Use `.ndjson` for append workflows that must
never look back.

### Field Inclusion

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `includeTimestamp` | `bool` | `true` | Include timestamp in output |
| `includeLevel` | `bool` | `true` | Include log level in output |
| `includeSource` | `bool` | `false` | Include source location |
| `includeTraceId` | `bool` | `false` | Include trace IDs (distributed tracing) |

### File Write Mode

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `overwriteMode` | `bool` | `false` | Legacy field: `false` = append (default), `true` = truncate file on startup. Prefer `writeMode`. |
| `writeMode` | `WriteMode` | `.append` | File write mode. See `WriteMode` enum below. |
| `fileMode` | `?u32` | `null` | File permissions for created log files (Unix only). |

#### WriteMode Enum

| Variant | Behavior |
|---------|----------|
| `.append` | Append to existing file (default). File grows over time. |
| `.overwrite` | Truncate file on startup. Only current session logs are kept. |
| `.appendRotate` | Append to file with explicit rotation trigger. Use with rotation config. |

```zig
// Append mode (default)
var sink = logly.SinkConfig.file("app.log");
sink.writeMode = .append;

// Overwrite mode (fresh start each run)
var sink = logly.SinkConfig.file("session.log");
sink.writeMode = .overwrite;

// Append with rotation
var sink = logly.SinkConfig.file("app.log");
sink.writeMode = .appendRotate;
sink.rotation = "daily";
sink.retention = 7;
```

When using `overwriteMode = true`, it is equivalent to `writeMode = .overwrite`.

### File Rotation

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `rotation` | `?[]const u8` | `null` | Rotation interval: "minutely", "hourly", "daily", "weekly", "monthly", "yearly" |
| `sizeLimit` | `?u64` | `null` | Max file size in bytes |
| `sizeLimitStr` | `?[]const u8` | `null` | Max file size as string (e.g., "10MB", "1GB") |
| `retention` | `?usize` | `null` | Number of rotated files to keep |

### Async Writing & Buffering

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `asyncWrite` | `bool` | `true` | Enable async writing with buffering |
| `bufferSize` | `usize` | `8192` | Buffer size for async writing in bytes |
| `maxBufferRecords` | `usize` | `1000` | Maximum records to buffer before forcing a flush |
| `flushIntervalMs` | `u64` | `1000` | Flush interval in milliseconds |
| `buffered_write_mode` | `bool` | `false` | Accumulate records in buffer until `flush()` is explicitly called by the user |

### Rate Limiting

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `rateLimitPerSecond` | `?u32` | `null` | Maximum messages allowed per second. Extra messages are dropped. |

### Error Handling

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `onError` | `ErrorBehavior` | `.logStderr` | Error handling behavior: `.silent`, `.logStderr`, `.disableSink`, `.propagate` |

#### ErrorBehavior semantics

- Applied across direct writes and buffered flush paths (`writeRaw`, `flush`, `flushNow`).
- `.silent`: increments write error stats and suppresses output.
- `.logStderr`: increments write error stats and emits a compact sink error line to stderr.
- `.disableSink`: disables the sink after an error and triggers `onStateChange(false)` callback when configured.
- `.propagate`: returns the original write/flush error to the caller.

For TCP sinks, reconnect attempts use centralized retry defaults:

- `Constants.TimeDefaults.maxRetries`
- `Constants.TimeDefaults.retryDelayMs`

### Advanced Options

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `compression` | `CompressionConfig` | `{}` | Compression settings for file and network sinks |
| `filter` | `FilterConfig` | `{}` | Per-sink filter configuration |

## Cryptographic Log Chaining

To enforce strict, tamper-evident log integrity, Logly offers built-in SHA-256 cryptographic chaining. 

### How It Works
1. When a log record is written to a tamper-evident sink, Logly calculates a SHA-256 hash.
2. The hash input is a combination of the current log record bytes and the hash of the *previous* log record written to that sink.
3. The resulting hash signature is appended to the written log line in a standard `"SIG:<hash>"` format.
4. If an attacker modifies or deletes any log line, the cryptographic chain is broken. Subsequent signatures will no longer match the calculated hashes, making tampering immediately detectable during log auditing.

### Usage Example
```zig
var config = logly.Config.default();
config.autoSink = false;

var sinkCfg = logly.SinkConfig.file("secure_audit.log");
sinkCfg.tamperEvident = true; // Enable tamper-evident chaining

const logger = try logly.Logger.initWithConfig(allocator, config);
defer logger.deinit();

 _ = try logger.addSink(sinkCfg);

try logger.info("Critical user balance update", @src());
try logger.flush();
```

---

## Memory-Mapped Sinks (Mmap)

For ultra-high-performance logging workloads, Logly provides portable memory-mapped file writing via POSIX `mmap` (on Linux and macOS) and Win32 Virtual Memory mapping APIs (on Windows).

### How It Works
- By mapping the log file directly into the process's virtual memory address space, Logly performs zero-copy logging directly to RAM, completely bypassing standard operating system write calls (`write` / `WriteFile`).
- The OS kernel handles flushing memory pages to disk asynchronously in the background.
- Logly manages mapping boundaries, handles dynamic pre-allocation growth when the file capacity is exceeded, and gracefully truncates the log file to its exact written offset during sink deinitialization.

### Usage Example
```zig
var config = logly.Config.default();
config.autoSink = false;

var mmap_sink = logly.SinkConfig.file("high_throughput.log");
mmap_sink.mmap = true;         // Enable memory-mapped file sink
mmap_sink.asyncWrite = false; // direct zero-copy write

const logger = try logly.Logger.initWithConfig(allocator, config);
defer logger.deinit();

 _ = try logger.addSink(mmap_sink);

try logger.info("Microsecond-latency zero-copy write", @src());
try logger.flush();
```

## Write Mode Examples

### Append Mode (Default)

Keep a permanent log file that grows over time:

```zig
 _ = try logger.addSink(.{
    .path = "logs/app.log",
    .overwriteMode = false,  // Default: append to existing file
});
```

Every time you run the application, new logs are appended to the file.

### Overwrite Mode

Start fresh each run with only current session logs:

```zig
 _ = try logger.addSink(.{
    .path = "logs/session.log",
    .overwriteMode = true,  // Overwrite file on initialization
});
```

When the sink is initialized, it truncates the file, creating a fresh log for the current session.

### Mixed Approach

Use different modes for different sinks:

```zig
// Persistent history - append mode
 _ = try logger.addSink(.{
    .path = "logs/history.log",
    .overwriteMode = false,  // Keep all logs forever
});

// Current session - overwrite mode
 _ = try logger.addSink(.{
    .path = "logs/session.log",
    .overwriteMode = true,   // Fresh start each time
});

// Error tracking - append mode for permanent record
 _ = try logger.addSink(.{
    .path = "logs/errors.log",
    .level = .err,
    .overwriteMode = false,  // Keep error history
});
```

## Methods

### `init(allocator: std.mem.Allocator, config: SinkConfig) !*Sink`

Initializes a new sink with the specified configuration.

**Alias:** `create`

### `initWithIo(allocator: std.mem.Allocator, io_handle: std.Io, config: SinkConfig) !*Sink`

Initializes a new sink with an explicit I/O handle and the specified configuration.

### `deinit() void`

Deinitializes the sink and frees resources.

**Alias:** `destroy`

### `write(record: *const Record, globalConfig: Config) !void`

Writes a log record to the sink. Uses the internal allocator for formatting.

### `writeWithAllocator(record: *const Record, globalConfig: Config, scratchAllocator: ?std.mem.Allocator) !void`

Writes a log record using an optional scratch allocator for formatting.

**Example:**
```zig
try sink.writeWithAllocator(record, config, logger.scratchAllocator());
```

### `writeRaw(data: []const u8) !void`

Writes preformatted data directly to the sink, bypassing record formatting.

- Appends a newline for file/console/network raw writes.
- Updates `SinkStats` and `onWrite` callback on success.
- Applies `onError` behavior consistently on failures.

### `flush() !void`

Flushes buffered sink data to its destination.

- Returns immediately when buffer is empty.
- Uses internal buffered record accounting so stats reflect batch flushes accurately.
- On success updates `SinkStats` (`totalWritten`, `bytesWritten`, `flushCount`).
- Invokes `onWrite(recordCount, bytes)` and `onFlush(bytes, durationNs)` callbacks.
- On failure increments `writeErrors` and applies configured `onError` behavior.

### `isAsyncEnabled() bool`

Returns `true` if async writing is enabled for this sink, `false` otherwise.

### `isHealthy() bool`

Returns `false` if the sink has encountered consecutive write errors exceeding its threshold or if the underlying connection/file handle is broken.

### `enableAsync() void`

Enables async writing for this sink, allowing buffered writes with periodic flushing.

### `disableAsync() void`

Disables async writing for this sink, forcing immediate synchronous writes and flushing any pending buffer.

### `flushNow() !void`

Manually flushes the sink buffer immediately, regardless of async settings.

Use this in batch checkpoints when async buffering is enabled but immediate durability is required.

## Examples

### Console Sink (Default)

```zig
// Using add() alias (same as addSink())
 _ = try logger.add(SinkConfig.default());
```

### File Sink with Rotation

```zig
 _ = try logger.add(.{
    .path = "logs/app.log",
    .rotation = "daily",
    .retention = 7,
    .sizeLimitStr = "100MB",
});
```

### JSON Sink for Structured Logging

```zig
 _ = try logger.add(.{
    .path = "logs/app.json",
    .format = .json,
    .prettyJson = true,
    .includeTraceId = true,
});
```

### Error-Only File Sink

```zig
 _ = try logger.add(.{
    .path = "logs/errors.log",
    .level = .err,           // Minimum: error
    .maxLevel = .critical,  // Maximum: critical
    .color = false,
});
```

### Console with Color Control

```zig
// Disable colors for console output
 _ = try logger.add(.{
    .color = false,  // Override auto-detection
});

// Or use global setting
var config = Config.default();
config.globalColorDisplay = false;
logger.configure(config);
```

### High-Throughput Async Sink

```zig
 _ = try logger.add(.{
    .path = "logs/high-volume.log",
    .asyncWrite = true,
    .bufferSize = 65536, // 64KB buffer
});
```

### Manual Flush Control

```zig
var sink = try logly.Sink.init(allocator, .{
    .path = "logs/batch.log",
    .asyncWrite = true,
    .onError = .propagate,
});
defer sink.deinit();

try sink.writeRaw("batch line 1");
try sink.writeRaw("batch line 2");

// Explicit durability checkpoint
try sink.flushNow();

const stats = sink.getStats();
std.debug.print("flushed records: {}\n", .{stats.getTotalWritten()});
```

### Multiple Sinks with Different Levels

```zig
// Console: info and above
 _ = try logger.addSink(.{
    .level = .info,
});

// File: all levels
 _ = try logger.addSink(.{
    .path = "logs/debug.log",
    .level = .trace,
});

// Errors file: errors only
 _ = try logger.addSink(.{
    .path = "logs/errors.log",
    .level = .err,
});
```

## Color Auto-Detection

When `color` is `null` (default), the sink auto-detects:
- **Console sinks**: Colors enabled if terminal supports ANSI
- **File sinks**: Colors disabled

Override with explicit `true` or `false`:

```zig
// Force colors off for console
 _ = try logger.addSink(.{ .color = false });

// Force colors on for file (e.g., for viewing with `less -R`)
 _ = try logger.addSink(.{
    .path = "logs/colored.log",
    .color = true,
});
```

## SinkStats

Statistics for monitoring sink performance.

### Getter Methods

| Method | Return | Description |
|--------|--------|-------------|
| `getTotalWritten()` | `u64` | Get total number of records written |
| `getBytesWritten()` | `u64` | Get total bytes written |
| `getWriteErrors()` | `u64` | Get number of write errors |
| `getFlushCount()` | `u64` | Get number of flush operations |
| `getRotationCount()` | `u64` | Get number of file rotations |

### Boolean Checks

| Method | Return | Description |
|--------|--------|-------------|
| `hasWritten()` | `bool` | Check if any records have been written |
| `hasErrors()` | `bool` | Check if any errors have occurred |
| `hasFlushed()` | `bool` | Check if any flushes have occurred |
| `hasRotated()` | `bool` | Check if any rotations have occurred |

### Rate Calculations

| Method | Return | Description |
|--------|--------|-------------|
| `throughputBytesPerSecond(elapsedSeconds)` | `f64` | Calculate bytes per second throughput |
| `throughputRecordsPerSecond(elapsedSeconds)` | `f64` | Calculate records per second throughput |
| `errorRate()` | `f64` | Calculate error rate (0.0 - 1.0) |
| `successRate()` | `f64` | Calculate success rate (0.0 - 1.0) |
| `avgBytesPerWrite()` | `f64` | Calculate average bytes per write |
| `avgFlushesPerRotation()` | `f64` | Calculate average flushes per rotation |

### Reset

| Method | Description |
|--------|-------------|
| `reset()` | Reset all statistics to initial state |

### Example

```zig
const stats = sink.getStats();
std.debug.print("Written: {} records, {} bytes\n", .{
    stats.getTotalWritten(),
    stats.getBytesWritten(),
});
std.debug.print("Error rate: {d:.2}%\n", .{stats.errorRate() * 100});
std.debug.print("Avg bytes/write: {d:.1}\n", .{stats.avgBytesPerWrite()});
```

## Compression Configuration

```zig
 _ = try logger.addSink(.{
    .path = "logs/app.log",
    .compression = .{
        .enabled = true,
        .algorithm = .gzip,
        .level = 6,
    },
});
```

## Per-Sink Filtering

```zig
 _ = try logger.addSink(.{
    .path = "logs/filtered.log",
    .filter = .{
        .includeModules = &.{"database", "http"},
        .excludeModules = &.{"health_check"},
        .includeMessages = &.{"important"},
        .excludeMessages = &.{"debug"},
    },
});
```

## Aliases

The Sink module provides convenience aliases:

| Alias | Method | Description |
|-------|--------|-------------|
| `statistics` | `getStats()` | Get sink statistics |
| `stats_` | `getStats()` | Get sink statistics |
| `clear` | `clearBuffer()` | Clear internal buffer |
| `sync` | `flush()` | Synchronize buffer to storage |
| `close` | `deinit()` | Close and cleanup sink |
| `name` | `getName()` | Get sink name |

## New Methods (v0.0.9)

```zig
// State management
const enabled = sink.isEnabled();
sink.enable();
sink.disable();

// Buffer management
sink.clearBuffer();

// Name access
const name = sink.getName();

// Statistics
const stats = sink.getStats();  // or sink.statistics()
```

## Configuration Helpers

Helper methods on `SinkConfig` for common use cases:

```zig
// Usage: logger.addSink(SinkConfig.console());

pub const SinkConfig = struct {
    /// Returns the default sink configuration (Console, async).
    pub fn default() SinkConfig;

    /// Returns a console sink configuration.
    pub fn console() SinkConfig;
    
    /// Returns a standard error sink configuration.
    pub fn stderr() SinkConfig;
    
    /// Returns a file sink configuration.
    pub fn file(path: []const u8) SinkConfig;

    /// Returns a JSON file sink configuration.
    pub fn jsonFile(path: []const u8) SinkConfig;
    
    /// Returns a rotating file sink configuration.
    pub fn rotating(path: []const u8, rotationInterval: []const u8, retentionCount: usize) SinkConfig;
    
    /// Returns an error-only sink configuration.
    pub fn errorOnly(path: []const u8) SinkConfig;
    
    /// Returns a network sink configuration.
    pub fn network(uri: []const u8) SinkConfig;

    /// Returns an in-memory ring buffer sink for testing/snapshots.
    pub fn memory() SinkConfig;
};
```

## SinkGroup

The `SinkGroup` struct enables atomic fan-out routing of a single log record to multiple named sinks efficiently.

```zig
pub const SinkGroup = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    sinks: std.ArrayListUnmanaged(*Sink),
    mutex: std.Io.Mutex,

    pub fn init(allocator: std.mem.Allocator) SinkGroup;
    pub fn initWithIo(allocator: std.mem.Allocator, io_handle: std.Io) SinkGroup;
    pub fn deinit(self: *SinkGroup) void;
    pub fn addSink(self: *SinkGroup, sink: *Sink) !void;
    pub fn write(self: *SinkGroup, record: *const Record, globalConfig: anytype) !void;
    pub fn flush(self: *SinkGroup) !void;
};
```

## MmapFile

High-performance memory-mapped file abstraction for sub-microsecond logging.

```zig
pub const MmapFile = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    file: std.Io.File,
    memory: []align(std.heap.page_size_min) u8,
    writePtr: usize,
    capacity: usize,
    isMapped: bool,

    pub fn init(allocator: std.mem.Allocator, file: std.Io.File, initialSize: usize) !MmapFile;
    pub fn initWithIo(allocator: std.mem.Allocator, io_handle: std.Io, file: std.Io.File, initialSize: usize) !MmapFile;
    pub fn deinit(self: *MmapFile) void;
    pub fn write(self: *MmapFile, data: []const u8) !void;
    pub fn flush(self: *MmapFile) void;
    pub fn finalizeForRotation(self: *MmapFile) void;
    pub fn remapToFile(self: *MmapFile, newFile: std.Io.File, initialSize: usize) !void;
    pub fn resumeMapping(self: *MmapFile) void;
};
```

## See Also

- [Sinks Guide](../guide/sinks.md) - Detailed sink configuration
- [Rotation Guide](../guide/rotation.md) - Log file rotation
- [JSON Guide](../guide/json.md) - JSON output configuration
- [Compression API](compression.md) - Compression options
- [Logger API](logger.md) - Logger sink management

