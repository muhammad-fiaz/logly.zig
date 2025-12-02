# Quick Start

Learn the basics of Logly-Zig with practical examples.

## Basic Usage

### Simple Console Logging

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const logger = try logly.Logger.init(allocator);
    defer logger.deinit();

    try logger.info("Hello, Logly!");
    try logger.success("Operation completed!");
    try logger.warning("Be careful!");
    try logger.err("Something went wrong!");
}
```

### All Log Levels

```zig
try logger.trace("Detailed trace");      // Priority 5
try logger.debug("Debug info");          // Priority 10
try logger.info("Information");          // Priority 20
try logger.success("Success!");          // Priority 25
try logger.warning("Warning");           // Priority 30
try logger.err("Error occurred");        // Priority 40
try logger.fail("Operation failed");     // Priority 45
try logger.critical("Critical!");        // Priority 50
```

### Formatted Logging

Use `printf`-style formatting with the `f` suffix methods:

```zig
try logger.infof("User {s} logged in from {s}", .{ "Alice", "127.0.0.1" });
try logger.debugf("Processing item {d} of {d}", .{ 5, 10 });
try logger.errf("Connection failed: {s}", .{ "Timeout" });
```

## File Logging

```zig
const logger = try logly.Logger.init(allocator);
defer logger.deinit();

var config = logly.Config.default();
config.auto_sink = false; // Disable auto console sink
logger.configure(config);

_ = try logger.addSink(.{
    .path = "app.log",
});

try logger.info("Logging to file!");
try logger.flush(); // Ensure data is written
```

## Common Patterns

### File Rotation

```zig
_ = try logger.addSink(.{
    .path = "logs/app.log",
    .rotation = "daily",
    .retention = 7, // Keep 7 days
});
```

### JSON Logging

```zig
var config = logly.Config.default();
config.json = true;
logger.configure(config);

try logger.info("JSON formatted");
```

### Context Binding

```zig
try logger.bind("user_id", .{ .string = "12345" });
try logger.bind("request_id", .{ .string = "req-abc" });

try logger.info("User action");
// Logs include user_id and request_id automatically
```

### Custom Log Levels

```zig
try logger.addCustomLevel("NOTICE", 35, "96");
try logger.custom("NOTICE", "Custom level message");
```

### Callbacks

```zig
fn logCallback(record: *const logly.Record) !void {
    if (record.level.priority() >= logly.Level.err.priority()) {
        // Handle high severity
    }
}

logger.setLogCallback(&logCallback);
```

### Multiple Sinks

```zig
// Console sink
_ = try logger.addSink(.{});

// File sink
_ = try logger.addSink(.{
    .path = "app.log",
});

// Error-only file
_ = try logger.addSink(.{
    .path = "errors.log",
    .level = .err,
});
```

## Configuration

### Basic Configuration

```zig
var config = logly.Config.default();
config.level = .debug;
config.color = true;
config.json = false;
logger.configure(config);
```

### Global Controls

```zig
var config = logly.Config.default();
config.global_console_display = true;  // Enable console
config.global_file_storage = true;     // Enable file storage
config.global_color_display = true;    // Enable colors
logger.configure(config);
```

## Complete Example

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create logger
    const logger = try logly.Logger.init(allocator);
    defer logger.deinit();

    // Configure
    var config = logly.Config.default();
    config.level = .debug;
    config.color = true;
    config.enable_callbacks = true;
    logger.configure(config);

    // Add sinks
    _ = try logger.addSink(.{}); // Console
    _ = try logger.addSink(.{
        .path = "logs/app.log",
        .rotation = "daily",
        .retention = 7,
    });

    // Bind context
    try logger.bind("app", .{ .string = "myapp" });
    try logger.bind("version", .{ .string = "1.0.0" });

    // Log messages
    try logger.info("Application started");
    try logger.success("Initialization complete");

    // Simulate work
    for (0..10) |i| {
        const msg = try std.fmt.allocPrint(
            allocator,
            "Processing item {d}",
            .{i}
        );
        defer allocator.free(msg);
        try logger.debug(msg);
    }

    try logger.success("All items processed");
}
```

## Next Steps

- [Log Levels](/guide/log-levels) - Understand log levels
- [Configuration](/guide/configuration) - Detailed configuration
- [Sinks](/guide/sinks) - Working with sinks
- [Examples](/examples/basic) - More examples
