# File Logging

This example demonstrates how to log to a file. Logly supports logging to multiple destinations simultaneously (e.g., console and file).

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

    // Configure to disable auto console sink
    var config = logly.Config.default();
    config.auto_sink = false;
    logger.configure(config);

    // Add file sink (also available as logger.add())
    _ = try logger.addSink(.{
        .path = "logs/app.log",
    });

    // Add console sink
    _ = try logger.add(.{});  // Using the short alias

    try logger.info("Logging to both file and console", @src());
    try logger.success("File created in logs/app.log", @src());

    // Flush to ensure all data is written
    try logger.flush();

    std.debug.print("\nFile logging example completed! Check logs/app.log\n", .{});
}
```

## Expected Output

Console:

```text
[INFO] Logging to both file and console
[SUCCESS] File created in logs/app.log
```

File (`logs/app.log`):

```text
[INFO] Logging to both file and console
[SUCCESS] File created in logs/app.log
```
