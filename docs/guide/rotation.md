# File Rotation Guide

Logly provides a powerful file rotation system suitable for high-throughput production environments. This guide explains how to configure rotation strategies, retention policies, compression, and global defaults.

## Basics

File rotation prevents log files from growing indefinitely by periodically closing the current file, renaming it, and starting a fresh one.

To enable rotation, use the `rotating` sink or configure a `Rotation` object manually.

```zig
const config = Config.init(allocator)
    .withSink(SinkConfig.rotating("app.log", "daily", 7));
```

Alternatively, you can use the `logger.add()` shortcut with a configuration struct:

```zig
try logger.add(.{
    .path = "app.log",
    .rotation = "daily",
    .retention = 7,
    .size_limit_str = "10MB", // Optional: also rotate on size
});
```

## Global Configuration

You can configure rotation defaults globally in `Config`, which allows you to enforce strategies across all sinks or provide defaults for those that don't specify them.

### Configuration Reference

The `RotationConfig` struct provides the following fields:

| Field | Type | Description |
| :--- | :--- | :--- |
| `enabled` | `bool` | Master switch for default rotation logic. |
| `interval` | `?[]const u8` | Default time interval ("daily", "hourly"). |
| `size_limit` | `?u64` | Default size limit in bytes. |
| `retention_count` | `?usize` | Default max number of files to keep. |
| `max_age_seconds` | `?i64` | Default max age of files in seconds. |
| `naming_strategy` | `NamingStrategy` | Default naming strategy (`timestamp`, `date`, `iso_datetime`, `index`). |
| `archive_dir` | `?[]const u8` | Directory to automatically move rotated files into. |
| `clean_empty_dirs` | `bool` | Whether to delete the archive directory if it becomes empty. |

### Example

```zig
const config = Config{
    .rotation = .{
        .enabled = true,
        .naming_strategy = .iso_datetime,
        .archive_dir = "logs/archive",
        .max_age_seconds = 86400 * 30, // 30 days
        .clean_empty_dirs = true,
        .interval = "daily",
    }
};
```

## Strategies

### Time-Based Rotation
Rotates files based on elapsed time.

- `minutely`: Useful for debugging.
- `hourly`: Good for high-volume logs.
- `daily`: Standard for most applications.
- `weekly`/`monthly`: For lower volume, long-term logs.

### Size-Based Rotation
Rotates files when they reach a specific size limit.

```zig
// Rotate when file hits 100MB, keep 10 files
const config = SinkConfig.createSizeRotatingSink("app.log", 100 * 1024 * 1024, 10);
```

### Sink Configuration Fields

When using `logger.add(.{...})`, you can use the following fields to control rotation:

| Field | Type | Description |
| :--- | :--- | :--- |
| `rotation` | `?[]const u8` | Time interval ("daily", "hourly"). |
| `size_limit` | `?u64` | Size limit in bytes. |
| `size_limit_str` | `?[]const u8` | Size limit as string (e.g., "10MB"). |
| `retention` | `?usize` | Number of files to keep. |
| `compression` | `CompressionConfig` | Nested struct to enable compression. |

## Naming Strategies
You can control how rotated files are named using `NamingStrategy`.

- **Timestamp** (Default for `size/hourly`): `app.log` -> `app.log.167882233`
- **Date** (Default for `daily`+): `app.log` -> `app.log.2023-10-25`
- **ISO**: `app.log` -> `app.log.2023-10-25T14-30-00`
- **Index**: `app.log` -> `app.log.1`, `app.log.2` (Rolling log style)
- **Custom**: Define your own pattern like `app-{date}.log`.

### Custom Formatting
You can define a custom format string using `naming_format`.

Supported placeholders:
- `{base}`: Filename without extension (e.g. "app")
- `{ext}`: File extension including dot (e.g. ".log")
- `{date}`: YYYY-MM-DD
- `{time}`: HH-mm-ss
- `{iso}`: ISO 8601 datetime
- `{YYYY}`, `{YY}`, `{MM}`, `{M}`, `{DD}`, `{D}`, `{HH}`, `{H}`, `{mm}`, `{m}`, `{ss}`, `{s}`: Granular date formatting

**Example: `app-2023-12-25.log`**
```zig
try logger.add(.{
    .path = "app.log",
    .rotation = "daily",
    // Custom: Use dots, slashes, or specific ordering
    .naming_format = "{base}-{DD}-{MM}-{YYYY}{ext}",
});
```

To control the *active* file naming (e.g. writing directly to a date-stamped file), refer to the [Dynamic Path](../examples/dynamic-path.md) documentation.

## Compression
Logly can automatically compress old log files to save space (`.gz` or `.zst`).

```zig
var rot = try Rotation.init(allocator, "app.log", "daily", null, 30);
try rot.withCompression(.{ .algorithm = .deflate });
```

## Retention Policies
Retention controls how long rotated files are kept.

- **Count Based**: Keep only the last `N` files.
- **Age Based**: Keep files younger than `Seconds`.

Old files are automatically deleted during the rotation process.

### Archiving
You can move rotated files to a specific directory to keep your main log folder clean.

```zig
try rot.withArchiveDir("logs/archive");
```

## Performance
Rotation checks are optimized to be `O(1)` (simple time or size check). The actual rotation involves file I/O (renaming, creating) and is protected by a mutex to ensure thread safety. Compression happens after the critical logic, so the impact on the logging thread is managed, but for extremely large files, consider scheduling compression separately.
