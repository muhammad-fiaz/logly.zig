# Context Binding

This example demonstrates how to use context binding to attach metadata to logs. Context is particularly useful for tracking requests, user sessions, or system states across multiple log messages.

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

    // Application-wide context
    try logger.bind("app_name", .{ .string = "web-server" });
    try logger.bind("version", .{ .string = "2.1.0" });
    try logger.bind("host", .{ .string = "server-01" });

    try logger.info("Server starting...", @src());

    // Simulate handling a request
    try handleRequest(logger, "req-001", "user-alice");
    try handleRequest(logger, "req-002", "user-bob");

    try logger.info("Server shutting down", @src());

    std.debug.print("\nContext binding example completed!\n", .{});
}

fn handleRequest(logger: *logly.Logger, request_id: []const u8, user_id: []const u8) !void {
    // Add request-specific context
    try logger.bind("request_id", .{ .string = request_id });
    try logger.bind("user_id", .{ .string = user_id });

    try logger.info("Request received", @src());
    try logger.debug("Processing request...", @src());
    try logger.success("Request completed successfully", @src());

    // Clean up request context
    logger.unbind("request_id");
    logger.unbind("user_id");
}
```

## Expected Output

(Note: Context fields are typically shown in JSON output, but some text formatters may include them)

```text
[INFO] Server starting...
[INFO] Request received
[DEBUG] Processing request...
[SUCCESS] Request completed successfully
[INFO] Request received
[DEBUG] Processing request...
[SUCCESS] Request completed successfully
[INFO] Server shutting down
```
