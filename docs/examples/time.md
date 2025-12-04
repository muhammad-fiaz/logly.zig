# Time Formatting

This example demonstrates how to customize timestamp formatting and timezones. Logly allows you to use standard date format strings or switch between Local and UTC time.

## Code Example

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Enable colors on Windows
    _ = logly.Terminal.enableAnsiColors();

    const logger = try logly.Logger.init(allocator);
    defer logger.deinit();

    var config = logly.Config.default();

    // Example 1: Default format (YYYY-MM-DD HH:mm:ss)
    logger.configure(config);
    try logger.info("Default time format", @src());

    // Example 2: Custom time format
    // Supports standard format specifiers
    config.time_format = "HH:mm:ss";
    logger.configure(config);
    try logger.info("Short time format", @src());

    // Example 3: UTC timezone
    // Switch to UTC time instead of local time
    config.timezone = .utc;
    logger.configure(config);
    try logger.info("UTC time", @src());
}
```

## Expected Output

```text
[2024-06-01 12:00:00] [INFO] Default time format
[12:00:00] [INFO] Short time format
[10:00:00] [INFO] UTC time
```
