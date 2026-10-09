//! Thread pool.
//!
//! Work-stealing pool for parallel log processing.
const std = @import("std");
const Config = @import("config.zig").Config;
const Constants = @import("constants.zig");
const Utils = @import("utils.zig");

/// Thread pool for parallel log processing with full callback support.
///
/// Provides concurrent execution of logging tasks with configurable
/// thread count, work stealing, load balancing, and comprehensive monitoring.
pub const ThreadPool = struct {
    /// Memory allocator for pool operations.
    allocator: std.mem.Allocator,
    /// Explicit Io handle for thread pool synchronization.
    io: std.Io = Utils.defaultIo(),
    /// Thread pool configuration.
    config: ThreadPoolConfig,
    /// Worker threads array.
    workers: []Worker,
    /// Work queue for pending tasks.
    workQueue: WorkQueue,
    /// Thread pool statistics.
    stats: ThreadPoolStats,
    /// Whether the pool is currently running.
    running: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    /// Whether shutdown has completed.
    shutdownComplete: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    /// Next task ID generator.
    nextTaskId: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(1),

    /// Callback invoked when worker thread starts.
    onThreadStart: ?*const fn (usize) void = null,

    /// Callback invoked when worker thread stops.
    onThreadStop: ?*const fn (usize, u64, u64) void = null,

    /// Callback invoked when task is submitted.
    onTaskSubmitted: ?*const fn (u8, usize) void = null,

    /// Callback invoked when task is dequeued.
    onTaskDequeued: ?*const fn (u8, u64) void = null,

    /// Callback invoked after task execution.
    onTaskExecuted: ?*const fn (u64, bool) void = null,

    /// Callback invoked when work stealing occurs.
    onWorkStolen: ?*const fn (usize, usize) void = null,

    /// Callback invoked when queue reaches capacity.
    onQueueOverflow: ?*const fn (usize, usize) void = null,

    /// Configuration for the thread pool.
    /// Uses centralized config as base with extended options.
    pub const ThreadPoolConfig = Config.ThreadPoolConfig;

    /// Presets for common thread pool configurations.
    /// Uses Constants.ThreadDefaults for consistent defaults.
    pub const ThreadPoolPresets = struct {
        /// Default configuration: auto-detect threads, standard queue size.
        /// Best for general-purpose workloads.
        pub fn default() ThreadPoolConfig {
            return .{
                .threadCount = Constants.ThreadDefaults.threadCount,
                .queueSize = Constants.ThreadDefaults.queueSize,
                .stackSize = Constants.ThreadDefaults.stackSize,
            };
        }

        /// High-throughput configuration: larger queues, work stealing enabled.
        /// Optimized for sustained high volume workloads.
        pub fn highThroughput() ThreadPoolConfig {
            return .{
                .threadCount = Constants.ThreadDefaults.threadCount, // Auto-detect
                .queueSize = Constants.ThreadDefaults.maxTasks,
                .workStealing = true,
                .stackSize = Constants.ThreadDefaults.highThroughputStackSize,
            };
        }

        /// Low-resource configuration: minimal threads, small queues.
        /// For embedded systems or resource-constrained environments.
        pub fn lowResource() ThreadPoolConfig {
            return .{
                .threadCount = Constants.ThreadDefaults.lowLatencyThreadCount,
                .queueSize = Constants.ThreadDefaults.queueSizeLow,
                .workStealing = false,
                .stackSize = Constants.ThreadDefaults.lowResourceStackSize,
            };
        }

        /// I/O-bound configuration: optimized for disk/network workloads.
        /// Uses 2x CPU cores for better I/O parallelism.
        pub fn ioBound() ThreadPoolConfig {
            return .{
                .threadCount = Constants.ThreadDefaults.ioBoundThreadCount(),
                .queueSize = Constants.ThreadDefaults.ioBoundQueueSize,
                .workStealing = true,
                .stackSize = Constants.ThreadDefaults.stackSize,
            };
        }

        /// CPU-bound configuration: optimized for compute-heavy tasks.
        /// Uses exactly CPU core count.
        pub fn cpuBound() ThreadPoolConfig {
            return .{
                .threadCount = Constants.ThreadDefaults.cpuBoundThreadCount(),
                .queueSize = Constants.ThreadDefaults.queueSize,
                .workStealing = false, // Less stealing for CPU-bound
                .stackSize = Constants.ThreadDefaults.stackSize,
            };
        }
    };

    /// Statistics for thread pool operations with detailed tracking.
    pub const ThreadPoolStats = struct {
        /// Total tasks submitted to the pool.
        tasksSubmitted: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        /// Total tasks completed.
        tasksCompleted: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        /// Number of tasks stolen via work stealing.
        tasksStolen: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        tasksDropped: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        tasksCancelled: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        totalWaitTimeNs: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        totalExecTimeNs: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        activeThreads: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),

        /// Calculate average wait time in nanoseconds
        pub fn avgWaitTimeNs(self: *const ThreadPoolStats) u64 {
            const completed = Utils.atomicLoadU64(&self.tasksCompleted);
            const totalWait = Utils.atomicLoadU64(&self.totalWaitTimeNs);
            return if (completed == 0) 0 else totalWait / completed;
        }

        /// Calculate average execution time in nanoseconds
        pub fn avgExecTimeNs(self: *const ThreadPoolStats) u64 {
            const completed = Utils.atomicLoadU64(&self.tasksCompleted);
            const totalExec = Utils.atomicLoadU64(&self.totalExecTimeNs);
            return if (completed == 0) 0 else totalExec / completed;
        }

        /// Calculate throughput (tasks per second)
        pub fn throughput(self: *const ThreadPoolStats) f64 {
            const completed = Utils.atomicLoadU64(&self.tasksCompleted);
            const execTime = Utils.atomicLoadU64(&self.totalExecTimeNs);
            if (execTime == 0) return 0;
            const nsPerSec = @as(f64, @floatFromInt(Constants.TimeConstants.nsPerSecond));
            return @as(f64, @floatFromInt(completed)) / (@as(f64, @floatFromInt(execTime)) / nsPerSec);
        }

        /// Returns total tasks submitted as u64.
        pub fn getSubmitted(self: *const ThreadPoolStats) u64 {
            return Utils.atomicLoadU64(&self.tasksSubmitted);
        }

        /// Returns total tasks completed as u64.
        pub fn getCompleted(self: *const ThreadPoolStats) u64 {
            return Utils.atomicLoadU64(&self.tasksCompleted);
        }

        /// Returns total tasks dropped as u64.
        pub fn getDropped(self: *const ThreadPoolStats) u64 {
            return Utils.atomicLoadU64(&self.tasksDropped);
        }

        /// Returns total tasks cancelled as u64.
        pub fn getCancelled(self: *const ThreadPoolStats) u64 {
            return Utils.atomicLoadU64(&self.tasksCancelled);
        }

        /// Returns total tasks stolen as u64.
        pub fn getStolen(self: *const ThreadPoolStats) u64 {
            return Utils.atomicLoadU64(&self.tasksStolen);
        }

        /// Calculate task completion rate (0.0 - 1.0).
        pub fn completionRate(self: *const ThreadPoolStats) f64 {
            const submitted = Utils.atomicLoadU64(&self.tasksSubmitted);
            const completed = Utils.atomicLoadU64(&self.tasksCompleted);
            return Utils.calculateErrorRate(completed, submitted);
        }

        /// Calculate task drop rate (0.0 - 1.0).
        pub fn dropRate(self: *const ThreadPoolStats) f64 {
            const submitted = Utils.atomicLoadU64(&self.tasksSubmitted);
            const dropped = Utils.atomicLoadU64(&self.tasksDropped);
            return Utils.calculateErrorRate(dropped, submitted);
        }

        /// Checks if any tasks were dropped.
        pub fn hasDropped(self: *const ThreadPoolStats) bool {
            return self.tasksDropped.load(.monotonic) > 0;
        }

        /// Returns current active thread count.
        pub fn getActiveThreads(self: *const ThreadPoolStats) u32 {
            return self.activeThreads.load(.monotonic);
        }

        /// Calculate average wait time in milliseconds.
        pub fn avgWaitTimeMs(self: *const ThreadPoolStats) f64 {
            return @as(f64, @floatFromInt(self.avgWaitTimeNs())) / @as(f64, @floatFromInt(Constants.TimeConstants.nsPerMs));
        }

        /// Calculate average execution time in milliseconds.
        pub fn avgExecTimeMs(self: *const ThreadPoolStats) f64 {
            return @as(f64, @floatFromInt(self.avgExecTimeNs())) / @as(f64, @floatFromInt(Constants.TimeConstants.nsPerMs));
        }
    };

    /// Handle to a submitted task, allowing cancellation before execution.
    pub const TaskHandle = struct {
        id: u64,

        /// Checks if this handle is valid.
        pub fn isValid(self: TaskHandle) bool {
            return self.id != 0;
        }
    };

    /// A work item in the queue.
    pub const WorkItem = struct {
        id: u64 = 0,
        task: Task,
        submittedAt: i64,
        priority: Priority = .normal,
        /// Optional cleanup invoked with the task's callback context when
        /// the item is discarded without executing (clear/cancel). Submit
        /// functions default this to null; owners of heap contexts must
        /// provide it or accept the leak on explicit drops. Hooks run under
        /// the queue lock: they must only free memory and never call back
        /// into the pool.
        onDrop: ?*const fn (?*anyopaque) void = null,

        /// Priority level for task scheduling.
        pub const Priority = enum(u8) {
            /// Lowest priority task.
            low = 0,
            /// Default priority task.
            normal = 1,
            /// High priority task.
            high = 2,
            /// Critical priority task.
            critical = 3,
        };
    };

    /// Task to be executed.
    pub const Task = union(enum) {
        /// Function pointer task
        function: FunctionTask,
        /// Callback with context
        callback: CallbackTask,

        /// Function-only task payload.
        pub const FunctionTask = struct {
            func: *const fn (?std.mem.Allocator) void,
        };

        /// Callback task payload with opaque context pointer.
        pub const CallbackTask = struct {
            func: *const fn (*anyopaque, ?std.mem.Allocator) void,
            context: *anyopaque,
        };

        /// Returns the context carried by callback tasks (null otherwise).
        pub fn dropContext(self: Task) ?*anyopaque {
            return switch (self) {
                .function => null,
                .callback => |c| c.context,
            };
        }

        /// Executes this task variant.
        pub fn execute(self: Task, allocator: ?std.mem.Allocator) void {
            switch (self) {
                .function => |f| f.func(allocator),
                .callback => |c| c.func(c.context, allocator),
            }
        }
    };

    /// Work queue implementation using a Ring Deque for efficient FIFO/LIFO access.
    pub const WorkQueue = struct {
        allocator: std.mem.Allocator,
        io: std.Io = Utils.defaultIo(),
        items: []WorkItem,
        head: usize = 0,
        tail: usize = 0,
        count: usize = 0,
        capacity: usize,
        mutex: std.Io.Mutex = .init,
        condition: std.Io.Condition = .init,

        /// Initializes a queue with fixed `capacity` using default stateless Io.
        pub fn init(allocator: std.mem.Allocator, capacity: usize) !WorkQueue {
            return WorkQueue.initWithIo(allocator, Utils.defaultIo(), capacity);
        }

        /// Initializes a queue with fixed `capacity` and explicit Io handle.
        pub fn initWithIo(allocator: std.mem.Allocator, io_handle: std.Io, capacity: usize) !WorkQueue {
            const items = try allocator.alloc(WorkItem, capacity);
            return .{
                .allocator = allocator,
                .io = io_handle,
                .items = items,
                .capacity = capacity,
            };
        }

        /// Alias for init().
        pub const create = @This().init;

        /// Releases queue storage.
        pub fn deinit(self: *WorkQueue) void {
            self.allocator.free(self.items);
        }

        /// Alias for deinit().
        pub const destroy = @This().deinit;

        /// Pushes an item to the queue.
        ///
        /// Returns false when queue is at capacity.
        pub fn push(self: *WorkQueue, item: WorkItem) bool {
            self.mutex.lockUncancelable(self.io);
            defer self.mutex.unlock(self.io);

            if (self.count >= self.capacity) {
                return false;
            }

            self.items[self.tail] = item;
            self.tail = (self.tail + 1) % self.capacity;
            self.count += 1;
            self.condition.signal(self.io);
            return true;
        }

        /// Pops one item from the queue, if available.
        pub fn pop(self: *WorkQueue) ?WorkItem {
            self.mutex.lockUncancelable(self.io);
            defer self.mutex.unlock(self.io);

            return self.popUnlocked();
        }

        /// Internal pop without locking - caller must hold mutex
        fn popUnlocked(self: *WorkQueue) ?WorkItem {
            if (self.count == 0) return null;

            // Fast path: if strict FIFO is ok or just check head
            // Priority support: Scan for highest priority
            // If head is critical/highest, return it.
            const headItem = self.items[self.head];
            var bestPriority = @backingInt(headItem.priority);

            if (bestPriority >= @backingInt(WorkItem.Priority.critical)) {
                self.head = (self.head + 1) % self.capacity;
                self.count -= 1;
                return headItem;
            }

            // O(N) scan.
            var bestIdx: usize = 0;
            var bestOffset: usize = 0;

            var i: usize = 1;
            while (i < self.count) : (i += 1) {
                const idx = (self.head + i) % self.capacity;
                const item = self.items[idx];
                const p = @backingInt(item.priority);
                if (p > bestPriority) {
                    bestPriority = p;
                    bestIdx = idx;
                    bestOffset = i;
                    if (p >= @backingInt(WorkItem.Priority.critical)) break;
                }
            }

            if (bestOffset == 0) {
                self.head = (self.head + 1) % self.capacity;
                self.count -= 1;
                return headItem;
            } else {
                // Determine item to return
                const bestItem = self.items[bestIdx];
                // Move head to empty slot
                self.items[bestIdx] = headItem;
                self.head = (self.head + 1) % self.capacity;
                self.count -= 1;
                return bestItem;
            }
        }

        /// Waits up to `timeout_ns` for an item, then pops once.
        pub fn popWait(self: *WorkQueue, timeoutNs: u64) ?WorkItem {
            self.mutex.lockUncancelable(self.io);
            defer self.mutex.unlock(self.io);

            // Wait for items if queue is empty
            if (self.count == 0) {
                const clock_dur = std.Io.Clock.Duration{
                    .raw = std.Io.Duration.fromNanoseconds(@as(i96, @intCast(timeoutNs))),
                    .clock = .awake,
                };
                const timeout = std.Io.Timeout{ .duration = clock_dur };
                std.Io.Condition.waitTimeout(&self.condition, self.io, &self.mutex, timeout) catch {};
            }

            // Pop while still holding the lock (no double-locking)
            return self.popUnlocked();
        }

        /// Steals one item from the queue tail.
        pub fn steal(self: *WorkQueue) ?WorkItem {
            self.mutex.lockUncancelable(self.io);
            defer self.mutex.unlock(self.io);

            if (self.count == 0) return null;

            // Steal from the back (tail)
            // Tail points to next empty, so decrement
            const idx = if (self.tail == 0) self.capacity - 1 else self.tail - 1;
            const item = self.items[idx];

            self.tail = idx;
            self.count -= 1;
            return item;
        }

        /// Returns current queue depth.
        pub fn size(self: *WorkQueue) usize {
            self.mutex.lockUncancelable(self.io);
            defer self.mutex.unlock(self.io);
            return self.count;
        }

        /// Returns true when the queue is full.
        pub fn isFull(self: *WorkQueue) bool {
            self.mutex.lockUncancelable(self.io);
            defer self.mutex.unlock(self.io);
            return self.count >= self.capacity;
        }

        /// Removes all queued items, invoking per-item drop hooks so
        /// submitters can reclaim discarded contexts.
        pub fn clear(self: *WorkQueue) void {
            self.mutex.lockUncancelable(self.io);
            defer self.mutex.unlock(self.io);
            var i: usize = 0;
            while (i < self.count) : (i += 1) {
                const idx = (self.head + i) % self.capacity;
                const item = self.items[idx];
                if (item.onDrop) |hook| hook(item.task.dropContext());
            }
            self.head = 0;
            self.tail = 0;
            self.count = 0;
        }

        /// Removes an item by ID without locking.
        pub fn removeByIdUnlocked(self: *WorkQueue, id: u64) bool {
            if (self.count == 0) return false;

            var i: usize = 0;
            var found = false;
            var removeIdx: usize = 0;

            while (i < self.count) : (i += 1) {
                const idx = (self.head + i) % self.capacity;
                if (self.items[idx].id == id) {
                    found = true;
                    removeIdx = idx;
                    break;
                }
            }

            if (!found) return false;

            // Run the drop hook before shifting so a failing hook cannot
            // leave the queue half-compacted (hooks must not throw; they
            // are plain function pointers).
            const doomed = self.items[removeIdx];
            if (doomed.onDrop) |hook| hook(doomed.task.dropContext());

            // Shift elements to fill the gap.
            var curr = removeIdx;
            while (curr != self.head) {
                const prev = if (curr == 0) self.capacity - 1 else curr - 1;
                self.items[curr] = self.items[prev];
                curr = prev;
            }

            self.head = (self.head + 1) % self.capacity;
            self.count -= 1;
            return true;
        }
    };

    /// Worker thread state.
    pub const Worker = struct {
        id: usize,
        thread: ?std.Thread = null,
        localQueue: WorkQueue,
        pool: *ThreadPool,
        running: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
        tasksProcessed: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        name: [64]u8 = undefined,
        nameLen: usize = 0,
    };

    /// Queue depth snapshot split by global and local queues.
    pub const QueueDepth = struct {
        global: usize,
        local: usize,
        total: usize,
    };

    /// Initializes a new ThreadPool with default configuration and stateless Io.
    pub fn init(allocator: std.mem.Allocator) !*ThreadPool {
        return initWithConfig(allocator, .{});
    }

    /// Initializes a ThreadPool with custom configuration.
    pub fn initWithConfig(allocator: std.mem.Allocator, config: ThreadPoolConfig) !*ThreadPool {
        const io_handle = config.io orelse Utils.defaultIo();
        return initWithConfigAndIo(allocator, config, io_handle);
    }

    /// Initializes a ThreadPool with an explicit Io handle and configuration.
    pub fn initWithIo(allocator: std.mem.Allocator, io_handle: std.Io, config: ThreadPoolConfig) !*ThreadPool {
        return initWithConfigAndIo(allocator, config, io_handle);
    }

    /// Initializes a ThreadPool with both configuration and explicit Io handle.
    pub fn initWithConfigAndIo(allocator: std.mem.Allocator, config: ThreadPoolConfig, io_handle: std.Io) !*ThreadPool {
        const self = try allocator.create(ThreadPool);
        errdefer allocator.destroy(self);

        // Determine thread count using Constants.ThreadDefaults
        const recommended = Constants.ThreadDefaults.recommendedThreadCount();
        const numThreads = if (config.threadCount == 0)
            (if (recommended == 0) 1 else recommended)
        else
            config.threadCount;

        // Create workers
        const workers = try allocator.alloc(Worker, numThreads);
        errdefer allocator.free(workers);

        for (workers, 0..) |*worker, i| {
            worker.* = .{
                .id = i,
                .localQueue = try WorkQueue.initWithIo(allocator, io_handle, config.queueSize),
                .pool = self,
            };
        }

        self.* = .{
            .allocator = allocator,
            .io = io_handle,
            .config = config,
            .workers = workers,
            .workQueue = try WorkQueue.initWithIo(allocator, io_handle, config.queueSize * numThreads),
            .stats = .{},
        };

        return self;
    }

    /// Releases all resources.
    pub fn deinit(self: *ThreadPool) void {
        self.shutdown();

        for (self.workers) |*worker| {
            worker.localQueue.deinit();
        }
        self.allocator.free(self.workers);
        self.workQueue.deinit();
        self.allocator.destroy(self);
    }

    /// Starts the thread pool.
    pub fn start(self: *ThreadPool) !void {
        if (self.running.load(.acquire)) return;

        self.running.store(true, .release);
        self.shutdownComplete.store(false, .release);

        for (self.workers) |*worker| {
            worker.running.store(true, .release);
            worker.thread = try std.Thread.spawn(.{}, workerLoop, .{worker});
        }
    }

    /// Shuts down the thread pool gracefully.
    pub fn shutdown(self: *ThreadPool) void {
        if (!self.running.load(.acquire)) return;

        self.running.store(false, .release);

        // Signal all workers
        self.workQueue.condition.broadcast(self.io);
        for (self.workers) |*worker| {
            worker.running.store(false, .release);
            worker.localQueue.condition.broadcast(self.io);
        }

        // Wait for workers to finish
        for (self.workers) |*worker| {
            if (worker.thread) |thread| {
                thread.join();
                worker.thread = null;
            }
        }

        self.shutdownComplete.store(true, .release);
    }

    /// Cancels a task if it hasn't started executing yet.
    /// Returns true if successfully removed from queues.
    pub fn cancel(self: *ThreadPool, handle: TaskHandle) bool {
        if (!handle.isValid()) return false;

        self.workQueue.mutex.lockUncancelable(self.io);
        defer self.workQueue.mutex.unlock(self.io);

        if (self.workQueue.removeByIdUnlocked(handle.id)) {
            _ = self.stats.tasksCancelled.fetchAdd(1, .monotonic);
            return true;
        }

        for (self.workers) |*worker| {
            worker.localQueue.mutex.lockUncancelable(self.io);
            defer worker.localQueue.mutex.unlock(self.io);
            if (worker.localQueue.removeByIdUnlocked(handle.id)) {
                _ = self.stats.tasksCancelled.fetchAdd(1, .monotonic);
                return true;
            }
        }
        return false;
    }

    /// Submits a task for execution.
    pub fn submit(self: *ThreadPool, task: Task, priority: WorkItem.Priority) TaskHandle {
        return self.submitWithDrop(task, priority, null);
    }

    /// Submits a task with a drop hook invoked if the item is discarded
    /// without executing (clear/cancel). See WorkItem.onDrop.
    pub fn submitWithDrop(self: *ThreadPool, task: Task, priority: WorkItem.Priority, onDrop: ?*const fn (?*anyopaque) void) TaskHandle {
        if (!self.running.load(.acquire)) return .{ .id = 0 };

        const id: u64 = @intCast(self.nextTaskId.fetchAdd(1, .monotonic));
        const item = WorkItem{
            .id = id,
            .task = task,
            .submittedAt = Utils.currentMillis(),
            .priority = priority,
            .onDrop = onDrop,
        };

        if (self.workQueue.push(item)) {
            _ = self.stats.tasksSubmitted.fetchAdd(1, .monotonic);
            self.emitTaskSubmitted(priority, self.workQueue.size());
            return .{ .id = id };
        }

        self.emitQueueOverflow(self.workQueue.size(), self.workQueue.capacity);
        _ = self.stats.tasksDropped.fetchAdd(1, .monotonic);
        if (onDrop) |hook| hook(task.dropContext());
        return .{ .id = 0 };
    }

    /// Submits a function for execution.
    pub fn submitFn(self: *ThreadPool, func: *const fn (?std.mem.Allocator) void) bool {
        return self.submit(.{ .function = .{ .func = func } }, .normal).isValid();
    }

    /// Submits a function and returns a handle.
    pub fn submitFnWithHandle(self: *ThreadPool, func: *const fn (?std.mem.Allocator) void) TaskHandle {
        return self.submit(.{ .function = .{ .func = func } }, .normal);
    }

    /// Submits a callback with context for execution.
    pub fn submitCallback(self: *ThreadPool, func: *const fn (*anyopaque, ?std.mem.Allocator) void, context: *anyopaque) bool {
        return self.submit(.{ .callback = .{ .func = func, .context = context } }, .normal).isValid();
    }

    /// Submits a callback with context plus a drop hook for the context.
    ///
    /// The hook fires if the item is discarded without executing
    /// (clear/cancel). Use it whenever `context` owns heap memory.
    pub fn submitCallbackWithDrop(
        self: *ThreadPool,
        func: *const fn (*anyopaque, ?std.mem.Allocator) void,
        context: *anyopaque,
        onDrop: *const fn (?*anyopaque) void,
    ) bool {
        return self.submitWithDrop(.{ .callback = .{ .func = func, .context = context } }, .normal, onDrop).isValid();
    }

    /// Submits a callback and returns a handle.
    pub fn submitCallbackWithHandle(self: *ThreadPool, func: *const fn (*anyopaque, ?std.mem.Allocator) void, context: *anyopaque) TaskHandle {
        return self.submit(.{ .callback = .{ .func = func, .context = context } }, .normal);
    }

    /// Submits a callback with high priority for immediate execution.
    pub fn submitHighPriority(self: *ThreadPool, func: *const fn (*anyopaque, ?std.mem.Allocator) void, context: *anyopaque) bool {
        return self.submit(.{ .callback = .{ .func = func, .context = context } }, .high).isValid();
    }

    /// Submits a callback with high priority and returns a handle.
    pub fn submitHighPriorityWithHandle(self: *ThreadPool, func: *const fn (*anyopaque, ?std.mem.Allocator) void, context: *anyopaque) TaskHandle {
        return self.submit(.{ .callback = .{ .func = func, .context = context } }, .high);
    }

    /// Submits a callback with critical priority (processed first).
    pub fn submitCritical(self: *ThreadPool, func: *const fn (*anyopaque, ?std.mem.Allocator) void, context: *anyopaque) bool {
        return self.submit(.{ .callback = .{ .func = func, .context = context } }, .critical).isValid();
    }

    /// Submits a callback with critical priority and returns a handle.
    pub fn submitCriticalWithHandle(self: *ThreadPool, func: *const fn (*anyopaque, ?std.mem.Allocator) void, context: *anyopaque) TaskHandle {
        return self.submit(.{ .callback = .{ .func = func, .context = context } }, .critical);
    }

    /// Batch submit multiple tasks for higher throughput.
    /// Returns the number of successfully submitted tasks.
    pub fn submitBatch(self: *ThreadPool, tasks: []const Task, priority: WorkItem.Priority) usize {
        if (!self.running.load(.acquire)) return 0;

        var submitted: usize = 0;
        for (tasks) |task| {
            if (self.submit(task, priority).isValid()) {
                submitted += 1;
            } else if (self.running.load(.acquire)) {
                _ = self.stats.tasksDropped.fetchAdd(1, .monotonic);
            }
        }

        return submitted;
    }

    /// Batch submit with bounded retries for transient queue pressure.
    ///
    /// Returns number of tasks eventually submitted.
    pub fn submitBatchWithRetry(self: *ThreadPool, tasks: []const Task, priority: WorkItem.Priority, maxAttempts: u8, retryDelayUs: u32) usize {
        if (!self.running.load(.acquire)) return 0;
        if (tasks.len == 0) return 0;

        const attemptsLimit: u8 = if (maxAttempts == 0) 1 else maxAttempts;
        var submitted: usize = 0;

        for (tasks) |task| {
            var attempts: u8 = 0;
            while (attempts < attemptsLimit) : (attempts += 1) {
                if (self.submit(task, priority).isValid()) {
                    submitted += 1;
                    break;
                }

                if (attempts + 1 < attemptsLimit and retryDelayUs > 0) {
                    Utils.sleepNs(@as(u64, retryDelayUs) * Constants.TimeConstants.nsPerUs);
                }
            }
        }

        return submitted;
    }

    /// Try to submit without blocking and returns a handle.
    pub fn trySubmitWithHandle(self: *ThreadPool, task: Task, priority: WorkItem.Priority) TaskHandle {
        if (!self.running.load(.acquire)) return .{ .id = 0 };

        // Try lock without blocking
        if (!self.workQueue.mutex.tryLock()) {
            return .{ .id = 0 };
        }
        var queueDepth: usize = 0;
        const handle: TaskHandle = blk: {
            defer self.workQueue.mutex.unlock(self.io);

            if (self.workQueue.count >= self.workQueue.capacity) {
                _ = self.stats.tasksDropped.fetchAdd(1, .monotonic);
                break :blk .{ .id = 0 };
            }

            const id: u64 = @intCast(self.nextTaskId.fetchAdd(1, .monotonic));
            const item = WorkItem{
                .id = id,
                .task = task,
                .submittedAt = Utils.currentMillis(),
                .priority = priority,
            };

            self.workQueue.items[self.workQueue.tail] = item;
            self.workQueue.tail = (self.workQueue.tail + 1) % self.workQueue.capacity;
            self.workQueue.count += 1;
            queueDepth = self.workQueue.count;

            _ = self.stats.tasksSubmitted.fetchAdd(1, .monotonic);
            self.workQueue.condition.signal(self.io);
            break :blk .{ .id = id };
        };

        if (handle.id != 0) {
            self.emitTaskSubmitted(priority, queueDepth);
        }
        return handle;
    }

    /// Try to submit without blocking (fast path for non-contended cases).
    pub fn trySubmit(self: *ThreadPool, task: Task, priority: WorkItem.Priority) bool {
        return self.trySubmitWithHandle(task, priority).isValid();
    }

    /// Submit to a specific worker's local queue for better cache locality. Returns a handle.
    pub fn submitToWorkerWithHandle(self: *ThreadPool, workerId: usize, task: Task, priority: WorkItem.Priority) TaskHandle {
        if (!self.running.load(.acquire)) return .{ .id = 0 };
        if (workerId >= self.workers.len) return .{ .id = 0 };

        const id: u64 = @intCast(self.nextTaskId.fetchAdd(1, .monotonic));
        const item = WorkItem{
            .id = id,
            .task = task,
            .submittedAt = Utils.currentMillis(),
            .priority = priority,
        };

        if (self.workers[workerId].localQueue.push(item)) {
            _ = self.stats.tasksSubmitted.fetchAdd(1, .monotonic);
            self.emitTaskSubmitted(priority, self.workers[workerId].localQueue.size());
            return .{ .id = id };
        }

        self.emitQueueOverflow(self.workers[workerId].localQueue.size(), self.workers[workerId].localQueue.capacity);
        _ = self.stats.tasksDropped.fetchAdd(1, .monotonic);
        return .{ .id = 0 };
    }

    /// Submit to a specific worker's local queue for better cache locality.
    pub fn submitToWorker(self: *ThreadPool, workerId: usize, task: Task, priority: WorkItem.Priority) bool {
        return self.submitToWorkerWithHandle(workerId, task, priority).isValid();
    }

    fn workerLoop(worker: *Worker) void {
        const pool = worker.pool;
        const startedAtMs = Utils.currentMillis();

        const nameStr = std.fmt.bufPrint(&worker.name, "{s}-{d}", .{ pool.config.threadNamePrefix, worker.id }) catch pool.config.threadNamePrefix;
        worker.nameLen = nameStr.len;

        _ = pool.stats.activeThreads.fetchAdd(1, .monotonic);
        pool.emitThreadStart(worker.id);
        defer pool.emitThreadStop(
            worker.id,
            worker.tasksProcessed.load(.monotonic),
            @as(u64, @intCast(@max(0, Utils.currentMillis() - startedAtMs))),
        );
        defer _ = pool.stats.activeThreads.fetchSub(1, .monotonic);

        while (worker.running.load(.acquire) or pool.workQueue.size() > 0 or worker.localQueue.size() > 0) {
            // Try local queue first
            var item = worker.localQueue.pop();

            // Try global queue with timeout from Constants
            if (item == null) {
                item = pool.workQueue.popWait(Constants.ThreadDefaults.waitTimeoutNs);
            }

            // Try work stealing
            if (item == null and pool.config.workStealing and pool.workers.len > 1) {
                for (pool.workers) |*other| {
                    if (other.id != worker.id) {
                        if (other.localQueue.steal()) |stolen| {
                            item = stolen;
                            _ = pool.stats.tasksStolen.fetchAdd(1, .monotonic);
                            pool.emitWorkStolen(other.id, worker.id);
                            break;
                        }
                    }
                }
            }

            if (item) |work| {
                const startTime = Utils.currentNanos();
                const waitTimeMs = Utils.currentMillis() - work.submittedAt;
                const waitTimeNs = @as(u64, @intCast(@max(0, waitTimeMs))) * Constants.TimeConstants.nsPerMs;
                pool.emitTaskDequeued(work.priority, waitTimeNs);

                work.task.execute(pool.allocator);

                const execTime = Utils.currentNanos() - startTime;
                _ = pool.stats.totalWaitTimeNs.fetchAdd(@truncate(waitTimeNs), .monotonic);
                _ = pool.stats.totalExecTimeNs.fetchAdd(@truncate(@as(u64, @intCast(@max(0, execTime)))), .monotonic);
                _ = pool.stats.tasksCompleted.fetchAdd(1, .monotonic);
                _ = worker.tasksProcessed.fetchAdd(1, .monotonic);
                pool.emitTaskExecuted(@as(u64, @intCast(@max(0, execTime))), true);
            }
        }
    }

    /// Gets current statistics.
    pub fn getStats(self: *const ThreadPool) ThreadPoolStats {
        return self.stats;
    }

    /// Sets the worker start callback.
    pub fn setThreadStartCallback(self: *ThreadPool, callback: ?*const fn (usize) void) void {
        self.onThreadStart = callback;
    }

    /// Sets the worker stop callback.
    pub fn setThreadStopCallback(self: *ThreadPool, callback: ?*const fn (usize, u64, u64) void) void {
        self.onThreadStop = callback;
    }

    /// Sets the task submitted callback.
    pub fn setTaskSubmittedCallback(self: *ThreadPool, callback: ?*const fn (u8, usize) void) void {
        self.onTaskSubmitted = callback;
    }

    /// Sets the task dequeued callback.
    pub fn setTaskDequeuedCallback(self: *ThreadPool, callback: ?*const fn (u8, u64) void) void {
        self.onTaskDequeued = callback;
    }

    /// Sets the task executed callback.
    pub fn setTaskExecutedCallback(self: *ThreadPool, callback: ?*const fn (u64, bool) void) void {
        self.onTaskExecuted = callback;
    }

    /// Sets the work stolen callback.
    pub fn setWorkStolenCallback(self: *ThreadPool, callback: ?*const fn (usize, usize) void) void {
        self.onWorkStolen = callback;
    }

    /// Sets the queue overflow callback.
    pub fn setQueueOverflowCallback(self: *ThreadPool, callback: ?*const fn (usize, usize) void) void {
        self.onQueueOverflow = callback;
    }

    fn emitThreadStart(self: *ThreadPool, threadId: usize) void {
        if (self.onThreadStart) |cb| cb(threadId);
    }

    fn emitThreadStop(self: *ThreadPool, threadId: usize, tasksProcessed: u64, uptimeMs: u64) void {
        if (self.onThreadStop) |cb| cb(threadId, tasksProcessed, uptimeMs);
    }

    fn emitTaskSubmitted(self: *ThreadPool, priority: WorkItem.Priority, queueDepth: usize) void {
        if (self.onTaskSubmitted) |cb| cb(@backingInt(priority), queueDepth);
    }

    fn emitTaskDequeued(self: *ThreadPool, priority: WorkItem.Priority, waitTimeNs: u64) void {
        if (self.onTaskDequeued) |cb| cb(@backingInt(priority), waitTimeNs / Constants.TimeConstants.nsPerUs);
    }

    fn emitTaskExecuted(self: *ThreadPool, execTimeNs: u64, success: bool) void {
        if (self.onTaskExecuted) |cb| cb(execTimeNs / Constants.TimeConstants.nsPerUs, success);
    }

    fn emitWorkStolen(self: *ThreadPool, victimThread: usize, thiefThread: usize) void {
        if (self.onWorkStolen) |cb| cb(victimThread, thiefThread);
    }

    fn emitQueueOverflow(self: *ThreadPool, queueSize: usize, capacity: usize) void {
        if (self.onQueueOverflow) |cb| cb(queueSize, capacity);
    }

    /// Gets the number of pending tasks.
    pub fn pendingTasks(self: *ThreadPool) usize {
        return self.pendingTasksByQueue().total;
    }

    /// Gets a queue depth snapshot split by global and local queues.
    pub fn pendingTasksByQueue(self: *ThreadPool) QueueDepth {
        const globalCount = self.workQueue.size();
        var localCount: usize = 0;

        for (self.workers) |*worker| {
            localCount += worker.localQueue.size();
        }

        return .{
            .global = globalCount,
            .local = localCount,
            .total = globalCount + localCount,
        };
    }

    /// Gets total queue capacity across global and per-worker queues.
    pub fn queueCapacity(self: *const ThreadPool) usize {
        return self.workQueue.capacity + (self.workers.len * self.config.queueSize);
    }

    /// Gets currently available queue slots.
    pub fn availableQueueCapacity(self: *ThreadPool) usize {
        const capacity = self.queueCapacity();
        const pending = self.pendingTasks();
        return if (capacity > pending) capacity - pending else 0;
    }

    /// Returns true when queue has at least `required_slots` free entries.
    pub fn canAcceptTasks(self: *ThreadPool, requiredSlots: usize) bool {
        if (requiredSlots == 0) return true;
        return self.availableQueueCapacity() >= requiredSlots;
    }

    /// Gets queue utilization ratio in [0.0, 1.0].
    pub fn queueUtilization(self: *ThreadPool) f64 {
        const capacity = self.queueCapacity();
        if (capacity == 0) return 0.0;
        return @as(f64, @floatFromInt(self.pendingTasks())) / @as(f64, @floatFromInt(capacity));
    }

    /// Returns true if queue utilization is above the provided threshold.
    pub fn isSaturated(self: *ThreadPool, threshold: f64) bool {
        const clamped = if (threshold < 0.0)
            0.0
        else if (threshold > 1.0)
            1.0
        else
            threshold;
        return self.queueUtilization() >= clamped;
    }

    /// Gets the number of active threads.
    pub fn activeThreads(self: *const ThreadPool) u32 {
        return self.stats.activeThreads.load(.monotonic);
    }

    fn hasTimedOut(startedAtMs: i64, timeoutMs: u64) bool {
        if (timeoutMs == 0) return true;
        const elapsed = Utils.currentMillis() - startedAtMs;
        return elapsed >= @as(i64, @intCast(timeoutMs));
    }

    /// Waits for all pending tasks to complete.
    pub fn waitAll(self: *ThreadPool) void {
        // Wait until all submitted tasks are completed or cancelled
        while (true) {
            const submitted = self.stats.tasksSubmitted.load(.monotonic);
            const completed = self.stats.tasksCompleted.load(.monotonic);
            const cancelled = self.stats.tasksCancelled.load(.monotonic);

            if (completed + cancelled >= submitted and self.pendingTasks() == 0) break;

            Utils.sleepMs(1);
        }
    }

    /// Waits for all pending tasks with timeout.
    ///
    /// Returns true when all tasks completed before timeout.
    pub fn waitAllTimeout(self: *ThreadPool, timeoutMs: u64) bool {
        const startedAtMs = Utils.currentMillis();

        while (true) {
            const submitted = self.stats.tasksSubmitted.load(.monotonic);
            const completed = self.stats.tasksCompleted.load(.monotonic);
            const cancelled = self.stats.tasksCancelled.load(.monotonic);

            if (completed + cancelled >= submitted and self.pendingTasks() == 0) return true;

            if (hasTimedOut(startedAtMs, timeoutMs)) return false;

            Utils.sleepMs(1);
        }
    }

    /// Waits until pending queue depth is below or equal to threshold.
    ///
    /// Returns true when threshold was reached before timeout.
    pub fn waitUntilQueueBelow(self: *ThreadPool, threshold: usize, timeoutMs: u64) bool {
        const startedAtMs = Utils.currentMillis();

        while (true) {
            if (self.pendingTasks() <= threshold) return true;

            if (hasTimedOut(startedAtMs, timeoutMs)) return false;

            Utils.sleepMs(1);
        }
    }

    /// Clears all pending tasks without executing them.
    pub fn clear(self: *ThreadPool) void {
        self.workQueue.clear();
        for (self.workers) |*worker| {
            worker.localQueue.clear();
        }
    }

    /// Returns true if the pool is running.
    pub fn isRunning(self: *const ThreadPool) bool {
        return self.running.load(.acquire);
    }

    /// Returns the total thread count (including idle).
    pub fn threadCount(self: *const ThreadPool) usize {
        return self.workers.len;
    }

    /// Returns true if the pool has no pending tasks.
    pub fn isEmpty(self: *ThreadPool) bool {
        return self.pendingTasks() == 0;
    }

    /// Returns true if the pool is at capacity (queue full).
    pub fn isFull(self: *ThreadPool) bool {
        return self.workQueue.isFull();
    }

    /// Returns the utilization ratio (0.0 - 1.0).
    pub fn utilization(self: *const ThreadPool) f64 {
        const active = @as(f64, @floatFromInt(self.activeThreads()));
        const total = @as(f64, @floatFromInt(self.workers.len));
        if (total == 0) return 0;
        return active / total;
    }

    /// Resets statistics.
    pub fn resetStats(self: *ThreadPool) void {
        self.stats = .{};
    }
};

/// Re-export ParallelConfig from global config for convenience.
pub const ParallelConfig = Config.ParallelConfig;

/// Parallel sink writer for distributing writes across threads with full configuration support.
/// Uses ParallelConfig for fine-grained control over concurrent write behavior.
pub const ParallelSinkWriter = struct {
    allocator: std.mem.Allocator,
    pool: *ThreadPool,
    config: ParallelConfig,
    sinks: std.ArrayList(SinkHandle),
    buffer: std.ArrayList([]const u8),
    mutex: std.Io.Mutex = .init,
    stats: ParallelStats = .{},

    pub const SinkHandle = struct {
        writeFn: *const fn (data: []const u8) void,
        flushFn: ?*const fn () void = null,
        name: []const u8,
        enabled: bool = true,
    };

    pub const ParallelStats = struct {
        writesSubmitted: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        writesCompleted: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        writesFailed: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        retries: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        bytesWritten: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),

        pub fn successRate(self: *const ParallelStats) f64 {
            const completed = @as(f64, @floatFromInt(Utils.atomicLoadU64(&self.writesCompleted)));
            const total = @as(f64, @floatFromInt(Utils.atomicLoadU64(&self.writesSubmitted)));
            if (total == 0) return 1.0;
            return completed / total;
        }
    };

    /// Initialize with default ParallelConfig.
    pub fn init(allocator: std.mem.Allocator, pool: *ThreadPool) !*ParallelSinkWriter {
        return initWithConfig(allocator, pool, .{});
    }

    /// Initialize with custom ParallelConfig.
    pub fn initWithConfig(allocator: std.mem.Allocator, pool: *ThreadPool, config: ParallelConfig) !*ParallelSinkWriter {
        const self = try allocator.create(ParallelSinkWriter);
        self.* = .{
            .allocator = allocator,
            .pool = pool,
            .config = config,
            .sinks = .empty,
            .buffer = .empty,
        };
        return self;
    }

    pub fn deinit(self: *ParallelSinkWriter) void {
        // Flush any remaining buffered data
        self.flushBuffer();

        // Clean up buffer
        for (self.buffer.items) |item| {
            self.allocator.free(item);
        }
        self.buffer.deinit(self.allocator);
        self.sinks.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    /// Add a sink for parallel writing.
    pub fn addSink(self: *ParallelSinkWriter, handle: SinkHandle) !void {
        self.mutex.lockUncancelable(self.pool.io);
        defer self.mutex.unlock(self.pool.io);
        try self.sinks.append(self.allocator, handle);
    }

    /// Remove a sink by name.
    pub fn removeSink(self: *ParallelSinkWriter, name: []const u8) void {
        self.mutex.lockUncancelable(self.pool.io);
        defer self.mutex.unlock(self.pool.io);

        var i: usize = 0;
        while (i < self.sinks.items.len) {
            if (std.mem.eql(u8, self.sinks.items[i].name, name)) {
                _ = self.sinks.orderedRemove(i);
            } else {
                i += 1;
            }
        }
    }

    /// Enable or disable a sink by name.
    pub fn setSinkEnabled(self: *ParallelSinkWriter, name: []const u8, enabled: bool) void {
        self.mutex.lockUncancelable(self.pool.io);
        defer self.mutex.unlock(self.pool.io);

        for (self.sinks.items) |*sink| {
            if (std.mem.eql(u8, sink.name, name)) {
                sink.enabled = enabled;
            }
        }
    }

    /// Write to all sinks in parallel.
    pub fn writeParallel(self: *ParallelSinkWriter, data: []const u8) void {
        _ = self.stats.writesSubmitted.fetchAdd(1, .monotonic);
        _ = self.stats.bytesWritten.fetchAdd(@intCast(data.len), .monotonic);

        if (self.config.buffered) {
            self.bufferWrite(data);
        } else {
            self.dispatchWrite(data);
        }
    }

    /// Buffer a write for later dispatch.
    fn bufferWrite(self: *ParallelSinkWriter, data: []const u8) void {
        self.mutex.lockUncancelable(self.pool.io);
        defer self.mutex.unlock(self.pool.io);

        if (self.allocator.dupe(u8, data)) |dataCopy| {
            self.buffer.append(self.allocator, dataCopy) catch {
                self.allocator.free(dataCopy);
                return;
            };

            // Flush if buffer is full
            if (self.buffer.items.len >= self.config.bufferSize) {
                self.flushBufferUnlocked();
            }
        } else |_| {}
    }

    /// Flush the buffer immediately.
    pub fn flushBuffer(self: *ParallelSinkWriter) void {
        self.mutex.lockUncancelable(self.pool.io);
        defer self.mutex.unlock(self.pool.io);
        self.flushBufferUnlocked();
    }

    fn flushBufferUnlocked(self: *ParallelSinkWriter) void {
        for (self.buffer.items) |item| {
            self.dispatchWriteUnlocked(item);
            self.allocator.free(item);
        }
        self.buffer.clearRetainingCapacity();
    }

    /// Dispatch write to all sinks.
    fn dispatchWrite(self: *ParallelSinkWriter, data: []const u8) void {
        self.mutex.lockUncancelable(self.pool.io);
        defer self.mutex.unlock(self.pool.io);
        self.dispatchWriteUnlocked(data);
    }

    fn dispatchWriteUnlocked(self: *ParallelSinkWriter, data: []const u8) void {
        const WriteContext = struct {
            allocator: std.mem.Allocator,
            writeFn: *const fn (data: []const u8) void,
            data: []const u8,
            stats: *ParallelStats,
            maxRetries: u3,
            retryOnFailure: bool,
        };

        const taskFns = struct {
            fn run(ctxPtr: *anyopaque, _: ?std.mem.Allocator) void {
                const ctx = @as(*WriteContext, @ptrCast(@alignCast(ctxPtr)));
                defer {
                    ctx.allocator.free(ctx.data);
                    ctx.allocator.destroy(ctx);
                }
                var success = false;
                var attempts: u32 = 0;
                const maxAttempts: u32 = if (ctx.retryOnFailure) @as(u32, ctx.maxRetries) + 1 else 1;

                while (attempts < maxAttempts and !success) {
                    // Execute the write
                    ctx.writeFn(ctx.data);
                    success = true; // Assume success if no error
                    attempts += 1;

                    if (!success and ctx.retryOnFailure) {
                        _ = ctx.stats.retries.fetchAdd(1, .monotonic);
                    }
                }

                if (success) {
                    _ = ctx.stats.writesCompleted.fetchAdd(1, .monotonic);
                } else {
                    _ = ctx.stats.writesFailed.fetchAdd(1, .monotonic);
                }
            }

            fn drop(ctxPtr: ?*anyopaque) void {
                const ctx = @as(*WriteContext, @ptrCast(@alignCast(ctxPtr.?)));
                ctx.allocator.free(ctx.data);
                ctx.allocator.destroy(ctx);
            }
        };
        const taskFn = taskFns.run;

        // Track concurrent writes
        var activeWrites: usize = 0;

        // Submit write task to each enabled sink
        for (self.sinks.items) |sink| {
            if (!sink.enabled) continue;

            // Respect max_concurrent limit
            if (activeWrites >= self.config.maxConcurrent) {
                // Execute synchronously if at limit
                sink.writeFn(data);
                _ = self.stats.writesCompleted.fetchAdd(1, .monotonic);
                continue;
            }

            // Create context for this task
            if (self.allocator.create(WriteContext)) |ctx| {
                if (self.allocator.dupe(u8, data)) |dataCopy| {
                    ctx.* = .{
                        .allocator = self.allocator,
                        .writeFn = sink.writeFn,
                        .data = dataCopy,
                        .stats = &self.stats,
                        .maxRetries = self.config.maxRetries,
                        .retryOnFailure = self.config.retryOnFailure,
                    };

                    if (!self.pool.submitCallbackWithDrop(taskFn, ctx, taskFns.drop)) {
                        // Fallback: execute synchronously if pool is full
                        sink.writeFn(data);
                        _ = self.stats.writesCompleted.fetchAdd(1, .monotonic);
                        self.allocator.free(dataCopy);
                        self.allocator.destroy(ctx);
                    } else {
                        activeWrites += 1;
                    }
                } else |_| {
                    sink.writeFn(data);
                    _ = self.stats.writesCompleted.fetchAdd(1, .monotonic);
                    self.allocator.destroy(ctx);
                }
            } else |_| {
                sink.writeFn(data);
                _ = self.stats.writesCompleted.fetchAdd(1, .monotonic);
            }
        }
    }

    /// Flush all sinks.
    pub fn flushAll(self: *ParallelSinkWriter) void {
        self.flushBuffer();

        self.mutex.lockUncancelable(self.pool.io);
        defer self.mutex.unlock(self.pool.io);

        for (self.sinks.items) |sink| {
            if (sink.flushFn) |flushFunc| {
                flushFunc();
            }
        }
    }

    /// Get current statistics.
    pub fn getStats(self: *const ParallelSinkWriter) ParallelStats {
        return self.stats;
    }

    /// Get sink count.
    pub fn sinkCount(self: *const ParallelSinkWriter) usize {
        return self.sinks.items.len;
    }

    /// Check if any sinks are enabled.
    pub fn hasEnabledSinks(self: *ParallelSinkWriter) bool {
        self.mutex.lockUncancelable(self.pool.io);
        defer self.mutex.unlock(self.pool.io);

        for (self.sinks.items) |sink| {
            if (sink.enabled) return true;
        }
        return false;
    }

    // Aliases
};

/// Preset thread pool configurations.
pub const ThreadPoolPresets = struct {
    /// Single-threaded pool (for sequential processing).
    pub fn singleThread() ThreadPool.ThreadPoolConfig {
        return .{
            .threadCount = 1,
            .workStealing = false,
        };
    }

    /// CPU-bound workload (one thread per core).
    pub fn cpuBound() ThreadPool.ThreadPoolConfig {
        return .{
            .threadCount = Constants.ThreadDefaults.threadCount, // Auto-detect
            .workStealing = true,
        };
    }

    /// I/O-bound workload (more threads than cores).
    pub fn ioBound() ThreadPool.ThreadPoolConfig {
        const cpuCount = Constants.ThreadDefaults.recommendedThreadCount();
        return .{
            .threadCount = cpuCount * 2,
            .workStealing = true,
            .queueSize = Constants.ThreadDefaults.queueSize * 2,
        };
    }

    /// High-throughput logging.
    pub fn highThroughput() ThreadPool.ThreadPoolConfig {
        const cpuCount = Constants.ThreadDefaults.recommendedThreadCount();
        return .{
            .threadCount = cpuCount,
            .queueSize = Constants.ThreadDefaults.queueSize * 4,
            .workStealing = true,
        };
    }

    /// Low-latency logging.
    pub fn lowLatency() ThreadPool.ThreadPoolConfig {
        return .{
            .threadCount = Constants.ThreadDefaults.lowLatencyThreadCount,
            .queueSize = Constants.ThreadDefaults.queueSizeLow * 2,
            .workStealing = false,
        };
    }
};

test "thread pool basic" {
    const allocator = std.testing.allocator;

    const pool = try ThreadPool.initWithConfig(allocator, .{
        .threadCount = 2,
        .queueSize = 16,
    });
    defer pool.deinit();

    try pool.start();

    var counter: std.atomic.Value(u32) = std.atomic.Value(u32).init(0);

    const TestTask = struct {
        fn increment(ctx: *anyopaque, _: ?std.mem.Allocator) void {
            const c: *std.atomic.Value(u32) = @ptrCast(@alignCast(ctx));
            _ = c.fetchAdd(1, .monotonic);
        }
    };

    // Submit tasks
    for (0..10) |_| {
        _ = pool.submitCallback(TestTask.increment, @ptrCast(&counter));
    }

    // Wait for completion
    pool.waitAll();

    try std.testing.expectEqual(@as(u32, 10), counter.load(.monotonic));
}

test "work queue" {
    const allocator = std.testing.allocator;

    var queue = try ThreadPool.WorkQueue.init(allocator, 10);
    defer queue.deinit();

    const item = ThreadPool.WorkItem{
        .task = .{ .function = .{ .func = undefined } },
        .submittedAt = 0,
        .priority = .high,
    };

    try std.testing.expect(queue.push(item));
    try std.testing.expectEqual(@as(usize, 1), queue.size());

    const popped = queue.pop();
    try std.testing.expect(popped != null);
    try std.testing.expectEqual(@as(usize, 0), queue.size());
}

test "thread pool stats" {
    var stats = ThreadPool.ThreadPoolStats{};

    _ = stats.tasksCompleted.fetchAdd(10, .monotonic);
    _ = stats.totalExecTimeNs.fetchAdd(100_000_000, .monotonic); // 0.1 second (fits in u32)

    try std.testing.expect(stats.throughput() > 99 and stats.throughput() < 101);
}

test "thread pool batch submit" {
    const allocator = std.testing.allocator;

    const pool = try ThreadPool.initWithConfig(allocator, .{
        .threadCount = 2,
        .queueSize = 32,
    });
    defer pool.deinit();

    try pool.start();

    const TestTask = struct {
        fn increment(_: ?std.mem.Allocator) void {
            // Empty task for testing
        }
    };

    // Create batch of tasks
    var tasks: [5]ThreadPool.Task = undefined;
    for (&tasks) |*task| {
        task.* = .{ .function = .{ .func = TestTask.increment } };
    }

    // Batch submit
    const submitted = pool.submitBatch(&tasks, .normal);
    try std.testing.expectEqual(@as(usize, 5), submitted);

    // Wait for completion
    pool.waitAll();

    const stats = pool.getStats();
    try std.testing.expectEqual(@as(Constants.AtomicUnsigned, 5), stats.tasksSubmitted.load(.monotonic));
}

test "thread pool priority submission" {
    const allocator = std.testing.allocator;

    const pool = try ThreadPool.initWithConfig(allocator, .{
        .threadCount = 1,
        .queueSize = 16,
    });
    defer pool.deinit();

    try pool.start();

    var counter: std.atomic.Value(u32) = std.atomic.Value(u32).init(0);

    const TestTask = struct {
        fn increment(ctx: *anyopaque, _: ?std.mem.Allocator) void {
            const c: *std.atomic.Value(u32) = @ptrCast(@alignCast(ctx));
            _ = c.fetchAdd(1, .monotonic);
        }
    };

    // Submit with different priorities
    _ = pool.submitCallback(TestTask.increment, @ptrCast(&counter));
    _ = pool.submitHighPriority(TestTask.increment, @ptrCast(&counter));
    _ = pool.submitCritical(TestTask.increment, @ptrCast(&counter));

    pool.waitAll();

    try std.testing.expectEqual(@as(u32, 3), counter.load(.monotonic));
}

test "thread pool presets" {
    // Test preset configurations compile and have sensible values
    const single = ThreadPoolPresets.singleThread();
    try std.testing.expectEqual(@as(usize, 1), single.threadCount);
    try std.testing.expect(!single.workStealing);

    const cpu = ThreadPoolPresets.cpuBound();
    try std.testing.expectEqual(@as(usize, 0), cpu.threadCount); // auto-detect
    try std.testing.expect(cpu.workStealing);

    const io = ThreadPoolPresets.ioBound();
    try std.testing.expect(io.threadCount > 0);
    try std.testing.expect(io.workStealing);

    const ht = ThreadPoolPresets.highThroughput();
    try std.testing.expect(ht.queueSize >= Constants.ThreadDefaults.queueSize * 4);

    const ll = ThreadPoolPresets.lowLatency();
    try std.testing.expectEqual(@as(usize, Constants.ThreadDefaults.lowLatencyThreadCount), ll.threadCount);
}

test "thread pool try submit" {
    const allocator = std.testing.allocator;

    const pool = try ThreadPool.initWithConfig(allocator, .{
        .threadCount = 1,
        .queueSize = 4,
    });
    defer pool.deinit();

    try pool.start();

    const TestTask = struct {
        fn noop(_: ?std.mem.Allocator) void {}
    };

    // Try submit should work when not contended
    const task = ThreadPool.Task{ .function = .{ .func = TestTask.noop } };
    const success = pool.trySubmit(task, .normal);

    // May or may not succeed depending on timing, but should not crash
    _ = success;

    pool.waitAll();
}

test "thread pool worker affinity" {
    const allocator = std.testing.allocator;

    const pool = try ThreadPool.initWithConfig(allocator, .{
        .threadCount = 2,
        .queueSize = 8,
    });
    defer pool.deinit();

    try pool.start();

    var counter: std.atomic.Value(u32) = std.atomic.Value(u32).init(0);

    const TestTask = struct {
        fn increment(ctx: *anyopaque, _: ?std.mem.Allocator) void {
            const c: *std.atomic.Value(u32) = @ptrCast(@alignCast(ctx));
            _ = c.fetchAdd(1, .monotonic);
        }
    };

    // Submit to specific worker
    _ = pool.submitToWorker(0, .{ .callback = .{ .func = TestTask.increment, .context = @ptrCast(&counter) } }, .normal);
    _ = pool.submitToWorker(1, .{ .callback = .{ .func = TestTask.increment, .context = @ptrCast(&counter) } }, .normal);

    pool.waitAll();

    try std.testing.expectEqual(@as(u32, 2), counter.load(.monotonic));
}

test "thread pool priority ordering" {
    const allocator = std.testing.allocator;

    // Use single thread to make ordering deterministic
    const pool = try ThreadPool.initWithConfig(allocator, .{
        .threadCount = 1,
        .queueSize = 32,
    });
    defer pool.deinit();

    // Start the pool first so we can submit tasks
    try pool.start();

    var order: std.ArrayList(u8) = std.ArrayList(u8).empty;
    defer order.deinit(allocator);
    var mutex: std.Io.Mutex = .init;

    const Params = struct { o: *std.ArrayList(u8), m: *std.Io.Mutex, val: u8, a: std.mem.Allocator, io: std.Io };
    const OrderTask = struct {
        fn run(ctx: *anyopaque, _: ?std.mem.Allocator) void {
            const params: *Params = @ptrCast(@alignCast(ctx));
            params.m.lockUncancelable(params.io);
            params.o.append(params.a, params.val) catch {};
            params.m.unlock(params.io);
        }
    };

    var p1: Params = .{ .o = &order, .m = &mutex, .val = 1, .a = allocator, .io = pool.io }; // Normal
    var p2: Params = .{ .o = &order, .m = &mutex, .val = 2, .a = allocator, .io = pool.io }; // High
    var p3: Params = .{ .o = &order, .m = &mutex, .val = 3, .a = allocator, .io = pool.io }; // Critical

    // Use a primary task to block the single worker thread
    var blockMutex: std.Io.Mutex = .init;
    blockMutex.lockUncancelable(pool.io); // Worker will block on this

    const BlockTask = struct {
        fn run(ctx: *anyopaque, _: ?std.mem.Allocator) void {
            const m: *std.Io.Mutex = @ptrCast(@alignCast(ctx));
            const io = Utils.defaultIo();
            m.lockUncancelable(io); // Wait here
            m.unlock(io);
        }
    };

    _ = pool.submit(.{ .callback = .{ .func = BlockTask.run, .context = &blockMutex } }, .critical);

    // Give it a moment to pick up the block task
    Utils.sleepMs(10);

    // Queue them up - they should be ordered in the queue by priority
    _ = pool.submit(.{ .callback = .{ .func = OrderTask.run, .context = &p1 } }, .normal);
    _ = pool.submit(.{ .callback = .{ .func = OrderTask.run, .context = &p2 } }, .high);
    _ = pool.submit(.{ .callback = .{ .func = OrderTask.run, .context = &p3 } }, .critical);

    // Release the worker
    blockMutex.unlock(pool.io);
    pool.waitAll();

    // Order should be 3, 2, 1
    try std.testing.expectEqual(@as(usize, 3), order.items.len);
    try std.testing.expectEqual(@as(u8, 3), order.items[0]);
    try std.testing.expectEqual(@as(u8, 2), order.items[1]);
    try std.testing.expectEqual(@as(u8, 1), order.items[2]);
}

test "thread pool capacity helpers" {
    const allocator = std.testing.allocator;

    const pool = try ThreadPool.initWithConfig(allocator, .{
        .threadCount = 2,
        .queueSize = 8,
    });
    defer pool.deinit();

    try std.testing.expectEqual(@as(usize, 32), pool.queueCapacity());
    try std.testing.expectEqual(@as(usize, 32), pool.availableQueueCapacity());
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), pool.queueUtilization(), 0.0001);
    try std.testing.expect(!pool.isSaturated(0.1));
}

test "thread pool wait all timeout" {
    const allocator = std.testing.allocator;

    const pool = try ThreadPool.initWithConfig(allocator, .{
        .threadCount = 1,
        .queueSize = 16,
    });
    defer pool.deinit();

    try pool.start();

    var gate = std.Io.Mutex.init;
    gate.lockUncancelable(pool.io);

    const BlockTask = struct {
        fn run(ctx: *anyopaque, _: ?std.mem.Allocator) void {
            const m: *std.Io.Mutex = @ptrCast(@alignCast(ctx));
            const io = Utils.defaultIo();
            m.lockUncancelable(io);
            m.unlock(io);
        }
    };

    _ = pool.submit(.{ .callback = .{ .func = BlockTask.run, .context = &gate } }, .critical);

    Utils.sleepMs(5);
    try std.testing.expect(!pool.waitAllTimeout(10));

    gate.unlock(pool.io);
    try std.testing.expect(pool.waitAllTimeout(2_000));
}

test "thread pool queue breakdown and capacity helpers" {
    const allocator = std.testing.allocator;

    const pool = try ThreadPool.initWithConfig(allocator, .{
        .threadCount = 2,
        .queueSize = 8,
    });
    defer pool.deinit();

    try pool.start();

    const breakdown = pool.pendingTasksByQueue();
    try std.testing.expectEqual(@as(usize, 0), breakdown.global);
    try std.testing.expectEqual(@as(usize, 0), breakdown.local);
    try std.testing.expectEqual(@as(usize, 0), breakdown.total);

    try std.testing.expect(pool.canAcceptTasks(1));
    try std.testing.expect(pool.canAcceptTasks(pool.queueCapacity()));
    try std.testing.expect(!pool.canAcceptTasks(pool.queueCapacity() + 1));
}

test "thread pool batch retry and queue threshold wait" {
    const allocator = std.testing.allocator;

    const pool = try ThreadPool.initWithConfig(allocator, .{
        .threadCount = 2,
        .queueSize = 8,
    });
    defer pool.deinit();

    try pool.start();

    const NoopTask = struct {
        fn run(_: ?std.mem.Allocator) void {}
    };

    var tasks: [24]ThreadPool.Task = undefined;
    for (&tasks) |*task| {
        task.* = .{ .function = .{ .func = NoopTask.run } };
    }

    const submitted = pool.submitBatchWithRetry(&tasks, .normal, 64, 100);
    try std.testing.expect(submitted > 0);
    try std.testing.expect(submitted <= tasks.len);
    try std.testing.expect(pool.waitUntilQueueBelow(0, 5_000));
    try std.testing.expect(pool.waitAllTimeout(5_000));

    const stats = pool.getStats();
    try std.testing.expectEqual(@as(u64, @intCast(submitted)), stats.getSubmitted());
    try std.testing.expectEqual(@as(u64, @intCast(submitted)), stats.getCompleted());
}

test "thread pool heavy concurrency stress loop" {
    const allocator = std.testing.allocator;

    const pool = try ThreadPool.initWithConfig(allocator, .{
        .threadCount = 0,
        .queueSize = 256,
        .workStealing = true,
    });
    defer pool.deinit();

    try pool.start();

    const producerCount = 4;
    const tasksPerProducer = 3_000;
    const totalTasks = producerCount * tasksPerProducer;
    const totalTasksU64: u64 = @intCast(totalTasks);

    var executed = std.atomic.Value(Constants.AtomicUnsigned).init(0);

    const TaskCtx = struct {
        counter: *std.atomic.Value(Constants.AtomicUnsigned),
        spinIterations: u32,
    };

    var taskCtx = TaskCtx{
        .counter = &executed,
        .spinIterations = 64,
    };

    const StressTask = struct {
        fn run(rawCtx: *anyopaque, _: ?std.mem.Allocator) void {
            const ctx: *TaskCtx = @ptrCast(@alignCast(rawCtx));

            var i: u32 = 0;
            while (i < ctx.spinIterations) : (i += 1) {
                std.atomic.spinLoopHint();
            }

            _ = ctx.counter.fetchAdd(1, .monotonic);
        }
    };

    const ProducerCtx = struct {
        pool: *ThreadPool,
        taskCtx: *TaskCtx,
        iterations: usize,
    };

    const Producer = struct {
        fn run(ctx: *ProducerCtx) void {
            var submitted: usize = 0;
            while (submitted < ctx.iterations) {
                const accepted = ctx.pool.submit(.{
                    .callback = .{
                        .func = StressTask.run,
                        .context = ctx.taskCtx,
                    },
                }, .normal);

                if (accepted.isValid()) {
                    submitted += 1;
                } else {
                    Utils.sleepNs(50 * Constants.TimeConstants.nsPerUs);
                }
            }
        }
    };

    var producerContexts: [producerCount]ProducerCtx = undefined;
    var producerThreads: [producerCount]std.Thread = undefined;

    for (0..producerCount) |i| {
        producerContexts[i] = .{
            .pool = pool,
            .taskCtx = &taskCtx,
            .iterations = tasksPerProducer,
        };
        producerThreads[i] = try std.Thread.spawn(.{}, Producer.run, .{&producerContexts[i]});
    }

    for (producerThreads) |thread| {
        thread.join();
    }

    try std.testing.expect(pool.waitAllTimeout(20_000));

    const executedCount = Utils.atomicLoadU64(&executed);
    try std.testing.expectEqual(totalTasksU64, executedCount);

    const stats = pool.getStats();
    try std.testing.expectEqual(totalTasksU64, stats.getSubmitted());
    try std.testing.expectEqual(totalTasksU64, stats.getCompleted());

    try std.testing.expect(pool.queueUtilization() <= 1.0);
    try std.testing.expect(pool.availableQueueCapacity() <= pool.queueCapacity());
}
