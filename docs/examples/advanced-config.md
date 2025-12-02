# Advanced Configuration

This example demonstrates how to leverage advanced configuration options to customize log formats, timestamps, and timezone settings.

## Code Example

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize logger
    const logger = try logly.Logger.init(allocator);
    defer logger.deinit();

    // Configure with advanced options
    var config = logly.Config.default();

    // 1. Custom Log Format
    // Available placeholders: {time}, {level}, {message}, {module}, {function}, {file}, {line}
    config.log_format = "{time} | {level} | {message}";

    // 2. Custom Time Format
    // You can use "unix" for timestamps or standard format strings
    config.time_format = "unix";

    // 3. Timezone (Local or UTC)
    config.timezone = .UTC;

    logger.configure(config);

    // Log some messages
    try logger.info("This is a message with custom format");
    try logger.warning("Notice the timestamp is now a unix timestamp");

    // Change format dynamically
    config.log_format = "[{level}] {message} (at {time})";
    config.time_format = "YYYY-MM-DD HH:mm:ss"; // Standard format
    logger.configure(config);

    try logger.success("Now the format has changed!");
    try logger.err("And the time format is human-readable");
}
```

## Expected Output

```text
1717286400000 | INFO | This is a message with custom format
1717286400005 | WARNING | Notice the timestamp is now a unix timestamp
[SUCCESS] Now the format has changed! (at 2024-06-02 00:00:00)
[ERROR] And the time format is human-readable (at 2024-06-02 00:00:00)
```
