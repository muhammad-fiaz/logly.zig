# File Rotation

This example demonstrates how to configure file rotation. Rotation ensures that log files don't grow indefinitely by creating new files based on time intervals or size limits, and deleting old files based on retention policies.

## Code Example

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const logger = try logly.Logger.init(allocator);
    defer logger.deinit();

    var config = logly.Config.default();
    config.auto_sink = false;
    logger.configure(config);

    // Daily rotation with 7 day retention (using add() alias)
    _ = try logger.add(.{
        .path = "logs/daily.log",
        .rotation = "daily",
        .retention = 7,
    });

    // Size-based rotation (10MB limit)
    _ = try logger.add(.{
        .path = "logs/size_based.log",
        .size_limit = 10 * 1024 * 1024,
        .retention = 5,
    });

    // Combined rotation (daily OR 5MB)
    _ = try logger.add(.{
        .path = "logs/combined.log",
        .rotation = "daily",
        .size_limit = 5 * 1024 * 1024,
        .retention = 10,
    });

    try logger.info("Rotation example - files will rotate based on time or size", @src());
    try logger.success("Check logs/ directory for rotated files", @src());

    try logger.flush();

    std.debug.print("\nRotation example completed!\n", .{});
}
```

## Expected Output

Files created in `logs/`:

- `daily.log`
- `size_based.log`
- `combined.log`

(When rotation triggers, you will see files like `daily.2024-06-01.log` or `size_based.1.log`)

## New Presets (v0.0.9)

```zig
const RotationPresets = logly.RotationPresets;

// 1GB size-based rotation
var rotation = RotationPresets.size1GB();

// 90-day daily rotation
var rotation = RotationPresets.daily90Days();

// 48-hour hourly rotation
var rotation = RotationPresets.hourly48Hours();

// Factory methods for sinks
var sink = RotationPresets.dailySink("logs/app.log", 30);
var sink = RotationPresets.hourlySink("logs/app.log", 24);
```

## Aliases

| Alias | Method |
|-------|--------|
| `check` | `shouldRotate` |
| `tryRotate` | `rotate` |
| `rotateNow` | `rotate` |
| `rotatingSink` | `createSinkWithRotation` |
| `sizeSink` | `createSinkWithSizeRotation` |

## Best Practices

1. **Set retention** - Always define retention to prevent disk filling
2. **Use compression** - Enable compression for rotated files
3. **Monitor disk** - Alert when disk usage is high
4. **Test rotation** - Verify rotation works in staging
5. **Combine with scheduler** - Use scheduler for cleanup tasks

## See Also

- [Rotation Guide](/guide/rotation) - Detailed rotation documentation
- [Rotation API](/api/rotation) - Full API reference

