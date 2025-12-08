# Callbacks

Callbacks allow you to hook into the logging process and execute custom code whenever a log event occurs. This powerful feature enables integration with external monitoring systems, alerting mechanisms, metrics collection, and custom workflows throughout the logging pipeline.

## Overview

Logly provides comprehensive callback support across all major components:

- **Logger Callbacks**: Record logging, filtering, sink errors
- **Sink Callbacks**: Write operations, flushes, rotations, errors
- **Async Callbacks**: Buffer overflows, worker lifecycle, batch processing
- **Filter Callbacks**: Record allow/deny decisions
- **Sampler Callbacks**: Sample accept/reject, rate limiting, adaptive adjustments
- **Redactor Callbacks**: Sensitive data redaction events
- **Formatter Callbacks**: Format operations and errors
- **Rotation Callbacks**: File rotation lifecycle events
- **Compression Callbacks**: Compression operations and errors
- **Metrics Callbacks**: Metrics snapshots, threshold violations
- **Thread Pool Callbacks**: Task lifecycle, work stealing
- **Scheduler Callbacks**: Scheduled task execution

## Logger Callbacks

### Record Logged Callback

Called when a record is successfully logged:

```zig
fn onRecordLogged(level: logly.Level, message: []const u8, record: *const logly.Record) void {
    // Track metrics or send to external system
    metrics.increment("logs.total", 1);
    if (level == .err) {
        alerting.notifyError(message);
    }
}

logger.setLoggedCallback(&onRecordLogged);
```

### Record Filtered Callback

Called when a record is filtered/dropped:

```zig
fn onRecordFiltered(reason: []const u8, record: *const logly.Record) void {
    std.debug.print("Record filtered: {s}\n", .{reason});
}

logger.setFilteredCallback(&onRecordFiltered);
```

### Sink Error Callback

Called when a sink encounters an error:

```zig
fn onSinkError(sink_name: []const u8, error_msg: []const u8) void {
    std.debug.print("Sink '{s}' error: {s}\n", .{sink_name, error_msg});
}

logger.setSinkErrorCallback(&onSinkError);
```

### Logger Lifecycle Callbacks

```zig
fn onLoggerInitialized(stats: *const logly.Logger.LoggerStats) void {
    std.debug.print("Logger initialized with {d} active sinks\n", 
        .{stats.active_sinks.load(.monotonic)});
}

fn onLoggerDestroyed(stats: *const logly.Logger.LoggerStats) void {
    const total = stats.total_records_logged.load(.monotonic);
    std.debug.print("Logger destroyed. Total records: {d}\n", .{total});
}

logger.setInitializedCallback(&onLoggerInitialized);
logger.setDestroyedCallback(&onLoggerDestroyed);
```

## Sink Callbacks

### Write Callback

Called after each successful write:

```zig
fn onSinkWrite(record_count: u64, bytes_written: u64) void {
    metrics.track("sink.bytes_written", bytes_written);
}

sink.setWriteCallback(&onSinkWrite);
```

### Flush Callback

Called after a flush operation:

```zig
fn onFlush(bytes_flushed: u64, duration_ns: u64) void {
    const duration_ms = duration_ns / 1_000_000;
    std.debug.print("Flushed {d} bytes in {d}ms\n", .{bytes_flushed, duration_ms});
}

sink.setFlushCallback(&onFlush);
```

### Rotation Callback

Called when file rotation occurs:

```zig
fn onRotation(old_file: []const u8, new_file: []const u8) void {
    std.debug.print("Rotated: {s} -> {s}\n", .{old_file, new_file});
}

sink.setRotationCallback(&onRotation);
```

## Async Logging Callbacks

### Buffer Overflow Callback

```zig
fn onOverflow(dropped_count: u64) void {
    alerting.critical("Async buffer overflow! Dropped {d} records", .{dropped_count});
}

async_logger.overflow_callback = &onOverflow;
```

### Batch Processed Callback

```zig
fn onBatchProcessed(batch_size: usize, processing_time_us: u64) void {
    metrics.histogram("async.batch_size", batch_size);
    metrics.histogram("async.processing_time_us", processing_time_us);
}

async_logger.on_batch_processed = &onBatchProcessed;
```

### Latency Threshold Callback

```zig
fn onLatencyExceeded(actual_latency_us: u64, threshold_us: u64) void {
    std.debug.print("⚠️  Latency {d}μs exceeds threshold {d}μs\n", 
        .{actual_latency_us, threshold_us});
}

async_logger.on_latency_threshold_exceeded = &onLatencyExceeded;
```

## Filter Callbacks

### Record Allowed/Denied

```zig
fn onRecordAllowed(record: *const logly.Record, rules_checked: u32) void {
    std.debug.print("Record passed {d} filter rules\n", .{rules_checked});
}

fn onRecordDenied(record: *const logly.Record, blocking_rule: u32) void {
    std.debug.print("Record blocked by rule #{d}\n", .{blocking_rule});
}

filter.setAllowedCallback(&onRecordAllowed);
filter.setDeniedCallback(&onRecordDenied);
```

## Sampler Callbacks

### Sample Accept/Reject

```zig
fn onSampleAccept(sample_rate: f64) void {
    metrics.increment("sampler.accepted", 1);
}

fn onSampleReject(sample_rate: f64, reason: logly.Sampler.SampleRejectReason) void {
    metrics.increment("sampler.rejected", 1);
}

sampler.setAcceptCallback(&onSampleAccept);
sampler.setRejectCallback(&onSampleReject);
```

### Rate Limit Exceeded

```zig
fn onRateExceeded(window_count: u32, max_allowed: u32) void {
    std.debug.print("Rate limit hit: {d}/{d}\n", .{window_count, max_allowed});
}

sampler.setRateLimitCallback(&onRateExceeded);
```

### Adaptive Rate Adjustment

```zig
fn onRateAdjustment(old_rate: f64, new_rate: f64, reason: []const u8) void {
    std.debug.print("Sample rate adjusted: {d:.2} -> {d:.2} ({s})\n", 
        .{old_rate, new_rate, reason});
}

sampler.setAdjustmentCallback(&onRateAdjustment);
```

## Redactor Callbacks

### Redaction Applied

```zig
fn onRedactionApplied(original_len: u64, redacted_len: u64, redaction_type: u32) void {
    metrics.increment("redaction.applied", 1);
}

redactor.setRedactionAppliedCallback(&onRedactionApplied);
```

### Pattern Matched

```zig
fn onPatternMatched(pattern_name: []const u8, matched_value: []const u8) void {
    audit.log("Sensitive pattern '{s}' detected", .{pattern_name});
}

redactor.setPatternMatchedCallback(&onPatternMatched);
```

## Rotation Callbacks

### Rotation Lifecycle

```zig
fn onRotationStart(old_file: []const u8) void {
    std.debug.print("Starting rotation: {s}\n", .{old_file});
}

fn onRotationComplete(old_file: []const u8, new_file: []const u8, duration_ns: u64) void {
    const duration_ms = duration_ns / 1_000_000;
    std.debug.print("Rotation complete in {d}ms: {s} -> {s}\n", 
        .{duration_ms, old_file, new_file});
}

rotation.on_rotation_start = &onRotationStart;
rotation.on_rotation_complete = &onRotationComplete;
```

### Archive and Cleanup

```zig
fn onFileArchived(archived_file: []const u8, archive_path: []const u8) void {
    std.debug.print("Archived: {s} -> {s}\n", .{archived_file, archive_path});
}

fn onRetentionCleanup(deleted_count: u32, freed_bytes: u64) void {
    std.debug.print("Cleanup: {d} files deleted, {d} bytes freed\n", 
        .{deleted_count, freed_bytes});
}

rotation.on_file_archived = &onFileArchived;
rotation.on_retention_cleanup = &onRetentionCleanup;
```

## Compression Callbacks

```zig
fn onCompressionStart(file_path: []const u8, original_size: u64) void {
    std.debug.print("Compressing: {s} ({d} bytes)\n", .{file_path, original_size});
}

fn onCompressionComplete(file_path: []const u8, ratio: f64, duration_ns: u64) void {
    std.debug.print("Compressed: {s}, ratio: {d:.2}, time: {d}ms\n", 
        .{file_path, ratio, duration_ns / 1_000_000});
}

compression.on_compression_start = &onCompressionStart;
compression.on_compression_complete = &onCompressionComplete;
```

## Metrics Callbacks

```zig
fn onMetricsSnapshot(snapshot: *const logly.Metrics.Snapshot) void {
    const drop_rate = snapshot.getDropRate();
    if (drop_rate > 0.05) { // 5% drop rate
        alerting.warn("High drop rate: {d:.2}%", .{drop_rate * 100});
    }
}

fn onThresholdExceeded(metric_type: logly.Metrics.MetricType, value: u64, threshold: u64) void {
    std.debug.print("Threshold exceeded: {s} = {d} (limit: {d})\n", 
        .{@tagName(metric_type), value, threshold});
}

metrics.on_metrics_snapshot = &onMetricsSnapshot;
metrics.on_threshold_exceeded = &onThresholdExceeded;
```

## Thread Pool Callbacks

```zig
fn onTaskExecuted(task_id: u64, execution_time_ns: u64) void {
    metrics.histogram("threadpool.execution_time_us", execution_time_ns / 1000);
}

fn onWorkStolen(from_queue: u32, to_queue: u32, tasks_stolen: u32) void {
    metrics.increment("threadpool.work_stealing", tasks_stolen);
}

thread_pool.on_task_executed = &onTaskExecuted;
thread_pool.on_work_stolen = &onWorkStolen;
```

## Scheduler Callbacks

```zig
fn onTaskStarted(task_name: []const u8, run_count: u64) void {
    std.debug.print("Task '{s}' started (run #{d})\n", .{task_name, run_count});
}

fn onTaskCompleted(task_name: []const u8, duration_ms: u64) void {
    metrics.histogram("scheduler.task_duration_ms", duration_ms);
}

fn onTaskError(task_name: []const u8, error_msg: []const u8) void {
    alerting.error("Scheduled task '{s}' failed: {s}", .{task_name, error_msg});
}

scheduler.setTaskStartedCallback(&onTaskStarted);
scheduler.setTaskCompletedCallback(&onTaskCompleted);
scheduler.setTaskErrorCallback(&onTaskError);
```

## Best Practices

### 1. Keep Callbacks Fast

Callbacks are invoked in the hot path. Keep them minimal:

```zig
// ✅ Good: Fast counter increment
fn fastCallback(level: logly.Level, msg: []const u8, record: *const logly.Record) void {
    stats.increment();
}

// ❌ Bad: Expensive I/O in callback
fn slowCallback(level: logly.Level, msg: []const u8, record: *const logly.Record) void {
    sendHttpRequest(msg); // Don't do this!
}
```

### 2. Use Thread-Safe Operations

Callbacks may be invoked from multiple threads:

```zig
fn threadSafeCallback(count: u64) void {
    counter.fetchAdd(1, .monotonic); // ✅ Atomic operation
    // non_atomic_counter += 1;      // ❌ Race condition!
}
```

### 3. Handle Errors Gracefully

Don't let callback errors crash the logger:

```zig
fn safeCallback(msg: []const u8) void {
    sendAlert(msg) catch |err| {
        std.debug.print("Callback error: {}\n", .{err});
        return; // Continue logging despite callback failure
    };
}
```

### 4. Offload Heavy Work

For expensive operations, use a queue:

```zig
const CallbackQueue = struct {
    queue: std.ArrayList([]const u8),
    mutex: std.Thread.Mutex = .{},
    
    fn enqueue(self: *CallbackQueue, msg: []const u8) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.queue.append(msg) catch return;
    }
};

var callback_queue: CallbackQueue = undefined;

fn lightweightCallback(msg: []const u8) void {
    callback_queue.enqueue(msg); // Fast enqueue
}

// Process queue asynchronously in background thread
```

### 5. Monitor Callback Performance

Track callback execution time:

```zig
fn monitoredCallback(record: *const logly.Record) void {
    const start = std.time.nanoTimestamp();
    defer {
        const elapsed = std.time.nanoTimestamp() - start;
        if (elapsed > 1_000_000) { // >1ms
            std.debug.print("⚠️  Slow callback: {d}μs\n", .{elapsed / 1000});
        }
    }
    
    // Callback logic here
}
```

## Performance Impact

Well-designed callbacks have minimal overhead:

- **Function pointer call**: ~5-10ns
- **Atomic counter increment**: ~20-30ns
- **Total overhead**: <1% for typical workloads

Avoid in callbacks:
- I/O operations
- Memory allocations
- Lock contention
- Expensive computations

## Complete Example

```zig
const std = @import("std");
const logly = @import("logly");

const MonitoringSystem = struct {
    error_count: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    drop_count: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    
    fn onError(self: *MonitoringSystem) fn([]const u8, []const u8) void {
        return struct {
            fn callback(sink_name: []const u8, error_msg: []const u8) void {
                _ = self.error_count.fetchAdd(1, .monotonic);
                if (self.error_count.load(.monotonic) > 100) {
                    // Alert on high error rate
                }
            }
        }.callback;
    }
    
    fn onDrop(self: *MonitoringSystem) fn(u64) void {
        return struct {
            fn callback(dropped: u64) void {
                _ = self.drop_count.fetchAdd(dropped, .monotonic);
            }
        }.callback;
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var monitor = MonitoringSystem{};
    
    const logger = try logly.Logger.init(allocator);
    defer logger.deinit();
    
    // Register callbacks
    logger.setSinkErrorCallback(monitor.onError());
    
    // Use logger normally
    try logger.info("Application started");
    
    // Get statistics
    const stats = logger.getStats();
    std.debug.print("Total errors: {d}\n", .{monitor.error_count.load(.monotonic)});
    std.debug.print("Records logged: {d}\n", .{stats.total_records_logged.load(.monotonic)});
}
```

## See Also

- [Metrics Guide](./metrics.md) - Collecting logging metrics
- [Async Logging](./async.md) - Asynchronous callback handling
- [Custom Levels](./custom-levels.md) - Custom level callbacks
