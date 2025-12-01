<div align="center">
<img src="https://github.com/user-attachments/assets/565fc3dc-dd2c-47a6-bab6-2f545c551f26" alt="logly logo" width="400" />

<a href="https://muhammad-fiaz.github.io/logly.zig/"><img src="https://img.shields.io/badge/docs-muhammad--fiaz.github.io-blue" alt="Documentation"></a>
<a href="https://ziglang.org/"><img src="https://img.shields.io/badge/Zig-0.15.1-orange.svg?logo=zig" alt="Zig Version"></a>
<a href="https://github.com/muhammad-fiaz/logly.zig"><img src="https://img.shields.io/github/stars/muhammad-fiaz/logly.zig" alt="GitHub stars"></a>
<a href="https://github.com/muhammad-fiaz/logly.zig/issues"><img src="https://img.shields.io/github/issues/muhammad-fiaz/logly.zig" alt="GitHub issues"></a>
<a href="https://github.com/muhammad-fiaz/logly.zig/pulls"><img src="https://img.shields.io/github/issues-pr/muhammad-fiaz/logly.zig" alt="GitHub pull requests"></a>
<a href="https://github.com/muhammad-fiaz/logly.zig"><img src="https://img.shields.io/github/last-commit/muhammad-fiaz/logly.zig" alt="GitHub last commit"></a>
<a href="https://github.com/muhammad-fiaz/logly.zig"><img src="https://img.shields.io/github/license/muhammad-fiaz/logly.zig" alt="License"></a>
<a href="https://github.com/muhammad-fiaz/logly.zig/actions/workflows/ci.yml"><img src="https://github.com/muhammad-fiaz/logly.zig/actions/workflows/ci.yml/badge.svg" alt="CI"></a>

<p><em>High-performance, structured logging library for Zig.</em></p>

**📚 [Documentation](https://muhammad-fiaz.github.io/logly.zig/) | [API Reference](https://muhammad-fiaz.github.io/logly.zig/api/logger) | [Quick Start](https://muhammad-fiaz.github.io/logly.zig/guide/quick-start)**

</div>

A production-ready, high-performance structured logging library for Zig with a clean, simplified API.

## Features

✨ **Simple & Clean API** - Python-like logging interface (`logger.info()`, `logger.error()`, etc.)  
🎯 **8 Log Levels** - TRACE, DEBUG, INFO, SUCCESS, WARNING, ERROR, FAIL, CRITICAL  
📁 **Multiple Sinks** - Console, file, and custom outputs  
🔄 **File Rotation** - Time-based (hourly to yearly) and size-based rotation  
🎨 **Colored Output** - ANSI colors with customizable callbacks  
📊 **JSON Logging** - Structured JSON output for log aggregation  
🔗 **Context Binding** - Attach persistent key-value pairs to logs  
⚡ **Async I/O** - Non-blocking writes with configurable buffering  
🔒 **Thread-Safe** - Safe concurrent logging  
🎭 **Custom Levels** - Define your own log levels with priorities  
📞 **Callbacks** - Monitor and react to log events

## Installation

Add to your `build.zig.zon`:

```zig
.dependencies = .{
    .logly = .{
        .url = "https://github.com/muhammad-fiaz/logly.zig/archive/refs/tags/v0.0.1.tar.gz",
        .hash = "...",
    },
},
```

Then in your `build.zig`:

```zig
const logly = b.dependency("logly", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("logly", logly.module("logly"));
```

## Quick Start

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create logger (console sink auto-enabled)
    const logger = try logly.Logger.init(allocator);
    defer logger.deinit();

    // Log at different levels - Python-like API!
    try logger.trace("Detailed trace information");
    try logger.debug("Debug information");
    try logger.info("Application started");
    try logger.success("Operation completed successfully!");
    try logger.warning("Warning message");
    try logger.err("Error occurred");
    try logger.fail("Operation failed");
    try logger.critical("Critical system error!");
}
```

## Usage Examples

### File Logging

```zig
const logger = try logly.Logger.init(allocator);
defer logger.deinit();

// Disable auto console sink
var config = logly.Config.default();
config.auto_sink = false;
logger.configure(config);

// Add file sink
_ = try logger.addSink(.{
    .path = "logs/app.log",
});

try logger.info("Logging to file!");
try logger.flush(); // Ensure data is written
```

### File Rotation

```zig
// Daily rotation with 7-day retention
_ = try logger.addSink(.{
    .path = "logs/daily.log",
    .rotation = "daily",
    .retention = 7,
});

// Size-based rotation (10MB limit, keep 5 files)
_ = try logger.addSink(.{
    .path = "logs/app.log",
    .size_limit = 10 * 1024 * 1024,
    .retention = 5,
});

// Combined: rotate daily OR when 5MB reached
_ = try logger.addSink(.{
    .path = "logs/combined.log",
    .rotation = "daily",
    .size_limit = 5 * 1024 * 1024,
    .retention = 10,
});
```

### JSON Logging

```zig
var config = logly.Config.default();
config.json = true;
config.pretty_json = true;
logger.configure(config);

try logger.info("JSON formatted log");
// Output: {"timestamp":1701234567890,"level":"INFO","message":"JSON formatted log"}
```

### Context Binding

```zig
// Application-wide context
try logger.bind("app", .{ .string = "myapp" });
try logger.bind("version", .{ .string = "1.0.0" });

try logger.info("Application started");
// All logs include app and version fields

// Request-specific context
try logger.bind("request_id", .{ .string = "req-12345" });
try logger.info("Processing request");
logger.unbind("request_id"); // Clean up
```

### Callbacks

```zig
fn logCallback(record: *const logly.Record) !void {
    if (record.level.priority() >= logly.Level.err.priority()) {
        // Send alert, update metrics, etc.
        std.debug.print("[ALERT] {s}\n", .{record.message});
    }
}

logger.setLogCallback(&logCallback);
try logger.err("Error occurred"); // Callback triggers
```

### Custom Log Levels

```zig
// Add custom level between WARNING (30) and ERROR (40)
try logger.addCustomLevel("NOTICE", 35, "96"); // Cyan color

try logger.custom("NOTICE", "Custom level message");
```

### Multiple Sinks

```zig
// Console
_ = try logger.addSink(.{});

// Application logs
_ = try logger.addSink(.{
    .path = "logs/app.log",
    .rotation = "daily",
    .retention = 7,
});

// Error-only file
_ = try logger.addSink(.{
    .path = "logs/errors.log",
    .level = .err, // Only ERROR and above
});
```

## Configuration

```zig
var config = logly.Config.default();

// Global controls
config.global_color_display = true;
config.global_console_display = true;
config.global_file_storage = true;

// Log level
config.level = .debug;

// Display options
config.show_time = true;
config.show_module = true;
config.show_function = false;
config.show_filename = false;
config.show_lineno = false;

// Output format
config.json = false;
config.color = true;

// Features
config.enable_callbacks = true;
config.enable_exception_handling = true;

logger.configure(config);
```

## Log Levels

| Level    | Priority | Method              | Use Case                |
| -------- | -------- | ------------------- | ----------------------- |
| TRACE    | 5        | `logger.trace()`    | Very detailed debugging |
| DEBUG    | 10       | `logger.debug()`    | Debugging information   |
| INFO     | 20       | `logger.info()`     | General information     |
| SUCCESS  | 25       | `logger.success()`  | Successful operations   |
| WARNING  | 30       | `logger.warning()`  | Warning messages        |
| ERROR    | 40       | `logger.err()`      | Error conditions        |
| FAIL     | 45       | `logger.fail()`     | Operation failures      |
| CRITICAL | 50       | `logger.critical()` | Critical system errors  |

## Rotation Intervals

- `minutely` - Rotate every minute
- `hourly` - Rotate every hour
- `daily` - Rotate every day
- `weekly` - Rotate every week
- `monthly` - Rotate every 30 days
- `yearly` - Rotate every 365 days

## Building

```bash
# Run tests
zig build test

# Build examples
zig build example-basic
zig build example-file_logging
zig build example-rotation
zig build example-json_logging
zig build example-callbacks
zig build example-context

# Run an example
./zig-out/bin/basic
```

## Documentation

Full documentation is available at: https://muhammad-fiaz.github.io/logly.zig

## Comparison with Rust Logly

| Feature         | Python Logly | Rust Logly   | Logly-Zig           |
| --------------- | ------------ | ------------ | ------------------- |
| Performance     | Fast         | Fast         | Native Zig (faster) |
| Memory Safety   | Runtime      | Compile-time | Compile-time        |
| Async Support   | ✓            | ✓            | ✓                   |
| File Rotation   | ✓            | ✓            | ✓                   |
| JSON Logging    | ✓            | ✓            | ✓                   |
| Custom Colors   | ✓            | ✓            | ✓                   |
| GPU Support (experimental)    |  ✗        | ✓            | ✗                   |
| Simplified API | ✓            |       ✓        | ✓                   |

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT License - see [LICENSE](LICENSE) for details.

## Links

- **Documentation**: https://muhammad-fiaz.github.io/logly.zig
- **Repository**: https://github.com/muhammad-fiaz/logly.zig
- **Issues**: https://github.com/muhammad-fiaz/logly.zig/issues
- **Rust Version**: https://github.com/muhammad-fiaz/logly-rs
- **Python Version**: https://github.com/muhammad-fiaz/logly
