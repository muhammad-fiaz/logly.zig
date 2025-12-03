# Color Control Example

This example demonstrates comprehensive control over ANSI color output at global and per-sink levels, including Windows support and custom colors.

## Enable Colors on Windows

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    // IMPORTANT: Call this first on Windows for color support
    // This enables Virtual Terminal Processing
    // No-op on Linux/macOS
    _ = logly.Terminal.enableAnsiColors();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const logger = try logly.Logger.init(allocator);
    defer logger.deinit();

    // Colors now work on Windows!
    try logger.info("Colored output on all platforms");
    try logger.success("Green success message");
    try logger.warning("Yellow warning message");
    try logger.err("Red error message");
}
```

## Global Color Control

```zig
const logger = try logly.Logger.init(allocator);
defer logger.deinit();

var config = logly.Config.default();

// Master switch - disables colors everywhere
config.global_color_display = false;
logger.configure(config);

// All output will be plain text (no ANSI codes)
try logger.info("No colors here");
try logger.warning("Still no colors");

// Re-enable colors
config.global_color_display = true;
config.color = true;
logger.configure(config);

try logger.success("Colors are back!");
```

## Per-Sink Color Control

```zig
const logger = try logly.Logger.init(allocator);
defer logger.deinit();

var config = logly.Config.default();
config.auto_sink = false;  // Don't create default console sink
logger.configure(config);

// Console sink WITH colors (entire line colored)
_ = try logger.addSink(.{
    .name = "console",
    .color = true,
});

// File sink WITHOUT colors (no ANSI codes in file)
_ = try logger.addSink(.{
    .path = "logs/app.log",
    .color = false,
});

// JSON file sink (colors never apply to JSON)
_ = try logger.addSink(.{
    .path = "logs/app.json",
    .json = true,
    .color = false,
});

// Console shows colored output, files are plain text
try logger.info("Console: colored, File: plain text");
try logger.err("Error appears red on console only");
```

## Sink-Specific Level Filtering

```zig
// Console: all levels
_ = try logger.addSink(.{
    .color = true,
});

// Error file: only errors and above
_ = try logger.addSink(.{
    .path = "logs/errors.log",
    .level = .err,
    .color = false,
});

// Debug file: only debug and trace
_ = try logger.addSink(.{
    .path = "logs/debug.log",
    .level = .trace,
    .max_level = .debug,
    .color = false,
});
```

## Custom Level Colors

```zig
// Enable colors first
_ = logly.Terminal.enableAnsiColors();

const logger = try logly.Logger.init(allocator);
defer logger.deinit();

// Define custom levels with specific colors
// Format: (name, priority, color_code)
try logger.addCustomLevel("AUDIT", 35, "35");        // Magenta
try logger.addCustomLevel("NOTICE", 22, "36;1");    // Bold Cyan
try logger.addCustomLevel("ALERT", 48, "91;1");     // Bold Bright Red
try logger.addCustomLevel("SECURITY", 55, "31;4");  // Underline Red
try logger.addCustomLevel("HIGHLIGHT", 28, "33;7"); // Reverse Yellow

// Use custom levels - entire line gets the custom color
try logger.custom("AUDIT", "Security audit event");
try logger.custom("NOTICE", "Important notice");
try logger.custom("ALERT", "System alert!");
try logger.custom("SECURITY", "Unauthorized access attempt");
try logger.customf("HIGHLIGHT", "User {s} action", .{"admin"});
```

## Color Code Reference

### Basic Colors

| Color | Code | Description |
|-------|------|-------------|
| Black | 30 | Dark text |
| Red | 31 | Errors |
| Green | 32 | Success |
| Yellow | 33 | Warnings |
| Blue | 34 | Debug |
| Magenta | 35 | Custom/Audit |
| Cyan | 36 | Trace |
| White | 37 | Info |

### Bright Colors

| Color | Code | Description |
|-------|------|-------------|
| Bright Red | 91 | Critical |
| Bright Green | 92 | Highlight success |
| Bright Yellow | 93 | Important warning |
| Bright Blue | 94 | Highlight debug |
| Bright Magenta | 95 | Special |
| Bright Cyan | 96 | Highlight trace |
| Bright White | 97 | Emphasis |

### Modifiers

Combine with semicolons:

| Modifier | Code | Example | Result |
|----------|------|---------|--------|
| Bold | 1 | `31;1` | Bold Red |
| Underline | 4 | `34;4` | Underline Blue |
| Reverse | 7 | `32;7` | Reverse Green |

## Built-in Level Colors

| Level | Color | Code |
|-------|-------|------|
| TRACE | Cyan | 36 |
| DEBUG | Blue | 34 |
| INFO | White | 37 |
| SUCCESS | Green | 32 |
| WARNING | Yellow | 33 |
| ERROR | Red | 31 |
| FAIL | Magenta | 35 |
| CRITICAL | Bright Red | 91 |

## JSON with Custom Levels

Custom level names appear in JSON output:

```zig
var config = logly.Config.default();
config.json = true;
config.pretty_json = true;
logger.configure(config);

try logger.addCustomLevel("AUDIT", 35, "35");
try logger.custom("AUDIT", "Login event");
```

Output:
```json
{
  "timestamp": "2024-01-15 10:30:45.000",
  "level": "AUDIT",
  "message": "Login event"
}
```

## Complete Example

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Enable Windows color support
    _ = logly.Terminal.enableAnsiColors();

    const logger = try logly.Logger.init(allocator);
    defer logger.deinit();

    // Add custom levels
    try logger.addCustomLevel("AUDIT", 35, "35;1");
    try logger.addCustomLevel("SECURITY", 55, "91;4");

    // Standard levels (whole line colored)
    try logger.trace("Cyan trace line");
    try logger.debug("Blue debug line");
    try logger.info("White info line");
    try logger.success("Green success line");
    try logger.warning("Yellow warning line");
    try logger.err("Red error line");
    try logger.critical("Bright red critical line");

    // Custom levels
    try logger.custom("AUDIT", "Bold magenta audit line");
    try logger.custom("SECURITY", "Underline bright red security line");

    // Disable colors for comparison
    var config = logly.Config.default();
    config.global_color_display = false;
    logger.configure(config);

    try logger.info("Plain text - no colors");

    std.debug.print("\nColor control example completed!\n", .{});
}
```

```zig
const is_tty = std.io.getStdOut().isTty();
const force_no_color = std.process.getEnvVarOwned(allocator, "NO_COLOR") catch null;

var config = logly.Config.default();
config.color = is_tty and force_no_color == null;
```

## Color Levels

| Level | Default Color |
|-------|--------------|
| trace | Gray |
| debug | Blue |
| info | Green |
| success | Bright Green |
| warning | Yellow |
| error | Red |
| fail | Bright Red |
| critical | Red on White |

## Custom Colors

See the [Custom Colors](/examples/custom-colors) example for changing level colors.

## Best Practices

1. **Auto-detect for terminals** - Use `null` for automatic TTY detection
2. **Disable for files** - Unless using ANSI-capable viewers
3. **Never color JSON** - Breaks parsing
4. **Respect NO_COLOR** - Honor the [NO_COLOR](https://no-color.org/) environment variable
5. **Test both modes** - Ensure logs are readable with and without colors
