# Rotation API

The `Rotation` struct handles log file rotation logic.

## Overview

Rotation manages the lifecycle of log files, including rolling over based on size or time, and cleaning up old files based on retention policies.

## Types

### Rotation

The main rotation controller.

```zig
pub const Rotation = struct {
    allocator: std.mem.Allocator,
    base_path: []const u8,
    interval: ?RotationInterval,
    size_limit: ?u64,
    retention: ?usize,
    stats: RotationStats,
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
};
```

## Methods

### `init(allocator: std.mem.Allocator, path: []const u8, interval_str: ?[]const u8, size_limit: ?u64, retention: ?usize) !Rotation`

Initializes a new Rotation instance.

### `rotate() !void`

Forces a log rotation.

### `shouldRotate() bool`

Checks if rotation is needed based on current file size or time.

## Callbacks

### `on_rotation_start: ?*const fn ([]const u8, []const u8) void`

Called before rotation begins.

### `on_rotation_complete: ?*const fn ([]const u8, []const u8, u64) void`

Called after successful rotation.

### `on_rotation_error: ?*const fn ([]const u8, anyerror) void`

Called if rotation fails.

### `on_file_archived: ?*const fn ([]const u8, []const u8) void`

Called when a file is archived/compressed.

### `on_retention_cleanup: ?*const fn ([]const u8) void`

Called when an old file is deleted.
