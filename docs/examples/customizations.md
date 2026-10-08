---
title: Customizations Example
description: Complete example of Logly.zig customizations including global root path, format structure, color customization, and highlighter patterns.
head:
  - - meta
    - name: keywords
      content: customizations, root path, format structure, color customization, highlighters, alerts
  - - meta
    - property: og:title
      content: Customizations Example | Logly.zig
  - - meta
    - property: og:image
      content: https://muhammad-fiaz.github.io/logly.zig/cover.png
---

# Customizations Example

This example demonstrates all of Logly's advanced customization features.

## Features Shown

1. **Global Root Path** - Configure all logs to be stored in a single directory
2. **Format Structure** - Customize message prefixes, suffixes, and field separators
3. **Color Customization** - Define custom ANSI colors for each log level
4. **Highlighters & Alerts** - Configure pattern matching for special handling
5. **Combined Configuration** - Use all features together

## Running the Example

```bash
zig build run-customizations
```

## Code Structure

The example is organized into 6 demonstrations:

### 1. Global Root Path Configuration

```zig
var config = logly.Config.default();
config.logsRootPath = "./logs";

 _ = try logger.addSink(logly.SinkConfig.file("application.log"));
 _ = try logger.addSink(logly.SinkConfig.file("errors.log"));
```

This automatically creates the `./logs` directory and stores both log files there.

**Output:**
```
./logs/
├── application.log
└── errors.log
```

### 2. Format Structure Customization

```zig
config.formatStructure = .{
    .messagePrefix = ">>> ",
    .messageSuffix = " <<<",
    .fieldSeparator = " :: ",
    .enableNesting = true,
};
```

Customizes how messages appear in the output.

### 3. Color Customization Per Level

```zig
config.levelColors = .{
    .infoColor = "\x1b[36m",      // Cyan
    .warningColor = "\x1b[35m",   // Magenta
    .errorColor = "\x1b[31m",     // Red
};
```

Each log level can have a unique color scheme.

### 4. Highlighter Patterns and Alerts

```zig
config.highlighters = .{
    .enabled = true,
    .alertOnMatch = true,
    .alertMinSeverity = .warning,
    .logMatches = true,
};
```

Matches patterns in log messages and triggers alerts.

### 5. Combined Customizations

All features work together seamlessly:

```zig
var configCombined = logly.Config.default();
configCombined.logsRootPath = "./logs";

configCombined.formatStructure = .{
    .messagePrefix = "[APP] ",
    .fieldSeparator = " | ",
    .enableNesting = true,
};

configCombined.levelColors = .{
    .infoColor = "\x1b[34m",
    .warningColor = "\x1b[33m",
    .errorColor = "\x1b[31m",
};

configCombined.highlighters = .{
    .enabled = true,
    .alertOnMatch = true,
    .logMatches = true,
};

const logger = try logly.Logger.initWithConfig(allocator, configCombined);
```

## Expected Output

When you run the example, you'll see:

1. **Section headers** for each customization feature
2. **Formatted log messages** with custom prefixes, suffixes, and colors
3. **Diagnostics information** including OS, CPU, and memory details
4. **File creation** confirmation

Example console output:

```
=== Logly Customizations Example ===

1. Global Root Path Configuration
   Setting logs to be stored in './logs' directory

[2025-12-08 16:36:10.574] [INFO] Application started - logs stored in ./logs directory
[2025-12-08 16:36:10.575] [WARNING] This warning is saved to ./logs/application.log

2. Format Structure Customization
   Customizing log message format with prefix, suffix, and separators

>>> Message with custom format prefix and suffix <<<

3. Color Customization Per Level
   Setting custom colors for each log level

[2025-12-08 16:36:10.575] [INFO] Custom cyan info message
[2025-12-08 16:36:10.575] [WARNING] Custom magenta warning
```

## Generated Files

The example creates the following directory structure:

```
./logs/
├── application.log      # From example 1
├── errors.log           # From example 1
└── combined.log         # From example 6
```

Each file contains the formatted log entries with custom colors (in ANSI format).

## Customization Options Reference

| Feature | Config Field | Purpose |
|---------|-------------|---------|
| Root Path | `logsRootPath` | Set directory for all file sinks |
| Format | `formatStructure` | Customize message structure |
| Colors | `levelColors` | Per-level ANSI color codes |
| Highlighters | `highlighters` | Pattern matching & alerts |

## Use Cases

**Development:**
```zig
config.logsRootPath = "./dev_logs";
config.formatStructure.messagePrefix = "[DEV] ";
config.highlighters.enabled = true;
```

**Production:**
```zig
config.logsRootPath = "/var/log/myapp";
config.levelColors.criticalColor = "\x1b[1;31m";
```

**Testing:**
```zig
config.logsRootPath = "./test_output";
config.highlighters.logMatches = true;
```

## Learning Resources

- **Guide:** See `docs/guide/customizations.md` for detailed usage
- **API Reference:** See `docs/api/customizations.md` for complete API docs
- **Full Example:** Check `examples/customizations.zig` for the complete source code
