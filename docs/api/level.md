---
title: Level API Reference
description: API reference for Logly.zig Level enum. All 10 built-in log levels (trace, debug, info, success, warning, error, fail, critical, fatal, panic) with priorities and colors.
head:
  - - meta
    - name: keywords
      content: log level api, level enum, log priority, trace debug info, error critical fatal, severity levels
  - - meta
    - property: og:title
      content: Level API Reference | Logly.zig
---

# Level API

The Level module defines the standard logging levels and their priorities.

## Level Enum

Logly provides **10 built-in log levels** ordered by severity:

```zig
pub const Level = enum(u8) {
    trace = 5,      // Very detailed tracing
    debug = 10,     // Debug information
    info = 20,      // General information
    notice = 22,    // Important notices
    success = 25,   // Successful operations
    warning = 30,   // Warning conditions
    err = 40,       // Error conditions
    fail = 45,      // Failure conditions
    critical = 50,  // Critical failures
    fatal = 55,     // Fatal system errors
};
```

## Level Table

| Level    | Priority | Color        | ANSI Code | Description              |
|----------|----------|--------------|-----------|--------------------------|
| `trace`    | 5        | Cyan         | 36        | Detailed tracing info    |
| `debug`    | 10       | Blue         | 34        | Debug information        |
| `info`     | 20       | White        | 37        | General information      |
| `notice`   | 22       | Bright Cyan  | 96        | Important notices        |
| `success`  | 25       | Green        | 32        | Successful operations    |
| `warning`  | 30       | Yellow       | 33        | Warning conditions       |
| `err`      | 40       | Red          | 31        | Error conditions         |
| `fail`     | 45       | Magenta      | 35        | Failure conditions       |
| `critical` | 50       | Bright Red   | 91        | Critical failures        |
| `fatal`    | 55       | White on Red | 97;41     | Fatal system errors      |

## Methods

### priority

Returns the numeric priority value of the level.

```zig
const level = Level.warning;
const p = level.priority(); // Returns 30
```

### fromPriority

Creates a Level from a numeric priority value.

```zig
const level = Level.fromPriority(20); // Returns .info
const invalid = Level.fromPriority(99); // Returns null
```

### asString

Returns the string representation of the level.

```zig
const level = Level.fatal;
const s = level.asString(); // Returns "FATAL"
```

### fromString

Creates a Level from a string representation.

```zig
const level = Level.fromString("NOTICE"); // Returns .notice
const invalid = Level.fromString("INVALID"); // Returns null
```

### defaultColor

Returns the ANSI color code for the level.

```zig
const level = Level.fatal;
const color = level.defaultColor(); // Returns "97;41" (white on red)
```

## CustomLevel

For dynamic custom levels, use the CustomLevel struct:

```zig
pub const CustomLevel = struct {
    name: []const u8,     // Display name (e.g., "AUDIT")
    priority: u8,         // Numeric priority
    color: []const u8,    // ANSI color code
};
```

### Usage

```zig
// Register a custom level
try logger.addCustomLevel("AUDIT", 35, "35");  // Priority 35, Magenta

// Use the custom level
try logger.custom("AUDIT", "User login detected", @src());
try logger.customf("AUDIT", "User {s} logged in", .{"admin"}, @src());

// Remove a custom level
logger.removeCustomLevel("AUDIT");
```

## Level Filtering

Set minimum log level in config:

```zig
var config = logly.Config.default();
config.level = .warning;  // Only WARNING and above will be logged
logger.configure(config);
```

## Level Comparison

```zig
const level1 = Level.warning;
const level2 = Level.err;

// Compare by priority
if (level1.priority() < level2.priority()) {
    // WARNING has lower priority than ERROR
}
```

## Example

```zig
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const logger = try logly.Logger.init(allocator);
    defer logger.deinit();

    // Log at all 10 built-in levels
    try logger.trace("Trace message", @src());
    try logger.debug("Debug message", @src());
    try logger.info("Info message", @src());
    try logger.notice("Notice message", @src());
    try logger.success("Success message", @src());
    try logger.warning("Warning message", @src());
    try logger.err("Error message", @src());
    try logger.fail("Fail message", @src());
    try logger.critical("Critical message", @src());
    try logger.fatal("Fatal message", @src());
}
```

## Aliases

The Level module provides convenience aliases:

| Alias | Method |
|-------|--------|
| `value` | `priority` |
| `severity` | `priority` |
| `toString` | `asString` |
| `str` | `asString` |
| `color` | `defaultColor` |
| `parse` | `fromString` |

## Additional Methods

- `isAtLeast(other: Level) bool` - Returns true if this level is at least as severe as other
- `isMoreSevereThan(other: Level) bool` - Returns true if this level is more severe than other
- `isError() bool` - Returns true if level is err, fail, critical, or fatal
- `isWarning() bool` - Returns true if level is warning or above
- `isDebug() bool` - Returns true if level is debug or trace

### CustomLevel Methods

- `init(name, priority, color) CustomLevel` - Create a new custom level
- `isAtLeast(other: Level) bool` - Compare with standard level
- `isError() bool` - Check if error-level severity
- `asString() []const u8` - Get level name

## See Also

- [Custom Levels Guide](../guide/custom-levels.md) - Custom level configuration
- [Logger API](logger.md) - Logger logging methods
- [Record API](record.md) - Log record structure
- [Configuration Guide](../guide/configuration.md) - Level configuration

