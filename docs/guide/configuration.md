# Configuration

Logly-Zig offers a comprehensive and flexible configuration system, allowing you to tailor every aspect of the logging behavior to your application's needs.

## Basic Configuration

The `Config` struct is the primary interface for global settings. You can start with a default configuration and modify it as needed.

```zig
var config = logly.Config.default();

// 🎚️ Global controls
config.global_color_display = true;
config.global_console_display = true;
config.global_file_storage = true;

// 🔍 Log level
config.level = .debug;

// 👁️ Display options
config.show_time = true;
config.show_module = true;
config.show_function = false;
config.show_filename = true; // Useful for debugging
config.show_lineno = true;   // Pinpoint the exact line
config.include_hostname = true; // Add hostname to logs
config.include_pid = true;      // Add process ID

// 📝 Output format
config.json = false;
config.pretty_json = false;
config.color = true;

// ⚡ Features
config.enable_callbacks = true;
config.enable_exception_handling = true;

logger.configure(config);
```

## Configuration Options

| Option                   | Type          | Default                 | Description                                          |
| :----------------------- | :------------ | :---------------------- | :--------------------------------------------------- |
| `level`                  | `Level`       | `.info`                 | Minimum log level to output.                         |
| `global_color_display`   | `bool`        | `true`                  | Globally enable/disable colored output.              |
| `global_console_display` | `bool`        | `true`                  | Globally enable/disable console output.              |
| `global_file_storage`    | `bool`        | `true`                  | Globally enable/disable file output.                 |
| `json`                   | `bool`        | `false`                 | Format logs as JSON objects.                         |
| `pretty_json`            | `bool`        | `false`                 | Pretty-print JSON output (indented).                 |
| `color`                  | `bool`        | `true`                  | Enable ANSI color codes.                             |
| `show_time`              | `bool`        | `true`                  | Include timestamp in log output.                     |
| `show_module`            | `bool`        | `true`                  | Include the module name.                             |
| `show_function`          | `bool`        | `false`                 | Include the function name.                           |
| `show_filename`          | `bool`        | `false`                 | Include the source filename.                         |
| `show_lineno`            | `bool`        | `false`                 | Include the source line number.                      |
| `include_hostname`       | `bool`        | `false`                 | Include the system hostname.                         |
| `include_pid`            | `bool`        | `false`                 | Include the process ID.                              |
| `show_lineno`            | `bool`        | `false`                 | Show line number                                     |
| `auto_sink`              | `bool`        | `true`                  | Automatically add a console sink on init             |
| `enable_callbacks`       | `bool`        | `true`                  | Enable log callbacks                                 |
| `log_format`             | `?[]const u8` | `null`                  | Custom log format string (e.g. `"{time} {message}"`) |
| `time_format`            | `[]const u8`  | `"YYYY-MM-DD HH:mm:ss"` | Timestamp format                                     |
| `timezone`               | `enum`        | `.Local`                | Timezone for timestamps (`.Local` or `.UTC`)         |

## Advanced Configuration

### Custom Log Format

You can customize the log output format using the `log_format` option. The following placeholders are supported:

- `{time}`: Timestamp
- `{level}`: Log level
- `{message}`: Log message
- `{module}`: Module name
- `{function}`: Function name
- `{file}`: Filename (clickable in supported terminals)
- `{line}`: Line number

```zig
config.log_format = "{time} | {level} | {message}";
```

### Clickable Links

To enable clickable file links in your terminal (like VS Code), enable filename and line number display:

```zig
config.show_filename = true;
config.show_lineno = true;
```

This will output the location in `path/to/file:line` format.

### Time Configuration

You can configure the timestamp format and timezone:

```zig
config.time_format = "unix"; // or default
config.timezone = .UTC;      // or .Local
```
