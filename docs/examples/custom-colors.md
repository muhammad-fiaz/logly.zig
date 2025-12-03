# Custom Colors

This example demonstrates how to define and use custom colors for log levels. Logly colors the **entire log line** (timestamp, level, and message), not just the level tag.

## Platform Support

Logly supports ANSI colors on:
- **Linux**: Native support
- **macOS**: Native support
- **Windows 10+**: Enabled via `Terminal.enableAnsiColors()`
- **VS Code Terminal**: Full support

## Code Example

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Enable ANSI colors on Windows (no-op on Linux/macOS)
    _ = logly.Terminal.enableAnsiColors();

    const logger = try logly.Logger.init(allocator);
    defer logger.deinit();

    // Define custom levels with specific colors
    // Format: "FG;BG;STYLE" or just "FG"
    // Colors: 30=Black, 31=Red, 32=Green, 33=Yellow, 34=Blue, 35=Magenta, 36=Cyan, 37=White
    // Bright: 90-97 for bright versions (e.g., 91=Bright Red)
    // Styles: 1=Bold, 4=Underline, 7=Reverse

    try logger.addCustomLevel("NOTICE", 22, "36;1");    // Cyan Bold
    try logger.addCustomLevel("ALERT", 42, "31;4");     // Red Underline
    try logger.addCustomLevel("HIGHLIGHT", 52, "33;7"); // Yellow Reverse

    // Standard levels (entire line colored):
    try logger.info("Info message - entire line is white");
    try logger.success("Success message - entire line is green");
    try logger.warning("Warning message - entire line is yellow");
    try logger.err("Error message - entire line is red");

    // Custom levels (entire line colored with custom colors):
    try logger.custom("NOTICE", "Notice message - entire line cyan bold");
    try logger.custom("ALERT", "Alert message - entire line red underline");
    try logger.custom("HIGHLIGHT", "Highlighted - entire line yellow reverse");
}
```

## Standard Level Colors

| Level    | ANSI Code | Color           |
|----------|-----------|-----------------|
| TRACE    | 36        | Cyan            |
| DEBUG    | 34        | Blue            |
| INFO     | 37        | White           |
| SUCCESS  | 32        | Green           |
| WARNING  | 33        | Yellow          |
| ERROR    | 31        | Red             |
| FAIL     | 35        | Magenta         |
| CRITICAL | 91        | Bright Red      |

## Expected Output

```text
[2025-01-01 12:00:00.000] [INFO] Info message - entire line is white
[2025-01-01 12:00:00.000] [SUCCESS] Success message - entire line is green
[2025-01-01 12:00:00.000] [WARNING] Warning message - entire line is yellow
[2025-01-01 12:00:00.000] [ERROR] Error message - entire line is red
[2025-01-01 12:00:00.000] [NOTICE] Notice message - entire line cyan bold
[2025-01-01 12:00:00.000] [ALERT] Alert message - entire line red underline
[2025-01-01 12:00:00.000] [HIGHLIGHT] Highlighted - entire line yellow reverse
```
