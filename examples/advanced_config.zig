const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize logger
    const logger = try logly.Logger.init(allocator);
    defer logger.deinit();

    // Configure with advanced options
    var config = logly.Config.default();

    // 1. Custom Log Format
    // Available placeholders: {time}, {level}, {message}, {module}, {function}, {file}, {line}
    config.logFormat = "{time} | {level} | {message}";

    // 2. Time Format Options:
    //    - Config.TimeFormat.default_pattern (default) - Human readable format with milliseconds
    //    - Config.TimeFormat.unix - Unix timestamp in seconds
    //    - Config.TimeFormat.unix_ms - Unix timestamp in milliseconds
    config.timeFormat = logly.Config.TimeFormat.unix;

    // 3. Timezone (Local or UTC)
    config.timezone = .utc;

    // 4. Stack Trace Configuration
    config.captureStackTrace = true;
    config.symbolizeStackTrace = true;

    // 5. Allocator: pass your own allocator to Logger.initWithConfig(allocator, config)

    logger.configure(config);

    // Log some messages
    try logger.info("This is a message with custom format", @src());
    try logger.warning("Notice the timestamp is now a unix timestamp", @src());

    // Change format dynamically
    config.logFormat = "[{level}] {message} (at {time})";
    config.timeFormat = logly.Config.TimeFormat.defaultPattern; // Switch back to human readable
    logger.configure(config);

    try logger.success("Now the format has changed!", @src());
    try logger.err("And the time format is back to readable datetime", @src());

    // Example with module/function context (simulated)
    // Note: In real usage, these are automatically captured if show_module/show_function are true
    // and the format string includes {module}/{function}
    config.logFormat = "{level}: {message} [Module: {module}]";
    config.showModule = true;
    logger.configure(config);

    // Use a scoped logger so {module} resolves to a real module name
    // instead of rendering an empty "[Module: ]".
    const scoped = logger.scoped("myModule");
    try scoped.info("Message with module info", @src());
    try logger.flush();
}
