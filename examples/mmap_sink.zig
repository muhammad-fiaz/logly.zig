const std = @import("std");
const logly = @import("logly");

var threaded = std.Io.Threaded.init_single_threaded;
const io = threaded.io();

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("Memory-Mapped Sink Example\n\n", .{});

    // Configure a sink with mmap enabled for high-performance writes
    const logPath = "mmap_example.log";

    var sinkConfig = logly.SinkConfig.file(logPath);
    sinkConfig.name = "mmap_sink";
    sinkConfig.mmap = true; // Enable memory-mapped I/O for high-performance writes

    // Use log-only mode (no console output - we write to our mmap file sink)
    var config = logly.Config.logOnly();
    config.autoSink = false; // Disable auto console sink so our mmap sink is the only one

    const logger = try logly.Logger.initWithConfig(allocator, config);
    defer logger.deinit();

    // Add the mmap sink
    _ = try logger.addSink(sinkConfig);

    std.debug.print("[mmap] Writing 100 log records via memory-mapped sink...\n", .{});

    var i: usize = 0;
    while (i < 100) : (i += 1) {
        try logger.infof("mmap record #{d}: high-performance write", .{i}, @src());
    }

    try logger.warning("mmap sink: completed batch write.", @src());

    // Flush all sinks to ensure data is persisted
    try logger.flush();

    std.debug.print("[mmap] Completed. Log written to: {s}\n", .{logPath});

    // Read back and show first bytes using Zig 0.16 IO API
    const f = std.Io.Dir.cwd().openFile(io, logPath, .{}) catch |err| {
        std.debug.print("[mmap] Could not open output file: {any}\n", .{err});
        return;
    };
    defer f.close(io);
    defer std.Io.Dir.cwd().deleteFile(io, logPath) catch {};

    var previewBuf: [256]u8 = undefined;
    var fileBuf: [512]u8 = undefined;
    var reader = f.reader(io, &fileBuf);
    const n = reader.interface.readSliceShort(&previewBuf) catch 0;
    if (n > 0) {
        std.debug.print("[mmap] First {d} bytes of log file:\n{s}\n", .{ n, previewBuf[0..n] });
    }

    std.debug.print("\nmmap Sink Example Complete\n", .{});
}
