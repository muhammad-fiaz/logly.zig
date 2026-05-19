const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var rotation = try logly.Rotation.init(allocator, "logs/app.log", "hourly", null, 7);
    defer rotation.deinit();

    if (rotation.nextRotationAt()) |epoch_seconds| {
        std.debug.print("Next rotation at: {d}\n", .{epoch_seconds});
    } else {
        std.debug.print("Interval rotation disabled\n", .{});
    }

    const age = rotation.rotationAgeSeconds();
    std.debug.print("Last rotation age: {d}s\n", .{age});
}
