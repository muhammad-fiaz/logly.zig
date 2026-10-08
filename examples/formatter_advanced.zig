const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Enable ANSI colors on Windows
    _ = logly.Terminal.enableAnsiColors();

    std.debug.print("\n", .{});
    std.debug.print("  Advanced Formatting Demo\n", .{});
    std.debug.print("\n\n", .{});

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

    // 1. NDJSON (Newline Delimited JSON) Formatting
    std.debug.print("1. NDJSON Format\n", .{});
    var ndjsonConfig = logly.Config.default();
    ndjsonConfig.format = .ndjson;
    ndjsonConfig.includeTraceId = true;

    const ndjsonOut = try formatter.format(&record, ndjsonConfig);
    defer allocator.free(ndjsonOut);
    std.debug.print("{s}\n", .{ndjsonOut});

    // 2. Logfmt Formatting
    std.debug.print("2. Logfmt Format\n", .{});
    var logfmtConfig = logly.Config.default();
    logfmtConfig.format = .logfmt;

    const logfmtOut = try formatter.format(&record, logfmtConfig);
    defer allocator.free(logfmtOut);
    std.debug.print("{s}\n\n", .{logfmtOut});

    // 3. Syslog (RFC5424) Formatting
    std.debug.print("3. Syslog Format\n", .{});
    var syslogConfig = logly.Config.default();
    syslogConfig.format = .syslog;

    const syslogOut = try formatter.format(&record, syslogConfig);
    defer allocator.free(syslogOut);
    std.debug.print("{s}\n\n", .{syslogOut});

    // 4. Custom Template with Padding and Alignment
    std.debug.print("4. Template Formatting with Alignments\n", .{});
    var templateConfig = logly.Config.default();
    // Template placeholder padding/alignment: e.g. {level:8} pads level to 8 chars
    templateConfig.logFormat = "[{level:8}] {time} | {message} (module={module})";

    const templateOut = try formatter.format(&record, templateConfig);
    defer allocator.free(templateOut);
    std.debug.print("{s}\n", .{templateOut});

    std.debug.print("\nAdvanced Formatting Example completed successfully!\n", .{});
}
