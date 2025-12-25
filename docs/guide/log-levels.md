---
title: Log Levels
description: Explore the 10 built-in log levels in Logly.zig. Learn about priorities, whole-line coloring, custom levels, and fine-grained level filtering for modules.
head:
  - - meta
    - name: keywords
      content: log levels, log priority, level filtering, module levels, custom log levels, whole-line coloring, zig logging
  - - meta
    - property: og:title
      content: Log Levels | Logly.zig
  - - meta
    - property: og:image
      content: https://muhammad-fiaz.github.io/logly.zig/cover.png
---

# Log Levels

Logly-Zig supports **10 built-in log levels**, each with a specific priority, color, and use case.

## Level Overview

| Level    | Priority | Color        | ANSI    | Method              | Alias    | Use Case                  |
| -------- | -------- | ------------ | ------- | ------------------- | -------- | ------------------------- |
| TRACE    | 5        | Cyan         | 36      | `logger.trace()`    | -        | Very detailed debugging   |
| DEBUG    | 10       | Blue         | 34      | `logger.debug()`    | -        | Debugging information     |
| INFO     | 20       | White        | 37      | `logger.info()`     | -        | General information       |
| NOTICE   | 22       | Bright Cyan  | 96      | `logger.notice()`   | -        | Important notices         |
| SUCCESS  | 25       | Green        | 32      | `logger.success()`  | -        | Successful operations     |
| WARNING  | 30       | Yellow       | 33      | `logger.warning()`  | `warn()` | Warning messages          |
| ERROR    | 40       | Red          | 31      | `logger.err()`      | -        | Error conditions          |
| FAIL     | 45       | Magenta      | 35      | `logger.fail()`     | -        | Operation failures        |
| CRITICAL | 50       | Bright Red   | 91      | `logger.critical()` | `crit()` | Critical system errors    |
| FATAL    | 55       | White on Red | 97;41   | `logger.fatal()`    | -        | Fatal system errors       |

## Whole-Line Coloring

Logly colors the **entire log line** (timestamp, level tag, and message), not just the level name:

```
[2024-01-15 10:30:45] [WARNING] Low disk space    <- Entire line is yellow
[2024-01-15 10:30:46] [ERROR] Connection failed   <- Entire line is red
[2024-01-15 10:30:47] [FATAL] System crash        <- Entire line is white on red background
```

## Usage

```zig
// Enable colors on Windows first
_ = logly.Terminal.enableAnsiColors();

// All methods accept optional @src() for clickable file:line output
try logger.trace("Detailed trace information", @src());   // Cyan line
try logger.debug("Debug information", @src());            // Blue line
try logger.info("Application started", @src());           // White line
try logger.notice("Important notice", @src());            // Bright cyan line
try logger.success("Operation completed!", @src());       // Green line
try logger.warning("Warning message", @src());            // Yellow line
try logger.warn("Short alias for warning", @src());       // Yellow line (alias)
try logger.err("Error occurred", @src());                 // Red line
try logger.fail("Operation failed", @src());              // Magenta line
try logger.critical("Critical system error!", @src());    // Bright red line
try logger.crit("Short alias for critical", @src());      // Bright red line (alias)
try logger.fatal("Fatal system error!", @src());          // White on red background
```

> **Note:** Each level also has a formatted variant (e.g., `tracef`, `infof`, `noticef`, `fatalf`) that accepts a format string and arguments. See [Formatting](/guide/formatting#formatted-logging) for details.

## Custom Levels

Create your own log levels with custom priorities and colors:

```zig
// Add custom levels
try logger.addCustomLevel("AUDIT", 35, "35");      // Magenta (between WARNING and ERR)
try logger.addCustomLevel("SECURITY", 48, "91;1"); // Bold bright red (between FAIL and CRITICAL)

// Use custom levels
try logger.custom("AUDIT", "Security event detected", @src());
try logger.customf("SECURITY", "Unauthorized access from {s}", .{"192.168.1.1"}, @src());
```

## Level Filtering

You can configure the minimum log level to output. Messages below this level will be ignored.

```zig
var config = logly.Config.default();
config.level = .info; // Ignore TRACE and DEBUG
logger.configure(config);
```

## Priority Order

The levels follow this priority order (lowest to highest):

```
TRACE (5) < DEBUG (10) < INFO (20) < NOTICE (22) < SUCCESS (25) < WARNING (30) < ERROR (40) < FAIL (45) < CRITICAL (50) < FATAL (55)
```

When you set a minimum level, only messages at that level or higher will be logged.

## Module Levels

You can set different log levels for specific modules. This allows you to enable debug logging for a specific part of your application while keeping the rest at a higher level.

```zig
// Set global level to INFO
config.level = .info;
logger.configure(config);

// Enable DEBUG for network module
try logger.setModuleLevel("network", .debug);

// Create a scoped logger
const net_logger = logger.scoped("network");
try net_logger.debug("This will be logged", @src());
```

To use module-specific logging, use the `scoped()` method to create a logger instance for that module.
