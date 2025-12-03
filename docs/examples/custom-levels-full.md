# Custom Levels (Full Features)

This example demonstrates custom log levels with **all features**: console output, file output, JSON output, context binding, and formatted messages.

## Code Example

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Enable ANSI colors on Windows
    _ = logly.Terminal.enableAnsiColors();

    const logger = try logly.Logger.init(allocator);
    defer logger.deinit();

    // ========================================
    // Test 1: Console with Color
    // ========================================
    
    try logger.addCustomLevel("AUDIT", 25, "35;1");     // Magenta Bold
    try logger.addCustomLevel("SECURITY", 45, "31;7"); // Red Reverse
    try logger.addCustomLevel("METRIC", 15, "36");      // Cyan

    try logger.info("Standard INFO message");
    try logger.custom("AUDIT", "User login recorded");
    try logger.custom("SECURITY", "Access control check passed");
    try logger.custom("METRIC", "Response time: 42ms");

    // ========================================
    // Test 2: File Output
    // ========================================
    
    const file_logger = try logly.Logger.init(allocator);
    defer file_logger.deinit();

    var config = logly.Config.default();
    config.auto_sink = false;
    file_logger.configure(config);

    _ = try file_logger.addSink(.{
        .path = "logs/audit.log",
    });

    try file_logger.addCustomLevel("AUDIT", 25, "35");
    try file_logger.custom("AUDIT", "This goes to the file");
    try file_logger.flush();

    // ========================================
    // Test 3: JSON Output
    // ========================================
    
    const json_logger = try logly.Logger.init(allocator);
    defer json_logger.deinit();

    var json_config = logly.Config.default();
    json_config.json = true;
    json_config.pretty_json = true;
    json_logger.configure(json_config);

    try json_logger.addCustomLevel("AUDIT", 25, "35");
    try json_logger.custom("AUDIT", "Custom level in JSON format");

    // ========================================
    // Test 4: JSON with Context
    // ========================================
    
    try json_logger.bind("service", .{ .string = "auth-service" });
    try json_logger.bind("user_id", .{ .string = "user-12345" });
    try json_logger.custom("AUDIT", "User authentication successful");

    // ========================================
    // Test 5: Formatted Messages
    // ========================================
    
    try logger.addCustomLevel("PERF", 12, "36;1");
    try logger.customf("PERF", "Request processed in {d}ms", .{42});
    try logger.customf("AUDIT", "User {s} logged in from {s}", .{ "alice", "10.0.0.1" });
}
```

## Expected Output

### Console (Colored)

```text
[2025-01-15 10:30:45.123] [INFO] Standard INFO message
[2025-01-15 10:30:45.124] [AUDIT] User login recorded
[2025-01-15 10:30:45.124] [SECURITY] Access control check passed
[2025-01-15 10:30:45.124] [METRIC] Response time: 42ms
```

### File Output (logs/audit.log)

```text
[2025-01-15 10:30:45.125] [AUDIT] This goes to the file
```

### JSON Output

```json
{
  "timestamp": "2025-01-15 10:30:45.126",
  "level": "AUDIT",
  "message": "Custom level in JSON format"
}
```

### JSON with Context

```json
{
  "timestamp": "2025-01-15 10:30:45.127",
  "level": "AUDIT",
  "message": "User authentication successful",
  "service": "auth-service",
  "user_id": "user-12345"
}
```

### Formatted Messages

```text
[2025-01-15 10:30:45.128] [PERF] Request processed in 42ms
[2025-01-15 10:30:45.128] [AUDIT] User alice logged in from 10.0.0.1
```

## Feature Parity

Custom levels support **all features** that standard levels support:

| Feature | Description |
|---------|-------------|
| Console output | ✅ Colored output with custom ANSI codes |
| File output | ✅ Write to text log files |
| JSON output | ✅ Level name appears in JSON |
| JSON file | ✅ Write JSON to files |
| Context binding | ✅ Context fields included in logs |
| Formatted messages | ✅ `customf()` with format strings |
| Level filtering | ✅ Filter by priority |
| All sink types | ✅ Works with all sink configurations |
