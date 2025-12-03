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

    // 2. Custom Time Format (currently supports "unix" or default seconds.millis)
    // In a future update, this will support full date formatting strings
    config.time_format = "unix";

    // 3. Timezone (Local or UTC)
    config.timezone = .utc;

    logger.configure(config);

    // Log some messages
    try logger.info("This is a message with custom format");
    try logger.warning("Notice the timestamp is now a unix timestamp");

    // Change format dynamically
    config.log_format = "[{level}] {message} (at {time})";
    config.time_format = "default"; // Switch back to default time format
    logger.configure(config);

    try logger.success("Now the format has changed!");
    try logger.err("And the time format is back to seconds.millis");

    // Example with module/function context (simulated)
    // Note: In real usage, these are automatically captured if show_module/show_function are true
    // and the format string includes {module}/{function}
    config.log_format = "{level}: {message} [Module: {module}]";
    config.show_module = true;
    logger.configure(config);

    try logger.info("Message with module info");
}
