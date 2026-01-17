# Rotation API

The `Rotation` module provides enterprise-grade log rotation capabilities, including time-based and size-based rotation, retention policies, compression, and flexible naming strategies.

## Quick Reference: Method Aliases

| Full Method | Alias(es) | Description |
|-------------|-----------|-------------|
| `init()` | `create()` | Initialize rotation |
| `deinit()` | `destroy()` | Deinitialize rotation |

## Rotation Struct

The core struct managing rotation logic.

```zig
const Rotation = @import("logly").Rotation;
```

### Initialization

```zig
pub fn init(
    allocator: std.mem.Allocator,
    path: []const u8,
    interval_str: ?[]const u8, // "daily", "hourly", etc.
    size_limit: ?u64,          // Bytes
    retention: ?usize          // Max files to keep
) !Rotation
```

### Configuration Methods

#### `withCompression`
Enables automatic compression of rotated files.

```zig
pub fn withCompression(self: *Rotation, config: CompressionConfig) !void
```

**Example:**
```zig
try rot.withCompression(.{ .algorithm = .deflate });
```

#### `withNaming`
Sets the naming strategy for rotated files.

```zig
pub fn withNaming(self: *Rotation, strategy: NamingStrategy) void
```

**Example:**
```zig
rot.withNaming(.iso_datetime);
```

#### `withNamingFormat`
Sets a custom format string for rotated files. Automatically sets strategy to `.custom`.

```zig
pub fn withNamingFormat(self: *Rotation, format: []const u8) !void
```

**Example:**
```zig
try rot.withNamingFormat("{base}-{date}{ext}");
```

#### `withMaxAge`
Sets a maximum age (in seconds) for retaining log files.

```zig
pub fn withMaxAge(self: *Rotation, seconds: i64) void
```

**Example:**
```zig
rot.withMaxAge(86400 * 7); // 7 days
```

#### `withArchiveDir`
Sets a specific directory to move rotated files into.

```zig
pub fn withArchiveDir(self: *Rotation, dir: []const u8) !void
```

**Example:**
```zig
try rot.withArchiveDir("logs/archive");
```

#### `withKeepOriginal`
Set whether to keep original files after compression.

```zig
pub fn withKeepOriginal(self: *Rotation, keep: bool) void
```

**Example:**
```zig
rot.withKeepOriginal(true); // Keep both original and compressed files
```

#### `withCompressOnRetention`
Enable compression during retention cleanup instead of deletion.

```zig
pub fn withCompressOnRetention(self: *Rotation, enable: bool) void
```

**Example:**
```zig
rot.withCompressOnRetention(true); // Compress old files instead of deleting
```

#### `withDeleteAfterRetentionCompress`
Set whether to delete original files after retention compression.

```zig
pub fn withDeleteAfterRetentionCompress(self: *Rotation, delete: bool) void
```

**Example:**
```zig
rot.withDeleteAfterRetentionCompress(false); // Keep originals after compression
```

#### `applyConfig`
Applies global configuration settings to the rotation instance.

```zig
pub fn applyConfig(self: *Rotation, config: RotationConfig) !void
```

**Example:**
```zig
try rot.applyConfig(global_config.rotation);
```

## Configuration Structs

### RotationConfig
Global configuration struct for rotation defaults.

```zig
pub const RotationConfig = struct {
    enabled: bool = false,
    interval: ?[]const u8 = null,
    size_limit: ?u64 = null,
    size_limit_str: ?[]const u8 = null,
    retention_count: ?usize = null,
    max_age_seconds: ?i64 = null,
    naming_strategy: NamingStrategy = .timestamp,
    naming_format: ?[]const u8 = null,
    archive_dir: ?[]const u8 = null,
    clean_empty_dirs: bool = false,
    async_cleanup: bool = false,
    keep_original: bool = false,                    // Keep original after compression
    compress_on_retention: bool = false,            // Compress instead of delete during retention
    delete_after_retention_compress: bool = true,   // Delete originals after retention compression
    archive_root_dir: ?[]const u8 = null,           // Root directory for all archives
    create_date_subdirs: bool = false,              // Create YYYY/MM/DD subdirectories
    file_prefix: ?[]const u8 = null,                // Custom prefix for rotated files
    file_suffix: ?[]const u8 = null,                // Custom suffix for rotated files
    compression_algorithm: CompressionAlgorithm = .gzip,
    compression_level: CompressionLevel = .default,
};
```

### RotationConfig Field Reference

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `enabled` | `bool` | `false` | Enable rotation |
| `interval` | `?[]const u8` | `null` | Time-based interval (e.g., "daily") |
| `size_limit` | `?u64` | `null` | Size-based rotation threshold (bytes) |
| `retention_count` | `?usize` | `null` | Max files to retain |
| `max_age_seconds` | `?i64` | `null` | Max age for rotated files |
| `naming_strategy` | `NamingStrategy` | `.timestamp` | File naming strategy |
| `archive_dir` | `?[]const u8` | `null` | Directory for rotated files |
| `archive_root_dir` | `?[]const u8` | `null` | Centralized archive root |
| `create_date_subdirs` | `bool` | `false` | Create YYYY/MM/DD subdirs |
| `file_prefix` | `?[]const u8` | `null` | Prefix for rotated file names |
| `file_suffix` | `?[]const u8` | `null` | Suffix for rotated file names |
| `compression_algorithm` | `CompressionAlgorithm` | `.gzip` | Algorithm for compression (gzip, zlib, deflate, zstd v0.1.5+) |
| `compression_level` | `CompressionLevel` | `.default` | Compression level |
| `keep_original` | `bool` | `false` | Keep original after compression |
| `compress_on_retention` | `bool` | `false` | Compress instead of delete |
| `delete_after_retention_compress` | `bool` | `true` | Delete after retention compression |
| `clean_empty_dirs` | `bool` | `false` | Remove empty directories |

## Enums

### RotationInterval
Defines the time interval for rotation.

| Value | Description |
| :--- | :--- |
| `.minutely` | Rotate every minute. |
| `.hourly` | Rotate every hour. |
| `.daily` | Rotate every day (24 hours). |
| `.weekly` | Rotate every week. |
| `.monthly` | Rotate every 30 days. |
| `.yearly` | Rotate every 365 days. |

### NamingStrategy
Defines how rotated files are named.

| Value | Example (`app.log`) | Notes |
| :--- | :--- | :--- |
| `.timestamp` | `app.log.167882233` | Default for size/hourly rotation. |
| `.date` | `app.log.2023-01-01` | Default for daily/weekly/monthly. |
| `.iso_datetime` | `app.log.2023-01-01T12-00-00` | High precision. |
| `.index` | `app.log.1`, `app.log.2` | Rolling log style. |
| `.custom` | `app-2023-01-01.log` | Uses `naming_format`. |

### Custom Format Placeholders

When using `.custom` (or setting `naming_format`), you can use:

| Placeholder | Description |
| :--- | :--- |
| `{base}` | Filename without extension |
| `{ext}` | Extension (including dot) |
| `{date}` | YYYY-MM-DD |
| `{time}` | HH-mm-ss |
| `{timestamp}` | Unix timestamp |
| `{iso}` | ISO 8601 Datetime |

**Flexible Date/Time Placeholders:**
You can also use `{YYYY}`, `{YY}`, `{MM}`, `{M}`, `{DD}`, `{D}`, `{HH}`, `{H}`, `{mm}`, `{m}`, `{ss}`, `{s}` and any separators.
Example: `app-{YYYY}/{M}/{D}.log` -> `app-2023/10/5.log`

## Statistics

The `RotationStats` struct provides insights into the rotation process.

| Field | Type | Description |
| :--- | :--- | :--- |
| `total_rotations` | `AtomicUnsigned` | Total number of rotations performed. |
| `files_archived` | `AtomicUnsigned` | Number of files successfully compressed. |
| `files_deleted` | `AtomicUnsigned` | Number of files deleted due to retention policy. |
| `last_rotation_time_ms` | `AtomicUnsigned` | Duration of the last rotation operation. |
| `rotation_errors` | `AtomicUnsigned` | Count of rotation failures. |
| `compression_errors` | `AtomicUnsigned` | Count of compression failures. |

### Getter Methods

| Method | Return | Description |
|--------|--------|-------------|
| `getTotalRotations()` | `u64` | Get total rotations performed |
| `getFilesArchived()` | `u64` | Get files archived count |
| `getFilesDeleted()` | `u64` | Get files deleted count |
| `getRotationErrors()` | `u64` | Get rotation error count |
| `getCompressionErrors()` | `u64` | Get compression error count |
| `getTotalErrors()` | `u64` | Get total error count |

### Boolean Checks

| Method | Return | Description |
|--------|--------|-------------|
| `hasRotated()` | `bool` | Check if any rotations have occurred |
| `hasErrors()` | `bool` | Check if any errors have occurred |
| `hasCompressionErrors()` | `bool` | Check for compression errors |
| `hasArchived()` | `bool` | Check if any files have been archived |

### Rate Calculations

| Method | Return | Description |
|--------|--------|-------------|
| `successRate()` | `f64` | Calculate success rate (0.0 - 1.0) |
| `errorRate()` | `f64` | Calculate error rate (0.0 - 1.0) |
| `totalErrorRate()` | `f64` | Calculate total error rate including compression |
| `archiveRate()` | `f64` | Calculate archive rate (archived / rotated) |

### Reset

| Method | Description |
|--------|-------------|
| `reset()` | Reset all statistics to initial state |

## Presets

The `RotationPresets` struct offers comprehensive pre-configured rotation strategies for common use cases.

### Time-Based Presets

| Method | Interval | Retention | Description |
|--------|----------|-----------|-------------|
| `daily7Days()` | daily | 7 | Standard weekly cleanup |
| `daily30Days()` | daily | 30 | Monthly cleanup |
| `daily90Days()` | daily | 90 | Quarterly cleanup |
| `daily365Days()` | daily | 365 | Yearly archive |
| `hourly24Hours()` | hourly | 24 | Daily cleanup |
| `hourly48Hours()` | hourly | 48 | Two-day buffer |
| `hourly7Days()` | hourly | 168 | Weekly retention |
| `weekly4Weeks()` | weekly | 4 | Monthly cleanup |
| `weekly12Weeks()` | weekly | 12 | Quarterly cleanup |
| `monthly12Months()` | monthly | 12 | Yearly retention |
| `minutely60()` | minutely | 60 | Debug/testing |

### Size-Based Presets

| Method | Size Limit | Retention | Description |
|--------|------------|-----------|-------------|
| `size1MB()` | 1 MB | 5 | Small logs |
| `size5MB()` | 5 MB | 5 | Compact logs |
| `size10MB()` | 10 MB | 5 | Standard size |
| `size25MB()` | 25 MB | 10 | Medium size |
| `size50MB()` | 50 MB | 10 | Large size |
| `size100MB()` | 100 MB | 10 | Enterprise size |
| `size250MB()` | 250 MB | 5 | High volume |
| `size500MB()` | 500 MB | 3 | Very high volume |
| `size1GB()` | 1 GB | 2 | Maximum size |

### Hybrid Presets (Time + Size)

| Method | Interval | Size Limit | Retention | Description |
|--------|----------|------------|-----------|-------------|
| `dailyOr100MB()` | daily | 100 MB | 30 | Rotate on time OR size |
| `hourlyOr50MB()` | hourly | 50 MB | 48 | Fast rotation |
| `dailyOr500MB()` | daily | 500 MB | 7 | High volume |

### Production Presets

| Method | Description |
|--------|-------------|
| `production()` | Daily, 30 days, gzip compression, date naming |
| `enterprise()` | Daily, 90 days, best compression, ISO naming, compress on retention |
| `debug()` | Minutely, 60 files, timestamp naming, no compression |
| `highVolume()` | Hourly OR 500MB, 7 days, ISO naming, compression |
| `audit()` | Daily, 365 days, best compression, keep all archives |
| `minimal()` | Size 10MB, 3 files, index naming (embedded systems) |

### Sink Configuration Helpers

| Method | Description |
|--------|-------------|
| `dailySink(path, retention)` | Create daily rotation sink config |
| `hourlySink(path, retention)` | Create hourly rotation sink config |
| `weeklySink(path, retention)` | Create weekly rotation sink config |
| `monthlySink(path, retention)` | Create monthly rotation sink config |
| `sizeSink(path, bytes, retention)` | Create size-based rotation sink config |

### Preset Aliases

| Alias | Target |
|-------|--------|
| `daily` | `daily7Days` |
| `hourly` | `hourly24Hours` |
| `weekly` | `weekly4Weeks` |
| `monthly` | `monthly12Months` |

### Example Usage

```zig
const RotationPresets = @import("logly").RotationPresets;

// Quick preset usage
var rot = try RotationPresets.daily7Days(allocator, "app.log");
defer rot.deinit();

// Using alias
var rot2 = try RotationPresets.daily(allocator, "server.log");
defer rot2.deinit();

// Production preset with compression enabled
var prod = try RotationPresets.production(allocator, "production.log");
defer prod.deinit();

// Enterprise preset with full archival
var ent = try RotationPresets.enterprise(allocator, "enterprise.log");
defer ent.deinit();

// Audit log with maximum retention
var audit = try RotationPresets.audit(allocator, "audit.log");
defer audit.deinit();

// Hybrid: rotate daily OR when file reaches 100MB
var hybrid = try RotationPresets.dailyOr100MB(allocator, "hybrid.log");
defer hybrid.deinit();

// Create sink configs for logger
const sink = RotationPresets.dailySink("logs/app.log", 30);
try logger.addSink(sink);
```

## Example Usage

```zig
var rotation = try Rotation.init(allocator, "app.log", "daily", null, 30);

// Enable compression
try rotation.withCompression(.{ .algorithm = .deflate });

// Logic ensures checks are fast
try rotation.checkAndRotate(&file);
```
