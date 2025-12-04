# Context Binding

Context binding allows you to attach persistent key-value pairs to your logger. These values are automatically included in every log message, which is incredibly useful for tracking requests, users, or sessions.

## Binding Values

You can bind strings, integers, booleans, and more.

```zig
// Bind a user ID
try logger.bind("user_id", .{ .string = "12345" });

// Bind a request ID
try logger.bind("request_id", .{ .string = "req-abc-123" });

// Bind a boolean flag
try logger.bind("is_admin", .{ .bool = true });
```

## Unbinding Values

When a context is no longer needed (e.g., at the end of a request), you can unbind it.

```zig
logger.unbind("request_id");
```

## Usage Example

```zig
fn handleRequest(logger: *logly.Logger, req: Request) !void {
    // Start of request
    try logger.bind("path", .{ .string = req.path });
    try logger.bind("method", .{ .string = req.method });

    try logger.info("Handling request", @src());

    // ... processing ...

    try logger.success("Request completed", @src());

    // Cleanup
    logger.unbind("path");
    logger.unbind("method");
}
```

## JSON Output

When using JSON logging, context values are grouped under the `context` object.

```json
{
  "message": "Handling request",
  "context": {
    "path": "/api/users",
    "method": "GET"
  }
}
```
