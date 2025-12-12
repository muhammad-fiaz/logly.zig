const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Enable ANSI colors
    _ = logly.Terminal.enableAnsiColors();

    std.debug.print("=== Logly Update Checker Example ===\n\n", .{});

    // 1. Display current version
    std.debug.print("Current Version: {s}\n", .{logly.version});

    // 2. Check for updates
    // Note: This requires internet access and might fail in restricted environments
    std.debug.print("Checking for updates...\n", .{});

    // We can use the internal update checker if exposed, or just demonstrate the version check logic
    // Since UpdateChecker is internal to Logger usually, let's see if we can access it via Logger config

    var config = logly.Config.default();
    config.check_for_updates = true; // Enable update check

    const logger = try logly.Logger.initWithConfig(allocator, config);
    defer logger.deinit();

    // The update check runs in a background thread.
    // We need to wait a bit to see if it prints anything (it prints to stderr usually)
    std.debug.print("Logger initialized with update check enabled.\n", .{});
    std.debug.print("Waiting for background check (2 seconds)...\n", .{});

    std.Thread.sleep(2 * std.time.ns_per_s);

    std.debug.print("\n=== Update Check Example Complete ===\n", .{});
}
