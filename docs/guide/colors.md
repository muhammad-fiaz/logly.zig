---
title: Colors and Styling
description: Master ANSI color support in Logly.zig. Learn about whole-line coloring, custom level colors, and enabling colors on Windows, Linux, and macOS.
head:
  - - meta
    - name: keywords
      content: colors, styling, ansi codes, terminal colors, windows colors, custom colors, log formatting
  - - meta
    - property: og:title
      content: Colors and Styling | Logly.zig
  - - meta
    - property: og:image
      content: https://muhammad-fiaz.github.io/logly.zig/cover.png
---

# Colors & Styling

Logly colors console output via tint.zig. Two rendering modes plus off:

```zig
var config = logly.Config.default();
config.colorMode = .horizontal; // whole record in level color (default)
config.colorMode = .vertical;   // per-column colors (below)
config.colorMode = .none;       // plain text
```

## Horizontal

One level color for the complete record (existing whole-line behavior).

```text
[entire log record uses one level color]
2026-10-07 12:00:00 [INFO] Application started
```

## Vertical

Independent colors per field. Unset columns render uncolored; `level`
falls back to the resolved level color.

```zig
config.columnColors.timestamp = logly.Color.Tint.color.ansi4.blue;
config.columnColors.message = logly.Color.Tint.color.ansi4.yellow;
```

```text
[timestamp: blue] [level: green] [message: yellow]
2026-10-07 12:00:00 [INFO] Application started
```

Precedence: `color`/`globalColorDisplay` off wins first, then `colorMode`,
then column colors, then level colors, then defaults. Multiline messages
keep the color across lines with a trailing reset; every field reset
prevents leakage into later output.

## Format Color Policy

Serialization is always valid on its own; color is a presentation layer
applied afterwards, never inside the data. All rendering goes through
`tint.zig` — Logly keeps no second ANSI implementation.

| Format | No color | Horizontal | Vertical |
|---|---|---|---|
| `text`, `logfmt` | plain | whole record in level color | per-field column colors |
| `json`, `ndjson` | plain valid JSON | whole rendered line wrapped | JSON re-rendered with per-key colors |
| `syslog`, `syslog3164` | plain | whole rendered line wrapped | whole rendered line wrapped |
| `msgpack` | raw bytes | unsupported (bytes stay raw) | unsupported (bytes stay raw) |
| custom template | plain | whole-line wrap | per-field spans |

Stripping ANSI from any colored text/JSON/syslog output recovers the exact
uncolored bytes. `msgpack` output never contains color under any setting.

Per-sink selection: set `.color = true` to force presentation color even
when piped, `.color = false` to disable, or leave `null` for automatic
behavior (colored on interactive terminals, plain otherwise). A `text`
console plus a plain JSON file plus a binary network sink can share one
record without interfering, because presentation is computed per sink
from the same record.

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
    
    var gpa = std.heap.DebugAllocator(.{}){};
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
    try logger.custom("AUDIT", "User login event", @src());
    try logger.custom("NOTICE", "Important notice", @src());
    try logger.custom("ALERT", "High CPU usage detected", @src());
    try logger.custom("SECURITY", "Unauthorized access attempt", @src());
    try logger.customf("METRIC", "Response time: {d}ms", .{42}, @src());
}
```

## Enhanced Color Options (v0.1.8)

### Level Colors

Each log level has a default tint color. `Level.defaultColor()` returns a
tint `Color` value; render it to an SGR sequence when writing output:

```zig
const Level = logly.Level;

// Default color as a tint Color value.
const traceColor = Level.trace.defaultColor();

// Render to an escape sequence for output.
const seq = logly.Color.sequence(traceColor, .trueColor);
// seq.slice() gives e.g. "\x1b[36m" for trace.
```

### tint Colors

All terminal colors come from tint.zig via `logly.Color`:

```zig
const tint = logly.Color.Tint;

// Named ANSI colors.
const red = tint.color.ansi4.red;
const brightRed = tint.color.ansi4.brightRed;

// 256-color palette.
const orange = tint.color.ansi256.index(208);

// RGB colors.
const coral = tint.color.rgb(255, 127, 80);

// Render any color to a sequence.
const seq = logly.Color.sequence(red, .trueColor);
```

Parse user-supplied text (names, `#rrggbb`, or SGR params) with
`logly.Color.parse`:

```zig
const magenta = logly.Color.parse("magenta").?;
const custom = logly.Color.parse("38;5;196").?;
```

### Theme Presets

Logly includes multiple color theme presets built on tint colors:

```zig
const Formatter = logly.Formatter;

// Use preset themes (each field is a tint Color).
const defaultTheme = Formatter.Theme{};           // Standard colors
const brightTheme = Formatter.Theme.bright();     // Bright colors
const dimTheme = Formatter.Theme.dim();           // Dim colors
const minimalTheme = Formatter.Theme.minimal();   // Subtle grays
const neonTheme = Formatter.Theme.neon();         // Vivid 256-colors
const pastelTheme = Formatter.Theme.pastel();     // Soft colors
const darkTheme = Formatter.Theme.dark();         // Dark terminal optimized
const lightTheme = Formatter.Theme.light();       // Light terminal optimized

// Apply theme to formatter
var formatter = Formatter.init(allocator);
formatter.setTheme(Formatter.Theme.neon());
```

### Custom Themes

Define per-level tint colors directly:

```zig
const Theme = logly.Formatter.Theme;
const custom = Theme{
    .trace = logly.Color.parse("cyan").?,
    .err = logly.Color.Tint.color.rgb(255, 80, 80),
};
formatter.setTheme(custom);
```

  ### Advanced CustomLevel Options

  Create custom levels with full tint color control:

  ```zig
  const CustomLevel = logly.CustomLevel;

  // Basic custom level with a tint color
  const audit = CustomLevel.init("AUDIT", 35, logly.Color.parse("cyan").?);

  // Styled custom level (explicit tint style)
  const styled = CustomLevel.initStyled("STYLED", 45, .{
      .foreground = logly.Color.Tint.color.red,
      .underline = true,
  });

  // With background color
  const alert = CustomLevel.initWithBackground(
      "ALERT", 50,
      logly.Color.Tint.color.ansi4.brightWhite,
      logly.Color.Tint.color.ansi4.red,
  );
  ```

## Color Configuration

### Global Color Control

```zig
var config = logly.Config.default();

// Master switch - disables colors everywhere
config.globalColorDisplay = false;
logger.configure(config);

// Re-enable colors
config.globalColorDisplay = true;
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

### JSON Output Is Never Colored

Serialization formats never contain ANSI sequences, even with colors
enabled — color is a presentation concern for human-readable text only:

```zig
var config = logly.Config.default();
config.format = .json;
config.color = true; // Has no effect on JSON output
logger.configure(config);

try logger.info("Plain JSON object, no escape codes");
```

Color applies to `text` and `logfmt` output. `json`, `ndjson`, `syslog`,
`syslog3164`, and `msgpack` output is always plain.

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
config.logFormat = "{time} | {level} | {message}";
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
config.globalColorDisplay = false;
logger.configure(config);
```

### For Specific Sinks

```zig
// JSON file without colors (for log aggregation)
 _ = try logger.addSink(.{
    .path = "logs/app.json",
    .format = .json,
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
    
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const logger = try logly.Logger.init(allocator);
    defer logger.deinit();
    
      // Add custom colored levels (tint colors)
      try logger.addCustomLevel("AUDIT", 35, logly.Color.parse("magenta").?);
      try logger.addCustomLevel("NOTICE", 22, logly.Color.parse("cyan").?);
      try logger.addCustomLevel("HIGHLIGHT", 52, logly.Color.parse("yellow").?);
    
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
        .format = .json,
        .color = false,
    });
    
    try logger.info("This goes to console (colored) and both files");
}
```

## Structured formats and presentation

Color never corrupts serialized data. For `json`, `ndjson`, `syslog`, and
`syslog3164` the record is serialized first and color is applied *around* the
result, so stripping ANSI recovers the exact document — `PRI`, timestamp,
hostname, and structured data included.

| Format | No color | Horizontal | Vertical | Custom / level colors |
|--------|:--------:|:----------:|:--------:|:---------------------:|
| `text` | yes | yes | yes | yes |
| `logfmt` | yes | yes | yes | yes |
| `json` | yes | yes | yes | yes |
| `ndjson` | yes | yes | yes | yes |
| `syslog` / `syslog3164` | yes | yes | whole-record | yes |
| `msgpack` | yes | presentation only | presentation only | presentation only |

A JSON file sink writes a single array document (`[`, records, `]`), so a
colored record is wrapped inside the array and the file stays valid JSON.

`msgpack` is never colored. Binary payloads stay byte-exact: no ANSI, no
trailing newline, and length-prefixed framing is preserved.

## Color is per sink

Each sink decides independently whether to present color, so enabling
console color never injects ANSI into a file or network sink.

| Target | Default | How to enable |
|--------|---------|---------------|
| Console | Auto | Colored when stdout is a TTY; plain when piped, redirected, or in CI |
| File | Off | `color = true` |
| Network | Off | `color = true` |
| MessagePack | Never | Not supported |

```zig
_ = try logger.addSink(.{ .name = "console", .color = true });
_ = try logger.addSink(.{ .path = "logs/app.log", .color = false });
_ = try logger.addSink(.{ .path = "logs/app.json", .format = .json, .color = false });
```

## Async logging

Async mode queues the uncolored serialized record together with its resolved
level color. Presentation is applied per sink at write time, which means
background workers cannot push console color into files or network sinks, and
ANSI sequences cannot interleave between records from different workers.

See [Async](/guide/async) for the queue and worker model.
