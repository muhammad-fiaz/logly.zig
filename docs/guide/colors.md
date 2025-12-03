# Colors & Styling

Logly-Zig provides comprehensive ANSI color support for console output, with options to enable colors in file output as well.

## Platform Support

| Platform | Color Support | Notes |
|----------|--------------|-------|
| Linux | ✅ Native | Works out of the box |
| macOS | ✅ Native | Works out of the box |
| Windows 10+ | ✅ Requires init | Call `Terminal.enableAnsiColors()` |
| VS Code Terminal | ✅ Full | Works on all platforms |
| Windows Console | ⚠️ Legacy | May need VT processing enabled |

## Enabling Colors

### Windows Setup

On Windows, you must enable ANSI color support at the start of your program:

```zig
const logly = @import("logly");

pub fn main() !void {
    // Enable ANSI colors on Windows (no-op on Linux/macOS)
    _ = logly.Terminal.enableAnsiColors();
    
    // ... rest of your code
}
```

### Check Color Support

```zig
if (logly.Terminal.supportsAnsiColors()) {
    // Terminal supports colors
}
```

## Whole-Line Coloring

Logly colors the **entire log line** (timestamp, level, and message), not just the level tag. This provides better visual scanning:

```
[2024-01-15 10:30:45] [INFO] Application started      <- Entire line white
[2024-01-15 10:30:46] [WARNING] Low disk space        <- Entire line yellow
[2024-01-15 10:30:47] [ERROR] Connection failed       <- Entire line red
```

## Built-in Level Colors

| Level | Priority | ANSI Code | Color | Preview |
|-------|----------|-----------|-------|---------|
| TRACE | 5 | 36 | Cyan | `\x1b[36m` |
| DEBUG | 10 | 34 | Blue | `\x1b[34m` |
| INFO | 20 | 37 | White | `\x1b[37m` |
| SUCCESS | 25 | 32 | Green | `\x1b[32m` |
| WARNING | 30 | 33 | Yellow | `\x1b[33m` |
| ERROR | 40 | 31 | Red | `\x1b[31m` |
| FAIL | 45 | 35 | Magenta | `\x1b[35m` |
| CRITICAL | 50 | 91 | Bright Red | `\x1b[91m` |

## ANSI Color Code Reference

### Basic Colors (Foreground)

| Code | Color |
|------|-------|
| 30 | Black |
| 31 | Red |
| 32 | Green |
| 33 | Yellow |
| 34 | Blue |
| 35 | Magenta |
| 36 | Cyan |
| 37 | White |

### Bright Colors (Foreground)

| Code | Color |
|------|-------|
| 90 | Bright Black (Gray) |
| 91 | Bright Red |
| 92 | Bright Green |
| 93 | Bright Yellow |
| 94 | Bright Blue |
| 95 | Bright Magenta |
| 96 | Bright Cyan |
| 97 | Bright White |

### Background Colors

| Code | Color |
|------|-------|
| 40 | Black Background |
| 41 | Red Background |
| 42 | Green Background |
| 43 | Yellow Background |
| 44 | Blue Background |
| 45 | Magenta Background |
| 46 | Cyan Background |
| 47 | White Background |

### Text Styles

| Code | Style |
|------|-------|
| 0 | Reset |
| 1 | Bold |
| 2 | Dim |
| 3 | Italic |
| 4 | Underline |
| 5 | Blink |
| 7 | Reverse |
| 8 | Hidden |
| 9 | Strikethrough |

### Combining Codes

Combine multiple codes with semicolons:

| Example | Description |
|---------|-------------|
| `"31"` | Red text |
| `"31;1"` | Bold red text |
| `"31;4"` | Underlined red text |
| `"31;1;4"` | Bold underlined red |
| `"97;41"` | White text on red background |
| `"36;1"` | Bold cyan |
| `"33;7"` | Yellow reverse (yellow background, black text) |

## Custom Level Colors

Create custom log levels with your own colors:

```zig
const logly = @import("logly");

pub fn main() !void {
    _ = logly.Terminal.enableAnsiColors();
    
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    
    const logger = try logly.Logger.init(allocator);
    defer logger.deinit();
    
    // Add custom levels with custom colors
    try logger.addCustomLevel("AUDIT", 35, "35");        // Magenta
    try logger.addCustomLevel("NOTICE", 22, "36;1");     // Bold Cyan
    try logger.addCustomLevel("ALERT", 48, "91;1");      // Bold Bright Red
    try logger.addCustomLevel("SECURITY", 55, "97;41"); // White on Red BG
    try logger.addCustomLevel("METRIC", 15, "32;1");     // Bold Green
    
    // Use custom levels
    try logger.custom("AUDIT", "User login event");
    try logger.custom("NOTICE", "Important notice");
    try logger.custom("ALERT", "High CPU usage detected");
    try logger.custom("SECURITY", "Unauthorized access attempt");
    try logger.customf("METRIC", "Response time: {d}ms", .{42});
}
```

## Color Configuration

### Global Color Control

```zig
var config = logly.Config.default();

// Master switch - disables colors everywhere
config.global_color_display = false;
logger.configure(config);

// Re-enable colors
config.global_color_display = true;
config.color = true;
logger.configure(config);
```

### Per-Sink Color Control

```zig
// Console sink with colors (default)
_ = try logger.addSink(.{
    .color = true,  // Explicitly enable colors
});

// File sink without colors (default for files)
_ = try logger.addSink(.{
    .path = "logs/app.log",
    .color = null,  // Auto-detect: false for files
});

// File sink WITH colors (for terminals that read log files)
_ = try logger.addSink(.{
    .path = "logs/colored.log",
    .color = true,  // Force colors in file
});
```

## Colors in Different Output Formats

### Console Output (Default)

Colors are enabled by default for console output:

```zig
try logger.info("White text");      // \x1b[37m...\x1b[0m
try logger.warning("Yellow text");  // \x1b[33m...\x1b[0m
try logger.err("Red text");         // \x1b[31m...\x1b[0m
```

### JSON Output with Colors

JSON output also supports colors when enabled:

```zig
var config = logly.Config.default();
config.json = true;
config.pretty_json = true;
config.color = true;  // Enable colors for JSON
logger.configure(config);

try logger.info("Colored JSON");
try logger.warning("Yellow JSON block");
```

The entire JSON block will be wrapped in the level's color.

### File Output

By default, file sinks disable colors. To enable:

```zig
_ = try logger.addSink(.{
    .path = "logs/colored.log",
    .color = true,  // Enable ANSI codes in file
});
```

**Note:** Files with ANSI codes will display correctly in:
- `cat` command on Linux/macOS
- `less -R` command
- VS Code with ANSI color extensions
- Modern terminal emulators

## Custom Format Strings with Colors

Custom format strings also support colors:

```zig
var config = logly.Config.default();
config.log_format = "{time} | {level} | {message}";
config.color = true;
logger.configure(config);

// Output: \x1b[33m2024-01-15 10:30:45 | WARNING | Message\x1b[0m
try logger.warning("Formatted warning");
```

## Disabling Colors

### For Production/Log Aggregation

```zig
// Disable colors globally
var config = logly.Config.default();
config.color = false;
config.global_color_display = false;
logger.configure(config);
```

### For Specific Sinks

```zig
// JSON file without colors (for log aggregation)
_ = try logger.addSink(.{
    .path = "logs/app.json",
    .json = true,
    .color = false,  // No ANSI codes
});
```

## Complete Example

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    // Enable Windows ANSI support
    _ = logly.Terminal.enableAnsiColors();
    
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const logger = try logly.Logger.init(allocator);
    defer logger.deinit();
    
    // Add custom colored levels
    try logger.addCustomLevel("AUDIT", 35, "35");      // Magenta
    try logger.addCustomLevel("NOTICE", 22, "36;1");   // Bold Cyan
    try logger.addCustomLevel("HIGHLIGHT", 52, "33;7"); // Yellow Reverse
    
    // Standard levels (all colored)
    try logger.trace("Cyan trace message");
    try logger.debug("Blue debug message");
    try logger.info("White info message");
    try logger.success("Green success message");
    try logger.warning("Yellow warning message");
    try logger.err("Red error message");
    try logger.fail("Magenta fail message");
    try logger.critical("Bright red critical message");
    
    // Custom levels
    try logger.custom("AUDIT", "Magenta audit message");
    try logger.custom("NOTICE", "Bold cyan notice");
    try logger.custom("HIGHLIGHT", "Yellow reverse highlight");
    
    // Add file sink with colors
    _ = try logger.addSink(.{
        .path = "logs/colored.log",
        .color = true,
    });
    
    // Add JSON sink without colors
    _ = try logger.addSink(.{
        .path = "logs/app.json",
        .json = true,
        .color = false,
    });
    
    try logger.info("This goes to console (colored) and both files");
}
```
