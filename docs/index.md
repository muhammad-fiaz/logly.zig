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

  - icon: 🎭
    title: Custom Levels
    details: Define your own log levels with custom priorities and colors
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
    try logger.info("Application started");      // White line
    try logger.success("Operation completed!");  // Green line
    try logger.warning("Low memory");            // Yellow line
    try logger.err("Connection failed");         // Red line
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
        .url = "https://github.com/muhammad-fiaz/logly.zig/archive/refs/tags/v0.0.3.tar.gz",
        .hash = "...",
    },
},
```

[Get Started →](/guide/getting-started)
