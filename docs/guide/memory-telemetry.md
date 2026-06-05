---
title: Memory Telemetry
description: Track live bytes, peak usage, and live allocations of your logly logger in real time using the MemoryTracker wrapper.
head:
  - - meta
    - name: keywords
      content: logly, zig, memory tracking, allocator, telemetry, leak detection, pressure
---

# Memory Telemetry

`logly.MemoryTracker` is a thin wrapper around any `std.mem.Allocator` that tracks live bytes, peak bytes, allocation count, deallocation count, and live allocation count. It is the recommended way to observe logly's allocator behaviour at runtime without instrumenting individual call sites.

> [!NOTE]
> `MemoryTracker` is fully opt-in. If you do not create one, logly allocates through your plain `std.mem.Allocator` and the telemetry hooks are simply not active.

## Basic Usage

```zig
const logly = @import("logly");
const std = @import("std");

var gpa = std.heap.DebugAllocator(.{}){};
defer _ = gpa.deinit();

var tracker = logly.MemoryTracker.init(gpa.allocator());
const logger = try logly.Logger.initWithConfig(tracker.allocator(), .default());
defer logger.deinit();
logger.attachMemoryTracker(&tracker);

try logger.info("hello", @src());
try logger.info("world", @src());

const report = logger.getMemoryReport().?;
std.debug.print("used={d} peak={d} live={d}\n", .{
    report.bytes_used,
    report.bytes_peak,
    report.live_allocations,
});
```

## Detecting Host Memory

```zig
const avail = logly.detectAvailableMemory(); // bytes, OS-level probe
const rss = logly.detectCurrentMemoryUsage(); // bytes, process resident set
std.debug.print("available={d} rss={d}\n", .{ avail, rss });
```

`detectAvailableMemory` reads `/proc/meminfo` (MemAvailable) on Linux, calls `GlobalMemoryStatusEx` via direct FFI on Windows, and falls back to MemFree on the BSD family. `detectCurrentMemoryUsage` reads `/proc/self/status` VmRSS on Linux; on other operating systems it returns 0.

## Reporting Helpers

`MemoryReport` exposes helpers for ergonomic rendering:

```zig
var buf: std.ArrayListUnmanaged(u8) = .empty;
defer buf.deinit(allocator);

try report.formatCompact(buf.writer(allocator));
std.debug.print("compact: {s}\n", .{buf.items});

try report.formatHuman(buf.writer(allocator));
std.debug.print("human:   {s}\n", .{buf.items});

if (report.isPressureHigh(0.85)) {
    std.log.warn("memory pressure high", .{});
}
```

## Per-Allocation Callback

Register a `MemoryCallback` to react to every `alloc`, `resize`, `remap`, and `free`:

```zig
const Callback = struct {
    fn onChange(
        used: usize,
        peak: usize,
        cap: usize,
        ud: ?*anyopaque,
    ) void {
        _ = ud;
        std.log.info("alloc/free fired used={d} peak={d} cap={d}", .{ used, peak, cap });
    }
};

tracker.setCallback(&Callback.onChange, null);
// aliases: tracker.onChange(...), tracker.setOnChange(...), tracker.setNotifyCallback(...)
```

> [!TIP]
> The callback fires while the tracker mutex is held. Keep it short; defer any non-trivial work to a worker thread.

## Pressure-Event Callback

Wire a `PressureCallback` to fire when the live usage crosses a configurable threshold of the running peak. The tracker is an **edge detector** - the callback fires exactly once per crossing, and re-arms when `bytes_used` drops back below the threshold.

```zig
const Pressure = struct {
    fn onPressure(
        used: usize,
        peak: usize,
        cap: usize,
        threshold: f64,
        ud: ?*anyopaque,
    ) void {
        _ = ud;
        std.log.warn(
            "memory pressure: used={d} peak={d} cap={d} threshold={d:.2}",
            .{ used, peak, cap, threshold },
        );
    }
};

tracker.setPressureThreshold(0.9);                       // clamped to [0.0, 1.0]
tracker.setFireOnPressure(true);                         // enable the callback
tracker.setPressureCallback(&Pressure.onPressure, null);  // aliases: onPressure, setOnPressure
```

`tracker.isPressureHigh()` is the poll form of the same edge detector - it returns `true` after a crossing and `false` once the live usage drops back below the threshold.

## OOM-Event Callback

Register an `OomCallback` to observe allocation failures from the inner allocator. Fires outside the tracker mutex.

```zig
const Oom = struct {
    fn onOom(
        requested_len: usize,
        alignment: std.mem.Alignment,
        ud: ?*anyopaque,
    ) void {
        _ = ud;
        std.log.err("OOM: requested {d} bytes, alignment {d}", .{ requested_len, alignment.toByteUnits() });
    }
};

tracker.setOomCallback(&Oom.onOom, null);
// aliases: tracker.onOom(...), tracker.setOnOom(...)
```

## Periodic OS Probe Refresh

When `setRefreshInterval(interval_ms)` is set to a non-zero value, the tracker refreshes `bytes_available` from the OS probe on every `alloc` / `resize` / `remap` at the configured cadence. `0` disables the periodic refresh; the user can still call `tracker.refreshAvailableMemory()` on demand.

```zig
tracker.setRefreshInterval(2_000); // 2 s
```

## Driving the Tracker from `Config.MemoryConfig`

The same fields are exposed through `Config.MemoryConfig` and propagated through `Config.withMemory(...)` and the family of `withMemory*` builders. The struct is read by `MemoryTracker.initWithConfig(inner, memory)` so a logger can be configured end-to-end from a single `Config`:

```zig
const cfg = logly.Config.default()
    .withMemoryPressureThreshold(0.85)
    .withMemoryRefreshInterval(2_000)
    .withMemoryPressureCallback(&Pressure.onPressure, null)
    .withMemoryOomCallback(&Oom.onOom, null);

var tracker = logly.MemoryTracker.initWithConfig(gpa.allocator(), cfg.memory);
const logger = try logly.Logger.initWithConfig(tracker.allocator(), cfg);
```

`Config.MemoryConfig` builders: `withThreshold` / `withRefreshInterval` / `withEnabled` / `withPressureEvents` / `withPressureCallback` / `withOomCallback` (with matching `threshold` / `refreshInterval` / `pressure` / `onPressure` / `setPressureCallback` / `oom` / `onOom` / `setOomCallback` / `enable` / `disable` / `fireOnPressure` aliases).

`Config` builders: `withMemory` / `withMemoryConfig` / `withMemoryPressureThreshold` / `withMemoryRefreshInterval` / `withMemoryPressureCallback` / `withMemoryOomCallback` / `withMemoryEnabled` (with matching `memoryConfig` / `memoryThreshold` / `memoryRefresh` / `memoryPressure` / `memoryOom` / `memoryEnabled` aliases).

## Resetting Counters

Two reset modes are available:

- `tracker.resetCounters()` — zeroes the alloc/free counters but keeps live bytes tracking. Use this when you want a fresh window without disturbing running buffers.
- `tracker.reset()` / `tracker.wipe()` — zeroes everything. Use this only when you know no live allocation is held outside the tracker.

## Aliases

`logly.MemoryTracker` is also available as `logly.MemoryTelemetry` and `logly.MemTracker`. `logly.detectAvailableMemory` is also `logly.detectAvail` / `logly.detectFreeMemory` / `logly.getAvailableRAM`. `logly.detectCurrentMemoryUsage` is also `logly.detectRSS` / `logly.currentRSS` / `logly.processMemory`.

> [!IMPORTANT]
> `tracker.allocator()` returns a *different* allocator each call (a fresh vtable-borrowed handle). Store the handle in a single variable, do not pass it to a function that retains it past the lifetime of the tracker.
