# Dynamic Path

Several sinks support dynamic path formatting, which lets you include date and time placeholders that are resolved when the sink initializes or when creating rotated files.

Common placeholders supported by `SinkConfig.path` include:

- `{date}` → `YYYY-MM-DD`
- `{time}` → `HH-mm-ss`
- `{YYYY}`, `{MM}`, `{DD}`, `{HH}`, `{mm}`, `{ss}` → specific components

Example: see `examples/dynamic_path.zig` for a runnable demonstration. The example adds a sink that writes logs into a date-stamped directory and uses a timestamp in the filename.

```zig
_ = try logger.addSink(.{
    .path = "logs_dynamic/{date}/test-{HH}-{mm}-{ss}.log",
    .json = false,
});

try logger.info("This log should be in a date-stamped folder", null);
```

Tip: To experiment locally, run the `examples/dynamic_path.zig` program and inspect the `logs_dynamic/` directory to confirm the generated path format.
