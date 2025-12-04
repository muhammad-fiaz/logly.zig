# Formatted Logging

This example demonstrates how to use the formatted logging methods (`infof`, `debugf`, etc.) to log messages with arguments, similar to `printf` or `std.log`. This allows for dynamic message construction without manual string concatenation. All formatted output supports colors based on log level.

## Code Example

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    // Enable ANSI colors on Windows
    _ = logly.Terminal.enableAnsiColors();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const logger = try logly.Logger.init(allocator);
    defer logger.deinit();

    // 1. Formatted Logging with Colors
    // Use methods ending with 'f' to pass format strings and arguments
    // Each line will be colored based on log level
    // Pass @src() for clickable file:line output
    try logger.infof("User {s} logged in with ID {d}", .{ "Alice", 12345 }, @src());
    try logger.warningf("Disk usage is at {d}%", .{ 85 }, @src());
    try logger.warnf("Short alias: {d}% disk used", .{ 85 }, @src());  // warnf alias
    try logger.errf("Failed to connect to {s}:{d}", .{ "localhost", 8080 }, @src());
    try logger.critf("System critical: {s}", .{ "out of memory" }, @src());  // critf alias

    // 2. Scoped Formatted Logging
    // Scoped loggers also support formatted methods with colors
    const db_logger = logger.scoped("database");
    try db_logger.debugf("Query executed in {d}ms: {s}", .{ 15, "SELECT * FROM users" }, @src());
    try db_logger.infof("Connected to database '{s}'", .{ "production_db" }, @src());

    // 3. Custom Level Formatted Logging with Custom Colors
    try logger.addCustomLevel("AUDIT", 22, "35"); // Magenta
    try logger.customf("AUDIT", "User {s} performed action: {s}", .{ "Bob", "DELETE" }, @src());

    // 4. Mixing styles
    // You can mix standard string logging with formatted logging
    try logger.info("Standard message", @src());
    try logger.infof("Formatted message with {s}", .{ "arguments" }, @src());
}
```

## Expected Output

All output is colored based on log level (entire line):

```text
[INFO] User Alice logged in with ID 12345       (white)
[WARNING] Disk usage is at 85%                  (yellow)
[ERROR] Failed to connect to localhost:8080     (red)
[database] [DEBUG] Query executed in 15ms...    (blue)
[database] [INFO] Connected to database...      (white)
[AUDIT] User Bob performed action: DELETE       (magenta - custom)
[INFO] Standard message                         (white)
[INFO] Formatted message with arguments         (white)
```

## Custom Format Strings with Colors

You can also use custom format strings with colors:

```zig
var config = logly.Config.default();
config.log_format = "{time} | {level} | {message}";
config.color = true;  // Colors apply to entire formatted line
logger.configure(config);

try logger.info("Application started");
try logger.warning("High memory usage");
try logger.err("Connection failed");
```

Output (each line colored by level):
```text
2024-01-15 10:30:45 | INFO | Application started      (white)
2024-01-15 10:30:45 | WARNING | High memory usage     (yellow)
2024-01-15 10:30:45 | ERROR | Connection failed       (red)
```
