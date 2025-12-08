# Customizations Example

This example demonstrates all of Logly's advanced customization features.

## Features Shown

1. **Global Root Path** - Configure all logs to be stored in a single directory
2. **Format Structure** - Customize message prefixes, suffixes, and field separators
3. **Color Customization** - Define custom ANSI colors for each log level
4. **Diagnostics Logging** - Emit system diagnostics with structured data
5. **Highlighters & Alerts** - Configure pattern matching for special handling
6. **Combined Configuration** - Use all features together

## Running the Example

```bash
zig build run-customizations
```

## Code Structure

The example is organized into 6 demonstrations:

### 1. Global Root Path Configuration

```zig
var config = logly.Config.default();
config.logs_root_path = "./logs";

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
config.format_structure = .{
    .message_prefix = ">>> ",
    .message_suffix = " <<<",
    .field_separator = " :: ",
    .enable_nesting = true,
};
```

Customizes how messages appear in the output.

### 3. Color Customization Per Level

```zig
config.level_colors = .{
    .info_color = "\x1b[36m",      // Cyan
    .warning_color = "\x1b[35m",   // Magenta
    .error_color = "\x1b[31m",     // Red
};
```

Each log level can have a unique color scheme.

### 4. Diagnostics Custom Path

```zig
config.diagnostics_output_path = "./diagnostics/system_info.log";
config.logs_root_path = "./logs";
config.emit_system_diagnostics_on_init = true;
```

System information is logged with structured fields available for custom formats.

### 5. Highlighter Patterns and Alerts

```zig
config.highlighters = .{
    .enabled = true,
    .alert_on_match = true,
    .alert_min_severity = .warning,
    .log_matches = true,
};
```

Matches patterns in log messages and triggers alerts.

### 6. Combined Customizations

All features work together seamlessly:

```zig
var config_combined = logly.Config.default();
config_combined.logs_root_path = "./logs";
config_combined.diagnostics_output_path = "./logs/diagnostics.log";
config_combined.emit_system_diagnostics_on_init = true;

config_combined.format_structure = .{
    .message_prefix = "[APP] ",
    .field_separator = " | ",
    .enable_nesting = true,
};

config_combined.level_colors = .{
    .info_color = "\x1b[34m",
    .warning_color = "\x1b[33m",
    .error_color = "\x1b[31m",
};

config_combined.highlighters = .{
    .enabled = true,
    .alert_on_match = true,
    .log_matches = true,
};

const logger = try logly.Logger.initWithConfig(allocator, config_combined);
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

./diagnostics/
└── system_info.log      # From example 4 (if configured)
```

Each file contains the formatted log entries with custom colors (in ANSI format).

## Customization Options Reference

| Feature | Config Field | Purpose |
|---------|-------------|---------|
| Root Path | `logs_root_path` | Set directory for all file sinks |
| Format | `format_structure` | Customize message structure |
| Colors | `level_colors` | Per-level ANSI color codes |
| Diagnostics Path | `diagnostics_output_path` | Custom diagnostics file location |
| Highlighters | `highlighters` | Pattern matching & alerts |

## Use Cases

**Development:**
```zig
config.logs_root_path = "./dev_logs";
config.format_structure.message_prefix = "[DEV] ";
config.highlighters.enabled = true;
```

**Production:**
```zig
config.logs_root_path = "/var/log/myapp";
config.level_colors.critical_color = "\x1b[1;31m";
config.diagnostics_output_path = "/var/log/myapp/system.log";
```

**Testing:**
```zig
config.logs_root_path = "./test_output";
config.highlighters.log_matches = true;
config.emit_system_diagnostics_on_init = true;
```

## Learning Resources

- **Guide:** See `docs/guide/customizations.md` for detailed usage
- **API Reference:** See `docs/api/customizations.md` for complete API docs
- **Full Example:** Check `examples/customizations.zig` for the complete source code
