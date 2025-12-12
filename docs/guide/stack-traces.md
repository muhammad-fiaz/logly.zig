# Stack Traces

Logly-Zig automatically captures stack traces for `err` and `critical` log levels, helping you debug issues faster by pinpointing exactly where they occurred.

## Automatic Capture

By default, when you log at `.err` or `.critical` levels, a stack trace is captured and attached to the log record.

```zig
// This will include a stack trace
try logger.err("Database connection failed", @src());

// This will also include a stack trace
try logger.critical("System out of memory", @src());
```

## Output Formats

### Text Format

In the default text formatter, stack traces are printed as a list of memory addresses. To make these useful, you typically need to resolve them using `zig build run` or a symbolizer tool, but they provide the raw data needed for debugging.

You can also enable **symbolization** in the configuration to attempt to resolve these addresses to function names and line numbers at runtime (requires debug info).

```text
[ERR] Database connection failed
Stack Trace:
  0x100003f80
  0x100003e20
  0x100003a10
```

With symbolization enabled:
```text
[ERR] Database connection failed
Stack Trace:
  main (src/main.zig:42)
  processRequest (src/handler.zig:15)
  0x100003a10
```

### JSON Format

When using JSON output, the stack trace is included as an array of address strings in the `stack_trace` field.

```json
{
  "level": "ERR",
  "message": "Database connection failed",
  "timestamp": 1710930645000,
  "stack_trace": ["0x100003f80", "0x100003e20", "0x100003a10"]
}
```

## Configuration

You can control stack trace behavior via the `Config` struct.

### Stack Size

You can configure the stack size allocated for capturing traces (default is 1MB).

```zig
var config = logly.Config.default();
config.stack_size = 2 * 1024 * 1024; // 2MB
logger.configure(config);
```

### Symbolization

You can enable runtime symbolization to resolve addresses to function names. Note that this can be expensive and requires the binary to be built with debug information.

```zig
var config = logly.Config.default();
config.symbolize_stack_trace = true;
logger.configure(config);
```

## Performance Considerations

Capturing stack traces involves walking the stack, which can be relatively expensive compared to normal logging. However, since it only happens for errors and critical failures (which should be rare), the performance impact on the overall application is usually negligible.

## Best Practices

1. **Use Error Levels Appropriately**: Only use `.err` and `.critical` for actual errors where a stack trace is valuable. Use `.warning` for handled issues where you don't need a trace.
2. **Symbolization**: For production logs, consider using a tool to post-process logs and resolve addresses to function names and line numbers using your binary's debug symbols.
