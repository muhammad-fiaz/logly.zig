# Metrics

Logly-Zig v0.0.3+ provides built-in metrics collection for monitoring logging performance and behavior. Track record counts, error rates, throughput, and more.

## Overview

The `Metrics` module enables you to:
- Track total log records processed
- Count records by log level
- Monitor error rates and failures
- Measure logging throughput
- Track per-sink statistics

## Basic Usage

```zig
const std = @import("std");
const logly = @import("logly");
const Metrics = logly.Metrics;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create metrics collector
    var metrics = Metrics.init(allocator);
    defer metrics.deinit();

    // Record log events
    metrics.recordLog(.info, 45);     // info log, 45 bytes
    metrics.recordLog(.debug, 32);    // debug log, 32 bytes
    metrics.recordLog(.warning, 28);  // warning log, 28 bytes
    metrics.recordLog(.err, 52);      // error log, 52 bytes
    metrics.recordError();            // record an error event

    // Get metrics snapshot
    const snapshot = metrics.getSnapshot();
    
    std.debug.print("=== Logging Metrics ===\n", .{});
    std.debug.print("Total records: {d}\n", .{snapshot.total_records});
    std.debug.print("Total bytes: {d}\n", .{snapshot.total_bytes});
    std.debug.print("Error count: {d}\n", .{snapshot.error_count});
    std.debug.print("Records/sec: {d:.2}\n", .{snapshot.records_per_second});
}
```

## Metrics Snapshot

The `Metrics.Snapshot` struct contains:

| Field | Type | Description |
|-------|------|-------------|
| `total_records` | `u64` | Total number of log records processed |
| `total_bytes` | `u64` | Total bytes logged |
| `dropped_records` | `u64` | Records dropped (by sampling/filtering) |
| `error_count` | `u64` | Number of errors recorded |
| `uptime_ms` | `i64` | Time since metrics started (milliseconds) |
| `records_per_second` | `f64` | Current record rate |
| `bytes_per_second` | `f64` | Current throughput rate |
| `level_counts` | `[8]u64` | Per-level record counts |

## Level Counts

Access counts per log level using the level index:

```zig
const snapshot = metrics.getSnapshot();

// Level indices: trace=0, debug=1, info=2, success=3, warning=4, err=5, fail=6, critical=7
const debug_count = snapshot.level_counts[1];   // debug
const info_count = snapshot.level_counts[2];    // info
const warning_count = snapshot.level_counts[4]; // warning
const error_count = snapshot.level_counts[5];   // err
const critical_count = snapshot.level_counts[7]; // critical
```

## Recording Events

```zig
var metrics = Metrics.init(allocator);
defer metrics.deinit();

// Record a log at specific level with byte size
metrics.recordLog(.info, 100);
metrics.recordLog(.warning, 75);

// Record a dropped log (e.g., filtered or sampled out)
metrics.recordDrop();

// Record an error event
metrics.recordError();

// Reset all metrics to zero
metrics.reset();
```

## Per-Sink Metrics

Track metrics per sink:

```zig
var metrics = Metrics.init(allocator);
defer metrics.deinit();

// Add sinks to track
const file_sink_idx = try metrics.addSink("file_sink");
const console_sink_idx = try metrics.addSink("console_sink");

// Record sink-specific writes
metrics.recordSinkWrite(file_sink_idx, 256);      // 256 bytes to file sink
metrics.recordSinkWrite(console_sink_idx, 128);   // 128 bytes to console

// Record sink write errors
metrics.recordSinkError(file_sink_idx);
```

## Formatted Output

Get a human-readable metrics report:

```zig
var metrics = Metrics.init(allocator);
defer metrics.deinit();

// Record some logs...
metrics.recordLog(.info, 100);
metrics.recordLog(.err, 50);

// Get formatted output
const formatted = try metrics.format(allocator);
defer allocator.free(formatted);

std.debug.print("{s}\n", .{formatted});
// Output:
// Logly Metrics
//   Total Records: 2
//   Total Bytes: 150
//   Dropped: 0
//   Errors: 0
//   Uptime: 1234ms
//   Rate: 1.62 records/sec
//   Throughput: 121.55 bytes/sec
```

## Periodic Metrics Reporting

```zig
const std = @import("std");
const logly = @import("logly");
const Metrics = logly.Metrics;

pub fn reportMetrics(m: *Metrics) void {
    const snapshot = m.getSnapshot();
    
    const error_rate = if (snapshot.total_records > 0)
        @as(f64, @floatFromInt(snapshot.error_count)) / 
        @as(f64, @floatFromInt(snapshot.total_records)) * 100.0
    else
        0.0;

    std.debug.print(
        "[Metrics] Total: {d} | Errors: {d} ({d:.2}%) | Rate: {d:.1} rec/sec\n",
        .{
            snapshot.total_records,
            snapshot.error_count,
            error_rate,
            snapshot.records_per_second,
        }
    );
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var metrics = Metrics.init(allocator);
    defer metrics.deinit();

    // Simulate logging with periodic reporting
    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        metrics.recordLog(.info, 50);

        // Report every 100 records
        if (i % 100 == 0) {
            reportMetrics(&metrics);
        }
    }

    // Final report
    reportMetrics(&metrics);
}
```

## Best Practices

1. **Use metrics in production**: Metrics have minimal overhead
2. **Export regularly**: Don't wait until shutdown to check metrics
3. **Alert on error rates**: Set up alerts for high error percentages
4. **Track dropped records**: Monitor how many records are sampled/filtered out
5. **Reset periodically**: Use `reset()` for time-windowed metrics

## See Also

- [Filtering](/guide/filtering) - Rule-based log filtering
- [Sampling](/guide/sampling) - Log volume control
- [Tracing](/guide/tracing) - Distributed tracing
- [Configuration](/guide/configuration) - Global configuration options
