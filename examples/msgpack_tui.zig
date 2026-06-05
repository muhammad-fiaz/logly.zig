const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    _ = logly.Terminal.enableAnsiColors();

    std.debug.print("=== Logly v0.2.1 MessagePack & TUI Formatter Example ===\n\n", .{});

    // Create a sample log record
    var record = logly.Record.init(allocator, .warning, "High memory utilisation detected");
    defer record.deinit();
    record.module = "sys.monitor";
    record.function = "checkMemory";
    record.filename = "monitor.zig";
    record.line = 88;
    try record.addField("mem_used_pct", .{ .float = 87.4 });
    try record.addField("pid", .{ .integer = 1234 });
    try record.addField("host", .{ .string = "prod-node-01" });

    var formatter = logly.Formatter.init(allocator);
    defer formatter.deinit();

    // ---------------------------------------------------------------
    // 1. MessagePack Binary Format
    // ---------------------------------------------------------------
    std.debug.print("--- 1. MessagePack Binary Format ---\n", .{});
    var msgpack_config = logly.Config.default();
    msgpack_config.msgpack = true;

    const msgpack_data = try formatter.format(&record, msgpack_config);
    defer allocator.free(msgpack_data);

    std.debug.print("Encoded {d} bytes of MessagePack binary data.\n", .{msgpack_data.len});
    if (msgpack_data.len > 0) {
        // 0x87 = fixmap with 7 fields
        std.debug.print("First byte (fixmap header): 0x{X:0>2}  (expected 0x87 for 7-field map)\n", .{msgpack_data[0]});
    }
    // Print hex dump of first 32 bytes
    std.debug.print("Hex dump (first 32 bytes):", .{});
    for (msgpack_data[0..@min(32, msgpack_data.len)]) |b| {
        std.debug.print(" {X:0>2}", .{b});
    }
    std.debug.print("\n\n", .{});

    // ---------------------------------------------------------------
    // 2. Terminal UI (TUI) Dashboard Format
    // ---------------------------------------------------------------
    std.debug.print("--- 2. Terminal UI Dashboard Format ---\n", .{});
    var tui_config = logly.Config.default();
    tui_config.tui = true;

    const tui_output = try formatter.format(&record, tui_config);
    defer allocator.free(tui_output);
    std.debug.print("{s}\n", .{tui_output});

    // ---------------------------------------------------------------
    // 3. Compare with standard JSON output on the same record
    // ---------------------------------------------------------------
    std.debug.print("--- 3. JSON Format (same record for comparison) ---\n", .{});
    var json_config = logly.Config.default();
    json_config.json = true;
    json_config.show_time = false;

    const json_output = try formatter.format(&record, json_config);
    defer allocator.free(json_output);
    std.debug.print("{s}\n", .{json_output});

    std.debug.print("=== MessagePack & TUI Formatter Example Complete ===\n", .{});
}
