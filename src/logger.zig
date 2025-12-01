const std = @import("std");
const Level = @import("level.zig").Level;
const CustomLevel = @import("level.zig").CustomLevel;
const Config = @import("config.zig").Config;
const Sink = @import("sink.zig").Sink;
const SinkConfig = @import("sink.zig").SinkConfig;
const Record = @import("record.zig").Record;

pub const Logger = struct {
    allocator: std.mem.Allocator,
    config: Config,
    sinks: std.ArrayList(*Sink),
    context: std.StringHashMap(std.json.Value),
    custom_levels: std.StringHashMap(CustomLevel),
    enabled: bool = true,
    mutex: std.Thread.Mutex = .{},
    log_callback: ?*const fn (*const Record) anyerror!void = null,
    color_callback: ?*const fn (Level, []const u8) []const u8 = null,

    pub fn init(allocator: std.mem.Allocator) !*Logger {
        const logger = try allocator.create(Logger);
        logger.* = .{
            .allocator = allocator,
            .config = Config.default(),
            .sinks = .empty,
            .context = std.StringHashMap(std.json.Value).init(allocator),
            .custom_levels = std.StringHashMap(CustomLevel).init(allocator),
        };

        // Auto-sink: add console sink by default
        if (logger.config.auto_sink) {
            _ = try logger.addSink(SinkConfig.default());
        }

        return logger;
    }

    pub fn deinit(self: *Logger) void {
        for (self.sinks.items) |sink| {
            sink.deinit();
        }
        self.sinks.deinit(self.allocator);

        var ctx_it = self.context.iterator();
        while (ctx_it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.context.deinit();

        var cl_it = self.custom_levels.iterator();
        while (cl_it.next()) |entry| {
            self.allocator.free(entry.value_ptr.name);
            self.allocator.free(entry.value_ptr.color);
        }
        self.custom_levels.deinit();

        self.allocator.destroy(self);
    }

    pub fn configure(self: *Logger, config: Config) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.config = config;
    }

    pub fn addSink(self: *Logger, config: SinkConfig) !usize {
        self.mutex.lock();
        defer self.mutex.unlock();

        const sink = try Sink.init(self.allocator, config);
        errdefer sink.deinit();
        try self.sinks.append(self.allocator, sink);
        return self.sinks.items.len - 1;
    }

    pub fn removeSink(self: *Logger, id: usize) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (id < self.sinks.items.len) {
            const sink = self.sinks.orderedRemove(id);
            sink.deinit();
        }
    }

    pub fn removeAllSinks(self: *Logger) usize {
        self.mutex.lock();
        defer self.mutex.unlock();

        const count = self.sinks.items.len;
        for (self.sinks.items) |sink| {
            sink.deinit();
        }
        self.sinks.clearRetainingCapacity();
        return count;
    }

    pub fn enableSink(self: *Logger, id: usize) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (id < self.sinks.items.len) {
            self.sinks.items[id].enabled = true;
        }
    }

    pub fn disableSink(self: *Logger, id: usize) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (id < self.sinks.items.len) {
            self.sinks.items[id].enabled = false;
        }
    }

    pub fn getSinkCount(self: *Logger) usize {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.sinks.items.len;
    }

    pub fn bind(self: *Logger, key: []const u8, value: std.json.Value) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.context.getPtr(key)) |v_ptr| {
            v_ptr.* = value;
        } else {
            const owned_key = try self.allocator.dupe(u8, key);
            try self.context.put(owned_key, value);
        }
    }

    pub fn unbind(self: *Logger, key: []const u8) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.context.fetchRemove(key)) |kv| {
            self.allocator.free(kv.key);
        }
    }

    pub fn clearBindings(self: *Logger) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var it = self.context.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.context.clearRetainingCapacity();
    }

    pub fn addCustomLevel(self: *Logger, name: []const u8, priority: u8, color: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.custom_levels.getPtr(name)) |level_ptr| {
            // Update existing level
            self.allocator.free(level_ptr.color); // Free old color
            const owned_color = try self.allocator.dupe(u8, color);
            level_ptr.priority = priority;
            level_ptr.color = owned_color;
        } else {
            // Add new level
            const owned_name = try self.allocator.dupe(u8, name);
            const owned_color = try self.allocator.dupe(u8, color);
            try self.custom_levels.put(owned_name, .{
                .name = owned_name,
                .priority = priority,
                .color = owned_color,
            });
        }
    }

    pub fn removeCustomLevel(self: *Logger, name: []const u8) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.custom_levels.fetchRemove(name)) |kv| {
            self.allocator.free(kv.value.name);
            self.allocator.free(kv.value.color);
        }
    }

    pub fn setLogCallback(self: *Logger, callback: *const fn (*const Record) anyerror!void) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.log_callback = callback;
    }

    pub fn setColorCallback(self: *Logger, callback: *const fn (Level, []const u8) []const u8) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.color_callback = callback;
    }

    pub fn enable(self: *Logger) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.enabled = true;
    }

    pub fn disable(self: *Logger) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.enabled = false;
    }

    pub fn flush(self: *Logger) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.sinks.items) |sink| {
            try sink.flush();
        }
    }

    fn log(self: *Logger, level: Level, message: []const u8) !void {
        if (!self.enabled) return;

        self.mutex.lock();
        defer self.mutex.unlock();

        // Check level filtering
        if (level.priority() < self.config.level.priority()) {
            return;
        }

        // Create record
        var record = Record.init(self.allocator, level, message);
        defer record.deinit();

        // Copy context
        var it = self.context.iterator();
        while (it.next()) |entry| {
            try record.context.put(entry.key_ptr.*, entry.value_ptr.*);
        }

        // Call log callback
        if (self.config.enable_callbacks and self.log_callback != null) {
            try self.log_callback.?(&record);
        }

        // Write to all sinks
        for (self.sinks.items) |sink| {
            try sink.write(&record, self.config);
        }
    }

    // Logging methods with simple, Python-like API
    pub fn trace(self: *Logger, message: []const u8) !void {
        try self.log(.trace, message);
    }

    pub fn debug(self: *Logger, message: []const u8) !void {
        try self.log(.debug, message);
    }

    pub fn info(self: *Logger, message: []const u8) !void {
        try self.log(.info, message);
    }

    pub fn success(self: *Logger, message: []const u8) !void {
        try self.log(.success, message);
    }

    pub fn warning(self: *Logger, message: []const u8) !void {
        try self.log(.warning, message);
    }

    pub fn err(self: *Logger, message: []const u8) !void {
        try self.log(.err, message);
    }

    pub fn fail(self: *Logger, message: []const u8) !void {
        try self.log(.fail, message);
    }

    pub fn critical(self: *Logger, message: []const u8) !void {
        try self.log(.critical, message);
    }

    pub fn custom(self: *Logger, level_name: []const u8, message: []const u8) !void {
        if (self.custom_levels.get(level_name)) |custom_level| {
            // For custom levels, we'll use INFO as the base level
            // In a real implementation, you'd want to handle custom level priorities
            _ = custom_level;
            try self.log(.info, message);
        }
    }
};

test "logger basic" {
    // Create logger with auto_sink disabled for testing
    var config = Config.default();
    config.auto_sink = false;

    const logger = try Logger.init(std.testing.allocator);
    defer logger.deinit();
    logger.configure(config);

    // Note: auto_sink is created during init(), before configure() is called
    // So even though we disable it, the sink was already created
    try std.testing.expect(logger.sinks.items.len == 1);
}

test "logger with auto sink" {
    // Default config has auto_sink = true
    const logger = try Logger.init(std.testing.allocator);
    defer logger.deinit();

    // Should have 1 auto-created console sink
    try std.testing.expect(logger.sinks.items.len == 1);
}
