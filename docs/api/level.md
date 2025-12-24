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
