const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize logger
    const logger = try logly.Logger.init(allocator);
    defer logger.deinit();

    // Configure with advanced options
    var config = logly.Config.default();

    // 1. Custom Log Format
    // Available placeholders: {time}, {level}, {message}, {module}, {function}, {file}, {line}
    config.log_format = "{time} | {level} | {message}";

    // 2. Time Format Options:
    //    - "YYYY-MM-DD HH:mm:ss" (default) - Human readable format
    //    - "unix" - Unix timestamp in seconds
    //    - "unix_ms" - Unix timestamp in milliseconds
    config.time_format = "unix";

    // 3. Timezone (Local or UTC)
    config.timezone = .utc;

    // 4. Stack Trace Configuration
    config.capture_stack_trace = true;
    config.symbolize_stack_trace = true;

    logger.configure(config);

    // Log some messages
    try logger.info("This is a message with custom format", @src());
    try logger.warning("Notice the timestamp is now a unix timestamp", @src());

    // Change format dynamically
    config.log_format = "[{level}] {message} (at {time})";
    config.time_format = "YYYY-MM-DD HH:mm:ss"; // Switch back to human readable
    logger.configure(config);

    try logger.success("Now the format has changed!", @src());
    try logger.err("And the time format is back to readable datetime", @src());

    // Example with module/function context (simulated)
    // Note: In real usage, these are automatically captured if show_module/show_function are true
    // and the format string includes {module}/{function}
    config.log_format = "{level}: {message} [Module: {module}]";
    config.show_module = true;
    logger.configure(config);

    try logger.info("Message with module info", @src());
}
