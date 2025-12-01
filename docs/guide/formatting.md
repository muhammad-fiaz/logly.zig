# Formatting

Logly-Zig provides flexible formatting options for your logs.

## Default Format

The default format includes the timestamp, level, module (optional), and message.

```
[2024-03-20 10:30:45] [INFO] [main] Application started
```

## JSON Format

You can enable JSON formatting globally or per-sink.

```zig
var config = logly.Config.default();
config.json = true;
logger.configure(config);
```

Output:

```json
{
  "timestamp": 1710930645000,
  "level": "INFO",
  "module": "main",
  "message": "Application started"
}
```

## Pretty JSON

For development, you might prefer pretty-printed JSON.

```zig
config.pretty_json = true;
```

Output:

```json
{
  "timestamp": 1710930645000,
  "level": "INFO",
  "module": "main",
  "message": "Application started"
}
```

## Customizing Output

You can control which fields are displayed using the configuration:

```zig
config.show_time = true;
config.show_module = true;
config.show_function = true;
config.show_filename = true;
config.show_lineno = true;
```

## Colors

Logly-Zig uses ANSI color codes by default. You can customize the colors for each level using callbacks (see [Callbacks](/guide/callbacks)).

To disable colors:

```zig
config.color = false;
```
