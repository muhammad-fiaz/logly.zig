const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const logger = try logly.Logger.init(allocator);
    defer logger.deinit();

    // 1. Custom Theme
    const theme = logly.Formatter.Theme{
        .info = "35", // Magenta for info
        .err = "33", // Yellow for error
    };

    // Apply theme to the first sink (console)
    if (logger.sinks.items.len > 0) {
        logger.sinks.items[0].formatter.setTheme(theme);
    }

    try logger.info("This info should be magenta!", @src());
    try logger.err("This error should be yellow!", @src());

    // 2. Scoped Context
    {
        var scoped = logger.with();
        defer scoped.deinit();

        _ = scoped.str("scope", "test")
            .int("id", 42);

        try scoped.info("Scoped message", @src());
    }

    try logger.info("Global message (no scope)", @src());

    // 3. Advanced Redaction
    // We need to access the redactor. Logger doesn't expose it directly easily?
    // Logger has setRedactor.
    // Let's create a redactor.
    var redactor = logly.Redactor.init(allocator);
    // defer redactor.deinit(); // Logger doesn't own redactor, but we need to keep it alive?
    // Actually Logger doesn't own it.

    try redactor.addPattern("secret", .contains, "secret", "[HIDDEN]");
    logger.setRedactor(&redactor);

    try logger.info("This is a secret message", @src());

    // Clean up redactor manually since we created it
    redactor.deinit();
}
