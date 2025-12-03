# Metrics Example

Collect logging metrics for observability and monitoring.

## Basic Metrics Collection

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

    // Record log metrics manually
    metrics.recordLog(.info, 45);    // info log, 45 bytes
    metrics.recordLog(.debug, 32);   // debug log, 32 bytes
    metrics.recordLog(.warning, 28); // warning log, 28 bytes
    metrics.recordLog(.err, 52);     // error log, 52 bytes
    metrics.recordLog(.info, 41);    // info log, 41 bytes

    // Get metrics snapshot
    const snapshot = metrics.getSnapshot();

    std.debug.print("Metrics:\n", .{});
    std.debug.print("  Total records: {d}\n", .{snapshot.total_records});
    std.debug.print("  Total bytes: {d}\n", .{snapshot.total_bytes});
    std.debug.print("  Dropped records: {d}\n", .{snapshot.dropped_records});
    std.debug.print("  Error count: {d}\n", .{snapshot.error_count});
    std.debug.print("  Uptime: {d}ms\n", .{snapshot.uptime_ms});
    std.debug.print("  Rate: {d:.2} records/sec\n", .{snapshot.records_per_second});
    std.debug.print("  Throughput: {d:.2} bytes/sec\n", .{snapshot.bytes_per_second});
}
```

## Metrics Available

```zig
const snapshot = metrics.getSnapshot();

// Per-level counts (array indexed by level)
snapshot.level_counts[0]  // trace
snapshot.level_counts[1]  // debug
snapshot.level_counts[2]  // info
snapshot.level_counts[3]  // success
snapshot.level_counts[4]  // warning
snapshot.level_counts[5]  // err
snapshot.level_counts[6]  // fail
snapshot.level_counts[7]  // critical

// Aggregates
snapshot.total_records      // Total log count
snapshot.total_bytes        // Total bytes logged
snapshot.dropped_records    // Count of dropped logs
snapshot.error_count        // Count of errors

// Timing and rates
snapshot.uptime_ms          // Time since start (milliseconds)
snapshot.records_per_second // Current record rate
snapshot.bytes_per_second   // Current throughput rate
```

## Recording Events

```zig
var metrics = Metrics.init(allocator);
defer metrics.deinit();

// Record a log at a specific level with byte size
metrics.recordLog(.info, 100);
metrics.recordLog(.warning, 75);

// Record a dropped log (e.g., from sampling/filtering)
metrics.recordDrop();

// Record an error (e.g., write failure)
metrics.recordError();

// Reset all metrics to zero
metrics.reset();
```

## Per-Sink Metrics

```zig
// Add a sink to track
const file_sink_idx = try metrics.addSink("file_sink");
const console_sink_idx = try metrics.addSink("console_sink");

// Record sink-specific writes
metrics.recordSinkWrite(file_sink_idx, 256);
metrics.recordSinkWrite(console_sink_idx, 128);

// Record sink write errors
metrics.recordSinkError(file_sink_idx);
```

## Formatted Output

```zig
// Get formatted metrics string
const formatted = try metrics.format(allocator);
defer allocator.free(formatted);

std.debug.print("{s}\n", .{formatted});
// Output:
// Logly Metrics
//   Total Records: 5
//   Total Bytes: 198
//   Dropped: 0
//   Errors: 0
//   Uptime: 1234ms
//   Rate: 4.05 records/sec
//   Throughput: 160.45 bytes/sec
```

## Metrics Alerts

```zig
// Check for error rate threshold
const snapshot = metrics.getSnapshot();
const error_rate = @as(f64, @floatFromInt(snapshot.error_count)) / 
                  @as(f64, @floatFromInt(snapshot.total_logs));

if (error_rate > 0.01) { // More than 1% errors
    // Trigger alert
    try alertSystem.notify("High error rate detected");
}
```

## Integration Examples

### Prometheus Format

```zig
pub fn prometheusMetrics(metrics: *Metrics) []const u8 {
    const s = metrics.getSnapshot();
    return std.fmt.allocPrint(allocator,
        \\# HELP logly_logs_total Total number of logs
        \\# TYPE logly_logs_total counter
        \\logly_logs_total {{level="debug"}} {}
        \\logly_logs_total {{level="info"}} {}
        \\logly_logs_total {{level="warning"}} {}
        \\logly_logs_total {{level="error"}} {}
        , .{s.debug_count, s.info_count, s.warning_count, s.error_count}
    );
}
```

### Health Check

```zig
pub fn healthCheck(metrics: *Metrics) bool {
    const s = metrics.getSnapshot();
    
    // Unhealthy if:
    // - Error rate > 5%
    // - No logs in last 60 seconds
    // - Critical errors present
    
    if (s.critical_count > 0) return false;
    if (s.total_logs > 0) {
        const error_rate = @as(f64, s.error_count) / @as(f64, s.total_logs);
        if (error_rate > 0.05) return false;
    }
    
    return true;
}
```

## Best Practices

1. **Monitor error rates** - Set up alerts for error rate spikes
2. **Track volume** - Watch for unusual log volume patterns
3. **Use dashboards** - Visualize metrics in real-time
4. **Reset periodically** - Clear metrics for fresh windows
5. **Export regularly** - Send metrics to monitoring systems
