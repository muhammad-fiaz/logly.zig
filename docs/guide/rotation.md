# File Rotation

Logly-Zig supports automatic file rotation based on time or file size. This ensures your log files don't grow indefinitely and are easy to manage.

## Time-Based Rotation

You can rotate files at specific time intervals.

```zig
_ = try logger.add(.{  // Short alias for addSink()
    .path = "logs/app.log",
    .rotation = "daily", // Rotate every day
    .retention = 7,      // Keep 7 rotated files
});
```

Supported intervals:

- `minutely`
- `hourly`
- `daily`
- `weekly`
- `monthly`
- `yearly`

## Size-Based Rotation

You can rotate files when they reach a certain size.

```zig
_ = try logger.add(.{  // Short alias for addSink()
    .path = "logs/app.log",
    .size_limit = 10 * 1024 * 1024, // 10 MB
    // Or use a string:
    // .size_limit_str = "10MB",
    .retention = 5,                 // Keep 5 rotated files
});
```

## Combined Rotation

You can combine both time and size limits. The rotation will trigger when _either_ condition is met.

```zig
_ = try logger.add(.{  // Short alias for addSink()
    .path = "logs/app.log",
    .rotation = "daily",
    .size_limit = 5 * 1024 * 1024,
    .retention = 10,
});
```

## Retention Policy

The `retention` parameter controls how many rotated files are kept. Older files are automatically deleted.

- If `retention` is not set, no files are deleted (infinite retention).
- Rotated files are named with a timestamp suffix (e.g., `app.log.2024-03-20-10-30-45`).
