const std = @import("std");
const logly = @import("logly");

// Demonstrates the `CustomSink` generic writer. It accepts any
// user-supplied function pointer so you can route logly output to
// storage backends the library does not ship with: a database
// connection, a Kafka producer, a remote syslog daemon over a
// proprietary wire protocol, a serial port, or simply a custom
// file format you control end-to-end.

const Captured = struct {
    bytes: std.ArrayList(u8) = .empty,
    alloc: std.mem.Allocator,

    fn writer(data: []const u8, user_data: *anyopaque) anyerror!void {
        const self: *@This() = @ptrCast(@alignCast(user_data));
        try self.bytes.appendSlice(self.alloc, data);
    }

    fn closer(user_data: *anyopaque) void {
        _ = user_data;
    }
};

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var captured: Captured = .{ .alloc = allocator };
    defer captured.bytes.deinit(allocator);

    var custom: logly.CustomSink = .{
        .write_fn = Captured.writer,
        .close_fn = Captured.closer,
        .user_data = @ptrCast(&captured),
        .name = "demo-backend",
    };
    defer custom.close();

    // 1. Raw passthrough: write a pre-formatted string straight into the sink.
    try custom.write("[demo] hello from a custom sink\n");

    // 2. Formatter-driven path: format a logly `Record` into a stack buffer,
    //    then push the rendered bytes through the same callback. This is
    //    the supported way to feed a `CustomSink` with logly's standard
    //    layout / level coloring / module enrichment.
    var formatter = logly.Formatter.init(allocator);
    defer formatter.deinit();
    var ctx = std.StringHashMap(std.json.Value).init(allocator);
    defer ctx.deinit();

    var record: logly.Record = .{
        .timestamp = logly.Utils.currentMillis(),
        .level = .info,
        .message = "order processed",
        .module = "checkout",
        .function = "processOrder",
        .filename = "checkout.zig",
        .line = 42,
        .context = ctx,
        .allocator = allocator,
        .owned_strings = .empty,
    };

    var buf: [4096]u8 = undefined;
    const n = try formatter.formatText(&record, &buf, logly.Config{});
    try custom.write(buf[0..n]);

    // 3. Formatter returning into an unbounded arena, useful when the message
    //    might exceed the on-stack buffer. Reuses the same formatter.
    const rendered = try formatter.format(&record, logly.Config{});
    defer allocator.free(rendered);
    try custom.write(rendered);

    try custom.flush();

    std.debug.print("custom sink captured {d} bytes across {d} records\n", .{
        custom.getBytesWritten(),
        custom.getRecordsWritten(),
    });
    std.debug.print("---- captured payload ----\n{s}\n", .{captured.bytes.items});
}
