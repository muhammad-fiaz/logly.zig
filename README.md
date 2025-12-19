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
<img src="https://img.shields.io/badge/platforms-linux%20%7C%20windows%20%7C%20macos-blue" alt="Supported Platforms">
<a href="https://github.com/muhammad-fiaz/logly.zig/actions/workflows/github-code-scanning/codeql"><img src="https://github.com/muhammad-fiaz/logly.zig/actions/workflows/github-code-scanning/codeql/badge.svg" alt="CodeQL"></a>
<a href="https://github.com/muhammad-fiaz/logly.zig/actions/workflows/release.yml"><img src="https://github.com/muhammad-fiaz/logly.zig/actions/workflows/release.yml/badge.svg" alt="Release"></a>
<a href="https://github.com/muhammad-fiaz/logly.zig/releases/latest"><img src="https://img.shields.io/github/v/release/muhammad-fiaz/logly.zig?label=Latest%20Release&style=flat-square" alt="Latest Release"></a>
<a href="https://pay.muhammadfiaz.com"><img src="https://img.shields.io/badge/Sponsor-pay.muhammadfiaz.com-ff69b4?style=flat&logo=heart" alt="Sponsor"></a>
<a href="https://github.com/sponsors/muhammad-fiaz"><img src="https://img.shields.io/badge/Sponsor-💖-pink?style=social&logo=github" alt="GitHub Sponsors"></a>
<a href="https://github.com/muhammad-fiaz/logly.zig/releases"><img src="https://img.shields.io/github/downloads/muhammad-fiaz/logly.zig/total?label=Downloads&logo=github" alt="Downloads"></a>
<a href="https://hits.sh/muhammad-fiaz/logly.zig/"><img src="https://hits.sh/muhammad-fiaz/logly.zig.svg?label=Visitors&extraCount=0&color=green" alt="Repo Visitors"></a>

<p><em>A fast, high-performance structured logging library for Zig.</em></p>

<b>📚 <a href="https://muhammad-fiaz.github.io/logly.zig/">Documentation</a> |
<a href="https://muhammad-fiaz.github.io/logly.zig/api/logger">API Reference</a> |
<a href="https://muhammad-fiaz.github.io/logly.zig/guide/quick-start">Quick Start</a> |
<a href="CONTRIBUTING.md">Contributing</a></b>

</div>


A production-grade, high-performance structured logging library for Zig, designed with a clean, intuitive, and developer-friendly API.


**⭐️ If you love `logly.zig`, make sure to give it a star! ⭐️**

---

<details>
<summary><strong>✨ Features of Logly</strong> (click to expand)</summary>

| Feature | Description |
|---------|-------------|
| ✨ **Simple & Clean API** | Python-like logging interface (`logger.info()`, `logger.err()`, etc.) |
| 🎯 **8 Log Levels** | TRACE, DEBUG, INFO, SUCCESS, WARNING, ERROR, FAIL, CRITICAL |
| 🚀 **Custom Levels** | Define your own log levels with custom priorities and colors |
| 📁 **Multiple Sinks** | Console, file, and custom outputs simultaneously |
| 🔄 **File Rotation** | Time-based (hourly to yearly) and size-based rotation |
| 🎨 **Whole-Line Colors** | ANSI colors wrap entire log lines for better visual scanning |
| 📊 **JSON Logging** | Structured JSON output with valid array format for file storage |
| 📝 **Custom Formats** | Customizable log message and timestamp formats |
| 🌐 **Network Logging** | Send logs over TCP/UDP with JSON support and automatic reconnection |
| 🐛 **Stack Traces** | Automatic stack trace capture for errors and critical logs |
| 📦 **Compression** | Built-in support for GZIP, ZLIB, and DEFLATE compression |
| 📈 **Metrics** | Track logger performance, throughput, and error rates |
| 🩺 **System Diagnostics** | Emit OS/CPU/memory (and drives) on startup or on-demand |
| 🔍 **Scoped Logging** | Create child loggers with bound context that persists across calls |
| 🛡️ **Redaction** | Automatically mask sensitive data like passwords and API keys |
| 🔄 **Update Checker** | Automatically check for new versions of Logly |
| 🔗 **Context Binding** | Attach persistent key-value pairs to logs |
| ⚡ **Async I/O** | Non-blocking writes with configurable buffering |
| 🔒 **Thread-Safe** | Safe concurrent logging from multiple threads |
| 🎭 **Custom Levels** | Define your own log levels with custom priorities and colors |
| 📦 **Module Levels** | Set different log levels for specific modules |
| 🖨️ **Formatted Logging** | Printf-style formatting support (`infof`, `debugf`, etc.) |
| 📞 **Callbacks** | Monitor and react to log events programmatically |
| 🖥️ **Cross-Platform Colors** | Works on Linux, macOS, Windows 10+, and popular terminals |
| 🔍 **Filtering** | Rule-based log filtering by level, module, or content |
| 🪪 **Per-Sink Filtering** | Configure filters on each sink in addition to global logger filters |
| 🏗️ **Arena Allocation** | Optional arena allocator for reduced allocation overhead in high-throughput scenarios |
| 📍 **Source Location** | Optional clickable `file:line` output via `@src()` when `show_filename`/`show_lineno` are enabled |
| 🔧 **Method Aliases** | Convenience aliases for common APIs e.g., `add()` / `remove()` for sink management, `warn()` / `crit()` for logging |
| 📉 **Sampling** | Control log throughput with probability and rate-limiting |
| 🔐 **Redaction** | Automatic masking of sensitive data (PII, credentials) |
| 📈 **Metrics** | Built-in observability with log counters and statistics |
| 🔗 **Distributed Tracing** | Trace ID, span ID, and correlation ID support |
| ⚙️ **Configuration Presets** | Production, development, high-throughput, and secure presets |
| 🗜️ **Compression** | Automatic and manual log compression (deflate, gzip, lz4, zstd) |
| 🔄 **Async Logger** | Ring buffer-based async logging with background workers |
| 🧵 **Thread Pool** | Parallel log processing with work stealing |
| ⏰ **Scheduler** | Automatic log cleanup, compression, and maintenance |
| 🖥️ **System Diagnostics** | Automatic OS, CPU, memory, and drive information collection |
| 🌐 **Network Logging** | Send logs via TCP/UDP with JSON support and compression |
| 🎨 **Custom Themes** | Define custom color themes for log levels |
| 🔐 **Advanced Redaction** | Custom patterns and callbacks for sensitive data |
| 🔗 **Persistent Context** | Scoped loggers with persistent fields via `logger.with()` |
| 🔍 **Advanced Filtering** | Fluent API for complex filter rules |
| 🎛️ **Configuration Modes** | Log-only, display-only, and custom display/storage modes |

</details>

----

<details>
<summary><strong>📌 Prerequisites & Supported Platforms</strong> (click to expand)</summary>

<br>

## Prerequisites

Before installing Logly, ensure you have the following:

| Requirement | Version | Notes |
|-------------|---------|-------|
| **Zig** | 0.15.0+ | Download from [ziglang.org](https://ziglang.org/download/) |
| **Operating System** | Windows 10+, Linux, macOS | Cross-platform support |
| **Terminal** | Any modern terminal | For colored output support |

> **Tip:** Verify your Zig installation by running `zig version` in your terminal.

---

## Supported Platforms

Logly.Zig supports a wide range of platforms and architectures:

| Platform | Architectures | Status |
|----------|---------------|--------|
| **Windows** | x86_64, x86 | ✅ Full support |
| **Linux** | x86_64, x86, aarch64 | ✅ Full support |
| **macOS** | x86_64, aarch64 (Apple Silicon) | ✅ Full support |
| **Bare Metal / Freestanding** | x86_64, aarch64, arm, riscv64 | ✅ Full support |

---

### Color Support

| Terminal | Platform | Support |
|----------|----------|---------|
| **Windows Terminal** | Windows 10+ | ✅ Native ANSI |
| **cmd.exe** | Windows 10+ | ⚠️ Requires `enableAnsiColors()` |
| **iTerm2, Terminal.app** | macOS | ✅ Native |
| **GNOME Terminal, Konsole** | Linux | ✅ Native |
| **VS Code Terminal** | All | ✅ Native |

</details>

---

## Installation

**Note:** Version `0.0.8` fixes x86 (32-bit) build compatibility (see issue: https://github.com/muhammad-fiaz/logly.zig/issues/11).

### Method 1: Zig Fetch (Recommended)

The easiest way to add Logly to your project:

```bash
zig fetch --save https://github.com/muhammad-fiaz/logly.zig/archive/refs/tags/0.0.8.tar.gz
```
This automatically adds the dependency with the correct hash to your `build.zig.zon`.

or

For Nightly builds, you can use the Git URL directly:

```bash
zig build --save git+https://github.com/muhammad-fiaz/logly.zig.git

```

This automatically adds the dependency with the correct hash to your `build.zig.zon`.

### Method 2: Project Starter Template (Quick Start)

Get started quickly with a pre-configured project template:

📦 **[Download Project Starter Example](https://download-directory.github.io/?url=https://github.com/muhammad-fiaz/logly.zig/tree/main/project-starter-example
)**

Or clone directly:
```bash
# Download and extract the starter template
curl -L https://github.com/muhammad-fiaz/logly.zig/releases/latest/download/project-starter-example.zip -o logly-starter.zip
unzip logly-starter.zip
cd project-starter-example

# Build and run
zig build run
```

The starter template includes:
- ✅ Pre-configured `build.zig` and `build.zig.zon`
- ✅ Example code demonstrating all major features
- ✅ Multiple sink configurations (console, file, rotation)
- ✅ Context binding and custom log levels
- ✅ JSON logging examples


### Method 3: Manual Configuration

Add to your `build.zig.zon`:

```zig
.dependencies = .{
    .logly = .{
        .url = "https://github.com/muhammad-fiaz/logly.zig/archive/refs/tags/0.0.8.tar.gz",
        .hash = "...", // you needed to add hash here :)
    },
},
```

> **Note:** Run `zig fetch --save <url>` to automatically get the correct hash, or run `zig build` and copy the expected hash from the error message.

Then in your `build.zig`:

```zig
const logly = b.dependency("logly", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("logly", logly.module("logly"));
```

### 📦 Prebuilt Library

While we recommend using the Zig Package Manager, we also provide prebuilt static libraries for each release on the [Releases](https://github.com/muhammad-fiaz/logly.zig/releases) page. These can be useful for integration with other build systems or languages.

- **Windows**: `logly-x86_64-windows.lib`, `logly-x86-windows.lib`
- **Linux**: `liblogly-x86_64-linux.a`, `liblogly-x86-linux.a`, `liblogly-aarch64-linux.a`
- **macOS**: `liblogly-x86_64-macos.a`, `liblogly-aarch64-macos.a`
- **Bare Metal**: `liblogly-x86_64-freestanding.a`, `liblogly-aarch64-freestanding.a`, `liblogly-riscv64-freestanding.a`, `liblogly-arm-freestanding.a`

To use them, link against the static library in your build process.

**Example `build.zig`:**

```zig
// Assuming you downloaded the library to `libs/`
exe.addLibraryPath(b.path("libs"));
exe.linkSystemLibrary("logly");
```

## Quick Start

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Enable ANSI colors (Windows requires explicit enable, Unix-like natively supports)
    _ = logly.Terminal.enableAnsiColors();

    // Create logger (console sink auto-enabled)
    const logger = try logly.Logger.init(allocator);
    defer logger.deinit();

    // Log at different levels - entire line is colored!
    try logger.trace("Detailed trace information", @src());   // Cyan with source location, make sure to enable show_filename/show_lineno in config
    try logger.trace("Detailed trace information", null);   // Cyan with no source location
    try logger.debug("Debug information", @src());            // Blue
    try logger.info("Application started", @src());           // White
    try logger.success("Operation completed!", @src());       // Green
    try logger.warn("Warning message", @src());               // Yellow (alias for .warning())
    try logger.err("Error occurred", @src());                 // Red
    try logger.fail("Operation failed", @src());              // Magenta
    try logger.crit("Critical system error!", @src());        // Bright Red (alias for .critical())
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

// Add file sink using add() alias (same as addSink())
_ = try logger.add(.{
    .path = "logs/app.log",
});

try logger.info("Logging to file!", @src());
try logger.flush(); // Ensure data is written
```

### File Rotation

```zig
// Daily rotation with 7-day retention
_ = try logger.add(.{
    .path = "logs/daily.log",
    .rotation = "daily",
    .retention = 7,
});

// Size-based rotation (10MB limit, keep 5 files)
_ = try logger.add(.{
    .path = "logs/app.log",
    .size_limit = 10 * 1024 * 1024,
    .retention = 5,
});

// Combined: rotate daily OR when 5MB reached
_ = try logger.add(.{
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

try logger.info("JSON formatted log", @src());
// Output: {"timestamp":1701234567890,"level":"INFO","message":"JSON formatted log"}
```

### Context Binding

```zig
// Application-wide context
try logger.bind("app", .{ .string = "myapp" });
try logger.bind("version", .{ .string = "1.0.0" });

try logger.info("Application started", @src());
// All logs include app and version fields

// Request-specific context
try logger.bind("request_id", .{ .string = "req-12345" });
try logger.info("Processing request", @src());
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
try logger.err("Error occurred", @src()); // Callback triggers
```

### Custom Log Levels

```zig
// Add custom level between WARNING (30) and ERROR (40)
try logger.addCustomLevel("NOTICE", 35, "96"); // Cyan color
try logger.addCustomLevel("AUDIT", 25, "35;1"); // Magenta Bold

// Use custom levels - supports all features like standard levels
try logger.custom("NOTICE", "Custom level message", @src());
try logger.custom("AUDIT", "User action recorded", @src());

// Formatted custom level messages
try logger.customf("AUDIT", "User {s} logged in from {s}", .{ "alice", "10.0.0.1" }, @src());

// Custom levels work with JSON output
var config = logly.Config.default();
config.json = true;
logger.configure(config);
try logger.custom("AUDIT", "Appears as level: AUDIT in JSON", @src());

// Custom levels work with file sinks
_ = try logger.add(.{ .path = "logs/audit.log" });
try logger.custom("AUDIT", "Written to file with custom level name", @src());
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

### Distributed Tracing

```zig
// Set trace context for request tracking
try logger.setTraceContext("trace-abc123", "span-001");
try logger.setCorrelationId("request-789");

try logger.info("Processing request", @src());

// Create child spans for nested operations
{
    var span = try logger.startSpan("database-query");
    try logger.info("Executing query", @src());
    try span.end(null);
}

// Clear context
logger.clearTraceContext();
```

### Filtering

```zig
var filter = logly.Filter.init(allocator);
defer filter.deinit();

// Only allow warnings and above
try filter.addMinLevel(.warning);

logger.setFilter(&filter);
```

### Sampling

```zig
// Sample 50% of logs for high-throughput scenarios
var sampler = logly.Sampler.init(allocator, .{ .probability = 0.5 });
defer sampler.deinit();

logger.setSampler(&sampler);
```

### Redaction

```zig
var redactor = logly.Redactor.init(allocator);
defer redactor.deinit();

// Mask passwords in logs
try redactor.addPattern(
    "password",
    .contains,
    "password=",
    "[REDACTED]",
);

logger.setRedactor(&redactor);
try logger.info("User login: password=secret123", @src());
// Output: "User login: [REDACTED]secret123"
```

### Metrics

```zig
const logger = try logly.Logger.init(allocator);
defer logger.deinit();

// Enable metrics collection
logger.enableMetrics();

// Log some messages
try logger.info("Request processed", @src());
try logger.err("Database error", @src());

// Get metrics snapshot
if (logger.getMetrics()) |snapshot| {
    std.debug.print("Total logs: {}\n", .{snapshot.total_records});
    std.debug.print("Errors: {}\n", .{snapshot.error_count});
}
```

### Log-Only and Display-Only Modes

```zig
// Log-only mode (files only, no console output)
const log_config = logly.Config.logOnly();
const log_logger = try logly.Logger.initWithConfig(allocator, log_config);
defer log_logger.deinit();

// Add file sinks manually
_ = try log_logger.addSink(logly.SinkConfig.file("app.log"));
try log_logger.info("This goes to file only", @src());

// Display-only mode (console only, no files)
const display_config = logly.Config.displayOnly();
const display_logger = try logly.Logger.initWithConfig(allocator, display_config);
defer display_logger.deinit();

try display_logger.info("This appears in console only", @src());

// Custom display/storage settings
const custom_config = logly.Config.withDisplayStorage(true, true, true); // console, file, auto_sink
const custom_logger = try logly.Logger.initWithConfig(allocator, custom_config);
defer custom_logger.deinit();

// Silent mode (no output anywhere)
const silent_config = logly.Config.withDisplayStorage(false, false, false);
const silent_logger = try logly.Logger.initWithConfig(allocator, silent_config);
defer silent_logger.deinit();
```

### Production Configuration

```zig
// Use preset configurations
const config = logly.ConfigPresets.production();
logger.configure(config);

// Or customize
var config = logly.Config.production();
config.level = .info;
config.include_hostname = true;
logger.configure(config);
```

## Configuration

```zig
var config = logly.Config.default();

// Global controls
config.global_color_display = true;
config.global_console_display = true;
config.global_file_storage = true;

// Or use convenience presets:
// Log-only mode (no console, only files)
const log_only_config = logly.Config.logOnly();

// Display-only mode (console only, no files)
const display_only_config = logly.Config.displayOnly();

// Custom display/storage settings
const custom_config = logly.Config.withDisplayStorage(true, true, true);

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

### Module Configuration

Configure advanced features like async logging, compression, thread pools, and scheduling:

```zig
var config = logly.Config.default();

// Async logging for non-blocking writes
config.async_config = .{
    .enabled = true,
    .buffer_size = 8192,
    .batch_size = 100,
    .flush_interval_ms = 100,
    .min_flush_interval_ms = 10,
    .max_latency_ms = 5000,
    .overflow_policy = .drop_oldest,
    .background_worker = true,
};

// Compression for log files
config.compression = .{
    .enabled = true,
    .algorithm = .deflate,
    .level = .default,
    .on_rotation = true,
    .keep_original = false,
    .extension = ".gz",
};

// Thread pool for parallel processing
config.thread_pool = .{
    .enabled = true,
    .thread_count = 4,       // 0 = auto-detect CPU cores
    .queue_size = 10000,
    .stack_size = 1024 * 1024,
    .work_stealing = true,
};

// Scheduler for automatic maintenance
config.scheduler = .{
    .enabled = true,
    .cleanup_max_age_days = 7,
    .max_files = 10,
    .compress_before_cleanup = true,
    .file_pattern = "*.log",
};

logger.configure(config);
```

Or use convenient helper methods:

```zig
var config = logly.Config.default()
    .withAsync()
    .withCompression()
    .withThreadPool(4)
    .withScheduler();
```

## Log Levels

| Level    | Priority | Method              | Alias          | Use Case                |
| -------- | -------- | ------------------- | -------------- | ----------------------- |
| TRACE    | 5        | `logger.trace()`    | -              | Very detailed debugging |
| DEBUG    | 10       | `logger.debug()`    | -              | Debugging information   |
| INFO     | 20       | `logger.info()`     | -              | General information     |
| SUCCESS  | 25       | `logger.success()`  | -              | Successful operations   |
| WARNING  | 30       | `logger.warning()`  | `warn()`       | Warning messages        |
| ERROR    | 40       | `logger.err()`      | `error()`      | Error conditions        |
| FAIL     | 45       | `logger.fail()`     | -              | Operation failures      |
| CRITICAL | 50       | `logger.critical()` | `crit()`       | Critical system errors  |

### Sink Management Aliases

| Full Method       | Alias           | Description              |
| ----------------- | --------------- | ------------------------ |
| `addSink()`       | `add()`         | Add a new sink           |
| `removeSink()`    | `remove()`      | Remove a specific sink   |
| `removeAllSinks()`| `removeAll()`, `clear()` | Remove all sinks |
| `getSinkCount()`  | `count()`, `sinkCount()` | Get number of sinks |

## Rotation Intervals

- `minutely` - Rotate every minute
- `hourly` - Rotate every hour
- `daily` - Rotate every day
- `weekly` - Rotate every week
- `monthly` - Rotate every 30 days
- `yearly` - Rotate every 365 days

## Performance & Benchmarks

Logly.Zig is designed for high-performance logging with minimal overhead. Below are benchmark results from running `zig build bench`:

### Benchmark Results

<details>
<summary><strong>Basic Logging</strong></summary>

| Benchmark | Ops/sec (higher is better) | Avg Latency (ns) (lower is better) | Notes |
|-----------|----------------------------|------------------------------------|-------|
| Simple log (no color) | 117,334 | 8,523 | Plain text output |
| Formatted log (no color) | 37,341 | 26,781 | Printf-style formatting |
| Simple log (with color) | 116,864 | 8,557 | ANSI color codes |
| Formatted log (with color) | 34,903 | 28,651 | Colored + formatting |

</details>

<details>
<summary><strong>JSON Logging</strong></summary>

| Benchmark | Ops/sec (higher is better) | Avg Latency (ns) (lower is better) | Notes |
|-----------|----------------------------|------------------------------------|-------|
| JSON compact | 53,149 | 18,815 | Compact JSON output |
| JSON formatted | 30,426 | 32,867 | JSON with formatting |
| JSON pretty | 15,963 | 62,643 | Indented JSON output |
| JSON with color | 29,633 | 33,746 | JSON with ANSI colors |

</details>

<details>
<summary><strong>Log Levels</strong></summary>

| Benchmark | Ops/sec (higher is better) | Avg Latency (ns) (lower is better) | Notes |
|-----------|----------------------------|------------------------------------|-------|
| TRACE level | 54,073 | 18,494 | Lowest priority level |
| DEBUG level | 28,247 | 35,402 | Debug information |
| INFO level | 62,796 | 15,925 | General information |
| SUCCESS level | 45,301 | 22,074 | Success messages |
| WARNING level | 49,987 | 20,005 | Warning messages |
| ERROR level | 48,143 | 20,771 | Error messages |
| FAIL level | 48,729 | 20,522 | Failure messages |
| CRITICAL level | 49,209 | 20,322 | Critical messages |

</details>

<details>
<summary><strong>Custom Features</strong></summary>

| Benchmark | Ops/sec (higher is better) | Avg Latency (ns) (lower is better) | Notes |
|-----------|----------------------------|------------------------------------|-------|
| Custom level (AUDIT) | 56,116 | 17,820 | User-defined log level |
| Custom log format | 56,488 | 17,703 | `{time} \| {level} \| {message}` |
| Custom time format | 52,964 | 18,881 | DD/MM/YYYY HH:mm:ss |
| ISO8601 time format | 47,387 | 21,103 | ISO 8601 standard format |
| Unix timestamp (ms) | 58,943 | 16,966 | Millisecond Unix timestamp |

</details>

<details>
<summary><strong>Configuration Presets</strong></summary>

| Benchmark | Ops/sec (higher is better) | Avg Latency (ns) (lower is better) | Notes |
|-----------|----------------------------|------------------------------------|-------|
| Full metadata config | 57,684 | 17,336 | Time + module + file + line |
| Minimal config | 114,176 | 8,758 | No timestamp or module |
| Production preset | 35,363 | 28,278 | JSON + sampling + metrics |
| Development preset | 52,771 | 18,950 | Debug + source location |
| High throughput preset | 36,483,035 | 27 | Async + thread pool + sampling |
| Secure preset | 54,322 | 18,409 | Redaction enabled |
| Multiple sinks (3) | 62,815 | 15,920 | Text + JSON + Pretty |

</details>

<details>
<summary><strong>Allocator Comparison</strong></summary>

| Benchmark | Ops/sec (higher is better) | Avg Latency (ns) (lower is better) | Notes |
|-----------|----------------------------|------------------------------------|-------|
| Standard allocator (GPA) | 55,929 | 17,880 | Default allocation |
| Standard allocator (formatted) | 32,885 | 30,409 | GPA with formatting |
| Arena allocator | 92,368 | 10,826 | Reduced alloc overhead |
| Arena allocator (formatted) | 34,596 | 28,905 | Arena with formatting |
| Page allocator | 69,599 | 14,368 | System page allocator |

</details>

<details>
<summary><strong>Enterprise Features</strong></summary>

| Benchmark | Ops/sec (higher is better) | Avg Latency (ns) (lower is better) | Notes |
|-----------|----------------------------|------------------------------------|-------|
| With context (3 fields) | 59,076 | 16,927 | Bound context data |
| With trace context | 46,864 | 21,338 | Trace ID + Span ID |
| With metrics enabled | 55,463 | 18,030 | Performance monitoring |
| Structured logging | 38,205 | 26,174 | JSON structured output |

</details>

<details>
<summary><strong>Sampling & Rate Limiting</strong></summary>

| Benchmark | Ops/sec (higher is better) | Avg Latency (ns) (lower is better) | Notes |
|-----------|----------------------------|------------------------------------|-------|
| Sampling (50% probability) | 54,118 | 18,478 | Probability sampling |
| Sampling (rate limit) | 53,695 | 18,624 | Rate-based sampling |
| Sampling (adaptive) | 44,584 | 22,429 | Adaptive sampling |
| Sampling (every-N) | 54,704 | 18,280 | Every-N message sampling |
| Rate limiting (10K/sec) | 44,143 | 22,654 | Max 10K logs per second |
| With redaction enabled | 53,361 | 18,740 | Sensitive data masking |

</details>

<details>
<summary><strong>Filtering</strong></summary>

| Benchmark | Ops/sec (higher is better) | Avg Latency (ns) (lower is better) | Notes |
|-----------|----------------------------|------------------------------------|-------|
| Filter (allowed) | 40,731 | 24,552 | Message passes filter |
| Filter (rejected) | 23,304,591 | 43 | Message blocked by filter |

</details>

<details>
<summary><strong>System Diagnostics</strong></summary>

| Benchmark | Ops/sec (higher is better) | Avg Latency (ns) (lower is better) | Notes |
|-----------|----------------------------|------------------------------------|-------|
| System Diagnostics (basic) | 24,566 | 40,706 | OS/CPU/Mem info |

</details>

<details>
<summary><strong>Multi-Threading</strong></summary>

| Benchmark | Ops/sec (higher is better) | Avg Latency (ns) (lower is better) | Notes |
|-----------|----------------------------|------------------------------------|-------|
| Single thread baseline | 63,592 | 15,725 | 1 thread sequential |
| 2 threads concurrent | 55,268 | 18,094 | 2 threads parallel |
| 4 threads concurrent | 51,211 | 19,527 | 4 threads parallel |
| 8 threads concurrent | 43,571 | 22,951 | 8 threads parallel |
| 16 threads concurrent | 48,274 | 20,715 | 16 threads parallel |
| 4 threads JSON | 37,412 | 26,730 | Parallel JSON logging |
| 4 threads colored | 54,558 | 18,329 | Parallel colored logging |
| 4 threads formatted | 51,787 | 19,310 | Parallel formatted logging |
| 4 threads arena allocator | 51,039 | 19,593 | Parallel with arena alloc |

</details>

<details>
<summary><strong>Performance Comparison</strong></summary>

| Benchmark | Ops/sec (higher is better) | Avg Latency (ns) (lower is better) | Notes |
|-----------|----------------------------|------------------------------------|-------|
| File output (plain) | 83,878 | 11,922 | Null device output |
| File output (error) | 39,494 | 25,321 | Error to file |
| No sampling (baseline) | 62,077 | 16,109 | Sampling disabled |
| Compression enabled (fast) | 43,747 | 22,859 | Deflate compression |

</details>

### Summary

| Metric | Value |
|--------|-------|
| **Total Benchmarks** | 59 |
| **Average Throughput** | ~1,064,399 ops/sec |
| **Maximum Throughput** | 36,483,035 ops/sec (High throughput preset) |
| **Minimum Throughput** | 15,963 ops/sec (JSON pretty) |
| **Average Latency** | ~939 ns |

> **Note:** Benchmark results may vary based on operating system, environment, Zig version, hardware specifications, and software configurations.


### Reproducing the Benchmark Results

To reproduce the benchmark table above locally, run the benchmark executable included with the repository. The benchmark implementation is at [bench/benchmark.zig](bench/benchmark.zig) and is licensed under the repository's `LICENSE` (MIT) in the project root.

Run the benchmark with the following command (Windows and POSIX both supported):

```bash
# Build and run the benchmark (default build output in `zig-out`)
zig build bench

# Or build then run the built executable directly (useful if you pass extra flags to build):
zig build -p zig-out
./zig-out/bin/benchmark       # POSIX
.\zig-out\bin\benchmark.exe # Windows PowerShell
```

Notes:
- The benchmark code uses a null output path (NUL on Windows, /dev/null on POSIX) during tests so console/file I/O does not bottleneck results; you can inspect [bench/benchmark.zig](bench/benchmark.zig) for details and tune `BENCHMARK_ITERATIONS`/`WARMUP_ITERATIONS` to extend runs.
- The printed results include the benchmark name, operations per second, average latency (ns), and a short notes column indicating the operation. Results will vary by OS, Zig version, hardware, and environment.


### Performance Notes

- **JSON logging** is fastest due to simpler string concatenation
- **Color overhead** is minimal (~2-3% performance impact)
- **Formatted logging** (`infof`, `debugf`, etc.) adds ~10% overhead vs simple strings
- **Full metadata** (file, line, function) adds ~15% overhead
- All benchmarks use `ReleaseFast` optimization
- Results measured on Windows with output to NUL device

## Building

```bash
# Run tests
zig build test

# Build examples
zig build example-basic
zig build example-file_logging
zig build example-rotation
zig build example-json_logging
zig build example-json_extended
zig build example-callbacks
zig build example-context
zig build example-advanced_config
zig build example-module_levels
zig build example-sink_formats
zig build example-formatted_logging
zig build example-time
zig build example-custom_colors
zig build example-custom_levels_full
zig build example-dynamic_path
zig build example-customizations
zig build example-sink_write_modes

# Enterprise feature examples
zig build example-filtering
zig build example-sampling
zig build example-redaction
zig build example-metrics
zig build example-tracing
zig build example-color_options
zig build example-production_config
zig build example-diagnostics

# Advanced feature examples
zig build example-compression
zig build example-thread_pool
zig build example-scheduler
zig build example-async_logging
zig build example-async_advanced
zig build example-compression_demo
zig build example-scheduler_demo
zig build example-thread_pool_arena

# Run an example
./zig-out/bin/basic
```

## Documentation

Full documentation is available at: https://muhammad-fiaz.github.io/logly.zig

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
