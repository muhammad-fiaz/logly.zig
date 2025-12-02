# Module Levels

This example demonstrates how to use module-specific log levels to control logging verbosity for different parts of your application.

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const logger = try logly.Logger.init(allocator);
    defer logger.deinit();

    // Set global level to INFO
    var config = logly.Config.default();
    config.level = .info;
    config.show_module = true;
    logger.configure(config);

    // Create scoped loggers for different modules
    const net_logger = logger.scoped("network");
    const db_logger = logger.scoped("database");
    const ui_logger = logger.scoped("ui");

    // Default behavior (INFO and above)
    try logger.info("Application started");
    try net_logger.info("Network initialized"); // Shows [network]
    try net_logger.debug("Network debug message"); // Hidden (global level is INFO)

    // Set specific level for network module (allow DEBUG)
    try logger.setModuleLevel("network", .debug);
    try logger.info("Changed network module level to DEBUG");

    try net_logger.debug("Network debug message (now visible)");
    try db_logger.debug("Database debug message"); // Still hidden

    // Set specific level for UI module (only ERROR)
    try logger.setModuleLevel("ui", .err);
    try logger.info("Changed UI module level to ERROR");

    try ui_logger.warning("UI warning"); // Hidden
    try ui_logger.err("UI error"); // Visible

    // Verify database still follows global
    try db_logger.info("Database info"); // Visible
}
```
