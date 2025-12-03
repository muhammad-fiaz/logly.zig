# Custom Log Levels

While Logly-Zig comes with 8 built-in levels, you might need to define your own levels for specific domain requirements.

## Platform Color Support

Logly supports ANSI colors on all major platforms:
- **Linux/macOS**: Native ANSI support
- **Windows 10+**: Call `Terminal.enableAnsiColors()` at startup
- **VS Code Terminal**: Full support

```zig
// Enable ANSI colors on Windows (no-op on Linux/macOS)
_ = logly.Terminal.enableAnsiColors();
```

## Whole-Line Coloring

Logly colors the **entire log line** (timestamp, level tag, and message), not just the level tag. This makes logs much more readable.

## Adding a Custom Level

You can add a custom level with a name, priority, and ANSI color code:

```zig
// Add a NOTICE level with priority 35 (between WARNING and ERROR)
// "36;1" is the ANSI color code for Cyan Bold
try logger.addCustomLevel("NOTICE", 35, "36;1");

// Add an ALERT level with Red Underline
try logger.addCustomLevel("ALERT", 42, "31;4");

// Add a HIGHLIGHT level with Yellow Reverse
try logger.addCustomLevel("HIGHLIGHT", 52, "33;7");
```

## ANSI Color Codes

| Code | Color | Code | Style |
|------|-------|------|-------|
| 30 | Black | 1 | Bold |
| 31 | Red | 4 | Underline |
| 32 | Green | 7 | Reverse |
| 33 | Yellow | 90-97 | Bright colors |
| 34 | Blue | | |
| 35 | Magenta | | |
| 36 | Cyan | | |
| 37 | White | | |

Combine codes with semicolons: `"36;1"` = Cyan Bold, `"31;4"` = Red Underline

## Using Custom Levels

To log using a custom level, use the `custom` method:

```zig
try logger.custom("NOTICE", "This is a notice message");
try logger.custom("ALERT", "This is an alert message");
```

Or use formatted logging with `customf`:

```zig
try logger.customf("NOTICE", "User {s} action: {s}", .{ "alice", "login" });
```

## Standard Level Colors

| Level | Priority | ANSI Code | Color |
|-------|----------|-----------|-------|
| TRACE | 5 | 36 | Cyan |
| DEBUG | 10 | 34 | Blue |
| INFO | 20 | 37 | White |
| SUCCESS | 25 | 32 | Green |
| WARNING | 30 | 33 | Yellow |
| ERROR | 40 | 31 | Red |
| FAIL | 45 | 35 | Magenta |
| CRITICAL | 50 | 91 | Bright Red |

## Complete Example

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Enable ANSI colors on Windows
    _ = logly.Terminal.enableAnsiColors();

    const logger = try logly.Logger.init(allocator);
    defer logger.deinit();

    // Add custom levels
    try logger.addCustomLevel("NOTICE", 35, "36;1");    // Cyan Bold
    try logger.addCustomLevel("ALERT", 42, "31;4");     // Red Underline
    try logger.addCustomLevel("AUDIT", 22, "35");       // Magenta

    // Use standard levels (entire line colored)
    try logger.info("Standard info - white line");
    try logger.warning("Standard warning - yellow line");
    try logger.err("Standard error - red line");

    // Use custom levels (entire line colored with custom colors)
    try logger.custom("NOTICE", "Notice - cyan bold line");
    try logger.custom("ALERT", "Alert - red underline line");
    try logger.custom("AUDIT", "Audit - magenta line");
}
```

## Priorities

Choose a priority for your custom level that fits into the standard hierarchy:

- TRACE: 5
- DEBUG: 10
- INFO: 20
- SUCCESS: 25
- WARNING: 30
- **Custom levels: 31-39** (between WARNING and ERROR)
- ERROR: 40
- **Custom levels: 41-44** (between ERROR and FAIL)
- FAIL: 45
- **Custom levels: 46-49** (between FAIL and CRITICAL)
- CRITICAL: 50

## Custom Levels with JSON Output

Custom levels work seamlessly with JSON output - the level name appears in the JSON:

```zig
var config = logly.Config.default();
config.json = true;
config.pretty_json = true;
logger.configure(config);

try logger.addCustomLevel("AUDIT", 25, "35");
try logger.custom("AUDIT", "User action logged");
```

Output:
```json
{
  "timestamp": "2025-01-15 10:30:45.123",
  "level": "AUDIT",
  "message": "User action logged"
}
```

## Custom Levels with File Sinks

Custom levels work with all sink types - console, file (text), and file (JSON):

```zig
// Disable auto console sink
var config = logly.Config.default();
config.auto_sink = false;
logger.configure(config);

// Add file sink for text output
_ = try logger.addSink(.{
    .path = "logs/app.log",
});

// Add JSON file sink
_ = try logger.addSink(.{
    .path = "logs/app.json",
    .json = true,
    .pretty_json = true,
});

// Add console sink
_ = try logger.addSink(.{});

// Register and use custom level
try logger.addCustomLevel("AUDIT", 25, "35");
try logger.custom("AUDIT", "This logs to all three sinks");
```

## Custom Levels with Context

Custom levels support all context features like standard levels:

```zig
var config = logly.Config.default();
config.json = true;
config.pretty_json = true;
logger.configure(config);

// Bind context
try logger.bind("service", .{ .string = "auth-service" });
try logger.bind("user_id", .{ .string = "user-12345" });

try logger.addCustomLevel("AUDIT", 25, "35");
try logger.custom("AUDIT", "User authentication successful");
```

Output:
```json
{
  "timestamp": "2025-01-15 10:30:45.123",
  "level": "AUDIT",
  "message": "User authentication successful",
  "service": "auth-service",
  "user_id": "user-12345"
}
```

## Feature Parity with Standard Levels

Custom levels have **full feature parity** with standard levels:

| Feature | Standard Levels | Custom Levels |
|---------|-----------------|---------------|
| Console output | ✅ | ✅ |
| File output | ✅ | ✅ |
| JSON output | ✅ | ✅ |
| Colored output | ✅ | ✅ (custom colors) |
| Context binding | ✅ | ✅ |
| Formatted messages | ✅ | ✅ |
| Level filtering | ✅ | ✅ (by priority) |
| All sink types | ✅ | ✅ |
