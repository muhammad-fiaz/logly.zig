//! Async logging.
//!
//! Non-blocking log submission via ring buffer and background workers.
const std = @import("std");
const Config = @import("config.zig").Config;
const Record = @import("record.zig").Record;
const Sink = @import("sink.zig").Sink;
const Color = @import("color.zig");
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
    mutex: std.Io.Mutex = .init,
    /// Condition variable for worker thread signaling.
    condition: std.Io.Condition = .init,
    /// Background worker thread.
    workerThread: ?std.Thread = null,
    /// Whether the async logger is running.
    running: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    /// List of sinks to write to.
    sinks: std.ArrayList(*Sink) = .empty,

    /// Callback triggered when the internal buffer exceeds its capacity.
    /// Provides the number of dropped records for monitoring.
    overflowCallback: ?*const fn (droppedCount: u64) void = null,

    /// Callback triggered upon completion of a flush operation.
    /// Provides metrics: records flushed, total bytes, and elapsed time in ms.
    flushCallback: ?*const fn (u64, u64, u64) void = null,

    /// Callback triggered when the background worker thread initializes.
    onWorkerStart: ?*const fn () void = null,

    /// Callback triggered when the background worker thread terminates.
    /// Provides total records processed and worker uptime in ms.
    onWorkerStop: ?*const fn (u64, u64) void = null,

    /// Callback triggered after a batch of logs is successfully written.
    /// Provides batch size and processing time in microseconds.
    onBatchProcessed: ?*const fn (usize, u64) void = null,

    /// Callback triggered after a batch of logs is successfully flushed.
    /// Provides batch size and processing latency in nanoseconds.
    onBatchFlushed: ?*const fn (count: usize, latencyNs: u64) void = null,

    /// Callback triggered when log processing latency exceeds the configured threshold.
    /// Useful for detecting I/O bottlenecks.
    onLatencyThresholdExceeded: ?*const fn (u64, u64) void = null,

    /// Callback triggered when the buffer reaches full capacity.
    onFull: ?*const fn () void = null,

    /// Callback triggered when the buffer becomes completely empty.
    onEmpty: ?*const fn () void = null,

    /// Callback triggered when an internal error occurs during logging.
    onError: ?*const fn (err: anyerror) void = null,

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
        recordsQueued: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        /// Total records successfully written.
        recordsWritten: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        /// Total records dropped due to overflow.
        recordsDropped: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        /// Number of buffer overflow events.
        bufferOverflows: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        /// Number of times the queue entered a high-utilization backpressure range.
        backpressureEvents: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        /// Number of flush operations performed.
        flushCount: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        /// Total latency in nanoseconds.
        totalLatencyNs: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        /// Maximum queue depth observed.
        maxQueueDepth: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        /// Timestamp of last flush operation.
        lastFlushTimestamp: std.atomic.Value(Constants.AtomicSigned) = std.atomic.Value(Constants.AtomicSigned).init(0),

        /// Computes the average latency per record processing.
        pub fn averageLatencyNs(self: *const AsyncStats) u64 {
            const written = Utils.atomicLoadU64(&self.recordsWritten);
            const total = Utils.atomicLoadU64(&self.totalLatencyNs);
            return if (written == 0) 0 else total / written;
        }

        /// Computes the reliable drop rate as a ratio of dropped vs queued records.
        pub fn dropRate(self: *const AsyncStats) f64 {
            const total = Utils.atomicLoadU64(&self.recordsQueued);
            const dropped = Utils.atomicLoadU64(&self.recordsDropped);
            return Utils.calculateErrorRate(dropped, total);
        }

        /// Returns total records queued as u64.
        pub fn getQueued(self: *const AsyncStats) u64 {
            return Utils.atomicLoadU64(&self.recordsQueued);
        }

        /// Returns total records written as u64.
        pub fn getWritten(self: *const AsyncStats) u64 {
            return Utils.atomicLoadU64(&self.recordsWritten);
        }

        /// Returns total records dropped as u64.
        pub fn getDropped(self: *const AsyncStats) u64 {
            return Utils.atomicLoadU64(&self.recordsDropped);
        }

        /// Returns records that are queued but not yet written.
        pub fn inFlight(self: *const AsyncStats) u64 {
            const queued = self.getQueued();
            const written = self.getWritten();
            return if (queued > written) queued - written else 0;
        }

        /// Returns total flush count as u64.
        pub fn getFlushCount(self: *const AsyncStats) u64 {
            return Utils.atomicLoadU64(&self.flushCount);
        }

        /// Returns max queue depth observed as u64.
        pub fn getMaxQueueDepth(self: *const AsyncStats) u64 {
            return Utils.atomicLoadU64(&self.maxQueueDepth);
        }

        /// Returns buffer overflow count as u64.
        pub fn getBufferOverflows(self: *const AsyncStats) u64 {
            return Utils.atomicLoadU64(&self.bufferOverflows);
        }

        /// Returns backpressure event count as u64.
        pub fn getBackpressureEvents(self: *const AsyncStats) u64 {
            return Utils.atomicLoadU64(&self.backpressureEvents);
        }

        /// Checks if any records have been dropped.
        pub fn hasDropped(self: *const AsyncStats) bool {
            return self.recordsDropped.load(.monotonic) > 0;
        }

        /// Checks if any buffer overflows occurred.
        pub fn hasOverflows(self: *const AsyncStats) bool {
            return self.bufferOverflows.load(.monotonic) > 0;
        }

        /// Checks if any backpressure events occurred.
        pub fn hasBackpressureEvents(self: *const AsyncStats) bool {
            return self.backpressureEvents.load(.monotonic) > 0;
        }

        /// Calculate write success rate (0.0 - 1.0).
        pub fn successRate(self: *const AsyncStats) f64 {
            const queued = Utils.atomicLoadU64(&self.recordsQueued);
            const written = Utils.atomicLoadU64(&self.recordsWritten);
            return Utils.calculateErrorRate(written, queued);
        }

        /// Calculate average latency in milliseconds.
        pub fn averageLatencyMs(self: *const AsyncStats) f64 {
            return @as(f64, @floatFromInt(self.averageLatencyNs())) / @as(f64, @floatFromInt(Constants.TimeConstants.nsPerMs));
        }
    };

    /// Represents a single log entry within the ring buffer.
    pub const BufferEntry = struct {
        timestamp: i64,
        formattedMessage: []const u8,
        levelPriority: u8,
        queuedAt: i128,
        owned: bool = false,
        /// Binary payloads (e.g. MessagePack) route to writeRawBinary so
        /// no line terminator corrupts the byte stream.
        binary: bool = false,
        /// Resolved presentation color for this record, or null for none.
        ///
        /// Carried alongside the *uncolored* serialized bytes so each sink can
        /// apply (or ignore) presentation independently at write time. Storing
        /// pre-wrapped bytes here would leak console coloring into files and
        /// network sinks that never asked for it.
        color: ?Color.Color = null,
        /// Whether the logger-wide color mode selects vertical (per-field)
        /// presentation over horizontal (whole-record) wrapping.
        colorVertical: bool = false,
        /// True when the serialized form is one where color is presentation
        /// applied around the payload (json/ndjson/syslog/syslog3164). False
        /// for text/logfmt (colored inline by the formatter) and msgpack
        /// (binary must stay byte-exact).
        colorPresentable: bool = false,
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
                    self.allocator.free(entry.formattedMessage);
                }
            }
            self.allocator.free(self.entries);
        }

        /// Add entry to buffer
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
        pub fn pop(self: *RingBuffer) ?BufferEntry {
            if (self.count == 0) return null;
            const entry = self.entries[self.tail];
            self.tail = (self.tail + 1) % self.capacity;
            self.count -= 1;
            return entry;
        }

        /// Remove up to 'batch.len' entries and fill batch array
        pub fn popBatch(self: *RingBuffer, batch: []BufferEntry) usize {
            if (self.count == 0) return 0;
            const n = @min(self.count, batch.len);

            // First chunk: from tail to end of buffer or split point
            const chunk1Size = @min(n, self.capacity - self.tail);
            @memcpy(batch[0..chunk1Size], self.entries[self.tail .. self.tail + chunk1Size]);

            // Second chunk: wrap around if needed
            if (n > chunk1Size) {
                const chunk2Size = n - chunk1Size;
                @memcpy(batch[chunk1Size..n], self.entries[0..chunk2Size]);
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
                    self.allocator.free(entry.formattedMessage);
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
            .buffer = try RingBuffer.init(allocator, config.bufferSize),
            .stats = .{},
            .sinks = .empty,
        };

        if (config.backgroundWorker) {
            try self.startWorker();
        }

        return self;
    }

    /// Terminates the logger and releases all resources.
    /// Blocks until the worker thread has completely stopped and flushed pending operations.
    pub fn deinit(self: *AsyncLogger) void {
        _ = self.drainAndFlush(self.config.shutdownTimeoutMs);
        self.stop();

        // Flush remaining entries
        self.flushSync();

        // Release every owned sink (files, rotation state, ring buffers).
        // The list alone does not own the sinks' resources.
        for (self.sinks.items) |sink| {
            sink.deinit();
        }
        self.buffer.deinit();
        self.sinks.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    /// Returns the allocator for temporary allocations.
    pub fn scratchAllocator(self: *AsyncLogger) std.mem.Allocator {
        return self.allocator;
    }

    /// Returns the effective batch size after clamping configuration to the static buffer.
    pub fn effectiveBatchSize(self: *const AsyncLogger) usize {
        if (self.config.batchSize == 0) return 1;
        return @min(self.config.batchSize, Constants.AsyncConstants.batchSize);
    }

    /// Registers a new sink for log output.
    /// Thread-safe.
    pub fn addSink(self: *AsyncLogger, sink: *Sink) !void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
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
    pub fn queue(self: *AsyncLogger, message: []const u8, levelPriority: u8) bool {
        return self.queueInternal(message, levelPriority, false, null, false, false);
    }

    /// Queues an already-serialized record together with its resolved
    /// presentation color.
    ///
    /// The bytes stay uncolored; sinks apply presentation according to their
    /// own configuration when the entry is drained.
    pub fn queuePresented(self: *AsyncLogger, message: []const u8, levelPriority: u8, color: ?Color.Color, vertical: bool, presentable: bool) bool {
        return self.queueInternal(message, levelPriority, false, color, vertical, presentable);
    }

    /// Queues a binary payload (e.g. MessagePack) that must not gain a
    /// line terminator at the sink. Routes to writeRawBinary downstream.
    pub fn queueBinary(self: *AsyncLogger, message: []const u8, levelPriority: u8) bool {
        return self.queueInternal(message, levelPriority, true, null, false, false);
    }

    fn queueInternal(self: *AsyncLogger, message: []const u8, levelPriority: u8, binary: bool, color: ?Color.Color, vertical: bool, presentable: bool) bool {
        // High-priority records (Critical/Fatal) skip the queue
        if (levelPriority >= Constants.LevelConstants.Priorities.critical) {
            self.mutex.lockUncancelable(Utils.io());
            defer self.mutex.unlock(Utils.io());
            const entry = BufferEntry{
                .timestamp = Utils.currentMillis(),
                .formattedMessage = message,
                .levelPriority = levelPriority,
                .queuedAt = Utils.currentNanos(),
                .owned = false,
                .binary = binary,
                .color = color,
                .colorVertical = vertical,
                .colorPresentable = presentable,
            };
            self.writeToSinks(entry);
            return true;
        }

        // Optimization: Allocate outside the lock to reduce contention
        const ownedMessage = self.allocator.dupe(u8, message) catch {
            _ = self.stats.recordsDropped.fetchAdd(1, .monotonic);
            return false;
        };

        var messageToFree: ?[]const u8 = null;
        var dropped = false;

        {
            self.mutex.lockUncancelable(Utils.io());
            defer self.mutex.unlock(Utils.io());

            const now = Utils.currentNanos();

            // Handle overflow
            if (self.buffer.isFull()) {
                if (self.onFull) |cb| cb();

                switch (self.config.overflowPolicy) {
                    .dropOldest => {
                        // Attempt to make space by removing oldest entry
                        if (self.buffer.pop()) |oldEntry| {
                            if (oldEntry.owned) {
                                messageToFree = oldEntry.formattedMessage;
                            }
                            _ = self.stats.recordsDropped.fetchAdd(1, .monotonic);
                        }
                    },
                    .dropNewest => {
                        // Drop the current incoming message
                        _ = self.stats.recordsDropped.fetchAdd(1, .monotonic);
                        _ = self.stats.bufferOverflows.fetchAdd(1, .monotonic);
                        if (self.overflowCallback) |cb| {
                            cb(self.stats.recordsDropped.load(.monotonic));
                        }
                        messageToFree = ownedMessage;
                        dropped = true;
                    },
                    .block => {
                        // Wait for space (with timeout to prevent deadlock)
                        self.mutex.unlock(Utils.io());
                        Utils.sleepNs(Constants.AsyncConstants.blockSleepNs);
                        self.mutex.lockUncancelable(Utils.io());
                        if (self.buffer.isFull()) {
                            _ = self.stats.recordsDropped.fetchAdd(1, .monotonic);
                            messageToFree = ownedMessage;
                            dropped = true;
                        }
                    },
                }
            }

            if (!dropped) {
                const entry = BufferEntry{
                    .timestamp = Utils.currentMillis(),
                    .formattedMessage = ownedMessage,
                    .levelPriority = levelPriority,
                    .queuedAt = now,
                    .owned = true,
                    .binary = binary,
                    .color = color,
                    .colorVertical = vertical,
                    .colorPresentable = presentable,
                };

                if (self.buffer.push(entry)) {
                    _ = self.stats.recordsQueued.fetchAdd(1, .monotonic);

                    const threshold = if (self.config.backpressureThreshold < 0.0)
                        0.0
                    else if (self.config.backpressureThreshold > 1.0)
                        1.0
                    else
                        self.config.backpressureThreshold;
                    const queueLoad = if (self.buffer.capacity == 0)
                        0.0
                    else
                        @as(f64, @floatFromInt(self.buffer.count)) / @as(f64, @floatFromInt(self.buffer.capacity));
                    if (queueLoad >= threshold) {
                        _ = self.stats.backpressureEvents.fetchAdd(1, .monotonic);
                    }

                    // Update max queue depth
                    const current = self.buffer.size();
                    var max = self.stats.maxQueueDepth.load(.monotonic);
                    while (current > max) {
                        const result = self.stats.maxQueueDepth.cmpxchgWeak(max, current, .monotonic, .monotonic);
                        if (result) |v| {
                            max = v;
                        } else {
                            break;
                        }
                    }

                    // Signal worker regarding new data
                    self.condition.signal(Utils.io());
                } else {
                    // This creates a failsafe if unexpected full state occurs
                    messageToFree = ownedMessage;
                    dropped = true;
                }
            }
        }

        if (messageToFree) |msg| {
            self.allocator.free(msg);
        }

        return !dropped;
    }

    /// Spawns the background worker thread if not already running.
    pub fn startWorker(self: *AsyncLogger) !void {
        if (self.running.load(.acquire)) return;

        self.running.store(true, .release);
        self.workerThread = try std.Thread.spawn(.{}, workerLoop, .{self});
    }

    /// Signals the background worker to stop and waits for it to join.
    pub fn stop(self: *AsyncLogger) void {
        if (!self.running.load(.acquire)) return;

        self.running.store(false, .release);
        self.condition.broadcast(Utils.io());

        if (self.workerThread) |thread| {
            thread.join();
            self.workerThread = null;
        }
    }

    /// Synchronously processes all pending messages in the buffer.
    /// This is typically called during shutdown or panic.
    pub fn flushSync(self: *AsyncLogger) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());

        var batch: [Constants.AsyncConstants.batchSize]BufferEntry = undefined;
        const batchLimit = self.effectiveBatchSize();
        const startTime = Utils.currentMillis();
        var totalFlushed: u64 = 0;
        var totalBytes: u64 = 0;

        while (true) {
            const count = self.buffer.popBatch(batch[0..batchLimit]);
            if (count == 0) break;

            for (batch[0..count]) |entry| {
                totalBytes += entry.formattedMessage.len;
                self.writeToSinks(entry);
                if (entry.owned) {
                    self.allocator.free(entry.formattedMessage);
                }
            }
            totalFlushed += count;
        }

        if (totalFlushed > 0) {
            _ = self.stats.flushCount.fetchAdd(1, .monotonic);
            const elapsed = Utils.currentMillis() - startTime;
            if (self.flushCallback) |cb| {
                cb(totalFlushed, totalBytes, @intCast(elapsed));
            }
        }

        // Ensure all registered sinks flush their underlying OS and user buffers
        for (self.sinks.items) |sink| {
            sink.flush() catch {};
        }
    }

    /// Signals the worker thread to perform a flush immediately.
    pub fn flush(self: *AsyncLogger) void {
        self.condition.signal(Utils.io());
    }

    /// Main loop for the background worker thread.
    /// Handles batch retrieval from buffer and writing to sinks.
    fn workerLoop(self: *AsyncLogger) void {
        if (self.onWorkerStart) |cb| cb();

        const startTime = Utils.currentMillis();
        defer {
            if (self.onWorkerStop) |cb| {
                const uptime = @as(u64, @intCast(Utils.currentMillis() - startTime));
                cb(self.stats.recordsWritten.load(.monotonic), uptime);
            }
        }

        var batch: [Constants.AsyncConstants.batchSize]BufferEntry = undefined;
        const batchLimit = self.effectiveBatchSize();
        var lastFlush = Utils.currentMillis();

        while (self.running.load(.acquire) or !self.buffer.isEmpty()) {
            self.mutex.lockUncancelable(Utils.io());

            // Wait for entries or timeout
            const now = Utils.currentMillis();
            const elapsed = now - lastFlush;

            if (self.buffer.isEmpty()) {
                if (self.onEmpty) |cb| cb();
                self.mutex.unlock(Utils.io());
                Utils.sleepMs(self.config.flushIntervalMs);
                self.mutex.lockUncancelable(Utils.io());
            } else if (self.config.minFlushIntervalMs > 0 and elapsed < @as(i64, @intCast(self.config.minFlushIntervalMs))) {
                // Enforce minimum flush interval
                const waitTime = self.config.minFlushIntervalMs - @as(u64, @intCast(elapsed));
                self.mutex.unlock(Utils.io());
                Utils.sleepMs(waitTime);
                self.mutex.lockUncancelable(Utils.io());
            }

            // Process batch
            const count = self.buffer.popBatch(batch[0..batchLimit]);
            self.mutex.unlock(Utils.io());

            if (count > 0) {
                const writeStart = Utils.currentNanos();
                var bytesWritten: u64 = 0;

                for (batch[0..count]) |entry| {
                    const nowNs = Utils.currentNanos();
                    const latency = nowNs - entry.queuedAt;
                    if (self.config.maxLatencyMs > 0) {
                        const thresholdNs = @as(i128, @intCast(self.config.maxLatencyMs)) * Constants.TimeConstants.nsPerMs;
                        if (latency > thresholdNs) {
                            if (self.onLatencyThresholdExceeded) |cb| {
                                cb(@truncate(@as(u64, @intCast(@max(0, @divTrunc(latency, Constants.TimeConstants.nsPerUs))))), @truncate(@as(u64, @intCast(self.config.maxLatencyMs * Constants.TimeConstants.usPerMs))));
                            }
                        }
                    }

                    bytesWritten += entry.formattedMessage.len;
                    self.writeToSinks(entry);
                    if (entry.owned) {
                        self.allocator.free(entry.formattedMessage);
                    }
                }

                const writeEnd = Utils.currentNanos();
                const writeTime = writeEnd - writeStart;
                _ = self.stats.totalLatencyNs.fetchAdd(@truncate(@as(u64, @intCast(@max(0, writeTime)))), .monotonic);

                const nowMs = Utils.currentMillis();
                self.stats.lastFlushTimestamp.store(@truncate(nowMs), .monotonic);
                lastFlush = nowMs;

                if (self.flushCallback) |cb| {
                    cb(count, bytesWritten, @truncate(@as(u64, @intCast(@max(0, @divTrunc(writeTime, Constants.TimeConstants.nsPerMs))))));
                }

                if (self.onBatchProcessed) |cb| {
                    cb(count, @truncate(@as(u64, @intCast(@max(0, @divTrunc(writeTime, Constants.TimeConstants.nsPerUs))))));
                }

                if (self.onBatchFlushed) |cb| {
                    cb(count, @truncate(@as(u64, @intCast(@max(0, writeTime)))));
                }
            }
        }
    }

    /// Distributes a single entry to all registered sinks.
    /// Internal errors in sinks are caught and reported via on_error callback.
    fn writeToSinks(self: *AsyncLogger, entry: BufferEntry) void {
        for (self.sinks.items) |sink| {
            if (entry.binary) {
                sink.writeRawBinary(entry.formattedMessage) catch |err| {
                    if (self.onError) |cb| cb(err);
                };
            } else {
                // Presentation is applied per sink here, not at queue time, so
                // a console-only color setting can never push ANSI into a file
                // or network sink. Serialized bytes stay valid underneath.
                if (entry.color) |c| {
                    if (sink.applyQueuedPresentation(self.allocator, entry.formattedMessage, c, entry.colorVertical, entry.colorPresentable)) |presented| {
                        defer self.allocator.free(presented);
                        sink.writeRaw(presented) catch |err| {
                            if (self.onError) |cb| cb(err);
                        };
                        continue;
                    }
                }
                sink.writeRaw(entry.formattedMessage) catch |err| {
                    if (self.onError) |cb| cb(err);
                };
            }
        }
        _ = self.stats.recordsWritten.fetchAdd(1, .monotonic);
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
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        return self.buffer.size();
    }

    /// Checks if queue is empty.
    pub fn isQueueEmpty(self: *AsyncLogger) bool {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        return self.buffer.isEmpty();
    }

    /// Returns available queue slots before reaching capacity.
    pub fn availableCapacity(self: *AsyncLogger) usize {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());

        const currentDepth = self.buffer.size();
        return if (self.buffer.capacity > currentDepth) self.buffer.capacity - currentDepth else 0;
    }

    /// Returns queue utilization as a ratio in [0.0, 1.0].
    pub fn queueUtilization(self: *AsyncLogger) f64 {
        const capacity = self.bufferCapacity();
        if (capacity == 0) return 0.0;

        const currentDepth = self.queueDepth();
        return @as(f64, @floatFromInt(currentDepth)) / @as(f64, @floatFromInt(capacity));
    }

    /// Returns true when queue utilization is above the provided threshold.
    pub fn isNearCapacity(self: *AsyncLogger, threshold: f64) bool {
        const clamped = if (threshold < 0.0)
            0.0
        else if (threshold > 1.0)
            1.0
        else
            threshold;
        return self.queueUtilization() >= clamped;
    }

    /// Wait until queue is drained or timeout is reached.
    ///
    /// Returns true when drained before timeout.
    pub fn waitUntilDrained(self: *AsyncLogger, timeoutMs: u64) bool {
        if (timeoutMs == 0) {
            return self.isQueueEmpty();
        }

        const start = Utils.currentMillis();
        while (true) {
            if (self.isQueueEmpty()) return true;

            const elapsed = Utils.currentMillis() - start;
            if (elapsed >= @as(i64, @intCast(timeoutMs))) {
                return false;
            }

            self.flush();
            Utils.sleepMs(1);
        }
    }

    /// Waits for the queue to drain using the configured drain timeout.
    pub fn waitUntilDrainedDefault(self: *AsyncLogger) bool {
        return self.waitUntilDrained(self.config.drainTimeoutMs);
    }

    /// Blocks until the queue is completely empty or the timeout expires.
    /// Returns true if successfully drained, false on timeout.
    pub fn drainAndFlush(self: *AsyncLogger, timeoutMs: u64) bool {
        return self.waitUntilDrained(timeoutMs);
    }

    /// Sets overflow callback.
    pub fn setOverflowCallback(self: *AsyncLogger, callback: *const fn (u64) void) void {
        self.overflowCallback = callback;
    }

    /// Sets flush callback.
    pub fn setFlushCallback(self: *AsyncLogger, callback: *const fn (u64, u64, u64) void) void {
        self.flushCallback = callback;
    }

    /// Sets worker start callback.
    pub fn setWorkerStartCallback(self: *AsyncLogger, callback: *const fn () void) void {
        self.onWorkerStart = callback;
    }

    /// Sets worker stop callback.
    pub fn setWorkerStopCallback(self: *AsyncLogger, callback: *const fn (u64, u64) void) void {
        self.onWorkerStop = callback;
    }

    /// Sets batch processed callback.
    pub fn setBatchProcessedCallback(self: *AsyncLogger, callback: *const fn (usize, u64) void) void {
        self.onBatchProcessed = callback;
    }

    /// Sets latency threshold exceeded callback.
    pub fn setLatencyThresholdExceededCallback(self: *AsyncLogger, callback: *const fn (u64, u64) void) void {
        self.onLatencyThresholdExceeded = callback;
    }

    /// Sets buffer full callback.
    pub fn setFullCallback(self: *AsyncLogger, callback: *const fn () void) void {
        self.onFull = callback;
    }

    /// Sets buffer empty callback.
    pub fn setEmptyCallback(self: *AsyncLogger, callback: *const fn () void) void {
        self.onEmpty = callback;
    }

    /// Sets error callback.
    pub fn setErrorCallback(self: *AsyncLogger, callback: *const fn (anyerror) void) void {
        self.onError = callback;
    }

    /// Returns true if the async logger is running.
    pub fn isRunning(self: *const AsyncLogger) bool {
        return self.workerThread != null;
    }

    /// Returns the buffer capacity.
    pub fn bufferCapacity(self: *const AsyncLogger) usize {
        return self.buffer.capacity;
    }

    /// Returns true if the buffer is full.
    pub fn isFull(self: *AsyncLogger) bool {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        return self.buffer.isFull();
    }

    /// Returns true when queue utilization is >= 90%.
    pub fn isBackpressured(self: *AsyncLogger) bool {
        return self.isNearCapacity(0.9);
    }
};

/// Async file writer for high-performance file logging.
pub const AsyncFileWriter = struct {
    allocator: std.mem.Allocator,
    file: std.Io.File,
    buffer: std.ArrayList(u8),
    config: FileConfig,
    mutex: std.Io.Mutex = .init,
    flushThread: ?std.Thread = null,
    running: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    totalBytesWritten: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
    lastFlush: std.atomic.Value(Constants.AtomicSigned) = std.atomic.Value(Constants.AtomicSigned).init(0),

    /// Buffering options for `AsyncFileWriter`.
    pub const FileConfig = struct {
        bufferSize: usize = Constants.AsyncPresetDefaults.highThroughputBufferSize,
        flushIntervalMs: u64 = Constants.SinkDefaults.flushIntervalMs,
        syncOnFlush: bool = false,
        appendMode: bool = true,
    };

    /// Opens `path` for buffered background writes.
    pub fn init(allocator: std.mem.Allocator, path: []const u8, config: FileConfig) !*AsyncFileWriter {
        const self = try allocator.create(AsyncFileWriter);
        errdefer allocator.destroy(self);

        const file = try std.Io.Dir.cwd().createFile(Utils.io(), path, .{
            .truncate = !config.appendMode,
        });
        errdefer file.close(Utils.io());

        self.* = .{
            .allocator = allocator,
            .file = file,
            .buffer = .empty,
            .config = config,
        };

        try self.buffer.ensureTotalCapacity(self.allocator, config.bufferSize);

        return self;
    }

    /// Flushes, closes the file, and releases the writer.
    pub fn deinit(self: *AsyncFileWriter) void {
        self.stop();
        self.flushSync();
        self.buffer.deinit(self.allocator);
        self.file.close(Utils.io());
        self.allocator.destroy(self);
    }

    /// Queues `data` verbatim, with no line terminator.
    pub fn write(self: *AsyncFileWriter, data: []const u8) !void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());

        try self.buffer.appendSlice(self.allocator, data);

        if (self.buffer.items.len >= self.config.bufferSize) {
            try self.flushInternal();
        }
    }

    /// Queues `data` followed by a newline.
    pub fn writeLine(self: *AsyncFileWriter, data: []const u8) !void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());

        try self.buffer.appendSlice(self.allocator, data);
        try self.buffer.append(self.allocator, '\n');

        if (self.buffer.items.len >= self.config.bufferSize) {
            try self.flushInternal();
        }
    }

    fn flushInternal(self: *AsyncFileWriter) !void {
        if (self.buffer.items.len == 0) return;

        const offset = if (self.config.appendMode) try self.file.length(Utils.io()) else 0;
        try self.file.writePositionalAll(Utils.io(), self.buffer.items, offset);
        _ = self.totalBytesWritten.fetchAdd(self.buffer.items.len, .monotonic);

        if (self.config.syncOnFlush) {
            try self.file.sync(Utils.io());
        }

        self.buffer.clearRetainingCapacity();
        self.lastFlush.store(@truncate(Utils.currentMillis()), .monotonic);
    }

    /// Drains the queue on the calling thread.
    pub fn flushSync(self: *AsyncFileWriter) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        self.flushInternal() catch {};
    }

    /// Starts periodic background flushing.
    pub fn startAutoFlush(self: *AsyncFileWriter) !void {
        if (self.running.load(.acquire)) return;
        self.running.store(true, .release);
        self.flushThread = try std.Thread.spawn(.{}, autoFlushLoop, .{self});
    }

    /// Stops periodic background flushing and joins flush thread.
    pub fn stop(self: *AsyncFileWriter) void {
        if (!self.running.load(.acquire)) return;
        self.running.store(false, .release);
        if (self.flushThread) |thread| {
            thread.join();
            self.flushThread = null;
        }
    }

    fn autoFlushLoop(self: *AsyncFileWriter) void {
        while (self.running.load(.acquire)) {
            Utils.sleepMs(self.config.flushIntervalMs);
            self.flushSync();
        }
    }

    /// Returns total flushed bytes written by the async writer.
    pub fn bytesWritten(self: *const AsyncFileWriter) u64 {
        return @as(u64, self.totalBytesWritten.load(.monotonic));
    }
};

/// Preset configurations for async logging.
pub const AsyncPresets = struct {
    /// High-throughput configuration for maximum performance.
    pub fn highThroughput() AsyncLogger.AsyncConfig {
        return .{
            .bufferSize = Constants.AsyncPresetDefaults.highThroughputBufferSize,
            .flushIntervalMs = Constants.AsyncPresetDefaults.highThroughputFlushIntervalMs,
            .minFlushIntervalMs = Constants.AsyncPresetDefaults.highThroughputMinFlushIntervalMs,
            .maxLatencyMs = Constants.AsyncPresetDefaults.highThroughputMaxLatencyMs,
            .batchSize = Constants.AsyncPresetDefaults.highThroughputBatchSize,
            .overflowPolicy = .dropOldest,
            .backgroundWorker = true,
        };
    }

    /// Low-latency configuration for responsive logging.
    pub fn lowLatency() AsyncLogger.AsyncConfig {
        return .{
            .bufferSize = Constants.AsyncPresetDefaults.lowLatencyBufferSize,
            .flushIntervalMs = Constants.AsyncPresetDefaults.lowLatencyFlushIntervalMs,
            .minFlushIntervalMs = Constants.AsyncPresetDefaults.lowLatencyMinFlushIntervalMs,
            .maxLatencyMs = Constants.AsyncPresetDefaults.lowLatencyMaxLatencyMs,
            .batchSize = Constants.AsyncPresetDefaults.lowLatencyBatchSize,
            .overflowPolicy = .block,
            .backgroundWorker = true,
        };
    }

    /// Balanced configuration for general use.
    pub fn balanced() AsyncLogger.AsyncConfig {
        return .{
            .bufferSize = Constants.BufferSizes.asyncQueue,
            .flushIntervalMs = Constants.AsyncPresetDefaults.balancedFlushIntervalMs,
            .minFlushIntervalMs = Constants.AsyncPresetDefaults.balancedMinFlushIntervalMs,
            .maxLatencyMs = Constants.AsyncPresetDefaults.balancedMaxLatencyMs,
            .batchSize = Constants.AsyncConstants.batchSize,
            .overflowPolicy = .dropOldest,
            .backgroundWorker = true,
        };
    }

    /// No-drop configuration (blocks when full).
    pub fn noDrop() AsyncLogger.AsyncConfig {
        return .{
            .bufferSize = Constants.AsyncPresetDefaults.noDropBufferSize,
            .flushIntervalMs = Constants.AsyncPresetDefaults.balancedFlushIntervalMs,
            .minFlushIntervalMs = Constants.AsyncPresetDefaults.balancedMinFlushIntervalMs,
            .maxLatencyMs = Constants.AsyncPresetDefaults.balancedMaxLatencyMs,
            .batchSize = Constants.AsyncConstants.batchSize,
            .overflowPolicy = .block,
            .backgroundWorker = true,
        };
    }
};

test "ring buffer basic" {
    const allocator = std.testing.allocator;

    var rb = try AsyncLogger.RingBuffer.init(allocator, 4);
    defer rb.deinit();

    try std.testing.expect(rb.isEmpty());
    try std.testing.expect(!rb.isFull());

    _ = rb.push(.{ .timestamp = 1, .formattedMessage = "test1", .levelPriority = 20, .queuedAt = 0 });
    _ = rb.push(.{ .timestamp = 2, .formattedMessage = "test2", .levelPriority = 20, .queuedAt = 0 });

    try std.testing.expectEqual(@as(usize, 2), rb.size());

    const entry = rb.pop();
    try std.testing.expect(entry != null);
    try std.testing.expectEqual(@as(i64, 1), entry.?.timestamp);
}

test "async stats" {
    var stats = AsyncLogger.AsyncStats{};

    _ = stats.recordsQueued.fetchAdd(100, .monotonic);
    _ = stats.recordsDropped.fetchAdd(10, .monotonic);

    try std.testing.expect(stats.dropRate() > 0.09 and stats.dropRate() < 0.11);
}

test "async stats in flight" {
    var stats = AsyncLogger.AsyncStats{};

    _ = stats.recordsQueued.fetchAdd(20, .monotonic);
    _ = stats.recordsWritten.fetchAdd(7, .monotonic);

    try std.testing.expectEqual(@as(u64, 13), stats.inFlight());
    try std.testing.expectEqual(@as(u64, 13), stats.inFlight());
}

const TestCallbacks = struct {
    pub var overflowCalled: bool = false;
    pub var flushCalled: bool = false;
    pub var fullCalled: bool = false;

    pub fn onOverflow(dropped: u64) void {
        _ = dropped;
        overflowCalled = true;
    }

    pub fn onFlush(count: u64, bytes: u64, elapsed: u64) void {
        _ = count;
        _ = bytes;
        _ = elapsed;
        flushCalled = true;
    }

    pub fn onFull() void {
        fullCalled = true;
    }
};

test "async callbacks" {
    const allocator = std.testing.allocator;

    // Reset flags
    TestCallbacks.overflowCalled = false;
    TestCallbacks.flushCalled = false;
    TestCallbacks.fullCalled = false;

    const config = AsyncLogger.AsyncConfig{
        .bufferSize = 2,
        .overflowPolicy = .dropNewest,
        .flushIntervalMs = 10,
        .backgroundWorker = false,
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

    try std.testing.expect(TestCallbacks.fullCalled);
    try std.testing.expect(TestCallbacks.overflowCalled);

    // Flush
    logger.flushSync();
    try std.testing.expect(TestCallbacks.flushCalled);
}

test "async queue utilization and drain helpers" {
    const allocator = std.testing.allocator;

    const config = AsyncLogger.AsyncConfig{
        .bufferSize = 4,
        .backgroundWorker = false,
        .overflowPolicy = .dropNewest,
    };

    var logger = try AsyncLogger.initWithConfig(allocator, config);
    defer logger.deinit();

    _ = logger.queue("one", 1);
    _ = logger.queue("two", 1);

    try std.testing.expectEqual(@as(usize, 2), logger.queueDepth());
    try std.testing.expectEqual(@as(usize, 2), logger.availableCapacity());
    try std.testing.expectApproxEqAbs(@as(f64, 0.5), logger.queueUtilization(), 0.001);
    try std.testing.expect(logger.isNearCapacity(0.5));
    try std.testing.expect(!logger.isNearCapacity(0.75));

    logger.flushSync();
    try std.testing.expect(logger.waitUntilDrained(25));
    try std.testing.expect(logger.waitUntilDrainedDefault());
}

test "async backpressure events" {
    const allocator = std.testing.allocator;

    const config = AsyncLogger.AsyncConfig{
        .bufferSize = 2,
        .backgroundWorker = false,
        .overflowPolicy = .dropNewest,
        .backpressureThreshold = 0.5,
    };

    var logger = try AsyncLogger.initWithConfig(allocator, config);
    defer logger.deinit();

    _ = logger.queue("alpha", 1);
    _ = logger.queue("beta", 1);

    try std.testing.expect(logger.stats.hasBackpressureEvents());
    try std.testing.expect(logger.stats.getBackpressureEvents() > 0);
    try std.testing.expect(logger.stats.getBackpressureEvents() > 0);
}

test "async effective batch size respects config" {
    const allocator = std.testing.allocator;

    var logger = try AsyncLogger.initWithConfig(allocator, .{
        .bufferSize = 8,
        .batchSize = 3,
        .backgroundWorker = false,
    });
    defer logger.deinit();

    try std.testing.expectEqual(@as(usize, 3), logger.effectiveBatchSize());

    logger.config.batchSize = 0;
    try std.testing.expectEqual(@as(usize, 1), logger.effectiveBatchSize());

    logger.config.batchSize = Constants.AsyncConstants.batchSize * 4;
    try std.testing.expectEqual(Constants.AsyncConstants.batchSize, logger.effectiveBatchSize());
}
