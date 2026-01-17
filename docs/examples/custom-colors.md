---
title: Custom Colors Example
description: Example of defining custom ANSI colors for log levels in Logly.zig. Create bold, underlined, and reverse color effects for custom log levels.
head:
  - - meta
    - name: keywords
      content: custom colors, ansi codes, log colors, color levels, bold text, underline, color themes
  - - meta
    - property: og:title
      content: Custom Colors Example | Logly.zig
  - - meta
    - property: og:image
      content: https://muhammad-fiaz.github.io/logly.zig/cover.png
---

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
    try logger.info("Info message - entire line is white", @src());
    try logger.success("Success message - entire line is green", @src());
    try logger.warn("Warning message - entire line is yellow", @src());  // Short alias
    try logger.err("Error message - entire line is red", @src());

    // Custom levels (entire line colored with custom colors):
    try logger.custom("NOTICE", "Notice message - entire line cyan bold", @src());
    try logger.custom("ALERT", "Alert message - entire line red underline", @src());
    try logger.custom("HIGHLIGHT", "Highlighted - entire line yellow reverse", @src());
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

## Color Variants (v0.1.5)

Each level now supports multiple color variants:

| Level    | Default | Bright    | Dim   | 256-Color   |
|----------|---------|-----------|-------|-------------|
| TRACE    | 36      | 96;1      | 36;2  | 38;5;51     |
| DEBUG    | 34      | 94;1      | 34;2  | 38;5;33     |
| INFO     | 37      | 97;1      | 37;2  | 38;5;252    |
| SUCCESS  | 32      | 92;1      | 32;2  | 38;5;46     |
| WARNING  | 33      | 93;1      | 33;2  | 38;5;226    |
| ERROR    | 31      | 91;1      | 31;2  | 38;5;196    |
| FAIL     | 35      | 95;1      | 35;2  | 38;5;201    |
| CRITICAL | 91      | 91;1;4    | 91;2  | 38;5;196;1  |

## Theme Presets

Use built-in theme presets:

```zig
const Formatter = logly.Formatter;

// Available themes
const default_theme = Formatter.Theme{};         // Standard colors
const bright = Formatter.Theme.bright();         // Bold/bright colors
const dim = Formatter.Theme.dim();               // Dim colors
const minimal = Formatter.Theme.minimal();       // Subtle grays
const neon = Formatter.Theme.neon();             // Vivid 256-colors
const pastel = Formatter.Theme.pastel();         // Soft colors
const dark = Formatter.Theme.dark();             // Dark terminal optimized
const light = Formatter.Theme.light();           // Light terminal optimized
```

## Extended 256-Color Example

```zig
const Colors = logly.Constants.Colors;

// Use 256-color palette
const orange = Colors.fg256(208);      // "38;5;208"
const pink = Colors.fg256(213);        // "38;5;213"
const teal = Colors.fg256(43);         // "38;5;43"
const purple_bg = Colors.bg256(141);   // "48;5;141"

// Create custom level with 256 colors
try logger.addCustomLevel("NOTICE", 22, Colors.fg256(81));
try logger.addCustomLevel("AUDIT", 35, Colors.fg256(214));
```

## RGB Color Example

```zig
const Colors = logly.Constants.Colors;

// Define colors with RGB values
const coral = Colors.fgRgb(255, 127, 80);    // "38;2;255;127;80"
const navy_bg = Colors.bgRgb(0, 0, 128);     // "48;2;0;0;128"
const lime = Colors.fgRgb(50, 205, 50);      // "38;2;50;205;50"
```

## Advanced CustomLevel

```zig
const CustomLevel = logly.CustomLevel;

// Full color control
const audit = CustomLevel.initFull(
    "AUDIT",        // name
    35,             // priority
    "36",           // base color (cyan)
    "96;1",         // bright color (bright cyan bold)
    "36;2",         // dim color
    "38;5;81",      // 256-color
);

// RGB custom level
const metric = CustomLevel.initRgb("METRIC", 25, 50, 205, 50);

// With background
const alert = CustomLevel.initWithBackground("ALERT", 50, "97", "41");

// With style
const security = CustomLevel.initStyled("SECURITY", 55, "31", "1;4");
```

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
