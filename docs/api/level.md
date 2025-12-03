# Level API

The `Level` enum defines the standard log levels with numeric priorities and colors.

## Overview

Log levels control which messages are processed and help filter output based on severity. Higher priority numbers indicate more severe conditions. Each level has an associated ANSI color for console output.

## Enum Values with Colors

| Level | Priority | Color Code | Color | Description |
|-------|----------|------------|-------|-------------|
| `trace` | 5 | 36 | Cyan | Very detailed debugging information |
| `debug` | 10 | 34 | Blue | Debugging information for development |
| `info` | 20 | 37 | White | General informational messages |
| `success` | 25 | 32 | Green | Successful operation confirmations |
| `warning` | 30 | 33 | Yellow | Warning messages indicating potential issues |
| `err` | 40 | 31 | Red | Error conditions that should be addressed |
| `fail` | 45 | 35 | Magenta | Operation failures that may be recoverable |
| `critical` | 50 | 91 | Bright Red | Critical system errors requiring immediate attention |

### Whole-Line Coloring

Logly colors the **entire log line** including timestamp, level tag, and message:

```
\x1b[33m[2024-01-15 10:30:45] [WARNING] Disk space low\x1b[0m
```

This provides better visual separation between log levels in console output.

## Methods

### `priority() u8`

Returns the numeric priority of the level.

```zig
const level = Level.warning;
const p = level.priority(); // Returns 30
```

### `asString() []const u8`

Returns the uppercase string representation of the level.

```zig
const level = Level.err;
const name = level.asString(); // Returns "ERR"
```

### `color() []const u8`

Returns the ANSI color code for the level.

```zig
const level = Level.warning;
const c = level.color(); // Returns "33"
```

## Custom Levels

Create custom log levels with their own priority, name, and color:

```zig
// Add a custom "AUDIT" level with priority 35 and purple color
try logger.addCustomLevel("audit", 35, "35");  // "35" = magenta

// Use the custom level
try logger.custom("audit", "User login detected");
// Output: [2024-01-15 10:30:45] [AUDIT] User login detected (in magenta)
```

### Custom Level Colors

You can use any ANSI color code or combination:

| Code | Color | Example |
|------|-------|---------|
| `31` | Red | Error messages |
| `32` | Green | Success indicators |
| `33` | Yellow | Warnings |
| `34` | Blue | Debug info |
| `35` | Magenta | Custom/audit |
| `36` | Cyan | Trace/verbose |
| `37` | White | Standard info |
| `91` | Bright Red | Critical |
| `92` | Bright Green | Highlights |
| `93` | Bright Yellow | Important |

### Color Modifiers

Combine colors with modifiers using semicolons:

```zig
try logger.addCustomLevel("alert", 42, "31;1");     // Bold red
try logger.addCustomLevel("notice", 22, "36;4");    // Underline cyan
try logger.addCustomLevel("highlight", 38, "33;7"); // Reverse yellow
```

| Modifier | Code | Effect |
|----------|------|--------|
| Bold | `1` | `31;1` = bold red |
| Underline | `4` | `34;4` = underline blue |
| Reverse | `7` | `32;7` = reverse green |

## Level Filtering

### Global Level Filter

Set the minimum log level globally:

```zig
var config = Config.default();
config.level = .warning; // Only warning and above
logger.configure(config);
```

### Per-Sink Level Filter

Each sink can have its own level filter:

```zig
_ = try logger.addSink(.{
    .level = .err,      // Minimum level
    .max_level = .fail, // Maximum level (optional)
});
```

### Module-Level Filtering

Set different log levels for different modules:

```zig
try logger.setModuleLevel("database", .debug);
try logger.setModuleLevel("http", .warning);
```

## Windows Support

On Windows, enable ANSI colors at application startup:

```zig
_ = logly.Terminal.enableAnsiColors();
```

This enables Virtual Terminal Processing for proper color display. No-op on Linux/macOS.
