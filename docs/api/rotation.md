# Rotation API

The `Rotation` module provides enterprise-grade log rotation capabilities, including time-based and size-based rotation, retention policies, compression, and flexible naming strategies.

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
    archive_dir: ?[]const u8 = null,
    clean_empty_dirs: bool = false,
};
```

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

## Presets

The `RotationPresets` struct offers common configurations.

```zig
// Daily rotation, keep 7 days
const rot = try RotationPresets.daily7Days(allocator, path);

// Size based (10MB), keep 5 files
const rot = try RotationPresets.size10MB(allocator, path);
```

## Example Usage

```zig
var rotation = try Rotation.init(allocator, "app.log", "daily", null, 30);

// Enable compression
try rotation.withCompression(.{ .algorithm = .deflate });

// Logic ensures checks are fast
try rotation.checkAndRotate(&file);
```
