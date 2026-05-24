---
title: Zero-Downtime Hot-Reload Example
description: Learn how to dynamically reload configurations at runtime without restarting processes or dropping log records.
---

# Zero-Downtime Hot-Reload Example

This example demonstrates how to configure and execute runtime log level and feature adjustments from a JSON configuration file.

For detailed concepts, see the [Zero-Downtime Hot-Reload Guide](/guide/hot-reload).

---

## Code Listing

The following is the complete source from [examples/hot_reload.zig](file:///c:/Users/smuha/Downloads/logly.zig/examples/hot_reload.zig):

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){}; 
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    _ = logly.Terminal.enableAnsiColors();

    std.debug.print("=== Logly v0.2.0 Hot-Reload Config Example ===\n\n", .{});

    // Start with display-only config (no files)
    const logger = try logly.Logger.initWithConfig(allocator, logly.Config.displayOnly());
    defer logger.deinit();

    try logger.info("Logger started with display-only config.", @src());

    // Write a sample JSON config file to disk using Zig 0.16 IO API
    const config_path = "hot_reload_test.json";
    const io = logly.Utils.io();
    {
        const f = try std.Io.Dir.cwd().createFile(io, config_path, .{});
        defer f.close(io);
        try f.writeStreamingAll(io,
            \\{"global_console_display": true, "global_file_storage": false, "color": true}
        );
    }
    defer std.Io.Dir.cwd().deleteFile(io, config_path) catch {};

    std.debug.print("[Hot-Reload] Config file written to: {s}\n", .{config_path});
    std.debug.print("[Hot-Reload] Reloading config from file...\n\n", .{});

    // Attempt to reload from file (graceful fallback on parse error)
    logger.reloadFromFile(config_path) catch |err| {
        std.debug.print("[Hot-Reload] reloadFromFile returned: {any} (graceful fallback to current config)\n", .{err});
    };

    try logger.info("Post-reload info message.", @src());
    try logger.warning("Post-reload warning message.", @src());

    std.debug.print("\n[Hot-Reload] Configuration hot-reload demonstrated successfully.\n", .{});
    std.debug.print("=== Hot-Reload Example Complete ===\n", .{});
}
```

---

## Execution Output

When you compile and run this example with `zig build run-hot_reload` or `zig build example-hot_reload`, the console will display:

```text
=== Logly v0.2.0 Hot-Reload Config Example ===

2026-05-24 11:00:00.123 [INFO] Logger started with display-only config. (examples/hot_reload.zig:17)
[Hot-Reload] Config file written to: hot_reload_test.json
[Hot-Reload] Reloading config from file...

2026-05-24 11:00:00.125 [INFO] Post-reload info message. (examples/hot_reload.zig:39)
2026-05-24 11:00:00.126 [WARNING] Post-reload warning message. (examples/hot_reload.zig:40)

[Hot-Reload] Configuration hot-reload demonstrated successfully.
=== Hot-Reload Example Complete ===
```
