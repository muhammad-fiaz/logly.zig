# Callbacks

This example demonstrates how to use callbacks to monitor log events.

```zig
const std = @import("std");
const logly = @import("logly");

fn logCallback(record: *const logly.Record) !void {
    if (record.level.priority() >= logly.Level.err.priority()) {
        std.debug.print("[ALERT] High severity log detected: {s}\n", .{record.message});
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const logger = try logly.Logger.init(allocator);
    defer logger.deinit();

    // Set log callback for monitoring
    logger.setLogCallback(&logCallback);

    try logger.info("Normal operation");
    try logger.warning("Warning message");
    try logger.err("Error occurred - callback will trigger");
    try logger.critical("Critical error - callback will trigger");

    std.debug.print("\nCallbacks example completed!\n", .{});
}
```
