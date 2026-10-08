const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    _ = logly.Terminal.enableAnsiColors();

    std.debug.print("Hot-Reload Config Example\n\n", .{});

    // Start with display-only config (no files)
    const logger = try logly.Logger.initWithConfig(allocator, logly.Config.displayOnly());
    defer logger.deinit();

    try logger.info("Logger started with display-only config.", @src());

    // Write a sample JSON config file to disk using Zig 0.16 IO API
    const configPath = "hot_reload_test.json";
    const io = logly.Utils.io();
    {
        const f = try std.Io.Dir.cwd().createFile(io, configPath, .{});
        defer f.close(io);
        try f.writeStreamingAll(io,
            \\{"global_console_display": true, "global_file_storage": false, "color": true}
        );
    }
    defer std.Io.Dir.cwd().deleteFile(io, configPath) catch {};

    std.debug.print("[Hot-Reload] Config file written to: {s}\n", .{configPath});
    std.debug.print("[Hot-Reload] Reloading config from file...\n\n", .{});

    // Attempt to reload from file (graceful fallback on parse error)
    logger.reloadFromFile(configPath) catch |err| {
        std.debug.print("[Hot-Reload] reloadFromFile returned: {any} (graceful fallback to current config)\n", .{err});
    };

    try logger.info("Post-reload info message.", @src());
    try logger.warning("Post-reload warning message.", @src());

    std.debug.print("\n[Hot-Reload] Configuration hot-reload demonstrated successfully.\n", .{});
    std.debug.print("Hot-Reload Example Complete\n", .{});
}
