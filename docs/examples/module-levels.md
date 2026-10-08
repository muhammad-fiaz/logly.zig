---
title: Module Levels Example
description: Example of module-specific log levels in Logly.zig. Control logging verbosity for different parts of your application with scoped loggers and per-module settings.
head:
  - - meta
    - name: keywords
      content: module levels, scoped logger, per-module logging, log verbosity, component logging, selective debug
  - - meta
    - property: og:title
      content: Module Levels Example | Logly.zig
  - - meta
    - property: og:image
      content: https://muhammad-fiaz.github.io/logly.zig/cover.png
---

# Module Levels

This example demonstrates how to use module-specific log levels to control logging verbosity for different parts of your application. This is incredibly useful for debugging specific components without being overwhelmed by logs from the entire system.

## Code Example

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Enable colors on Windows
     _ = logly.Terminal.enableAnsiColors();

    const logger = try logly.Logger.init(allocator);
    defer logger.deinit();

    // Set global level to INFO
    var config = logly.Config.default();
    config.level = .info;
    config.showModule = true;
    logger.configure(config);

    // Create scoped loggers for different modules
    const netLogger = logger.scoped("network");
    const dbLogger = logger.scoped("database");
    const uiLogger = logger.scoped("ui");

    // Default behavior (INFO and above)
    try logger.info("Application started", @src());
    try netLogger.info("Network initialized", @src()); // Shows [network]
    try netLogger.debug("Network debug message", @src()); // Hidden (global level is INFO)

    // Set specific level for network module (allow DEBUG)
    try logger.setModuleLevel("network", .debug);
    try logger.info("Changed network module level to DEBUG", @src());

    try netLogger.debug("Network debug message (now visible)", @src());
    try dbLogger.debug("Database debug message", @src()); // Still hidden

    // Set specific level for UI module (only ERROR)
    try logger.setModuleLevel("ui", .err);
    try logger.info("Changed UI module level to ERROR", @src());

    try uiLogger.warn("UI warning", @src()); // Hidden (using short alias)
    try uiLogger.err("UI error", @src()); // Visible

    // Verify database still follows global
    try dbLogger.info("Database info", @src()); // Visible
}
```

## Expected Output

```text
[INFO] Application started
[network] [INFO] Network initialized
[INFO] Changed network module level to DEBUG
[network] [DEBUG] Network debug message (now visible)
[INFO] Changed UI module level to ERROR
[ui] [ERROR] UI error
[database] [INFO] Database info
```
