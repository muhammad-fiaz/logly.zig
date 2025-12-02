const std = @import("std");

pub fn main() void {
    const epoch_seconds = std.time.epoch.EpochSeconds{ .secs = 0 };
    const day_seconds = epoch_seconds.getDaySeconds();
    std.debug.print("H: {d}, M: {d}, S: {d}\n", .{
        day_seconds.getHours(),
        day_seconds.getMinutes(),
        day_seconds.getSeconds(),
    });
}
