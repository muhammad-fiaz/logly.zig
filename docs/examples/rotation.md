# Rotation Examples

This page demonstrates various ways to configure file rotation and retention in Logly, covering basic usage, presets, global configuration, advanced retention, and compression.

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

## Using Presets

Logly provides comprehensive presets for common rotation scenarios.

### Time-Based Presets

```zig
const RotationPresets = logly.RotationPresets;

// Standard weekly cleanup
var daily7 = try RotationPresets.daily7Days(allocator, "logs/app.log");
defer daily7.deinit();

// Monthly retention
var daily30 = try RotationPresets.daily30Days(allocator, "logs/server.log");
defer daily30.deinit();

// Quarterly retention
var daily90 = try RotationPresets.daily90Days(allocator, "logs/audit.log");
defer daily90.deinit();

// Yearly archive
var daily365 = try RotationPresets.daily365Days(allocator, "logs/archive.log");
defer daily365.deinit();

// Hourly rotation variants
var hourly24 = try RotationPresets.hourly24Hours(allocator, "logs/access.log");
defer hourly24.deinit();

var hourly7d = try RotationPresets.hourly7Days(allocator, "logs/traffic.log");
defer hourly7d.deinit();

// Weekly and monthly
var weekly = try RotationPresets.weekly4Weeks(allocator, "logs/weekly.log");
defer weekly.deinit();

var monthly = try RotationPresets.monthly12Months(allocator, "logs/monthly.log");
defer monthly.deinit();
```

### Size-Based Presets

```zig
// Various size limits
var size1mb = try RotationPresets.size1MB(allocator, "logs/small.log");
defer size1mb.deinit();

var size10mb = try RotationPresets.size10MB(allocator, "logs/standard.log");
defer size10mb.deinit();

var size100mb = try RotationPresets.size100MB(allocator, "logs/large.log");
defer size100mb.deinit();

var size1gb = try RotationPresets.size1GB(allocator, "logs/huge.log");
defer size1gb.deinit();
```

### Hybrid Presets (Time OR Size)

```zig
// Rotate daily OR when file reaches 100MB
var hybrid = try RotationPresets.dailyOr100MB(allocator, "logs/hybrid.log");
defer hybrid.deinit();

// Rotate hourly OR when file reaches 50MB
var fast = try RotationPresets.hourlyOr50MB(allocator, "logs/fast.log");
defer fast.deinit();
```

### Production-Ready Presets

```zig
// Production: daily, 30 days, gzip compression, date naming
var prod = try RotationPresets.production(allocator, "logs/production.log");
defer prod.deinit();

// Enterprise: daily, 90 days, best compression, ISO naming
var ent = try RotationPresets.enterprise(allocator, "logs/enterprise.log");
defer ent.deinit();

// Audit: daily, 365 days, keep ALL archives (compliance)
var audit = try RotationPresets.audit(allocator, "logs/audit.log");
defer audit.deinit();

// Debug: minutely, 60 files (development/testing)
var debug = try RotationPresets.debug(allocator, "logs/debug.log");
defer debug.deinit();

// High-volume: hourly OR 500MB, 7 days
var highvol = try RotationPresets.highVolume(allocator, "logs/traffic.log");
defer highvol.deinit();

// Minimal: 10MB, 3 files (embedded/resource-constrained)
var minimal = try RotationPresets.minimal(allocator, "logs/embedded.log");
defer minimal.deinit();
```

### Quick Sink Helpers

```zig
// Use preset helpers to create sink configs
try logger.addSink(RotationPresets.dailySink("logs/app.log", 30));
try logger.addSink(RotationPresets.hourlySink("logs/access.log", 48));
try logger.addSink(RotationPresets.weeklySink("logs/weekly.log", 12));
try logger.addSink(RotationPresets.monthlySink("logs/monthly.log", 12));
try logger.addSink(RotationPresets.sizeSink("logs/data.log", 100 * 1024 * 1024, 10));
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
        .keep_original = false,           // Delete originals after compression
        .compress_on_retention = true,    // Compress during retention cleanup
    }
};

var logger = try logly.Logger.init(allocator, config);
// Sinks added will inherit these rotation settings if applicable
```

---

## Advanced Scenarios

### Archiving and Compression
Rotate files, compress them, and move them to an archive folder.

```zig
const Rotation = logly.Rotation;

// Manually configure a Rotation instance
var rot = try Rotation.init(allocator, "logs/access.log", "daily", null, 60);

// 1. Enable compression
try rot.withCompression(.{ 
    .algorithm = .gzip, 
    .level = .best 
});

// 2. Use ISO timestamps for better sorting
rot.withNaming(.iso_datetime); 

// 3. Move rotated files to a dedicated archive folder
try rot.withArchiveDir("logs/archive/access");
```

### Compress Instead of Delete
During retention cleanup, compress old files instead of deleting them:

```zig
var rot = try Rotation.init(allocator, "logs/app.log", "daily", null, 7);
try rot.withCompression(.{ .algorithm = .deflate });
rot.withCompressOnRetention(true);  // Compress files exceeding retention limits
rot.withDeleteAfterRetentionCompress(true);  // Delete originals after compression
```

### Keep Both Original and Compressed
Keep both versions of files after compression:

```zig
var rot = try Rotation.init(allocator, "logs/app.log", "hourly", null, 24);
try rot.withCompression(.{ .algorithm = .gzip });
rot.withKeepOriginal(true);  // Keep app.log.timestamp AND app.log.timestamp.gz
```

### Full Archival Pipeline
Compress on rotation, compress during retention, keep archives indefinitely:

```zig
var rot = try Rotation.init(allocator, "logs/audit.log", "daily", null, 365);
try rot.withCompression(.{ .algorithm = .gzip, .level = .best });
try rot.withArchiveDir("logs/archive/audit");
rot.withKeepOriginal(false);              // Delete original after rotation compression
rot.withCompressOnRetention(true);        // Also compress during retention
rot.withDeleteAfterRetentionCompress(false); // Keep everything in archive
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
var rot = try Rotation.init(allocator, "sys.log", null, 10 * 1024 * 1024, 5);
rot.withNaming(.index);

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
