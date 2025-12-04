# Extended JSON Logging

This example demonstrates how to enable extended JSON fields like hostname and PID. These fields are valuable for distributed systems where knowing the source machine and process is critical.

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
    config.json = true;
    config.pretty_json = true;

    // Enable extended fields
    config.include_hostname = true;
    config.include_pid = true;

    logger.configure(config);

    try logger.info("This log includes hostname and PID", @src());

    // You can also combine with context
    try logger.bind("session", .{ .string = "123" });
    try logger.warn("Something happened in this session", @src());  // Short alias
}
```

## Expected Output

```json
{
  "level": "INFO",
  "message": "This log includes hostname and PID",
  "timestamp": 1717286400000,
  "hostname": "my-server-01",
  "pid": 12345
}
{
  "level": "WARNING",
  "message": "Something happened in this session",
  "timestamp": 1717286400005,
  "hostname": "my-server-01",
  "pid": 12345,
  "context": {
    "session": "123"
  }
}
```
