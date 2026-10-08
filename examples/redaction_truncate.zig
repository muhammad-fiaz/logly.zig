const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("Redaction Truncate Example\n\n", .{});

    var redactor = logly.Redactor.init(allocator);
    defer redactor.deinit();

    redactor.config.truncateLength = 8;
    redactor.config.truncateSuffix = "...";
    redactor.config.hashAlgorithm = .sha512;

    try redactor.addField("token", .truncate);
    try redactor.addField("user_id", .hash);

    const truncated = try redactor.redactField("token", "supersecretvalue");
    defer allocator.free(truncated);

    const hashed = try redactor.redactField("user_id", "user-123");
    defer allocator.free(hashed);

    std.debug.print("Truncated: {s}\n", .{truncated});
    std.debug.print("Hashed: {s}\n", .{hashed});
    std.debug.print("\nRedaction truncate example completed!\n", .{});
}
