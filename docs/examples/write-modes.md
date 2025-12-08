# Sink Write Modes

Learn how to control whether log files are appended to or overwritten using the `overwrite_mode` parameter.

## Overview

The `overwrite_mode` parameter in `SinkConfig` controls how files are written:

- **Append Mode** (default, `overwrite_mode = false`): New logs are added to existing files, preserving history
- **Overwrite Mode** (`overwrite_mode = true`): Files are truncated when the sink initializes, starting fresh

This is useful for scenarios like:
- **Append**: Permanent audit logs, error tracking, system history
- **Overwrite**: Session logs, temporary debug output, test runs

## Append Mode (Default)

The default behavior appends logs to existing files:

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create logger with append mode sink
    const logger = try logly.Logger.init(allocator);
    defer logger.deinit();

    var config = logly.SinkConfig.file("logs/app.log");
    config.overwrite_mode = false;  // Append mode (this is the default)
    
    _ = try logger.addSink(config);

    try logger.info("First run", @src());
    try logger.info("This is appended", @src());
}
```

Each time you run the application:
1. First run: Creates `logs/app.log` with 2 entries
2. Second run: Appends 2 more entries → file now has 4 entries
3. Third run: Appends 2 more entries → file now has 6 entries

**File grows continuously**, preserving all historical logs.

## Overwrite Mode

Start fresh each run by enabling overwrite mode:

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create logger with overwrite mode sink
    const logger = try logly.Logger.init(allocator);
    defer logger.deinit();

    var config = logly.SinkConfig.file("logs/session.log");
    config.overwrite_mode = true;  // Enable overwrite mode
    
    _ = try logger.addSink(config);

    try logger.info("Fresh start", @src());
    try logger.info("Previous logs discarded", @src());
}
```

Each time you run the application:
1. First run: Creates `logs/session.log` with 2 entries
2. Second run: File is truncated, then has 2 entries (old ones gone)
3. Third run: File is truncated, then has 2 entries (old ones gone)

**File is reset each run**, showing only the current session.

## Mixed Modes

Combine both modes in a single logger:

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const logger = try logly.Logger.init(allocator);
    defer logger.deinit();

    // Sink 1: Persistent audit log (append mode)
    var audit = logly.SinkConfig.file("logs/audit.log");
    audit.overwrite_mode = false;  // Keep all history
    _ = try logger.addSink(audit);

    // Sink 2: Current session debug log (overwrite mode)
    var debug = logly.SinkConfig.file("logs/debug.log");
    debug.overwrite_mode = true;   // Fresh each run
    _ = try logger.addSink(debug);

    // Sink 3: Error log (append mode for permanent record)
    var errors = logly.SinkConfig.file("logs/errors.log");
    errors.level = .err;
    errors.overwrite_mode = false;  // Keep error history
    _ = try logger.addSink(errors);

    try logger.info("Logged to audit.log and debug.log", @src());
    try logger.err("Logged to errors.log", @src());
}
```

**Result**:
- `audit.log`: Grows over time with all entries
- `debug.log`: Fresh each run, shows only current session
- `errors.log`: Grows over time with all error entries

## JSON Output

Overwrite mode works with JSON sinks too:

```zig
// JSON file that overwrites each run
var config = logly.SinkConfig.file("logs/session.json");
config.json = true;
config.pretty_json = true;
config.overwrite_mode = true;  // Overwrite JSON file
_ = try logger.addSink(config);
```

## Use Cases

### Append Mode

- **Audit logs**: Keep permanent record of all events
- **Error tracking**: Maintain history of all errors
- **Production logs**: Accumulate data for analysis
- **Application history**: Track all user actions

```zig
// Permanent error log
var errors = logly.SinkConfig.file("logs/errors.log");
errors.level = .err;
errors.overwrite_mode = false;  // Never discard
_ = try logger.addSink(errors);
```

### Overwrite Mode

- **Debug sessions**: Fresh logs for each debugging session
- **Test runs**: Clean output for each test
- **Development**: Don't accumulate noise during development
- **Temporary logs**: Logs meant for current session only

```zig
// Fresh debug log each time
var debug = logly.SinkConfig.file("logs/debug.log");
debug.overwrite_mode = true;  // Reset each run
_ = try logger.addSink(debug);
```

## Performance Considerations

- **Append mode**: Slightly faster (no truncation overhead)
- **Overwrite mode**: Minimal overhead from file truncation at initialization

Both modes use the same high-performance async writing internally.

## File Rotation

The `overwrite_mode` parameter works independently from file rotation:

```zig
// Rotation + Append mode: rotated files accumulate
var config = logly.SinkConfig.file("logs/app.log");
config.rotation = "daily";      // Daily rotation
config.overwrite_mode = false;  // Append mode
config.retention = 7;           // Keep 7 days of rotated files
_ = try logger.addSink(config);
```

## See Also

- [File Rotation](rotation.md)
- [Async Writing](async-logging.md)
- [File Logging](file-logging.md)
- [Sink Configuration](../api/sink.md)
