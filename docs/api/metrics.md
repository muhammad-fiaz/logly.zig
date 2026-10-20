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

The `Metrics` struct exposes counters, histograms, and rates for the logging system.

## Overview

Metrics tracks record counts, throughput, errors, and per-sink statistics. Counters use atomic operations, and mutations that touch shared structures are synchronized by an internal mutex.

## Export Customization

`Config.MetricsConfig` includes exporter naming and breakdown controls:

```zig
const cfg = logly.Config.MetricsConfig.production()
    .prometheus()
    .withPrefix("checkout.api")
    .withLatencyHistogram(20)
    .withBreakdowns(true, true);

var metrics = logly.Metrics.initWithConfig(allocator, cfg);
```

Available controls:

| Field / Helper | Purpose |
|----------------|---------|
| `metricPrefix`, `withPrefix()` | Namespace exported metrics |
| `metricSeparator` | Separator for Prometheus-compatible names |
| `statsdSeparator` | Separator for StatsD metric names |
| `sanitizeNames` | Replace exporter-unsafe characters |
| `exportLevelBreakdown` | Include per-level counters |
| `exportSinkBreakdown` | Include per-sink counters/errors |
| `prometheus()` | Configure Prometheus export naming |
| `statsd()` | Configure StatsD export naming |
| `withAlerts()` | Configure error/drop thresholds |
| `withLatencyHistogram()` | Enable latency histogram collection |

### MetricsConfig

Global configuration for metrics collection and export.

```zig
pub const MetricsConfig = struct {
    enabled: bool = false,
    trackLevels: bool = true,
    trackSinks: bool = true,
    trackThroughput: bool = true,
    trackLatency: bool = false,
    snapshotIntervalMs: u64 = 0,
    errorRateThreshold: f32 = 0.0,
    dropRateThreshold: f32 = 0.0,
    maxRecordsPerSecond: u64 = 0,
    exportFormat: ExportFormat = .text,
    enableHistogram: bool = false,
    histogramBuckets: u8 = 10,
    historySize: u16 = 0,
    metricPrefix: []const u8 = "logly",
    metricSeparator: []const u8 = "_",
    statsdSeparator: []const u8 = ".",
    sanitizeNames: bool = true,
    exportLevelBreakdown: bool = true,
    exportSinkBreakdown: bool = true,

    pub const ExportFormat = enum {
        text,
        json,
        prometheus,
        statsd,
    };
};
```

## Types

### Metrics

The main metrics controller with atomic counters and callback support.

```zig
pub const Metrics = struct {
    totalRecords: std.atomic.Value(u64),
    totalBytes: std.atomic.Value(u64),
    droppedRecords: std.atomic.Value(u64),
    totalErrors: std.atomic.Value(u64),
    levelCounts: [Constants.LevelConstants.count]std.atomic.Value(u64),
    startTime: i64,
    sinkMetrics: std.ArrayList(SinkMetrics),

    // Callbacks
    onRecordLogged: ?*const fn (Level, u64) void,
    onMetricsSnapshot: ?*const fn (*const Snapshot) void,
    onThresholdExceeded: ?*const fn (MetricType, u64, u64) void,
    onErrorDetected: ?*const fn (ErrorEvent, u64) void,
};
```

### MetricType

Types of metrics for threshold notifications.

```zig
pub const MetricType = enum {
    totalRecords,
    totalBytes,
    droppedRecords,
    errorCount,
    recordsPerSecond,
    bytesPerSecond,
};
```

### ErrorEvent

Error event types for monitoring.

```zig
pub const ErrorEvent = enum {
    recordsDropped,
    sinkWriteError,
    bufferOverflow,
    samplingDrop,
};
```

### SinkMetrics

Per-sink statistics with atomic counters.

```zig
pub const SinkMetrics = struct {
    name: []const u8,
    recordsWritten: std.atomic.Value(u64),
    bytesWritten: std.atomic.Value(u64),
    writeErrors: std.atomic.Value(u64),
    flushCount: std.atomic.Value(u64),
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
| `throughputBytesPerSecond(elapsedSeconds)` | `f64` | Calculate bytes per second throughput |

#### Reset

| Method | Description |
|--------|-------------|
| `reset()` | Reset all statistics to initial state |

### Snapshot

A point-in-time snapshot of metrics, useful for reporting.

```zig
pub const Snapshot = struct {
    totalRecords: u64,
    totalBytes: u64,
    droppedRecords: u64,
    errorCount: u64,
    uptimeMs: i64,
    recordsPerSecond: f64,
    bytesPerSecond: f64,
    levelCounts: [10]u64,

    pub fn getDropRate(self: *const Snapshot) f64;
};
```

## Methods

### Initialization

#### `init(allocator: std.mem.Allocator) Metrics`

Initializes a new Metrics instance with all counters at zero.

#### `initWithConfig(allocator: std.mem.Allocator, config: MetricsConfig) Metrics`

Initializes a new Metrics instance with custom configuration.

#### `initWithIo(allocator: std.mem.Allocator, io_handle: std.Io, config: MetricsConfig) Metrics`

Initializes a new Metrics instance with an explicit I/O handle and custom configuration.

#### `deinit(self: *Metrics) void`

Releases all resources associated with metrics.

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

#### `recordLogWithLatency(level: Level, bytes: u64, latencyNs: u64) void`

Records a log with latency measurement for histogram tracking.

#### `recordDrop() void`

Records a dropped log event (e.g., due to buffer overflow).

#### `recordError() void`

Records an internal error.

#### `recordCustomLog(bytes: u64) void`

Records a log using a custom level.

### Sink Tracking

#### `addSink(name: []const u8) !usize`

Adds a sink to track. Returns the sink index.

#### `recordSinkWrite(sinkIndex: usize, bytes: u64) void`

Records a successful write to a sink.

#### `recordSinkError(sinkIndex: usize) void`

Records a write error on a sink.

#### `recordSinkFlush(sinkIndex: usize) void`

Records a flush operation on a sink.

#### `getSinkMetrics(sinkIndex: usize) ?SinkMetrics`

Returns sink metrics by index.

#### `getSinkMetricsByName(name: []const u8) ?SinkMetrics`

Returns sink metrics by name.

### Snapshots

#### `getSnapshot() Snapshot`

Returns a thread-safe snapshot of the current metrics.

#### `takeSnapshot() !Snapshot`

Takes a snapshot and optionally stores in history.

#### `getHistory() []const Snapshot`

Returns the snapshot history.

#### `formatLevelBreakdown(allocator: Allocator) ![]u8`

Returns a formatted string showing log counts by level.

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

#### `latencyPercentileNs(percentile: f64) u64`

Estimates latency percentile in nanoseconds using histogram buckets.

#### `latencyPercentileMs(percentile: f64) f64`

Estimates latency percentile in milliseconds.

#### `getLatencySummary() LatencySummary`

Returns aggregated latency values including `min`, `max`, `avg`, `p50`, `p95`, and `p99`.

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

#### `uptime() i64`

Returns uptime in milliseconds.

#### `uptimeSeconds() f64`

Returns uptime in seconds.

#### `levelCount(level: Level) u64`

Returns the count for a specific log level.

#### `sinkCount() usize`

Returns the number of sinks being tracked.

#### `totalSinkErrors() u64`

Returns total sink write errors across all tracked sinks.

#### `totalSinkFlushes() u64`

Returns total sink flush count across all tracked sinks.

#### `lastRecordAgeMs() ?i64`

Returns age in milliseconds since the last recorded log entry, or `null` when no record has been logged yet.

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

## Presets

### MetricsPresets

```zig
pub const MetricsPresets = struct {
    /// Creates a basic metrics instance.
    pub fn basic(allocator: std.mem.Allocator) Metrics;

    /// Creates a metrics sink configuration.
    pub fn createMetricsSink(filePath: []const u8) SinkConfig;
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
std.debug.print("Records: {d}\n", .{snapshot.totalRecords});
std.debug.print("Rate: {d:.2} rec/s\n", .{snapshot.recordsPerSecond});

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

- **Thread-safe**: Recording and snapshot reads are synchronized by an internal mutex.
- **Opt-in overhead**: Allocation and locking costs apply only when metrics collection is enabled.
