const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Enable ANSI colors on Windows (no-op elsewhere)
    _ = logly.Terminal.enableAnsiColors();

    var config = logly.Config.default();
    config.emit_system_diagnostics_on_init = true; // Log OS/arch/CPU/memory immediately
    config.include_drive_diagnostics = true; // Include per-drive totals/free space

    const logger = try logly.Logger.initWithConfig(allocator, config);
    defer logger.deinit();

    std.debug.print("Diagnostics emitted at startup via config...\n", .{});

    // Manually emit diagnostics on demand (respects include_drive_diagnostics)
    try logger.logSystemDiagnostics(@src());

    std.debug.print("\nDiagnostics example completed.\n", .{});
}
