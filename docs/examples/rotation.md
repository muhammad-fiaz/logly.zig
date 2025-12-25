# Rotation Examples

This page demonstrates various ways to configure file rotation and retention in Logly, covering basic usage, global configuration, advanced retention, and compression.

## Basic Usage

### Daily Rotation
Standard setup: daily rotation with 30-day retention.

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var logger = try logly.Logger.init(allocator, .{});
    defer logger.deinit();

    // Add a rotating sink: Daily rotation, keep 30 files
    try logger.addSink(logly.SinkConfig.rotating("logs/app.log", "daily", 30));

    logger.info("Application started");
}
```

### Size-Based Rotation
Rotate every 50MB, keep 5 files.

```zig
try logger.addSink(logly.SinkConfig.createSizeRotatingSink("logs/data.log", 50 * 1024 * 1024, 5));
```

### Concise Configuration (Short Alias)
You can use `logger.add()` with a struct literal to configure rotation inline, without needing helper functions. This gives you full access to all `SinkConfig` fields.

```zig
_ = try logger.add(.{
    .path = "logs/app.log",
    .size_limit_str = "10MB",       // Use string for easy size definition
    // .size_limit = 10 * 1024 * 1024, // Or raw bytes
    .retention = 5,                 // Keep 5 rotated files
    .rotation = "daily",            // Optional: Combine time and size
});
```

---

## Global Configuration
Configure rotation defaults globally. This is useful for enforcing consistency across services or multiple sinks.

### Full Global Config Example

```zig
const config = logly.Config{
    .rotation = .{
        .enabled = true,
        .naming_strategy = .iso_datetime, // Use ISO timestamps
        .archive_dir = "logs/archive",    // Move old files here
        .max_age_seconds = 86400 * 30,    // 30 days max age
        .retention_count = 50,            // Max 50 files total
        .clean_empty_dirs = true,         // Clean up archive dir if empty
        .interval = "hourly",             // Default interval
    }
};

var logger = try logly.Logger.init(allocator, config);
// Sinks added will inherit these rotation settings if applicable
```

---

## Advanced Scenarios

### Archiving and Compression
Rotate files, compress them with Zstd, and move them to an archive folder.

```zig
const Rotation = logly.Rotation;

// Manually configure a Rotation instance
var rot = try Rotation.init(allocator, "logs/access.log", "daily", null, 60);

// 1. Enable Zstd compression (high ratio)
try rot.withCompression(.{ 
    .algorithm = .zstd, 
    .level = .best 
});

// 2. Use ISO timestamps for better sorting
rot.withNaming(.iso_datetime); 

// 3. Move rotated files to a dedicated archive folder
try rot.withArchiveDir("logs/archive/access");

// Note: To use this manually configured Rotation with a Sink, you would integrate it 
// into a custom Sink implementation or ensure your SinkConfig supports applying these settings.
```

### Complex Retention (Age AND Count)
Enforce both max age and max count. The stricter limit applies.

```zig
var rot = try Rotation.init(allocator, "server.log", "daily", null, 100); // Max 100 files

// AND max 7 days old
rot.withMaxAge(7 * 24 * 3600); 

// Result: Files are deleted if they are the 101st file OR if they are older than 7 days.
```

### Rolling Index Strategy
Mimic standard Unix `logrotate` behavior: `app.log` -> `app.log.1` -> `app.log.2`.

```zig
var rot = try Rotation.init(allocator, "sys.log", "size", 10 * 1024 * 1024, 5);
rot.withNaming(.index);

// Result: 
// sys.log (current)
// sys.log.1 (previous)
// Result: 
// sys.log (current)
// sys.log.1 (previous)
// sys.log.2 (oldest)
```

### Dynamic Base Paths
You can combine rotation with dynamic paths (e.g., date-based directories).

```zig
// Writes to logs/2023-10-25/app.log and rotates hourly within that folder
_ = try logger.add(.{
    .path = "logs/{date}/app.log",
    .rotation = "hourly",
    .retention = 24,
});
// See 'examples/dynamic-path.md' for more path patterns.
```

### Custom File Naming
Control exactly how the rotated file is named using a format string.

```zig
// Rotates "app.log" to "app-2023.10.25.log" instead of "app.log.2023-10-25"
try logger.add(.{
    .path = "app.log",
    .rotation = "daily",
    .naming_format = "{base}-{date}{ext}",
});
```
