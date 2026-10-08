---
title: addSink Reference
description: Complete client-side reference for Logger.addSink and every SinkConfig option in Logly.zig. Target selection, formats, color, buffering, rotation, compression, and memory sinks.
head:
  - - meta
    - name: keywords
      content: addSink, SinkConfig, sink options, log destination, file sink, console sink, network sink, memory sink, rotation, compression
  - - meta
    - property: og:title
      content: addSink Reference | Logly.zig
---

# addSink Reference

`Logger.addSink` is the single client-side entry point for adding an output
destination. `Logger.add` is a shorter alias for the same call.

```zig
const index = try logger.addSink(logly.SinkConfig.file("logs/app.log"));
```

It returns the sink's index, which `logger.getSink(index)` resolves back to a
handle for inspection. The logger owns every sink added this way and releases
it on `deinit`.

## Choosing a target

A sink's target is decided by the fields you set. Setting `path` makes a file
or network sink; leaving it unset makes a console sink.

```zig
// Console (stdout)
_ = try logger.addSink(.{});

// Console (stderr)
_ = try logger.addSink(.{ .isStderr = true });

// File
_ = try logger.addSink(.{ .path = "logs/app.log" });

// Network, by URI scheme in `path`
_ = try logger.addSink(.{ .path = "tcp://127.0.0.1:9000" });
_ = try logger.addSink(.{ .path = "udp://127.0.0.1:9000" });

// In-memory ring buffer
_ = try logger.addSink(logly.SinkConfig.memory());
```

| `path` value | Target |
| :--- | :--- |
| unset, `isMemory = false` | Console (stdout) |
| unset, `isStderr = true` | Console (stderr) |
| `"NUL"`, `"/dev/null"` | Null device; output is discarded, no file is created |
| `"tcp://host:port"` | TCP stream |
| `"udp://host:port"` | UDP socket |
| any other path | File, with parent directories created as needed |

## Preset helpers

These build a `SinkConfig` with sensible defaults. A struct literal gives the
same result with explicit control.

```zig
_ = try logger.addSink(logly.SinkConfig.console());
_ = try logger.addSink(logly.SinkConfig.file("logs/app.log"));
_ = try logger.addSink(logly.SinkConfig.jsonFile("logs/app.json"));
_ = try logger.addSink(logly.SinkConfig.rotating("logs/app.log", "daily", 7));
_ = try logger.addSink(logly.SinkConfig.errorOnly("logs/errors.log"));
_ = try logger.addSink(logly.SinkConfig.network("tcp://127.0.0.1:9000"));
_ = try logger.addSink(logly.SinkConfig.memory());
```

## Options

### Target and identity

| Field | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `path` | `?[]const u8` | `null` | Destination path or URI. Unset means console. |
| `name` | `?[]const u8` | `null` | Identifier used in metrics and diagnostics. |
| `isMemory` | `bool` | `false` | Route records to an in-process ring buffer. |
| `isStderr` | `bool` | `false` | Write to stderr instead of stdout. |
| `eventLog` | `bool` | `false` | Emit to the platform event log. Binary formats are rejected. |
| `enabled` | `bool` | `true` | Initial enabled state. |

### Format

| Field | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `format` | `?Config.Format` | `null` | Output format. `null` inherits the logger-wide format. |
| `prettyJson` | `bool` | `false` | Indent `.json` document output. |

`Config.Format` is one of `text`, `json`, `ndjson`, `logfmt`, `syslog`,
`syslog3164`, or `msgpack`. Set it per sink to render the same records
differently:

```zig
_ = try logger.addSink(.{ .path = "logs/app.log", .format = .text });
_ = try logger.addSink(.{ .path = "logs/app.ndjson", .format = .ndjson });
_ = try logger.addSink(.{ .path = "logs/app.syslog", .format = .syslog });
```

### Level and filtering

| Field | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `level` | `?Level` | `null` | Minimum level for this sink. Records below it are skipped. |
| `maxLevel` | `?Level` | `null` | Maximum level for this sink, forming a level range. |

```zig
// Everything
_ = try logger.addSink(.{ .path = "logs/app.log" });
// Warnings and above only
_ = try logger.addSink(.{ .path = "logs/warnings.log", .level = .warning });
// Errors through critical only
_ = try logger.addSink(.{ .path = "logs/incidents.log", .level = .err, .maxLevel = .critical });
```

### Color

| Field | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `color` | `?bool` | `null` | `null` auto-detects: on for a TTY console, off for files and network. |

Color is presentation applied per sink. A console color setting never adds ANSI
to a file or network sink, and files never receive ANSI unless asked:

```zig
_ = try logger.addSink(.{ .name = "console", .color = true });
_ = try logger.addSink(.{ .path = "logs/app.log", .color = false });
```

Set the color mode and per-field colors on `Config` with `colorMode` and
`columnColors`. See [Colors](/guide/colors).

### Buffering and flushing

| Field | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `asyncWrite` | `bool` | `true` | Buffer records and write in batches. |
| `bufferSize` | `usize` | sink default | Buffer threshold in bytes that triggers a flush. |
| `maxBufferRecords` | `usize` | sink default | Record count that triggers a flush. |
| `flushIntervalMs` | `u64` | sink default | Maximum time a record may sit unflushed. |
| `rateLimitPerSecond` | `u32` | `0` | Records per second; `0` disables rate limiting. |

`asyncWrite` only controls buffering. It does not change which target is
written, and it does not interact with the logger-wide `autoFlush`.

### Rotation

| Field | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `rotation` | `?[]const u8` | `null` | Time interval: `minutely`, `hourly`, `daily`, `weekly`, `monthly`, `yearly`. |
| `sizeLimit` | `?u64` | `null` | Rotate once the file passes this many bytes. |
| `sizeLimitStr` | `?[]const u8` | `null` | Human-readable size such as `"10MB"`, used when `sizeLimit` is unset. |
| `retention` | `?usize` | `null` | Number of rotated files to keep. Older archives are pruned. |
| `namingFormat` | `?[]const u8` | `null` | Archive name template, e.g. `"{base}-{date}{ext}"`. |

```zig
// Daily, keeping 7 archives
_ = try logger.addSink(.{ .path = "logs/app.log", .rotation = "daily", .retention = 7 });

// Size cap expressed as a string
_ = try logger.addSink(.{ .path = "logs/data.log", .sizeLimitStr = "50MB", .retention = 5 });

// Rotate on either condition
_ = try logger.addSink(.{
    .path = "logs/combined.log",
    .rotation = "daily",
    .sizeLimit = 5 * 1024 * 1024,
    .retention = 10,
});
```

Rotation callbacks and total-size caps are logger-wide; set
`config.rotation.onRotate` and `config.rotation.maxTotalSize` on `Config`.

### Write mode

| Field | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `writeMode` | `WriteMode` | `.append` | `append`, `overwrite`, or `appendRotate`. |
| `overwriteMode` | `bool` | `false` | Convenience flag: `true` truncates the file at startup. |

### Performance

| Field | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `mmap` | `bool` | `false` | Memory-map the file and grow the mapping on demand. |

### Integrity

| Field | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `tamperEvident` | `bool` | `false` | Chain each record with a SHA-256 signature over the previous one. |

### Record content

| Field | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `includeTimestamp` | `bool` | `true` | Render the timestamp. |
| `includeLevel` | `bool` | `true` | Render the level. |
| `includeSource` | `bool` | `false` | Render `file:line`. |
| `includeTraceId` | `bool` | `false` | Render trace and span identifiers. |

### Compression

| Field | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `compression` | `CompressionConfig` | `.{}` | Compress rotated files. Set `.enabled` and `.algorithm`. |

```zig
_ = try logger.addSink(.{
    .path = "logs/app.log",
    .rotation = "daily",
    .retention = 7,
    .compression = .{ .enabled = true, .algorithm = .gzip },
});
```

## Storage and display flags

`Config.globalConsoleDisplay` and `Config.globalFileStorage` decide which
sinks are legal. A request that contradicts the active flags fails with a typed
error instead of creating a dead file or an empty console target:

| Situation | Result |
| :--- | :--- |
| `globalFileStorage = false`, file sink added | `error.FileStorageDisabled` |
| `globalConsoleDisplay = false`, console sink added | `error.ConsoleDisplayDisabled` |
| Null-device path with file storage off | Allowed; creates no file |
| Memory sink with console display off | Allowed; captures in-process |

`Config.autoSink` adds a console sink at startup, and only when
`globalConsoleDisplay` is also enabled.

## Inspecting sinks

```zig
const index = try logger.addSink(logly.SinkConfig.memory());
if (logger.getSink(index)) |sink| {
    const messages = try sink.getMemoryMessages(allocator);
    defer {
        for (messages) |m| allocator.free(m);
        allocator.free(messages);
    }
    for (messages) |m| std.debug.print("{s}\n", .{m});
}
```

Sink management helpers: `getSinkCount()`, `removeSink(index)` (alias
`remove`), `removeAllSinks()` (aliases `removeAll` and `clear`).

## Io handle

Logging works with no configuration: Logly uses a default `std.Io` that
covers the synchronous file and console paths. Network transports need
`async`/`concurrent` capability, which the default does not provide. Install
your own handle once at startup:

```zig
var threaded = std.Io.Threaded.init(allocator, .{});
defer threaded.deinit();

logly.setIo(threaded.io());
```
