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

## Quick Reference: Method Aliases

| Full Method | Alias(es) | Description |
|-------------|-----------|-------------|
| `priority()` | `value()`, `severity()` | Get priority value |
| `asString()` | `toString()`, `str()` | Convert to string |
| `fromString()` | `parse()` | Parse from string |
| `fromPriority()` | `fromValue()`, `fromSeverity()` | Create from priority |
| `defaultColor()` | `color()` | Get default tint color |
| `defaultStyle()` | — | Get default tint style (fatal includes background) |
| `isAtLeast()` | `atLeast()`, `gte()` | Check if at least level |
| `isMoreSevereThan()` | `moreSevereThan()`, `gt()` | Check if more severe than |
| `isError()` | `isErr()`, `isFailure()` | Check if error level |
| `isWarning()` | `isWarn()` | Check if warning level |
| `isDebug()` | `isTraceOrDebug()`, `isVerbose()` | Check if debug/trace level |
| `init()` | `create()`, `new()` | Initialize custom level (CustomLevel) |
| `initRgb()` | `createRgb()`, `newRgb()` | Initialize RGB custom level (CustomLevel) |
| `init256()` | `create256()`, `new256()` | Initialize 256-color custom level (CustomLevel) |
| `initStyled()` | `createStyled()`, `newStyled()` | Initialize styled custom level (CustomLevel) |
| `initWithBackground()` | `createWithBackground()`, `newWithBackground()` | Initialize with background (CustomLevel) |
| `effectiveColor()` | `effective()`, `getColor()` | Get effective tint color (CustomLevel) |
| `effectiveStyle()` | — | Get effective tint style (CustomLevel) |
| `isAtLeast()` | `atLeast()`, `gte()` | Check if at least level (CustomLevel) |
| `isError()` | `isErr()`, `isFailure()` | Check if error level (CustomLevel) |
| `asString()` | `toString()`, `str()` | Convert to string (CustomLevel) |
| `hasBackground()` | `hasBg()`, `hasBackgroundColor()` | Check if has background (CustomLevel) |
| `hasStyle()` | `hasTextStyle()` | Check if has text style (CustomLevel) |

> Colors are tint `Color` values. Render with `logly.Color.sequence(color, .trueColor)` and write `Sequence.slice()`.

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

  Returns the default tint color for the level.

  ```zig
  const level = Level.fatal;
  const color = level.defaultColor(); // tint Color (bright white)
  const seq = logly.Color.sequence(color, .trueColor);
  ```

  ### defaultStyle

  Returns the default tint style (fatal includes a red background).

  ```zig
  const style = Level.fatal.defaultStyle();
  const seq = logly.Color.styleSequence(style);
  ```

## CustomLevel

For dynamic custom levels, use the CustomLevel struct:

  ```zig
  pub const CustomLevel = struct {
      name: []const u8,          // Display name (e.g., "AUDIT")
      priority: u8,              // Numeric priority
      color: logly.Color.Color, // Foreground tint color
      bgColor: ?logly.Color.Color = null,   // Background tint color
      style: ?logly.Color.Style = null,     // Full style override
  };
  ```

  ### Basic Usage

  ```zig
  // Register a custom level (tint colors)
  try logger.addCustomLevel("AUDIT", 35, logly.Color.parse("magenta").?);

  // Use the custom level
  try logger.custom("AUDIT", "User login detected", @src());
  try logger.customf("AUDIT", "User {s} logged in", .{"admin"}, @src());

  // Remove a custom level
  logger.removeCustomLevel("AUDIT");
  ```

  ### Advanced CustomLevel Constructors

  ```zig
  const CustomLevel = logly.CustomLevel;

  // Basic initialization with a tint color
  const audit = CustomLevel.init("AUDIT", 35, logly.Color.parse("cyan").?);

  // RGB color
  const rgbLevel = CustomLevel.initRgb("METRIC", 25, 50, 205, 50);

  // With explicit style (bold underline red)
  const styled = CustomLevel.initStyled("STYLED", 45, .{
      .foreground = logly.Color.Tint.color.red,
      .underline = true,
  });

  // With background
  const alert = CustomLevel.initWithBackground(
      "ALERT", 50,
      logly.Color.Tint.color.ansi4.brightWhite,
      logly.Color.Tint.color.ansi4.red,
  );
  ```

  ### CustomLevel Methods

  ```zig
  const custom = CustomLevel.init("TEST", 42, logly.Color.parse("green").?);

  // Effective tint color and style
  const color = custom.effectiveColor();
  const style = custom.effectiveStyle();

  // Capability checks
  const has_bg = custom.hasBackground();
  const has_style = custom.hasStyle();
  ```

## LevelMask

The `LevelMask` struct enables fine-grained inclusion/exclusion of specific levels independent of priority.

```zig
pub const LevelMask = struct {
    mask: u16 = 0,

    /// Creates an empty mask (no levels enabled).
    pub fn init() LevelMask;

    /// Creates a mask with all standard levels enabled.
    pub fn all() LevelMask;

    /// Creates a mask with only error/fatal levels enabled.
    pub fn errorOnly() LevelMask;

    /// Enables a specific level.
    pub fn enable(self: *LevelMask, lvl: Level) void;

    /// Disables a specific level.
    pub fn disable(self: *LevelMask, lvl: Level) void;

    /// Checks if a level is enabled.
    pub fn isEnabled(self: *const LevelMask, lvl: Level) bool;
};
```

### Basic Usage

```zig
var mask = LevelMask.init();
mask.enable(.err);
mask.enable(.critical);

if (mask.isEnabled(level)) {
    // Level is enabled
}
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
    var gpa = std.heap.DebugAllocator(.{}){};
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

