const std = @import("std");
const logly = @import("logly");

/// Demonstrates every core serialization format end to end and shows
/// per-sink format selection: one logger, a text console plus a JSON-lines
/// file and a syslog file, each rendering the same record its own way.
pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("Serialization Formats\n\n", .{});

    var record = logly.Record.init(allocator, .warning, "Cache miss, retrying");
    defer record.deinit();
    record.module = "cache";
    try record.addField("attempt", .{ .integer = 2 });
    try record.addField("host", .{ .string = "example.com" });

    var formatter = logly.Formatter.init(allocator);
    defer formatter.deinit();

    const selections = [_]logly.Config.Format{
        .text,
        .json,
        .ndjson,
        .logfmt,
        .syslog,
        .syslog3164,
    };
    for (selections) |sel| {
        var config = logly.Config.default();
        config.format = sel;
        const out = try formatter.format(&record, config);
        defer allocator.free(out);
        std.debug.print("{s}\n{s}\n\n", .{ @tagName(sel), out });
    }

    {
        var config = logly.Config.default();
        config.format = .msgpack;
        const out = try formatter.format(&record, config);
        defer allocator.free(out);
        std.debug.print("msgpack\n{d} bytes, first byte 0x{x:0>2}\n\n", .{ out.len, out[0] });
    }

    // Per-sink formats: console text plus a JSON-lines file and a syslog file.
    const logger = try logly.Logger.init(allocator);
    defer logger.deinit();

    _ = try logger.addSink(.{ .path = "logs/formats.ndjson", .format = .ndjson });
    _ = try logger.addSink(.{ .path = "logs/formats.syslog", .format = .syslog });

    try logger.warning("Cache miss, retrying", @src());
    try logger.flush();

    std.debug.print("Formats example complete (see logs/formats.ndjson, logs/formats.syslog)\n", .{});
}
