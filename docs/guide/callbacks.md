# Callbacks

Callbacks allow you to hook into the logging process and execute custom code whenever a log message is processed. This is useful for integrating with external monitoring systems, sending alerts, or updating metrics.

## Setting a Callback

You can set a global callback function that receives the `Record` object.

```zig
fn logCallback(record: *const logly.Record) !void {
    // Check if the log level is ERROR or higher
    if (record.level.priority() >= logly.Level.err.priority()) {
        // Send alert to external system
        sendAlert(record.message);
    }
}

// Register the callback
logger.setLogCallback(&logCallback);
```

## The Record Object

The `Record` object contains all information about the log event:

- `level`: The log level
- `message`: The log message
- `timestamp`: The timestamp
- `module`: The module name
- `function`: The function name
- `file`: The filename
- `line`: The line number
- `context`: The bound context values

## Custom Color Callbacks

You can also customize the colors used for each log level by setting a color callback.

```zig
fn colorCallback(level: logly.Level, message: []const u8) []const u8 {
    // Return ANSI color codes based on level
    return switch (level) {
        .err => "\x1b[31m", // Red
        .info => "\x1b[32m", // Green
        else => "\x1b[0m",  // Reset
    };
}

logger.setColorCallback(&colorCallback);
```
