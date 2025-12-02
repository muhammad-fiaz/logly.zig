# Log Levels

Logly-Zig supports 8 distinct log levels, each with a specific priority and use case.

| Level    | Priority | Method              | Use Case                |
| -------- | -------- | ------------------- | ----------------------- |
| TRACE    | 5        | `logger.trace()`    | Very detailed debugging |
| DEBUG    | 10       | `logger.debug()`    | Debugging information   |
| INFO     | 20       | `logger.info()`     | General information     |
| SUCCESS  | 25       | `logger.success()`  | Successful operations   |
| WARNING  | 30       | `logger.warning()`  | Warning messages        |
| ERROR    | 40       | `logger.err()`      | Error conditions        |
| FAIL     | 45       | `logger.fail()`     | Operation failures      |
| CRITICAL | 50       | `logger.critical()` | Critical system errors  |

## Usage

```zig
try logger.trace("Detailed trace information");
try logger.debug("Debug information");
try logger.info("Application started");
try logger.success("Operation completed successfully!");
try logger.warning("Warning message");
try logger.err("Error occurred");
try logger.fail("Operation failed");
try logger.critical("Critical system error!");
```

> **Note:** Each level also has a formatted variant (e.g., `tracef`, `infof`) that accepts a format string and arguments. See [Formatting](/guide/formatting#formatted-logging) for details.

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
