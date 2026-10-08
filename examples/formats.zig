const std = @import("std");
const logly = @import("logly");

var threaded = std.Io.Threaded.init_single_threaded;
const io = threaded.io();

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

    // Formatting is a sink concern: give each format its own sink and read
    // the rendered bytes back from the sink rather than driving a Formatter.
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
        config.autoSink = false;
        config.format = sel;

        var mem = logly.SinkConfig.memory();
        mem.name = @tagName(sel);

        const logger = try logly.Logger.initWithConfig(allocator, config);
        defer logger.deinit();
        const sink = logger.getSink(try logger.addSink(mem)) orelse
            return error.SinkUnavailable;

        try logger.warning("Cache miss, retrying", null);
        try logger.flush();

        var msgs = try sink.getMemoryMessagesOwned(allocator);
        defer msgs.deinit();
        for (msgs.slice()) |m| std.debug.print("{s}\n{s}\n\n", .{ @tagName(sel), m });
    }

    {
        // MessagePack is binary, so it goes to a file sink rather than a
        // memory ring: the bytes stay byte-exact with no terminator added.
        const mpath = "logs/formats.msgpack";
        std.Io.Dir.cwd().deleteFile(io, mpath) catch {};
        var config = logly.Config.default();
        config.autoSink = false;
        config.format = .msgpack;

        const bin = try logly.Logger.initWithConfig(allocator, config);
        defer bin.deinit();
        _ = try bin.addSink(.{ .path = mpath, .format = .msgpack, .overwriteMode = true });
        try bin.warning("Cache miss, retrying", null);
        try bin.flush();

        var f = try std.Io.Dir.cwd().openFile(io, mpath, .{});
        defer f.close(io);
        const stat = try f.stat(io);
        var head: [1]u8 = undefined;
        var rbuf: [64]u8 = undefined;
        var reader = f.reader(io, &rbuf);
        const got = try reader.interface.readSliceShort(&head);
        std.debug.print("msgpack\n{d} bytes, first byte 0x{x:0>2}\n\n", .{
            stat.size,
            if (got > 0) head[0] else 0,
        });
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
