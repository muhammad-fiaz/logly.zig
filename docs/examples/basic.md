# Basic Usage

This example demonstrates the basic usage of Logly-Zig, including initialization and logging at different levels.

## Code Example

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Enable ANSI colors on Windows (no-op on Linux/macOS)
    _ = logly.Terminal.enableAnsiColors();

    // Create logger (auto-sink enabled by default)
    const logger = try logly.Logger.init(allocator);
    defer logger.deinit();

    // Log at different levels - entire line is colored!
    // Pass @src() for clickable file:line, or null for no source location
    try logger.trace("This is a trace message", @src());       // Cyan
    try logger.debug("This is a debug message", @src());       // Blue
    try logger.info("This is an info message", @src());        // White
    try logger.success("Operation completed!", @src());        // Green
    try logger.warning("This is a warning", @src());           // Yellow (also: .warn())
    try logger.err("This is an error", @src());                // Red
    try logger.fail("Operation failed", @src());               // Magenta
    try logger.critical("Critical system error!", @src());     // Bright Red (also: .crit())

    // Short aliases also available
    try logger.warn("Warning with short alias", @src());
    try logger.crit("Critical with short alias", @src());

    std.debug.print("\nBasic logging example completed!\n", .{});
}
```

## Expected Output

Each line is colored according to its level:

```text
[2024-01-15 10:30:45] [TRACE] This is a trace message       <- Cyan line
[2024-01-15 10:30:45] [DEBUG] This is a debug message       <- Blue line
[2024-01-15 10:30:45] [INFO] This is an info message        <- White line
[2024-01-15 10:30:45] [SUCCESS] Operation completed!        <- Green line
[2024-01-15 10:30:45] [WARNING] This is a warning           <- Yellow line
[2024-01-15 10:30:45] [ERROR] This is an error              <- Red line
[2024-01-15 10:30:45] [FAIL] Operation failed               <- Magenta line
[2024-01-15 10:30:45] [CRITICAL] Critical system error!     <- Bright Red line
```

## Level Colors

| Level | Color Code | Display |
|-------|------------|---------|
| TRACE | 36 | Cyan |
| DEBUG | 34 | Blue |
| INFO | 37 | White |
| SUCCESS | 32 | Green |
| WARNING | 33 | Yellow |
| ERROR | 31 | Red |
| FAIL | 35 | Magenta |
| CRITICAL | 91 | Bright Red |
