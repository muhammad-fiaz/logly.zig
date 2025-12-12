---
layout: home

hero:
  name: Logly.Zig
  text: High-Performance Logging for Zig
  tagline: Production-ready structured logging with a clean, simple API
  image:
    src: /logo.png
    alt: Logly.Zig
  actions:
    - theme: brand
      text: Get Started
      link: /guide/getting-started
    - theme: alt
      text: View on GitHub
      link: https://github.com/muhammad-fiaz/logly.zig

features:
  - icon: ⚡
    title: Blazing Fast
    details: Native Zig performance with async I/O and zero-copy operations

  - icon: 🎯
    title: Simple API
    details: Python-like logging interface - logger.info(), logger.error(), etc.

  - icon: 🔄
    title: File Rotation
    details: Time-based and size-based rotation with automatic cleanup

  - icon: 📊
    title: JSON Logging
    details: Structured JSON output for log aggregation and analysis

  - icon: 🎨
    title: Whole-Line Colors
    details: ANSI colors wrap entire log lines for better visual scanning on all platforms

  - icon: 🔗
    title: Context Binding
    details: Attach persistent key-value pairs to all logs

  - icon: 🔒
    title: Thread-Safe
    details: Safe concurrent logging with mutex protection

  - icon: 📁
    title: Multiple Sinks
    details: Log to console, files, or custom destinations simultaneously

  - icon: 🌐
    title: Network Logging
    details: Send logs over TCP/UDP with JSON support and automatic reconnection

  - icon: 🎭
    title: Custom Themes
    details: Fully customizable color themes for different log levels

  - icon: 🎭
    title: Custom Levels
    details: Define your own log levels with custom priorities and colors

  - icon: 🩺
    title: System Diagnostics
    details: Emit OS/CPU/memory (and drives) on startup or on-demand for quick host visibility

  - icon: 🛡️
    title: Redaction
    details: Automatically mask sensitive data like passwords and API keys

  - icon: 🔍
    title: Scoped Logging
    details: Create child loggers with bound context that persists across calls

  - icon: 🔄
    title: Update Checker
    details: Automatically check for new versions of Logly

  - icon: 🐛
    title: Stack Traces
    details: Automatic stack trace capture for errors and critical logs

  - icon: 📦
    title: Compression
    details: Built-in support for GZIP, ZLIB, and DEFLATE compression

  - icon: 📈
    title: Metrics
    details: Track logger performance, throughput, and error rates
---

## Quick Example

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    // Enable ANSI colors on Windows (no-op on Linux/macOS)
    _ = logly.Terminal.enableAnsiColors();

    const logger = try logly.Logger.init(gpa.allocator());
    defer logger.deinit();

    // Each level colors the ENTIRE line (timestamp, level, message)
    // @src() is optional - enables file:line display when show_filename/show_lineno are true
    try logger.info(@src(), "Application started", .{});      // White line
    try logger.success(@src(), "Operation completed!", .{});  // Green line
    try logger.warn(@src(), "Low memory", .{});               // Yellow line (alias for warning)
    try logger.err(@src(), "Connection failed", .{});         // Red line
}
```

## Why Logly-Zig?

- **Production Ready**: Battle-tested features from Rust Logly, reimplemented in Zig
- **Zero Dependencies**: Pure Zig implementation with no external dependencies
- **Memory Safe**: Compile-time safety guarantees from Zig
- **Cross-Platform**: Works on Linux, Windows, macOS, and more
- **Well Documented**: Comprehensive guides and API documentation

## Installation

Add to your `build.zig.zon`:

```zig
.dependencies = .{
    .logly = .{
    .url = "https://github.com/muhammad-fiaz/logly.zig/archive/refs/tags/v0.0.5.tar.gz",
        .hash = "...",
    },
},
```

[Get Started →](/guide/getting-started)
