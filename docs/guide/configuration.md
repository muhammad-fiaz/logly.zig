# Configuration

Logly-Zig provides a flexible configuration system to customize every aspect of logging.

## Basic Configuration

```zig
var config = logly.Config.default();

// Global controls
config.global_color_display = true;
config.global_console_display = true;
config.global_file_storage = true;

// Log level
config.level = .debug;

// Display options
config.show_time = true;
config.show_module = true;
config.show_function = false;
config.show_filename = false;
config.show_lineno = false;

// Output format
config.json = false;
config.color = true;

// Features
config.enable_callbacks = true;
config.enable_exception_handling = true;

logger.configure(config);
```

## Configuration Options

| Option | Type | Default | Description |
| ~ | ~ | ~ | ~ |
| `level` | `Level` | `.info` | Minimum log level to output |
| `global_color_display` | `bool` | `true` | Enable colored output globally |
| `global_console_display` | `bool` | `true` | Enable console output globally |
| `global_file_storage` | `bool` | `true` | Enable file output globally |
| `json` | `bool` | `false` | Output logs in JSON format |
| `pretty_json` | `bool` | `false` | Pretty print JSON output |
| `color` | `bool` | `true` | Enable ANSI colors |
| `show_time` | `bool` | `true` | Show timestamp in logs |
| `show_module` | `bool` | `true` | Show module name |
| `show_function` | `bool` | `false` | Show function name |
| `show_filename` | `bool` | `false` | Show filename |
| `show_lineno` | `bool` | `false` | Show line number |
| `auto_sink` | `bool` | `true` | Automatically add a console sink on init |
| `enable_callbacks` | `bool` | `true` | Enable log callbacks |
