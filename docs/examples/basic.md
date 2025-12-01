# Basic Usage

This example demonstrates the basic usage of Logly-Zig, including initialization and logging at different levels.

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create logger (auto-sink enabled by default)
    const logger = try logly.Logger.init(allocator);
    defer logger.deinit();

    // Log at different levels - Python-like API
    try logger.trace("This is a trace message");
    try logger.debug("This is a debug message");
    try logger.info("This is an info message");
    try logger.success("Operation completed successfully!");
    try logger.warning("This is a warning");
    try logger.err("This is an error");
    try logger.fail("Operation failed");
    try logger.critical("Critical system error!");

    std.debug.print("\nBasic logging example completed!\n", .{});
}
```
