---
title: Formats Example
description: Example demonstrating all core serialization formats end to end with per-sink format selection in Logly.zig.
head:
  - - meta
    - name: keywords
      content: log formats, text, json, ndjson, logfmt, syslog, syslog3164, msgpack, per-sink format
  - - meta
    - property: og:title
      content: Formats Example | Logly.zig
---

# Formats Example

This example demonstrates every core serialization format end-to-end and shows per-sink format selection: one logger, text console plus JSON-lines, logfmt, syslog, and binary MessagePack, each rendering the same record its own way.

## Source Code

```zig
const std = @import("std");
const logly = @import("logly");

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

        var msgs = try sink.messages(allocator);
        defer msgs.deinit();
        for (msgs.items) |m| std.debug.print("{s}\n{s}\n\n", .{ @tagName(sel), m });
    }

    {
        // MessagePack is binary, so it goes to a file sink rather than a
        // memory ring: the bytes stay byte-exact with no terminator added.
        const mpath = "logs/formats.msgpack";
        const io = logly.Utils.defaultIo();
        std.Io.Dir.cwd().deleteFile(io, mpath) catch {};
        var config = logly.Config.default();
        config.autoSink = false;
        config.format = .msgpack;

        const logger = try logly.Logger.initWithConfig(allocator, config);
        defer logger.deinit();
        _ = try logger.addSink(.{ .path = mpath });

        try logger.warning("Binary message pack record", null);
        try logger.flush();

        const file = try std.Io.Dir.cwd().openFile(io, mpath, .{});
        defer file.close(io);
        const stat = try file.stat(io);
        std.debug.print("msgpack\n{s} ({d} bytes written)\n", .{ mpath, stat.size });
    }
}
```

## Running the Example

```bash
zig build run-formats
```
