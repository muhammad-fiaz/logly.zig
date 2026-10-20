---
title: What is Logly.zig?
description: Logly.zig is a structured logging library for Zig with async I/O, JSON output, file rotation, redaction, metrics, and distributed tracing.
head:
  - - meta
    - name: keywords
      content: logly zig, zig logging library, structured logging, high performance logging, async logging, json logging, zig logger
---

# What is Logly.zig?

Logly.zig is a structured logging library for Zig built around explicit configuration and predictable allocation behavior.

## Key Features

### Performance

- **Allocation-Aware Design**: Records use caller-owned slices until dispatch; asynchronous paths clone records explicitly.
- **Asynchronous I/O**: `AsyncLogger` and the thread pool move formatting and writes off the calling thread when enabled.
- **Thread Safety**: Shared logger, sink, and filter state is protected by locks; statistics use atomic counters.
- **Efficient Buffering**: Configurable buffer strategies to balance latency and throughput.

### Flexibility

- **Log Levels**: 10 levels (TRACE, DEBUG, INFO, NOTICE, SUCCESS, WARNING, ERROR, FAIL, CRITICAL, FATAL).
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

### Reliability

- **Concurrency**: Per-logger and per-sink locking protect shared state across threads.
- **Error Handling**: Typed errors and configurable sink error policies.
- **Automated Rotation**: Sophisticated time-based and size-based file rotation.
- **Retention Management**: Automatic cleanup policies to manage disk usage.

## Design Philosophy

Logly.Zig is built upon the following core principles:

1.  **Explicit API**: Configuration is stated directly and validated before use.
2.  **Predictable Overhead**: Hot paths avoid per-record allocation unless an enabled feature requires it.
3.  **Type Safety**: Zig compile-time checks catch type errors; invalid runtime combinations return typed errors.
4.  **Feature Gating**: Disabled subsystems are not entered on the logging path.
5.  **Modularity**: Components can be used independently.

## Advanced Features

Logly.zig provides:

### Filtering

Rule-based log filtering by level, message patterns, or modules.

### Sampling

Probability-based sampling, rate limiting, and every-Nth message sampling for high-volume scenarios.

### Redaction

Automatic masking of sensitive data (passwords, API keys, PII) in log messages.

### Metrics

Built-in metrics collection for logging performance monitoring.

### Distributed Tracing

OpenTelemetry-compatible trace context propagation with automatic span ID generation.

### Cross-Platform Colors

Enhanced ANSI color support for Windows, Linux, macOS, and bare metal/freestanding targets.

### Method Aliases

The `Logger` type exposes `warn`, `crit`, `add`, and `remove` as short aliases for `warning`, `critical`, `addSink`, and `removeSink`.

## When to Use Logly.Zig

Logly.Zig is intended for:

- **Production applications** requiring structured logging
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
