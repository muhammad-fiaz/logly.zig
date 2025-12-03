# JSON Logging

This example demonstrates how to enable JSON logging and use context binding. JSON logging is essential for modern log aggregation systems like ELK, Datadog, or CloudWatch.

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

    // Enable JSON output
    var config = logly.Config.default();
    config.json = true;
    config.pretty_json = true;
    logger.configure(config);

    // Bind context that will appear in all logs
    try logger.bind("app", .{ .string = "myapp" });
    try logger.bind("version", .{ .string = "1.0.0" });
    try logger.bind("environment", .{ .string = "production" });

    try logger.info("Application started");
    try logger.success("All systems operational");

    // Add request-specific context
    try logger.bind("request_id", .{ .string = "req-12345" });
    try logger.bind("user_id", .{ .string = "user-67890" });

    try logger.info("Processing user request");

    // Clean up request context
    logger.unbind("request_id");
    logger.unbind("user_id");

    try logger.info("Request completed");

    std.debug.print("\nJSON logging example completed!\n", .{});
}
```

## Expected Output

```json
{
  "timestamp": "2024-01-15 10:30:45.+000",
  "level": "INFO",
  "message": "Application started",
  "app": "myapp",
  "version": "1.0.0",
  "environment": "production"
}
{
  "timestamp": "2024-01-15 10:30:45.+005",
  "level": "INFO",
  "message": "Processing user request",
  "app": "myapp",
  "version": "1.0.0",
  "environment": "production",
  "request_id": "req-12345",
  "user_id": "user-67890"
}
```

## Custom Levels in JSON

Custom levels display their actual names in JSON:

```zig
try logger.addCustomLevel("audit", 35, "35");
try logger.custom("audit", "User login event");
```

Output:
```json
{
  "timestamp": "2024-01-15 10:30:45.+000",
  "level": "AUDIT",
  "message": "User login event"
}
```
