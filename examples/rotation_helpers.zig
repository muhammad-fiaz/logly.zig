const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("Rotation Helpers Example\n\n", .{});

    var rotation = try logly.Rotation.init(allocator, "logs/app.log", "hourly", null, 7);
    defer rotation.deinit();

    if (rotation.nextRotationAt()) |epochSeconds| {
        std.debug.print("Next rotation at: {d}\n", .{epochSeconds});
    } else {
        std.debug.print("Interval rotation disabled\n", .{});
    }

    const age = rotation.rotationAgeSeconds();
    std.debug.print("Last rotation age: {d}s\n", .{age});
    std.debug.print("\nRotation helpers example completed!\n", .{});
}
