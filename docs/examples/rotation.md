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
