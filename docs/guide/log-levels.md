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

## Level Filtering

You can configure the minimum log level to output. Messages below this level will be ignored.

```zig
var config = logly.Config.default();
config.level = .info; // Ignore TRACE and DEBUG
logger.configure(config);
```
