const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    // Enable ANSI colors on Windows
    _ = logly.Terminal.enableAnsiColors();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const logger = try logly.Logger.init(allocator);
    defer logger.deinit();

    // 1. Formatted Logging
    try logger.infof("User {s} logged in with ID {d}", .{ "Alice", 12345 });
    try logger.warningf("Disk usage is at {d}%", .{85});
    try logger.errf("Failed to connect to {s}:{d}", .{ "localhost", 8080 });

    // 2. Scoped Formatted Logging
    const db_logger = logger.scoped("database");
    try db_logger.debugf("Query executed in {d}ms: {s}", .{ 15, "SELECT * FROM users" });
    try db_logger.infof("Connected to database '{s}'", .{"production_db"});

    // 3. Custom Level Formatted Logging
    try logger.addCustomLevel("AUDIT", 22, "35"); // Magenta
    try logger.customf("AUDIT", "User {s} performed action: {s}", .{ "Bob", "DELETE" });

    // 4. Mixing styles
    try logger.info("Standard message");
    try logger.infof("Formatted message with {s}", .{"arguments"});
}
