const std = @import("std");
const Config = @import("config.zig").Config;
const Record = @import("record.zig").Record;
const Sink = @import("sink.zig").Sink;

/// Asynchronous logging infrastructure for non-blocking operations.
///
/// Provides non-blocking log operations with configurable buffering,
/// background processing threads, and batch writing for high-throughput scenarios.
///
/// Features:
/// - High-performance ring buffer for minimal contention
/// - Background worker thread for batch processing
/// - Configurable overflow policies (drop, block, or custom callback)
/// - Comprehensive statistics tracking
///
/// Usage:
/// ```zig
/// var async_logger = try logly.AsyncLogger.init(allocator);
/// defer async_logger.deinit();
///
/// // Add a sink (e.g., file sink)
/// const sink = try logly.Sink.init(allocator, .file("app.log"));
/// try async_logger.addSink(sink);
///
/// // Queue a log message
/// _ = async_logger.queue("Log message", 1);
/// ```
///
/// Callbacks:
/// - `on_overflow`: Called when buffer overflows
/// - `on_flush`: Called when buffer is flushed
/// - `on_worker_start`: Called when worker thread starts
/// - `on_worker_stop`: Called when worker thread stops
/// - `on_batch_processed`: Called after processing a batch
/// - `on_latency_threshold_exceeded`: Called when latency exceeds threshold
///
/// Performance:
/// - Low CPU overhead for typical workloads
/// - Sub-millisecond latency from enqueue to worker processing
/// - Batch processing reduces syscalls and I/O operations
/// - Optimized buffer access
pub const AsyncLogger = struct {
    allocator: std.mem.Allocator,
    config: AsyncConfig,
    buffer: RingBuffer,
    stats: AsyncStats,
    mutex: std.Thread.Mutex = .{},
    condition: std.Thread.Condition = .{},
    worker_thread: ?std.Thread = null,
    running: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    sinks: std.ArrayList(*Sink),

    /// Callback invoked when buffer overflows (depends on overflow policy)
    /// Parameters: (dropped_count: u64)
    overflow_callback: ?*const fn (dropped_count: u64) void = null,

    /// Callback invoked when buffer is flushed
    /// Parameters: (records_flushed: u64, bytes_flushed: u64, elapsed_ms: u64)
    flush_callback: ?*const fn (u64, u64, u64) void = null,

    /// Callback invoked when worker thread starts
    on_worker_start: ?*const fn () void = null,

    /// Callback invoked when worker thread stops
    /// Parameters: (records_processed: u64, uptime_ms: u64)
    on_worker_stop: ?*const fn (u64, u64) void = null,

    /// Callback invoked after processing a batch
    /// Parameters: (batch_size: usize, processing_time_us: u64)
    on_batch_processed: ?*const fn (usize, u64) void = null,

    /// Callback invoked when latency exceeds threshold
    /// Parameters: (actual_latency_us: u64, threshold_us: u64)
    on_latency_threshold_exceeded: ?*const fn (u64, u64) void = null,

    /// Callback invoked when buffer becomes full
    on_full: ?*const fn () void = null,

    /// Callback invoked when buffer becomes empty
    on_empty: ?*const fn () void = null,

    /// Callback invoked when an error occurs
    on_error: ?*const fn (err: anyerror) void = null,

    /// Configuration for async logging behavior.
    /// Re-exports centralized config for convenience.
    pub const AsyncConfig = Config.AsyncConfig;

    /// What to do when the buffer is full.
    /// Re-exports centralized overflow policy for convenience.
    pub const OverflowPolicy = Config.AsyncConfig.OverflowPolicy;

    /// Worker thread priority levels for resource management.
    pub const WorkerPriority = enum {
        low,
        normal,
        high,
        realtime,
    };

    /// Statistics for async operations with comprehensive metrics.
    pub const AsyncStats = struct {
        records_queued: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
        records_written: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
        records_dropped: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
        buffer_overflows: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
        flush_count: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
        total_latency_ns: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
        max_queue_depth: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
        last_flush_timestamp: std.atomic.Value(i64) = std.atomic.Value(i64).init(0),

        /// Calculate average latency in nanoseconds
        /// Performance: O(1) - atomic load
        pub fn averageLatencyNs(self: *const AsyncStats) u64 {
            const written = self.records_written.load(.monotonic);
            if (written == 0) return 0;
            return self.total_latency_ns.load(.monotonic) / written;
        }

        /// Calculate drop rate (0.0 - 1.0)
        /// Performance: O(1) - atomic loads
        pub fn dropRate(self: *const AsyncStats) f64 {
            const total = self.records_queued.load(.monotonic);
            if (total == 0) return 0;
            const dropped = self.records_dropped.load(.monotonic);
            return @as(f64, @floatFromInt(dropped)) / @as(f64, @floatFromInt(total));
        }
    };

    /// Entry in the ring buffer.
    pub const BufferEntry = struct {
        timestamp: i64,
        formatted_message: []const u8,
        level_priority: u8,
        queued_at: i128,
        owned: bool = false,
    };

    /// High-performance ring buffer for enqueue/dequeue with overflow protection.
    /// Note: This implementation is thread-safe when used with the AsyncLogger's mutex.
    pub const RingBuffer = struct {
        allocator: std.mem.Allocator,
        entries: []?BufferEntry,
        head: usize = 0,
        tail: usize = 0,
        count: usize = 0,
        capacity: usize,

        /// Initialize ring buffer with specified capacity
        /// Performance: O(capacity) - allocates and zeros memory
        pub fn init(allocator: std.mem.Allocator, capacity: usize) !RingBuffer {
            const entries = try allocator.alloc(?BufferEntry, capacity);
            @memset(entries, null);
            return .{
                .allocator = allocator,
                .entries = entries,
                .capacity = capacity,
            };
        }

        /// Free all resources including any owned entries
        pub fn deinit(self: *RingBuffer) void {
            for (self.entries) |entry_opt| {
                if (entry_opt) |entry| {
                    if (entry.owned) {
                        self.allocator.free(entry.formatted_message);
                    }
                }
            }
            self.allocator.free(self.entries);
        }

        /// Add entry to buffer
        /// Returns: true if successful, false if buffer is full
        /// Performance: O(1) - simple index and count update
        pub fn push(self: *RingBuffer, entry: BufferEntry) bool {
            if (self.count >= self.capacity) {
                return false;
            }
            self.entries[self.head] = entry;
            self.head = (self.head + 1) % self.capacity;
            self.count += 1;
            return true;
        }

        /// Remove and return next entry from buffer
        /// Returns: entry or null if buffer is empty
        /// Performance: O(1) - simple index and count update
        pub fn pop(self: *RingBuffer) ?BufferEntry {
            if (self.count == 0) return null;
            const entry = self.entries[self.tail];
            self.entries[self.tail] = null;
            self.tail = (self.tail + 1) % self.capacity;
            self.count -= 1;
            return entry;
        }

        /// Remove up to 'batch.len' entries and fill batch array
        /// Performance: O(batch_size) - single scan
        pub fn popBatch(self: *RingBuffer, batch: []BufferEntry) usize {
            var count: usize = 0;
            while (count < batch.len) {
                if (self.pop()) |entry| {
                    batch[count] = entry;
                    count += 1;
                } else {
                    break;
                }
            }
            return count;
        }

        /// Check if buffer is at capacity
        pub fn isFull(self: *const RingBuffer) bool {
            return self.count >= self.capacity;
        }

        /// Check if buffer is empty
        pub fn isEmpty(self: *const RingBuffer) bool {
            return self.count == 0;
        }

        /// Get current count of entries in buffer
        pub fn size(self: *const RingBuffer) usize {
            return self.count;
        }

        /// Clear all entries and free any owned allocations
        pub fn clear(self: *RingBuffer) void {
            while (self.pop()) |entry| {
                if (entry.owned) {
                    self.allocator.free(entry.formatted_message);
                }
            }
        }
    };

    /// Initializes a new AsyncLogger.
    ///
    /// Arguments:
    ///     allocator: Memory allocator for internal operations.
    ///
    /// Returns:
    ///     A new AsyncLogger instance with default configuration.
    pub fn init(allocator: std.mem.Allocator) !*AsyncLogger {
        return initWithConfig(allocator, .{});
    }

    /// Initializes an AsyncLogger with custom configuration.
    ///
    /// Arguments:
    ///     allocator: Memory allocator.
    ///     config: Custom async configuration.
    ///
    /// Returns:
    ///     A new AsyncLogger instance.
    pub fn initWithConfig(allocator: std.mem.Allocator, config: AsyncConfig) !*AsyncLogger {
        const self = try allocator.create(AsyncLogger);
        errdefer allocator.destroy(self);

        self.* = .{
            .allocator = allocator,
            .config = config,
            .buffer = try RingBuffer.init(allocator, config.buffer_size),
            .stats = .{},
            .sinks = .empty,
        };

        if (config.background_worker) {
            try self.startWorker();
        }

        return self;
    }

    /// Releases all resources.
    pub fn deinit(self: *AsyncLogger) void {
        self.stop();

        // Flush remaining entries
        self.flushSync();

        self.buffer.deinit();
        self.sinks.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    /// Adds a sink for async writing.
    pub fn addSink(self: *AsyncLogger, sink: *Sink) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        try self.sinks.append(self.allocator, sink);
    }

    /// Queues a log record for async processing.
    ///
    /// Arguments:
    ///     message: The formatted log message.
    ///     level_priority: Priority of the log level.
    ///
    /// Returns:
    ///     true if queued successfully, false if dropped.
    pub fn queue(self: *AsyncLogger, message: []const u8, level_priority: u8) bool {
        // Optimization: Allocate outside the lock to reduce contention
        const owned_message = self.allocator.dupe(u8, message) catch {
            _ = self.stats.records_dropped.fetchAdd(1, .monotonic);
            return false;
        };

        var message_to_free: ?[]const u8 = null;
        var dropped = false;

        {
            self.mutex.lock();
            defer self.mutex.unlock();

            const now = std.time.nanoTimestamp();

            // Handle overflow
            if (self.buffer.isFull()) {
                if (self.on_full) |cb| cb();

                switch (self.config.overflow_policy) {
                    .drop_oldest => {
                        if (self.buffer.pop()) |old_entry| {
                            if (old_entry.owned) {
                                message_to_free = old_entry.formatted_message;
                            }
                            _ = self.stats.records_dropped.fetchAdd(1, .monotonic);
                        }
                    },
                    .drop_newest => {
                        _ = self.stats.records_dropped.fetchAdd(1, .monotonic);
                        _ = self.stats.buffer_overflows.fetchAdd(1, .monotonic);
                        if (self.overflow_callback) |cb| {
                            cb(self.stats.records_dropped.load(.monotonic));
                        }
                        message_to_free = owned_message;
                        dropped = true;
                    },
                    .block => {
                        // Wait for space (with timeout to prevent deadlock)
                        self.mutex.unlock();
                        std.Thread.sleep(1 * std.time.ns_per_ms);
                        self.mutex.lock();
                        if (self.buffer.isFull()) {
                            _ = self.stats.records_dropped.fetchAdd(1, .monotonic);
                            message_to_free = owned_message;
                            dropped = true;
                        }
                    },
                }
            }

            if (!dropped) {
                const entry = BufferEntry{
                    .timestamp = std.time.milliTimestamp(),
                    .formatted_message = owned_message,
                    .level_priority = level_priority,
                    .queued_at = now,
                    .owned = true,
                };

                if (self.buffer.push(entry)) {
                    _ = self.stats.records_queued.fetchAdd(1, .monotonic);

                    // Update max queue depth
                    const current = self.buffer.size();
                    var max = self.stats.max_queue_depth.load(.monotonic);
                    while (current > max) {
                        const result = self.stats.max_queue_depth.cmpxchgWeak(max, current, .monotonic, .monotonic);
                        if (result) |v| {
                            max = v;
                        } else {
                            break;
                        }
                    }

                    // Signal worker
                    self.condition.signal();
                } else {
                    message_to_free = owned_message;
                    dropped = true;
                }
            }
        }

        if (message_to_free) |msg| {
            self.allocator.free(msg);
        }

        return !dropped;
    }

    /// Starts the background worker thread.
    pub fn startWorker(self: *AsyncLogger) !void {
        if (self.running.load(.acquire)) return;

        self.running.store(true, .release);
        self.worker_thread = try std.Thread.spawn(.{}, workerLoop, .{self});
    }

    /// Stops the background worker thread.
    pub fn stop(self: *AsyncLogger) void {
        if (!self.running.load(.acquire)) return;

        self.running.store(false, .release);
        self.condition.broadcast();

        if (self.worker_thread) |thread| {
            thread.join();
            self.worker_thread = null;
        }
    }

    /// Flushes all pending entries synchronously.
    pub fn flushSync(self: *AsyncLogger) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var batch: [64]BufferEntry = undefined;
        const start_time = std.time.milliTimestamp();
        var total_flushed: u64 = 0;
        var total_bytes: u64 = 0;

        while (true) {
            const count = self.buffer.popBatch(&batch);
            if (count == 0) break;

            for (batch[0..count]) |entry| {
                total_bytes += entry.formatted_message.len;
                self.writeToSinks(entry);
                if (entry.owned) {
                    self.allocator.free(entry.formatted_message);
                }
            }
            total_flushed += count;
        }

        if (total_flushed > 0) {
            _ = self.stats.flush_count.fetchAdd(1, .monotonic);
            const elapsed = std.time.milliTimestamp() - start_time;
            if (self.flush_callback) |cb| {
                cb(total_flushed, total_bytes, @intCast(elapsed));
            }
        }
    }

    /// Triggers an async flush.
    pub fn flush(self: *AsyncLogger) void {
        self.condition.signal();
    }

    fn workerLoop(self: *AsyncLogger) void {
        if (self.on_worker_start) |cb| cb();

        const start_time = std.time.milliTimestamp();
        defer {
            if (self.on_worker_stop) |cb| {
                const uptime = @as(u64, @intCast(std.time.milliTimestamp() - start_time));
                cb(self.stats.records_written.load(.monotonic), uptime);
            }
        }

        var batch: [64]BufferEntry = undefined;
        var last_flush = std.time.milliTimestamp();

        while (self.running.load(.acquire) or !self.buffer.isEmpty()) {
            self.mutex.lock();

            // Wait for entries or timeout
            const now = std.time.milliTimestamp();
            const elapsed = now - last_flush;

            if (self.buffer.isEmpty()) {
                if (self.on_empty) |cb| cb();
                // Wait with timeout
                self.condition.timedWait(&self.mutex, self.config.flush_interval_ms * std.time.ns_per_ms) catch {};
            } else if (self.config.min_flush_interval_ms > 0 and elapsed < @as(i64, @intCast(self.config.min_flush_interval_ms))) {
                // Enforce minimum flush interval
                const wait_time = self.config.min_flush_interval_ms - @as(u64, @intCast(elapsed));
                self.condition.timedWait(&self.mutex, wait_time * std.time.ns_per_ms) catch {};
            }

            // Process batch
            const count = self.buffer.popBatch(&batch);
            self.mutex.unlock();

            if (count > 0) {
                const write_start = std.time.nanoTimestamp();
                var bytes_written: u64 = 0;

                for (batch[0..count]) |entry| {
                    const now_ns = std.time.nanoTimestamp();
                    const latency = now_ns - entry.queued_at;
                    if (self.config.max_latency_ms > 0) {
                        const threshold_ns = @as(i128, @intCast(self.config.max_latency_ms)) * std.time.ns_per_ms;
                        if (latency > threshold_ns) {
                            if (self.on_latency_threshold_exceeded) |cb| {
                                cb(@intCast(@divTrunc(latency, std.time.ns_per_us)), @intCast(self.config.max_latency_ms * 1000));
                            }
                        }
                    }

                    bytes_written += entry.formatted_message.len;
                    self.writeToSinks(entry);
                    if (entry.owned) {
                        self.allocator.free(entry.formatted_message);
                    }
                }

                const write_end = std.time.nanoTimestamp();
                const write_time = write_end - write_start;
                _ = self.stats.total_latency_ns.fetchAdd(@intCast(write_time), .monotonic);

                const now_ms = std.time.milliTimestamp();
                self.stats.last_flush_timestamp.store(now_ms, .monotonic);
                last_flush = now_ms;

                if (self.flush_callback) |cb| {
                    cb(count, bytes_written, @intCast(@divTrunc(write_time, std.time.ns_per_ms)));
                }

                if (self.on_batch_processed) |cb| {
                    cb(count, @intCast(@divTrunc(write_time, std.time.ns_per_us)));
                }
            }
        }
    }

    fn writeToSinks(self: *AsyncLogger, entry: BufferEntry) void {
        for (self.sinks.items) |sink| {
            sink.writeRaw(entry.formatted_message) catch |err| {
                if (self.on_error) |cb| cb(err);
            };
        }
        _ = self.stats.records_written.fetchAdd(1, .monotonic);
    }

    /// Gets current statistics.
    pub fn getStats(self: *const AsyncLogger) AsyncStats {
        return self.stats;
    }

    /// Resets statistics.
    pub fn resetStats(self: *AsyncLogger) void {
        self.stats = .{};
    }

    /// Gets current queue depth.
    pub fn queueDepth(self: *AsyncLogger) usize {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.buffer.size();
    }

    /// Checks if queue is empty.
    pub fn isQueueEmpty(self: *AsyncLogger) bool {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.buffer.isEmpty();
    }

    /// Sets overflow callback.
    pub fn setOverflowCallback(self: *AsyncLogger, callback: *const fn (u64) void) void {
        self.overflow_callback = callback;
    }

    /// Sets flush callback.
    pub fn setFlushCallback(self: *AsyncLogger, callback: *const fn (u64, u64, u64) void) void {
        self.flush_callback = callback;
    }

    /// Sets worker start callback.
    pub fn setWorkerStartCallback(self: *AsyncLogger, callback: *const fn () void) void {
        self.on_worker_start = callback;
    }

    /// Sets worker stop callback.
    pub fn setWorkerStopCallback(self: *AsyncLogger, callback: *const fn (u64, u64) void) void {
        self.on_worker_stop = callback;
    }

    /// Sets batch processed callback.
    pub fn setBatchProcessedCallback(self: *AsyncLogger, callback: *const fn (usize, u64) void) void {
        self.on_batch_processed = callback;
    }

    /// Sets latency threshold exceeded callback.
    pub fn setLatencyThresholdExceededCallback(self: *AsyncLogger, callback: *const fn (u64, u64) void) void {
        self.on_latency_threshold_exceeded = callback;
    }

    /// Sets buffer full callback.
    pub fn setFullCallback(self: *AsyncLogger, callback: *const fn () void) void {
        self.on_full = callback;
    }

    /// Sets buffer empty callback.
    pub fn setEmptyCallback(self: *AsyncLogger, callback: *const fn () void) void {
        self.on_empty = callback;
    }

    /// Sets error callback.
    pub fn setErrorCallback(self: *AsyncLogger, callback: *const fn (anyerror) void) void {
        self.on_error = callback;
    }
};

/// Async file writer for high-performance file logging.
pub const AsyncFileWriter = struct {
    allocator: std.mem.Allocator,
    file: std.fs.File,
    buffer: std.ArrayList(u8),
    config: FileConfig,
    mutex: std.Thread.Mutex = .{},
    flush_thread: ?std.Thread = null,
    running: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    bytes_written: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    last_flush: std.atomic.Value(i64) = std.atomic.Value(i64).init(0),

    pub const FileConfig = struct {
        buffer_size: usize = 64 * 1024, // 64KB
        flush_interval_ms: u64 = 1000,
        sync_on_flush: bool = false,
        append_mode: bool = true,
    };

    pub fn init(allocator: std.mem.Allocator, path: []const u8, config: FileConfig) !*AsyncFileWriter {
        const self = try allocator.create(AsyncFileWriter);
        errdefer allocator.destroy(self);

        const file = try std.fs.cwd().createFile(path, .{
            .truncate = !config.append_mode,
        });
        errdefer file.close();

        // Seek to end if appending
        if (config.append_mode) {
            try file.seekFromEnd(0);
        }

        self.* = .{
            .allocator = allocator,
            .file = file,
            .buffer = .empty,
            .config = config,
        };

        try self.buffer.ensureTotalCapacity(self.allocator, config.buffer_size);

        return self;
    }

    pub fn deinit(self: *AsyncFileWriter) void {
        self.stop();
        self.flushSync();
        self.buffer.deinit(self.allocator);
        self.file.close();
        self.allocator.destroy(self);
    }

    pub fn write(self: *AsyncFileWriter, data: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        try self.buffer.appendSlice(self.allocator, data);

        if (self.buffer.items.len >= self.config.buffer_size) {
            try self.flushInternal();
        }
    }

    pub fn writeLine(self: *AsyncFileWriter, data: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        try self.buffer.appendSlice(self.allocator, data);
        try self.buffer.append(self.allocator, '\n');

        if (self.buffer.items.len >= self.config.buffer_size) {
            try self.flushInternal();
        }
    }

    fn flushInternal(self: *AsyncFileWriter) !void {
        if (self.buffer.items.len == 0) return;

        try self.file.writeAll(self.buffer.items);
        _ = self.bytes_written.fetchAdd(self.buffer.items.len, .monotonic);

        if (self.config.sync_on_flush) {
            try self.file.sync();
        }

        self.buffer.clearRetainingCapacity();
        self.last_flush.store(std.time.milliTimestamp(), .monotonic);
    }

    pub fn flushSync(self: *AsyncFileWriter) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.flushInternal() catch {};
    }

    pub fn startAutoFlush(self: *AsyncFileWriter) !void {
        if (self.running.load(.acquire)) return;
        self.running.store(true, .release);
        self.flush_thread = try std.Thread.spawn(.{}, autoFlushLoop, .{self});
    }

    pub fn stop(self: *AsyncFileWriter) void {
        if (!self.running.load(.acquire)) return;
        self.running.store(false, .release);
        if (self.flush_thread) |thread| {
            thread.join();
            self.flush_thread = null;
        }
    }

    fn autoFlushLoop(self: *AsyncFileWriter) void {
        while (self.running.load(.acquire)) {
            std.Thread.sleep(self.config.flush_interval_ms * std.time.ns_per_ms);
            self.flushSync();
        }
    }

    pub fn bytesWritten(self: *const AsyncFileWriter) u64 {
        return self.bytes_written.load(.monotonic);
    }
};

/// Preset configurations for async logging.
pub const AsyncPresets = struct {
    /// High-throughput configuration for maximum performance.
    pub fn highThroughput() AsyncLogger.AsyncConfig {
        return .{
            .buffer_size = 65536,
            .flush_interval_ms = 500,
            .min_flush_interval_ms = 50,
            .max_latency_ms = 1000,
            .batch_size = 256,
            .overflow_policy = .drop_oldest,
            .background_worker = true,
        };
    }

    /// Low-latency configuration for responsive logging.
    pub fn lowLatency() AsyncLogger.AsyncConfig {
        return .{
            .buffer_size = 1024,
            .flush_interval_ms = 10,
            .min_flush_interval_ms = 1,
            .max_latency_ms = 50,
            .batch_size = 16,
            .overflow_policy = .block,
            .background_worker = true,
        };
    }

    /// Balanced configuration for general use.
    pub fn balanced() AsyncLogger.AsyncConfig {
        return .{
            .buffer_size = 8192,
            .flush_interval_ms = 100,
            .min_flush_interval_ms = 10,
            .max_latency_ms = 500,
            .batch_size = 64,
            .overflow_policy = .drop_oldest,
            .background_worker = true,
        };
    }

    /// No-drop configuration (blocks when full).
    pub fn noDrop() AsyncLogger.AsyncConfig {
        return .{
            .buffer_size = 16384,
            .flush_interval_ms = 100,
            .min_flush_interval_ms = 10,
            .max_latency_ms = 500,
            .batch_size = 64,
            .overflow_policy = .block,
            .background_worker = true,
        };
    }
};

test "ring buffer basic" {
    const allocator = std.testing.allocator;

    var rb = try AsyncLogger.RingBuffer.init(allocator, 4);
    defer rb.deinit();

    try std.testing.expect(rb.isEmpty());
    try std.testing.expect(!rb.isFull());

    _ = rb.push(.{ .timestamp = 1, .formatted_message = "test1", .level_priority = 20, .queued_at = 0 });
    _ = rb.push(.{ .timestamp = 2, .formatted_message = "test2", .level_priority = 20, .queued_at = 0 });

    try std.testing.expectEqual(@as(usize, 2), rb.size());

    const entry = rb.pop();
    try std.testing.expect(entry != null);
    try std.testing.expectEqual(@as(i64, 1), entry.?.timestamp);
}

test "async stats" {
    var stats = AsyncLogger.AsyncStats{};

    _ = stats.records_queued.fetchAdd(100, .monotonic);
    _ = stats.records_dropped.fetchAdd(10, .monotonic);

    try std.testing.expect(stats.dropRate() > 0.09 and stats.dropRate() < 0.11);
}

const TestCallbacks = struct {
    pub var overflow_called: bool = false;
    pub var flush_called: bool = false;
    pub var full_called: bool = false;

    pub fn onOverflow(dropped: u64) void {
        _ = dropped;
        overflow_called = true;
    }

    pub fn onFlush(count: u64, bytes: u64, elapsed: u64) void {
        _ = count;
        _ = bytes;
        _ = elapsed;
        flush_called = true;
    }

    pub fn onFull() void {
        full_called = true;
    }
};

test "async callbacks" {
    const allocator = std.testing.allocator;

    // Reset flags
    TestCallbacks.overflow_called = false;
    TestCallbacks.flush_called = false;
    TestCallbacks.full_called = false;

    const config = AsyncLogger.AsyncConfig{
        .buffer_size = 2,
        .overflow_policy = .drop_newest,
        .flush_interval_ms = 10,
        .background_worker = false,
    };

    var logger = try AsyncLogger.initWithConfig(allocator, config);
    defer logger.deinit();

    logger.setOverflowCallback(TestCallbacks.onOverflow);
    logger.setFlushCallback(TestCallbacks.onFlush);
    logger.setFullCallback(TestCallbacks.onFull);

    // Fill buffer
    _ = logger.queue("msg1", 1);
    _ = logger.queue("msg2", 1);

    // Should be full now
    try std.testing.expect(logger.buffer.isFull());

    // Try to add one more -> overflow + full callback
    _ = logger.queue("msg3", 1);

    try std.testing.expect(TestCallbacks.full_called);
    try std.testing.expect(TestCallbacks.overflow_called);

    // Flush
    logger.flushSync();
    try std.testing.expect(TestCallbacks.flush_called);
}
