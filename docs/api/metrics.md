---
title: Metrics API Reference
description: API reference for Logly.zig Metrics struct. Track record counts, bytes written, error rates, per-level statistics, and sink throughput with atomic counters.
head:
  - - meta
    - name: keywords
      content: metrics api, logging metrics, performance counters, statistics api, throughput tracking, observability
  - - meta
    - property: og:title
      content: Metrics API Reference | Logly.zig
---

# Metrics API

The `Metrics` struct provides comprehensive observability into the logging system's performance and health.

## Quick Reference: Method Aliases

| Full Method | Alias(es) | Description |
|-------------|-----------|-------------|
| `init()` | `create()` | Initialize metrics |
| `deinit()` | `destroy()` | Deinitialize metrics |

## Overview

Metrics tracks record counts, throughput, errors, and per-sink statistics. It uses thread-safe atomic operations for all counters, making it safe for concurrent access without locks on hot paths.

## Types

### Metrics

The main metrics controller with atomic counters and callback support.

```zig
pub const Metrics = struct {
    total_records: std.atomic.Value(u64),
    total_bytes: std.atomic.Value(u64),
    dropped_records: std.atomic.Value(u64),
    error_count: std.atomic.Value(u64),
    level_counts: [10]std.atomic.Value(u64),
    start_time: i64,
    sink_metrics: std.ArrayList(SinkMetrics),
    
    // Callbacks
    on_record_logged: ?*const fn (Level, u64) void,
    on_metrics_snapshot: ?*const fn (*const Snapshot) void,
    on_threshold_exceeded: ?*const fn (MetricType, u64, u64) void,
    on_error_detected: ?*const fn (ErrorEvent, u64) void,
};
```

### MetricType

Types of metrics for threshold notifications.

```zig
pub const MetricType = enum {
    total_records,
    total_bytes,
    dropped_records,
    error_count,
    records_per_second,
    bytes_per_second,
};
```

### ErrorEvent

Error event types for monitoring.

```zig
pub const ErrorEvent = enum {
    records_dropped,
    sink_write_error,
    buffer_overflow,
    sampling_drop,
};
```

### SinkMetrics

Per-sink statistics with atomic counters.

```zig
pub const SinkMetrics = struct {
    name: []const u8,
    records_written: std.atomic.Value(u64),
    bytes_written: std.atomic.Value(u64),
    write_errors: std.atomic.Value(u64),
    flush_count: std.atomic.Value(u64),
};
```

#### Getter Methods

| Method | Return | Description |
|--------|--------|-------------|
| `getRecordsWritten()` | `u64` | Get total records written |
| `getBytesWritten()` | `u64` | Get total bytes written |
| `getWriteErrors()` | `u64` | Get write errors count |
| `getFlushCount()` | `u64` | Get flush count |

#### Boolean Checks

| Method | Return | Description |
|--------|--------|-------------|
| `hasWritten()` | `bool` | Check if any records have been written |
| `hasErrors()` | `bool` | Check if any errors have occurred |

#### Rate Calculations

| Method | Return | Description |
|--------|--------|-------------|
| `getErrorRate()` | `f64` | Calculate error rate (0.0 - 1.0) |
| `getSuccessRate()` | `f64` | Calculate success rate (0.0 - 1.0) |
| `avgBytesPerRecord()` | `f64` | Calculate average bytes per record |
| `avgRecordsPerFlush()` | `f64` | Calculate average records per flush |
| `throughputBytesPerSecond(elapsed_seconds)` | `f64` | Calculate bytes per second throughput |

#### Reset

| Method | Description |
|--------|-------------|
| `reset()` | Reset all statistics to initial state |

### Snapshot

A point-in-time snapshot of metrics, useful for reporting.

```zig
pub const Snapshot = struct {
    total_records: u64,
    total_bytes: u64,
    dropped_records: u64,
    error_count: u64,
    uptime_ms: i64,
    records_per_second: f64,
    bytes_per_second: f64,
    level_counts: [10]u64,
    
    pub fn getDropRate(self: *const Snapshot) f64;
};
```

## Methods

### Initialization

#### `init(allocator: std.mem.Allocator) Metrics`

Initializes a new Metrics instance with all counters at zero.

**Alias:** `create`

#### `initWithConfig(allocator: std.mem.Allocator, config: MetricsConfig) Metrics`

Initializes a new Metrics instance with custom configuration.

#### `deinit(self: *Metrics) void`

Releases all resources associated with metrics.

**Alias:** `destroy`

### Callbacks

#### `setRecordLoggedCallback(callback: *const fn (Level, u64) void) void`

Sets the callback invoked when a record is logged.

#### `setSnapshotCallback(callback: *const fn (*const Snapshot) void) void`

Sets the callback invoked when a metrics snapshot is taken.

#### `setThresholdCallback(callback: *const fn (MetricType, u64, u64) void) void`

Sets the callback invoked when metrics exceed thresholds.

#### `setErrorCallback(callback: *const fn (ErrorEvent, u64) void) void`

Sets the callback invoked when errors or dropped records are detected.

### Configuration

#### `getConfig() MetricsConfig`

Returns the current metrics configuration.

#### `isEnabled() bool`

Returns true if metrics collection is enabled.

### Recording

#### `recordLog(level: Level, bytes: u64) void`

Records a successful log event with its level and size.

**Alias**: `record`, `log`

#### `recordLogWithLatency(level: Level, bytes: u64, latency_ns: u64) void`

Records a log with latency measurement for histogram tracking.

#### `recordDrop() void`

Records a dropped log event (e.g., due to buffer overflow).

**Alias**: `drop`, `dropped`

#### `recordError() void`

Records an internal error.

**Alias**: `recordErr`

#### `recordCustomLog(bytes: u64) void`

Records a log using a custom level.

### Sink Tracking

#### `addSink(name: []const u8) !usize`

Adds a sink to track. Returns the sink index.

#### `recordSinkWrite(sink_index: usize, bytes: u64) void`

Records a successful write to a sink.

#### `recordSinkError(sink_index: usize) void`

Records a write error on a sink.

#### `recordSinkFlush(sink_index: usize) void`

Records a flush operation on a sink.

#### `getSinkMetrics(sink_index: usize) ?SinkMetrics`

Returns sink metrics by index.

#### `getSinkMetricsByName(name: []const u8) ?SinkMetrics`

Returns sink metrics by name.

### Snapshots

#### `getSnapshot() Snapshot`

Returns a thread-safe snapshot of the current metrics.

**Alias**: `metricsSnapshot`

#### `takeSnapshot() !Snapshot`

Takes a snapshot and optionally stores in history.

#### `getHistory() []const Snapshot`

Returns the snapshot history.

#### `formatLevelBreakdown(allocator: Allocator) ![]u8`

Returns a formatted string showing log counts by level.

**Alias**: `levels`, `breakdown`

### Export

#### `exportMetrics(allocator: Allocator) ![]u8`

Exports metrics in the configured format.

#### `exportJson(allocator: Allocator) ![]u8`

Exports metrics as JSON format.

#### `exportPrometheus(allocator: Allocator) ![]u8`

Exports metrics as Prometheus exposition format.

#### `exportStatsd(allocator: Allocator) ![]u8`

Exports metrics as StatsD format.

### Latency

#### `avgLatencyNs() u64`

Returns average latency in nanoseconds.

#### `minLatencyNs() u64`

Returns minimum latency in nanoseconds.

#### `maxLatencyNs() u64`

Returns maximum latency in nanoseconds.

#### `getHistogram() [20]u64`

Returns histogram bucket data.

### Statistics

#### `totalRecordCount() u64`

Returns the total number of records logged.

#### `totalBytesLogged() u64`

Returns the total bytes written.

#### `errorCount() u64`

Returns the total error count.

#### `droppedCount() u64`

Returns the count of dropped records.

#### `errorRate() f64`

Returns the error rate (0.0 - 1.0).

#### `dropRate() f64`

Returns the drop rate (0.0 - 1.0).

#### `rate() f64`

Returns records per second throughput.

#### `bytesPerSecond() f64`

Returns bytes per second throughput.

**Alias**: `throughput`

#### `uptime() i64`

Returns uptime in milliseconds.

#### `uptimeSeconds() f64`

Returns uptime in seconds.

**Alias**: `uptimeSec`

#### `levelCount(level: Level) u64`

Returns the count for a specific log level.

#### `sinkCount() usize`

Returns the number of sinks being tracked.

### State

#### `hasRecords() bool`

Returns true if any records have been logged.

#### `hasErrors() bool`

Returns true if any errors have occurred.

#### `hasDropped() bool`

Returns true if any records have been dropped.

#### `hasHighErrorRate(threshold: f64) bool`

Returns true if error rate exceeds the threshold.

#### `hasHighDropRate(threshold: f64) bool`

Returns true if drop rate exceeds the threshold.

#### `reset() void`

Resets all metrics to zero.

**Alias**: `clear`

## Presets

### MetricsPresets

```zig
pub const MetricsPresets = struct {
    /// Creates a basic metrics instance.
    pub fn basic(allocator: std.mem.Allocator) Metrics;
    
    /// Creates a metrics sink configuration.
    pub fn createMetricsSink(file_path: []const u8) SinkConfig;
};
```

## Example

```zig
const Metrics = @import("logly").Metrics;

// Initialize
var metrics = Metrics.init(allocator);
defer metrics.deinit();

// Record logs
metrics.recordLog(.info, 256);
metrics.recordLog(.err, 512);

// Check statistics
const snapshot = metrics.getSnapshot();
std.debug.print("Records: {d}\n", .{snapshot.total_records});
std.debug.print("Rate: {d:.2} rec/s\n", .{snapshot.records_per_second});

// Check health
if (metrics.hasHighErrorRate(0.01)) {
    std.debug.print("Warning: High error rate!\n", .{});
}

// Get level breakdown
const breakdown = try metrics.formatLevelBreakdown(allocator);
defer allocator.free(breakdown);
std.debug.print("{s}\n", .{breakdown});

// Reset if needed
metrics.reset();
```

## Performance

- **Lock-free**: All hot paths use atomic operations
- **Low overhead**: ~1-2% CPU for enabled metrics
- **Thread-safe**: Safe for concurrent access from multiple threads
- **Batch updates**: Reduces contention in high-throughput scenarios
