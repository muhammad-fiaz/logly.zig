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
<a href="https://pay.muhammadfiaz.com"><img src="https://img.shields.io/badge/Sponsor-pay.muhammadfiaz.com-ff69b4?style=flat&logo=heart" alt="Sponsor"></a>
<a href="https://github.com/sponsors/muhammad-fiaz"><img src="https://img.shields.io/github/sponsors/muhammad-fiaz?style=social&logo=github" alt="GitHub Sponsors"></a>

<p><em>High-performance, structured logging library for Zig.</em></p>

**📚 [Documentation](https://muhammad-fiaz.github.io/logly.zig/) | [API Reference](https://muhammad-fiaz.github.io/logly.zig/api/logger) | [Quick Start](https://muhammad-fiaz.github.io/logly.zig/guide/quick-start) | [Contributing](CONTRIBUTING.md)**

</div>

A production-grade, high-performance structured logging library for Zig, designed with a clean, intuitive, and developer-friendly API.

<details>
<summary><strong>✨ Features of Logly</strong> (click to expand)</summary>

| Feature | Description |
|---------|-------------|
| ✨ **Simple & Clean API** | Python-like logging interface (`logger.info()`, `logger.err()`, etc.) |
| 🎯 **8 Log Levels** | TRACE, DEBUG, INFO, SUCCESS, WARNING, ERROR, FAIL, CRITICAL |
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
| 📉 **Sampling** | Control log throughput with probability and rate-limiting |
| 🔐 **Redaction** | Automatic masking of sensitive data (PII, credentials) |
| 📈 **Metrics** | Built-in observability with log counters and statistics |
| 🔗 **Distributed Tracing** | Trace ID, span ID, and correlation ID support |
| ⚙️ **Configuration Presets** | Production, development, high-throughput, and secure presets |

</details>

## Installation

### Method 1: Zig Fetch (Recommended)

The easiest way to add Logly to your project:

```bash
zig fetch --save https://github.com/muhammad-fiaz/logly.zig/archive/refs/tags/v0.0.3.tar.gz
```

This automatically adds the dependency with the correct hash to your `build.zig.zon`.

### Method 2: Manual Configuration

Add to your `build.zig.zon`:

```zig
.dependencies = .{
    .logly = .{
        .url = "https://github.com/muhammad-fiaz/logly.zig/archive/refs/tags/v0.0.3.tar.gz",
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

    // Enable ANSI colors on Windows (no-op on Linux/macOS)
    _ = logly.Terminal.enableAnsiColors();

    // Create logger (console sink auto-enabled)
    const logger = try logly.Logger.init(allocator);
    defer logger.deinit();

    // Log at different levels - entire line is colored!
    try logger.trace("Detailed trace information");   // Cyan
    try logger.debug("Debug information");            // Blue
    try logger.info("Application started");           // White
    try logger.success("Operation completed!");       // Green
    try logger.warning("Warning message");            // Yellow
    try logger.err("Error occurred");                 // Red
    try logger.fail("Operation failed");              // Magenta
    try logger.critical("Critical system error!");    // Bright Red
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
try logger.addCustomLevel("AUDIT", 25, "35;1"); // Magenta Bold

// Use custom levels - supports all features like standard levels
try logger.custom("NOTICE", "Custom level message");
try logger.custom("AUDIT", "User action recorded");

// Formatted custom level messages
try logger.customf("AUDIT", "User {s} logged in from {s}", .{ "alice", "10.0.0.1" });

// Custom levels work with JSON output
var config = logly.Config.default();
config.json = true;
logger.configure(config);
try logger.custom("AUDIT", "Appears as level: AUDIT in JSON");

// Custom levels work with file sinks
_ = try logger.addSink(.{ .path = "logs/audit.log" });
try logger.custom("AUDIT", "Written to file with custom level name");
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

try logger.info("Processing request");

// Create child spans for nested operations
{
    var span = try logger.startSpan("database-query");
    try logger.info("Executing query");
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
try logger.info("User login: password=secret123");
// Output: "User login: [REDACTED]secret123"
```

### Metrics

```zig
const logger = try logly.Logger.init(allocator);
defer logger.deinit();

// Enable metrics collection
logger.enableMetrics();

// Log some messages
try logger.info("Request processed");
try logger.err("Database error");

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

## Performance & Benchmarks

Logly.Zig is designed for high-performance logging with minimal overhead. Below are benchmark results from running `zig build bench`:

### Benchmark Results

| Benchmark | Ops/sec | Avg Latency (ns) | Notes |
|-----------|---------|------------------|-------|
| Console (no color) - info | 14,554 | 68,711 | Plain text, no ANSI codes |
| Console (no color) - formatted | 12,752 | 78,421 | Printf-style formatting |
| Console (with color) - info | 14,913 | 67,055 | ANSI color wrapping |
| Console (with color) - formatted | 13,374 | 74,775 | Colored + formatting |
| JSON (no color) - info | 19,620 | 50,969 | Compact JSON output |
| JSON (no color) - formatted | 13,852 | 72,193 | JSON with formatting |
| JSON (with color) - info | 18,549 | 53,911 | JSON with ANSI colors |
| JSON (with color) - error | 18,154 | 55,084 | JSON colored error |
| Pretty JSON - info | 13,403 | 74,610 | Indented JSON output |
| Custom format - info | 15,820 | 63,212 | `{time} \| {level} \| {message}` |
| Level: TRACE | 20,154 | 49,619 | Trace level messages |
| Level: DEBUG | 20,459 | 48,879 | Debug level messages |
| Level: INFO | 14,984 | 66,737 | Info level messages |
| Level: SUCCESS | 20,825 | 48,019 | Success level messages |
| Level: WARNING | 20,192 | 49,524 | Warning level messages |
| Level: ERROR | 20,906 | 47,832 | Error level messages |
| Level: FAIL | 14,935 | 66,957 | Fail level messages |
| Level: CRITICAL | 20,570 | 48,615 | Critical level messages |
| Level (color): TRACE | 11,120 | 89,929 | Colored trace messages |
| Level (color): DEBUG | 19,905 | 50,238 | Colored debug messages |
| Level (color): INFO | 14,488 | 69,024 | Colored info messages |
| Level (color): SUCCESS | 18,049 | 55,404 | Colored success messages |
| Level (color): WARNING | 19,454 | 51,404 | Colored warning messages |
| Level (color): ERROR | 18,726 | 53,402 | Colored error messages |
| Level (color): FAIL | 18,700 | 53,476 | Colored fail messages |
| Level (color): CRITICAL | 18,199 | 54,949 | Colored critical messages |
| Custom Level: AUDIT | 16,018 | 62,429 | User-defined log level |
| Custom Level (color): AUDIT | 18,164 | 55,055 | Colored custom level |
| File (no color) - info | 16,245 | 61,557 | Plain file output |
| File (no color) - error | 19,433 | 51,459 | Plain file error output |
| File (with color) - info | 15,025 | 66,554 | File with ANSI codes |
| File (with color) - error | 18,266 | 54,747 | File colored error |
| Full metadata - info | 15,769 | 63,415 | Time + module + file + line |
| Minimal config - info | 16,916 | 59,116 | No timestamp or module |
| Production config - info | 18,909 | 52,885 | JSON with optimizations |
| Multiple sinks (3) - info | 12,968 | 77,114 | Console + JSON + Pretty |

**Average Throughput: ~17,000 ops/sec**

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
| Sampling       | - (Coming soon!)                      | - (Coming soon!)           | ✓ (v0.0.3+)           |
| Redaction      | - (Coming soon!)             | - (Coming soon!)             | ✓ (v0.0.3+)           |
| Metrics        | - (Coming soon!)           | - (Coming soon!)            | ✓ (v0.0.3+)           |
| Tracing        | - (Coming soon!)           | - (Coming soon!)            | ✓ (v0.0.3+)           |

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
