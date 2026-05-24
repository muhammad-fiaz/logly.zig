const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Enable ANSI colors on Windows
    _ = logly.Terminal.enableAnsiColors();

    std.debug.print("============================================================\n", .{});
    std.debug.print("  ADVANCED FORMATTING DEMO (v0.2.0)\n", .{});
    std.debug.print("============================================================\n\n", .{});

    // Create a mock record to format
    var record = logly.Record.init(allocator, .warning, "Database connection latency detected");
    defer record.deinit();
    record.module = "db.client";
    record.function = "connect";
    record.filename = "client.zig";
    record.line = 42;
    try record.setTraceId("trace-1234567890abcdef");
    try record.setSpanId("span-12345");
    try record.setCorrelationId("corr-998877");
    try record.addField("latency_ms", .{ .integer = 250 });
    try record.addField("retry_count", .{ .integer = 2 });

    var formatter = logly.Formatter.init(allocator);
    defer formatter.deinit();

    // -------------------------------------------------------------
    // 1. NDJSON (Newline Delimited JSON) Formatting
    // -------------------------------------------------------------
    std.debug.print("--- 1. NDJSON Format ---\n", .{});
    var ndjson_config = logly.Config.default();
    ndjson_config.ndjson = true;
    ndjson_config.include_trace_id = true;

    const ndjson_out = try formatter.format(&record, ndjson_config);
    defer allocator.free(ndjson_out);
    std.debug.print("{s}\n", .{ndjson_out});

    // -------------------------------------------------------------
    // 2. Logfmt Formatting
    // -------------------------------------------------------------
    std.debug.print("--- 2. Logfmt Format ---\n", .{});
    var logfmt_config = logly.Config.default();
    logfmt_config.logfmt = true;

    const logfmt_out = try formatter.format(&record, logfmt_config);
    defer allocator.free(logfmt_out);
    std.debug.print("{s}\n\n", .{logfmt_out});

    // -------------------------------------------------------------
    // 3. CEF (Common Event Format) Formatting
    // -------------------------------------------------------------
    std.debug.print("--- 3. CEF (Common Event Format) ---\n", .{});
    var cef_config = logly.Config.default();
    cef_config.cef = true;

    const cef_out = try formatter.format(&record, cef_config);
    defer allocator.free(cef_out);
    std.debug.print("{s}\n\n", .{cef_out});

    // -------------------------------------------------------------
    // 4. Custom Template with Padding and Alignment
    // -------------------------------------------------------------
    std.debug.print("--- 4. Template Formatting with Alignments ---\n", .{});
    var template_config = logly.Config.default();
    // Template placeholder padding/alignment: e.g. {level:8} pads level to 8 chars
    template_config.log_format = "[{level:8}] {time} | {message} (module={module})";

    const template_out = try formatter.format(&record, template_config);
    defer allocator.free(template_out);
    std.debug.print("{s}\n", .{template_out});

    std.debug.print("\nAdvanced Formatting Example completed successfully!\n", .{});
}
