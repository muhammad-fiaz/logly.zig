# JSON Logging

Structured logging is essential for modern observability stacks. Logly-Zig supports JSON output out of the box.

## Enabling JSON

You can enable JSON output globally or for specific sinks.

### Global JSON

```zig
var config = logly.Config.default();
config.json = true;
logger.configure(config);
```

### Per-Sink JSON

```zig
_ = try logger.addSink(.{
    .path = "logs/app.json",
    .json = true,
});
```

## JSON Structure

The JSON output contains the following fields:

```json
{
  "timestamp": 1710930645000,
  "level": "INFO",
  "module": "main",
  "message": "Application started",
  "user_id": "12345",
  "request_id": "abc-123"
}
```

- `timestamp`: Unix timestamp in milliseconds
- `level`: Log level string (uses custom level name if set)
- `module`: Module name (if enabled)
- `function`: Function name (if enabled)
- `file`: Filename (if enabled)
- `line`: Line number (if enabled)
- `message`: The log message
- Context variables are added as top-level fields

## Custom Levels in JSON

Custom levels display their actual names in JSON output:

```zig
try logger.addCustomLevel("audit", 35, "35");
try logger.custom("audit", "Security event");
```

Output:
```json
{
  "timestamp": 1710930645000,
  "level": "AUDIT",
  "message": "Security event"
}
```

## Pretty Printing

For development or debugging, you can enable pretty printing to format the JSON with indentation.

```zig
config.pretty_json = true;
```
