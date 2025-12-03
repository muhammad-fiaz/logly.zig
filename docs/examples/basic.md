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
    try logger.trace("This is a trace message");       // Cyan
    try logger.debug("This is a debug message");       // Blue
    try logger.info("This is an info message");        // White
    try logger.success("Operation completed!");        // Green
    try logger.warning("This is a warning");           // Yellow
    try logger.err("This is an error");                // Red
    try logger.fail("Operation failed");               // Magenta
    try logger.critical("Critical system error!");     // Bright Red

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
[2024-01-15 10:30:45] [ERR] This is an error                <- Red line
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
| ERR | 31 | Red |
| FAIL | 35 | Magenta |
| CRITICAL | 91 | Bright Red |
