# Metrics API

The `Metrics` struct provides observability into the logging system's performance and health.

## Overview

Metrics tracks record counts, throughput, errors, and per-sink statistics. It is essential for monitoring the health of the logging pipeline in production.

## Types

### Metrics

The main metrics controller.

```zig
pub const Metrics = struct {
    total_records: std.atomic.Value(u64),
    total_bytes: std.atomic.Value(u64),
    dropped_records: std.atomic.Value(u64),
    error_count: std.atomic.Value(u64),
    level_counts: [8]std.atomic.Value(u64),
    start_time: i64,
    sink_metrics: std.ArrayList(SinkMetrics),
};
```

### SinkMetrics

Per-sink statistics.

```zig
pub const SinkMetrics = struct {
    name: []const u8,
    records_written: std.atomic.Value(u64),
    bytes_written: std.atomic.Value(u64),
    write_errors: std.atomic.Value(u64),
    flush_count: std.atomic.Value(u64),
};
```

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
    level_counts: [8]u64,
};
```

## Methods

### `init(allocator: std.mem.Allocator) Metrics`

Initializes a new Metrics instance.

### `record(level: Level, bytes: usize) void`

Records a successful log event.

### `recordDrop() void`

Records a dropped log event (e.g., due to buffer overflow).

### `recordError() void`

Records an internal error.

### `getSnapshot() Snapshot`

Returns a thread-safe snapshot of the current metrics.

### `getSinkMetrics(index: usize) ?*SinkMetrics`

Returns metrics for a specific sink.
