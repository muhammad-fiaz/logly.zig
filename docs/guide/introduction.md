---
title: What is Logly.zig?
description: Logly.zig is a high-performance structured logging library for Zig with zero-copy architecture, async I/O, JSON output, file rotation, and enterprise features like redaction, metrics, and distributed tracing.
head:
  - - meta
    - name: keywords
      content: logly zig, zig logging library, structured logging, high performance logging, async logging, json logging, zig logger
---

# What is Logly.zig?

Logly.zig is a high-performance, structured logging library for Zig, designed to deliver a comprehensive feature set while maximizing native Zig performance and safety guarantees.

## Key Features

### 🚀 Performance

- **Zero-Copy Architecture**: Minimized allocations for maximum throughput.
- **Asynchronous I/O**: Non-blocking write operations to keep your application responsive.
- **Thread-Safety**: Fully optimized for concurrent execution environments.
- **Efficient Buffering**: Configurable buffer strategies to balance latency and throughput.

### 🛠️ Flexibility

- **Comprehensive Log Levels**: 10 distinct levels (TRACE, DEBUG, INFO, NOTICE, SUCCESS, WARNING, ERROR, FAIL, CRITICAL, FATAL) for granular control.
- **Multi-Sink Support**: Simultaneously output to console, files, and custom destinations.
- **Custom Formatting**: Flexible template strings and full printf-style formatting support.
- **Rich Context**: Structured logging with JSON support and context binding.
- **Network Logging**: Send logs via TCP or UDP to remote servers or aggregators.
- **Custom Themes**: Define custom color themes for log levels.
- **Advanced Redaction**: Custom patterns and callbacks for sensitive data.
- **Persistent Context**: Scoped loggers with persistent fields.
- **Whole-Line Coloring**: ANSI colors wrap the entire log line (timestamp, level, message) for better visual scanning.
- **Custom Levels**: Define your own log levels with custom names, priorities, and colors.
- **Cross-Platform Colors**: Works on Linux, macOS, Windows 10+, and popular terminals.

### 🛡️ Reliability

- **Concurrency Safe**: Robust locking mechanisms ensure data integrity across threads.
- **Resilient Error Handling**: Comprehensive error types and recovery strategies.
- **Automated Rotation**: Sophisticated time-based and size-based file rotation.
- **Retention Management**: Automatic cleanup policies to manage disk usage.

## Design Philosophy

Logly.Zig is built upon the following core principles:

1.  **Developer Experience**: An intuitive, ergonomic API that reduces cognitive load.
2.  **Uncompromised Performance**: Optimized for high-throughput, low-latency applications.
3.  **Type Safety**: Leveraging Zig's powerful compile-time checks to prevent runtime errors.
4.  **Zero-Cost Abstractions**: Features that incur no runtime overhead when unused.
5.  **Modularity**: A composable architecture allowing you to include only what you need.

## Comparison with Other Implementations

| Feature                   | Logly.zig              | std.log               |
| :------------------------ | :--------------------- | :-------------------- |
| **Performance**           | Native Zig (Fast)      | Raw (Manual)          |
| **Memory Safety**         | **Compile-time**       | Compile-time          |
| **Async Support**         | **✓ Automatic**        | ✗ Manual              |
| **File Rotation**         | **✓ Automatic**        | ✗ Manual              |
| **JSON Logging**          | **✓ Automatic**        | ✗ Manual              |
| **Custom Colors**         | **✓ Automatic**        | ✗                     |
| **Simplified API**        | ✓                       | ✓                    | **✓**               | ✓ Basic |
| **Filtering**             | ✓ Automatic             | ✓ Automatic          | **✓ Automatic**     | ✓ Manual |
| **Sampling**              | ✗ (Planned)             | ✗ (Planned)          | **✓ Automatic**     | ✗ |
| **Redaction**             | ✗ (Planned)             | ✗ (Planned)          | **✓ Automatic**     | ✗ |
| **Metrics**               | ✗ (Planned)             | ✗ (Planned)          | **✓ Automatic**     | ✗ |
| **Tracing**               | ✗ (Planned)             | ✗ (Planned)          | **✓ Automatic**     | ✗ |
| **Compression**           | ✗ (Planned)             | ✗ (Planned)          | **✓ Automatic**     | ✗ |
| **Thread Pool**           | ✗ (Planned)             | ✗ (Planned)          | **✓ Automatic**     | ✗ |
| **Scheduler**             | ✗ (Planned)             | ✗ (Planned)          | **✓ Automatic**     | ✗ |
| **Custom Formats**        | ✗ (Planned)             | ✗ (Planned)          | **✓ Automatic**     | ✗ Manual |
| **Cross-Platform Colors** | ✓                       | ✓                    | **✓**               | ✗ |
| **Invoke System (v0.0.9+)**| ✗                       | ✗                    | **✓ Automatic**     | ✗ |

> [!TIP]
> For a comprehensive comparison with other Zig logging libraries including nexlog, log.zig, and std.log, see the [Comparison](/guide/comparison) page.

## Enterprise Features

Logly.zig v0.0.6+ includes enterprise-grade features:

### 🔍 Filtering

Rule-based log filtering by level, message patterns, or modules.

### 📊 Sampling

Probability-based sampling, rate limiting, and every-Nth message sampling for high-volume scenarios.

### 🔒 Redaction

Automatic masking of sensitive data (passwords, API keys, PII) in log messages.

### 📈 Metrics

Built-in metrics collection for logging performance monitoring.

### 🔗 Distributed Tracing

OpenTelemetry-compatible trace context propagation with automatic span ID generation.

### 🎨 Cross-Platform Colors

Enhanced ANSI color support for Windows, Linux, macOS, and bare metal/freestanding targets.

### 📝 Method Aliases

Short aliases for common methods: `warn`/`crit` for levels, `add`/`remove`/`clear`/`count` for sink management.

## When to Use Logly.Zig

Logly.Zig is perfect for:

- **Production applications** requiring robust logging
- **High-performance systems** with strict latency requirements
- **Cross-platform projects** targeting multiple operating systems
- **Projects** that need structured logging for analysis
- **Teams** looking for a structured logging solution
- **Microservices** requiring distributed tracing support
- **Compliance-sensitive** applications needing data redaction
- **Embedded/bare metal** systems needing efficient logging

## Next Steps

- [Getting Started](/guide/getting-started) - Install and set up Logly.Zig
- [Quick Start](/guide/quick-start) - Your first logging program
- [Configuration](/guide/configuration) - Configure your logger
