const std = @import("std");
const logly = @import("logly");

/// Renders one record through a memory sink and prints the result. Formatting
/// is a sink concern, so every demo here goes through the public logger API
/// rather than constructing a formatter directly.
fn render(allocator: std.mem.Allocator, format: ?logly.Config.Format) !void {
    var config = logly.Config.default();
    config.autoSink = false;
    config.globalConsoleDisplay = false;
    config.color = false;
    if (format) |f| config.format = f;
    config.includeTraceId = true;

    const logger = try logly.Logger.initWithConfig(allocator, config);
    defer logger.deinit();

    const sink = logger.getSink(try logger.addSink(logly.SinkConfig.memory())) orelse
        return error.SinkUnavailable;

    // Two public ways to enrich a record: scoped() fixes the module, and
    // ctx() attaches structured fields. @src() records file:line.
    const msg = "Database connection latency detected";
    try logger.scoped("db.client").warning(msg, @src());

    // ctx() is consumed by the level call: ContextLogger.log() deinits it, so
    // do not defer deinit here.
    var ctx = logger.ctx();
    _ = ctx
        .int("latency_ms", 250)
        .int("retry_count", 2);
    try ctx.warning(msg, @src());
    try logger.flush();

    const msgs = try sink.getMemoryMessages(allocator);
    defer {
        for (msgs) |m| allocator.free(m);
        allocator.free(msgs);
    }
    if (msgs.len == 0) return error.NoMessageCaptured;

    // Both the scoped record and the context record reach the sink.
    for (msgs) |m| std.debug.print("{s}\n", .{m});
}

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    _ = logly.Terminal.enableAnsiColors();

    std.debug.print("\n", .{});
    std.debug.print("  Advanced Formatting Demo\n", .{});
    std.debug.print("\n\n", .{});

    // 1. NDJSON (Newline Delimited JSON)
    std.debug.print("1. NDJSON Format\n", .{});
    try render(allocator, .ndjson);

    // 2. Logfmt
    std.debug.print("\n2. Logfmt Format\n", .{});
    try render(allocator, .logfmt);

    // 3. Syslog (RFC5424)
    std.debug.print("\n3. Syslog Format\n", .{});
    try render(allocator, .syslog);

    // 4. Custom template. Placeholders accept padding, e.g. {level:8}.
    std.debug.print("\n4. Template Formatting with Alignments\n", .{});
    var templateConfig = logly.Config.default();
    templateConfig.autoSink = false;
    templateConfig.globalConsoleDisplay = false;
    templateConfig.color = false;
    templateConfig.logFormat = "[{level:8}] {time} | {message} (module={module})";

    const template_logger = try logly.Logger.initWithConfig(allocator, templateConfig);
    defer template_logger.deinit();
    const template_sink = template_logger.getSink(
        try template_logger.addSink(logly.SinkConfig.memory()),
    ) orelse return error.SinkUnavailable;

    const tpl = template_logger.scoped("db.client");
    try tpl.warning("Database connection latency detected", null);
    try template_logger.flush();

    const tpl_msgs = try template_sink.getMemoryMessages(allocator);
    defer {
        for (tpl_msgs) |m| allocator.free(m);
        allocator.free(tpl_msgs);
    }
    for (tpl_msgs) |m| std.debug.print("{s}\n", .{m});

    std.debug.print("\nAdvanced Formatting Example completed successfully!\n", .{});
}
