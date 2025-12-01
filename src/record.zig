const std = @import("std");
const Level = @import("level.zig").Level;

pub const Record = struct {
    timestamp: i64,
    level: Level,
    message: []const u8,
    module: ?[]const u8 = null,
    function: ?[]const u8 = null,
    filename: ?[]const u8 = null,
    line: ?u32 = null,
    context: std.StringHashMap(std.json.Value),

    pub fn init(allocator: std.mem.Allocator, level: Level, message: []const u8) Record {
        return .{
            .timestamp = std.time.milliTimestamp(),
            .level = level,
            .message = message,
            .context = std.StringHashMap(std.json.Value).init(allocator),
        };
    }

    pub fn deinit(self: *Record) void {
        self.context.deinit();
    }
};
