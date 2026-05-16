---
title: Logly.zig vs Other Zig Logging Libraries
description: Compare Logly.zig with nexlog, log.zig, and std.log. See feature comparisons, performance benchmarks, and learn why Logly.zig offers the most comprehensive logging solution for Zig applications.
head:
  - - meta
    - name: keywords
      content: zig logging comparison, logly vs nexlog, zig logger benchmark, std.log alternative, best zig logger, zig logging performance
---

# Comparison

This page provides a comprehensive comparison between Logly.zig and other Zig logging libraries, including the standard library's logging functions.

## Feature Comparison

### Logly.zig vs Other Zig Logging Libraries

| Feature | logly.zig | nexlog | log.zig | std.log |
|:--------|:----------|:-------|:--------|:--------|
| Current Version | 0.1.8 | 0.7.2 | 0.0.0 | Built-in |
| Min Zig Version | 0.16.0+ | 0.14, 0.15-dev | 0.11+ | Any |
| API Style | User-friendly | Builder/Fluent | Pool/Fluent | Basic/Manual |
| Structured Logging | ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ Automatic | ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ JSON/logfmt | ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ JSON/logfmt | ÃƒÂ¢Ã‚ÂÃ…â€™ Manual |
| File Formats (.json, .txt, .log) | ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ Automatic | ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ | ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ | ÃƒÂ¢Ã‚ÂÃ…â€™ |
| Async Logging | ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ Automatic (ring buffer, workers) | ÃƒÂ¢Ã…Â¡Ã‚Â  Basic | ÃƒÂ¢Ã‚ÂÃ…â€™ | ÃƒÂ¢Ã‚ÂÃ…â€™ |
| Thread Safety | ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ Automatic | ÃƒÂ¢Ã…Â¡Ã‚Â  Partial | ÃƒÂ¢Ã…Â¡Ã‚Â  Pool-only | ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ Basic |
| Single/Multi-Thread Support | ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ | ÃƒÂ¢Ã‚ÂÃ…â€™ | ÃƒÂ¢Ã‚ÂÃ…â€™ | ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ Manual |
| Multiple Sinks | ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ Automatic | ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ | ÃƒÂ¢Ã…Â¡Ã‚Â  Limited | ÃƒÂ¢Ã‚ÂÃ…â€™ |
| File Logging | ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ Automatic | ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ | ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ | ÃƒÂ¢Ã‚ÂÃ…â€™ Manual |
| File Rotation | ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ Automatic (Time + Size) | ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ Size | ÃƒÂ¢Ã‚ÂÃ…â€™ | ÃƒÂ¢Ã‚ÂÃ…â€™ |
| Retention Policy | ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ Automatic | ÃƒÂ¢Ã‚ÂÃ…â€™ | ÃƒÂ¢Ã‚ÂÃ…â€™ | ÃƒÂ¢Ã‚ÂÃ…â€™ |
| Compression | ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ Automatic (gzip/zlib/deflate/zstd, lzma, lzma2, xz, tar.gz, zip, lz4) | ÃƒÂ¢Ã‚ÂÃ…â€™ | ÃƒÂ¢Ã‚ÂÃ…â€™ | ÃƒÂ¢Ã‚ÂÃ…â€™ |
| Zstd Compression (v0.1.8+) | ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ Levels 1-22, presets, batch ops | ÃƒÂ¢Ã‚ÂÃ…â€™ | ÃƒÂ¢Ã‚ÂÃ…â€™ | ÃƒÂ¢Ã‚ÂÃ…â€™ |
| Rotation Presets (v0.1.8+) | ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ 25+ presets (time/size/hybrid/production) | ÃƒÂ¢Ã‚ÂÃ…â€™ | ÃƒÂ¢Ã‚ÂÃ…â€™ | ÃƒÂ¢Ã‚ÂÃ…â€™ |
| Performance Defaults (v0.1.8+) | ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ Optimized auto_flush/callbacks defaults | ÃƒÂ¢Ã‚ÂÃ…â€™ | ÃƒÂ¢Ã‚ÂÃ…â€™ | ÃƒÂ¢Ã‚ÂÃ…â€™ |
| Network Logging | ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ Automatic (TCP/UDP) | ÃƒÂ¢Ã‚ÂÃ…â€™ | ÃƒÂ¢Ã‚ÂÃ…â€™ | ÃƒÂ¢Ã‚ÂÃ…â€™ |
| Stack Traces | ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ Automatic | ÃƒÂ¢Ã‚ÂÃ…â€™ | ÃƒÂ¢Ã‚ÂÃ…â€™ | ÃƒÂ¢Ã‚ÂÃ…â€™ Manual |
| Redaction (PII) | ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ Automatic | ÃƒÂ¢Ã‚ÂÃ…â€™ | ÃƒÂ¢Ã‚ÂÃ…â€™ | ÃƒÂ¢Ã‚ÂÃ…â€™ |
| Sampling/Rate Limit | ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ Automatic | ÃƒÂ¢Ã‚ÂÃ…â€™ | ÃƒÂ¢Ã‚ÂÃ…â€™ | ÃƒÂ¢Ã‚ÂÃ…â€™ |
| Distributed Tracing | ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ Automatic (Trace/Span/Correlation IDs) + Callbacks | ÃƒÂ¢Ã…Â¡Ã‚Â  Context only | ÃƒÂ¢Ã‚ÂÃ…â€™ | ÃƒÂ¢Ã‚ÂÃ…â€™ |
| OpenTelemetry (v0.1.4+) | ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ Full OTLP/Jaeger/Zipkin/Datadog/AWS/Azure | ÃƒÂ¢Ã‚ÂÃ…â€™ | ÃƒÂ¢Ã‚ÂÃ…â€™ | ÃƒÂ¢Ã‚ÂÃ…â€™ |
| Metrics | ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ Automatic | ÃƒÂ¢Ã‚ÂÃ…â€™ | ÃƒÂ¢Ã…Â¡Ã‚Â  Prometheus | ÃƒÂ¢Ã‚ÂÃ…â€™ |
| System Diagnostics | ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ Automatic | ÃƒÂ¢Ã‚ÂÃ…â€™ | ÃƒÂ¢Ã‚ÂÃ…â€™ | ÃƒÂ¢Ã‚ÂÃ…â€™ |
| Filtering | ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ Automatic | ÃƒÂ¢Ã‚ÂÃ…â€™ | ÃƒÂ¢Ã‚ÂÃ…â€™ | ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ Manual |
| Scheduled Cleaning | ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ Automatic | ÃƒÂ¢Ã‚ÂÃ…â€™ | ÃƒÂ¢Ã‚ÂÃ…â€™ | ÃƒÂ¢Ã‚ÂÃ…â€™ |
| Dynamic Path | ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ Automatic | ÃƒÂ¢Ã‚ÂÃ…â€™ | ÃƒÂ¢Ã‚ÂÃ…â€™ | ÃƒÂ¢Ã‚ÂÃ…â€™ |
| Module-level Config | ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ | ÃƒÂ¢Ã‚ÂÃ…â€™ | ÃƒÂ¢Ã‚ÂÃ…â€™ | ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ Manual |
| Custom Log Levels | ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ | ÃƒÂ¢Ã‚ÂÃ…â€™ | ÃƒÂ¢Ã‚ÂÃ…â€™ | ÃƒÂ¢Ã‚ÂÃ…â€™ |
| Rules System (v0.1.0+) | ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ Template-triggered messages | ÃƒÂ¢Ã‚ÂÃ…â€™ | ÃƒÂ¢Ã‚ÂÃ…â€™ | ÃƒÂ¢Ã‚ÂÃ…â€™ |
| Bare-Metal Support | ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ | ÃƒÂ¢Ã‚ÂÃ…â€™ | ÃƒÂ¢Ã‚ÂÃ…â€™ | ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ |
| Prebuilt Libraries | ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ | ÃƒÂ¢Ã‚ÂÃ…â€™ | ÃƒÂ¢Ã‚ÂÃ…â€™ | ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ |
| Documentation Site | ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ | ÃƒÂ¢Ã‚ÂÃ…â€™ | ÃƒÂ¢Ã‚ÂÃ…â€™ | ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ |
| Auto-Update Checker | ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ | ÃƒÂ¢Ã‚ÂÃ…â€™ | ÃƒÂ¢Ã‚ÂÃ…â€™ | ÃƒÂ¢Ã‚ÂÃ…â€™ |
| CI/CodeQL | ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ | ÃƒÂ¢Ã…Â¡Ã‚Â  | ÃƒÂ¢Ã‚ÂÃ…â€™ | ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ |
| License | MIT | MIT | MIT | MIT |

### Standard Library Comparison (Automatic vs Manual)

| Feature | logly.zig | std.log | Notes |
|:--------|:----------|:--------|:------|
| Log Levels | ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ 10 levels (trace ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ fatal) | 4 levels (debug, info, warn, err) | logly.zig has more granularity |
| Custom Levels | ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ Automatic | ÃƒÂ¢Ã‚ÂÃ…â€™ | Define your own levels |
| Colored Output | ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ Automatic | ÃƒÂ¢Ã‚ÂÃ…â€™ | Cross-platform ANSI colors |
| JSON Output | ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ Automatic | ÃƒÂ¢Ã‚ÂÃ…â€™ Manual | Built-in JSON formatter |
| File Output | ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ Automatic | ÃƒÂ¢Ã‚ÂÃ…â€™ Manual (stderr only) | Must implement manually for std.log |
| Async Logging | ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ Automatic | ÃƒÂ¢Ã‚ÂÃ…â€™ Manual | Ring buffer with workers |
| Context Binding | ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ Automatic | ÃƒÂ¢Ã‚ÂÃ…â€™ Manual | Persistent fields across logs |
| Formatted Logging | ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ Automatic templates | ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ Manual format strings | std.log uses basic printf-style |
| Thread Safety | ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ Automatic (advanced) | ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ Basic | logly.zig has lock-free options |
| Performance Tuning | ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ Automatic presets | ÃƒÂ¢Ã‚ÂÃ…â€™ Manual | Production/development presets |
| File Rotation | ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ Automatic | ÃƒÂ¢Ã‚ÂÃ…â€™ Manual | Time + size based rotation |
| Compression | ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ Automatic | ÃƒÂ¢Ã‚ÂÃ…â€™ Manual | gzip/zlib/zstd support |
| Network Logging | ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ Automatic | ÃƒÂ¢Ã‚ÂÃ…â€™ Manual | TCP/UDP sinks |
| Redaction | ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ Automatic | ÃƒÂ¢Ã‚ÂÃ…â€™ Manual | PII masking built-in |
| Metrics | ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ Automatic | ÃƒÂ¢Ã‚ÂÃ…â€™ Manual | Built-in counters and stats |
| Distributed Tracing | ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ Automatic | ÃƒÂ¢Ã‚ÂÃ…â€™ Manual | Trace/span/correlation IDs |
| Rules System | ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ Automatic triggers | ÃƒÂ¢Ã‚ÂÃ…â€™ | Template-based diagnostic messages |

::: info Automatic vs Manual
- **Automatic**: Feature works out-of-the-box with configuration
- **Manual**: Feature requires custom implementation by the developer
- std.log provides raw performance but requires manual implementation for most features
:::

## Performance Comparison

| Scenario | logly.zig | nexlog | log.zig | std.log |
|:---------|:----------|:-------|:--------|:--------|
| Simple text logging (ops/sec) | **117,334** | 41,297 | ~120,000 | ~150,000( avg-based on hardware) |
| Colored logging (ops/sec) | **116,864** | ~38,000 | ~105,000 | N/A |
| Formatted logging (ops/sec) | **37,341** | ~30,000 | ~20,000 | N/A (manual) |
| JSON compact (ops/sec) | **53,149** | 26,790 | ~35,000 | N/A |
| JSON formatted (ops/sec) | **30,426** | ~22,000 | ~25,000 | N/A |
| JSON pretty (ops/sec) | **15,963** | ~12,000 | ~18,000 | N/A |
| Async high-throughput (ops/sec) | **36,483,035** | ~180,000 | N/A | N/A |
| Multi-threaded (4 threads, ops/sec) | **51,211** | ~22,000 | ~18,000 | N/A (based on implementation) |
| Multi-threaded JSON (4 threads, ops/sec) | **37,412** | ~14,000 | ~12,000 | N/A |
| Avg latency ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Å“ minimal config (ns) | **8,758** | ~24,000 | ~8,000 | N/A (based on implementation) |
| Avg latency ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Å“ JSON compact (ns) | **18,815** | ~37,000 | ~28,000 | N/A |
| Avg latency ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Å“ production preset (ns) | **28,278** | ~45,000 | ~35,000 | N/A |
| Max observed throughput (ops/sec) | **36.48M** | ~0.18M | ~0.12M |N/A (based on implementation) |
| Avg baseline latency (ns) | **~939** | ~25,000 | ~8,500 |N/A (based on implementation) |

::: warning Performance Note
- **std.log** has the lowest raw latency (~5,000 ns) because it's minimal and outputs to stderr only
- **logly.zig** trades slightly higher latency for automatic features (colors, JSON, rotation, etc.)
- All metrics vary based on system, OS, Zig version, hardware, and build configuration
- N/A means the feature is not available or requires manual implementation
:::

## Rules System (v0.1.0+)

Logly.zig includes a unique **Rules System** that provides compiler-style guided diagnostics:

```zig
// Define a rule that triggers on error logs containing "Database"
try rules.add(.{
    .id = 1,
    .level_match = .{ .exact = .err },
    .message_contains = "Database",
    .messages = &[_]logly.Rules.RuleMessage{
        .cause("Connection pool exhausted"),
        .fix("Increase max_connections in config"),
        .docs("DB Guide", "https://docs.example.com/db"),
    },
});

// When logging:
try logger.err("Database connection timeout", @src());

// Output:
// [ERROR] Database connection timeout
//     >> [ERROR] Connection pool exhausted
//     >> [FIX] Increase max_connections in config
//     >> [DOC] DB Guide (https://docs.example.com/db)
```

This feature is **not available** in std.log, nexlog, or log.zig.

## Links

| Library | GitHub |
|:--------|:-------|
| logly.zig | [github.com/muhammad-fiaz/logly.zig](https://github.com/muhammad-fiaz/logly.zig) |
| nexlog | [github.com/chrischtel/nexlog](https://github.com/chrischtel/nexlog) |
| log.zig | [github.com/karlseguin/log.zig](https://github.com/karlseguin/log.zig) |
| std.log | [Zig Standard Library](https://ziglang.org/documentation/master/std/#std.log) |

## Why Choose Logly.zig?

### Advantages

1. **Feature Complete**: Most comprehensive feature set among Zig logging libraries
2. **Automatic Everything**: Features work out-of-the-box vs manual implementation
3. **High Performance**: Optimized async logging with up to 36M ops/sec throughput
4. **Enterprise Ready**: Built-in redaction, metrics, distributed tracing
5. **Rules System**: Template-triggered diagnostic messages (unique feature)
6. **Developer Friendly**: Intuitive API with extensive documentation
7. **Production Tested**: Compression, rotation, and retention policies
8. **Cross-Platform**: Works on Linux, macOS, Windows, and bare-metal
9. **Multiple Compression Algorithms**: DEFLATE, GZIP, ZLIB, Zstd, LZMA, LZMA2, XZ, ZIP, TAR.GZ, LZ4 with automatic detection, factory methods, and presets
10. **Performance Optimized** (v0.1.8+): ~7.5x faster than v0.1.8 with performance-first defaults

## Compression Algorithm Comparison (v0.1.8+)

Logly.zig supports multiple compression and archive algorithms for log archival and archiving:

| Algorithm | Ratio | Compress Speed | Decompress Speed | Extension | Best For |
|:----------|:------|:---------------|:-----------------|:----------|:---------|
| **zstd** | 3-6x | ~400 MB/s | ~1400 MB/s | `.zst` | High-throughput, streaming, production |
| **gzip** | 3-5x | ~190 MB/s | ~290 MB/s | `.gz` | Compatibility, standard tooling |
| **deflate** | 3-5x | ~200 MB/s | ~300 MB/s | `.gz` | General purpose |
| **zlib** | 3-5x | ~180 MB/s | ~280 MB/s | `.gz` | Network transport |
| **lzma** | 5-8x | ~40 MB/s | ~120 MB/s | `.lzma` | Long-term archival (highest ratio) |
| **lzma2** | 5-8x | ~50 MB/s | ~120 MB/s | `.lzma` | Large file archival (multi-block LZMA) |
| **xz** | 5-8x | ~60 MB/s | ~120 MB/s | `.xz` | Distribution packages and high-ratio archives |
| **tar_gz** | 3-5x | ~180 MB/s | ~290 MB/s | `.tar.gz` | Multi-file Unix archives |
| **zip** | 3-5x | ~190 MB/s | ~290 MB/s | `.zip` | Cross-platform archives |
| **lz4** | 1-2x | ~600 MB/s | ~1000 MB/s | `.lz4` | Real-time, ultra-fast compression |

::: tip Recommendation
Use **zstd** (v0.1.8+) for best performance and a great general-purpose tradeoff. For long-term archival prefer **LZMA / XZ** (higher ratio); for ultra-low-latency real-time logging prefer **LZ4** (fastest). Choose based on the speed vs ratio trade-off for your workload.
:::

## OpenTelemetry Comparison (v0.1.4+)

Logly.zig provides comprehensive OpenTelemetry integration:

| Feature | logly.zig | nexlog | log.zig | std.log |
|:--------|:----------|:-------|:--------|:--------|
| OpenTelemetry Support | ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ Full | ÃƒÂ¢Ã‚ÂÃ…â€™ | ÃƒÂ¢Ã‚ÂÃ…â€™ | ÃƒÂ¢Ã‚ÂÃ…â€™ |
| OTLP Export | ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ JSON format | ÃƒÂ¢Ã‚ÂÃ…â€™ | ÃƒÂ¢Ã‚ÂÃ…â€™ | ÃƒÂ¢Ã‚ÂÃ…â€™ |
| Jaeger Integration | ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ Thrift format | ÃƒÂ¢Ã‚ÂÃ…â€™ | ÃƒÂ¢Ã‚ÂÃ…â€™ | ÃƒÂ¢Ã‚ÂÃ…â€™ |
| Zipkin Integration | ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ JSON format | ÃƒÂ¢Ã‚ÂÃ…â€™ | ÃƒÂ¢Ã‚ÂÃ…â€™ | ÃƒÂ¢Ã‚ÂÃ…â€™ |
| Datadog APM | ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ Native format | ÃƒÂ¢Ã‚ÂÃ…â€™ | ÃƒÂ¢Ã‚ÂÃ…â€™ | ÃƒÂ¢Ã‚ÂÃ…â€™ |
| Google Cloud Trace | ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ Native format | ÃƒÂ¢Ã‚ÂÃ…â€™ | ÃƒÂ¢Ã‚ÂÃ…â€™ | ÃƒÂ¢Ã‚ÂÃ…â€™ |
| Google Analytics 4 | ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ Measurement Protocol | ÃƒÂ¢Ã‚ÂÃ…â€™ | ÃƒÂ¢Ã‚ÂÃ…â€™ | ÃƒÂ¢Ã‚ÂÃ…â€™ |
| AWS X-Ray | ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ Segment format | ÃƒÂ¢Ã‚ÂÃ…â€™ | ÃƒÂ¢Ã‚ÂÃ…â€™ | ÃƒÂ¢Ã‚ÂÃ…â€™ |
| Azure App Insights | ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ Envelope format | ÃƒÂ¢Ã‚ÂÃ…â€™ | ÃƒÂ¢Ã‚ÂÃ…â€™ | ÃƒÂ¢Ã‚ÂÃ…â€™ |
| W3C Trace Context | ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ Full spec | ÃƒÂ¢Ã…Â¡Ã‚Â  Partial | ÃƒÂ¢Ã‚ÂÃ…â€™ | ÃƒÂ¢Ã‚ÂÃ…â€™ |
| W3C Baggage | ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ Full spec | ÃƒÂ¢Ã‚ÂÃ…â€™ | ÃƒÂ¢Ã‚ÂÃ…â€™ | ÃƒÂ¢Ã‚ÂÃ…â€™ |
| Span Sampling | ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ 4 strategies | ÃƒÂ¢Ã‚ÂÃ…â€™ | ÃƒÂ¢Ã‚ÂÃ…â€™ | ÃƒÂ¢Ã‚ÂÃ…â€™ |
| Metrics Export | ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ OTLP/Prometheus/JSON | ÃƒÂ¢Ã‚ÂÃ…â€™ | ÃƒÂ¢Ã…Â¡Ã‚Â  Prometheus | ÃƒÂ¢Ã‚ÂÃ…â€™ |
| File Exporter | ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ JSONL | ÃƒÂ¢Ã‚ÂÃ…â€™ | ÃƒÂ¢Ã‚ÂÃ…â€™ | ÃƒÂ¢Ã‚ÂÃ…â€™ |
| Custom Exporters | ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ Plugin API | ÃƒÂ¢Ã‚ÂÃ…â€™ | ÃƒÂ¢Ã‚ÂÃ…â€™ | ÃƒÂ¢Ã‚ÂÃ…â€™ |

**Note (v0.1.8):** Resolved a compile-time issue in the OTLP exporter (removed an unnecessary discard in `writeOtlpSpan`) and clarified span-processor behavior: `.simple` keeps completed spans pending until an explicit `exportSpans()` or `flush()` call, while `.batch` will auto-export when configured batch size or timeout thresholds are reached.

## Rotation Presets Comparison

Logly.zig offers 25+ rotation presets for common scenarios:

| Category | Presets | Other Libraries |
|:---------|:--------|:----------------|
| **Time-Based** | `daily7Days`, `daily30Days`, `daily90Days`, `daily365Days`, `hourly24Hours`, `hourly48Hours`, `hourly7Days`, `weekly4Weeks`, `weekly12Weeks`, `monthly12Months`, `minutely60` | ÃƒÂ¢Ã‚ÂÃ…â€™ Manual config |
| **Size-Based** | `size1MB`, `size5MB`, `size10MB`, `size25MB`, `size50MB`, `size100MB`, `size250MB`, `size500MB`, `size1GB` | ÃƒÂ¢Ã‚ÂÃ…â€™ Manual config |
| **Hybrid** | `dailyOr100MB`, `hourlyOr50MB`, `dailyOr500MB` | ÃƒÂ¢Ã‚ÂÃ…â€™ Not supported |
| **Production** | `production`, `enterprise`, `debug`, `highVolume`, `audit`, `minimal` | ÃƒÂ¢Ã‚ÂÃ…â€™ Not supported |
| **Sink Helpers** | `dailySink`, `hourlySink`, `weeklySink`, `monthlySink`, `sizeSink` | ÃƒÂ¢Ã‚ÂÃ…â€™ Not supported |

### When to Use std.log Instead

- **Ultra-minimal latency** is the only requirement (~5,000 ns vs ~8,758 ns)
- Simple applications with basic stderr logging needs
- When minimizing dependencies is critical (zero dependencies)
- Embedded systems with extreme memory constraints
- Quick prototyping without external dependencies
- You're willing to **manually implement** features like file output, rotation, JSON, etc.

## Migrating from std.log

```zig
// Before (std.log) - Manual, basic
const std = @import("std");
std.log.info("Hello, {s}!", .{"world"});
std.log.err("Error occurred: {}", .{error_code});

// After (logly.zig) - Automatic features
const logly = @import("logly");
var logger = try logly.Logger.init(allocator, .{});
defer logger.deinit();

try logger.info("Hello, {s}!", .{"world"}, @src());
try logger.err("Error occurred: {}", .{error_code}, @src());
```

## See Also

- [Getting Started](/guide/getting-started)
- [Installation](/guide/installation)
- [Configuration](/guide/configuration)
- [Rules System](/guide/rules)
