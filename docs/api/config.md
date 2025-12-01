# Config API

The `Config` struct controls the behavior of the logger.

## Fields

### `level: Level`

Minimum log level to output. Default: `.info`.

### `global_color_display: bool`

Enable colored output globally. Default: `true`.

### `global_console_display: bool`

Enable console output globally. Default: `true`.

### `global_file_storage: bool`

Enable file output globally. Default: `true`.

### `json: bool`

Output logs in JSON format. Default: `false`.

### `pretty_json: bool`

Pretty print JSON output. Default: `false`.

### `color: bool`

Enable ANSI colors. Default: `true`.

### `show_time: bool`

Show timestamp in logs. Default: `true`.

### `show_module: bool`

Show module name. Default: `true`.

### `show_function: bool`

Show function name. Default: `false`.

### `show_filename: bool`

Show filename. Default: `false`.

### `show_lineno: bool`

Show line number. Default: `false`.

### `auto_sink: bool`

Automatically add a console sink on init. Default: `true`.

### `enable_callbacks: bool`

Enable log callbacks. Default: `true`.

## Methods

### `default() Config`

Returns the default configuration.
