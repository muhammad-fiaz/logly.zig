<div align="center">
<img src="https://github.com/user-attachments/assets/565fc3dc-dd2c-47a6-bab6-2f545c551f26" alt="logly logo" width="400" />

<a href="https://muhammad-fiaz.github.io/logly.zig/"><img src="https://img.shields.io/badge/docs-muhammad--fiaz.github.io-blue" alt="Documentation"></a>
<a href="https://ziglang.org/"><img src="https://img.shields.io/badge/Zig-0.17.0-orange.svg?logo=zig" alt="Zig Version"></a>
<a href="https://github.com/muhammad-fiaz/logly.zig"><img src="https://img.shields.io/github/stars/muhammad-fiaz/logly.zig" alt="GitHub stars"></a>
<a href="https://github.com/muhammad-fiaz/logly.zig/issues"><img src="https://img.shields.io/github/issues/muhammad-fiaz/logly.zig" alt="GitHub issues"></a>
<a href="https://github.com/muhammad-fiaz/logly.zig/pulls"><img src="https://img.shields.io/github/issues-pr/muhammad-fiaz/logly.zig" alt="GitHub pull requests"></a>
<a href="https://github.com/muhammad-fiaz/logly.zig"><img src="https://img.shields.io/github/last-commit/muhammad-fiaz/logly.zig" alt="GitHub last commit"></a>
<a href="https://github.com/muhammad-fiaz/logly.zig"><img src="https://img.shields.io/github/license/muhammad-fiaz/logly.zig" alt="License"></a>
<a href="https://github.com/muhammad-fiaz/logly.zig/actions/workflows/ci.yml"><img src="https://github.com/muhammad-fiaz/logly.zig/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
<img src="https://img.shields.io/badge/platforms-linux%20%7C%20windows%20%7C%20macos-blue" alt="Supported Platforms">
<a href="https://github.com/muhammad-fiaz/logly.zig/actions/workflows/github-code-scanning/codeql"><img src="https://github.com/muhammad-fiaz/logly.zig/actions/workflows/github-code-scanning/codeql/badge.svg" alt="CodeQL"></a>
<a href="https://github.com/muhammad-fiaz/logly.zig/releases/latest"><img src="https://img.shields.io/github/v/release/muhammad-fiaz/logly.zig?label=Latest%20Release&style=flat-square" alt="Latest Release"></a>
<a href="https://pay.muhammadfiaz.com"><img src="https://img.shields.io/badge/Sponsor-pay.muhammadfiaz.com-ff69b4?style=flat&logo=heart" alt="Sponsor"></a>
<a href="https://github.com/sponsors/muhammad-fiaz"><img src="https://img.shields.io/badge/Sponsor-💖-pink?style=social&logo=github" alt="GitHub Sponsors"></a>
<a href="https://hits.sh/muhammad-fiaz/logly.zig/"><img src="https://hits.sh/muhammad-fiaz/logly.zig.svg?label=Visitors&extraCount=0&color=green" alt="Repo Visitors"></a>

<p><em>A fast, high-performance structured logging library for Zig.</em></p>

<b><a href="https://muhammad-fiaz.github.io/logly.zig/">Documentation</a> |
<a href="https://muhammad-fiaz.github.io/logly.zig/api/logger">API Reference</a> |
<a href="https://muhammad-fiaz.github.io/logly.zig/guide/quick-start">Quick Start</a> |
<a href="CONTRIBUTING.md">Contributing</a></b>

</div>


A production-grade, high-performance structured logging library for Zig, designed with a clean, intuitive, and developer-friendly API.

> [!NOTE]
> This Project aims to be production ready, while it is relatively new project you can find some interesting features which may simplify your zig project logging.

**⭐️ If you love `logly.zig`, make sure to give it a star! ⭐️**

---

<details>
<summary><strong>Table of Contents</strong> (click to expand)</summary>

- [Prerequisites](#prerequisites)
- [Supported Platforms](#supported-platforms)
  - [Color Support](#color-support)
- [Installation](#installation)
  - [Method 1: Zig Fetch (Recommended Stable)](#method-1-zig-fetch-recommended-stable)
  - [Method 2: Manual Configuration](#method-2-manual-configuration)
  - [Method 3: Building from Source](#method-3-building-from-source)
- [Quick Start](#quick-start)
- [Allocator Usage](#allocator-usage)
- [Explicit I/O Architecture](#explicit-io-architecture)
- [Usage Examples](#usage-examples)
  - [File Logging](#file-logging)
  - [File Rotation](#file-rotation)
  - [JSON Logging](#json-logging)
  - [Color Modes](#color-modes)
  - [Context Binding](#context-binding)
  - [Callbacks](#callbacks)
  - [Custom Log Levels](#custom-log-levels)
  - [Multiple Sinks](#multiple-sinks)
  - [Service Identity](#service-identity)
  - [Distributed Tracing](#distributed-tracing)
  - [OpenTelemetry Integration](#opentelemetry-integration)
    - [Basic Telemetry Setup](#basic-telemetry-setup)
    - [W3C Trace Context Propagation](#w3c-trace-context-propagation)
    - [Baggage Context](#baggage-context)
    - [Supported Providers](#supported-providers)
  - [Filtering](#filtering)
  - [Sampling](#sampling)
  - [Redaction](#redaction)
  - [Metrics](#metrics)
  - [Log-Only and Display-Only Modes](#log-only-and-display-only-modes)
  - [Production Configuration](#production-configuration)
- [Configuration](#configuration)
  - [Module Configuration](#module-configuration)
- [Log Levels](#log-levels)
  - [Sink Management Aliases](#sink-management-aliases)
- [Rotation Intervals](#rotation-intervals)
- [Performance \& Benchmarks](#performance--benchmarks)
  - [Benchmark Results](#benchmark-results)
  - [Summary](#summary)
  - [Reproducing the Benchmark Results](#reproducing-the-benchmark-results)
    - [Performance Notes](#performance-notes)
- [Building](#building)
- [Documentation](#documentation)
  - [Online Documentation](#online-documentation)
  - [Generating Local Documentation](#generating-local-documentation)
- [Contributing](#contributing)
- [License](#license)
- [Links](#links)

</details>

----

<details>
<summary><strong>Features of Logly</strong> (click to expand)</summary>

| Feature | Description | Documentation |
|---------|-------------|---------------|
| **Simple & Clean API** | User-friendly logging interface (`logger.info()`, `logger.err()`, etc.) | [Docs](https://muhammad-fiaz.github.io/logly.zig/guide/getting-started) |
| **10 Log Levels** | TRACE, DEBUG, INFO, NOTICE, SUCCESS, WARNING, ERROR, FAIL, CRITICAL, FATAL | [Docs](https://muhammad-fiaz.github.io/logly.zig/guide/log-levels) |
| **Custom Levels** | Define your own log levels with custom priorities and colors | [Docs](https://muhammad-fiaz.github.io/logly.zig/guide/custom-levels) |
| **Multiple Sinks** | Console, file, and custom outputs simultaneously | [Docs](https://muhammad-fiaz.github.io/logly.zig/guide/sinks) |
| **File Rotation** | Time-based (hourly to yearly) and size-based rotation | [Docs](https://muhammad-fiaz.github.io/logly.zig/guide/rotation) |
| **Whole-Line Colors** | ANSI colors wrap entire log lines for better visual scanning | [Docs](https://muhammad-fiaz.github.io/logly.zig/guide/colors) |
| **JSON Logging** | Structured JSON output with valid array format for file storage | [Docs](https://muhammad-fiaz.github.io/logly.zig/guide/json) |
| **Custom Formats** | Customizable log message and timestamp formats | [Docs](https://muhammad-fiaz.github.io/logly.zig/guide/formatting) |
| **Network Logging** | Send logs over TCP/UDP with JSON support and automatic reconnection | [Docs](https://muhammad-fiaz.github.io/logly.zig/guide/network-logging) |
| **Stack Traces** | Automatic stack trace capture for errors and critical logs | [Docs](https://muhammad-fiaz.github.io/logly.zig/guide/stack-traces) |
| **Compression** | Built-in support for GZIP, ZLIB, DEFLATE, ZSTD, and Brotli compression | [Docs](https://muhammad-fiaz.github.io/logly.zig/guide/compression) |
| **Metrics** | Track logger performance, throughput, and error rates | [Docs](https://muhammad-fiaz.github.io/logly.zig/guide/metrics) |

| **Scoped Logging** | Create child loggers with bound context that persists across calls | [Docs](https://muhammad-fiaz.github.io/logly.zig/guide/context) |
| **Redaction** | Automatically mask sensitive data like passwords and API keys | [Docs](https://muhammad-fiaz.github.io/logly.zig/guide/redaction) |

| **Context Binding** | Attach persistent key-value pairs to logs | [Docs](https://muhammad-fiaz.github.io/logly.zig/guide/context) |
| **Async I/O** | Non-blocking writes with configurable buffering | [Docs](https://muhammad-fiaz.github.io/logly.zig/guide/async) |
| **Thread-Safe** | Safe concurrent logging from multiple threads | [Docs](https://muhammad-fiaz.github.io/logly.zig/guide/introduction) |
| **Distributed Logging** | Native distributed tracing with auto-propagation | [Docs](https://muhammad-fiaz.github.io/logly.zig/guide/distributed) |
| **Trace Context** | W3C-compatible Trace ID, Span ID, and Parent ID support | [Docs](https://muhammad-fiaz.github.io/logly.zig/guide/tracing) |
| **Service Identity** | Auto-injection of Service Name, Version, Environment, and Region | [Docs](https://muhammad-fiaz.github.io/logly.zig/guide/distributed) |
| **Baggage Support** | Propagation of custom baggage items across service boundaries | [Docs](https://muhammad-fiaz.github.io/logly.zig/guide/tracing) |
| **Custom Levels** | Define your own log levels with custom priorities and colors | [Docs](https://muhammad-fiaz.github.io/logly.zig/guide/custom-levels) |
| **Module Levels** | Set different log levels for specific modules | [Docs](https://muhammad-fiaz.github.io/logly.zig/guide/filtering) |
| **Formatted Logging** | Printf-style formatting support (`infof`, `debugf`, etc.) | [Docs](https://muhammad-fiaz.github.io/logly.zig/guide/formatting) |
| **Callbacks** | Monitor and react to log events programmatically | [Docs](https://muhammad-fiaz.github.io/logly.zig/guide/callbacks) |
| **Cross-Platform Colors** | Works on Linux, macOS, Windows 10+, and popular terminals | [Docs](https://muhammad-fiaz.github.io/logly.zig/guide/colors) |
| **Filtering** | Rule-based log filtering by level, module, or content | [Docs](https://muhammad-fiaz.github.io/logly.zig/guide/filtering) |
| **Per-Sink Filtering** | Configure filters on each sink in addition to global logger filters | [Docs](https://muhammad-fiaz.github.io/logly.zig/guide/sinks) |
| **Source Location** | Optional clickable `file:line` output via `@src()` when `showFilename`/`showLineno` are enabled | [Docs](https://muhammad-fiaz.github.io/logly.zig/guide/source-location) |
| **Method Aliases** | Convenience aliases for common APIs e.g., `add()` / `remove()` for sink management, `warn()` / `crit()` for logging | [Docs](https://muhammad-fiaz.github.io/logly.zig/guide/introduction) |
| **Sampling** | Control log throughput with probability and rate-limiting | [Docs](https://muhammad-fiaz.github.io/logly.zig/guide/sampling) |
| **Redaction** | Automatic masking of sensitive data (PII, credentials) | [Docs](https://muhammad-fiaz.github.io/logly.zig/guide/redaction) |
| **Metrics** | Built-in observability with log counters and statistics | [Docs](https://muhammad-fiaz.github.io/logly.zig/guide/metrics) |
| **Distributed Tracing** | Trace ID, span ID, and correlation ID support | [Docs](https://muhammad-fiaz.github.io/logly.zig/guide/tracing) |
| **Configuration Presets** | Production, development, high-throughput, and secure presets | [Docs](https://muhammad-fiaz.github.io/logly.zig/guide/configuration) |
| **Async Logger** | Ring buffer-based async logging with background workers | [Docs](https://muhammad-fiaz.github.io/logly.zig/guide/async) |
| **Thread Pool** | Parallel log processing with work stealing | [Docs](https://muhammad-fiaz.github.io/logly.zig/guide/thread-pool) |
| **Scheduler** | Automatic log cleanup, compression, and maintenance | [Docs](https://muhammad-fiaz.github.io/logly.zig/guide/scheduler) |

| **Network Logging** | Send logs via TCP/UDP with JSON support and compression | [Docs](https://muhammad-fiaz.github.io/logly.zig/guide/network-logging) |
| **Custom Themes** | Define custom color themes for log levels | [Docs](https://muhammad-fiaz.github.io/logly.zig/guide/colors) |
| **Advanced Redaction** | Custom patterns and callbacks for sensitive data | [Docs](https://muhammad-fiaz.github.io/logly.zig/guide/redaction) |
| **Persistent Context** | Scoped loggers with persistent fields via `logger.with()` | [Docs](https://muhammad-fiaz.github.io/logly.zig/guide/context) |
| **Advanced Filtering** | Fluent API for complex filter rules | [Docs](https://muhammad-fiaz.github.io/logly.zig/guide/filtering) |
| **Configuration Modes** | Log-only, display-only, and custom display/storage modes | [Docs](https://muhammad-fiaz.github.io/logly.zig/guide/configuration) |
| **Invoke System** | Attach extra messages to logs when conditions match | [Docs](https://muhammad-fiaz.github.io/logly.zig/guide/invoke) |
| **OpenTelemetry** | Full OTEL support with Jaeger, Zipkin, Datadog, GCP, AWS, Azure, and generic collectors | [Docs](https://muhammad-fiaz.github.io/logly.zig/api/telemetry) |
| **Distributed Tracing** | W3C Trace Context propagation with span and trace management | [Docs](https://muhammad-fiaz.github.io/logly.zig/api/telemetry) |
| **Metrics Export** | Export metrics in OTLP, Prometheus, and JSON formats | [Docs](https://muhammad-fiaz.github.io/logly.zig/api/telemetry) |
| **Sampling Strategies** | Multiple sampling strategies for performance optimization | [Docs](https://muhammad-fiaz.github.io/logly.zig/api/telemetry) |
| **Baggage Propagation** | W3C Baggage support for correlation context | [Docs](https://muhammad-fiaz.github.io/logly.zig/api/telemetry) |

</details>

----

<details>
<summary><strong>Prerequisites & Supported Platforms</strong> (click to expand)</summary>

<br>

## Prerequisites

Before installing Logly, ensure you have the following:

| Requirement | Version | Notes |
|-------------|---------|-------|
| **Zig** | 0.17.0+ | Download from [ziglang.org](https://ziglang.org/download/) |
| **Operating System** | Windows 10+, Linux, macOS | Cross-platform support |
| **Terminal** | Any modern terminal | For colored output support |

  > Verify your Zig installation by running `zig version` in your terminal.
  > - For Zig 0.17.0+, use logly.zig version 0.2.2 or newer
  > - For Zig 0.16.x, use logly.zig version 0.2.1
  > - See Zig releases and downloads at [ziglang.org](https://ziglang.org/)

---

## Supported Platforms

Logly.Zig supports a wide range of platforms and architectures:

| Platform | Architectures | Status |
|----------|---------------|--------|
| **Windows** | x86_64, x86 | Full support |
| **Linux** | x86_64, x86, aarch64 | Full support |
| **macOS** | x86_64, aarch64 (Apple Silicon) | Full support |
| **Bare Metal / Freestanding** | x86_64, aarch64, arm, riscv64 | Full support |

---

### Color Support

| Terminal | Platform | Support |
|----------|----------|---------|
| **Windows Terminal** | Windows 10+ | Native ANSI |
| **cmd.exe** | Windows 10+ | Requires `enableAnsiColors()` |
| **iTerm2, Terminal.app** | macOS | Native |
| **GNOME Terminal, Konsole** | Linux | Native |
| **VS Code Terminal** | All | Native |

</details>

---

## Installation


### Method 1: Zig Fetch (Recommended Stable)

The easiest way to add Logly to your project:

  **For Zig 0.17.0+ (use `0.2.2` or newer):**

  ```bash
  zig fetch --save https://github.com/muhammad-fiaz/logly.zig/archive/refs/tags/0.2.2.tar.gz
  ```

  **For Zig 0.16.x (use `0.2.1`):**

  ```bash
  zig fetch --save https://github.com/muhammad-fiaz/logly.zig/archive/refs/tags/0.2.1.tar.gz
  ```

  **For Zig 0.15.0 (use `0.1.7` or earlier):**

  ```bash
  zig fetch --save https://github.com/muhammad-fiaz/logly.zig/archive/refs/tags/0.1.7.tar.gz
  ```

  This automatically adds the dependency with the correct hash to your `build.zig.zon`.

**For Nightly builds:**

```bash
zig fetch --save git+https://github.com/muhammad-fiaz/logly.zig.git
```

This automatically adds the dependency with the correct hash to your `build.zig.zon`.

### Method 2: Manual Configuration

Add to your `build.zig.zon`:

**For Zig 0.17.0+ (use `0.2.2` or newer):**

    ```zig
    .dependencies = .{
        .logly = .{
            .url = "https://github.com/muhammad-fiaz/logly.zig/archive/refs/tags/0.2.2.tar.gz",
            .hash = "...", // you needed to add hash here :)
        },
    },
    ```


> [!NOTE]
> Run `zig fetch --save <url>` to automatically get the correct hash, or run `zig build` and copy the expected hash from the error message.

Then in your `build.zig`:

```zig
const logly = b.dependency("logly", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("logly", logly.module("logly"));
```

> [!NOTE]
> Zig 0.16 keeps `root_module` on the compile step. You only need it to attach the `logly` module when using the package manager. If you link a prebuilt library only, no `root_module` import is required.

### Method 3: Building from Source

Clone the Logly repository and build the library:

```bash
git clone https://github.com/muhammad-fiaz/logly.zig.git
cd logly.zig
zig build
```

**Example `build.zig` (Zig 0.17.0):**

Assuming Logly is included in your project under `libs/logly.zig` and exposes its public module through `src/logly.zig`:

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const logly = b.createModule(.{
        .root_source_file = b.path("libs/logly.zig/src/logly.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "app",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addImport("logly", logly);

    b.installArtifact(exe);
}
```

Import Logly in your application:

```zig
const logly = @import("logly");
```


## Quick Start

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
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
    try logger.notice("Notice message", @src());              // Bright Cyan
    try logger.success("Operation completed!", @src());       // Green
    try logger.warn("Warning message", @src());               // Yellow (alias for .warning())
    try logger.err("Error occurred", @src());                 // Red
    try logger.fail("Operation failed", @src());              // Magenta
    try logger.crit("Critical system error!", @src());        // Bright Red (alias for .critical())
    try logger.fatal("Fatal system failure!", @src());        // White on Red (highest severity)

    // Auto flush is disabled by default; flush to ensure output is written
    try logger.flush();
}
```

> [!NOTE]
> To enable auto-flush globally, set `config.autoFlush = true` or call `logger.enableAutoFlush()`. Auto-flush trades throughput for immediate output.

## Allocator Usage

Logly works with any `std.mem.Allocator` implementation. Pass your own allocator directly — no built-in arena allocation:

```zig
var gpa = std.heap.DebugAllocator(.{}){};
defer _ = gpa.deinit();

const logger = try logly.Logger.initWithConfig(gpa.allocator(), logly.Config.default());
defer logger.deinit();
```

The recommended default in applications is `std.heap.DebugAllocator`. For high-throughput workloads, callers can wrap their allocator with a custom arena and pass it to `Logger.initWithConfig(allocator, config)`.

## Explicit I/O Architecture

Logly 0.2.2 is engineered around the Zig 0.17.0 `std.Io` design:

- **Zero Global Mutable I/O State**: No hidden global I/O state or background mutation.
- **Default Stateless I/O**: `logly.defaultIo()` provides a stateless default `std.Io` instance for synchronous console and file logging out of the box.
- **Explicit I/O Injection**: In concurrent runtimes or custom execution contexts, inject an explicit `std.Io` handle via `config.io = threaded.io()` or constructor functions:

```zig
var threaded = std.Io.Threaded.init(allocator, .{});
defer threaded.deinit();

var config = logly.Config.default();
config.io = threaded.io();

const logger = try logly.Logger.initWithConfig(allocator, config);
defer logger.deinit();

// Alternatively, initialize directly with an explicit I/O handle:
// const logger = try logly.Logger.initWithIo(allocator, threaded.io(), config);
```

- **First-Class Component Injection**: All subsystems support `*initWithIo` constructors for complete runtime control: `Logger.initWithIo`, `AsyncLogger.initWithIo`, `ThreadPool.initWithIo`, `Scheduler.initWithIo`, `Sink.initWithIo`, `NetworkSink.initWithIo`, `Rotation.initWithIo`, and `Telemetry.initWithIo`.

## Usage Examples

> `autoSink` creates the default console sink during logger initialization.
> If you want custom sinks only (file, network, memory, etc.), set `autoSink = false`
> so Logly does not add the console sink automatically.

Other common built-in modes:

- `Config.displayOnly()` for console output only
- `Config.logOnly()` for file storage only
- `Config.withDisplayStorage(console, file, autoSink)` for explicit control
- `SinkConfig.console()`, `SinkConfig.file("app.log")`, `SinkConfig.memory()`, and `SinkConfig.network("tcp://...")` for manual sink setup

### Console-Only Logging

Use this when you want Logly to write only to the console and keep file storage disabled:

`globalConsoleDisplay = true`, `globalFileStorage = false`, `autoSink = true`.

```zig
var config = logly.Config.withDisplayStorage(true, false, true);
config.globalColorDisplay = true;
config.showTime = true;
config.showModule = true;
config.showFunction = false;
config.showFilename = false;
config.showLineno = false;

const logger = try logly.Logger.initWithConfig(allocator, config);
defer logger.deinit();

try logger.info("Console-only message", @src());
try logger.warn("Another console log", @src());
```

### File-Only Logging

Use this when you want Logly to store logs in files and not display console output:

`globalConsoleDisplay = false`, `globalFileStorage = true`, `autoSink = false`.

```zig
var config = logly.Config.logOnly();
config.globalColorDisplay = false;
config.showTime = true;
config.showModule = true;
config.showFunction = true;
config.showFilename = true;
config.showLineno = true;

const logger = try logly.Logger.initWithConfig(allocator, config);
defer logger.deinit();

 _ = try logger.add(.{
    .path = "logs/app.log",
});

try logger.info("File-only message", @src());
try logger.err("This is written to disk", @src());
try logger.flush();
```

### File Logging

```zig
const logger = try logly.Logger.init(allocator);
defer logger.deinit();

// Disable auto console sink
var config = logly.Config.default();
config.autoSink = false;
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
    .sizeLimit = 10 * 1024 * 1024,
    .retention = 5,
});

// Combined: rotate daily OR when 5MB reached
 _ = try logger.add(.{
    .path = "logs/combined.log",
    .rotation = "daily",
    .sizeLimit = 5 * 1024 * 1024,
    .retention = 10,
});
```

### JSON Logging

```zig
var config = logly.Config.default();
config.format = .json;
config.prettyJson = true;
logger.configure(config);

try logger.info("JSON formatted log", @src());
// Output: {"timestamp":1701234567890,"level":"INFO","message":"JSON formatted log"}
```

### Color Modes

All color rendering is delegated to [`tint.zig`](https://github.com/muhammad-fiaz/tint.zig); Logly does not maintain a second ANSI engine. Three modes are available:

| Mode | Behavior |
|------|----------|
| `.none` | Zero ANSI sequences are emitted. |
| `.horizontal` | One color wraps the whole rendered record. |
| `.vertical` | Independent colors per semantic field (timestamp, level, module, message, ...). |

```zig
var config = logly.Config.default();
config.color = true;
config.colorMode = .vertical; // or .horizontal, .none
```

#### Color is a presentation layer, applied per sink

Serialization happens first and stays valid on its own; color is applied
afterwards, around the payload, and only for sinks that ask for it. One sink
never colors another sink's output, and enabling console color never injects
ANSI into a file or network sink.

| Target | Default | Notes |
|--------|---------|-------|
| Console | Auto | Colored when stdout is a TTY; plain when piped, redirected, or in CI. |
| File | Off | Must be enabled explicitly with `color = true`. |
| Network | Off | ANSI is never sent to remote consumers by default. |
| MessagePack | Never | Binary payloads stay byte-exact. |

#### Format support matrix

| Format | No color | Horizontal | Vertical | Custom / level colors |
|--------|:--------:|:----------:|:--------:|:---------------------:|
| `text` | ✓ | ✓ | ✓ | ✓ |
| `logfmt` | ✓ | ✓ | ✓ | ✓ |
| `json` | ✓ | ✓ | ✓ | ✓ |
| `ndjson` | ✓ | ✓ | ✓ | ✓ |
| `syslog` / `syslog3164` | ✓ | ✓ | whole-record | ✓ |
| `msgpack` | ✓ | presentation only | presentation only | presentation only |

For `json`, `ndjson`, and `syslog`, color is applied **around** the serialized
bytes, so the underlying data stays valid: strip ANSI and you recover the exact
JSON/syslog document, including `PRI`, timestamp, and hostname. Vertical mode
re-renders JSON with per-field colors and preserves the same guarantee. A JSON
file sink is a single array document (`[`, records, `]`), so the wrap appears
inside the array.

#### Per-sink configuration

```zig
// Console: text with vertical colors
_ = try logger.addSink(.{
    .name = "console",
    .color = true,
});

// File: plain text, never ANSI
_ = try logger.addSink(.{
    .path = "logs/app.log",
    .color = false,
});

// JSON file kept machine-readable
_ = try logger.addSink(.{
    .path = "logs/app.json",
    .format = .json,
    .color = false,
});
```

#### Async logging

Async mode queues the **uncolored** serialized record together with its resolved
level color. Each sink applies presentation at write time according to its own
configuration, so background workers cannot push console color into files or
network sinks, and ANSI sequences cannot interleave between records.

#### Custom colors and themes

Custom levels and themes flow through the same `tint.zig` pipeline:

```zig
try logger.addCustomLevel("AUDIT", 35, logly.Color.parse("96").?);
try logger.custom("AUDIT", "Custom level message", @src());
```

Named colors, ANSI colors, 256-color, and RGB values are all resolved by
`tint.zig`, which also handles terminal capability detection.

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
try logger.addCustomLevel("NOTICE", 35, logly.Color.parse("96").?); // Cyan color
try logger.addCustomLevel("AUDIT", 25, logly.Color.parse("35").?); // Magenta Bold

// Use custom levels - supports all features like standard levels
try logger.custom("NOTICE", "Custom level message", @src());
try logger.custom("AUDIT", "User action recorded", @src());

// Formatted custom level messages
try logger.customf("AUDIT", "User {s} logged in from {s}", .{ "alice", "10.0.0.1" }, @src());

// Custom levels work with JSON output
var config = logly.Config.default();
config.format = .json;
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

### Service Identity

Configure global service metadata for distributed environments:

```zig
var config = logly.Config.default();
config.distributed = .{
    .enabled = true,
    .serviceName = "payment-service",
    .serviceVersion = "1.2.0",
    .environment = "production",
    .region = "us-west-2",
    .instanceId = "pod-123",
};
logger.configure(config);
// Logs will now include service identity fields automatically
```

### Distributed Tracing

```zig
// Legacy/global context (applies to all subsequent logs)
try logger.setTraceContext("trace-abc123", "span-001");
try logger.setCorrelationId("request-789");
try logger.info("Processing request", @src());

// W3C traceparent -> request-scoped distributed logger
const incoming_traceparent = "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01";
var reqLogger = try logger.withTraceparent(incoming_traceparent);
reqLogger = reqLogger.inModule("http.request");
try reqLogger.info("Request accepted", @src());

// Create child span context for nested operations
const dbLogger = reqLogger.child("7a085853722dc6d2").inModule("database.query");
try dbLogger.debug("Executing query", @src());

// Optional: update global context directly from traceparent
try logger.setTraceContextFromTraceparent(incoming_traceparent);

// Export global context for outbound propagation
if (try logger.getTraceparentHeader(allocator)) |traceparent| {
    defer allocator.free(traceparent);
    // Inject header into HTTP/gRPC metadata: traceparent: {traceparent}
}

// Legacy span helper for nested operations
{
    var span = try logger.startSpan("database-query");
    try logger.info("Executing query", @src());
    try span.end(null);
}

// Clear global context
logger.clearTraceContext();
```

`withTraceparent(...)` and `setTraceContextFromTraceparent(...)` return `LoggerError.InvalidTraceparent` for malformed headers.

### OpenTelemetry Integration

Logly provides comprehensive OpenTelemetry support for distributed tracing, metrics, and context propagation.

#### Basic Telemetry Setup

```zig
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Configure Jaeger backend
    var config = logly.TelemetryConfig.jaeger();
    config.serviceName = "my-service";
    config.serviceVersion = "1.0.0";
    config.environment = "production";

    var telemetry = try logly.Telemetry.init(allocator, config);
    defer telemetry.deinit();

    // Create a span
    var span = try telemetry.startSpan("http_request", .{ .kind = .server });
    defer span.deinit();

    // Ensure span is ended and exported
    defer span.end();
    defer {
        telemetry.endSpan(&span) catch |err| {
            std.debug.print("Failed to export span: {}\n", .{err});
        };
    }

    try span.setAttribute("http.method", .{ .string = "POST" });
    try span.setAttribute("http.status_code", .{ .integer = 200 });

    // Record metrics
    try telemetry.recordCounter("requests.total", 1.0);
    try telemetry.recordGauge("connections.active", 42.0);
    try telemetry.recordHistogram("request.latency_ms", 23.5);
}
```

#### W3C Trace Context Propagation

```zig
// Generate traceparent header for outgoing requests
var span = try telemetry.startSpan("outbound_call", .{});
const traceparent = try telemetry.getTraceparentHeader(&span);
defer allocator.free(traceparent);
// Use: "traceparent: 00-trace_id-span_id-01"

// Parse incoming traceparent header
const incoming = "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01";
if (logly.Telemetry.parseTraceparentHeader(incoming)) |ctx| {
    std.debug.print("Continuing trace: {s}\n", .{ctx.traceId});
}
```

#### Baggage Context

```zig
// Create baggage for cross-service context
var baggage = logly.Baggage.init(allocator);
defer baggage.deinit();

try baggage.set("user.id", "user123");
try baggage.set("tenant.id", "tenant456");

// Convert to HTTP header
const header = try baggage.toHeaderValue(allocator);
defer allocator.free(header);
// header = "user.id=user123,tenant.id=tenant456"
```

#### Supported Providers

| Provider | Configuration |
|----------|---------------|
| **Jaeger** | `TelemetryConfig.jaeger()` |
| **Zipkin** | `TelemetryConfig.zipkin()` |
| **Datadog** | `TelemetryConfig.datadog(apiKey)` |
| **Google Cloud Trace** | `TelemetryConfig.googleCloud(projectId, apiKey)` |
| **Google Analytics 4** | `TelemetryConfig.googleAnalytics(measurementId, apiSecret)` |
| **Google Tag Manager** | `TelemetryConfig.googleTagManager(containerUrl, apiKey)` |
| **AWS X-Ray** | `TelemetryConfig.awsXray(region)` |
| **Azure App Insights** | `TelemetryConfig.azure(connectionString)` |
| **OTEL Collector** | `TelemetryConfig.otelCollector(endpoint)` |
| **File Export** | `TelemetryConfig.file(path)` |

See [Telemetry API Reference](https://muhammad-fiaz.github.io/logly.zig/api/telemetry) for complete documentation.

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
    std.debug.print("Total logs: {}\n", .{snapshot.totalRecords});
    std.debug.print("Errors: {}\n", .{snapshot.errorCount});
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

### Cryptographic Log Chaining (Tamper-Evident Logs)

Ensure absolute audit trail integrity using SHA-256 cryptographic chaining. Each log record contains a hash that includes the signature of the preceding record, making any manual log file modifications instantly detectable.

```zig
var config = logly.Config.default();
config.autoSink = false; // Disable default console output

// Enable tamper-evident cryptographic chaining on a file sink
var fileSink = logly.SinkConfig.file("secure_audit.log");
fileSink.tamperEvident = true; 

const logger = try logly.Logger.initWithConfig(allocator, config);
defer logger.deinit();

 _ = try logger.addSink(fileSink);

try logger.info("Critical action performed", @src());
try logger.flush();
// Output contains standard fields and a cryptographic "SIG:<hash>" signature.
```

### Memory-Mapped Sinks (Extreme Performance)

Map log files directly into RAM via native Win32 or POSIX `mmap` virtual memory mappings. Bypasses standard system call overhead for microsecond-latency disk writes, with automated dynamic resizing/remapping and exact file truncation to the written offset in `deinit`.

```zig
var config = logly.Config.default();
config.autoSink = false;

var sinkCfg = logly.SinkConfig.file("perf.log");
sinkCfg.mmap = true;         // Use memory mapping
sinkCfg.asyncWrite = false; // direct zero-copy write

const logger = try logly.Logger.initWithConfig(allocator, config);
defer logger.deinit();

 _ = try logger.addSink(sinkCfg);

try logger.info("Extremely fast disk log write", @src());
try logger.flush();
```

### Global Panic Hook (Crash Interception)

A robust crash protection hook that automatically captures standard Zig panics, emits crash dumps synchronously to active sinks (bypassing async worker queues to avoid locks/deadlocks), and flushes log buffers reliably before process exit.

Simply export the panic handler in your root source file (e.g., `main.zig`):

```zig
const logly = @import("logly");

// Export the Logly crash handler globally
pub const panic = logly.panic;

pub fn main() !void {
    // Deliberate panic will be cleanly logged, stack traced, and flushed to disk
    @panic("Simulated database connection crash!");
}
```

### Dynamic Configuration Reloading (Zero Downtime)

Reload active log levels, sinks, formats, and rules dynamically from JSON configuration files at runtime without restarts or dropped records.

```zig
// Initialize with default configuration
const logger = try logly.Logger.init(allocator);
defer logger.deinit();

// Reload configuration settings on-the-fly
try logger.reloadFromFile("config.json");
```

### MessagePack Binary Format

Utilize ultra-compact compliance MessagePack binary format to minimize network/disk footprint.

```zig
// MessagePack binary logging
var msgpack_config = logly.Config.default();
msgpack_config.format = .msgpack;

const msgpack_logger = try logly.Logger.initWithConfig(allocator, msgpack_config);
defer msgpack_logger.deinit();
```

### Production Configuration

```zig
// Use preset configurations
const config = logly.ConfigPresets.production();
logger.configure(config);

// Or customize
var config = logly.Config.production();
config.level = .info;
config.includeHostname = true;
logger.configure(config);
```

## Configuration

```zig
var config = logly.Config.default();

// Global controls
config.globalColorDisplay = true;
config.globalConsoleDisplay = true;
config.globalFileStorage = true;

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
config.showTime = true;
config.showModule = true;
config.showFunction = false;
config.showFilename = false;
config.showLineno = false;

// Output format
config.color = true;

// Flush behavior
config.autoFlush = false; // set true for immediate output (lower throughput)

// Features
config.enableCallbacks = true;
config.enableExceptionHandling = true;

logger.configure(config);
```

### Module Configuration

Configure advanced features like async logging, compression, thread pools, and scheduling:

```zig
var config = logly.Config.default();

// Async logging for non-blocking writes
config.asyncConfig = .{
    .enabled = true,
    .bufferSize = 8192,
    .batchSize = 100,
    .flushIntervalMs = 100,
    .minFlushIntervalMs = 10,
    .maxLatencyMs = 5000,
    .overflowPolicy = .dropOldest,
    .backgroundWorker = true,
};

// Compression for log files
config.compression = .{
    .enabled = true,
    .algorithm = .deflate,
    .level = .default,
    .onRotation = true,
    .keepOriginal = false,
    .extension = ".gz",
};

// Thread pool for parallel processing
config.threadPool = .{
    .enabled = true,
    .threadCount = 4,       // 0 = auto-detect CPU cores
    .queueSize = 10000,
    .stackSize = 1024 * 1024,
    .workStealing = true,
};

// Scheduler for automatic maintenance
config.scheduler = .{
    .enabled = true,
    .cleanupMaxAgeDays = 7,
    .maxFiles = 10,
    .compressBeforeCleanup = true,
    .filePattern = "*.log",
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
| NOTICE   | 22       | `logger.notice()`   | `note()`       | Notice messages         |
| SUCCESS  | 25       | `logger.success()`  | -              | Successful operations   |
| WARNING  | 30       | `logger.warning()`  | `warn()`       | Warning messages        |
| ERROR    | 40       | `logger.err()`      | `error()`      | Error conditions        |
| FAIL     | 45       | `logger.fail()`     | `failure()`    | Operation failures      |
| CRITICAL | 50       | `logger.critical()` | `crit()`       | Critical system errors  |
| FATAL    | 55       | `logger.fatal()`    | `panic()`      | Fatal system errors     |

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
| :--- | :--- | :--- | :--- |
| Simple log (no color) | 2409116 | 415 | Plain text output |
| Formatted log (no color) | 25572 | 39105 | Printf-style formatting |
| Disabled log call (TRACE vs INFO min) | 13453518 | 74 | Rejected before formatting |
| Simple log (with color) | 2326718 | 430 | ANSI color codes |
| Formatted log (with color) | 27099 | 36902 | Colored + formatting |
| Horizontal color | 2505826 | 399 | Whole-line level color |
| Vertical color | 2470051 | 405 | Per-column colors |
| No color mode | 2447681 | 409 | colorMode.none |
</details>

<details>
<summary><strong>JSON Logging</strong></summary>

| Benchmark | Ops/sec (higher is better) | Avg Latency (ns) (lower is better) | Notes |
| :--- | :--- | :--- | :--- |
| JSON compact | 2417035 | 414 | Compact JSON output |
| JSON formatted | 28028 | 35679 | JSON with formatting |
| JSON pretty | 45003 | 22221 | Indented JSON output |
| JSON with color | 32333 | 30928 | JSON with ANSI colors |
</details>

<details>
<summary><strong>Log Levels</strong></summary>

| Benchmark | Ops/sec (higher is better) | Avg Latency (ns) (lower is better) | Notes |
| :--- | :--- | :--- | :--- |
| TRACE level | 28415 | 35192 | Lowest priority level |
| DEBUG level | 23214 | 43077 | Debug information |
| INFO level | 26648 | 37527 | General information |
| SUCCESS level | 17228 | 58044 | Success messages |
| WARNING level | 9940 | 100605 | Warning messages |
| ERROR level | 9026 | 110787 | Error messages |
| FAIL level | 9235 | 108288 | Failure messages |
| CRITICAL level | 7110 | 140654 | Critical messages |
</details>

<details>
<summary><strong>Custom Features</strong></summary>

| Benchmark | Ops/sec (higher is better) | Avg Latency (ns) (lower is better) | Notes |
| :--- | :--- | :--- | :--- |
| Custom level (AUDIT) | 7132 | 140219 | User-defined log level |
| Custom log format | 8862 | 112845 | {time} | {level} | {message} |
| Custom time format | 9477 | 105517 | DD/MM/YYYY HH:mm:ss |
| ISO8601 time format | 6736 | 148458 | ISO 8601 standard format |
| Unix timestamp (ms) | 8197 | 121989 | Millisecond Unix timestamp |
</details>

<details>
<summary><strong>Configuration Presets</strong></summary>

| Benchmark | Ops/sec (higher is better) | Avg Latency (ns) (lower is better) | Notes |
| :--- | :--- | :--- | :--- |
| Full metadata config | 6492 | 154026 | Time + module + file + line |
| Minimal config | 13611 | 73471 | No timestamp or module |
| Production preset | 4031 | 248106 | JSON + sampling + metrics |
| Development preset | 6248 | 160040 | Debug + source location |
| High throughput preset | 10324179 | 97 | Async + thread pool + sampling |
| Secure preset | 5573 | 179449 | Redaction enabled |
| Multiple sinks (3) | 5539 | 180547 | Text + JSON + Pretty |
</details>

<details>
<summary><strong>Allocator Comparison</strong></summary>

| Benchmark | Ops/sec (higher is better) | Avg Latency (ns) (lower is better) | Notes |
| :--- | :--- | :--- | :--- |
| Standard allocator (GPA) | 134978 | 7409 | Default allocation |
| Standard allocator (formatted) | 17570 | 56916 | GPA with formatting |
| Page allocator | 147571 | 6776 | System page allocator |
</details>

<details>
<summary><strong>Enterprise Features</strong></summary>

| Benchmark | Ops/sec (higher is better) | Avg Latency (ns) (lower is better) | Notes |
| :--- | :--- | :--- | :--- |
| With context (3 fields) | 5327 | 187734 | Bound context data |
| With trace context | 5074 | 197088 | Trace ID + Span ID |
| With metrics enabled | 5241 | 190803 | Performance monitoring |
| Structured logging | 3014 | 331734 | JSON structured output |
</details>

<details>
<summary><strong>Sampling & Rate Limiting</strong></summary>

| Benchmark | Ops/sec (higher is better) | Avg Latency (ns) (lower is better) | Notes |
| :--- | :--- | :--- | :--- |
| Sampling (50% probability) | 118469 | 8441 | Probability sampling |
| Sampling (rate limit) | 124983 | 8001 | Rate-based sampling |
| Sampling (adaptive) | 141868 | 7049 | Adaptive sampling |
| Sampling (every-N) | 169251 | 5908 | Every-N message sampling |
| Rate limiting (10K/sec) | 165755 | 6033 | Max 10K logs per second |
| With redaction enabled | 138768 | 7206 | Sensitive data masking |
</details>

<details>
<summary><strong>Filtering</strong></summary>

| Benchmark | Ops/sec (higher is better) | Avg Latency (ns) (lower is better) | Notes |
| :--- | :--- | :--- | :--- |
| Filter (allowed) | 115302 | 8673 | Message passes filter |
| Filter (rejected) | 10161569 | 98 | Message blocked by filter |
</details>

<details>
<summary><strong>Rules Engine</strong></summary>

| Benchmark | Ops/sec (higher is better) | Avg Latency (ns) (lower is better) | Notes |
| :--- | :--- | :--- | :--- |
| Rules engine (enabled) | 135219 | 7395 | Rule evaluation |
| Rules engine (disabled) | 164190 | 6091 | No rule evaluation |
</details>

<details>
<summary><strong>Redaction</strong></summary>

| Benchmark | Ops/sec (higher is better) | Avg Latency (ns) (lower is better) | Notes |
| :--- | :--- | :--- | :--- |
| Redaction (pattern match) | 26514 | 37716 | 2 patterns matched |
| Redaction (no match) | 62255 | 16063 | No patterns matched |
| Field redaction (full) | 95242 | 10500 | Full field masking |
</details>

<details>
<summary><strong>Metrics</strong></summary>

| Benchmark | Ops/sec (higher is better) | Avg Latency (ns) (lower is better) | Notes |
| :--- | :--- | :--- | :--- |
| Metrics recordLog | 4256949 | 235 | Atomic counter update |
| Metrics with latency | 5201290 | 192 | With latency tracking |
| Metrics snapshot | 3181572 | 314 | Get current snapshot |
| Metrics (full config) | 4188306 | 239 | All tracking enabled |
</details>

<details>
<summary><strong>Rotation</strong></summary>

| Benchmark | Ops/sec (higher is better) | Avg Latency (ns) (lower is better) | Notes |
| :--- | :--- | :--- | :--- |
| Rotation (size check) | 141500 | 7067 | Size-based check |
</details>

<details>
<summary><strong>Multi-Threading</strong></summary>

| Benchmark | Ops/sec (higher is better) | Avg Latency (ns) (lower is better) | Notes |
| :--- | :--- | :--- | :--- |
| Single thread baseline | 151627 | 6595 | 1 thread sequential |
| 2 threads concurrent | 96890 | 10321 | 2 threads parallel |
| 4 threads concurrent | 87071 | 11485 | 4 threads parallel |
| 8 threads concurrent | 86289 | 11589 | 8 threads parallel |
| 16 threads concurrent | 86899 | 11508 | 16 threads parallel |
| 4 threads JSON | 85975 | 11631 | Parallel JSON logging |
| 4 threads colored | 87225 | 11465 | Parallel colored logging |
| 4 threads formatted | 57546 | 17377 | Parallel formatted logging |
</details>

<details>
<summary><strong>Performance Comparison</strong></summary>

| Benchmark | Ops/sec (higher is better) | Avg Latency (ns) (lower is better) | Notes |
| :--- | :--- | :--- | :--- |
| File output (plain) | 173092 | 5777 | Null device output |
| File output (error) | 185232 | 5399 | Error to file |
| No sampling (baseline) | 190454 | 5251 | Sampling disabled |
| Compression enabled (fast) | 186826 | 5353 | Deflate compression |
</details>

### Summary

| Metric | Value |
|--------|-------|
| **Total Benchmarks** | 69 |
| **Average Throughput** | ~1,001,562 ops/sec |
| **Maximum Throughput** | 13,453,518 ops/sec (Disabled log call) |
| **Minimum Throughput** | 3,014 ops/sec (Structured logging) |
| **Average Latency** | ~998 ns |

> [!NOTE]
> Benchmark results may vary based on operating system, environment, Zig version, hardware specifications, and software configurations.


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

> [!NOTE]
> The benchmark code uses a null output path (NUL on Windows, /dev/null on POSIX) during tests so console/file I/O does not bottleneck results; you can inspect [bench/benchmark.zig](bench/benchmark.zig) for details and tune `BENCHMARK_ITERATIONS`/`WARMUP_ITERATIONS` to extend runs.
> The printed results include the benchmark name, operations per second, average latency (ns), and a short notes column indicating the operation. Results will vary by OS, Zig version, hardware, and environment.
> for each latest release benchmark can be found in each [releases page](https://github.com/muhammad-fiaz/logly.zig/releases).


#### Performance Notes

> [!NOTE]
> - **JSON logging** is fastest due to simpler string concatenation
> - **Color overhead** is minimal (~2-3% performance impact)
> - **Formatted logging** (`infof`, `debugf`, etc.) adds ~10% overhead vs simple strings
> - **Full metadata** (file, line, function) adds ~15% overhead
> - All benchmarks use `ReleaseFast` optimization
> - Results measured on Windows with output to NUL device

## Building

```bash
# Run tests
zig build test

# Run only tests whose name contains a substring
zig build test -Dtest-filter="rotation"

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
zig build example-append_overwrite

# Enterprise feature examples
zig build example-filtering
zig build example-sampling
zig build example-redaction
zig build example-metrics
zig build example-tracing
zig build example-color_options
zig build example-color_modes
zig build example-production_config

# Advanced feature examples
zig build example-compression
zig build example-thread_pool
zig build example-scheduler
zig build example-async_logging
zig build example-async_advanced
zig build example-compression_demo

# Run every example sequentially
zig build run-all-examples

# Run one example (built to zig-out/bin)
zig build run-basic

# Run an example
./zig-out/bin/basic
```

## Documentation

### Online Documentation
Full documentation is available at: https://muhammad-fiaz.github.io/logly.zig

### Generating Local Documentation
To generate documentation locally:

```bash
zig build docs
```

This will generate HTML documentation in the `zig-out/docs/` directory. Open `zig-out/docs/index.html` in your browser to view the documentation.

>[!NOTE]
> For projects using Zig 0.15, you can also generate the local documentation with `zig build docs` while using the matching `logly.zig` release (`0.1.7` or earlier).

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
