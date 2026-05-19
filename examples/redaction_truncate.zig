const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var redactor = logly.Redactor.init(allocator);
    defer redactor.deinit();

    redactor.config.truncate_length = 8;
    redactor.config.truncate_suffix = "...";
    redactor.config.hash_algorithm = .sha512;

    try redactor.addField("token", .truncate);
    try redactor.addField("user_id", .hash);

    const truncated = try redactor.redactField("token", "supersecretvalue");
    defer allocator.free(truncated);

    const hashed = try redactor.redactField("user_id", "user-123");
    defer allocator.free(hashed);

    std.debug.print("Truncated: {s}\n", .{truncated});
    std.debug.print("Hashed: {s}\n", .{hashed});
}
