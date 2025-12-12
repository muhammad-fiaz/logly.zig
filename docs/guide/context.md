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

## Scoped Context

For temporary context that should only apply to a specific scope or chain of operations, you can use `logger.with()`. This creates a lightweight `PersistentContextLogger` that inherits the parent logger's configuration but maintains its own context.

```zig
// Create a scoped logger with specific context
var req_logger = logger.with();
defer req_logger.deinit();

// Chain context methods
_ = req_logger.str("request_id", "req-123")
              .str("user_id", "user-456")
              .boolean("is_admin", true);

// Log using the scoped logger
try req_logger.info("Processing request", @src());
try req_logger.warn("Resource usage high", @src());
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

## Scoped Context

For temporary context that should only apply to a specific scope or set of operations, you can use `logger.with()`. This creates a lightweight logger wrapper that maintains its own context without modifying the global logger.

```zig
{
    var scoped = logger.with();
    defer scoped.deinit();
    
    _ = scoped.str("request_id", "req-123")
              .int("attempt", 1);
              
    try scoped.info("Processing request"); // Includes request_id and attempt
    try scoped.warn("Retrying...");        // Includes request_id and attempt
}

try logger.info("Back to global context"); // Does NOT include request_id
```
