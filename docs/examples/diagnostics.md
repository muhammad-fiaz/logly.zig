---
title: System Diagnostics Example
description: Example of emitting system diagnostics with Logly.zig. Log OS, CPU, memory, and storage info at startup or on-demand. Includes JSON export, health check, and snapshot diff (v0.2.0).
head:
  - - meta
    - name: keywords
      content: diagnostics example, system info, cpu info, memory stats, storage info, monitoring, debugging, health check, json diagnostics
  - - meta
    - property: og:title
      content: System Diagnostics Example | Logly.zig
---

# Diagnostics Example

Emit system diagnostics at startup and on-demand, including optional per-drive storage details.

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){}; 
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    _ = logly.Terminal.enableAnsiColors();

    var config = logly.Config.default();
    config.emit_system_diagnostics_on_init = true;
    config.include_drive_diagnostics = true;

    const logger = try logly.Logger.initWithConfig(allocator, config);
    defer logger.deinit();

    // Startup diagnostics already logged. Emit again on demand:
    try logger.logSystemDiagnostics(@src());
}
```

## What it Logs

- OS tag, architecture, CPU model, logical cores
- Total and available RAM (MB)
- Per-drive totals/free space when `include_drive_diagnostics = true`

## JSON Export (v0.2.0)

Serialize diagnostics as a compact JSON string:

```zig
var diag = try logly.Diagnostics.collect(allocator, false);
defer diag.deinit(allocator);

const json = try logly.Diagnostics.toJson(&diag, allocator);
defer allocator.free(json);
std.debug.print("{s}\n", .{json});
```

## Health Check (v0.2.0)

Check system health based on available memory:

```zig
var diag = try logly.Diagnostics.collect(allocator, false);
defer diag.deinit(allocator);

const health = logly.Diagnostics.checkHealth(&diag);
std.debug.print("Status: {s}\n", .{@tagName(health.status)});
if (health.issues.len > 0) {
    std.debug.print("Issues: {s}\n", .{health.issues});
}
```

## Snapshot Diff (v0.2.0)

Compare two diagnostic snapshots to detect changes:

```zig
var diag1 = try logly.Diagnostics.collect(allocator, false);
defer diag1.deinit(allocator);
const snap1 = logly.Diagnostics.takeSnapshot(&diag1);

std.time.sleep(10_000_000); // 10ms

var diag2 = try logly.Diagnostics.collect(allocator, false);
defer diag2.deinit(allocator);
const snap2 = logly.Diagnostics.takeSnapshot(&diag2);

const delta = try logly.Diagnostics.diff(snap1, snap2, allocator);
defer allocator.free(delta);
std.debug.print("{s}", .{delta});
```

## See Also

- [Diagnostics API](../api/diagnostics) - Complete API reference
- [Diagnostics Guide](../guide/diagnostics) - Usage patterns
