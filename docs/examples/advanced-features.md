---
title: Advanced Features Example
description: Explore Logly.zig advanced features including scoped loggers, custom themes, and pipeline controls.
head:
  - - meta
    - name: keywords
      content: logly advanced features, scoped logger, custom theme, zig logging
  - - meta
    - property: og:title
      content: Advanced Features Example | Logly.zig
---

# Advanced Features

Scoped loggers, custom themes, and combined feature usage.

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const logger = try logly.Logger.init(allocator);
    defer logger.deinit();

    // Scoped logger with module context
    var scoped = logger.scoped("auth");
    try scoped.info("User login", @src());

    // Custom theme
    const theme = logly.Formatter.Theme{
        .info = logly.Color.parse("cyan").?,
        .err = logly.Color.parse("red").?,
    };
    if (logger.getSink(0)) |sink| sink.formatter.setTheme(theme);

    try logger.info("Themed message", @src());
}
```

Output:

```text
[INFO] [auth] User login
[INFO] Themed message
```
