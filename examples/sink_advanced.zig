const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    _ = logly.Terminal.enableAnsiColors();

    std.debug.print("============================================================\n", .{});
    std.debug.print("  ADVANCED SINK DEMO (v0.2.1)\n", .{});
    std.debug.print("============================================================\n\n", .{});

    // 1. Memory Sink Demo
    std.debug.print("--- 1. In-Memory Ring Buffer Sink ---\n", .{});
    var mem_cfg = logly.SinkConfig.memory();
    mem_cfg.name = "in_memory_buffer";
    mem_cfg.memory_capacity = 3; // Keep ring buffer tiny for simple demo

    const mem_sink = try logly.Sink.init(allocator, mem_cfg);
    defer mem_sink.deinit();

    var global_config = logly.Config.default();
    global_config.auto_sink = false;

    var r1 = logly.Record.init(allocator, .info, "Message One");
    defer r1.deinit();
    var r2 = logly.Record.init(allocator, .info, "Message Two");
    defer r2.deinit();
    var r3 = logly.Record.init(allocator, .info, "Message Three");
    defer r3.deinit();
    var r4 = logly.Record.init(allocator, .info, "Message Four (Will overwrite One)");
    defer r4.deinit();

    try mem_sink.write(&r1, global_config);
    try mem_sink.write(&r2, global_config);
    try mem_sink.write(&r3, global_config);
    try mem_sink.flush(); // Memory sink parses logs on flush

    std.debug.print("Messages written: 3. Capacity: 3.\n", .{});
    {
        const msgs = try mem_sink.getMemoryMessages(allocator);
        defer {
            for (msgs) |m| allocator.free(m);
            allocator.free(msgs);
        }
        for (msgs, 0..) |msg, i| {
            std.debug.print("  [{d}] {s}\n", .{ i, msg });
        }
    }

    std.debug.print("\nWriting fourth message (overflowing ring buffer)...\n", .{});
    try mem_sink.write(&r4, global_config);
    try mem_sink.flush();

    {
        const msgs = try mem_sink.getMemoryMessages(allocator);
        defer {
            for (msgs) |m| allocator.free(m);
            allocator.free(msgs);
        }
        for (msgs, 0..) |msg, i| {
            std.debug.print("  [{d}] {s}\n", .{ i, msg });
        }
    }

    // 2. Sink Groups (Atomic Fan-out)
    std.debug.print("\n--- 2. Sink Group Atomic Fan-out ---\n", .{});
    var group = logly.SinkGroup.init(allocator);
    defer group.deinit();

    var s1_cfg = logly.SinkConfig.memory();
    s1_cfg.name = "sub_sink_1";
    s1_cfg.memory_capacity = 10;
    const s1 = try logly.Sink.init(allocator, s1_cfg);
    defer s1.deinit();

    var s2_cfg = logly.SinkConfig.memory();
    s2_cfg.name = "sub_sink_2";
    s2_cfg.memory_capacity = 10;
    const s2 = try logly.Sink.init(allocator, s2_cfg);
    defer s2.deinit();

    try group.addSink(s1);
    try group.addSink(s2);

    var rec_group = logly.Record.init(allocator, .warning, "Group Alert: CPU High!");
    defer rec_group.deinit();

    std.debug.print("Writing to SinkGroup...\n", .{});
    try group.write(&rec_group, global_config);
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
    std.debug.print("\n--- 3. Sink Health and Rate Limiting ---\n", .{});
    std.debug.print("  Is memory sink healthy? {s}\n", .{if (mem_sink.isHealthy()) "Yes" else "No"});

    var rate_cfg = logly.SinkConfig.stderr();
    rate_cfg.name = "rate_limited_stderr";
    rate_cfg.rate_limit_per_second = 2; // only allow 2 msgs/sec

    const rate_sink = try logly.Sink.init(allocator, rate_cfg);
    defer rate_sink.deinit();

    std.debug.print("Writing 5 messages rapidly (expect only 2 to output)...\n", .{});
    var i: usize = 0;
    while (i < 5) : (i += 1) {
        var r = logly.Record.init(allocator, .info, "Burst message");
        defer r.deinit();
        try rate_sink.write(&r, global_config);
    }
    try rate_sink.flush();

    std.debug.print("\nAdvanced Sink Example completed successfully!\n", .{});
}
