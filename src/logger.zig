//! Central logger.
//!
//! Owns sinks, configuration, and dispatch. All public methods are thread-safe.
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
const AsyncLogger = @import("async.zig").AsyncLogger;
const Constants = @import("constants.zig");
const Utils = @import("utils.zig");
const Invoke = @import("invoke.zig").Invoke;
const Color = @import("color.zig");

/// The core Logger struct responsible for managing sinks, configuration, and log dispatch.
///
/// Every level method takes a trailing `src` argument. Pass `@src()` from
/// your call site to record a clickable `file:line`, or `null` to omit it.
pub const Logger = struct {
    /// Trace context for distributed request tracking.
    pub const TraceContext = struct {
        traceId: ?[]const u8 = null,
        spanId: ?[]const u8 = null,
        parentSpanId: ?[]const u8 = null,
    };

    /// Logger-specific errors for distributed tracing helpers.
    pub const LoggerError = error{
        InvalidTraceparent,
    };

    /// Logger statistics for monitoring and diagnostics.
    pub const LoggerStats = struct {
        /// Total number of records successfully logged.
        totalRecordsLogged: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        /// Number of records filtered/dropped before output.
        recordsFiltered: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        /// Number of sink write errors encountered.
        sinkErrors: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        /// Number of currently active sinks.
        activeSinks: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),
        /// Total bytes written across all sinks.
        bytesWritten: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),

        /// Calculate records per second (requires timestamp delta from caller).
        pub fn recordsPerSecond(self: *const LoggerStats, elapsedSeconds: f64) f64 {
            const total = @as(u64, self.totalRecordsLogged.load(.monotonic));
            return Utils.safeFloatDiv(@as(f64, @floatFromInt(total)), elapsedSeconds);
        }

        /// Calculate average bytes per record.
        pub fn avgBytesPerRecord(self: *const LoggerStats) f64 {
            const total = @as(u64, self.totalRecordsLogged.load(.monotonic));
            const bytes = @as(u64, self.bytesWritten.load(.monotonic));
            return Utils.calculateAverage(bytes, total);
        }

        /// Calculate filter rate (0.0 - 1.0).
        pub fn filterRate(self: *const LoggerStats) f64 {
            const total = @as(u64, self.totalRecordsLogged.load(.monotonic));
            const filtered = @as(u64, self.recordsFiltered.load(.monotonic));
            const totalSeen = total + filtered;
            return Utils.calculateRate(filtered, totalSeen);
        }

        /// Calculate sink error rate (0.0 - 1.0).
        pub fn sinkErrorRate(self: *const LoggerStats) f64 {
            const total = @as(u64, self.totalRecordsLogged.load(.monotonic));
            const errors = @as(u64, self.sinkErrors.load(.monotonic));
            return Utils.calculateErrorRate(errors, total);
        }

        /// Returns true if any records were filtered.
        pub fn hasFiltered(self: *const LoggerStats) bool {
            return self.recordsFiltered.load(.monotonic) > 0;
        }

        /// Returns true if any sink errors occurred.
        pub fn hasSinkErrors(self: *const LoggerStats) bool {
            return self.sinkErrors.load(.monotonic) > 0;
        }

        /// Returns total records logged as u64.
        pub fn getTotalLogged(self: *const LoggerStats) u64 {
            return @as(u64, self.totalRecordsLogged.load(.monotonic));
        }

        /// Returns filtered records count as u64.
        pub fn getFiltered(self: *const LoggerStats) u64 {
            return @as(u64, self.recordsFiltered.load(.monotonic));
        }

        /// Returns sink errors count as u64.
        pub fn getSinkErrors(self: *const LoggerStats) u64 {
            return @as(u64, self.sinkErrors.load(.monotonic));
        }

        /// Returns bytes written as u64.
        pub fn getBytesWritten(self: *const LoggerStats) u64 {
            return @as(u64, self.bytesWritten.load(.monotonic));
        }

        /// Returns active sinks count as u32.
        pub fn getActiveSinks(self: *const LoggerStats) u32 {
            return self.activeSinks.load(.monotonic);
        }

        /// Calculate bytes per second (requires elapsed time in ms).
        pub fn bytesPerSecond(self: *const LoggerStats, elapsedMs: i64) f64 {
            if (elapsedMs <= 0) return 0;
            const bytes = @as(u64, self.bytesWritten.load(.monotonic));
            const seconds = @as(f64, @floatFromInt(elapsedMs)) / @as(f64, Constants.TimeConstants.msPerSecond);
            return @as(f64, @floatFromInt(bytes)) / seconds;
        }
    };

    /// Memory allocator for logger operations.
    allocator: std.mem.Allocator,
    /// Logger configuration options.
    config: Config,
    /// List of attached sinks (output destinations).
    sinks: std.ArrayList(*Sink),
    /// Bound context key-value pairs for structured logging.
    context: std.StringHashMap(std.json.Value),
    /// Custom log levels defined by the user.
    customLevels: std.StringHashMap(CustomLevel),
    /// Per-module log level overrides.
    moduleLevels: std.StringHashMap(Level),
    /// Whether the logger is enabled (false to suppress all output).
    enabled: bool = true,
    /// Atomic log level for thread-safe level checking.
    atomicLevel: std.atomic.Value(u8) = std.atomic.Value(u8).init(@backingInt(Level.info)),
    /// Temporary level override
    tempLevel: ?Level = null,
    tempLevelExpiresAt: i64 = 0,
    /// Read-write lock for thread-safe access.
    mutex: std.Io.RwLock = std.Io.RwLock.init,
    /// Legacy callback for log events.
    logCallback: ?*const fn (*const Record) anyerror!void = null,
    /// Custom color callback for level-based coloring.
    colorCallback: ?*const fn (Level, Color.Color) Color.Color = null,

    /// Callback invoked when a record is successfully logged.
    onRecordLogged: ?*const fn (Level, []const u8, *const Record) void = null,

    /// Callback invoked when a record is filtered/dropped before output.
    onRecordFiltered: ?*const fn ([]const u8, *const Record) void = null,

    /// Callback invoked when a sink encounters an error.
    onSinkError: ?*const fn ([]const u8, []const u8) void = null,

    /// Callback invoked when logger is initialized.
    onLoggerInitialized: ?*const fn (*const LoggerStats) void = null,

    /// Callback invoked when logger is destroyed.
    onLoggerDestroyed: ?*const fn (*const LoggerStats) void = null,

    /// Tracing context for distributed systems.
    traceId: ?[]const u8 = null,
    /// Span ID for distributed tracing.
    spanId: ?[]const u8 = null,
    /// Correlation ID for request tracking.
    correlationId: ?[]const u8 = null,

    /// Filter for conditional log processing.
    filter: ?*Filter = null,
    /// Sampler for throughput control.
    sampler: ?*Sampler = null,
    /// Redactor for sensitive data masking.
    redactor: ?*Redactor = null,
    /// Metrics collector for observability.
    metrics: ?*Metrics = null,
    /// Thread pool for parallel processing.
    threadPool: ?*ThreadPool = null,
    /// Async logger for high-performance buffered logging.
    asyncLogger: ?*AsyncLogger = null,
    /// Invoke engine for extra diagnostic messages.
    invoke: ?*Invoke = null,

    /// Initialization timestamp for uptime tracking.
    initTimestamp: i64 = 0,

    /// Logger statistics for monitoring.
    stats: LoggerStats = .{},

    /// Total records processed counter.
    recordCount: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),

    /// Returns the allocator for scratch/temporary allocations.
    pub fn scratchAllocator(self: *Logger) std.mem.Allocator {
        return self.allocator;
    }

    /// Allocates and initializes a logger with common base state.
    fn initBaseLogger(allocator: std.mem.Allocator, config: Config) !*Logger {
        const logger = try allocator.create(Logger);
        logger.* = .{
            .allocator = allocator,
            .config = config,
            .sinks = .empty,
            .context = std.StringHashMap(std.json.Value).init(allocator),
            .customLevels = std.StringHashMap(CustomLevel).init(allocator),
            .moduleLevels = std.StringHashMap(Level).init(allocator),
            .initTimestamp = Utils.currentSeconds(),
            .atomicLevel = std.atomic.Value(u8).init(@backingInt(config.level)),
        };

        return logger;
    }

    /// Creates the default console sink when enabled.
    fn setupStartupOutputs(self: *Logger) !void {
        if (self.config.autoSink and self.config.globalConsoleDisplay) {
            _ = try self.addSink(SinkConfig.console());
        }
    }

    /// Initializes a new Logger instance.
    ///
    /// This function allocates memory for the logger and initializes its internal structures.
    /// By default, it adds a console sink if `auto_sink` is enabled in the default config.
    pub fn init(allocator: std.mem.Allocator) !*Logger {
        const config = Config.default();
        const logger = try initBaseLogger(allocator, config);
        errdefer logger.deinit();

        try logger.setupStartupOutputs();

        if (logger.onLoggerInitialized) |cb| cb(&logger.stats);
        return logger;
    }

    /// Initializes a Logger with a specific configuration preset.
    pub fn initWithConfig(allocator: std.mem.Allocator, config: Config) !*Logger {
        const logger = try initBaseLogger(allocator, config);
        errdefer logger.deinit();

        if (config.asyncConfig.enabled) {
            const al = try AsyncLogger.initWithConfig(allocator, config.asyncConfig);
            logger.asyncLogger = al;
        }

        try logger.setupStartupOutputs();

        if (config.enableMetrics) {
            const m = try allocator.create(Metrics);
            m.* = Metrics.init(allocator);
            logger.metrics = m;
        }

        if (config.threadPool.enabled) {
            const tp = try ThreadPool.initWithConfig(allocator, config.threadPool);
            try tp.start();
            logger.threadPool = tp;
        }

        if (logger.onLoggerInitialized) |cb| cb(&logger.stats);
        return logger;
    }

    /// Deinitializes the logger and frees all associated resources.
    pub fn deinit(self: *Logger) void {
        if (self.onLoggerDestroyed) |cb| cb(&self.stats);

        if (self.threadPool) |tp| {
            tp.deinit();
        }

        if (self.asyncLogger) |al| {
            al.deinit();
        }

        for (self.sinks.items) |sink| {
            sink.deinit();
        }
        self.sinks.deinit(self.allocator);

        var ctxIt = self.context.iterator();
        while (ctxIt.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.context.deinit();

        var clIt = self.customLevels.iterator();
        while (clIt.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.customLevels.deinit();

        var mlIt = self.moduleLevels.iterator();
        while (mlIt.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.moduleLevels.deinit();

        // Note: filter, sampler, and redactor are NOT owned by the logger.
        // They are set via setFilter/setSampler/setRedactor and must be
        // deinited by the caller who created them.

        if (self.metrics) |m| {
            m.deinit();
            self.allocator.destroy(m);
        }

        if (self.traceId) |t| self.allocator.free(t);
        if (self.spanId) |s| self.allocator.free(s);
        if (self.correlationId) |c| self.allocator.free(c);

        self.allocator.destroy(self);
    }

    /// Updates the logger configuration.
    ///
    /// The swap itself is atomic under the exclusive lock: readers never
    /// observe a half-written config, and a failed load (see
    /// reloadFromFile) leaves the previous configuration untouched.
    /// Scope note: only the Config struct is swapped. Owned subsystems
    /// (sinks, sampler, redactor, metrics, thread pool, async logger) are
    /// not rebuilt, so reload changes to those areas require explicit
    /// re-creation by the caller.
    pub fn configure(self: *Logger, config: Config) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());

        self.config = config;
        self.atomicLevel.store(@backingInt(config.level), .monotonic);
    }

    /// Reloads the logger configuration from a JSON file.
    pub fn reloadFromFile(self: *Logger, filePath: []const u8) !void {
        const newConfig = try Config.loadFromFile(self.allocator, filePath);
        self.configure(newConfig);
    }

    /// Sets the filter for this logger.
    ///
    /// Note: The logger does NOT take ownership of the filter.
    /// The caller is responsible for keeping the filter alive and deinitializing it.
    pub fn setFilter(self: *Logger, filter: *Filter) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        self.filter = filter;
    }

    /// Sets the sampler for this logger.
    ///
    /// Note: The logger does NOT take ownership of the sampler.
    /// The caller is responsible for keeping the sampler alive and deinitializing it.
    pub fn setSampler(self: *Logger, sampler: *Sampler) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        self.sampler = sampler;
    }

    /// Sets the redactor for sensitive data masking.
    ///
    /// Note: The logger does NOT take ownership of the redactor.
    /// The caller is responsible for keeping the redactor alive and deinitializing it.
    pub fn setRedactor(self: *Logger, redactor: *Redactor) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        self.redactor = redactor;
    }

    /// Installs the invoke rules used to attach extra messages.
    pub fn setInvoke(self: *Logger, invoke: *Invoke) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        self.invoke = invoke;
    }

    /// Enables metrics collection.
    pub fn enableMetrics(self: *Logger) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        if (self.metrics == null) {
            const m = self.allocator.create(Metrics) catch return;
            m.* = Metrics.init(self.allocator);
            self.metrics = m;
        }
    }

    /// Gets metrics snapshot.
    pub fn getMetrics(self: *Logger) ?Metrics.Snapshot {
        if (self.metrics) |m| {
            return m.getSnapshot();
        }
        return null;
    }

    /// Sets the trace context for distributed tracing.
    pub fn setTraceContext(self: *Logger, traceId: []const u8, spanId: ?[]const u8) !void {
        {
            self.mutex.lockUncancelable(Utils.io());
            defer self.mutex.unlock(Utils.io());

            if (self.traceId) |t| self.allocator.free(t);
            self.traceId = try self.allocator.dupe(u8, traceId);

            if (spanId) |s| {
                if (self.spanId) |old| self.allocator.free(old);
                self.spanId = try self.allocator.dupe(u8, s);
            }
        }

        // Trigger callback if configured
        if (self.config.distributed.onTraceCreated) |callback| {
            callback(traceId);
        }
    }

    /// Parses a W3C `traceparent` header and updates logger trace context.
    pub fn setTraceContextFromTraceparent(self: *Logger, traceparent: []const u8) !void {
        const parsed = Utils.parseTraceparentHeader(traceparent) orelse return LoggerError.InvalidTraceparent;
        try self.setTraceContext(parsed.traceId, parsed.spanId);
    }

    /// Sets the correlation ID for request tracking.
    pub fn setCorrelationId(self: *Logger, correlationId: []const u8) !void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());

        if (self.correlationId) |c| self.allocator.free(c);
        self.correlationId = try self.allocator.dupe(u8, correlationId);
    }

    /// Clears the trace context.
    pub fn clearTraceContext(self: *Logger) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());

        if (self.traceId) |t| {
            self.allocator.free(t);
            self.traceId = null;
        }
        if (self.spanId) |s| {
            self.allocator.free(s);
            self.spanId = null;
        }
        if (self.correlationId) |c| {
            self.allocator.free(c);
            self.correlationId = null;
        }
    }

    /// Returns current trace context encoded as W3C `traceparent` header.
    ///
    /// Returns `null` when trace or span context is missing.
    pub fn getTraceparentHeader(self: *Logger, allocator: std.mem.Allocator) !?[]u8 {
        self.mutex.lockSharedUncancelable(Utils.io());
        defer self.mutex.unlockShared(Utils.io());

        const traceId = self.traceId orelse return null;
        const spanId = self.spanId orelse return null;

        return try Utils.formatTraceparentHeader(allocator, traceId, spanId, true);
    }

    /// Creates a child span for nested tracing.
    pub fn startSpan(self: *Logger, name: []const u8) !SpanContext {
        const parentSpan = self.spanId;
        const newSpan = try Record.generateSpanId(self.allocator);

        self.mutex.lockUncancelable(Utils.io());
        self.spanId = newSpan;
        self.mutex.unlock(Utils.io());

        if (self.config.distributed.onSpanCreated) |callback| {
            callback(newSpan, name);
        }

        return SpanContext{
            .logger = self,
            .parentSpanId = parentSpan,
            .startTime = Utils.currentNanos(),
        };
    }

    /// Adds a new sink to the logger with the specified configuration.
    /// Thread-safe: Uses mutex for concurrent access protection.
    ///
    /// Also available as: `logger.add(config)`
    pub fn addSink(self: *Logger, config: SinkConfig) !usize {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());

        // Reject file sinks when file storage is globally disabled.
        // Prevents creating stray empty files in display-only mode.
        // The null device (NUL, /dev/null) is always allowed since it
        // discards output without creating files (used for benchmarking).
        if (!self.config.globalFileStorage) {
            const isFile = config.path != null and !config.isMemory and
                !std.mem.startsWith(u8, config.path.?, "tcp://") and
                !std.mem.startsWith(u8, config.path.?, "udp://") and
                !Sink.isNullDevicePath(config.path.?);
            if (isFile) return error.FileStorageDisabled;
        }

        // Reject console sinks when console display is globally disabled.
        if (!self.config.globalConsoleDisplay) {
            const isConsole = config.path == null and !config.isMemory and !config.eventLog;
            if (isConsole) return error.ConsoleDisplayDisabled;
        }

        // Reject event-log sinks whose effective format the transport
        // cannot carry (binary, or syslog framing the daemon would double).
        // Sink.init covers the explicit per-sink selection; this covers the
        // inherited logger-wide selection.
        if (config.eventLog and config.format == null) {
            switch (self.config.format) {
                .msgpack, .syslog, .syslog3164 => return error.UnsupportedFormatForSink,
                .text, .json, .ndjson, .logfmt => {},
            }
        }

        // Edge case: if adding a console sink (path == null, not file/network/memory),
        // auto-disable auto_sink to prevent duplicate console output.
        const isConsole = config.path == null and !config.isMemory and !config.eventLog;
        if (isConsole and self.config.autoSink) {
            self.config.autoSink = false;
        }

        // Handle logs_root_path: if set and config.path exists, prepend root to path
        var modifiedConfig = config;
        var resolvedPath: ?[]u8 = null;

        if (self.config.logsRootPath != null and config.path != null) {
            const root = self.config.logsRootPath.?;
            const file = config.path.?;

            // Auto-create root directory if it doesn't exist
            std.Io.Dir.cwd().createDirPath(Utils.io(), root) catch |e| {
                if (self.config.debugMode) {
                    std.debug.print("warning: failed to auto-create logs root path '{s}': {}\n", .{ root, e });
                }
            };

            // Combine root path with file name
            resolvedPath = try std.fmt.allocPrint(self.allocator, "{s}" ++ std.fs.path.sep_str ++ "{s}", .{ root, std.fs.path.basename(file) });
            modifiedConfig.path = resolvedPath;
        }
        defer if (resolvedPath) |path| self.allocator.free(path);

        const sink = try Sink.init(self.allocator, modifiedConfig);
        errdefer sink.deinit();

        // JSON-array file sinks using the inherited logger-wide format need
        // the same document reconciliation as explicit per-sink selection
        // (Sink.init only sees the sink config). Memory-mapped files keep
        // restart semantics and are excluded.
        if (sink.file != null and !sink.config.mmap and modifiedConfig.format == null) {
            if (self.config.format == .json and !sink.jsonArrayOpen) {
                try sink.ensureJsonArrayOpen();
            }
        }

        if (self.asyncLogger) |al| {
            try al.addSink(sink);
            // When using async logger, we don't track sinks in the main logger
            // Return a dummy index since sink management isn't supported
            return 0;
        } else {
            try self.sinks.append(self.allocator, sink);
            return self.sinks.items.len - 1;
        }
    }

    /// Alias for addSink() - shorter form.
    /// Usage: `_ = try logger.add(SinkConfig.file("app.log"));`
    /// Removes a sink by index.
    /// Thread-safe: Uses mutex for concurrent access protection.
    pub fn removeSink(self: *Logger, id: usize) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());

        if (self.asyncLogger != null) {
            // Async logger doesn't support removing sinks dynamically
            return;
        }

        if (id < self.sinks.items.len) {
            const sink = self.sinks.orderedRemove(id);
            sink.deinit();
        }
    }

    /// Removes all sinks from the logger.
    /// Thread-safe: Uses mutex for concurrent access protection.
    pub fn removeAllSinks(self: *Logger) usize {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());

        if (self.asyncLogger != null) {
            // Async logger doesn't support removing sinks dynamically
            return 0;
        }

        const removedCount = self.sinks.items.len;
        for (self.sinks.items) |sink| {
            sink.deinit();
        }
        self.sinks.clearRetainingCapacity();
        return removedCount;
    }

    /// Enables a sink by index.
    /// Thread-safe: Uses mutex for concurrent access protection.
    pub fn enableSink(self: *Logger, id: usize) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());

        if (id < self.sinks.items.len) {
            self.sinks.items[id].enabled = true;
        }
    }

    /// Disables a sink by index.
    /// Thread-safe: Uses mutex for concurrent access protection.
    pub fn disableSink(self: *Logger, id: usize) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());

        if (id < self.sinks.items.len) {
            self.sinks.items[id].enabled = false;
        }
    }

    /// Returns the number of sinks.
    /// Thread-safe: Uses mutex for concurrent access protection.
    pub fn getSinkCount(self: *Logger) usize {
        self.mutex.lockSharedUncancelable(Utils.io());
        defer self.mutex.unlockShared(Utils.io());
        return self.sinks.items.len;
    }

    /// Short form of `addSink`.
    pub const add = addSink;
    /// Short form of `removeSink`.
    pub const remove = removeSink;
    /// Short form of `removeAllSinks`.
    pub const removeAll = removeAllSinks;

    /// Enables async logging if an async logger is configured.
    /// Thread-safe: Uses mutex for concurrent access protection.
    pub fn enableAsync(self: *Logger) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());

        if (self.asyncLogger) |al| {
            al.running.store(true, .monotonic);
        }
    }

    /// Disables async logging if an async logger is configured.
    /// Thread-safe: Uses mutex for concurrent access protection.
    pub fn disableAsync(self: *Logger) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());

        if (self.asyncLogger) |al| {
            al.running.store(false, .monotonic);
        }
    }

    /// Checks if async logging is enabled and running.
    /// Thread-safe: Uses mutex for concurrent access protection.
    pub fn isAsyncEnabled(self: *Logger) bool {
        self.mutex.lockSharedUncancelable(Utils.io());
        defer self.mutex.unlockShared(Utils.io());

        if (self.asyncLogger) |al| {
            return al.running.load(.monotonic);
        }
        return false;
    }

    /// Enables auto-flush for all logging operations.
    /// Thread-safe: Uses mutex for concurrent access protection.
    pub fn enableAutoFlush(self: *Logger) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        self.config.autoFlush = true;
    }

    /// Disables auto-flush for all logging operations.
    /// Thread-safe: Uses mutex for concurrent access protection.
    pub fn disableAutoFlush(self: *Logger) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        self.config.autoFlush = false;
    }

    /// Checks if auto-flush is enabled.
    /// Thread-safe: Uses mutex for concurrent access protection.
    pub fn isAutoFlushEnabled(self: *Logger) bool {
        self.mutex.lockSharedUncancelable(Utils.io());
        defer self.mutex.unlockShared(Utils.io());
        return self.config.autoFlush;
    }

    /// Returns a pointer to the sink at the given index.
    /// Thread-safe: Uses mutex for concurrent access protection.
    pub fn getSink(self: *Logger, id: usize) ?*Sink {
        self.mutex.lockSharedUncancelable(Utils.io());
        defer self.mutex.unlockShared(Utils.io());

        if (id < self.sinks.items.len) {
            return self.sinks.items[id];
        }
        return null;
    }

    /// Returns the stats for a specific sink.
    /// Thread-safe: Uses mutex for concurrent access protection.
    pub fn getSinkStats(self: *Logger, id: usize) ?Sink.SinkStats {
        self.mutex.lockSharedUncancelable(Utils.io());
        defer self.mutex.unlockShared(Utils.io());

        if (id < self.sinks.items.len) {
            return self.sinks.items[id].stats;
        }
        return null;
    }

    /// Checks if a sink is enabled by index.
    /// Thread-safe: Uses mutex for concurrent access protection.
    pub fn isSinkEnabled(self: *Logger, id: usize) bool {
        self.mutex.lockSharedUncancelable(Utils.io());
        defer self.mutex.unlockShared(Utils.io());

        if (id < self.sinks.items.len) {
            return self.sinks.items[id].enabled;
        }
        return false;
    }

    /// Attaches a key/value pair to every later record. The key is copied.
    pub fn bind(self: *Logger, key: []const u8, value: std.json.Value) !void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());

        if (self.context.getPtr(key)) |vPtr| {
            vPtr.* = value;
        } else {
            const ownedKey = try self.allocator.dupe(u8, key);
            try self.context.put(ownedKey, value);
        }
    }

    /// Removes a previously bound context key.
    pub fn unbind(self: *Logger, key: []const u8) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());

        if (self.context.fetchRemove(key)) |kv| {
            self.allocator.free(kv.key);
        }
    }

    /// Removes every bound context key.
    pub fn clearBindings(self: *Logger) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());

        var it = self.context.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.context.clearRetainingCapacity();
    }

    /// Adds a new custom log level. Returns error if level already exists.
    /// Use updateCustomLevel() to update an existing level.
    pub fn addCustomLevel(self: *Logger, name: []const u8, priority: u8, color: Color.Color) !void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());

        if (self.customLevels.contains(name)) {
            return error.LevelAlreadyExists;
        }

        const ownedName = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(ownedName);

        try self.customLevels.put(ownedName, .{
            .name = ownedName,
            .priority = priority,
            .color = color,
        });
    }

    /// Updates an existing custom log level, or adds it if it doesn't exist.
    /// Use this when you want to allow updates.
    pub fn updateCustomLevel(self: *Logger, name: []const u8, priority: u8, color: Color.Color) !void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());

        if (self.customLevels.getPtr(name)) |levelPtr| {
            // Update existing level (Color is a value; no allocation).
            levelPtr.priority = priority;
            levelPtr.color = color;
        } else {
            // Add new level
            const ownedName = try self.allocator.dupe(u8, name);
            errdefer self.allocator.free(ownedName);

            try self.customLevels.put(ownedName, .{
                .name = ownedName,
                .priority = priority,
                .color = color,
            });
        }
    }

    /// Checks if a custom level with the given name exists.
    pub fn hasCustomLevel(self: *Logger, name: []const u8) bool {
        self.mutex.lockSharedUncancelable(Utils.io());
        defer self.mutex.unlockShared(Utils.io());
        return self.customLevels.contains(name);
    }

    /// Returns the count of custom levels.
    pub fn getCustomLevelCount(self: *Logger) usize {
        self.mutex.lockSharedUncancelable(Utils.io());
        defer self.mutex.unlockShared(Utils.io());
        return self.customLevels.count();
    }

    /// Removes a custom level by name. Unknown names are ignored.
    pub fn removeCustomLevel(self: *Logger, name: []const u8) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());

        if (self.customLevels.fetchRemove(name)) |kv| {
            self.allocator.free(kv.key);
        }
    }

    /// Invokes `callback` for each emitted record. The callback must not call back into the logger.
    pub fn setLogCallback(self: *Logger, callback: *const fn (*const Record) anyerror!void) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        self.logCallback = callback;
    }

    /// Sets the color callback invoked to override per-level colors.
    ///
    /// Invoked outside the logger lock with no shared state held, but the
    /// callback must still not call Logger methods: re-entering the logger
    /// from any user callback risks deadlock (shared-lock re-acquisition
    /// blocks when a writer is waiting). Keep callbacks pure and non-blocking.
    pub fn setColorCallback(self: *Logger, callback: *const fn (Level, Color.Color) Color.Color) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        self.colorCallback = callback;
    }

    /// Sets the callback for when a record is successfully logged.
    ///
    /// Fires after the record is dispatched. The callback must be
    /// non-blocking and must not call back into Logger methods: it runs
    /// under the logger lock, so reentry deadlocks.
    pub fn setLoggedCallback(self: *Logger, callback: *const fn (Level, []const u8, *const Record) void) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        self.onRecordLogged = callback;
    }

    /// Sets the callback for when a record is filtered/dropped.
    ///
    /// Receives the filter's denial reason. Same non-reentrancy contract
    /// as setLoggedCallback (runs under the logger lock).
    pub fn setFilteredCallback(self: *Logger, callback: *const fn ([]const u8, *const Record) void) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        self.onRecordFiltered = callback;
    }

    /// Sets the callback for when a sink encounters an error.
    ///
    /// Fires when errorHandling is .callback, with the sink name (or path,
    /// or "console") and the error name. Same non-reentrancy contract as
    /// setLoggedCallback.
    pub fn setSinkErrorCallback(self: *Logger, callback: *const fn ([]const u8, []const u8) void) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        self.onSinkError = callback;
    }

    /// Sets the callback for logger initialization.
    pub fn setInitializedCallback(self: *Logger, callback: *const fn (*const LoggerStats) void) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        self.onLoggerInitialized = callback;
    }

    /// Sets the callback for logger destruction.
    pub fn setDestroyedCallback(self: *Logger, callback: *const fn (*const LoggerStats) void) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        self.onLoggerDestroyed = callback;
    }

    /// Returns logger statistics for monitoring and diagnostics.
    pub fn getStats(self: *Logger) LoggerStats {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());

        return self.stats;
    }

    /// Re-enables logging after `disable`.
    pub fn enable(self: *Logger) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        self.enabled = true;
    }

    /// Drops every record until `enable` is called. Buffered sinks are still flushed on deinit.
    pub fn disable(self: *Logger) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        self.enabled = false;
    }

    /// Flushes all sinks, guaranteeing durability as defined below.
    ///
    /// Synchronous sinks: buffered data is written to the underlying
    /// transport (file, console, socket) before return.
    /// Asynchronous logger: queued records are processed by workers and
    /// each sink is flushed; returns after workers drain (bounded by the
    /// async shutdown timeout, after which pending items are dropped and
    /// counted in metrics).
    /// Network sinks: bytes are handed to the OS socket (no remote
    /// durability implied; TCP does not acknowledge application persistence).
    ///
    /// Takes the exclusive lock; concurrent producers block until flush
    /// completes. Thread-safe. Never invokes user callbacks while held.
    pub fn flush(self: *Logger) !void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        try self.flushInternal();
    }

    fn flushInternal(self: *Logger) !void {
        if (self.asyncLogger) |al| {
            al.flushSync();
        }
        for (self.sinks.items) |sink| {
            try sink.flush();
        }
    }

    /// Overrides the minimum level for one module prefix.
    pub fn setModuleLevel(self: *Logger, module: []const u8, level: Level) !void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());

        if (self.moduleLevels.getPtr(module)) |levelPtr| {
            levelPtr.* = level;
        } else {
            const ownedModule = try self.allocator.dupe(u8, module);
            try self.moduleLevels.put(ownedModule, level);
        }
    }

    /// Returns the level override for a module, or null when unset.
    pub fn getModuleLevel(self: *Logger, module: []const u8) ?Level {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        return self.moduleLevels.get(module);
    }

    /// Returns a logger that tags records with `module`.
    pub fn scoped(self: *Logger, module: []const u8) ScopedLogger {
        return ScopedLogger{ .logger = self, .module = module };
    }

    /// Returns a context builder bound to this logger.
    pub fn ctx(self: *Logger) ContextLogger {
        return ContextLogger.init(self);
    }

    /// Returns a logger carrying the given trace and span ids.
    pub fn withTrace(self: *Logger, traceId: []const u8, spanId: ?[]const u8) DistributedLogger {
        return DistributedLogger{
            .logger = self,
            .traceId = traceId,
            .spanId = spanId,
        };
    }

    /// Creates a distributed logger from an incoming W3C `traceparent` header.
    pub fn withTraceparent(self: *Logger, traceparent: []const u8) !DistributedLogger {
        const parsed = Utils.parseTraceparentHeader(traceparent) orelse return LoggerError.InvalidTraceparent;
        return self.withTrace(parsed.traceId, parsed.spanId);
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

    fn processLogTask(ctxPtr: *anyopaque, allocator: ?std.mem.Allocator) void {
        const taskCtx = @as(*LogTaskContext, @ptrCast(@alignCast(ctxPtr)));
        defer {
            taskCtx.record.deinit();
            taskCtx.logger.allocator.destroy(taskCtx);
        }
        const logger = taskCtx.logger;

        // Snapshot sinks to avoid holding lock during write
        logger.mutex.lockUncancelable(Utils.io());
        var sinksSnapshot: std.ArrayList(*Sink) = .empty;
        sinksSnapshot.appendSlice(logger.allocator, logger.sinks.items) catch {};
        logger.mutex.unlock(Utils.io());
        defer sinksSnapshot.deinit(logger.allocator);

        for (sinksSnapshot.items) |sink| {
            sink.writeWithAllocator(&taskCtx.record, logger.config, allocator) catch |writeErr| {
                if (logger.config.debugMode) {
                    std.debug.print("Async sink write error: {}\n", .{writeErr});
                }
            };
        }
    }

    /// Drop hook for queued log tasks discarded without executing
    /// (pool clear/cancel). Reclaims the cloned record and the context.
    /// Runs under the queue lock: frees memory only, never touches the pool.
    fn dropLogTask(ctxPtr: ?*anyopaque) void {
        const taskCtx = @as(*LogTaskContext, @ptrCast(@alignCast(ctxPtr.?)));
        taskCtx.record.deinit();
        taskCtx.logger.allocator.destroy(taskCtx);
    }
    fn log(self: *Logger, level: Level, message: []const u8, module: ?[]const u8, src: ?std.builtin.SourceLocation) !void {
        return self.logWithContext(level, message, module, src, null);
    }

    /// Logs at `level` with extra context merged into the record.
    pub fn logWithContext(self: *Logger, level: Level, message: []const u8, module: ?[]const u8, src: ?std.builtin.SourceLocation, extraContext: ?*std.StringHashMap(std.json.Value)) !void {
        return self.logInternal(level, message, module, src, extraContext, null);
    }

    /// Internal log function with extended capabilities.
    pub fn logInternal(self: *Logger, level: Level, message: []const u8, module: ?[]const u8, src: ?std.builtin.SourceLocation, extraContext: ?*std.StringHashMap(std.json.Value), traceCtx: ?TraceContext) !void {
        if (!self.enabled) return;

        // Resolve custom color before locking. The callback is pure user code
        // (Level, Color) -> Color with no shared state access; invoking it
        // outside the lock avoids deadlock if it ever calls back into Logly
        // (RwLock shared acquisition is not recursive when a writer waits).
        // Callbacks must not call Logger methods; see setColorCallback docs.
        const customColor: ?Color.Color = if (self.colorCallback) |cb|
            cb(level, level.defaultColor())
        else
            null;

        // Fast rejection before any expensive work. A call that will be
        // discarded must not pay for a clock reading, a lock, or formatting,
        // so the cheapest gate runs first: a single atomic load. The temporary
        // level override is the one case that needs the clock (to test expiry),
        // so the timestamp is only read when an override is actually present.
        if (module == null) {
            const atomicMin = self.atomicLevel.load(.monotonic);

            if (self.tempLevel == null) {
                if (@backingInt(level) < atomicMin) return;
            } else {
                const checkMs = Utils.currentMillis();
                var minVal = atomicMin;
                if (self.tempLevel) |lvl| {
                    if (checkMs < self.tempLevelExpiresAt) {
                        minVal = @backingInt(lvl);
                    } else {
                        self.tempLevel = null; // Expired
                    }
                }
                if (@backingInt(level) < minVal) return;
            }
        }

        // Capture the wall-clock timestamp once per record and reuse it for
        // the record itself and metrics, instead of generating separate
        // timestamps on the hot path.
        const nowMs = Utils.currentMillis();

        // Use shared lock for concurrent logging.
        self.mutex.lockSharedUncancelable(Utils.io());
        defer self.mutex.unlockShared(Utils.io());

        // Check level filtering
        var effectiveMinLevel = self.config.level;
        if (module) |m| {
            if (self.moduleLevels.get(m)) |l| {
                effectiveMinLevel = l;
            }
        }

        if (level.priority() < effectiveMinLevel.priority()) {
            return;
        }

        // Cheap pre-filter before any allocation: level/module/message rules
        // in ALL mode can reject here, skipping redaction and record setup.
        if (self.filter) |filter| {
            if (filter.preFilterRejects(level, module, message)) {
                return;
            }
        }

        // Apply sampling if configured (do early before record creation).
        // isEnabled() keeps disabled samplers at zero cost: no RNG, no clock,
        // no lock, no statistics traffic.
        if (self.sampler) |sampler| {
            if (sampler.isEnabled() and !sampler.shouldSampleLevel(level)) {
                return;
            }
        }

        // Apply redaction if configured with actual rules. Skipping the
        // redactor entirely when it has no rules avoids a message copy plus
        // a free on every record.
        var finalMessage = message;
        var redactedMessage: ?[]u8 = null;
        const scratch = self.scratchAllocator();
        if (self.redactor) |redactor| {
            if (redactor.hasRules()) {
                redactedMessage = try redactor.redactWithAllocator(message, scratch);
                finalMessage = redactedMessage orelse message;
            }
        }
        defer if (redactedMessage) |rm| scratch.free(rm);

        // Create record with enhanced fields
        var record = Record.init(self.scratchAllocator(), level, finalMessage);
        record.timestamp = nowMs;
        defer record.deinit();

        // Custom color resolved before locking (see above).
        if (customColor) |c| record.customLevelColor = c;

        if (module) |m| {
            record.module = m;
        }

        // Distributed Tracing Context
        if (self.config.enableTracing or self.config.distributed.enabled) {
            if (traceCtx) |tctx| {
                if (tctx.traceId) |tid| record.traceId = tid;
                if (tctx.spanId) |sid| record.spanId = sid;
                if (tctx.parentSpanId) |pid| record.parentSpanId = pid;
            } else {
                // Legacy/Global Trace Context
                record.traceId = self.traceId;
                record.spanId = self.spanId;
            }
        }

        // Capture stack trace for Error/Fatal levels if configured
        // We check if the config explicitly enables it, OR if it's an error/critical level
        // and the user hasn't explicitly disabled it (assuming default behavior was implicit).
        // However, to respect the new config strictly:
        if ((level == .err or level == .fail or level == .critical or level == .fatal) and self.config.captureStackTrace) {
            // Use the same allocator as the record so Record.deinit can release it safely.
            const allocator = self.scratchAllocator();
            // We use catch here to avoid failing the log if allocation fails
            if (allocator.create(std.builtin.StackTrace)) |st| {
                // Allocate a larger buffer to be safe
                if (allocator.alloc(usize, 64)) |addresses| {
                    const captured = std.debug.captureCurrentStackTrace(.{}, addresses);
                    st.* = .{
                        .instruction_addresses = addresses,
                        .index = captured.return_addresses.len,
                    };

                    record.stackTrace = st;
                    record.ownedStackTrace = st;
                } else |_| {
                    allocator.destroy(st);
                }
            } else |_| {}
        }

        // Add source location if available and configured
        if (src) |s| {
            if (self.config.showFilename) {
                record.filename = s.file;
            }
            if (self.config.showLineno) {
                record.line = s.line;
                record.column = s.column;
            }
            if (self.config.showFunction) {
                record.function = s.fn_name;
            }
        }

        // Copy context BEFORE filter evaluation so context/path rules
        // can match logger bindings (e.g. dot-notation user.id checks).
        // Fast path: skip if empty.
        if (self.context.count() > 0) {
            var it = self.context.iterator();
            while (it.next()) |entry| {
                try record.context.put(entry.key_ptr.*, entry.value_ptr.*);
            }
        }

        // Copy extra context - fast path: skip if null or empty
        if (extraContext) |ec| {
            if (ec.count() > 0) {
                var extraIt = ec.iterator();
                while (extraIt.next()) |entry| {
                    try record.context.put(entry.key_ptr.*, entry.value_ptr.*);
                }
            }
        }

        if (self.correlationId) |c| {
            record.correlationId = c;
        }

        // Apply filter if configured (needs record with context attached).
        // Denials report through onRecordFiltered with the filter's reason.
        // Like all user callbacks, it must be non-blocking and must not
        // call back into Logger methods (it runs under the logger lock).
        if (self.filter) |filter| {
            const decision = filter.shouldLogWithReason(&record);
            if (!decision.allowed) {
                if (self.onRecordFiltered) |cb| cb(decision.reason, &record);
                return;
            }
        }

        // Evaluate invoke triggers if configured
        if (self.config.rules.enabled and self.invoke != null) {
            if (self.invoke.?.evaluate(&record)) |messages| {
                record.invokeMessages = messages;
            }
        }

        // Update metrics (reuse the record timestamp, no extra clock read)
        if (self.metrics) |m| {
            m.recordLogAt(level, finalMessage.len, nowMs);
        }

        // Increment record count
        _ = self.recordCount.fetchAdd(1, .monotonic);

        // Call log callback
        if (self.config.enableCallbacks and self.logCallback != null) {
            try self.logCallback.?(&record);
        }

        // Dispatch the record
        try self.dispatchRecord(&record);

        // Report successful logging (same non-reentrancy contract as above).
        if (self.onRecordLogged) |cb| cb(level, finalMessage, &record);
    }

    /// Dispatches a record to the appropriate logging backend (async logger, thread pool, or direct sinks).
    /// This method handles the priority order: async_logger > thread_pool > direct sinks.
    pub fn dispatchRecord(self: *Logger, record: *const Record) !void {
        // Dispatch to async logger if available (highest priority)
        if (self.asyncLogger) |al| {
            // Format the record using the logger's formatter
            var formatter = Formatter.init(self.allocator);
            defer formatter.deinit();

            const formatted = try formatter.format(record, self.config);
            defer self.allocator.free(formatted);

            // Binary formats must not gain a line terminator downstream.
            if (self.config.format == .msgpack) {
                _ = al.queueBinary(formatted, record.level.priority());
            } else {
                // Queue the serialized bytes *uncolored* and carry the resolved
                // level color alongside. Each sink then applies presentation
                // per its own configuration at write time, so console color can
                // never leak into file or network sinks. Whole-record wrap is
                // the only presentation available here because vertical
                // highlighting needs field-level structure the queue no longer
                // has; the resolved color uses global overrides without sink
                // themes because async rendering is per logger, not per sink.
                const queuedColor = Formatter.resolveRecordColor(record, self.config, null);
                const queuedVertical = self.config.colorMode == .vertical;
                // Only these formats take presentation color applied around
                // the payload. text/logfmt color inline in the formatter and
                // msgpack must stay byte-exact.
                const queuedPresentable = switch (self.config.format) {
                    .json, .ndjson, .syslog, .syslog3164 => true,
                    else => false,
                };
                _ = al.queuePresented(formatted, record.level.priority(), queuedColor, queuedVertical, queuedPresentable);
            }

            // Signal async logger to flush if auto_flush is enabled
            if (self.config.autoFlush) {
                al.flush();
            }
            return;
        }

        // Dispatch to thread pool if available - this is where async parallelism happens
        if (self.threadPool) |tp| {
            // Clone record for async processing
            var clonedRec = try record.clone(self.allocator);
            errdefer clonedRec.deinit();

            const taskCtx = try self.allocator.create(LogTaskContext);
            taskCtx.* = .{
                .logger = self,
                .record = clonedRec,
            };

            if (tp.submitCallbackWithDrop(processLogTask, taskCtx, dropLogTask)) {
                // Task submitted to thread pool - no flush needed here.
                // The thread pool worker will write to sinks when the task executes.
                return;
            }

            // Fallback if submission fails (e.g. queue full)
            self.allocator.destroy(taskCtx);
            clonedRec.deinit();
        }

        // Write to all sinks (synchronous path when no thread pool or async logger)
        for (self.sinks.items) |sink| {
            sink.writeWithAllocator(record, self.config, null) catch |writeErr| {
                if (self.metrics) |m| {
                    m.recordError();
                }
                switch (self.config.errorHandling) {
                    .silent => {},
                    .logAndContinue => {
                        std.debug.print("Sink write error: {}\n", .{writeErr});
                    },
                    .failFast => return writeErr,
                    .callback => {
                        // Report through onSinkError with sink identity.
                        // Same non-reentrancy contract as other callbacks.
                        if (self.onSinkError) |cb| {
                            const sinkName: []const u8 = if (sink.getName()) |n|
                                n
                            else if (sink.config.path) |p|
                                p
                            else
                                "console";
                            cb(sinkName, @errorName(writeErr));
                        }
                    },
                }
            };
        }

        // Auto-flush on synchronous path only
        if (self.config.autoFlush) {
            self.flushInternal() catch {};
        }
    }

    /// Logs an error with associated error information.
    pub fn logError(self: *Logger, message: []const u8, errVal: anyerror) !void {
        if (!self.enabled) return;

        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());

        // Redact before anything else: error paths must not leak sensitive
        // data that the main path would mask. Failure drops the record
        // (fail-closed via try), never forwards unredacted text.
        var finalMessage = message;
        var redactedMessage: ?[]u8 = null;
        if (self.redactor) |redactor| {
            if (redactor.hasRules()) {
                redactedMessage = try redactor.redact(message);
                finalMessage = redactedMessage orelse message;
            }
        }
        defer if (redactedMessage) |rm| self.allocator.free(rm);

        var record = Record.init(self.allocator, .err, finalMessage);
        defer record.deinit();

        record.errorInfo = .{
            .name = @errorName(errVal),
            .message = finalMessage,
            .stackTrace = null,
            .code = null,
        };

        if (self.traceId) |t| record.traceId = t;
        if (self.spanId) |s| record.spanId = s;

        if (self.metrics) |m| {
            m.recordLog(.err, finalMessage.len);
            m.recordError();
        }

        // Dispatch the record
        try self.dispatchRecord(&record);
    }

    /// Logs a timed operation. Returns the duration in nanoseconds.
    pub fn logTimed(self: *Logger, level: Level, message: []const u8, startTime: i128, src: ?std.builtin.SourceLocation) !i128 {
        const endTime = Utils.currentNanos();
        const duration = endTime - startTime;

        if (!self.enabled) return duration;

        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());

        // Same fail-closed redaction as the main path (see logError).
        var finalMessage = message;
        var redactedMessage: ?[]u8 = null;
        if (self.redactor) |redactor| {
            if (redactor.hasRules()) {
                redactedMessage = try redactor.redact(message);
                finalMessage = redactedMessage orelse message;
            }
        }
        defer if (redactedMessage) |rm| self.allocator.free(rm);

        var record = Record.init(self.allocator, level, finalMessage);
        defer record.deinit();

        record.durationNs = @intCast(@max(0, duration));

        if (src) |s| {
            if (self.config.showFilename) {
                record.filename = s.file;
            }
            if (self.config.showLineno) {
                record.line = s.line;
                record.column = s.column;
            }
            if (self.config.showFunction) {
                record.function = s.fn_name;
            }
        }

        if (self.traceId) |t| record.traceId = t;
        if (self.spanId) |s| record.spanId = s;

        if (self.metrics) |m| {
            m.recordLog(level, finalMessage.len);
        }

        // Evaluate invoke triggers if configured
        if (self.config.rules.enabled and self.invoke != null) {
            if (self.invoke.?.evaluate(&record)) |messages| {
                record.invokeMessages = messages;
            }
        }

        // Dispatch the record
        try self.dispatchRecord(&record);

        return duration;
    }

    /// Returns the total number of records logged.
    pub fn getRecordCount(self: *Logger) u64 {
        return @as(u64, self.recordCount.load(.monotonic));
    }

    /// Returns the currently active minimum log level.
    pub fn getLevel(self: *Logger) Level {
        const now = Utils.currentMillis();
        if (self.tempLevel) |lvl| {
            if (now < self.tempLevelExpiresAt) {
                return lvl;
            } else {
                self.tempLevel = null;
            }
        }
        return @fromBackingInt(@intCast(self.atomicLevel.load(.monotonic)));
    }

    /// Temporarily overrides the minimum log level for a specified duration in milliseconds.
    pub fn setTemporaryLevel(self: *Logger, tempLevel: Level, durationMs: u64) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        self.tempLevel = tempLevel;
        self.tempLevelExpiresAt = Utils.currentMillis() + @as(i64, @intCast(durationMs));
    }

    /// Clears any active temporary level override.
    pub fn clearTemporaryLevel(self: *Logger) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        self.tempLevel = null;
        self.tempLevelExpiresAt = 0;
    }

    /// Returns uptime in seconds since logger initialization.
    pub fn getUptime(self: *Logger) i64 {
        return Utils.currentSeconds() - self.initTimestamp;
    }

    /// Logs a trace message.
    pub fn trace(self: *Logger, message: []const u8, src: ?std.builtin.SourceLocation) !void {
        try self.log(.trace, message, null, src);
    }

    /// Logs a debug message.
    pub fn debug(self: *Logger, message: []const u8, src: ?std.builtin.SourceLocation) !void {
        try self.log(.debug, message, null, src);
    }

    /// Logs an informational message.
    pub fn info(self: *Logger, message: []const u8, src: ?std.builtin.SourceLocation) !void {
        try self.log(.info, message, null, src);
    }

    /// Logs a notice message.
    pub fn notice(self: *Logger, message: []const u8, src: ?std.builtin.SourceLocation) !void {
        try self.log(.notice, message, null, src);
    }

    /// Logs a success message.
    pub fn success(self: *Logger, message: []const u8, src: ?std.builtin.SourceLocation) !void {
        try self.log(.success, message, null, src);
    }

    /// Logs a warning message.
    /// Also available as: `logger.warn("message", @src())`
    pub fn warning(self: *Logger, message: []const u8, src: ?std.builtin.SourceLocation) !void {
        try self.log(.warning, message, null, src);
    }

    /// Short form of `warning`.
    pub const warn = warning;

    /// Logs an error message.
    /// Note: This method is named `@"error"` to use 'error' as identifier.
    /// Call it as: `logger.@"error"("message", @src())`
    /// Or use the alias: `logger.err("message", @src())`
    pub const @"error" = err;

    /// Logs an error message. Alias of `@"error"`.
    pub fn err(self: *Logger, message: []const u8, src: ?std.builtin.SourceLocation) !void {
        try self.log(.err, message, null, src);
    }

    /// Logs a failure message.
    pub fn fail(self: *Logger, message: []const u8, src: ?std.builtin.SourceLocation) !void {
        try self.log(.fail, message, null, src);
    }

    /// Logs a critical message.
    /// Also available as: `logger.crit("message", @src())`
    pub fn critical(self: *Logger, message: []const u8, src: ?std.builtin.SourceLocation) !void {
        try self.log(.critical, message, null, src);
    }

    /// Short form of `critical`.
    pub const crit = critical;

    /// Logs a fatal message and flushes before returning.
    pub fn fatal(self: *Logger, message: []const u8, src: ?std.builtin.SourceLocation) !void {
        try self.log(.fatal, message, null, src);
    }

    /// Logs a panic message directly and synchronously to all sinks, then flushes them.
    /// Bypasses the asynchronous thread pool entirely to ensure the crash details are
    /// written to disk before the process aborts.
    pub fn logPanic(self: *Logger, message: []const u8) !void {
        // Bypass the logger lock to prevent deadlock if the crashing thread
        // already holds it. Sink locks are still acquired per write: if the
        // same thread crashed while holding a sink lock, this blocks instead
        // of recursing. Every step is best-effort (catch {}) by design.
        var record = Record.init(self.scratchAllocator(), .fatal, message);
        defer record.deinit();

        if (self.traceId) |t| record.traceId = t;
        if (self.spanId) |s| record.spanId = s;

        // Copy context
        var it = self.context.iterator();
        while (it.next()) |entry| {
            record.context.put(entry.key_ptr.*, entry.value_ptr.*) catch {};
        }

        for (self.sinks.items) |sink| {
            sink.writeWithAllocator(&record, self.config, null) catch {};
            sink.flush() catch {};
        }
    }

    /// Logs using a registered custom level. Returns error.UnknownCustomLevel when the name is not registered.
    pub fn custom(self: *Logger, levelName: []const u8, message: []const u8, src: ?std.builtin.SourceLocation) !void {
        const levelInfo = self.customLevels.get(levelName) orelse return error.InvalidLevel;
        const mappedLevel = Level.fromPriority(levelInfo.priority) orelse .info;
        try self.logCustomLevel(mappedLevel, levelInfo.name, levelInfo.color, message, null, src);
    }

    /// Internal method to log with custom level name and color
    fn logCustomLevel(
        self: *Logger,
        level: Level,
        customName: []const u8,
        customColor: Color.Color,
        message: []const u8,
        module: ?[]const u8,
        src: ?std.builtin.SourceLocation,
    ) !void {
        if (!self.enabled) return;

        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());

        // Check level filtering
        var effectiveMinLevel = self.config.level;
        if (module) |m| {
            if (self.moduleLevels.get(m)) |l| {
                effectiveMinLevel = l;
            }
        }

        if (level.priority() < effectiveMinLevel.priority()) {
            return;
        }

        // Cheap pre-filter before any allocation (see logInternal).
        if (self.filter) |filter| {
            if (filter.preFilterRejects(level, module, message)) {
                return;
            }
        }

        // Apply sampling (skipped entirely when the sampler is disabled).
        if (self.sampler) |sampler| {
            if (sampler.isEnabled() and !sampler.shouldSampleLevel(level)) {
                return;
            }
        }

        // Apply redaction only when rules exist.
        var finalMessage = message;
        var redactedMessage: ?[]u8 = null;
        if (self.redactor) |redactor| {
            if (redactor.hasRules()) {
                redactedMessage = try redactor.redact(message);
                finalMessage = redactedMessage orelse message;
            }
        }
        defer if (redactedMessage) |rm| self.allocator.free(rm);

        // Create record with custom level info
        var record = Record.initCustom(self.scratchAllocator(), level, customName, customColor, finalMessage);
        defer record.deinit();

        if (module) |m| {
            record.module = m;
        }

        // Add source location if available and configured
        if (src) |s| {
            if (self.config.showFilename) {
                record.filename = s.file;
            }
            if (self.config.showLineno) {
                record.line = s.line;
                record.column = s.column;
            }
            if (self.config.showFunction) {
                record.function = s.fn_name;
            }
        }

        // Add trace context BEFORE filter so trace/span rules can match.
        if (self.traceId) |t| {
            record.traceId = t;
        }
        if (self.spanId) |s| {
            record.spanId = s;
        }
        if (self.correlationId) |c| {
            record.correlationId = c;
        }

        // Copy context BEFORE filter evaluation (see logInternal).
        var it = self.context.iterator();
        while (it.next()) |entry| {
            try record.context.put(entry.key_ptr.*, entry.value_ptr.*);
        }

        // Apply filter if configured (reports denials like logInternal).
        if (self.filter) |filter| {
            const decision = filter.shouldLogWithReason(&record);
            if (!decision.allowed) {
                if (self.onRecordFiltered) |cb| cb(decision.reason, &record);
                return;
            }
        }

        // Evaluate invoke triggers if configured
        if (self.config.rules.enabled and self.invoke != null) {
            if (self.invoke.?.evaluate(&record)) |messages| {
                record.invokeMessages = messages;
            }
        }

        // Update metrics
        if (self.metrics) |m| {
            m.recordLog(level, finalMessage.len);
        }

        // Increment record count
        _ = self.recordCount.fetchAdd(1, .monotonic);

        // Call log callback
        if (self.config.enableCallbacks and self.logCallback != null) {
            try self.logCallback.?(&record);
        }

        // Dispatch to thread pool if available
        if (self.threadPool) |tp| {
            // Clone record for async processing
            var clonedRec = try record.clone(self.allocator);
            errdefer clonedRec.deinit();

            const taskCtx = try self.allocator.create(LogTaskContext);
            taskCtx.* = .{
                .logger = self,
                .record = clonedRec,
            };

            if (tp.submitCallbackWithDrop(processLogTask, taskCtx, dropLogTask)) {
                return;
            }

            // Fallback if submission fails
            self.allocator.destroy(taskCtx);
            clonedRec.deinit();
        }

        // Write to all sinks
        for (self.sinks.items) |sink| {
            sink.writeWithAllocator(&record, self.config, null) catch |writeErr| {
                if (self.metrics) |m| {
                    m.recordError();
                }
                switch (self.config.errorHandling) {
                    .silent => {},
                    .logAndContinue => {
                        std.debug.print("Sink write error: {}\n", .{writeErr});
                    },
                    .failFast => return writeErr,
                    .callback => {
                        if (self.onSinkError) |cb| {
                            const sinkName: []const u8 = if (sink.getName()) |n|
                                n
                            else if (sink.config.path) |p|
                                p
                            else
                                "console";
                            cb(sinkName, @errorName(writeErr));
                        }
                    },
                }
            };
        }

        // Auto-flush if enabled
        if (self.config.autoFlush) {
            self.flushInternal() catch {};
        }

        if (self.onRecordLogged) |cb| cb(level, finalMessage, &record);
    }

    // Formatted logging methods
    /// Printf-style form of `trace`.
    pub fn tracef(self: *Logger, comptime fmt: []const u8, args: anytype, src: ?std.builtin.SourceLocation) !void {
        const message = try std.fmt.allocPrint(self.allocator, fmt, args);
        defer self.allocator.free(message);
        try self.log(.trace, message, null, src);
    }

    /// Printf-style form of `debug`.
    pub fn debugf(self: *Logger, comptime fmt: []const u8, args: anytype, src: ?std.builtin.SourceLocation) !void {
        const message = try std.fmt.allocPrint(self.allocator, fmt, args);
        defer self.allocator.free(message);
        try self.log(.debug, message, null, src);
    }

    /// Printf-style form of `info`.
    pub fn infof(self: *Logger, comptime fmt: []const u8, args: anytype, src: ?std.builtin.SourceLocation) !void {
        const message = try std.fmt.allocPrint(self.allocator, fmt, args);
        defer self.allocator.free(message);
        try self.log(.info, message, null, src);
    }

    /// Printf-style form of `notice`.
    pub fn noticef(self: *Logger, comptime fmt: []const u8, args: anytype, src: ?std.builtin.SourceLocation) !void {
        const message = try std.fmt.allocPrint(self.allocator, fmt, args);
        defer self.allocator.free(message);
        try self.log(.notice, message, null, src);
    }

    /// Printf-style form of `success`.
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

    /// Short form of `warningf`.
    pub const warnf = warningf;

    /// Logs a formatted error message.
    /// Note: This method is named `@"errorf"` to provide 'errorf' function.
    /// Call it as: `logger.errorf("format {d}", .{val}, @src())`
    /// Or use the alias: `logger.errf("format {d}", .{val}, @src())`
    pub fn errf(self: *Logger, comptime fmt: []const u8, args: anytype, src: ?std.builtin.SourceLocation) !void {
        const message = try std.fmt.allocPrint(self.allocator, fmt, args);
        defer self.allocator.free(message);
        try self.log(.err, message, null, src);
    }

    /// Printf-style form of `fail`.
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

    /// Short form of `criticalf`.
    pub const critf = criticalf;

    /// Printf-style form of `fatal`.
    pub fn fatalf(self: *Logger, comptime fmt: []const u8, args: anytype, src: ?std.builtin.SourceLocation) !void {
        const message = try std.fmt.allocPrint(self.allocator, fmt, args);
        defer self.allocator.free(message);
        try self.log(.fatal, message, null, src);
    }

    /// Logs a message with a custom level name and format arguments.
    ///
    /// This allows for dynamic custom logging levels defined at runtime.
    pub fn customf(self: *Logger, levelName: []const u8, comptime fmt: []const u8, args: anytype, src: ?std.builtin.SourceLocation) !void {
        const levelInfo = self.customLevels.get(levelName) orelse return error.InvalidLevel;
        const message = try std.fmt.allocPrint(self.allocator, fmt, args);
        defer self.allocator.free(message);
        const mappedLevel = Level.fromPriority(levelInfo.priority) orelse .info;
        try self.logCustomLevel(mappedLevel, levelInfo.name, levelInfo.color, message, null, src);
    }
};

/// Context for span-based tracing operations.
///
/// Used for distributed tracing with nested spans. Automatically restores
/// the parent span when the current span is ended.
pub const SpanContext = struct {
    /// The logger instance this span belongs to.
    logger: *Logger,
    /// The parent span ID to restore when this span ends.
    parentSpanId: ?[]const u8,
    /// Start timestamp in nanoseconds for duration calculation.
    startTime: i128,

    /// Ends the span and logs the duration.
    pub fn end(self: *SpanContext, message: ?[]const u8, src: ?std.builtin.SourceLocation) !void {
        const duration = Utils.currentNanos() - self.startTime;

        if (message) |msg| {
            _ = try self.logger.logTimed(.debug, msg, self.startTime, src);
        }

        self.logger.mutex.lockUncancelable(Utils.io());
        defer self.logger.mutex.unlock(Utils.io());

        if (self.logger.spanId) |current| {
            self.logger.allocator.free(current);
        }
        self.logger.spanId = self.parentSpanId;

        _ = duration;
    }

    /// Ends the span without logging.
    pub fn endSilent(self: *SpanContext) void {
        self.logger.mutex.lockUncancelable(Utils.io());
        defer self.logger.mutex.unlock(Utils.io());

        if (self.logger.spanId) |current| {
            self.logger.allocator.free(current);
        }
        self.logger.spanId = self.parentSpanId;
    }
};

/// Logger view that stamps every record with a module name.
pub const ScopedLogger = struct {
    logger: *Logger,
    module: []const u8,

    /// Logs a trace message with module scope.
    pub fn trace(self: ScopedLogger, message: []const u8, src: ?std.builtin.SourceLocation) !void {
        try self.logger.log(.trace, message, self.module, src);
    }

    /// Logs a debug message with module scope.
    pub fn debug(self: ScopedLogger, message: []const u8, src: ?std.builtin.SourceLocation) !void {
        try self.logger.log(.debug, message, self.module, src);
    }

    /// Logs an info message with module scope.
    pub fn info(self: ScopedLogger, message: []const u8, src: ?std.builtin.SourceLocation) !void {
        try self.logger.log(.info, message, self.module, src);
    }

    /// Logs a notice message with module scope.
    pub fn notice(self: ScopedLogger, message: []const u8, src: ?std.builtin.SourceLocation) !void {
        try self.logger.log(.notice, message, self.module, src);
    }

    /// Logs a success message with module scope.
    pub fn success(self: ScopedLogger, message: []const u8, src: ?std.builtin.SourceLocation) !void {
        try self.logger.log(.success, message, self.module, src);
    }

    /// Logs a warning message with module scope.
    /// Also available as: `scoped.warn("message", @src())`
    pub fn warning(self: ScopedLogger, message: []const u8, src: ?std.builtin.SourceLocation) !void {
        try self.logger.log(.warning, message, self.module, src);
    }

    /// Short form of `warning`.
    pub const warn = warning;

    /// Logs an error message with module scope.
    /// Use `@"error"` or `err` to call this method.
    pub const @"error" = err;

    /// Logs an error message with module scope.
    pub fn err(self: ScopedLogger, message: []const u8, src: ?std.builtin.SourceLocation) !void {
        try self.logger.log(.err, message, self.module, src);
    }

    /// Logs a failure message with module scope.
    pub fn fail(self: ScopedLogger, message: []const u8, src: ?std.builtin.SourceLocation) !void {
        try self.logger.log(.fail, message, self.module, src);
    }

    /// Logs a critical message with module scope.
    /// Also available as: `scoped.crit("message", @src())`
    pub fn critical(self: ScopedLogger, message: []const u8, src: ?std.builtin.SourceLocation) !void {
        try self.logger.log(.critical, message, self.module, src);
    }

    /// Short form of `critical`.
    pub const crit = critical;

    /// Logs a fatal message with module scope.
    pub fn fatal(self: ScopedLogger, message: []const u8, src: ?std.builtin.SourceLocation) !void {
        try self.logger.log(.fatal, message, self.module, src);
    }

    /// Logs a formatted trace message with module scope.
    pub fn tracef(self: ScopedLogger, comptime fmt: []const u8, args: anytype, src: ?std.builtin.SourceLocation) !void {
        const message = try std.fmt.allocPrint(self.logger.allocator, fmt, args);
        defer self.logger.allocator.free(message);
        try self.logger.log(.trace, message, self.module, src);
    }

    /// Logs a formatted debug message with module scope.
    pub fn debugf(self: ScopedLogger, comptime fmt: []const u8, args: anytype, src: ?std.builtin.SourceLocation) !void {
        const message = try std.fmt.allocPrint(self.logger.allocator, fmt, args);
        defer self.logger.allocator.free(message);
        try self.logger.log(.debug, message, self.module, src);
    }

    /// Logs a formatted info message with module scope.
    pub fn infof(self: ScopedLogger, comptime fmt: []const u8, args: anytype, src: ?std.builtin.SourceLocation) !void {
        const message = try std.fmt.allocPrint(self.logger.allocator, fmt, args);
        defer self.logger.allocator.free(message);
        try self.logger.log(.info, message, self.module, src);
    }

    /// Logs a formatted notice message with module scope.
    pub fn noticef(self: ScopedLogger, comptime fmt: []const u8, args: anytype, src: ?std.builtin.SourceLocation) !void {
        const message = try std.fmt.allocPrint(self.logger.allocator, fmt, args);
        defer self.logger.allocator.free(message);
        try self.logger.log(.notice, message, self.module, src);
    }

    /// Logs a formatted success message with module scope.
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

    /// Short form of `warningf`.
    pub const warnf = warningf;

    /// Logs a formatted error message with module scope.
    /// Use `errorf` or `errf` to call this method.
    /// Logs a formatted error message with module scope.
    pub fn errf(self: ScopedLogger, comptime fmt: []const u8, args: anytype, src: ?std.builtin.SourceLocation) !void {
        const message = try std.fmt.allocPrint(self.logger.allocator, fmt, args);
        defer self.logger.allocator.free(message);
        try self.logger.log(.err, message, self.module, src);
    }

    /// Logs a formatted failure message with module scope.
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

    /// Short form of `criticalf`.
    pub const critf = criticalf;

    /// Logs a formatted fatal message with module scope.
    pub fn fatalf(self: ScopedLogger, comptime fmt: []const u8, args: anytype, src: ?std.builtin.SourceLocation) !void {
        const message = try std.fmt.allocPrint(self.logger.allocator, fmt, args);
        defer self.logger.allocator.free(message);
        try self.logger.log(.fatal, message, self.module, src);
    }
};

/// Builder for attaching context fields to records.
pub const ContextLogger = struct {
    logger: *Logger,
    context: std.StringHashMap(std.json.Value),

    /// Initializes a new ContextLogger.
    pub fn init(logger: *Logger) ContextLogger {
        return .{
            .logger = logger,
            .context = std.StringHashMap(std.json.Value).init(logger.allocator),
        };
    }

    /// Deinitializes the ContextLogger.
    pub fn deinit(self: *ContextLogger) void {
        self.context.deinit();
    }

    /// Adds a string value to the context.
    pub fn str(self: *ContextLogger, key: []const u8, value: []const u8) *ContextLogger {
        self.context.put(key, .{ .string = value }) catch {};
        return self;
    }

    /// Adds an integer value to the context.
    pub fn int(self: *ContextLogger, key: []const u8, value: i64) *ContextLogger {
        self.context.put(key, .{ .integer = value }) catch {};
        return self;
    }

    /// Adds a float value to the context.
    pub fn float(self: *ContextLogger, key: []const u8, value: f64) *ContextLogger {
        self.context.put(key, .{ .float = value }) catch {};
        return self;
    }

    /// Adds a boolean value to the context.
    pub fn boolean(self: *ContextLogger, key: []const u8, value: bool) *ContextLogger {
        self.context.put(key, .{ .boolean = value }) catch {};
        return self;
    }

    /// Logs the context message at the specified level.
    pub fn log(self: *ContextLogger, level: Level, message: []const u8, src: ?std.builtin.SourceLocation) !void {
        defer self.deinit();
        try self.logger.logWithContext(level, message, null, src, &self.context);
    }

    /// Logs a trace message with context.
    pub fn trace(self: *ContextLogger, message: []const u8, src: ?std.builtin.SourceLocation) !void {
        try self.log(.trace, message, src);
    }

    /// Logs a debug message with context.
    pub fn debug(self: *ContextLogger, message: []const u8, src: ?std.builtin.SourceLocation) !void {
        try self.log(.debug, message, src);
    }

    /// Logs an info message with context.
    pub fn info(self: *ContextLogger, message: []const u8, src: ?std.builtin.SourceLocation) !void {
        try self.log(.info, message, src);
    }

    /// Logs a warning message with context.
    pub fn warning(self: *ContextLogger, message: []const u8, src: ?std.builtin.SourceLocation) !void {
        try self.log(.warning, message, src);
    }

    /// Alias for warning (short form).
    pub const warn = warning;

    /// Logs an error message with context.
    pub fn err(self: *ContextLogger, message: []const u8, src: ?std.builtin.SourceLocation) !void {
        try self.log(.err, message, src);
    }

    /// Logs a critical message with context.
    pub fn critical(self: *ContextLogger, message: []const u8, src: ?std.builtin.SourceLocation) !void {
        try self.log(.critical, message, src);
    }

    /// Short form of `critical`.
    pub const crit = critical;
};

/// A logger that maintains a persistent context across multiple log calls.
/// Unlike ContextLogger, this struct must be manually deinited.
pub const PersistentContextLogger = struct {
    logger: *Logger,
    context: std.StringHashMap(std.json.Value),

    /// Initializes a new PersistentContextLogger.
    pub fn init(logger: *Logger) PersistentContextLogger {
        return .{
            .logger = logger,
            .context = std.StringHashMap(std.json.Value).init(logger.allocator),
        };
    }

    /// Deinitializes the PersistentContextLogger.
    pub fn deinit(self: *PersistentContextLogger) void {
        self.context.deinit();
    }

    /// Adds a string value to the persistent context.
    pub fn str(self: *PersistentContextLogger, key: []const u8, value: []const u8) *PersistentContextLogger {
        self.context.put(key, .{ .string = value }) catch {};
        return self;
    }

    /// Adds an integer value to the persistent context.
    pub fn int(self: *PersistentContextLogger, key: []const u8, value: i64) *PersistentContextLogger {
        self.context.put(key, .{ .integer = value }) catch {};
        return self;
    }

    /// Adds a float value to the persistent context.
    pub fn float(self: *PersistentContextLogger, key: []const u8, value: f64) *PersistentContextLogger {
        self.context.put(key, .{ .float = value }) catch {};
        return self;
    }

    /// Adds a boolean value to the persistent context.
    pub fn boolean(self: *PersistentContextLogger, key: []const u8, value: bool) *PersistentContextLogger {
        self.context.put(key, .{ .boolean = value }) catch {};
        return self;
    }

    /// Logs a message at the specified level with persistent context.
    pub fn log(self: *PersistentContextLogger, level: Level, message: []const u8, src: ?std.builtin.SourceLocation) !void {
        try self.logger.logWithContext(level, message, null, src, &self.context);
    }

    /// Logs a trace message with persistent context.
    pub fn trace(self: *PersistentContextLogger, message: []const u8, src: ?std.builtin.SourceLocation) !void {
        try self.log(.trace, message, src);
    }

    /// Logs a debug message with persistent context.
    pub fn debug(self: *PersistentContextLogger, message: []const u8, src: ?std.builtin.SourceLocation) !void {
        try self.log(.debug, message, src);
    }

    /// Logs an info message with persistent context.
    pub fn info(self: *PersistentContextLogger, message: []const u8, src: ?std.builtin.SourceLocation) !void {
        try self.log(.info, message, src);
    }

    /// Logs a warning message with persistent context.
    pub fn warning(self: *PersistentContextLogger, message: []const u8, src: ?std.builtin.SourceLocation) !void {
        try self.log(.warning, message, src);
    }

    /// Alias for warning (short form).
    pub const warn = warning;

    /// Logs an error message with persistent context.
    pub fn err(self: *PersistentContextLogger, message: []const u8, src: ?std.builtin.SourceLocation) !void {
        try self.log(.err, message, src);
    }

    /// Logs a critical message with persistent context.
    pub fn critical(self: *PersistentContextLogger, message: []const u8, src: ?std.builtin.SourceLocation) !void {
        try self.log(.critical, message, src);
    }

    /// Short form of `critical`.
    pub const crit = critical;
};

/// Logger handle for distributed systems that maintains trace context.
pub const DistributedLogger = struct {
    logger: *Logger,
    traceId: ?[]const u8,
    spanId: ?[]const u8,
    parentSpanId: ?[]const u8 = null,
    module: ?[]const u8 = null,

    /// Logs a message at the specified level with distributed trace context.
    pub fn log(self: *const DistributedLogger, level: Level, message: []const u8, src: ?std.builtin.SourceLocation) !void {
        try self.logger.logInternal(level, message, self.module, src, null, .{
            .traceId = self.traceId,
            .spanId = self.spanId,
            .parentSpanId = self.parentSpanId,
        });
    }

    /// Logs a trace message with distributed trace context.
    pub fn trace(self: *const DistributedLogger, message: []const u8, src: ?std.builtin.SourceLocation) !void {
        try self.log(.trace, message, src);
    }

    /// Logs a debug message with distributed trace context.
    pub fn debug(self: *const DistributedLogger, message: []const u8, src: ?std.builtin.SourceLocation) !void {
        try self.log(.debug, message, src);
    }

    /// Logs an info message with distributed trace context.
    pub fn info(self: *const DistributedLogger, message: []const u8, src: ?std.builtin.SourceLocation) !void {
        try self.log(.info, message, src);
    }

    /// Logs a warning message with distributed trace context.
    pub fn warning(self: *const DistributedLogger, message: []const u8, src: ?std.builtin.SourceLocation) !void {
        try self.log(.warning, message, src);
    }

    /// Short form of `warning`.
    pub const warn = warning;

    /// Logs an error message with distributed trace context.
    pub fn err(self: *const DistributedLogger, message: []const u8, src: ?std.builtin.SourceLocation) !void {
        try self.log(.err, message, src);
    }

    /// Logs a critical message with distributed trace context.
    pub fn critical(self: *const DistributedLogger, message: []const u8, src: ?std.builtin.SourceLocation) !void {
        try self.log(.critical, message, src);
    }

    /// Short form of `critical`.
    pub const crit = critical;

    /// Returns a child distributed logger context with parent span linkage.
    pub fn child(self: *const DistributedLogger, childSpanId: []const u8) DistributedLogger {
        return .{
            .logger = self.logger,
            .traceId = self.traceId,
            .spanId = childSpanId,
            .parentSpanId = self.spanId,
            .module = self.module,
        };
    }

    /// Returns a distributed logger bound to a specific module.
    pub fn inModule(self: *const DistributedLogger, module: []const u8) DistributedLogger {
        return .{
            .logger = self.logger,
            .traceId = self.traceId,
            .spanId = self.spanId,
            .parentSpanId = self.parentSpanId,
            .module = module,
        };
    }
};

test "logger basic" {
    // Create logger with auto_sink disabled for testing
    var config = Config.default();
    config.autoSink = false;

    const logger = try Logger.initWithConfig(std.testing.allocator, config);
    defer logger.deinit();

    // Note: providing config to initWithConfig prevents auto_sink creation if disabled
    try std.testing.expect(logger.sinks.items.len == 0);
}

test "logger with auto sink" {
    // Default config has auto_sink = true
    const config = Config.default();
    const logger = try Logger.initWithConfig(std.testing.allocator, config);
    defer logger.deinit();

    // Should have 1 auto-created console sink
    try std.testing.expect(logger.sinks.items.len == 1);
}

test "distributed logger context" {
    // Verify that DistributedLogger correctly propagates context
    var config = Config.default();
    config.autoSink = false; // Disable auto-sink to test logic only

    // Setup a memory sink to inspect records
    const logger = try Logger.initWithConfig(std.testing.allocator, config);
    defer logger.deinit();

    const traceId = "test-trace-id";
    const spanId = "test-span-id";

    const distLogger = logger.withTrace(traceId, spanId);

    // We are testing logical correctness of the struct init
    // A full e2e test would require mocking a sink which is complex in this unit test block
    // But we can verify the struct fields
    try std.testing.expectEqualStrings(traceId, distLogger.traceId.?);
    try std.testing.expectEqualStrings(spanId, distLogger.spanId.?);
}

test "global trace context" {
    var config = Config.default();
    config.autoSink = false;

    const logger = try Logger.initWithConfig(std.testing.allocator, config);
    defer logger.deinit();

    try logger.setTraceContext("global-trace", "global-span");

    // We can't easily inspect private state 'trace_id' but we can verify no crash
    // and subsequent logging doesn't fail
    try logger.info("Test message", null);

    logger.clearTraceContext();
}

test "logger traceparent context helpers" {
    var config = Config.default();
    config.autoSink = false;

    const logger = try Logger.initWithConfig(std.testing.allocator, config);
    defer logger.deinit();

    try logger.setTraceContextFromTraceparent("00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01");

    const traceparent = try logger.getTraceparentHeader(std.testing.allocator);
    defer if (traceparent) |tp| std.testing.allocator.free(tp);

    try std.testing.expect(traceparent != null);
    try std.testing.expect(std.mem.indexOf(u8, traceparent.?, "4bf92f3577b34da6a3ce929d0e0e4736") != null);
    try std.testing.expect(std.mem.indexOf(u8, traceparent.?, "00f067aa0ba902b7") != null);

    try std.testing.expectError(Logger.LoggerError.InvalidTraceparent, logger.setTraceContextFromTraceparent("invalid-traceparent"));
}

test "distributed logger child and module helpers" {
    var config = Config.default();
    config.autoSink = false;

    const logger = try Logger.initWithConfig(std.testing.allocator, config);
    defer logger.deinit();

    const root = logger.withTrace("trace-123", "span-root");
    const child = root.child("span-child").inModule("service.auth");

    try std.testing.expectEqualStrings("trace-123", child.traceId.?);
    try std.testing.expectEqualStrings("span-child", child.spanId.?);
    try std.testing.expectEqualStrings("span-root", child.parentSpanId.?);
    try std.testing.expectEqualStrings("service.auth", child.module.?);
}

test "logger supports GeneralPurposeAllocator" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();

    var config = Config.default();
    config.autoSink = false;

    const logger = try Logger.initWithConfig(gpa.allocator(), config);
    defer logger.deinit();

    try logger.info("gpa-backed logger", null);
}

fn testColorCallback(level: Level, color: Color.Color) Color.Color {
    _ = level;
    _ = color;
    return Color.Tint.color.ansi4.magenta;
}

test "logger custom level color end to end" {
    const allocator = std.testing.allocator;
    var logger = try Logger.init(allocator);
    defer logger.deinit();

    try logger.addCustomLevel("AUDIT", 35, Color.Tint.color.cyan);
    try std.testing.expect(logger.hasCustomLevel("AUDIT"));

    const info = logger.customLevels.get("AUDIT").?;
    try std.testing.expectEqual(Color.Tint.color.cyan, info.color);

    try logger.updateCustomLevel("AUDIT", 35, Color.Tint.color.ansi4.brightCyan);
    try std.testing.expectEqual(Color.Tint.color.ansi4.brightCyan, logger.customLevels.get("AUDIT").?.color);
}

test "logger async json presentation wraps at queue time" {
    const allocator = std.testing.allocator;
    const path = "test_async_present.json";
    std.Io.Dir.cwd().deleteFile(Utils.io(), path) catch {};
    defer std.Io.Dir.cwd().deleteFile(Utils.io(), path) catch {};

    var config = Config.default();
    config.format = .json;
    // Console output is never wanted in a test: under `zig build` the runner
    // speaks its progress protocol over stdout, so anything a test prints
    // corrupts that stream and stalls the build. Assertions here read the file.
    config.globalConsoleDisplay = false;
    config.asyncConfig.enabled = true;
    config.asyncConfig.backgroundWorker = false;
    const logger = try Logger.initWithConfig(allocator, config);
    defer logger.deinit();

    var scfg = SinkConfig.file(path);
    scfg.asyncWrite = false;
    // File sinks never inherit console color resolution, so the presentation
    // wrap has to be requested explicitly. That is the contract under test:
    // async rendering colors the serialized JSON *around* the payload, leaving
    // the JSON itself intact.
    scfg.color = true;
    _ = try logger.addSink(scfg);

    try logger.warning("async hello", null);
    try logger.flush();

    var file = try std.Io.Dir.cwd().openFile(Utils.io(), path, .{});
    defer file.close(Utils.io());
    const stat = try file.stat(Utils.io());
    const bytes = try allocator.alloc(u8, stat.size);
    defer allocator.free(bytes);
    var readBuf: [4096]u8 = undefined;
    var reader = file.reader(Utils.io(), &readBuf);
    var total: usize = 0;
    while (total < bytes.len) {
        const n = try reader.interface.readSliceShort(bytes[total..]);
        if (n == 0) break;
        total += n;
    }
    const content = bytes[0..total];
    // A JSON file sink is an array document: "[\n" opens it and "\n]" closes it
    // at close time, so after flush() the file is "[\n" + record + "\n". The
    // color wrap lives inside, around the serialized record.
    try std.testing.expect(std.mem.startsWith(u8, content, "[\n"));
    try std.testing.expect(std.mem.endsWith(u8, content, "\n"));
    const record = content[2 .. content.len - 1];

    // Async rendering follows the logger-wide config: JSON wrapped for
    // terminal presentation, still valid underneath.
    const seq = Color.sequence(Color.Tint.color.ansi4.yellow, Color.defaultCapability);
    try std.testing.expect(std.mem.startsWith(u8, record, seq.slice()));
    try std.testing.expect(std.mem.endsWith(u8, record, Color.resetAll));
    // Strip the single wrap (open seq + reset) to recover valid JSON.
    const inner = record[seq.slice().len .. record.len - Color.resetAll.len];
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, inner, .{});
    defer parsed.deinit();
    try std.testing.expectEqualStrings("async hello", parsed.value.object.get("message").?.string);
}

test "logger colored console sink under live async worker does not stall" {
    // Regression guard for the async presentation path on a colorized console
    // sink. A console sink is the only target that resolves color from TTY
    // detection, so this is the configuration that only runs in an interactive
    // terminal. Cycling the worker many times exercises start/stop/drain races
    // that a single-shot test would miss: a missed drain or a leaked worker
    // shows up here as a stall rather than as a wrong value.
    const allocator = std.testing.allocator;

    var iteration: usize = 0;
    while (iteration < 25) : (iteration += 1) {
        var config = Config.default();
        config.format = .json;
        // stdout belongs to the test runner's protocol; no test may print.
        config.autoSink = false;
        config.globalConsoleDisplay = false;
        config.asyncConfig.enabled = true;
        config.asyncConfig.backgroundWorker = true;

        const logger = try Logger.initWithConfig(allocator, config);
        errdefer logger.deinit();

        // Colorized sink exercising the interactive-terminal presentation path
        // (the same per-sink color resolution a TTY console sink gets) without
        // writing to stdout, which the test runner reserves for its protocol.
        var msink = SinkConfig.memory();
        msink.color = true;
        _ = try logger.addSink(msink);

        var i: usize = 0;
        while (i < 20) : (i += 1) {
            try logger.info("async console presentation", null);
        }
        try logger.flush();
        // Draining an empty queue must return immediately rather than
        // spinning out the shutdown drain timeout on every teardown.
        try logger.flush();
        logger.deinit();
    }
}

test "logger async background worker drains on deinit without a manual flush" {
    // Deinit must not block: the worker owns draining, and deinit joins it
    // rather than waiting out a timeout on a queue nobody will ever service.
    const allocator = std.testing.allocator;
    const path = "test_async_drain_on_deinit.json";
    std.Io.Dir.cwd().deleteFile(Utils.io(), path) catch {};
    defer std.Io.Dir.cwd().deleteFile(Utils.io(), path) catch {};

    var config = Config.default();
    config.format = .json;
    config.globalConsoleDisplay = false;
    config.asyncConfig.enabled = true;
    config.asyncConfig.backgroundWorker = true;

    const logger = try Logger.initWithConfig(allocator, config);
    var scfg = SinkConfig.file(path);
    scfg.color = true;
    _ = try logger.addSink(scfg);

    try logger.warning("queued without explicit flush", null);
    // Deliberately no flush(): deinit has to drain the queue itself.
    logger.deinit();

    var file = try std.Io.Dir.cwd().openFile(Utils.io(), path, .{});
    defer file.close(Utils.io());
    const stat = try file.stat(Utils.io());
    try std.testing.expect(stat.size > 0);
}

test "logger async memory sink retains records instead of writing to stdout" {
    // writeRaw() is the async delivery path. It once had no memory branch and
    // fell through to stdout, silently dropping records from a memory sink and
    // corrupting any protocol sharing stdout. Both sinks below receive the same
    // queued payload, so comparing them pins the regression precisely.
    const allocator = std.testing.allocator;
    const cmp_path = "test_async_memory_cmp.log";
    std.Io.Dir.cwd().deleteFile(Utils.io(), cmp_path) catch {};
    defer std.Io.Dir.cwd().deleteFile(Utils.io(), cmp_path) catch {};

    var config = Config.default();
    config.autoSink = false;
    config.globalConsoleDisplay = false;
    config.asyncConfig.enabled = true;
    config.asyncConfig.backgroundWorker = true;

    const logger = try Logger.initWithConfig(allocator, config);
    defer logger.deinit();

    var msink = SinkConfig.memory();
    msink.memoryCapacity = 64;
    _ = try logger.addSink(msink);
    _ = try logger.addSink(SinkConfig.file(cmp_path));

    // In async mode the async logger owns the sink list, not the logger.
    const sink = logger.asyncLogger.?.sinks.items[0];

    try logger.info("retained by memory sink", null);
    try logger.flush();

    const msgs = try sink.getMemoryMessages(allocator);
    defer {
        for (msgs) |m| allocator.free(m);
        allocator.free(msgs);
    }

    try std.testing.expect(msgs.len > 0);
    var found = false;
    for (msgs) |m| {
        if (std.mem.indexOf(u8, m, "retained by memory sink") != null) found = true;
    }
    try std.testing.expect(found);
}

test "config matrix: autoFlush, autoSink, storage flags and formats agree" {
    // Exercises the combinations that decide which sinks are legal and how
    // records reach them. Silent throughout: stdout belongs to the test
    // runner's protocol (see CONTRIBUTING.md).
    const allocator = std.testing.allocator;
    const path = "test_matrix.log";
    std.Io.Dir.cwd().deleteFile(Utils.io(), path) catch {};
    defer std.Io.Dir.cwd().deleteFile(Utils.io(), path) catch {};

    // Null-device spellings must all be treated alike: they never create a
    // real file, so file-storage-disabled must not reject them.
    inline for ([_][]const u8{ "NUL", "nul", "/dev/null" }) |null_path| {
        const cfg = Config.displayOnly();
        try std.testing.expect(Sink.isNullDevicePath(null_path));
        const l = try Logger.initWithConfig(allocator, cfg);
        defer l.deinit();
        _ = try l.addSink(.{ .path = null_path });
    }

    // displayOnly: console display on, file storage off.
    {
        var cfg = Config.displayOnly();
        cfg.autoSink = true;
        const l = try Logger.initWithConfig(allocator, cfg);
        defer l.deinit();
        // Auto console sink is present; file sinks are refused.
        try std.testing.expect(l.getSinkCount() >= 1);
        try std.testing.expectError(error.FileStorageDisabled, l.addSink(.{ .path = path }));
    }

    // logOnly: file storage on, console display off. autoSink cannot add a
    // console sink, and asking for one is an explicit error.
    {
        var cfg = Config.logOnly();
        cfg.autoSink = true; // conflicting: would imply console output
        const l = try Logger.initWithConfig(allocator, cfg);
        defer l.deinit();
        try std.testing.expectEqual(@as(usize, 0), l.getSinkCount());
        try std.testing.expectError(error.ConsoleDisplayDisabled, l.addSink(SinkConfig.console()));
        _ = try l.addSink(.{ .path = path });
    }

    // autoFlush on and off must both deliver to a file sink.
    inline for ([_]bool{ false, true }) |autoflush| {
        var cfg = Config.default();
        cfg.autoSink = false;
        cfg.autoFlush = autoflush;
        const l = try Logger.initWithConfig(allocator, cfg);
        defer l.deinit();
        _ = try l.addSink(.{ .path = path, .overwriteMode = !autoflush });
        try l.info("autoflush matrix", null);
        try l.flush();
    }

    // A JSON file sink is an array document. The closing bracket is written
    // when the sink closes, so the document is only complete after deinit;
    // reading it mid-session legitimately yields an unterminated array.
    {
        var cfg = Config.default();
        cfg.autoSink = false;
        cfg.format = .json;
        const l = try Logger.initWithConfig(allocator, cfg);
        _ = try l.addSink(.{ .path = path, .format = .json, .overwriteMode = true });
        try l.info("format matrix", null);
        l.deinit();

        const doc = try readWholeFile(allocator, path);
        defer allocator.free(doc);
        const parsed = try std.json.parseFromSlice(std.json.Value, allocator, doc, .{});
        defer parsed.deinit();
        try std.testing.expect(parsed.value == .array);
        try std.testing.expectEqual(@as(usize, 1), parsed.value.array.items.len);
        const first = parsed.value.array.items[0];
        try std.testing.expectEqualStrings("format matrix", first.object.get("message").?.string);
    }

    // Every structured format must survive a silent file sink round-trip.
    inline for ([_]Config.Format{ .text, .json, .ndjson, .logfmt, .syslog, .syslog3164 }) |fmt| {
        var cfg = Config.default();
        cfg.autoSink = false;
        cfg.format = fmt;
        const l = try Logger.initWithConfig(allocator, cfg);
        defer l.deinit();
        _ = try l.addSink(.{ .path = path, .format = fmt, .overwriteMode = true });
        try l.info("format matrix", null);
        try l.flush();
    }

    // MessagePack must not gain a trailing newline, so it is checked through
    // the binary path rather than the text matrix above.
    {
        const mpath = "test_matrix.msgpack";
        std.Io.Dir.cwd().deleteFile(Utils.io(), mpath) catch {};
        defer std.Io.Dir.cwd().deleteFile(Utils.io(), mpath) catch {};
        var cfg = Config.default();
        cfg.autoSink = false;
        cfg.format = .msgpack;
        const l = try Logger.initWithConfig(allocator, cfg);
        defer l.deinit();
        _ = try l.addSink(.{ .path = mpath, .format = .msgpack, .overwriteMode = true });
        try l.info("binary matrix", null);
        try l.flush();

        const blob = try readWholeFile(allocator, mpath);
        defer allocator.free(blob);
        try std.testing.expect(blob.len > 0);
        // A text terminator would corrupt the binary stream.
        try std.testing.expect(blob[blob.len - 1] != '\n');
    }
}

/// Reads a whole file into an owned slice for assertions in tests.
fn readWholeFile(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    var file = try std.Io.Dir.cwd().openFile(Utils.io(), path, .{});
    defer file.close(Utils.io());
    const stat = try file.stat(Utils.io());
    const buf = try allocator.alloc(u8, stat.size);
    errdefer allocator.free(buf);
    var rbuf: [4096]u8 = undefined;
    var reader = file.reader(Utils.io(), &rbuf);
    var total: usize = 0;
    while (total < buf.len) {
        const n = try reader.interface.readSliceShort(buf[total..]);
        if (n == 0) break;
        total += n;
    }
    return allocator.realloc(buf, total) catch buf[0..total];
}

test "logger setColorCallback overrides record color" {
    const allocator = std.testing.allocator;
    var logger = try Logger.init(allocator);
    defer logger.deinit();

    logger.setColorCallback(&testColorCallback);
    try std.testing.expect(logger.colorCallback != null);
}

test "logger displayOnly rejects file sinks" {
    const allocator = std.testing.allocator;
    const path = "test_display_only_rejected.log";
    std.Io.Dir.cwd().deleteFile(Utils.io(), path) catch {};

    var logger = try Logger.initWithConfig(allocator, Config.displayOnly());
    defer logger.deinit();

    try std.testing.expectError(error.FileStorageDisabled, logger.addSink(SinkConfig.file(path)));
    // No file must have been created.
    const stat = std.Io.Dir.cwd().statFile(Utils.io(), path, .{});
    try std.testing.expectError(error.FileNotFound, stat);
}

test "logger logOnly rejects console sinks" {
    const allocator = std.testing.allocator;
    var logger = try Logger.initWithConfig(allocator, Config.logOnly());
    defer logger.deinit();

    try std.testing.expectError(error.ConsoleDisplayDisabled, logger.addSink(SinkConfig.console()));
}

test "logger concurrent logging stress" {
    const allocator = std.testing.allocator;
    var config = Config.default();
    config.autoSink = false;
    var logger = try Logger.initWithConfig(allocator, config);
    defer logger.deinit();
    _ = try logger.addSink(SinkConfig.memory());

    const Worker = struct {
        fn run(l: *Logger) void {
            var i: usize = 0;
            while (i < 100) : (i += 1) {
                l.info("stress message", null) catch {};
            }
        }
    };

    var threads: [8]std.Thread = undefined;
    for (&threads) |*t| t.* = try std.Thread.spawn(.{}, Worker.run, .{logger});
    for (threads) |t| t.join();

    try logger.flush();
    try std.testing.expectEqual(@as(u64, 800), logger.getRecordCount());
}

test "logger shutdown during load stress" {
    const allocator = std.testing.allocator;
    var config = Config.default();
    config.autoSink = false;
    var logger = try Logger.initWithConfig(allocator, config);
    _ = try logger.addSink(SinkConfig.memory());

    const Worker = struct {
        fn run(l: *Logger) void {
            var i: usize = 0;
            while (i < 500) : (i += 1) {
                l.info("load", null) catch {};
                if (i % 100 == 0) l.flush() catch {};
            }
        }
    };

    var threads: [4]std.Thread = undefined;
    for (&threads) |*t| t.* = try std.Thread.spawn(.{}, Worker.run, .{logger});
    for (threads) |t| t.join();

    try logger.flush();
    // All 2000 records must be accounted for (no loss in sync memory sink).
    try std.testing.expectEqual(@as(u64, 2000), logger.getRecordCount());
    logger.deinit();
    // Deinit after join; no use-after-free possible.
}
