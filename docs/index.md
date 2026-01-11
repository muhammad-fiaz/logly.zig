---
layout: home
title: "Logly.Zig - High-Performance Logging Library for Zig"
description: "High-Performance Logging Library for Zig - Production-ready structured logging with a clean, simple API. Features async I/O, file rotation, JSON output, and more."
keywords: "zig, logging, library, high-performance, structured logging, async, json, file rotation, cross-platform"
head:
  - - link
    - rel: canonical
      href: https://muhammad-fiaz.github.io/logly.zig/
  - - link
    - rel: manifest
      href: site.webmanifest
  - - meta
    - name: robots
      content: index,follow
  - - meta
    - name: author
      content: Muhammad Fiaz
  - - meta
    - name: X-Robots-Tag
      content: index,follow
  - - meta
    - name: description
      content: "High-Performance Logging Library for Zig - Production-ready structured logging with a clean, simple API. Features async I/O, file rotation, JSON output, and more."
  - - meta
    - name: keywords
      content: "zig, logging, library, high-performance, structured logging, async, json, file rotation, cross-platform"
  - - meta
    - property: og:title
      content: "Logly.Zig - High-Performance Logging Library for Zig"
  - - meta
    - property: og:description
      content: "Production-ready structured logging with a clean, simple API. Features async I/O, file rotation, JSON output, and more."
  - - meta
    - property: og:image
      content: https://muhammad-fiaz.github.io/logly.zig/cover.png
  - - meta
    - property: og:url
      content: https://muhammad-fiaz.github.io/logly.zig/
  - - meta
    - property: og:type
      content: website
  - - meta
    - name: twitter:card
      content: summary_large_image
  - - meta
    - name: twitter:title
      content: "Logly.Zig - High-Performance Logging Library for Zig"
  - - meta
    - name: twitter:description
      content: "Production-ready structured logging with a clean, simple API. Features async I/O, file rotation, JSON output, and more."
  - - meta
    - name: twitter:image
      content: https://muhammad-fiaz.github.io/logly.zig/cover.png


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
    // Pass null instead of @src() to disable source location
    try logger.info("Application started", @src());      // White line
    try logger.success("Operation completed!", @src());  // Green line
    try logger.warn("Low memory", @src());               // Yellow line (alias for warning)
    try logger.err("Connection failed", @src());         // Red line
}
```

## Why Logly.Zig?

- **Out-of-Box Features**: Get file rotation, JSON logging, async I/O, compression, metrics, and more without manual implementation
- **Production Grade**: Aims to be production ready, built natively in Zig
- **Zero Dependencies**: Pure Zig implementation with no external dependencies
- **Memory Safe**: Compile-time safety guarantees from Zig
- **Cross-Platform**: Works on Linux, Windows, macOS, and more
- **Well Documented**: Comprehensive guides and API documentation

::: tip 💡 Note
Logly.zig aims to be production-ready. While this is a relatively new project and not yet widely adopted, it offers powerful features that can simplify your Zig project's logging. If you love Logly.zig, feel free to use it in your projects and give it a ⭐ on GitHub!
:::

## Installation

The easiest way to add Logly to your project:

```bash
zig fetch --save https://github.com/muhammad-fiaz/logly.zig/archive/refs/tags/0.1.3.tar.gz
```

This automatically adds the dependency with the correct hash to your `build.zig.zon`.

For Nightly builds, you can use the Git URL directly:

```bash
zig fetch --save git+https://github.com/muhammad-fiaz/logly.zig.git
```

[Get Started →](/guide/getting-started)

