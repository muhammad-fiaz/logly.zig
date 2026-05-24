---
title: MessagePack & Styled TUI Formatter Example
description: Learn how to utilize compact binary MessagePack logging and beautiful styled Terminal UI console cards.
---

# MessagePack & Styled TUI Formatter Example

This example demonstrates how to configure and output logs in **MessagePack binary format** for ultra-compact storage footprints, and **styled Terminal UI console cards** for local development.

For detailed concepts, see the [MessagePack Guide](/guide/msgpack) and [Terminal UI Guide](/guide/tui).

---

## Code Listing

The following is the complete source from [examples/msgpack_tui.zig](file:///c:/Users/smuha/Downloads/logly.zig/examples/msgpack_tui.zig):

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){}; 
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    _ = logly.Terminal.enableAnsiColors();

    std.debug.print("=== Logly v0.2.0 MessagePack & TUI Formatter Example ===\n\n", .{});

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
```

---

## Execution Output

When you compile and run this example with `zig build run-msgpack_tui` or `zig build example-msgpack_tui`, the console will display:

```text
=== Logly v0.2.0 MessagePack & TUI Formatter Example ===

--- 1. MessagePack Binary Format ---
Encoded 128 bytes of MessagePack binary data.
First byte (fixmap header): 0x87  (expected 0x87 for 7-field map)
Hex dump (first 32 bytes): 87 A9 74 69 6D 65 73 74 61 6D 70 CF 00 00 ...

--- 2. Terminal UI Dashboard Format ---
┌─────────────────────────────────[ WARNING ]─────────────────────────────────┐
│ Time: 2026-05-24 11:10:00.123                                               │
│ Module: sys.monitor             File: monitor.zig:88                        │
│ Message: High memory utilisation detected                                   │
├──────────────────────────────[ Record Context ]─────────────────────────────┤
│ • host: prod-node-01                                                        │
│ • mem_used_pct: 87.40                                                       │
│ • pid: 1234                                                                 │
└─────────────────────────────────────────────────────────────────────────────┘

--- 3. JSON Format (same record for comparison) ---
{"level":"WARNING","message":"High memory utilisation detected","module":"sys.monitor","file":"monitor.zig","line":88,"mem_used_pct":87.4,"pid":1234,"host":"prod-node-01"}

=== MessagePack & TUI Formatter Example Complete ===
```
