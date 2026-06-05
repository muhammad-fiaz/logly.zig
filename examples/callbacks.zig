const std = @import("std");
const logly = @import("logly");

fn logCallback(record: *const logly.Record) !void {
    if (record.level.priority() >= logly.Level.err.priority()) {
        std.debug.print("[ALERT] High severity log detected: {s}\n", .{record.message});
    }
}

fn signatureCallback(sink_name: []const u8, signature: []const u8) void {
    std.debug.print("[Signature Callback] Sink '{s}' computed SHA-256 signature: {s}\n", .{ sink_name, signature });
}

fn mmapResizeCallback(sink_name: []const u8, old_size: u64, new_size: u64) void {
    std.debug.print("[Mmap Resize Callback] Sink '{s}' resized virtual map: {d} bytes -> {d} bytes\n", .{ sink_name, old_size, new_size });
}

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== Logly v0.2.1 Callbacks Example ===\n\n", .{});

    // 1. Basic Logger Callback
    const logger = try logly.Logger.init(allocator);
    defer logger.deinit();

    logger.setLogCallback(&logCallback);

    try logger.info("Normal operation", @src());
    try logger.err("Error occurred - callback will trigger", @src());

    // 2. Cryptographic signature and Mmap Resize Callbacks
    std.debug.print("\n--- Testing Cryptographic & Memory-Mapped Callbacks ---\n\n", .{});
    const test_path = "callbacks_demo.log";
    std.Io.Dir.cwd().deleteFile(logly.Utils.io(), test_path) catch {};
    defer std.Io.Dir.cwd().deleteFile(logly.Utils.io(), test_path) catch {};

    var sink_cfg = logly.SinkPresets.file(test_path);
    sink_cfg.name = "tamper_evident_mmap_sink";
    sink_cfg.tamper_evident = true;
    sink_cfg.mmap = true;
    sink_cfg.async_write = false;

    const sink = try logly.Sink.init(allocator, sink_cfg);
    defer sink.deinit();

    // Register our new callbacks
    sink.setSignatureCallback(&signatureCallback);
    sink.setMmapResizeCallback(&mmapResizeCallback);

    var record1 = logly.Record.init(allocator, .info, "cryptographically chained message #1");
    defer record1.deinit();

    var global_config = logly.Config.default();
    global_config.auto_sink = false;

    try sink.write(&record1, global_config);

    // Manually trigger mmap resize to show the callback
    if (sink.mmap_file) |*mmap_f| {
        const old_cap = mmap_f.capacity;
        try mmap_f.grow(old_cap + 4096);
        if (sink.on_mmap_resize) |cb| {
            cb(sink.config.name orelse "unnamed_sink", old_cap, mmap_f.capacity);
        }
    }

    std.debug.print("\nCallbacks example completed!\n", .{});
}
