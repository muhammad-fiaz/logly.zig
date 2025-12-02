const std = @import("std");
const Level = @import("level.zig").Level;

/// Represents a single log event.
///
/// Contains all the metadata associated with a log message, including
/// timestamp, level, message content, and source location.
pub const Record = struct {
    /// Unix timestamp in milliseconds.
    timestamp: i64,
    /// Severity level of the log.
    level: Level,
    /// The actual log message.
    message: []const u8,
    /// Name of the module where the log originated (optional).
    module: ?[]const u8 = null,
    /// Name of the function where the log originated (optional).
    function: ?[]const u8 = null,
    /// Source filename (optional).
    filename: ?[]const u8 = null,
    /// Source line number (optional).
    line: ?u32 = null,
    /// Additional context key-value pairs.
    context: std.StringHashMap(std.json.Value),

    /// Creates a new log record.
    ///
    /// - `allocator`: Allocator for the context map.
    /// - `level`: Log severity.
    /// - `message`: Log message content.
    pub fn init(allocator: std.mem.Allocator, level: Level, message: []const u8) Record {
        return .{
            .timestamp = std.time.milliTimestamp(),
            .level = level,
            .message = message,
            .context = std.StringHashMap(std.json.Value).init(allocator),
        };
    }

    /// Frees resources associated with the record.
    pub fn deinit(self: *Record) void {
        self.context.deinit();
    }
};
