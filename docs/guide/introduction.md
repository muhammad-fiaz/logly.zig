# What is Logly-Zig?

Logly-Zig is a high-performance, structured logging library for Zig, engineered to deliver the robust feature set of its Python and Rust counterparts while maximizing native Zig performance and safety guarantees.

## Key Features

### 🚀 Performance

- **Zero-Copy Architecture**: Minimized allocations for maximum throughput.
- **Asynchronous I/O**: Non-blocking write operations to keep your application responsive.
- **Thread-Safety**: Fully optimized for concurrent execution environments.
- **Efficient Buffering**: Configurable buffer strategies to balance latency and throughput.

### 🛠️ Flexibility

- **Comprehensive Log Levels**: 8 distinct levels (TRACE, DEBUG, INFO, SUCCESS, WARNING, ERROR, FAIL, CRITICAL) for granular control.
- **Multi-Sink Support**: Simultaneously output to console, files, and custom destinations.
- **Custom Formatting**: Flexible template strings and full printf-style formatting support.
- **Rich Context**: Structured logging with JSON support and context binding.
- **Whole-Line Coloring**: ANSI colors wrap the entire log line (timestamp, level, message) for better visual scanning.
- **Custom Levels**: Define your own log levels with custom names, priorities, and colors.
- **Cross-Platform Colors**: Works on Linux, macOS, Windows 10+, and popular terminals.

### 🛡️ Reliability

- **Concurrency Safe**: Robust locking mechanisms ensure data integrity across threads.
- **Resilient Error Handling**: Comprehensive error types and recovery strategies.
- **Automated Rotation**: Sophisticated time-based and size-based file rotation.
- **Retention Management**: Automatic cleanup policies to manage disk usage.

## Design Philosophy

Logly-Zig is built upon the following core principles:

1.  **Developer Experience**: An intuitive, Python-inspired API that reduces cognitive load.
2.  **Uncompromised Performance**: Optimized for high-throughput, low-latency applications.
3.  **Type Safety**: Leveraging Zig's powerful compile-time checks to prevent runtime errors.
4.  **Zero-Cost Abstractions**: Features that incur no runtime overhead when unused.
5.  **Modularity**: A composable architecture allowing you to include only what you need.

## Comparison with Other Implementations

| Feature            | Python Logly | Rust Logly   | Logly-Zig                |
| :----------------- | :----------- | :----------- | :----------------------- |
| **Performance**    | Maturin-Bindings (Fast)        | Native Rust (Faster)         | Native Zig (faster) |
| **Memory Safety**  | Runtime      | Compile-time | **Compile-time**         |
| **Async Support**  | ✓            | ✓            | **✓**                    |
| **File Rotation**  | ✓            | ✓            | **✓**                    |
| **JSON Logging**   | ✓            | ✓            | **✓**                    |
| **Custom Colors**  | ✓            | ✓            | **✓**                    |
| **Simplified API** | ✓            | ✓            | **✓**                    |
| **Filtering**      | ✓            | ✓            | **✓** (v0.0.3+)          |
| **Sampling**       | ✗ Coming soon!)            | ✗ (Coming soon!)           | **✓** (v0.0.3+)          |
| **Redaction**      | ✗ (Coming soon!)             | ✗ (Coming soon!)             | **✓** (v0.0.3+)          |
| **Metrics**        | ✗ (Coming soon!)           | ✗ (Coming soon!)            | **✓** (v0.0.3+)          |
| **Tracing**        | ✗ (Coming soon!)           | ✗ (Coming soon!)            | **✓** (v0.0.3+)          |
| **Compression**    | ✗ (Coming soon!)           | ✗ (Coming soon!)            | **✓** (v0.0.4+)          |
| **Thread Pool**    | ✗ (Coming soon!)           | ✗ (Coming soon!)            | **✓** (v0.0.4+)          |
| **Scheduler**      | ✗ (Coming soon!)           | ✗ (Coming soon!)            | **✓** (v0.0.4+)          |
| **Custom Formats** | ✗ (Coming soon!)           | ✗ (Coming soon!)            | **✓** (v0.0.4+)          |
| **Cross-Platform Colors** | ✓      | ✓            | **✓** (v0.0.4+ - improved)|

## Enterprise Features (v0.0.4+)

Logly-Zig v0.0.4 introduces enterprise-grade features:

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

### 🚀 Arena Allocator (v0.0.4+)
Optional arena allocator support for improved performance in high-throughput scenarios, reducing allocation overhead for temporary formatting operations.

### 🎨 Cross-Platform Colors (v0.0.4+)
Enhanced ANSI color support for Windows, Linux, macOS, and bare metal/freestanding targets.

### 📝 Method Aliases (v0.0.4+)
Short aliases for common methods: `warn`/`crit` for levels, `add`/`remove`/`clear`/`count` for sink management.

## When to Use Logly-Zig

Logly-Zig is perfect for:

- **Production applications** requiring robust logging
- **High-performance systems** with strict latency requirements
- **Cross-platform projects** targeting multiple operating systems
- **Projects** that need structured logging for analysis
- **Teams** familiar with Python's logging patterns
- **Microservices** requiring distributed tracing support
- **Compliance-sensitive** applications needing data redaction
- **Embedded/bare metal** systems needing efficient logging

## Next Steps

- [Getting Started](/guide/getting-started) - Install and set up Logly-Zig
- [Quick Start](/guide/quick-start) - Your first logging program
- [Configuration](/guide/configuration) - Configure your logger

