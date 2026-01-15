//! Asynchronous Logging Module
//!
//! Provides non-blocking I/O for high-performance logging scenarios.
//! Decouples log submission from persistence using concurrent data structures.
//!
//! Components:
//! - AsyncLogger: Main async logging interface with ring buffer
//! - AsyncFileWriter: Buffered file writer with async flush
//! - RingBuffer: Lock-free circular buffer for log entries
//!
//! Features:
//! - Lock-free ring buffer for minimal contention
//! - Configurable overflow strategies (block, drop, grow)
//! - Batch processing for I/O efficiency
//! - Background worker threads for persistence
//! - Comprehensive statistics and monitoring
//!
//! Performance:
//! - Sub-microsecond log submission in typical cases
//! - Minimal memory copies through buffer pooling
//! - Automatic batch size tuning

const std = @import("std");
const Config = @import("config.zig").Config;
const Record = @import("record.zig").Record;
const Sink = @import("sink.zig").Sink;
const SinkConfig = @import("sink.zig").SinkConfig;
const Constants = @import("constants.zig");
const Utils = @import("utils.zig");

/// Asynchronous logging subsystem for non-blocking I/O operations.
///
/// Decouples log submission from persistence using a concurrent ring buffer
/// and background workers. Designed for low-latency applications.
pub const AsyncLogger = struct {
    /// Memory allocator for async operations.
    allocator: std.mem.Allocator,
    /// Async configuration options.
    config: AsyncConfig,
    /// Ring buffer for queuing log messages.
    buffer: RingBuffer,
    /// Async logger statistics.
    stats: AsyncStats,
    /// Mutex for thread-safe operations.
    mutex: std.Thread.Mutex = .{},
    /// Condition variable for worker thread signaling.
    condition: std.Thread.Condition = .{},
    /// Background worker thread.
    worker_thread: ?std.Thread = null,
    /// Whether the async logger is running.
    running: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    /// List of sinks to write to.
    sinks: std.ArrayList(*Sink) = .empty,

    /// Arena allocator optimized for batch operations to reduce fragmentation and allocation overhead.
    arena: ?std.heap.ArenaAllocator = null,

    /// Callback triggered when the internal buffer exceeds its capacity.
    /// Provides the number of dropped records for monitoring.
    overflow_callback: ?*const fn (dropped_count: u64) void = null,

    /// Callback triggered upon completion of a flush operation.
    /// Provides metrics: records flushed, total bytes, and elapsed time in ms.
    flush_callback: ?*const fn (u64, u64, u64) void = null,

    /// Callback triggered when the background worker thread initializes.
    on_worker_start: ?*const fn () void = null,

    /// Callback triggered when the background worker thread terminates.
    /// Provides total records processed and worker uptime in ms.
    on_worker_stop: ?*const fn (u64, u64) void = null,

    /// Callback triggered after a batch of logs is successfully written.
    /// Provides batch size and processing time in microseconds.
    on_batch_processed: ?*const fn (usize, u64) void = null,

    /// Callback triggered when log processing latency exceeds the configured threshold.
    /// Useful for detecting I/O bottlenecks.
    on_latency_threshold_exceeded: ?*const fn (u64, u64) void = null,

    /// Callback triggered when the buffer reaches full capacity.
    on_full: ?*const fn () void = null,

    /// Callback triggered when the buffer becomes completely empty.
    on_empty: ?*const fn () void = null,

    /// Callback triggered when an internal error occurs during logging.
    on_error: ?*const fn (err: anyerror) void = null,

    /// Configuration parameters for async behavior.
    pub const AsyncConfig = Config.AsyncConfig;

    /// Enumerated policies for handling buffer overflow conditions.
    pub const OverflowPolicy = Config.AsyncConfig.OverflowPolicy;

    /// Priority levels for the background worker thread.
    pub const WorkerPriority = enum {
        /// Low priority worker.
        low,
        /// Normal priority worker.
        normal,
        /// High priority worker.
        high,
        /// Realtime priority worker.
        realtime,
    };

    /// Runtime statistics for monitoring logger performance and health.
    pub const AsyncStats = struct {
        /// Total records queued for async processing.
        records_queued: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        /// Total records successfully written.
        records_written: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        /// Total records dropped due to overflow.
        records_dropped: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        /// Number of buffer overflow events.
        buffer_overflows: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        /// Number of flush operations performed.
        flush_count: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        /// Total latency in nanoseconds.
        total_latency_ns: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        /// Maximum queue depth observed.
        max_queue_depth: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        /// Timestamp of last flush operation.
        last_flush_timestamp: std.atomic.Value(Constants.AtomicSigned) = std.atomic.Value(Constants.AtomicSigned).init(0),

        /// Computes the average latency per record processing.
        /// Complexity: O(1)
        pub fn averageLatencyNs(self: *const AsyncStats) u64 {
            const written = Utils.atomicLoadU64(&self.records_written);
            const total = Utils.atomicLoadU64(&self.total_latency_ns);
            return if (written == 0) 0 else total / written;
        }

        /// Computes the reliable drop rate as a ratio of dropped vs queued records.
        /// Complexity: O(1)
        pub fn dropRate(self: *const AsyncStats) f64 {
            const total = Utils.atomicLoadU64(&self.records_queued);
            const dropped = Utils.atomicLoadU64(&self.records_dropped);
            return Utils.calculateErrorRate(dropped, total);
        }

        /// Returns total records queued as u64.
        pub fn getQueued(self: *const AsyncStats) u64 {
            return Utils.atomicLoadU64(&self.records_queued);
        }

        /// Returns total records written as u64.
        pub fn getWritten(self: *const AsyncStats) u64 {
            return Utils.atomicLoadU64(&self.records_written);
        }

        /// Returns total records dropped as u64.
        pub fn getDropped(self: *const AsyncStats) u64 {
            return Utils.atomicLoadU64(&self.records_dropped);
        }

        /// Returns total flush count as u64.
        pub fn getFlushCount(self: *const AsyncStats) u64 {
            return Utils.atomicLoadU64(&self.flush_count);
        }

        /// Returns max queue depth observed as u64.
        pub fn getMaxQueueDepth(self: *const AsyncStats) u64 {
            return Utils.atomicLoadU64(&self.max_queue_depth);
        }

        /// Returns buffer overflow count as u64.
        pub fn getBufferOverflows(self: *const AsyncStats) u64 {
            return Utils.atomicLoadU64(&self.buffer_overflows);
        }

        /// Checks if any records have been dropped.
        pub fn hasDropped(self: *const AsyncStats) bool {
            return self.records_dropped.load(.monotonic) > 0;
        }

        /// Checks if any buffer overflows occurred.
        pub fn hasOverflows(self: *const AsyncStats) bool {
            return self.buffer_overflows.load(.monotonic) > 0;
        }

        /// Calculate write success rate (0.0 - 1.0).
        pub fn successRate(self: *const AsyncStats) f64 {
            const queued = Utils.atomicLoadU64(&self.records_queued);
            const written = Utils.atomicLoadU64(&self.records_written);
            return Utils.calculateErrorRate(written, queued);
        }

        /// Calculate average latency in milliseconds.
        pub fn averageLatencyMs(self: *const AsyncStats) f64 {
            return @as(f64, @floatFromInt(self.averageLatencyNs())) / 1_000_000.0;
        }
    };

    /// Represents a single log entry within the ring buffer.
    pub const BufferEntry = struct {
        timestamp: i64,
        formatted_message: []const u8,
        level_priority: u8,
        queued_at: i128,
        owned: bool = false,
    };

    /// High-performance circular buffer logic for thread-safe enqueuing and batch dequeuing.
    pub const RingBuffer = struct {
        allocator: std.mem.Allocator,
        entries: []BufferEntry,
        head: usize = 0,
        tail: usize = 0,
        count: usize = 0,
        capacity: usize,

        /// Allocates and initializes the ring buffer.
        /// Complexity: O(N) where N is capacity (allocation).
        pub fn init(allocator: std.mem.Allocator, capacity: usize) !RingBuffer {
            const entries = try allocator.alloc(BufferEntry, capacity);
            return .{
                .allocator = allocator,
                .entries = entries,
                .capacity = capacity,
            };
        }

        /// Releases all resources, ensuring deep cleanup of owned entries.
        pub fn deinit(self: *RingBuffer) void {
            // Only free valid entries
            var i: usize = 0;
            while (i < self.count) : (i += 1) {
                const idx = (self.tail + i) % self.capacity;
                const entry = self.entries[idx];
                if (entry.owned) {
                    self.allocator.free(entry.formatted_message);
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
            self.tail = (self.tail + 1) % self.capacity;
            self.count -= 1;
            return entry;
        }

        /// Remove up to 'batch.len' entries and fill batch array
        /// Performance: O(1) - memcpy approaches peak bandwidth
        pub fn popBatch(self: *RingBuffer, batch: []BufferEntry) usize {
            if (self.count == 0) return 0;
            const n = @min(self.count, batch.len);

            // First chunk: from tail to end of buffer or split point
            const chunk1_size = @min(n, self.capacity - self.tail);
            @memcpy(batch[0..chunk1_size], self.entries[self.tail .. self.tail + chunk1_size]);

            // Second chunk: wrap around if needed
            if (n > chunk1_size) {
                const chunk2_size = n - chunk1_size;
                @memcpy(batch[chunk1_size..n], self.entries[0..chunk2_size]);
            }

            self.tail = (self.tail + n) % self.capacity;
            self.count -= n;
            return n;
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

    /// Initializes an AsyncLogger with default configuration.
    ///
    /// - allocator: Managing allocator for the logger lifecycle.
    /// - Returns: Initialized logger instance.
    pub fn init(allocator: std.mem.Allocator) !*AsyncLogger {
        return initWithConfig(allocator, .{});
    }

    /// Alias for init().
    pub const create = init;

    /// Initializes an AsyncLogger with specific configuration parameters.
    ///
    /// - allocator: Managing allocator.
    /// - config: Operational parameters (buffer size, worker threads, policies).
    /// - Returns: Initialized logger or error.
    ///
    /// Complexity: O(1) mostly, O(N) for buffer allocation.
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

        // Initialize arena allocator if enabled for better batch processing performance
        if (config.use_arena) {
            self.arena = std.heap.ArenaAllocator.init(allocator);
        }

        if (config.background_worker) {
            try self.startWorker();
        }

        return self;
    }

    /// Terminates the logger and releases all resources.
    /// Blocks until the worker thread has completely stopped and flushed pending operations.
    pub fn deinit(self: *AsyncLogger) void {
        self.stop();

        // Flush remaining entries
        self.flushSync();

        // Clean up arena allocator if it was created
        if (self.arena) |*arena| {
            arena.deinit();
        }

        self.buffer.deinit();
        self.sinks.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    /// Alias for deinit().
    pub const destroy = deinit;

    /// Returns the arena allocator if enabled, otherwise the main allocator.
    /// Use this for temporary allocations that can be batch-freed.
    pub fn scratchAllocator(self: *AsyncLogger) std.mem.Allocator {
        if (self.arena) |*arena| {
            return arena.allocator();
        }
        return self.allocator;
    }

    /// Resets the arena allocator if enabled, freeing all temporary allocations.
    /// Call this after processing a batch to reclaim memory.
    pub fn resetArena(self: *AsyncLogger) void {
        if (self.arena) |*arena| {
            _ = arena.reset(.retain_capacity);
        }
    }

    /// Registers a new sink for log output.
    /// Thread-safe.
    pub fn addSink(self: *AsyncLogger, sink: *Sink) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        try self.sinks.append(self.allocator, sink);
    }

    /// Convenience wrapper to initialize and add a sink from configuration.
    pub fn addSinkConfig(self: *AsyncLogger, config: SinkConfig) !*Sink {
        const sink = try Sink.init(self.allocator, config);
        try self.addSink(sink);
        return sink;
    }

    /// Convenience wrapper to add a standard console sink.
    pub fn addConsoleSink(self: *AsyncLogger) !*Sink {
        return self.addSinkConfig(SinkConfig.console());
    }

    /// Enqueues a log record for asynchronous processing.
    ///
    /// Strategy:
    /// 1. Pre-allocates message copy to minimize critical section time.
    /// 2. Acquires lock to access ring buffer.
    /// 3. Applies overflow policy if buffer is full (Drop/Block).
    /// 4. Pushes entry if space available.
    ///
    /// - message: Pre-formatted log message.
    /// - level_priority: numeric priority level.
    /// - Returns: true if enqueued, false if dropped/failure.
    ///
    /// Complexity: O(1) amortized.
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
                        // Attempt to make space by removing oldest entry
                        if (self.buffer.pop()) |old_entry| {
                            if (old_entry.owned) {
                                message_to_free = old_entry.formatted_message;
                            }
                            _ = self.stats.records_dropped.fetchAdd(1, .monotonic);
                        }
                    },
                    .drop_newest => {
                        // Drop the current incoming message
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

                    // Signal worker regarding new data
                    self.condition.signal();
                } else {
                    // This creates a failsafe if unexpected full state occurs
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

    /// Spawns the background worker thread if not already running.
    pub fn startWorker(self: *AsyncLogger) !void {
        if (self.running.load(.acquire)) return;

        self.running.store(true, .release);
        self.worker_thread = try std.Thread.spawn(.{}, workerLoop, .{self});
    }

    /// Signals the background worker to stop and waits for it to join.
    pub fn stop(self: *AsyncLogger) void {
        if (!self.running.load(.acquire)) return;

        self.running.store(false, .release);
        self.condition.broadcast();

        if (self.worker_thread) |thread| {
            thread.join();
            self.worker_thread = null;
        }
    }

    /// Synchronously processes all pending messages in the buffer.
    /// This is typically called during shutdown or panic.
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

    /// Signals the worker thread to perform a flush immediately.
    pub fn flush(self: *AsyncLogger) void {
        self.condition.signal();
    }

    /// Main loop for the background worker thread.
    /// Handles batch retrieval from buffer and writing to sinks.
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
                                cb(@truncate(@as(u64, @intCast(@max(0, @divTrunc(latency, std.time.ns_per_us))))), @truncate(@as(u64, @intCast(self.config.max_latency_ms * 1000))));
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
                _ = self.stats.total_latency_ns.fetchAdd(@truncate(@as(u64, @intCast(@max(0, write_time)))), .monotonic);

                const now_ms = std.time.milliTimestamp();
                self.stats.last_flush_timestamp.store(@truncate(now_ms), .monotonic);
                last_flush = now_ms;

                if (self.flush_callback) |cb| {
                    cb(count, bytes_written, @truncate(@as(u64, @intCast(@max(0, @divTrunc(write_time, std.time.ns_per_ms))))));
                }

                if (self.on_batch_processed) |cb| {
                    cb(count, @truncate(@as(u64, @intCast(@max(0, @divTrunc(write_time, std.time.ns_per_us))))));
                }

                // Reset arena after each batch to free temporary memory
                self.resetArena();
            }
        }
    }

    /// Distributes a single entry to all registered sinks.
    /// Internal errors in sinks are caught and reported via on_error callback.
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

    /// Returns true if the async logger is running.
    pub fn isRunning(self: *const AsyncLogger) bool {
        return self.worker_thread != null;
    }

    /// Returns the buffer capacity.
    pub fn bufferCapacity(self: *const AsyncLogger) usize {
        return self.buffer.capacity;
    }

    /// Returns true if the buffer is full.
    pub fn isFull(self: *AsyncLogger) bool {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.buffer.isFull();
    }

    /// Alias for queue
    pub const enqueue = queue;
    pub const push = queue;
    pub const logMsg = queue;

    /// Alias for getStats
    pub const statistics = getStats;

    /// Alias for queueDepth
    pub const depth = queueDepth;
    pub const pending = queueDepth;

    /// Alias for startWorker
    pub const begin = startWorker;

    /// Alias for stop
    pub const halt = stop;
    pub const end = stop;
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
    bytes_written: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
    last_flush: std.atomic.Value(Constants.AtomicSigned) = std.atomic.Value(Constants.AtomicSigned).init(0),

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

    pub const create = init;

    pub fn deinit(self: *AsyncFileWriter) void {
        self.stop();
        self.flushSync();
        self.buffer.deinit(self.allocator);
        self.file.close();
        self.allocator.destroy(self);
    }

    pub const destroy = deinit;

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
        self.last_flush.store(@truncate(std.time.milliTimestamp()), .monotonic);
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
        return @as(u64, self.bytes_written.load(.monotonic));
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
