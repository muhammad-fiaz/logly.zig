const std = @import("std");
const Level = @import("level.zig").Level;
const Record = @import("record.zig").Record;
const Formatter = @import("formatter.zig").Formatter;
const Rotation = @import("rotation.zig").Rotation;

pub const SinkConfig = struct {
    path: ?[]const u8 = null,
    rotation: ?[]const u8 = null,
    size_limit: ?u64 = null,
    size_limit_str: ?[]const u8 = null,
    retention: ?usize = null,
    level: ?Level = null,
    async_write: bool = true,
    buffer_size: usize = 8192,
    json: bool = false,
    enabled: bool = true,

    pub fn default() SinkConfig {
        return .{};
    }
};

fn parseSize(s: []const u8) ?u64 {
    var end: usize = 0;
    while (end < s.len and std.ascii.isDigit(s[end])) : (end += 1) {}

    if (end == 0) return null;

    const num = std.fmt.parseInt(u64, s[0..end], 10) catch return null;

    // Skip whitespace
    var unit_start = end;
    while (unit_start < s.len and std.ascii.isWhitespace(s[unit_start])) : (unit_start += 1) {}

    if (unit_start >= s.len) return num; // Default to bytes if no unit

    const unit = s[unit_start..];

    if (std.ascii.eqlIgnoreCase(unit, "B")) return num;
    if (std.ascii.eqlIgnoreCase(unit, "KB") or std.ascii.eqlIgnoreCase(unit, "K")) return num * 1024;
    if (std.ascii.eqlIgnoreCase(unit, "MB") or std.ascii.eqlIgnoreCase(unit, "M")) return num * 1024 * 1024;
    if (std.ascii.eqlIgnoreCase(unit, "GB") or std.ascii.eqlIgnoreCase(unit, "G")) return num * 1024 * 1024 * 1024;
    if (std.ascii.eqlIgnoreCase(unit, "TB") or std.ascii.eqlIgnoreCase(unit, "T")) return num * 1024 * 1024 * 1024 * 1024;

    return num;
}

pub const Sink = struct {
    allocator: std.mem.Allocator,
    config: SinkConfig,
    file: ?std.fs.File = null,
    formatter: Formatter,
    rotation: ?Rotation = null,
    buffer: std.ArrayList(u8),
    mutex: std.Thread.Mutex = .{},
    enabled: bool = true,

    pub fn init(allocator: std.mem.Allocator, config: SinkConfig) !*Sink {
        const sink = try allocator.create(Sink);
        sink.* = .{
            .allocator = allocator,
            .config = config,
            .formatter = Formatter.init(allocator),
            .buffer = .empty,
            .enabled = config.enabled,
        };
        errdefer sink.deinit();

        if (config.path) |path| {
            const dir = std.fs.path.dirname(path);
            if (dir) |d| {
                try std.fs.cwd().makePath(d);
            }

            sink.file = try std.fs.cwd().createFile(path, .{
                .read = true,
                .truncate = false,
            });

            var size_limit = config.size_limit;
            if (size_limit == null and config.size_limit_str != null) {
                size_limit = parseSize(config.size_limit_str.?);
            }

            if (config.rotation != null or size_limit != null) {
                sink.rotation = try Rotation.init(
                    allocator,
                    path,
                    config.rotation,
                    size_limit,
                    config.retention,
                );
            }
        }

        return sink;
    }

    pub fn deinit(self: *Sink) void {
        self.flush() catch {};
        if (self.file) |f| f.close();
        if (self.rotation) |*r| r.deinit();
        self.buffer.deinit(self.allocator);
        self.formatter.deinit();
        self.allocator.destroy(self);
    }

    pub fn write(self: *Sink, record: *const Record, global_config: anytype) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (!self.enabled) return;

        // Check level filtering
        if (self.config.level) |min_level| {
            if (record.level.priority() < min_level.priority()) {
                return;
            }
        }

        // Check rotation
        if (self.rotation) |*rot| {
            if (self.file) |*f| {
                try rot.checkAndRotate(f);
            }
        }

        // Format the message
        const formatted = if (self.config.json or global_config.json)
            try self.formatter.formatJson(record, global_config)
        else
            try self.formatter.format(record, global_config);
        defer self.allocator.free(formatted);

        // Write to console or file
        if (self.file) |file| {
            if (global_config.global_file_storage) {
                if (self.config.async_write) {
                    try self.buffer.appendSlice(self.allocator, formatted);
                    try self.buffer.append(self.allocator, '\n');
                    if (self.buffer.items.len >= self.config.buffer_size) {
                        try self.flush();
                    }
                } else {
                    try file.writeAll(formatted);
                    try file.writeAll("\n");
                }
            }
        } else {
            // Console output
            if (global_config.global_console_display) {
                var stdout_buffer: [4096]u8 = undefined;
                var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
                const stdout = &stdout_writer.interface;
                try stdout.writeAll(formatted);
                try stdout.writeAll("\n");
                try stdout.flush();
            }
        }
    }

    pub fn flush(self: *Sink) !void {
        if (self.buffer.items.len == 0) return;
        if (self.file) |file| {
            try file.writeAll(self.buffer.items);
            self.buffer.clearRetainingCapacity();
        }
    }
};
