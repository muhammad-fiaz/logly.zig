# Custom Colors

This example demonstrates how to define and use custom colors for log levels. You can customize the appearance of your logs by defining ANSI color codes for specific levels.

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

    // Add a custom level with specific color
    // Format: "FG;BG;STYLE" or just "FG"
    // 31=Red, 32=Green, 33=Yellow, 34=Blue, 35=Magenta, 36=Cyan
    // 1=Bold, 4=Underline

    try logger.addCustomLevel("NOTICE", 22, "36;1"); // Cyan Bold
    try logger.addCustomLevel("ALERT", 42, "31;4");  // Red Underline

    try logger.info("Standard Info (Green)");
    try logger.custom("NOTICE", "This is a notice (Cyan Bold)");
    try logger.warning("Standard Warning (Yellow)");
    try logger.custom("ALERT", "This is an alert (Red Underline)");
    try logger.err("Standard Error (Red)");

    std.debug.print("\nCustom colors example completed!\n", .{});
}
```

## Expected Output

```text
[INFO] Standard Info (Green)
[NOTICE] This is a notice (Cyan Bold)
[WARNING] Standard Warning (Yellow)
[ALERT] This is an alert (Red Underline)
[ERROR] Standard Error (Red)
```
