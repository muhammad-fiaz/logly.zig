const std = @import("std");
const Level = @import("level.zig").Level;
const CustomLevel = @import("level.zig").CustomLevel;
const Config = @import("config.zig").Config;
const Sink = @import("sink.zig").Sink;
const SinkConfig = @import("sink.zig").SinkConfig;
const Record = @import("record.zig").Record;
const Formatter = @import("formatter.zig").Formatter;
const Filter = @import("filter.zig").Filter;
const Sampler = @import("sampler.zig").Sampler;
const Redactor = @import("redactor.zig").Redactor;
const Metrics = @import("metrics.zig").Metrics;
const ThreadPool = @import("thread_pool.zig").ThreadPool;
const UpdateChecker = @import("update_checker.zig");
const Diagnostics = @import("diagnostics.zig");

/// The core Logger struct responsible for managing sinks, configuration, and log dispatch.
///
/// This struct serves as the central hub for all logging operations. It handles:
/// - Sink management (adding, removing, enabling/disabling)
/// - Configuration updates
/// - Context binding (structured logging)
/// - Custom log levels
/// - Thread-safe logging dispatch
/// - Distributed tracing context propagation
/// - Sampling and rate limiting
/// - Sensitive data redaction
/// - Metrics collection
/// - Arena allocator support for improved performance
///
/// Usage:
/// ```zig
/// var logger = try logly.Logger.init(allocator);
/// defer logger.deinit();
///
/// // Configure
/// var config = logly.Config.default();
/// config.level = .debug;
/// logger.configure(config);
///
/// // Log
/// try logger.info("Application started", .{});
/// try logger.err("An error occurred", .{});
/// ```
///
/// Callbacks:
/// - `on_record_logged`: Called when a record is successfully logged
/// - `on_record_filtered`: Called when a record is filtered/dropped before output
/// - `on_sink_error`: Called when a sink encounters an error
/// - `on_logger_initialized`: Called after logger initialization
/// - `on_logger_destroyed`: Called when logger is destroyed
///
/// Thread Safety:
/// - All public methods are thread-safe
/// - Uses std.Thread.Mutex for protecting mutable state
/// - Atomic operations for counters and statistics
pub const Logger = struct {
    /// Logger statistics for monitoring and diagnostics.
    pub const LoggerStats = struct {
        total_records_logged: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
        records_filtered: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
        sink_errors: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
        active_sinks: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),
        bytes_written: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),

        /// Calculate records per second (requires timestamp delta from caller)
        pub fn recordsPerSecond(self: *const LoggerStats, elapsed_seconds: f64) f64 {
            const total = self.total_records_logged.load(.monotonic);
            if (elapsed_seconds == 0) return 0;
            return @as(f64, @floatFromInt(total)) / elapsed_seconds;
        }

        /// Calculate average bytes per record
        pub fn avgBytesPerRecord(self: *const LoggerStats) f64 {
            const total = self.total_records_logged.load(.monotonic);
            if (total == 0) return 0;
            const bytes = self.bytes_written.load(.monotonic);
            return @as(f64, @floatFromInt(bytes)) / @as(f64, @floatFromInt(total));
        }

        /// Calculate filter rate (0.0 - 1.0)
        pub fn filterRate(self: *const LoggerStats) f64 {
            const total = self.total_records_logged.load(.monotonic);
            const filtered = self.records_filtered.load(.monotonic);
            const total_seen = total + filtered;
            if (total_seen == 0) return 0;
            return @as(f64, @floatFromInt(filtered)) / @as(f64, @floatFromInt(total_seen));
        }
    };

    allocator: std.mem.Allocator,
    config: Config,
    sinks: std.ArrayList(*Sink),
    context: std.StringHashMap(std.json.Value),
    custom_levels: std.StringHashMap(CustomLevel),
    module_levels: std.StringHashMap(Level),
    enabled: bool = true,
    atomic_level: std.atomic.Value(u8) = std.atomic.Value(u8).init(@intFromEnum(Level.info)),
    mutex: std.Thread.Mutex = .{},
    log_callback: ?*const fn (*const Record) anyerror!void = null,
    color_callback: ?*const fn (Level, []const u8) []const u8 = null,

    /// Callback invoked when a record is successfully logged.
    /// Parameters: (level: Level, message: []const u8, record: *const Record)
    on_record_logged: ?*const fn (Level, []const u8, *const Record) void = null,

    /// Callback invoked when a record is filtered/dropped before output.
    /// Parameters: (reason: []const u8, record: *const Record)
    on_record_filtered: ?*const fn ([]const u8, *const Record) void = null,

    /// Callback invoked when a sink encounters an error.
    /// Parameters: (sink_name: []const u8, error_msg: []const u8)
    on_sink_error: ?*const fn ([]const u8, []const u8) void = null,

    /// Callback invoked when logger is initialized.
    /// Parameters: (logger_stats: *const LoggerStats)
    on_logger_initialized: ?*const fn (*const LoggerStats) void = null,

    /// Callback invoked when logger is destroyed.
    /// Parameters: (final_stats: *const LoggerStats)
    on_logger_destroyed: ?*const fn (*const LoggerStats) void = null,

    /// Tracing context for distributed systems.
    trace_id: ?[]const u8 = null,
    span_id: ?[]const u8 = null,
    correlation_id: ?[]const u8 = null,

    /// Enterprise components.
    filter: ?*Filter = null,
    sampler: ?*Sampler = null,
    redactor: ?*Redactor = null,
    metrics: ?*Metrics = null,
    thread_pool: ?*ThreadPool = null,
    update_thread: ?std.Thread = null,

    /// Initialization timestamp for uptime tracking.
    init_timestamp: i64 = 0,

    /// Logger statistics for monitoring.
    stats: LoggerStats = .{},

    /// Total records processed counter.
    record_count: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),

    /// Arena allocator for temporary allocations (optional).
    /// When enabled, reduces allocation overhead for formatting operations.
    arena_state: ?std.heap.ArenaAllocator = null,

    /// The parent allocator used to create the arena (if applicable).
    parent_allocator: ?std.mem.Allocator = null,

    /// Returns the arena allocator if enabled, otherwise the main allocator.
    pub fn scratchAllocator(self: *Logger) std.mem.Allocator {
        if (self.arena_state) |*arena| {
            return arena.allocator();
        }
        return self.allocator;
    }

    /// Resets the arena allocator if enabled, freeing temporary allocations.
    /// Call this periodically in high-throughput scenarios to prevent memory growth.
    pub fn resetArena(self: *Logger) void {
        if (self.arena_state) |*arena| {
            _ = arena.reset(.retain_capacity);
        }
    }

    /// Initializes a new Logger instance.
    ///
    /// This function allocates memory for the logger and initializes its internal structures.
    /// By default, it adds a console sink if `auto_sink` is enabled in the default config.
    ///
    /// Arguments:
    ///     allocator: The memory allocator to use for internal allocations.
    ///
    /// Returns:
    ///     A pointer to the initialized Logger or an error.
    pub fn init(allocator: std.mem.Allocator) !*Logger {
        const logger = try allocator.create(Logger);
        logger.* = .{
            .allocator = allocator,
            .config = Config.default(),
            .sinks = .empty,
            .context = std.StringHashMap(std.json.Value).init(allocator),
            .custom_levels = std.StringHashMap(CustomLevel).init(allocator),
            .module_levels = std.StringHashMap(Level).init(allocator),
            .init_timestamp = std.time.timestamp(),
            .atomic_level = std.atomic.Value(u8).init(@intFromEnum(Config.default().level)),
        };

        if (logger.config.auto_sink) {
            _ = try logger.addSink(SinkConfig.default());
        }

        if (logger.config.emit_system_diagnostics_on_init) {
            logger.logSystemDiagnostics(null) catch {};
        }

        if (logger.config.check_for_updates) {
            logger.update_thread = UpdateChecker.checkForUpdates(allocator);
        }

        return logger;
    }

    /// Initializes a Logger with a specific configuration preset.
    ///
    /// Arguments:
    ///     allocator: The memory allocator to use.
    ///     config: The configuration to use.
    ///
    /// Returns:
    ///     A pointer to the initialized Logger.
    pub fn initWithConfig(allocator: std.mem.Allocator, config: Config) !*Logger {
        const logger = try allocator.create(Logger);
        logger.* = .{
            .allocator = allocator,
            .config = config,
            .sinks = .empty,
            .context = std.StringHashMap(std.json.Value).init(allocator),
            .custom_levels = std.StringHashMap(CustomLevel).init(allocator),
            .module_levels = std.StringHashMap(Level).init(allocator),
            .init_timestamp = std.time.timestamp(),
            .atomic_level = std.atomic.Value(u8).init(@intFromEnum(config.level)),
        };

        // Initialize arena allocator if configured
        if (config.use_arena_allocator) {
            logger.arena_state = std.heap.ArenaAllocator.init(allocator);
            logger.parent_allocator = allocator;
        }

        if (config.auto_sink) {
            _ = try logger.addSink(SinkConfig.default());
        }

        if (config.emit_system_diagnostics_on_init) {
            logger.logSystemDiagnostics(null) catch {};
        }

        if (config.enable_metrics) {
            const m = try allocator.create(Metrics);
            m.* = Metrics.init(allocator);
            logger.metrics = m;
        }

        if (config.thread_pool.enabled) {
            const tp = try ThreadPool.initWithConfig(allocator, config.thread_pool);
            try tp.start();
            logger.thread_pool = tp;
        }

        if (config.check_for_updates) {
            logger.update_thread = UpdateChecker.checkForUpdates(allocator);
        }

        return logger;
    }

    /// Deinitializes the logger and frees all associated resources.
    pub fn deinit(self: *Logger) void {
        if (self.update_thread) |t| {
            t.join();
        }

        if (self.thread_pool) |tp| {
            tp.deinit();
        }

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

        var ml_it = self.module_levels.iterator();
        while (ml_it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.module_levels.deinit();

        // Note: filter, sampler, and redactor are NOT owned by the logger.
        // They are set via setFilter/setSampler/setRedactor and must be
        // deinited by the caller who created them.

        if (self.metrics) |m| {
            m.deinit();
            self.allocator.destroy(m);
        }

        if (self.trace_id) |t| self.allocator.free(t);
        if (self.span_id) |s| self.allocator.free(s);
        if (self.correlation_id) |c| self.allocator.free(c);

        // Deinitialize arena allocator if it was created
        if (self.arena_state) |*arena| {
            arena.deinit();
        }

        self.allocator.destroy(self);
    }

    /// Updates the logger configuration.
    ///
    /// Arguments:
    ///     config: The new configuration object.
    pub fn configure(self: *Logger, config: Config) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.config = config;
        self.atomic_level.store(@intFromEnum(config.level), .monotonic);
    }

    /// Sets the filter for this logger.
    ///
    /// Note: The logger does NOT take ownership of the filter.
    /// The caller is responsible for keeping the filter alive and deinitializing it.
    ///
    /// Arguments:
    ///     filter: The filter instance to use.
    pub fn setFilter(self: *Logger, filter: *Filter) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.filter = filter;
    }

    /// Sets the sampler for this logger.
    ///
    /// Note: The logger does NOT take ownership of the sampler.
    /// The caller is responsible for keeping the sampler alive and deinitializing it.
    ///
    /// Arguments:
    ///     sampler: The sampler instance to use.
    pub fn setSampler(self: *Logger, sampler: *Sampler) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.sampler = sampler;
    }

    /// Sets the redactor for sensitive data masking.
    ///
    /// Note: The logger does NOT take ownership of the redactor.
    /// The caller is responsible for keeping the redactor alive and deinitializing it.
    ///
    /// Arguments:
    ///     redactor: The redactor instance to use.
    pub fn setRedactor(self: *Logger, redactor: *Redactor) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.redactor = redactor;
    }

    /// Enables metrics collection.
    pub fn enableMetrics(self: *Logger) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        if (self.metrics == null) {
            const m = self.allocator.create(Metrics) catch return;
            m.* = Metrics.init(self.allocator);
            self.metrics = m;
        }
    }

    /// Gets metrics snapshot.
    ///
    /// Returns:
    ///     A snapshot of current metrics, or null if metrics are disabled.
    pub fn getMetrics(self: *Logger) ?Metrics.Snapshot {
        if (self.metrics) |m| {
            return m.getSnapshot();
        }
        return null;
    }

    /// Sets the trace context for distributed tracing.
    ///
    /// Arguments:
    ///     trace_id: The trace identifier.
    ///     span_id: The span identifier (optional).
    pub fn setTraceContext(self: *Logger, trace_id: []const u8, span_id: ?[]const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.trace_id) |t| self.allocator.free(t);
        self.trace_id = try self.allocator.dupe(u8, trace_id);

        if (span_id) |s| {
            if (self.span_id) |old| self.allocator.free(old);
            self.span_id = try self.allocator.dupe(u8, s);
        }
    }

    /// Sets the correlation ID for request tracking.
    ///
    /// Arguments:
    ///     correlation_id: The correlation identifier.
    pub fn setCorrelationId(self: *Logger, correlation_id: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.correlation_id) |c| self.allocator.free(c);
        self.correlation_id = try self.allocator.dupe(u8, correlation_id);
    }

    /// Clears the trace context.
    pub fn clearTraceContext(self: *Logger) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.trace_id) |t| {
            self.allocator.free(t);
            self.trace_id = null;
        }
        if (self.span_id) |s| {
            self.allocator.free(s);
            self.span_id = null;
        }
        if (self.correlation_id) |c| {
            self.allocator.free(c);
            self.correlation_id = null;
        }
    }

    /// Creates a child span for nested tracing.
    ///
    /// Arguments:
    ///     name: Name for the span (used for context, not stored in span_id).
    ///
    /// Returns:
    ///     A SpanContext that automatically restores the previous span on completion.
    pub fn startSpan(self: *Logger, name: []const u8) !SpanContext {
        _ = name;
        const parent_span = self.span_id;
        const new_span = try Record.generateSpanId(self.allocator);

        self.mutex.lock();
        self.span_id = new_span;
        self.mutex.unlock();

        return SpanContext{
            .logger = self,
            .parent_span_id = parent_span,
            .start_time = std.time.nanoTimestamp(),
        };
    }

    /// Adds a new sink to the logger with the specified configuration.
    /// Thread-safe: Uses mutex for concurrent access protection.
    ///
    /// Arguments:
    ///     config: The sink configuration.
    ///
    /// Returns:
    ///     The index of the newly added sink.
    ///
    /// Also available as: `logger.add(config)`
    pub fn addSink(self: *Logger, config: SinkConfig) !usize {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Handle logs_root_path: if set and config.path exists, prepend root to path
        var modified_config = config;
        var resolved_path: ?[]u8 = null;

        if (self.config.logs_root_path != null and config.path != null) {
            const root = self.config.logs_root_path.?;
            const file = config.path.?;

            // Auto-create root directory if it doesn't exist
            std.fs.cwd().makePath(root) catch |e| {
                if (self.config.debug_mode) {
                    std.debug.print("warning: failed to auto-create logs root path '{s}': {}\n", .{ root, e });
                }
            };

            // Combine root path with file name
            resolved_path = try std.fmt.allocPrint(self.allocator, "{s}" ++ std.fs.path.sep_str ++ "{s}", .{ root, std.fs.path.basename(file) });
            modified_config.path = resolved_path;
        }
        defer if (resolved_path) |path| self.allocator.free(path);

        const sink = try Sink.init(self.allocator, modified_config);
        errdefer sink.deinit();
        try self.sinks.append(self.allocator, sink);
        return self.sinks.items.len - 1;
    }

    /// Alias for addSink() - shorter form.
    /// Usage: `_ = try logger.add(SinkConfig.file("app.log"));`
    pub const add = addSink;

    /// Removes a sink by index.
    /// Thread-safe: Uses mutex for concurrent access protection.
    pub fn removeSink(self: *Logger, id: usize) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (id < self.sinks.items.len) {
            const sink = self.sinks.orderedRemove(id);
            sink.deinit();
        }
    }

    /// Alias for removeSink() - shorter form.
    pub const remove = removeSink;

    /// Removes all sinks from the logger.
    /// Thread-safe: Uses mutex for concurrent access protection.
    ///
    /// Returns:
    ///     The number of sinks removed.
    pub fn removeAllSinks(self: *Logger) usize {
        self.mutex.lock();
        defer self.mutex.unlock();

        const removed_count = self.sinks.items.len;
        for (self.sinks.items) |sink| {
            sink.deinit();
        }
        self.sinks.clearRetainingCapacity();
        return removed_count;
    }

    /// Alias for removeAllSinks() - shorter form.
    pub const removeAll = removeAllSinks;
    pub const clear = removeAllSinks;

    /// Enables a sink by index.
    /// Thread-safe: Uses mutex for concurrent access protection.
    pub fn enableSink(self: *Logger, id: usize) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (id < self.sinks.items.len) {
            self.sinks.items[id].enabled = true;
        }
    }

    /// Disables a sink by index.
    /// Thread-safe: Uses mutex for concurrent access protection.
    pub fn disableSink(self: *Logger, id: usize) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (id < self.sinks.items.len) {
            self.sinks.items[id].enabled = false;
        }
    }

    /// Returns the number of sinks.
    /// Thread-safe: Uses mutex for concurrent access protection.
    pub fn getSinkCount(self: *Logger) usize {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.sinks.items.len;
    }

    /// Alias for getSinkCount() - shorter form.
    pub const count = getSinkCount;
    pub const sinkCount = getSinkCount;

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

    /// Sets the callback for when a record is successfully logged.
    pub fn setLoggedCallback(self: *Logger, callback: *const fn (Level, []const u8, *const Record) void) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.on_record_logged = callback;
    }

    /// Sets the callback for when a record is filtered/dropped.
    pub fn setFilteredCallback(self: *Logger, callback: *const fn ([]const u8, *const Record) void) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.on_record_filtered = callback;
    }

    /// Sets the callback for when a sink encounters an error.
    pub fn setSinkErrorCallback(self: *Logger, callback: *const fn ([]const u8, []const u8) void) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.on_sink_error = callback;
    }

    /// Sets the callback for logger initialization.
    pub fn setInitializedCallback(self: *Logger, callback: *const fn (*const LoggerStats) void) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.on_logger_initialized = callback;
    }

    /// Sets the callback for logger destruction.
    pub fn setDestroyedCallback(self: *Logger, callback: *const fn (*const LoggerStats) void) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.on_logger_destroyed = callback;
    }

    /// Returns logger statistics for monitoring and diagnostics.
    pub fn getStats(self: *Logger) LoggerStats {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.stats;
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

    pub fn ctx(self: *Logger) ContextLogger {
        return ContextLogger.init(self);
    }

    /// Returns a persistent context logger that maintains context across calls.
    /// The returned logger must be manually deinited.
    pub fn with(self: *Logger) PersistentContextLogger {
        return PersistentContextLogger.init(self);
    }

    const LogTaskContext = struct {
        logger: *Logger,
        record: Record,
    };

    fn processLogTask(ctx_ptr: *anyopaque, allocator: ?std.mem.Allocator) void {
        const task_ctx = @as(*LogTaskContext, @ptrCast(@alignCast(ctx_ptr)));
        defer {
            task_ctx.record.deinit();
            task_ctx.logger.allocator.destroy(task_ctx);
        }

        const logger = task_ctx.logger;

        // Snapshot sinks to avoid holding lock during write
        logger.mutex.lock();
        var sinks_snapshot: std.ArrayList(*Sink) = .empty;
        sinks_snapshot.appendSlice(logger.allocator, logger.sinks.items) catch {};
        logger.mutex.unlock();
        defer sinks_snapshot.deinit(logger.allocator);

        for (sinks_snapshot.items) |sink| {
            // Use the worker's arena allocator if available for formatting
            sink.writeWithAllocator(&task_ctx.record, logger.config, allocator) catch |write_err| {
                if (logger.config.debug_mode) {
                    std.debug.print("Async sink write error: {}\n", .{write_err});
                }
            };
        }
    }
    fn log(self: *Logger, level: Level, message: []const u8, module: ?[]const u8, src: ?std.builtin.SourceLocation) !void {
        return self.logWithContext(level, message, module, src, null);
    }

    pub fn logWithContext(self: *Logger, level: Level, message: []const u8, module: ?[]const u8, src: ?std.builtin.SourceLocation, extra_context: ?*std.StringHashMap(std.json.Value)) !void {
        if (!self.enabled) return;

        // Fast path: check global level if no module is specified
        if (module == null) {
            const min_val = self.atomic_level.load(.monotonic);
            if (@intFromEnum(level) < min_val) {
                return;
            }
        }

        self.mutex.lock();
        defer self.mutex.unlock();

        // Check level filtering
        var effective_min_level = self.config.level;
        if (module) |m| {
            if (self.module_levels.get(m)) |l| {
                effective_min_level = l;
            }
        }

        if (level.priority() < effective_min_level.priority()) {
            return;
        }

        // Apply sampling if configured (do early before record creation)
        if (self.sampler) |sampler| {
            if (!sampler.shouldSample()) {
                return;
            }
        }

        // Apply redaction if configured
        var final_message = message;
        var redacted_message: ?[]u8 = null;
        if (self.redactor) |redactor| {
            redacted_message = try redactor.redact(message);
            final_message = redacted_message orelse message;
        }
        defer if (redacted_message) |rm| self.allocator.free(rm);

        // Create record with enhanced fields
        var record = Record.init(self.scratchAllocator(), level, final_message);
        defer record.deinit();

        if (module) |m| {
            record.module = m;
        }

        // Capture stack trace for Error/Fatal levels if configured
        // We check if the config explicitly enables it, OR if it's an error/critical level
        // and the user hasn't explicitly disabled it (assuming default behavior was implicit).
        // However, to respect the new config strictly:
        if ((level == .err or level == .critical) and self.config.capture_stack_trace) {
            // Use the logger's main allocator for the stack trace so Record can safely free it
            const allocator = self.allocator;
            // We use catch here to avoid failing the log if allocation fails
            if (allocator.create(std.builtin.StackTrace)) |st| {
                // Allocate a larger buffer to be safe
                if (allocator.alloc(usize, 64)) |addresses| {
                    st.* = .{
                        .instruction_addresses = addresses,
                        .index = 0,
                    };
                    std.debug.captureStackTrace(null, st);

                    record.stack_trace = st;
                    record.owned_stack_trace = st;
                } else |_| {
                    allocator.destroy(st);
                }
            } else |_| {}
        }

        // Add source location if available and configured
        if (src) |s| {
            if (self.config.show_filename) {
                record.filename = s.file;
            }
            if (self.config.show_lineno) {
                record.line = s.line;
                record.column = s.column;
            }
            if (self.config.show_function) {
                record.function = s.fn_name;
            }
        }

        // Apply filter if configured (needs record)
        if (self.filter) |filter| {
            if (!filter.shouldLog(&record)) {
                return;
            }
        }

        // Add trace context
        if (self.trace_id) |t| {
            record.trace_id = t;
        }
        if (self.span_id) |s| {
            record.span_id = s;
        }
        if (self.correlation_id) |c| {
            record.correlation_id = c;
        }

        // Copy context
        var it = self.context.iterator();
        while (it.next()) |entry| {
            try record.context.put(entry.key_ptr.*, entry.value_ptr.*);
        }

        // Copy extra context
        if (extra_context) |ec| {
            var extra_it = ec.iterator();
            while (extra_it.next()) |entry| {
                try record.context.put(entry.key_ptr.*, entry.value_ptr.*);
            }
        }

        // Update metrics
        if (self.metrics) |m| {
            m.recordLog(level, final_message.len);
        }

        // Increment record count
        _ = self.record_count.fetchAdd(1, .monotonic);

        // Call log callback
        if (self.config.enable_callbacks and self.log_callback != null) {
            try self.log_callback.?(&record);
        }

        // Dispatch to thread pool if available
        if (self.thread_pool) |tp| {
            // Clone record for async processing
            // We need to clone because the original record is stack-allocated and will be deinitialized
            var cloned_rec = try record.clone(self.allocator);
            errdefer cloned_rec.deinit();

            const task_ctx = try self.allocator.create(LogTaskContext);
            task_ctx.* = .{
                .logger = self,
                .record = cloned_rec,
            };

            if (tp.submitCallback(processLogTask, task_ctx)) {
                return;
            }

            // Fallback if submission fails (e.g. queue full)
            self.allocator.destroy(task_ctx);
            cloned_rec.deinit();
        }

        // Write to all sinks
        for (self.sinks.items) |sink| {
            sink.write(&record, self.config) catch |write_err| {
                if (self.metrics) |m| {
                    m.recordError();
                }
                switch (self.config.error_handling) {
                    .silent => {},
                    .log_and_continue => {
                        std.debug.print("Sink write error: {}\n", .{write_err});
                    },
                    .fail_fast => return write_err,
                    .callback => {},
                }
            };
        }
    }

    /// Logs an error with associated error information.
    ///
    /// Arguments:
    ///     message: The error message.
    ///     err_val: The error value.
    pub fn logError(self: *Logger, message: []const u8, err_val: anyerror) !void {
        if (!self.enabled) return;

        self.mutex.lock();
        defer self.mutex.unlock();

        var record = Record.init(self.allocator, .err, message);
        defer record.deinit();

        record.error_info = .{
            .name = @errorName(err_val),
            .message = message,
            .stack_trace = null,
            .code = null,
        };

        if (self.trace_id) |t| record.trace_id = t;
        if (self.span_id) |s| record.span_id = s;

        if (self.metrics) |m| {
            m.recordLog(.err, message.len);
            m.recordError();
        }

        for (self.sinks.items) |sink| {
            try sink.write(&record, self.config);
        }
    }

    /// Logs a timed operation. Returns the duration in nanoseconds.
    ///
    /// Arguments:
    ///     level: The log level.
    ///     message: The log message.
    ///     start_time: The start timestamp from std.time.nanoTimestamp().
    ///
    /// Returns:
    ///     The duration in nanoseconds.
    pub fn logTimed(self: *Logger, level: Level, message: []const u8, start_time: i128) !i128 {
        const end_time = std.time.nanoTimestamp();
        const duration = end_time - start_time;

        if (!self.enabled) return duration;

        self.mutex.lock();
        defer self.mutex.unlock();

        var record = Record.init(self.allocator, level, message);
        defer record.deinit();

        record.duration_ns = @intCast(@max(0, duration));

        if (self.trace_id) |t| record.trace_id = t;
        if (self.span_id) |s| record.span_id = s;

        if (self.metrics) |m| {
            m.recordLog(level, message.len);
        }

        for (self.sinks.items) |sink| {
            try sink.write(&record, self.config);
        }

        return duration;
    }

    /// Returns the total number of records logged.
    pub fn getRecordCount(self: *Logger) u64 {
        return self.record_count.load(.monotonic);
    }

    /// Returns uptime in seconds since logger initialization.
    pub fn getUptime(self: *Logger) i64 {
        return std.time.timestamp() - self.init_timestamp;
    }

    /// Logs system diagnostics (OS, arch, CPU, memory, drives) as a single record.
    /// Respects Config.include_drive_diagnostics when emitting drive info.
    /// Stores structured data in Record context for custom format interpolation.
    pub fn logSystemDiagnostics(self: *Logger, src: ?std.builtin.SourceLocation) !void {
        const alloc = self.scratchAllocator();

        var diag = try Diagnostics.collect(alloc, self.config.include_drive_diagnostics);
        defer diag.deinit(alloc);

        // Build message using default structure (ASCII-safe)
        var msg = std.ArrayList(u8){};
        defer msg.deinit(alloc);

        var w = msg.writer(alloc);
        try w.print(
            "[DIAGNOSTICS] os={s} arch={s} cpu={s} cores={d}",
            .{ diag.os_tag, diag.arch, diag.cpu_model, diag.logical_cores },
        );

        if (diag.total_mem) |t| {
            const avail = diag.avail_mem orelse 0;
            try w.print(" ram_total={d}MB ram_available={d}MB", .{ t / (1024 * 1024), avail / (1024 * 1024) });
        }

        if (self.config.include_drive_diagnostics and diag.drives.len > 0) {
            try w.writeAll(" drives=[");
            for (diag.drives, 0..) |d, i| {
                const total_gb = d.total_bytes / (1024 * 1024 * 1024);
                const free_gb = d.free_bytes / (1024 * 1024 * 1024);
                try w.print("{s} total={d}GB free={d}GB", .{ d.name, total_gb, free_gb });
                if (i + 1 < diag.drives.len) try w.writeAll("; ");
            }
            try w.writeAll("]");
        }

        // Log with context data for structured formatting support
        self.mutex.lock();
        defer self.mutex.unlock();

        var record = Record.init(self.scratchAllocator(), .info, msg.items);
        defer record.deinit();

        if (src) |s| {
            if (self.config.show_filename) record.filename = s.file;
            if (self.config.show_lineno) {
                record.line = s.line;
                record.column = s.column;
            }
            if (self.config.show_function) record.function = s.fn_name;
        }

        // Store diagnostics in record context for format customization
        try record.context.put("diag.os", .{ .string = diag.os_tag });
        try record.context.put("diag.arch", .{ .string = diag.arch });
        try record.context.put("diag.cpu", .{ .string = diag.cpu_model });
        try record.context.put("diag.cores", .{ .integer = @intCast(diag.logical_cores) });
        if (diag.total_mem) |t| {
            try record.context.put("diag.ram_total_mb", .{ .integer = @intCast(t / (1024 * 1024)) });
        }
        if (diag.avail_mem) |a| {
            try record.context.put("diag.ram_avail_mb", .{ .integer = @intCast(a / (1024 * 1024)) });
        }

        // Note: diagnostics_output_path can be used by adding a separate sink for diagnostics
        // The diagnostics context fields (diag.os, diag.cpu, etc) are available for custom formats

        // Write to all sinks
        for (self.sinks.items) |sink| {
            sink.write(&record, self.config) catch |write_err| {
                if (self.metrics) |m| m.recordError();
                if (self.config.debug_mode) {
                    std.debug.print("Diagnostics write error: {}\n", .{write_err});
                }
            };
        }
    }

    // Logging methods with simple, Python-like API
    // Pass @src() from your call site to enable clickable file:line in terminal
    // Example: try logger.info("message", @src());
    pub fn trace(self: *Logger, message: []const u8, src: ?std.builtin.SourceLocation) !void {
        try self.log(.trace, message, null, src);
    }

    pub fn debug(self: *Logger, message: []const u8, src: ?std.builtin.SourceLocation) !void {
        try self.log(.debug, message, null, src);
    }

    pub fn info(self: *Logger, message: []const u8, src: ?std.builtin.SourceLocation) !void {
        try self.log(.info, message, null, src);
    }

    pub fn success(self: *Logger, message: []const u8, src: ?std.builtin.SourceLocation) !void {
        try self.log(.success, message, null, src);
    }

    /// Logs a warning message.
    /// Also available as: `logger.warn("message", @src())`
    pub fn warning(self: *Logger, message: []const u8, src: ?std.builtin.SourceLocation) !void {
        try self.log(.warning, message, null, src);
    }

    /// Alias for warning() - shorter form.
    pub const warn = warning;

    /// Logs an error message.
    /// Note: This method is named `@"error"` to use 'error' as identifier.
    /// Call it as: `logger.@"error"("message", @src())`
    /// Or use the alias: `logger.err("message", @src())`
    pub const @"error" = err;

    pub fn err(self: *Logger, message: []const u8, src: ?std.builtin.SourceLocation) !void {
        try self.log(.err, message, null, src);
    }

    pub fn fail(self: *Logger, message: []const u8, src: ?std.builtin.SourceLocation) !void {
        try self.log(.fail, message, null, src);
    }

    /// Logs a critical message.
    /// Also available as: `logger.crit("message", @src())`
    pub fn critical(self: *Logger, message: []const u8, src: ?std.builtin.SourceLocation) !void {
        try self.log(.critical, message, null, src);
    }

    /// Alias for critical() - shorter form.
    pub const crit = critical;

    pub fn custom(self: *Logger, level_name: []const u8, message: []const u8, src: ?std.builtin.SourceLocation) !void {
        const level_info = self.custom_levels.get(level_name) orelse return error.InvalidLevel;
        const mapped_level = Level.fromPriority(level_info.priority) orelse .info;
        try self.logCustomLevel(mapped_level, level_info.name, level_info.color, message, null, src);
    }

    /// Internal method to log with custom level name and color
    fn logCustomLevel(
        self: *Logger,
        level: Level,
        custom_name: []const u8,
        custom_color: []const u8,
        message: []const u8,
        module: ?[]const u8,
        src: ?std.builtin.SourceLocation,
    ) !void {
        if (!self.enabled) return;

        self.mutex.lock();
        defer self.mutex.unlock();

        // Check level filtering
        var effective_min_level = self.config.level;
        if (module) |m| {
            if (self.module_levels.get(m)) |l| {
                effective_min_level = l;
            }
        }

        if (level.priority() < effective_min_level.priority()) {
            return;
        }

        // Apply sampling if configured
        if (self.sampler) |sampler| {
            if (!sampler.shouldSample()) {
                return;
            }
        }

        // Apply redaction if configured
        var final_message = message;
        var redacted_message: ?[]u8 = null;
        if (self.redactor) |redactor| {
            redacted_message = try redactor.redact(message);
            final_message = redacted_message orelse message;
        }
        defer if (redacted_message) |rm| self.allocator.free(rm);

        // Create record with custom level info
        var record = Record.initCustom(self.scratchAllocator(), level, custom_name, custom_color, final_message);
        defer record.deinit();

        if (module) |m| {
            record.module = m;
        }

        // Add source location if available and configured
        if (src) |s| {
            if (self.config.show_filename) {
                record.filename = s.file;
            }
            if (self.config.show_lineno) {
                record.line = s.line;
                record.column = s.column;
            }
            if (self.config.show_function) {
                record.function = s.fn_name;
            }
        }

        // Apply filter if configured
        if (self.filter) |filter| {
            if (!filter.shouldLog(&record)) {
                return;
            }
        }

        // Add trace context
        if (self.trace_id) |t| {
            record.trace_id = t;
        }
        if (self.span_id) |s| {
            record.span_id = s;
        }
        if (self.correlation_id) |c| {
            record.correlation_id = c;
        }

        // Copy context
        var it = self.context.iterator();
        while (it.next()) |entry| {
            try record.context.put(entry.key_ptr.*, entry.value_ptr.*);
        }

        // Update metrics
        if (self.metrics) |m| {
            m.recordLog(level, final_message.len);
        }

        // Increment record count
        _ = self.record_count.fetchAdd(1, .monotonic);

        // Call log callback
        if (self.config.enable_callbacks and self.log_callback != null) {
            try self.log_callback.?(&record);
        }

        // Dispatch to thread pool if available
        if (self.thread_pool) |tp| {
            // Clone record for async processing
            var cloned_rec = try record.clone(self.allocator);
            errdefer cloned_rec.deinit();

            const task_ctx = try self.allocator.create(LogTaskContext);
            task_ctx.* = .{
                .logger = self,
                .record = cloned_rec,
            };

            if (tp.submitCallback(processLogTask, task_ctx)) {
                return;
            }

            // Fallback if submission fails
            self.allocator.destroy(task_ctx);
            cloned_rec.deinit();
        }

        // Write to all sinks
        for (self.sinks.items) |sink| {
            sink.write(&record, self.config) catch |write_err| {
                if (self.metrics) |m| {
                    m.recordError();
                }
                switch (self.config.error_handling) {
                    .silent => {},
                    .log_and_continue => {
                        std.debug.print("Sink write error: {}\n", .{write_err});
                    },
                    .fail_fast => return write_err,
                    .callback => {},
                }
            };
        }
    }

    // Formatted logging methods
    // Pass @src() from your call site to enable clickable file:line in terminal
    // Example: try logger.infof("value: {d}", .{42}, @src());
    pub fn tracef(self: *Logger, comptime fmt: []const u8, args: anytype, src: ?std.builtin.SourceLocation) !void {
        const message = try std.fmt.allocPrint(self.allocator, fmt, args);
        defer self.allocator.free(message);
        try self.log(.trace, message, null, src);
    }

    pub fn debugf(self: *Logger, comptime fmt: []const u8, args: anytype, src: ?std.builtin.SourceLocation) !void {
        const message = try std.fmt.allocPrint(self.allocator, fmt, args);
        defer self.allocator.free(message);
        try self.log(.debug, message, null, src);
    }

    pub fn infof(self: *Logger, comptime fmt: []const u8, args: anytype, src: ?std.builtin.SourceLocation) !void {
        const message = try std.fmt.allocPrint(self.allocator, fmt, args);
        defer self.allocator.free(message);
        try self.log(.info, message, null, src);
    }

    pub fn successf(self: *Logger, comptime fmt: []const u8, args: anytype, src: ?std.builtin.SourceLocation) !void {
        const message = try std.fmt.allocPrint(self.allocator, fmt, args);
        defer self.allocator.free(message);
        try self.log(.success, message, null, src);
    }

    /// Logs a formatted warning message.
    /// Also available as: `logger.warnf("format", .{args}, @src())`
    pub fn warningf(self: *Logger, comptime fmt: []const u8, args: anytype, src: ?std.builtin.SourceLocation) !void {
        const message = try std.fmt.allocPrint(self.allocator, fmt, args);
        defer self.allocator.free(message);
        try self.log(.warning, message, null, src);
    }

    /// Alias for warningf() - shorter form.
    pub const warnf = warningf;

    /// Logs a formatted error message.
    /// Note: This method is named `@"errorf"` to provide 'errorf' function.
    /// Call it as: `logger.errorf("format {d}", .{val}, @src())`
    /// Or use the alias: `logger.errf("format {d}", .{val}, @src())`
    pub const errorf = errf;

    pub fn errf(self: *Logger, comptime fmt: []const u8, args: anytype, src: ?std.builtin.SourceLocation) !void {
        const message = try std.fmt.allocPrint(self.allocator, fmt, args);
        defer self.allocator.free(message);
        try self.log(.err, message, null, src);
    }

    pub fn failf(self: *Logger, comptime fmt: []const u8, args: anytype, src: ?std.builtin.SourceLocation) !void {
        const message = try std.fmt.allocPrint(self.allocator, fmt, args);
        defer self.allocator.free(message);
        try self.log(.fail, message, null, src);
    }

    /// Logs a formatted critical message.
    /// Also available as: `logger.critf("format", .{args}, @src())`
    pub fn criticalf(self: *Logger, comptime fmt: []const u8, args: anytype, src: ?std.builtin.SourceLocation) !void {
        const message = try std.fmt.allocPrint(self.allocator, fmt, args);
        defer self.allocator.free(message);
        try self.log(.critical, message, null, src);
    }

    /// Alias for criticalf() - shorter form.
    pub const critf = criticalf;

    /// Logs a message with a custom level name and format arguments.
    ///
    /// This allows for dynamic custom logging levels defined at runtime.
    ///
    /// Arguments:
    ///     level_name: The name of the custom level (must be registered first).
    ///     fmt: The format string.
    ///     args: The arguments for the format string.
    ///     src: Optional source location for clickable file:line display.
    pub fn customf(self: *Logger, level_name: []const u8, comptime fmt: []const u8, args: anytype, src: ?std.builtin.SourceLocation) !void {
        const level_info = self.custom_levels.get(level_name) orelse return error.InvalidLevel;
        const message = try std.fmt.allocPrint(self.allocator, fmt, args);
        defer self.allocator.free(message);
        const mapped_level = Level.fromPriority(level_info.priority) orelse .info;
        try self.logCustomLevel(mapped_level, level_info.name, level_info.color, message, null, src);
    }
};

/// Context for span-based tracing operations.
/// Automatically restores the parent span when the span is ended.
pub const SpanContext = struct {
    logger: *Logger,
    parent_span_id: ?[]const u8,
    start_time: i128,

    /// Ends the span and logs the duration.
    ///
    /// Arguments:
    ///     message: Optional message to log with span completion.
    pub fn end(self: *SpanContext, message: ?[]const u8) !void {
        const duration = std.time.nanoTimestamp() - self.start_time;

        if (message) |msg| {
            _ = try self.logger.logTimed(.debug, msg, self.start_time);
        }

        self.logger.mutex.lock();
        defer self.logger.mutex.unlock();

        if (self.logger.span_id) |current| {
            self.logger.allocator.free(current);
        }
        self.logger.span_id = self.parent_span_id;

        _ = duration;
    }

    /// Ends the span without logging.
    pub fn endSilent(self: *SpanContext) void {
        self.logger.mutex.lock();
        defer self.logger.mutex.unlock();

        if (self.logger.span_id) |current| {
            self.logger.allocator.free(current);
        }
        self.logger.span_id = self.parent_span_id;
    }
};

pub const ScopedLogger = struct {
    logger: *Logger,
    module: []const u8,

    pub fn trace(self: ScopedLogger, message: []const u8, src: ?std.builtin.SourceLocation) !void {
        try self.logger.log(.trace, message, self.module, src);
    }

    pub fn debug(self: ScopedLogger, message: []const u8, src: ?std.builtin.SourceLocation) !void {
        try self.logger.log(.debug, message, self.module, src);
    }

    pub fn info(self: ScopedLogger, message: []const u8, src: ?std.builtin.SourceLocation) !void {
        try self.logger.log(.info, message, self.module, src);
    }

    pub fn success(self: ScopedLogger, message: []const u8, src: ?std.builtin.SourceLocation) !void {
        try self.logger.log(.success, message, self.module, src);
    }

    /// Logs a warning message with module scope.
    /// Also available as: `scoped.warn("message", @src())`
    pub fn warning(self: ScopedLogger, message: []const u8, src: ?std.builtin.SourceLocation) !void {
        try self.logger.log(.warning, message, self.module, src);
    }

    /// Alias for warning() - shorter form.
    pub const warn = warning;

    /// Logs an error message with module scope.
    /// Use `@"error"` or `err` to call this method.
    pub const @"error" = err;

    pub fn err(self: ScopedLogger, message: []const u8, src: ?std.builtin.SourceLocation) !void {
        try self.logger.log(.err, message, self.module, src);
    }

    pub fn fail(self: ScopedLogger, message: []const u8, src: ?std.builtin.SourceLocation) !void {
        try self.logger.log(.fail, message, self.module, src);
    }

    /// Logs a critical message with module scope.
    /// Also available as: `scoped.crit("message", @src())`
    pub fn critical(self: ScopedLogger, message: []const u8, src: ?std.builtin.SourceLocation) !void {
        try self.logger.log(.critical, message, self.module, src);
    }

    /// Alias for critical() - shorter form.
    pub const crit = critical;

    pub fn tracef(self: ScopedLogger, comptime fmt: []const u8, args: anytype, src: ?std.builtin.SourceLocation) !void {
        const message = try std.fmt.allocPrint(self.logger.allocator, fmt, args);
        defer self.logger.allocator.free(message);
        try self.logger.log(.trace, message, self.module, src);
    }

    pub fn debugf(self: ScopedLogger, comptime fmt: []const u8, args: anytype, src: ?std.builtin.SourceLocation) !void {
        const message = try std.fmt.allocPrint(self.logger.allocator, fmt, args);
        defer self.logger.allocator.free(message);
        try self.logger.log(.debug, message, self.module, src);
    }

    pub fn infof(self: ScopedLogger, comptime fmt: []const u8, args: anytype, src: ?std.builtin.SourceLocation) !void {
        const message = try std.fmt.allocPrint(self.logger.allocator, fmt, args);
        defer self.logger.allocator.free(message);
        try self.logger.log(.info, message, self.module, src);
    }

    pub fn successf(self: ScopedLogger, comptime fmt: []const u8, args: anytype, src: ?std.builtin.SourceLocation) !void {
        const message = try std.fmt.allocPrint(self.logger.allocator, fmt, args);
        defer self.logger.allocator.free(message);
        try self.logger.log(.success, message, self.module, src);
    }

    /// Logs a formatted warning message with module scope.
    /// Also available as: `scoped.warnf("format", .{args}, @src())`
    pub fn warningf(self: ScopedLogger, comptime fmt: []const u8, args: anytype, src: ?std.builtin.SourceLocation) !void {
        const message = try std.fmt.allocPrint(self.logger.allocator, fmt, args);
        defer self.logger.allocator.free(message);
        try self.logger.log(.warning, message, self.module, src);
    }

    /// Alias for warningf() - shorter form.
    pub const warnf = warningf;

    /// Logs a formatted error message with module scope.
    /// Use `errorf` or `errf` to call this method.
    pub const errorf = errf;

    pub fn errf(self: ScopedLogger, comptime fmt: []const u8, args: anytype, src: ?std.builtin.SourceLocation) !void {
        const message = try std.fmt.allocPrint(self.logger.allocator, fmt, args);
        defer self.logger.allocator.free(message);
        try self.logger.log(.err, message, self.module, src);
    }

    pub fn failf(self: ScopedLogger, comptime fmt: []const u8, args: anytype, src: ?std.builtin.SourceLocation) !void {
        const message = try std.fmt.allocPrint(self.logger.allocator, fmt, args);
        defer self.logger.allocator.free(message);
        try self.logger.log(.fail, message, self.module, src);
    }

    /// Logs a formatted critical message with module scope.
    /// Also available as: `scoped.critf("format", .{args}, @src())`
    pub fn criticalf(self: ScopedLogger, comptime fmt: []const u8, args: anytype, src: ?std.builtin.SourceLocation) !void {
        const message = try std.fmt.allocPrint(self.logger.allocator, fmt, args);
        defer self.logger.allocator.free(message);
        try self.logger.log(.critical, message, self.module, src);
    }

    /// Alias for criticalf() - shorter form.
    pub const critf = criticalf;
};

pub const ContextLogger = struct {
    logger: *Logger,
    context: std.StringHashMap(std.json.Value),

    pub fn init(logger: *Logger) ContextLogger {
        return .{
            .logger = logger,
            .context = std.StringHashMap(std.json.Value).init(logger.allocator),
        };
    }

    pub fn deinit(self: *ContextLogger) void {
        self.context.deinit();
    }

    pub fn str(self: *ContextLogger, key: []const u8, value: []const u8) *ContextLogger {
        self.context.put(key, .{ .string = value }) catch {};
        return self;
    }

    pub fn int(self: *ContextLogger, key: []const u8, value: i64) *ContextLogger {
        self.context.put(key, .{ .integer = value }) catch {};
        return self;
    }

    pub fn float(self: *ContextLogger, key: []const u8, value: f64) *ContextLogger {
        self.context.put(key, .{ .float = value }) catch {};
        return self;
    }

    pub fn boolean(self: *ContextLogger, key: []const u8, value: bool) *ContextLogger {
        self.context.put(key, .{ .boolean = value }) catch {};
        return self;
    }

    pub fn log(self: *ContextLogger, level: Level, message: []const u8, src: ?std.builtin.SourceLocation) !void {
        defer self.deinit();
        try self.logger.logWithContext(level, message, null, src, &self.context);
    }

    pub fn trace(self: *ContextLogger, message: []const u8) !void {
        try self.log(.trace, message, null);
    }

    pub fn debug(self: *ContextLogger, message: []const u8) !void {
        try self.log(.debug, message, null);
    }

    pub fn info(self: *ContextLogger, message: []const u8) !void {
        try self.log(.info, message, null);
    }

    pub fn warn(self: *ContextLogger, message: []const u8) !void {
        try self.log(.warning, message, null);
    }

    pub fn err(self: *ContextLogger, message: []const u8) !void {
        try self.log(.err, message, null);
    }

    pub fn critical(self: *ContextLogger, message: []const u8) !void {
        try self.log(.critical, message, null);
    }
};

/// A logger that maintains a persistent context across multiple log calls.
/// Unlike ContextLogger, this struct must be manually deinited.
pub const PersistentContextLogger = struct {
    logger: *Logger,
    context: std.StringHashMap(std.json.Value),

    pub fn init(logger: *Logger) PersistentContextLogger {
        return .{
            .logger = logger,
            .context = std.StringHashMap(std.json.Value).init(logger.allocator),
        };
    }

    pub fn deinit(self: *PersistentContextLogger) void {
        self.context.deinit();
    }

    pub fn str(self: *PersistentContextLogger, key: []const u8, value: []const u8) *PersistentContextLogger {
        self.context.put(key, .{ .string = value }) catch {};
        return self;
    }

    pub fn int(self: *PersistentContextLogger, key: []const u8, value: i64) *PersistentContextLogger {
        self.context.put(key, .{ .integer = value }) catch {};
        return self;
    }

    pub fn float(self: *PersistentContextLogger, key: []const u8, value: f64) *PersistentContextLogger {
        self.context.put(key, .{ .float = value }) catch {};
        return self;
    }

    pub fn boolean(self: *PersistentContextLogger, key: []const u8, value: bool) *PersistentContextLogger {
        self.context.put(key, .{ .boolean = value }) catch {};
        return self;
    }

    pub fn log(self: *PersistentContextLogger, level: Level, message: []const u8, src: ?std.builtin.SourceLocation) !void {
        try self.logger.logWithContext(level, message, null, src, &self.context);
    }

    pub fn trace(self: *PersistentContextLogger, message: []const u8, src: ?std.builtin.SourceLocation) !void {
        try self.log(.trace, message, src);
    }

    pub fn debug(self: *PersistentContextLogger, message: []const u8, src: ?std.builtin.SourceLocation) !void {
        try self.log(.debug, message, src);
    }

    pub fn info(self: *PersistentContextLogger, message: []const u8, src: ?std.builtin.SourceLocation) !void {
        try self.log(.info, message, src);
    }

    pub fn warn(self: *PersistentContextLogger, message: []const u8, src: ?std.builtin.SourceLocation) !void {
        try self.log(.warning, message, src);
    }

    pub fn err(self: *PersistentContextLogger, message: []const u8, src: ?std.builtin.SourceLocation) !void {
        try self.log(.err, message, src);
    }

    pub fn critical(self: *PersistentContextLogger, message: []const u8, src: ?std.builtin.SourceLocation) !void {
        try self.log(.critical, message, src);
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
