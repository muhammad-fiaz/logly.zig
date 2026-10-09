const std = @import("std");
const logly = @import("logly");

fn logCallback(record: *const logly.Record) !void {
    if (record.level.priority() >= logly.Level.err.priority()) {
        std.debug.print("[ALERT] High severity log detected: {s}\n", .{record.message});
    }
}

fn signatureCallback(sinkName: []const u8, signature: []const u8) void {
    std.debug.print("[Signature Callback] Sink '{s}' computed SHA-256 signature: {s}\n", .{ sinkName, signature });
}

fn mmapResizeCallback(sinkName: []const u8, oldSize: u64, newSize: u64) void {
    std.debug.print("[Mmap Resize Callback] Sink '{s}' resized virtual map: {d} bytes -> {d} bytes\n", .{ sinkName, oldSize, newSize });
}

var threaded = std.Io.Threaded.init_single_threaded;
const io = threaded.io();

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("Callbacks Example\n\n", .{});

    // 1. Basic Logger Callback
    const logger = try logly.Logger.init(allocator);
    defer logger.deinit();

    logger.setLogCallback(&logCallback);

    try logger.info("Normal operation", @src());
    try logger.err("Error occurred - callback will trigger", @src());

    // 2. Cryptographic signature and Mmap Resize Callbacks
    std.debug.print("\nTesting Cryptographic & Memory-Mapped Callbacks\n\n", .{});
    const testPath = "callbacks_demo.log";
    std.Io.Dir.cwd().deleteFile(io, testPath) catch {};
    defer std.Io.Dir.cwd().deleteFile(io, testPath) catch {};

    var sinkCfg = logly.SinkPresets.file(testPath);
    sinkCfg.name = "tamper_evident_mmap_sink";
    sinkCfg.tamperEvident = true;
    sinkCfg.mmap = true;
    sinkCfg.asyncWrite = false;

    var globalConfig = logly.Config.default();
    globalConfig.autoSink = false;

    // Register through the logger so the sink is owned and cleaned up, then
    // take the handle back to attach callbacks.
    const owner = try logly.Logger.initWithConfig(allocator, globalConfig);
    defer owner.deinit();

    const sink = owner.getSink(try owner.addSink(sinkCfg)) orelse
        return error.SinkUnavailable;

    // Register our new callbacks
    sink.setSignatureCallback(&signatureCallback);
    sink.setMmapResizeCallback(&mmapResizeCallback);

    var record1 = logly.Record.init(allocator, .info, "cryptographically chained message #1");
    defer record1.deinit();

    try sink.write(&record1, globalConfig);

    // Manually trigger mmap resize to show the callback
    if (sink.mmapFile) |*mmapF| {
        const oldCap = mmapF.capacity;
        try mmapF.grow(oldCap + 4096);
        if (sink.onMmapResize) |cb| {
            cb(sink.config.name orelse "unnamed_sink", oldCap, mmapF.capacity);
        }
    }

    std.debug.print("\nCallbacks example completed!\n", .{});
}
