const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const logger = try logly.Logger.init(allocator);
    defer logger.deinit();

    // 1. Custom per-level colors. Level colors live on the config and apply
    // to every sink that resolves color.
    logger.config.levelColors.infoColor = logly.Color.parse("35").?; // magenta
    logger.config.levelColors.errorColor = logly.Color.parse("33").?; // yellow

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
    // Logger has setRedactor.
    var redactor = logly.Redactor.init(allocator);
    // defer redactor.deinit();
    // Logger does not take ownership of the thread pool.

    try redactor.addPattern("secret", .contains, "secret", "[HIDDEN]");
    logger.setRedactor(&redactor);

    try logger.info("This is a secret message", @src());

    // Clean up redactor manually since we created it
    redactor.deinit();
}
