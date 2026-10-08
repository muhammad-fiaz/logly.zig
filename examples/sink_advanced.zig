const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    _ = logly.Terminal.enableAnsiColors();

    var globalConfig = logly.Config.default();
    globalConfig.autoSink = false;

    // Sinks are registered through the logger; fetch the handle back to
    // inspect it. The logger owns and cleans up every registered sink.
    const owner = try logly.Logger.initWithConfig(allocator, globalConfig);
    defer owner.deinit();

    std.debug.print("\n", .{});
    std.debug.print("  Advanced Sink Demo\n", .{});
    std.debug.print("\n\n", .{});

    // 1. Memory Sink Demo
    std.debug.print("1. In-Memory Ring Buffer Sink\n", .{});
    var memCfg = logly.SinkConfig.memory();
    memCfg.name = "in_memory_buffer";
    memCfg.memoryCapacity = 3; // Keep ring buffer tiny for simple demo

    const memSink = owner.getSink(try owner.addSink(memCfg)) orelse
        return error.SinkUnavailable;

    var r1 = logly.Record.init(allocator, .info, "Message One");
    defer r1.deinit();
    var r2 = logly.Record.init(allocator, .info, "Message Two");
    defer r2.deinit();
    var r3 = logly.Record.init(allocator, .info, "Message Three");
    defer r3.deinit();
    var r4 = logly.Record.init(allocator, .info, "Message Four (Will overwrite One)");
    defer r4.deinit();

    try memSink.write(&r1, globalConfig);
    try memSink.write(&r2, globalConfig);
    try memSink.write(&r3, globalConfig);
    try memSink.flush(); // Memory sink parses logs on flush

    std.debug.print("Messages written: 3. Capacity: 3.\n", .{});
    {
        const msgs = try memSink.getMemoryMessages(allocator);
        defer {
            for (msgs) |m| allocator.free(m);
            allocator.free(msgs);
        }
        for (msgs, 0..) |msg, i| {
            std.debug.print("  [{d}] {s}\n", .{ i, msg });
        }
    }

    std.debug.print("\nWriting fourth message (overflowing ring buffer)...\n", .{});
    try memSink.write(&r4, globalConfig);
    try memSink.flush();

    {
        const msgs = try memSink.getMemoryMessages(allocator);
        defer {
            for (msgs) |m| allocator.free(m);
            allocator.free(msgs);
        }
        for (msgs, 0..) |msg, i| {
            std.debug.print("  [{d}] {s}\n", .{ i, msg });
        }
    }

    // 2. Sink Groups (Atomic Fan-out)
    std.debug.print("\n2. Sink Group Atomic Fan-out\n", .{});
    var group = logly.SinkGroup.init(allocator);
    defer group.deinit();

    var s1Cfg = logly.SinkConfig.memory();
    s1Cfg.name = "sub_sink_1";
    s1Cfg.memoryCapacity = 10;
    const s1 = owner.getSink(try owner.addSink(s1Cfg)) orelse
        return error.SinkUnavailable;

    var s2Cfg = logly.SinkConfig.memory();
    s2Cfg.name = "sub_sink_2";
    s2Cfg.memoryCapacity = 10;
    const s2 = owner.getSink(try owner.addSink(s2Cfg)) orelse
        return error.SinkUnavailable;

    try group.addSink(s1);
    try group.addSink(s2);

    var recGroup = logly.Record.init(allocator, .warning, "Group Alert: CPU High!");
    defer recGroup.deinit();

    std.debug.print("Writing to SinkGroup...\n", .{});
    try group.write(&recGroup, globalConfig);
    try group.flush();

    // Verify sub-sinks both received the message
    {
        const m1 = try s1.getMemoryMessages(allocator);
        defer {
            for (m1) |m| allocator.free(m);
            allocator.free(m1);
        }
        std.debug.print("  Sink 1 got: '{s}'\n", .{m1[0]});

        const m2 = try s2.getMemoryMessages(allocator);
        defer {
            for (m2) |m| allocator.free(m);
            allocator.free(m2);
        }
        std.debug.print("  Sink 2 got: '{s}'\n", .{m2[0]});
    }

    // 3. Health check and Rate limiting
    std.debug.print("\n3. Sink Health and Rate Limiting\n", .{});
    std.debug.print("  Is memory sink healthy? {s}\n", .{if (memSink.isHealthy()) "Yes" else "No"});

    var rateCfg = logly.SinkConfig.stderr();
    rateCfg.name = "rate_limited_stderr";
    rateCfg.rateLimitPerSecond = 2; // only allow 2 msgs/sec

    const rateSink = owner.getSink(try owner.addSink(rateCfg)) orelse
        return error.SinkUnavailable;

    std.debug.print("Writing 5 messages rapidly (expect only 2 to output)...\n", .{});
    var i: usize = 0;
    while (i < 5) : (i += 1) {
        var r = logly.Record.init(allocator, .info, "Burst message");
        defer r.deinit();
        try rateSink.write(&r, globalConfig);
    }
    try rateSink.flush();

    std.debug.print("\nAdvanced Sink Example completed successfully!\n", .{});
}
