# Log Levels

Logly-Zig supports 8 distinct log levels, each with a specific priority, color, and use case.

## Level Overview

| Level    | Priority | Color | ANSI | Method              | Use Case                |
| -------- | -------- | ----- | ---- | ------------------- | ----------------------- |
| TRACE    | 5        | Cyan | 36 | `logger.trace()`    | Very detailed debugging |
| DEBUG    | 10       | Blue | 34 | `logger.debug()`    | Debugging information   |
| INFO     | 20       | White | 37 | `logger.info()`     | General information     |
| SUCCESS  | 25       | Green | 32 | `logger.success()`  | Successful operations   |
| WARNING  | 30       | Yellow | 33 | `logger.warning()`  | Warning messages        |
| ERROR    | 40       | Red | 31 | `logger.err()`      | Error conditions        |
| FAIL     | 45       | Magenta | 35 | `logger.fail()`     | Operation failures      |
| CRITICAL | 50       | Bright Red | 91 | `logger.critical()` | Critical system errors  |

## Whole-Line Coloring

Logly colors the **entire log line** (timestamp, level tag, and message), not just the level name:

```
[2024-01-15 10:30:45] [WARNING] Low disk space    <- Entire line is yellow
[2024-01-15 10:30:46] [ERROR] Connection failed   <- Entire line is red
```

## Usage

```zig
// Enable colors on Windows first
_ = logly.Terminal.enableAnsiColors();

try logger.trace("Detailed trace information");   // Cyan line
try logger.debug("Debug information");            // Blue line
try logger.info("Application started");           // White line
try logger.success("Operation completed!");       // Green line
try logger.warning("Warning message");            // Yellow line
try logger.err("Error occurred");                 // Red line
try logger.fail("Operation failed");              // Magenta line
try logger.critical("Critical system error!");    // Bright red line
```

> **Note:** Each level also has a formatted variant (e.g., `tracef`, `infof`) that accepts a format string and arguments. See [Formatting](/guide/formatting#formatted-logging) for details.

## Custom Levels

Create your own log levels with custom priorities and colors:

```zig
// Add custom levels
try logger.addCustomLevel("audit", 35, "35");      // Magenta (between WARNING and ERR)
try logger.addCustomLevel("notice", 22, "36;1");   // Bold cyan (between INFO and SUCCESS)
try logger.addCustomLevel("alert", 48, "91;1");    // Bold bright red (between FAIL and CRITICAL)

// Use custom levels
try logger.custom("audit", "Security event detected");
try logger.custom("notice", "Important notice");
try logger.customf("alert", "High CPU usage: {d}%", .{95});
```

## Level Filtering

You can configure the minimum log level to output. Messages below this level will be ignored.

```zig
var config = logly.Config.default();
config.level = .info; // Ignore TRACE and DEBUG
logger.configure(config);
```

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
try net_logger.debug("This will be logged");
```

To use module-specific logging, use the `scoped()` method to create a logger instance for that module.
