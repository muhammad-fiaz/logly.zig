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

### Method 1: Zig Fetch (Recommended)

The easiest way to add Logly to your project:

```bash
zig fetch --save https://github.com/muhammad-fiaz/logly.zig/archive/refs/tags/v0.0.5.tar.gz
```

This automatically adds the dependency with the correct hash to your `build.zig.zon`.

### Method 2: Project Starter Template (Quick Start)

Get started quickly with a pre-configured project template:

📦 **[Download Project Starter Example](https://github.com/muhammad-fiaz/logly.zig/releases/latest/download/project-starter-example.zip)**

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

### Update Checker

- Runs in a detached background thread so startup stays fast.
- If your local version is older than the latest release, you will see: "A newer logly.zig release is available".
- If your local build is ahead of the latest release (e.g., dev/nightly), you will see: "Running a dev/nightly build ahead of latest release".

### System Diagnostics Logging

- Enable automatic startup emission via `emit_system_diagnostics_on_init = true` (config) or call `try logger.logSystemDiagnostics(@src());` manually.
- Captures OS, architecture, CPU model, logical cores, RAM totals/available, and (on Windows) per-drive storage totals/frees.
- Respects existing sinks and formatting (text/JSON/async/thread pool) so diagnostics land where your logs already go.
- Toggle drive enumeration with `include_drive_diagnostics`.

### Method 3: Manual Configuration

Add to your `build.zig.zon`:

```zig
.dependencies = .{
    .logly = .{
        .url = "https://github.com/muhammad-fiaz/logly.zig/archive/refs/tags/v0.0.4.tar.gz",
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
    try logger.trace("Detailed trace information", @src());   // Cyan
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
    .overflow_policy = .drop_oldest,
    .auto_start = true,
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

| Benchmark | Ops/sec | Avg Latency (ns) | Notes |
|-----------|---------|------------------|-------|
| Simple log (no color) | 15,557 | 64,280 | Plain text output |
| Formatted log (no color) | 15,083 | 66,300 | Printf-style formatting |
| Simple log (with color) | 15,744 | 63,515 | ANSI color codes |
| Formatted log (with color) | 14,428 | 69,311 | Colored + formatting |

</details>

<details>
<summary><strong>JSON Logging</strong></summary>

| Benchmark | Ops/sec | Avg Latency (ns) | Notes |
|-----------|---------|------------------|-------|
| JSON compact | 19,705 | 50,748 | Compact JSON output |
| JSON formatted | 13,654 | 73,239 | JSON with formatting |
| JSON pretty | 14,879 | 67,209 | Indented JSON output |
| JSON with color | 19,929 | 50,179 | JSON with ANSI colors |

</details>

<details>
<summary><strong>Log Levels</strong></summary>

| Benchmark | Ops/sec | Avg Latency (ns) | Notes |
|-----------|---------|------------------|-------|
| TRACE level | 19,460 | 51,387 | Lowest priority level |
| DEBUG level | 20,867 | 47,922 | Debug information |
| INFO level | 16,436 | 60,844 | General information |
| SUCCESS level | 20,706 | 48,296 | Success messages |
| WARNING level | 19,587 | 51,054 | Warning messages |
| ERROR level | 20,513 | 48,750 | Error messages |
| FAIL level | 16,222 | 61,645 | Failure messages |
| CRITICAL level | 19,574 | 51,087 | Critical messages |

</details>

<details>
<summary><strong>Custom Features</strong></summary>

| Benchmark | Ops/sec | Avg Latency (ns) | Notes |
|-----------|---------|------------------|-------|
| Custom level (AUDIT) | 16,592 | 60,269 | User-defined log level |
| Custom log format | 16,136 | 61,975 | `{time} \| {level} \| {message}` |
| Custom time format | 15,432 | 64,801 | DD/MM/YYYY HH:mm:ss |
| ISO8601 time format | 14,644 | 68,287 | ISO 8601 standard format |
| Unix timestamp (ms) | 15,922 | 62,806 | Millisecond Unix timestamp |

</details>

<details>
<summary><strong>Configuration Presets</strong></summary>

| Benchmark | Ops/sec | Avg Latency (ns) | Notes |
|-----------|---------|------------------|-------|
| Full metadata config | 15,798 | 63,301 | Time + module + file + line |
| Minimal config | 16,536 | 60,474 | No timestamp or module |
| Production preset | 18,204 | 54,934 | JSON + sampling + metrics |
| Development preset | 15,807 | 63,263 | Debug + source location |
| High throughput preset | 26,364,355 | 38 | Async + thread pool + sampling |
| Secure preset | 15,643 | 63,927 | Redaction enabled |
| Multiple sinks (3) | 13,221 | 75,635 | Text + JSON + Pretty |

</details>

<details>
<summary><strong>Allocator Comparison</strong></summary>

| Benchmark | Ops/sec | Avg Latency (ns) | Notes |
|-----------|---------|------------------|-------|
| Standard allocator (GPA) | 15,274 | 65,469 | Default allocation |
| Standard allocator (formatted) | 14,085 | 70,996 | GPA with formatting |
| Arena allocator | 15,731 | 63,568 | Reduced alloc overhead |
| Arena allocator (formatted) | 13,344 | 74,940 | Arena with formatting |
| Page allocator | 20,907 | 47,830 | System page allocator |

</details>

<details>
<summary><strong>Enterprise Features</strong></summary>

| Benchmark | Ops/sec | Avg Latency (ns) | Notes |
|-----------|---------|------------------|-------|
| With context (3 fields) | 14,338 | 69,743 | Bound context data |
| With trace context | 15,201 | 65,786 | Trace ID + Span ID |
| With metrics enabled | 15,932 | 62,765 | Performance monitoring |
| Structured logging | 19,372 | 51,621 | JSON structured output |

</details>

<details>
<summary><strong>Sampling & Rate Limiting</strong></summary>

| Benchmark | Ops/sec | Avg Latency (ns) | Notes |
|-----------|---------|------------------|-------|
| Sampling (50% probability) | 15,325 | 65,253 | Probability sampling |
| Sampling (rate limit) | 16,597 | 60,253 | Rate-based sampling |
| Sampling (adaptive) | 16,231 | 61,609 | Adaptive sampling |
| Sampling (every-N) | 16,235 | 61,595 | Every-N message sampling |
| Rate limiting (10K/sec) | 14,951 | 66,883 | Max 10K logs per second |
| With redaction enabled | 15,834 | 63,156 | Sensitive data masking |

</details>

<details>
<summary><strong>Multi-Threading</strong></summary>

| Benchmark | Ops/sec | Avg Latency (ns) | Notes |
|-----------|---------|------------------|-------|
| Single thread baseline | 18,151 | 55,094 | 1 thread sequential |
| 2 threads concurrent | 16,896 | 59,186 | 2 threads parallel |
| 4 threads concurrent | 16,275 | 61,443 | 4 threads parallel |
| 8 threads concurrent | 16,122 | 62,026 | 8 threads parallel |
| 16 threads concurrent | 15,816 | 63,227 | 16 threads parallel |
| 4 threads JSON | 17,967 | 55,659 | Parallel JSON logging |
| 4 threads colored | 16,880 | 59,243 | Parallel colored logging |
| 4 threads formatted | 13,402 | 74,618 | Parallel formatted logging |
| 4 threads arena allocator | 16,684 | 59,938 | Parallel with arena alloc |

</details>

<details>
<summary><strong>Performance Comparison</strong></summary>

| Benchmark | Ops/sec | Avg Latency (ns) | Notes |
|-----------|---------|------------------|-------|
| File output (plain) | 16,413 | 60,926 | Null device output |
| File output (error) | 20,503 | 48,773 | Error to file |
| No sampling (baseline) | 15,816 | 63,228 | Sampling disabled |
| Compression enabled (fast) | 15,881 | 62,968 | Deflate compression |

</details>

### Summary

| Metric | Value |
|--------|-------|
| **Total Benchmarks** | 56 |
| **Average Throughput** | ~487,000 ops/sec |
| **Maximum Throughput** | 26,364,355 ops/sec (High throughput preset) |
| **Minimum Throughput** | 13,221 ops/sec (Multiple sinks) |
| **Average Latency** | ~2 μs |

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
zig build example-callbacks
zig build example-context
zig build example-advanced_config
zig build example-module_levels
zig build example-sink_formats
zig build example-formatted_logging

# Enterprise feature examples
zig build example-filtering
zig build example-sampling
zig build example-redaction
zig build example-metrics
zig build example-tracing
zig build example-color_options
zig build example-production_config

# Advanced feature examples
zig build example-compression
zig build example-thread_pool
zig build example-scheduler
zig build example-async_advanced

# Run an example
./zig-out/bin/basic
```

## Documentation

Full documentation is available at: https://muhammad-fiaz.github.io/logly.zig

## Comparison with Logly Other Variants

| Feature        | Python Logly            | Rust Logly           | Logly-Zig             |
| -------------- | ----------------------- | -------------------- | --------------------- |
| Performance    | Maturin-Bindings (Fast) | Native Rust (Faster) | Native Zig (Fastest)  |
| Memory Safety  | Runtime                 | Compile-time         | Compile-time          |
| Async Support  | ✓                       | ✓                    | ✓                     |
| File Rotation  | ✓                       | ✓                    | ✓                     |
| JSON Logging   | ✓                       | ✓                    | ✓                     |
| Custom Colors  | ✓                       | ✓                    | ✓                     |
| Simplified API | ✓                       | ✓                    | ✓                     |
| Filtering      | ✓                       | ✓                    | ✓ (v0.0.3+)           |
| Sampling       | - (Coming soon!)        | - (Coming soon!)     | ✓ (v0.0.3+)           |
| Redaction      | - (Coming soon!)        | - (Coming soon!)     | ✓ (v0.0.3+)           |
| Metrics        | - (Coming soon!)        | - (Coming soon!)     | ✓ (v0.0.3+)           |
| Tracing        | - (Coming soon!)        | - (Coming soon!)     | ✓ (v0.0.3+)           |
| Compression    | - (Coming soon!)        | - (Coming soon!)     | ✓ (v0.0.4+)           |
| Thread Pool    | - (Coming soon!)        | - (Coming soon!)     | ✓ (v0.0.4+)           |
| Scheduler      | - (Coming soon!)        | - (Coming soon!)     | ✓ (v0.0.4+)           |
| Async Logger   | - (Coming soon!)        | - (Coming soon!)     | ✓ (v0.0.4+)           |
| Custom Formats | ✓          | ✓                    | ✓ (v0.0.4+)           |

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
