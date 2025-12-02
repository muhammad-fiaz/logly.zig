const std = @import("std");
const Level = @import("level.zig").Level;
const CustomLevel = @import("level.zig").CustomLevel;
const Config = @import("config.zig").Config;
const Sink = @import("sink.zig").Sink;
const SinkConfig = @import("sink.zig").SinkConfig;
const Record = @import("record.zig").Record;

/// The core Logger struct responsible for managing sinks, configuration, and log dispatch.
///
/// This struct serves as the central hub for all logging operations. It handles:
/// *   Sink management (adding, removing, enabling/disabling).
/// *   Configuration updates.
/// *   Context binding (structured logging).
/// *   Custom log levels.
/// *   Thread-safe logging dispatch.
pub const Logger = struct {
    allocator: std.mem.Allocator,
    config: Config,
    sinks: std.ArrayList(*Sink),
    context: std.StringHashMap(std.json.Value),
    custom_levels: std.StringHashMap(CustomLevel),
    module_levels: std.StringHashMap(Level),
    enabled: bool = true,
    mutex: std.Thread.Mutex = .{},
    log_callback: ?*const fn (*const Record) anyerror!void = null,
    color_callback: ?*const fn (Level, []const u8) []const u8 = null,

    /// Initializes a new Logger instance.
    ///
    /// This function allocates memory for the logger and initializes its internal structures.
    /// By default, it adds a console sink if `auto_sink` is enabled in the default config.
    ///
    /// Arguments:
    /// * `allocator`: The memory allocator to use for internal allocations.
    ///
    /// Returns:
    /// * `!*Logger`: A pointer to the initialized Logger or an error.
    pub fn init(allocator: std.mem.Allocator) !*Logger {
        const logger = try allocator.create(Logger);
        logger.* = .{
            .allocator = allocator,
            .config = Config.default(),
            .sinks = .empty,
            .context = std.StringHashMap(std.json.Value).init(allocator),
            .custom_levels = std.StringHashMap(CustomLevel).init(allocator),
            .module_levels = std.StringHashMap(Level).init(allocator),
        };

        // 🚀 Auto-sink: We add a default console sink so you can start logging immediately!
        if (logger.config.auto_sink) {
            _ = try logger.addSink(SinkConfig.default());
        }

        return logger;
    }

    /// Deinitializes the logger and frees all associated resources.
    ///
    /// This method cleans up:
    /// *   All sinks.
    /// *   Context variables.
    /// *   Custom levels.
    /// *   Module levels.
    /// *   The logger instance itself.
    pub fn deinit(self: *Logger) void {
        // 🧹 Cleanup time! Freeing all sinks.
        for (self.sinks.items) |sink| {
            sink.deinit();
        }
        self.sinks.deinit(self.allocator);

        // 🗑️ Clearing context map.
        var ctx_it = self.context.iterator();
        while (ctx_it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.context.deinit();

        // 🎨 Removing custom levels.
        var cl_it = self.custom_levels.iterator();
        while (cl_it.next()) |entry| {
            self.allocator.free(entry.value_ptr.name);
            self.allocator.free(entry.value_ptr.color);
        }
        self.custom_levels.deinit();

        // 📦 Clearing module levels.
        var ml_it = self.module_levels.iterator();
        while (ml_it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.module_levels.deinit();

        self.allocator.destroy(self);
    }

    /// Updates the logger configuration.
    ///
    /// This method is thread-safe and updates the global configuration for the logger.
    ///
    /// Arguments:
    /// * `config`: The new configuration object.
    pub fn configure(self: *Logger, config: Config) void {
        // 🔒 Thread safety first! Locking to update config.
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

    pub fn setModuleLevel(self: *Logger, module: []const u8, level: Level) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.module_levels.getPtr(module)) |level_ptr| {
            level_ptr.* = level;
        } else {
            const owned_module = try self.allocator.dupe(u8, module);
            try self.module_levels.put(owned_module, level);
        }
    }

    pub fn getModuleLevel(self: *Logger, module: []const u8) ?Level {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.module_levels.get(module);
    }

    pub fn scoped(self: *Logger, module: []const u8) ScopedLogger {
        return ScopedLogger{ .logger = self, .module = module };
    }

    fn log(self: *Logger, level: Level, message: []const u8, module: ?[]const u8) !void {
        if (!self.enabled) return;

        self.mutex.lock();
        defer self.mutex.unlock();

        // Check level filtering
        // If module is specified, check module-specific level first
        var effective_min_level = self.config.level;
        if (module) |m| {
            if (self.module_levels.get(m)) |l| {
                effective_min_level = l;
            }
        }

        if (level.priority() < effective_min_level.priority()) {
            return;
        }

        // Create record
        var record = Record.init(self.allocator, level, message);
        defer record.deinit();

        if (module) |m| {
            record.module = m;
        }

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
        try self.log(.trace, message, null);
    }

    pub fn debug(self: *Logger, message: []const u8) !void {
        try self.log(.debug, message, null);
    }

    pub fn info(self: *Logger, message: []const u8) !void {
        try self.log(.info, message, null);
    }

    pub fn success(self: *Logger, message: []const u8) !void {
        try self.log(.success, message, null);
    }

    pub fn warning(self: *Logger, message: []const u8) !void {
        try self.log(.warning, message, null);
    }

    pub fn err(self: *Logger, message: []const u8) !void {
        try self.log(.err, message, null);
    }

    pub fn fail(self: *Logger, message: []const u8) !void {
        try self.log(.fail, message, null);
    }

    pub fn critical(self: *Logger, message: []const u8) !void {
        try self.log(.critical, message, null);
    }

    pub fn custom(self: *Logger, level_name: []const u8, message: []const u8) !void {
        const level = self.custom_levels.get(level_name) orelse return error.InvalidLevel;
        const mapped_level = Level.fromPriority(level.priority) orelse .info;
        try self.log(mapped_level, message, null);
    }

    // Formatted logging methods
    pub fn tracef(self: *Logger, comptime fmt: []const u8, args: anytype) !void {
        const message = try std.fmt.allocPrint(self.allocator, fmt, args);
        defer self.allocator.free(message);
        try self.log(.trace, message, null);
    }

    pub fn debugf(self: *Logger, comptime fmt: []const u8, args: anytype) !void {
        const message = try std.fmt.allocPrint(self.allocator, fmt, args);
        defer self.allocator.free(message);
        try self.log(.debug, message, null);
    }

    pub fn infof(self: *Logger, comptime fmt: []const u8, args: anytype) !void {
        const message = try std.fmt.allocPrint(self.allocator, fmt, args);
        defer self.allocator.free(message);
        try self.log(.info, message, null);
    }

    pub fn successf(self: *Logger, comptime fmt: []const u8, args: anytype) !void {
        const message = try std.fmt.allocPrint(self.allocator, fmt, args);
        defer self.allocator.free(message);
        try self.log(.success, message, null);
    }

    pub fn warningf(self: *Logger, comptime fmt: []const u8, args: anytype) !void {
        const message = try std.fmt.allocPrint(self.allocator, fmt, args);
        defer self.allocator.free(message);
        try self.log(.warning, message, null);
    }

    pub fn errf(self: *Logger, comptime fmt: []const u8, args: anytype) !void {
        const message = try std.fmt.allocPrint(self.allocator, fmt, args);
        defer self.allocator.free(message);
        try self.log(.err, message, null);
    }

    pub fn failf(self: *Logger, comptime fmt: []const u8, args: anytype) !void {
        const message = try std.fmt.allocPrint(self.allocator, fmt, args);
        defer self.allocator.free(message);
        try self.log(.fail, message, null);
    }

    pub fn criticalf(self: *Logger, comptime fmt: []const u8, args: anytype) !void {
        const message = try std.fmt.allocPrint(self.allocator, fmt, args);
        defer self.allocator.free(message);
        try self.log(.critical, message, null);
    }

    /// Logs a message with a custom level name and format arguments.
    ///
    /// This allows for dynamic custom logging levels defined at runtime.
    ///
    /// Arguments:
    /// * `level_name`: The name of the custom level (must be registered first).
    /// * `fmt`: The format string.
    /// * `args`: The arguments for the format string.
    pub fn customf(self: *Logger, level_name: []const u8, comptime fmt: []const u8, args: anytype) !void {
        // 🕵️‍♂️ Look up the custom level. If it's not there, we can't log it.
        const level = self.custom_levels.get(level_name) orelse return error.InvalidLevel;

        // 🎨 Format the message using the provided arguments.
        const message = try std.fmt.allocPrint(self.allocator, fmt, args);
        defer self.allocator.free(message);

        // 🗺️ Map the custom level priority to a standard level for internal handling.
        // This ensures the sink logic knows how to handle it (e.g., coloring).
        const mapped_level = Level.fromPriority(level.priority) orelse .info;

        try self.log(mapped_level, message, null);
    }
};

pub const ScopedLogger = struct {
    logger: *Logger,
    module: []const u8,

    pub fn trace(self: ScopedLogger, message: []const u8) !void {
        try self.logger.log(.trace, message, self.module);
    }

    pub fn debug(self: ScopedLogger, message: []const u8) !void {
        try self.logger.log(.debug, message, self.module);
    }

    pub fn info(self: ScopedLogger, message: []const u8) !void {
        try self.logger.log(.info, message, self.module);
    }

    pub fn success(self: ScopedLogger, message: []const u8) !void {
        try self.logger.log(.success, message, self.module);
    }

    pub fn warning(self: ScopedLogger, message: []const u8) !void {
        try self.logger.log(.warning, message, self.module);
    }

    pub fn err(self: ScopedLogger, message: []const u8) !void {
        try self.logger.log(.err, message, self.module);
    }

    pub fn fail(self: ScopedLogger, message: []const u8) !void {
        try self.logger.log(.fail, message, self.module);
    }

    pub fn critical(self: ScopedLogger, message: []const u8) !void {
        try self.logger.log(.critical, message, self.module);
    }

    // Formatted logging methods for ScopedLogger
    pub fn tracef(self: ScopedLogger, comptime fmt: []const u8, args: anytype) !void {
        const message = try std.fmt.allocPrint(self.logger.allocator, fmt, args);
        defer self.logger.allocator.free(message);
        try self.logger.log(.trace, message, self.module);
    }

    pub fn debugf(self: ScopedLogger, comptime fmt: []const u8, args: anytype) !void {
        const message = try std.fmt.allocPrint(self.logger.allocator, fmt, args);
        defer self.logger.allocator.free(message);
        try self.logger.log(.debug, message, self.module);
    }

    pub fn infof(self: ScopedLogger, comptime fmt: []const u8, args: anytype) !void {
        const message = try std.fmt.allocPrint(self.logger.allocator, fmt, args);
        defer self.logger.allocator.free(message);
        try self.logger.log(.info, message, self.module);
    }

    pub fn successf(self: ScopedLogger, comptime fmt: []const u8, args: anytype) !void {
        const message = try std.fmt.allocPrint(self.logger.allocator, fmt, args);
        defer self.logger.allocator.free(message);
        try self.logger.log(.success, message, self.module);
    }

    pub fn warningf(self: ScopedLogger, comptime fmt: []const u8, args: anytype) !void {
        const message = try std.fmt.allocPrint(self.logger.allocator, fmt, args);
        defer self.logger.allocator.free(message);
        try self.logger.log(.warning, message, self.module);
    }

    pub fn errf(self: ScopedLogger, comptime fmt: []const u8, args: anytype) !void {
        const message = try std.fmt.allocPrint(self.logger.allocator, fmt, args);
        defer self.logger.allocator.free(message);
        try self.logger.log(.err, message, self.module);
    }

    pub fn failf(self: ScopedLogger, comptime fmt: []const u8, args: anytype) !void {
        const message = try std.fmt.allocPrint(self.logger.allocator, fmt, args);
        defer self.logger.allocator.free(message);
        try self.logger.log(.fail, message, self.module);
    }

    pub fn criticalf(self: ScopedLogger, comptime fmt: []const u8, args: anytype) !void {
        const message = try std.fmt.allocPrint(self.logger.allocator, fmt, args);
        defer self.logger.allocator.free(message);
        try self.logger.log(.critical, message, self.module);
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
