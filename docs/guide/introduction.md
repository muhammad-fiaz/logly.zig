# What is Logly-Zig?

Logly-Zig is a high-performance, structured logging library for Zig designed to provide all the features of the Python and Rust logly libraries with native Zig performance and safety guarantees.

## Key Features

### Performance

- **Zero-copy logging**: Minimal allocations
- **Async I/O**: Non-blocking writes
- **Thread-safe operations**: Optimized for concurrency
- **Efficient buffering**: Configurable buffer sizes

### Flexibility

- **8 log levels**: TRACE, DEBUG, INFO, SUCCESS, WARNING, ERROR, FAIL, CRITICAL
- **Multiple sinks**: Console, file, custom outputs
- **Custom formatting**: Template strings with placeholders
- **Colored output**: ANSI colors with custom callbacks

### Reliability

- **Thread-safe**: Safe concurrent logging
- **Error handling**: Comprehensive error types
- **File rotation**: Time and size-based rotation
- **Retention policies**: Automatic cleanup

## Design Philosophy

Logly-Zig follows these principles:

1. **Simplicity First**: Python-like API that's intuitive and easy to use
2. **Performance**: Optimized for high-throughput scenarios
3. **Type Safety**: Leverage Zig's compile-time guarantees
4. **Zero Cost Abstractions**: No runtime overhead
5. **Modular Design**: Use only what you need

## Comparison with Other Implementations

| Feature         | Python Logly | Rust Logly   | Logly-Zig           |
| --------------- | ------------ | ------------ | ------------------- |
| Performance     | Fast         | Faster         | Native Zig (Faster) |
| Memory Safety   | Runtime      | Compile-time | Compile-time        |
| Async Support   | ✓            | ✓            | ✓                   |
| File Rotation   | ✓            | ✓            | ✓                   |
| JSON Logging    | ✓            | ✓            | ✓                   |
| Custom Colors   | ✓            | ✓            | ✓                   |
| GPU Support     | Planned      | ✓            | ✗                   |
| Simplified API | ✓            |     ✓         | ✓                   |

## When to Use Logly-Zig

Logly-Zig is perfect for:

- **Production applications** requiring robust logging
- **High-performance systems** with strict latency requirements
- **Cross-platform projects** targeting multiple operating systems
- **Projects** that need structured logging for analysis
- **Teams** familiar with Python's logging patterns

## Next Steps

- [Getting Started](/guide/getting-started) - Install and set up Logly-Zig
- [Quick Start](/guide/quick-start) - Your first logging program
- [Configuration](/guide/configuration) - Configure your logger
