# Async Logging

Logly-Zig supports asynchronous logging to ensure that logging operations do not block your application's main execution flow. This is particularly important for high-performance applications.

## How it Works

When async logging is enabled (which is the default for file sinks), log messages are written to an in-memory buffer. The buffer is then flushed to the file system when it fills up or when `flush()` is called.

## Configuration

You can control async behavior per sink.

```zig
_ = try logger.addSink(.{
    .path = "logs/app.log",
    .async_write = true,      // Enable async (default)
    .buffer_size = 8192,      // Buffer size in bytes (default 8KB)
});
```

## Blocking vs Non-Blocking

- **Console Sink**: Typically blocking (direct write to stdout/stderr).
- **File Sink**: Non-blocking (buffered) by default.

## Flushing

To ensure all buffered logs are written to disk, you should call `flush()`. This is automatically called when the logger is deinitialized.

```zig
// Manually flush
try logger.flush();
```
