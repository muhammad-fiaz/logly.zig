---
title: Runtime Configuration Override Example
description: Dynamic runtime configuration updates, per-sink overrides, and conflict resolution in Logly.zig.
head:
  - - meta
    - name: keywords
      content: runtime config override, dynamic logging level, sink reconfiguration, conflict resolution
  - - meta
    - property: og:title
      content: Runtime Configuration Override Example | Logly.zig
---

# Runtime Configuration Override & Conflict Resolution Example

Demonstrates dynamic runtime configuration overrides, per-sink customizations, partial config merging via `ConfigOverride`, and automatic conflict resolution in Logly.zig.

## Code Example

```zig
const std = @import("std");
const logly = @import("logly");
const Logger = logly.Logger;
const Config = logly.Config;
const SinkConfig = logly.SinkConfig;
const Level = logly.Level;

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 1. Initial logger setup (info level, text format)
    var initialConfig = Config.default();
    initialConfig.autoSink = false;
    initialConfig.level = .info;

    var logger = try Logger.initWithConfig(allocator, initialConfig);
    defer logger.deinit();

    const consoleSinkId = try logger.addSink(SinkConfig.console());

    // 2. Dynamic runtime level change
    logger.setLevel(.debug);
    try logger.debug("Now visible after runtime setLevel()", null);

    // 3. Dynamic per-sink format customization
    try logger.setSinkFormat(consoleSinkId, .logfmt);
    try logger.info("Formatted as logfmt at runtime", null);

    // 4. Runtime partial override via ConfigOverride
    logger.applyOverride(.{
        .level = .warning,
        .format = .json,
        .autoFlush = true,
    });
    try logger.warn("Visible in JSON format with autoFlush enabled", null);

    // 5. Conflict Resolution
    var conflictConfig = Config.default();
    conflictConfig.captureStackTrace = false;
    conflictConfig.symbolizeStackTrace = true; // Requires captureStackTrace
    conflictConfig.resolveConflicts();
    // conflictConfig.captureStackTrace is now true
}
```

## Running the Example

```bash
zig build run-runtime_config_override
```
