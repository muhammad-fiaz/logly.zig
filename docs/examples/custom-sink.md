---
title: Custom Sink Example
description: Example of routing logly output to a custom backend (database, Kafka, serial port) with logly.CustomSink.
head:
  - - meta
    - name: keywords
    - content: custom sink, custom writer, kafka, database, plugin, logly
---

# Custom Sink Example

This example demonstrates `logly.CustomSink` with a user-supplied function pointer. The same pattern is the supported way to route logly output to a backend the library does not ship with (custom binary encoder, database writer, Kafka producer, hardware serial port, ...).

> [!NOTE]
> Run with: `zig build run-custom_sink`

## Code Example

```zig
const std = @import("std");
const logly = @import("logly");

const Backend = struct {
    bytes: std.ArrayListUnmanaged(u8) = .empty,
    alloc: std.mem.Allocator,

    fn writer(data: []const u8, user_data: *anyopaque) anyerror!void {
        const self: *@This() = @ptrCast(@alignCast(user_data));
        try self.bytes.appendSlice(self.alloc, data);
    }

    fn closer(user_data: *anyopaque) void {
        const self: *@This() = @ptrCast(@alignCast(user_data));
        std.debug.print("[backend] {d} bytes stored\n", .{self.bytes.items.len});
        self.bytes.deinit(self.alloc);
    }
};

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();

    var backend: Backend = .{ .alloc = gpa.allocator() };
    var custom: logly.CustomSink = .{
        .write_fn = Backend.writer,
        .close_fn = Backend.closer,
        .user_data = @ptrCast(&backend),
        .name = "demo",
    };
    defer custom.close();

    try custom.write("[demo] hello from a custom sink\n");
    try custom.write("[demo] second line\n");
    try custom.flush();

    std.debug.print("custom sink captured {d} bytes across {d} records\n", .{
        custom.getBytesWritten(),
        custom.getRecordsWritten(),
    });
}
```

> [!CAUTION]
> `CustomSink` does not own `user_data`. Make sure the underlying state outlives the `CustomSink` or that the `close_fn` releases any resources that the writer was holding.
