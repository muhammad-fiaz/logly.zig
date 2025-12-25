---
title: Basic Logging Example
description: Learn the basics of Logly.zig with this simple example. Covers logger initialization, all 10 built-in log levels, and proper cleanup with defer.
head:
  - - meta
    - name: keywords
      content: logly example, basic logging, zig logging tutorial, hello world logging, getting started
  - - meta
    - property: og:title
      content: Basic Logging Example | Logly.zig
  - - meta
    - property: og:description
      content: Simple example demonstrating Logly.zig initialization and all 10 built-in log levels.
---

# Basic Usage

This example demonstrates the basic usage of Logly.zig, including initialization and logging at all 10 built-in levels.

## Code Example

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Enable ANSI colors on Windows (no-op on Linux/macOS)
    _ = logly.Terminal.enableAnsiColors();

    // Create logger (auto-sink enabled by default)
    const logger = try logly.Logger.init(allocator);
    defer logger.deinit();

    // Log at all 10 built-in levels - entire line is colored!
    // Pass @src() for clickable file:line, or null for no source location
    try logger.trace("This is a trace message", @src());       // Cyan
    try logger.debug("This is a debug message", @src());       // Blue
    try logger.info("This is an info message", @src());        // White
    try logger.notice("This is a notice", @src());             // Bright Cyan
    try logger.success("Operation completed!", @src());        // Green
    try logger.warning("This is a warning", @src());           // Yellow
    try logger.err("This is an error", @src());                // Red
    try logger.fail("Operation failed", @src());               // Magenta
    try logger.critical("Critical system error!", @src());     // Bright Red
    try logger.fatal("Fatal system error!", @src());           // White on Red

    // Short aliases also available
    try logger.warn("Warning with short alias", @src());
    try logger.crit("Critical with short alias", @src());

    std.debug.print("\nBasic logging example completed!\n", .{});
}
```

## Expected Output

Each line is colored according to its level:

```text
[2024-01-15 10:30:45] [TRACE] This is a trace message       <- Cyan line
[2024-01-15 10:30:45] [DEBUG] This is a debug message       <- Blue line
[2024-01-15 10:30:45] [INFO] This is an info message        <- White line
[2024-01-15 10:30:45] [NOTICE] This is a notice             <- Bright Cyan line
[2024-01-15 10:30:45] [SUCCESS] Operation completed!        <- Green line
[2024-01-15 10:30:45] [WARNING] This is a warning           <- Yellow line
[2024-01-15 10:30:45] [ERROR] This is an error              <- Red line
[2024-01-15 10:30:45] [FAIL] Operation failed               <- Magenta line
[2024-01-15 10:30:45] [CRITICAL] Critical system error!     <- Bright Red line
[2024-01-15 10:30:45] [FATAL] Fatal system error!           <- White on Red background
```

## Level Colors

| Level    | Priority | Color Code | Display              |
|----------|----------|------------|----------------------|
| TRACE    | 5        | 36         | Cyan                 |
| DEBUG    | 10       | 34         | Blue                 |
| INFO     | 20       | 37         | White                |
| NOTICE   | 22       | 96         | Bright Cyan          |
| SUCCESS  | 25       | 32         | Green                |
| WARNING  | 30       | 33         | Yellow               |
| ERROR    | 40       | 31         | Red                  |
| FAIL     | 45       | 35         | Magenta              |
| CRITICAL | 50       | 91         | Bright Red           |
| FATAL    | 55       | 97;41      | White on Red         |

## Running the Example

```bash
zig build run-basic
```
