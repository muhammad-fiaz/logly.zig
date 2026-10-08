---
title: Logging Callbacks
description: Use callbacks in Logly.zig to hook into the logging process. Monitor events, track metrics, and trigger alerts across the entire logging pipeline.
head:
  - - meta
    - name: keywords
      content: callbacks, log hooks, monitoring, alerting, metrics collection, event handling, zig logging
  - - meta
    - property: og:title
      content: Logging Callbacks | Logly.zig
  - - meta
    - property: og:image
      content: https://muhammad-fiaz.github.io/logly.zig/cover.png
---

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
- **Thread Pool Callbacks**: Task lifecycle, queue pressure, work stealing
- **Scheduler Callbacks**: Scheduled task execution
- **Rules Callbacks**: Rule matching, evaluation, diagnostic messages
- **Crash Callbacks**: Panic and signal handling notifications

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
fn onSinkError(sinkName: []const u8, errorMsg: []const u8) void {
    std.debug.print("Sink '{s}' error: {s}\n", .{sinkName, errorMsg});
}

logger.setSinkErrorCallback(&onSinkError);
```

### Logger Lifecycle Callbacks

```zig
fn onLoggerInitialized(stats: *const logly.Logger.LoggerStats) void {
    std.debug.print("Logger initialized with {d} active sinks\\n", 
        .{stats.getActiveSinks()});
}

fn onLoggerDestroyed(stats: *const logly.Logger.LoggerStats) void {
    const total = stats.getTotalLogged();
    std.debug.print("Logger destroyed. Total records: {d}\\n", .{total});
}

logger.setInitializedCallback(&onLoggerInitialized);
logger.setDestroyedCallback(&onLoggerDestroyed);
```

## Sink Callbacks

### Write Callback

Called after each successful write:

```zig
fn onSinkWrite(recordCount: u64, bytesWritten: u64) void {
    metrics.track("sink.bytes_written", bytesWritten);
}

sink.setWriteCallback(&onSinkWrite);
```

### Flush Callback

Called after a flush operation:

```zig
fn onFlush(bytesFlushed: u64, durationNs: u64) void {
    const durationMs = durationNs / 1_000_000;
    std.debug.print("Flushed {d} bytes in {d}ms\n", .{bytesFlushed, durationMs});
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

### Signature Callback

Called when a cryptographic signature is generated for a log record (under cryptographic log chaining):

```zig
fn onSignature(sinkName: []const u8, signature: []const u8) void {
    std.debug.print("Sink '{s}' computed SHA-256 signature: {s}\n", .{sinkName, signature});
}

sink.setSignatureCallback(&onSignature);
```

### Mmap Resize Callback

Called when a memory-mapped sink grows in virtual memory capacity:

```zig
fn onMmapResize(sinkName: []const u8, oldSize: u64, newSize: u64) void {
    std.debug.print("Sink '{s}' virtual map grown: {d} -> {d} bytes\n", .{sinkName, oldSize, newSize});
}

sink.setMmapResizeCallback(&onMmapResize);
```

## Async Logging Callbacks

### Buffer Overflow Callback

```zig
fn onOverflow(droppedCount: u64) void {
    alerting.critical("Async buffer overflow! Dropped {d} records", .{droppedCount});
}

asyncLogger.overflowCallback = &onOverflow;
```

### Batch Processed Callback

```zig
fn onBatchProcessed(batchSize: usize, processing_time_us: u64) void {
    metrics.histogram("async.batch_size", batchSize);
    metrics.histogram("async.processing_time_us", processing_time_us);
}

asyncLogger.onBatchProcessed = &onBatchProcessed;
```

### Latency Threshold Callback

```zig
fn onLatencyExceeded(actual_latency_us: u64, threshold_us: u64) void {
    std.debug.print("⚠️  Latency {d}μs exceeds threshold {d}μs\n", 
        .{actual_latency_us, threshold_us});
}

asyncLogger.onLatencyThresholdExceeded = &onLatencyExceeded;
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
fn onSampleAccept(sampleRate: f64) void {
    metrics.increment("sampler.accepted", 1);
}

fn onSampleReject(sampleRate: f64, reason: logly.Sampler.SampleRejectReason) void {
    metrics.increment("sampler.rejected", 1);
}

sampler.setAcceptCallback(&onSampleAccept);
sampler.setRejectCallback(&onSampleReject);
```

### Rate Limit Exceeded

```zig
fn onRateExceeded(windowCount: u32, max_allowed: u32) void {
    std.debug.print("Rate limit hit: {d}/{d}\n", .{windowCount, max_allowed});
}

sampler.setRateLimitCallback(&onRateExceeded);
```

### Adaptive Rate Adjustment

```zig
fn onRateAdjustment(oldRate: f64, new_rate: f64, reason: []const u8) void {
    std.debug.print("Sample rate adjusted: {d:.2} -> {d:.2} ({s})\n", 
        .{oldRate, new_rate, reason});
}

sampler.setAdjustmentCallback(&onRateAdjustment);
```

## Redactor Callbacks

### Redaction Applied

```zig
fn onRedactionApplied(original_len: u64, redacted_len: u64, redactionType: u32) void {
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

### Redaction Detail

Called when a redaction occurs, providing the pattern name, original value, and the redacted replacement:

```zig
fn onRedactionDetail(pattern_name: []const u8, originalValue: []const u8, redacted_value: []const u8) void {
    audit.log("Redacted '{s}': '{s}' -> '{s}'", .{ pattern_name, originalValue, redacted_value });
}

redactor.setRedactionDetailCallback(&onRedactionDetail);
```

| Parameter | Type | Description |
|-----------|------|-------------|
| `pattern_name` | `[]const u8` | Name of the redaction pattern that matched (e.g., `"password"`, `"card"`) |
| `originalValue` | `[]const u8` | The original sensitive value before redaction |
| `redacted_value` | `[]const u8` | The replacement value after redaction (e.g., `"[REDACTED]"`) |

> [!NOTE]
> The `onRedactionDetail` callback is invoked for each individual redaction within a log record. A single record may trigger multiple redactions if multiple patterns match.

## Rotation Callbacks

### Rotation Lifecycle

```zig
fn onRotationStart(old_file: []const u8) void {
    std.debug.print("Starting rotation: {s}\n", .{old_file});
}

fn onRotationComplete(old_file: []const u8, new_file: []const u8, durationNs: u64) void {
    const durationMs = durationNs / 1_000_000;
    std.debug.print("Rotation complete in {d}ms: {s} -> {s}\n", 
        .{durationMs, old_file, new_file});
}

rotation.onRotationStart = &onRotationStart;
rotation.onRotationComplete = &onRotationComplete;
```

### Archive and Cleanup

```zig
fn onFileArchived(archived_file: []const u8, archivePath: []const u8) void {
    std.debug.print("Archived: {s} -> {s}\n", .{archived_file, archivePath});
}

fn onRetentionCleanup(deleted_count: u32, freed_bytes: u64) void {
    std.debug.print("Cleanup: {d} files deleted, {d} bytes freed\n", 
        .{deleted_count, freed_bytes});
}

rotation.onFileArchived = &onFileArchived;
rotation.onRetentionCleanup = &onRetentionCleanup;
```

## Compression Callbacks

```zig
fn onCompressionStart(filePath: []const u8, originalSize: u64) void {
    std.debug.print("Compressing: {s} ({d} bytes)\n", .{filePath, originalSize});
}

fn onCompressionComplete(filePath: []const u8, ratio: f64, durationNs: u64) void {
    std.debug.print("Compressed: {s}, ratio: {d:.2}, time: {d}ms\n", 
        .{filePath, ratio, durationNs / 1_000_000});
}

compression.onCompressionStart = &onCompressionStart;
compression.onCompressionComplete = &onCompressionComplete;
```

## Metrics Callbacks

```zig
fn onMetricsSnapshot(snapshot: *const logly.Metrics.Snapshot) void {
    const dropRate = snapshot.getDropRate();
    if (dropRate > 0.05) { // 5% drop rate
        alerting.warn("High drop rate: {d:.2}%", .{dropRate * 100});
    }
}

fn onThresholdExceeded(metricType: logly.Metrics.MetricType, value: u64, threshold: u64) void {
    std.debug.print("Threshold exceeded: {s} = {d} (limit: {d})\n", 
        .{@tagName(metricType), value, threshold});
}

metrics.onMetricsSnapshot = &onMetricsSnapshot;
metrics.onThresholdExceeded = &onThresholdExceeded;
```

## Thread Pool Callbacks

```zig
fn onThreadStart(threadId: usize) void {
    std.debug.print("Thread {d} started\n", .{threadId});
}

fn onThreadStop(threadId: usize, tasksProcessed: u64, uptimeMs: u64) void {
    std.debug.print("Thread {d} stopped after {d} tasks in {d}ms\n", .{threadId, tasksProcessed, uptimeMs});
}

fn onTaskSubmitted(priority: u8, queueDepth: usize) void {
    metrics.increment("threadpool.submitted", 1);
     _ = priority;
     _ = queueDepth;
}

fn onTaskDequeued(priority: u8, wait_time_us: u64) void {
    metrics.histogram("threadpool.wait_time_us", wait_time_us);
     _ = priority;
}

fn onTaskExecuted(exec_time_us: u64, success: bool) void {
    metrics.histogram("threadpool.execution_time_us", exec_time_us);
     _ = success;
}

fn onWorkStolen(victimThread: usize, thiefThread: usize) void {
    std.debug.print("Work stolen from {d} to {d}\n", .{victimThread, thiefThread});
}

fn onQueueOverflow(queueSize: usize, capacity: usize) void {
    std.debug.print("Thread pool full: {d}/{d}\n", .{queueSize, capacity});
}

threadPool.setThreadStartCallback(&onThreadStart);
threadPool.setThreadStopCallback(&onThreadStop);
threadPool.setTaskSubmittedCallback(&onTaskSubmitted);
threadPool.setTaskDequeuedCallback(&onTaskDequeued);
threadPool.setTaskExecutedCallback(&onTaskExecuted);
threadPool.setWorkStolenCallback(&onWorkStolen);
threadPool.setQueueOverflowCallback(&onQueueOverflow);
```

## Scheduler Callbacks

```zig
fn onTaskStarted(task_name: []const u8, runCount: u64) void {
    std.debug.print("Task '{s}' started (run #{d})\n", .{task_name, runCount});
}

fn onTaskCompleted(task_name: []const u8, durationMs: u64) void {
    metrics.histogram("scheduler.task_duration_ms", durationMs);
}

fn onTaskError(task_name: []const u8, errorMsg: []const u8) void {
    alerting.error("Scheduled task '{s}' failed: {s}", .{task_name, errorMsg});
}

scheduler.setTaskStartedCallback(&onTaskStarted);
scheduler.setTaskCompletedCallback(&onTaskCompleted);
scheduler.setTaskErrorCallback(&onTaskError);
```

## Invoke System Callbacks

The Invoke engine provides callbacks for monitoring trigger evaluations and message generation:

### Trigger Matched Callback

Called when a trigger matches a log record:

```zig
fn onTriggerMatched(trigger: *const logly.Invoke.Trigger, record: *const logly.Record) void {
    std.debug.print("Trigger '{s}' matched for level {s}\n", .{
        trigger.name orelse "unnamed",
        @tagName(record.level),
    });
}

invoke.on_trigger_matched = &onTriggerMatched;
```

### Messages Attached Callback

Called when messages are attached to a record:

```zig
fn onMessagesAttached(record: *const logly.Record, message_count: usize) void {
    std.debug.print("Attached {d} messages to record\n", .{message_count});
}

invoke.on_messages_attached = &onMessagesAttached;
```

### Evaluation Lifecycle Callbacks

```zig
fn onBeforeEvaluate(record: *const logly.Record) void {
    // Called before trigger evaluation starts
}

fn onAfterEvaluate(record: *const logly.Record, matched_count: usize) void {
    // Called after all triggers have been evaluated
    std.debug.print("{d} triggers matched for this record\n", .{matched_count});
}

fn onEvaluationError(errorMsg: []const u8) void {
    std.debug.print("Invoke evaluation error: {s}\n", .{errorMsg});
}

invoke.on_before_evaluate = &onBeforeEvaluate;
invoke.on_after_evaluate = &onAfterEvaluate;
invoke.on_evaluation_error = &onEvaluationError;
```

## Crash Callbacks

```zig
fn onCrash(message: []const u8) void {
    std.debug.print("Crash callback: {s}\n", .{message});
}

logly.crash.setCrashCallback(&onCrash);
```

### Available Rules Callbacks

| Callback | Parameters | Description |
|----------|-----------|-------------|
| `on_rule_matched` | `(rule, record)` | Rule matched a log record |
| `on_rule_evaluated` | `(rule, record, matched)` | Rule evaluation completed |
| `on_messages_attached` | `(record, count)` | Messages attached to record |
| `on_before_evaluate` | `(record)` | Before evaluation starts |
| `on_after_evaluate` | `(record, count)` | After evaluation completes |
| `on_evaluation_error` | `(errorMsg)` | Evaluation error occurred |

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
    const start = logly.Utils.currentNanos();
    defer {
        const elapsed = logly.Utils.currentNanos() - start;
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
    errorCount: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    drop_count: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    
    fn onError(self: *MonitoringSystem) fn([]const u8, []const u8) void {
        return struct {
            fn callback(sinkName: []const u8, errorMsg: []const u8) void {
                 _ = sinkName;
                 _ = errorMsg;
                 _ = self.errorCount.fetchAdd(1, .monotonic);
                if (self.errorCount.load(.monotonic) > 100) {
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
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var monitor = MonitoringSystem{};
    
    const logger = try logly.Logger.init(allocator);
    defer logger.deinit();
    
    // Register callbacks
    logger.setSinkErrorCallback(monitor.onError());
    
    // Use logger normally
    try logger.info("Application started", @src());
    
    // Get statistics
    const stats = logger.getStats();
    std.debug.print("Total errors: {d}\\n", .{monitor.errorCount.load(.monotonic)});
    std.debug.print("Records logged: {d}\\n", .{stats.getTotalLogged()});
}
```

## See Also

- [Metrics Guide](./metrics.md) - Collecting logging metrics
- [Async Logging](./async.md) - Asynchronous callback handling
- [Custom Levels](./custom-levels.md) - Custom level callbacks
