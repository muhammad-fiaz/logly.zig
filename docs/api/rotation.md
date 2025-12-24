# Rotation API

The `Rotation` struct handles log file rotation logic with time-based and size-based strategies.

## Overview

Rotation manages the lifecycle of log files, including rolling over based on size or time intervals, and cleaning up old files based on retention policies. Supports callbacks for all rotation events.

## Types

### Rotation

The main rotation controller with thread-safe operations.

```zig
pub const Rotation = struct {
    allocator: std.mem.Allocator,
    base_path: []const u8,
    interval: ?RotationInterval,
    size_limit: ?u64,
    retention: ?usize,
    stats: RotationStats,
    mutex: std.Thread.Mutex,
    
    // Callbacks
    on_rotation_start: ?*const fn ([]const u8, []const u8) void,
    on_rotation_complete: ?*const fn ([]const u8, []const u8, u64) void,
    on_rotation_error: ?*const fn ([]const u8, anyerror) void,
    on_file_archived: ?*const fn ([]const u8, []const u8) void,
    on_retention_cleanup: ?*const fn ([]const u8) void,
};
```

### RotationInterval

Time-based rotation intervals.

```zig
pub const RotationInterval = enum {
    minutely,
    hourly,
    daily,
    weekly,
    monthly,
    yearly,
    
    pub fn millis(self: RotationInterval) u64;
    pub fn fromString(str: []const u8) ?RotationInterval;
    pub fn name(self: RotationInterval) []const u8;
};
```

### RotationStats

Statistics for rotation operations.

```zig
pub const RotationStats = struct {
    total_rotations: std.atomic.Value(u64),
    files_archived: std.atomic.Value(u64),
    files_deleted: std.atomic.Value(u64),
    last_rotation_time_ms: std.atomic.Value(u64),
    rotation_errors: std.atomic.Value(u64),
    
    pub fn reset(self: *RotationStats) void;
    pub fn rotationCount(self: *const RotationStats) u64;
    pub fn errorCount(self: *const RotationStats) u64;
};
```

## Methods

### Initialization

#### `init(allocator, path, interval_str, size_limit, retention) !Rotation`

Initializes a new Rotation instance.

#### `deinit(self: *Rotation) void`

Releases all resources associated with the rotation.

### Factory Methods

#### `daily(allocator, path, retention_days) !Rotation`

Creates a daily rotation with specified retention.

#### `hourly(allocator, path, retention_hours) !Rotation`

Creates an hourly rotation with specified retention.

#### `bySize(allocator, path, size_bytes, retention) !Rotation`

Creates a size-based rotation.

### Rotation Control

#### `rotate() !void`

Forces a log rotation.

#### `checkAndRotate() !bool`

Checks if rotation is needed and performs it. Returns true if rotation occurred.

**Alias**: `check`, `tryRotate`

#### `forceRotate() !void`

Forces an immediate rotation regardless of conditions.

**Alias**: `rotateNow`

### Statistics

#### `getStats() RotationStats`

Returns current rotation statistics.

#### `resetStats() void`

Resets all statistics to zero.

### State

#### `shouldRotate() bool`

Checks if rotation is needed based on current file size or time.

#### `isEnabled() bool`

Returns true if rotation is configured.

#### `intervalName() []const u8`

Returns the name of the current rotation interval.

### Sink Creation

#### `createRotatingSink(file_path, interval, retention) SinkConfig`

Creates a rotating sink configuration with time-based rotation.

**Alias**: `rotatingSink`

#### `createSizeRotatingSink(file_path, size_limit, retention) SinkConfig`

Creates a rotating sink configuration with size-based rotation.

**Alias**: `sizeSink`

## Presets

### RotationPresets

```zig
pub const RotationPresets = struct {
    /// Daily rotation with 7 day retention.
    pub fn daily7Days(allocator, path) !Rotation;
    
    /// Daily rotation with 30 day retention.
    pub fn daily30Days(allocator, path) !Rotation;
    
    /// Daily rotation with 90 day retention (compliance).
    pub fn daily90Days(allocator, path) !Rotation;
    
    /// Hourly rotation with 24 hour retention.
    pub fn hourly24Hours(allocator, path) !Rotation;
    
    /// Hourly rotation with 48 hour retention.
    pub fn hourly48Hours(allocator, path) !Rotation;
    
    /// 10MB size-based rotation with 5 file retention.
    pub fn size10MB(allocator, path) !Rotation;
    
    /// 100MB size-based rotation with 10 file retention.
    pub fn size100MB(allocator, path) !Rotation;
    
    /// 1GB size-based rotation with 5 file retention (high-volume).
    pub fn size1GB(allocator, path) !Rotation;
    
    /// Creates a daily rotation sink config.
    pub fn dailySink(file_path, retention_days) SinkConfig;
    
    /// Creates an hourly rotation sink config.
    pub fn hourlySink(file_path, retention_hours) SinkConfig;
};
```

## Callbacks

### `on_rotation_start`

Called before rotation begins with old and new paths.

```zig
fn myCallback(old_path: []const u8, new_path: []const u8) void {
    std.debug.print("Rotating: {s} -> {s}\n", .{old_path, new_path});
}
```

### `on_rotation_complete`

Called after successful rotation with file size.

### `on_rotation_error`

Called if rotation fails.

### `on_file_archived`

Called when a file is archived/compressed.

### `on_retention_cleanup`

Called when an old file is deleted due to retention policy.

## Example

```zig
const Rotation = @import("logly").Rotation;
const RotationPresets = @import("logly").RotationPresets;

// Create with presets
var rotation = try RotationPresets.daily7Days(allocator, "/var/log/app.log");
defer rotation.deinit();

// Or create manually
var manual_rotation = try Rotation.init(
    allocator,
    "/var/log/app.log",
    "daily",        // interval
    10 * 1024 * 1024, // 10MB size limit
    7,              // retention days
);
defer manual_rotation.deinit();

// Set callbacks
rotation.on_rotation_complete = myRotationCallback;

// Check and rotate if needed
if (try rotation.checkAndRotate()) {
    std.debug.print("Rotation performed\n", .{});
}

// Force rotation
try rotation.forceRotate();

// Check statistics
const stats = rotation.getStats();
std.debug.print("Total rotations: {d}\n", .{stats.rotationCount()});
std.debug.print("Files cleaned up: {d}\n", .{stats.files_deleted.load(.monotonic)});

// Create rotating sink
const sink_config = RotationPresets.dailySink("/var/log/app.log", 30);
```

## Strategy Guide

| Strategy | Use Case | Recommended Retention |
|----------|----------|----------------------|
| `hourly` | High-volume, debugging | 24-48 hours |
| `daily` | Standard production | 7-30 days |
| `size10MB` | Limited disk space | 5-10 files |
| `size100MB` | Moderate volume | 10-20 files |
| `size1GB` | High-volume archives | 3-5 files |

## See Also

- [Rotation Guide](../guide/rotation.md) - Detailed rotation configuration
- [Compression API](compression.md) - Compress rotated files
- [Scheduler API](scheduler.md) - Schedule rotation tasks
