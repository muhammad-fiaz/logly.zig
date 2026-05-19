const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var sampler = logly.Sampler.init(allocator, .{ .probability = 0.2 });
    defer sampler.deinit();

    const users = [_][]const u8{ "user-123", "user-456", "user-789" };
    for (users) |user| {
        const decision = sampler.shouldSampleKey(user);
        std.debug.print("{s}: {s}\n", .{ user, if (decision) "sample" else "skip" });
    }
}
