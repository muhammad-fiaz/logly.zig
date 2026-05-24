---
title: MessagePack Binary Formatter
description: Learn how to utilize Logly's compact MessagePack binary formatter to minimize network and disk footprints.
---

# MessagePack Binary Formatter

Structured loggers typically output logs in JSON format. While JSON is highly human-readable and universally supported, it is an extremely verbose text format. The duplication of field names (like `"timestamp"`, `"level"`, `"message"`, `"module"`) in every single log record consumes substantial disk space and network bandwidth in high-throughput enterprise systems.

Logly addresses this by introducing a native **MessagePack (msgpack) Formatter**. MessagePack is a highly efficient, standard-compliant binary serialization format. It lets you serialize structured logs into compact binary payloads that retain the full key-value expressiveness of JSON while cutting storage footprint by **30% to 70%**.

---

## Performance & Payload Size Comparison

Consider a typical structured log record:

```json
{
  "timestamp": 1701234567890,
  "level": "WARNING",
  "message": "High database connection latency",
  "module": "db.client",
  "latency_ms": 145.2
}
```

* **Standard JSON Output**: 136 bytes
* **MessagePack Binary Output**: **68 bytes (50% size reduction!)**

This binary compression is achieved by encoding data types directly into header bits and eliminating verbose text quotes and field separators:

```
[FixMap Header (5 fields)] -> [FixStr Key: "timestamp"] -> [UInt64 Value: 1701234567890] -> ...
```

---

## Enabling MessagePack Formatting

To enable MessagePack formatting, set `msgpack = true` in your main configuration or on the individual file/network sinks:

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Enable MessagePack formatting globally
    var config = logly.Config.default();
    config.msgpack = true; // [!code hl] // Force binary MessagePack output
    config.json = false;

    const logger = try logly.Logger.initWithConfig(allocator, config);
    defer logger.deinit();

    try logger.info("This record will be saved in MessagePack binary format!", @src());
    try logger.flush();
}
```

---

## API Reference

### Manual Serialization

You can serialize a record manually using Logly's formatting library, which is useful when building custom network ingestion tools:

```zig
const record = logly.Record.init(allocator, .warning, "Database latency");
defer record.deinit();

var formatter = logly.Formatter.init(allocator);
defer formatter.deinit();

const binary_data = try formatter.formatMsgpackWithAllocator(&record, allocator);
defer allocator.free(binary_data);

std.debug.print("Binary length: {d} bytes\n", .{binary_data.len});
```

---

## Best Practices

> [!NOTE]
> MessagePack is a standard binary format. Sinks that stream MessagePack data can be consumed natively by enterprise log aggregators like **Vector**, **Fluentbit**, **Logstash**, and **Elasticsearch** without intermediate conversion.

* **Use for Network Sinks**: MessagePack is ideal for TCP/UDP socket sinks, as it dramatically reduces packet sizes, reduces packet fragmentation, and increases throughput.
* **Combine with Compression**: When combined with Logly's `Zstd` compression, MessagePack binary data yields extreme compression ratios, saving massive long-term archive costs.
* **Tool Integration**: Ensure your ingestion receiver is configured to parse MessagePack binary headers instead of raw JSON.
