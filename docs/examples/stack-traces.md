---
title: Stack Traces Example
description: Capturing and formatting stack traces for error and critical log records in Logly.zig.
head:
  - - meta
    - name: keywords
      content: stack traces, capture stack trace, error logging, debug symbols
  - - meta
    - property: og:title
      content: Stack Traces Example | Logly.zig
---

# Stack Traces Example

Demonstrates capturing and formatting stack traces for `err` and `critical` log events in Logly.zig.

## Code Example

```zig
const std = @import("std");
const logly = @import("logly");

fn triggerFailure(logger: *logly.Logger) !void {
    try helperFunction(logger);
}

fn helperFunction(logger: *logly.Logger) !void {
    try deepOperation(logger);
}

fn deepOperation(logger: *logly.Logger) !void {
    try logger.err("Database transaction failed with connection timeout", @src());
    try logger.critical("Kernel subsystem unrecoverable error", @src());
}

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 1. Text Format with Stack Trace Capture
    {
        var config = logly.Config.default();
        config.captureStackTrace = true;
        config.symbolizeStackTrace = true;

        const logger = try logly.Logger.initWithConfig(allocator, config);
        defer logger.deinit();

        try triggerFailure(logger);
    }

    // 2. JSON Format with Stack Trace Capture
    {
        var config = logly.Config.default();
        config.format = .json;
        config.captureStackTrace = true;

        const logger = try logly.Logger.initWithConfig(allocator, config);
        defer logger.deinit();

        try logger.err("API request payload failed validation", @src());
    }
}
```
