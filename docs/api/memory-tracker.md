---
title: Memory Tracker API
description: API reference for logly.MemoryTracker, logly.MemoryReport, and OS-level memory probes.
---

# Memory Tracker API

`logly.MemoryTracker` wraps any `std.mem.Allocator` and tracks live bytes, peak bytes, allocation count, deallocation count, and live allocation count.

## Struct `MemoryTracker`

### Init

```zig
pub fn init(backing: std.mem.Allocator) MemoryTracker
pub fn create(backing: std.mem.Allocator) MemoryTracker             // alias
pub fn wrap(backing: std.mem.Allocator) MemoryTracker               // alias
pub fn initWithConfig(backing: std.mem.Allocator, memory: Config.MemoryConfig) MemoryTracker
pub fn createWithConfig(backing: std.mem.Allocator, memory: Config.MemoryConfig) MemoryTracker  // alias
pub fn wrapWithConfig(backing: std.mem.Allocator, memory: Config.MemoryConfig) MemoryTracker    // alias
```

`initWithConfig` reads the `Config.MemoryConfig` struct to set the pressure threshold, refresh interval, and per-event callbacks. The default `Config.MemoryConfig{}` matches the historical behaviour of `init`.

### Allocator Access

```zig
pub fn allocator(self: *MemoryTracker) std.mem.Allocator
```

Returns a vtable-borrowed allocator handle. Anything allocated through this handle is tracked. The handle is **not** tied to a particular `MemoryTracker` instance; treat the returned value as a thin handle, not as a long-lived allocator.

### Counters

```zig
pub fn getBytesUsed(self: *MemoryTracker) usize     // aliases: bytesUsed, used
pub fn getBytesPeak(self: *MemoryTracker) usize     // aliases: bytesPeak, peak
pub fn snapshot(self: *MemoryTracker) MemoryReport  // aliases: report, getReport
```

### Refresh OS Probes

```zig
pub fn refreshAvailableMemory(self: *MemoryTracker) void   // aliases: refreshAvail, refresh
pub fn getAvailableMemory(_: *MemoryTracker) usize         // aliases: availableMemory, avail
pub fn getCurrentMemoryUsage(_: *MemoryTracker) usize      // aliases: currentMemoryUsage, rss
```

When `setRefreshInterval(interval_ms)` is set to a non-zero value, the tracker refreshes `bytes_available` from the OS probe on every `alloc` / `resize` / `remap` at the configured cadence.

### Reset

```zig
pub fn resetCounters(self: *MemoryTracker) void  // aliases: resetStats, clearCounters
pub fn resetAll(self: *MemoryTracker) void        // aliases: reset, clear, wipe
```

### Report

```zig
pub fn report(self: *const MemoryTracker) MemoryReport  // alias: getReport
```

### Callback (per-alloc / per-free)

```zig
pub fn setCallback(self: *MemoryTracker, cb: ?*const MemoryCallback, user_data: ?*anyopaque) void
// aliases: onChange, setOnChange, setNotifyCallback
```

The callback fires while the tracker mutex is held - keep it short.

### Pressure-Event Callback

```zig
pub fn setPressureCallback(self: *MemoryTracker, cb: ?*const PressureCallback, user_data: ?*anyopaque) void
// aliases: onPressure, setOnPressure
pub fn setPressureThreshold(self: *MemoryTracker, value: f64) void   // aliases: setThreshold, threshold
pub fn getPressureThreshold(self: *MemoryTracker) f64
pub fn setRefreshInterval(self: *MemoryTracker, interval_ms: u64) void
pub fn setFireOnPressure(self: *MemoryTracker, on: bool) void        // aliases: setFireCallbackOnPressure, fireOnPressure
pub fn isPressureHigh(self: *MemoryTracker) bool
```

`isPressureHigh` is an edge detector: it returns `true` after a crossing of `bytes_used / bytes_capacity >= pressure_threshold`, and `false` again after `bytes_used` drops back below the threshold. The pressure threshold is clamped to `[0.0, 1.0]`. The `pressure_callback` fires exactly once per crossing (re-armed on free).

### OOM-Event Callback

```zig
pub fn setOomCallback(self: *MemoryTracker, cb: ?*const OomCallback, user_data: ?*anyopaque) void
// aliases: onOom, setOnOom
```

Fires when a wrapped allocation request is returned `null` by the inner allocator.

## Struct `MemoryReport`

```zig
pub const MemoryReport = struct {
    bytes_used: u64,
    bytes_peak: u64,
    live_allocations: u64,
    allocation_count: u64,
    deallocation_count: u64,
    capacity: u64,
    available_memory: u64,
    current_rss: u64,
};
```

### Helpers

```zig
pub fn isPressureHigh(self: *const MemoryReport, fraction: f64) bool
pub fn formatCompact(self: *const MemoryReport, writer: anytype) !void
pub fn formatHuman(self: *const MemoryReport, writer: anytype) !void
```

`isPressureHigh(fraction)` returns `true` when `bytes_used / available_memory >= fraction`.

## OS-Level Probes

```zig
pub fn detectAvailableMemory() u64  // aliases: detectAvail, detectFreeMemory, getAvailableRAM
pub fn detectCurrentMemoryUsage() u64 // aliases: detectRSS, currentRSS, rss, processMemory
```

`detectAvailableMemory` reads `/proc/meminfo` MemAvailable on Linux, calls `GlobalMemoryStatusEx` via direct FFI on Windows, and falls back to MemFree on the BSD family. `detectCurrentMemoryUsage` reads `/proc/self/status` VmRSS on Linux; on other operating systems it returns 0.

## Callback Types

```zig
pub const MemoryCallback = fn (
    bytes_used: usize,
    bytes_peak: usize,
    bytes_capacity: usize,
    user_data: ?*anyopaque,
) void;

pub const PressureCallback = fn (
    bytes_used: usize,
    bytes_peak: usize,
    bytes_capacity: usize,
    threshold: f64,
    user_data: ?*anyopaque,
) void;

pub const OomCallback = fn (
    requested_len: usize,
    alignment: std.mem.Alignment,
    user_data: ?*anyopaque,
) void;
```

## Aliases

Top-level aliases:

- `logly.MemoryTracker` ↔ `logly.MemoryTelemetry` ↔ `logly.MemTracker`
- `logly.MemoryReport` ↔ `logly.MemReport`
- `logly.MemoryCallback` ↔ `logly.MemCallback`
- `logly.detectAvailableMemory` ↔ `logly.detectAvail` ↔ `logly.detectFreeMemory` ↔ `logly.getAvailableRAM`
- `logly.detectCurrentMemoryUsage` ↔ `logly.detectRSS` ↔ `logly.currentRSS` ↔ `logly.rss` ↔ `logly.processMemory`

> [!TIP]
> See the [Memory Telemetry guide](../guide/memory-telemetry.md) for end-to-end usage.
>
> The tracker is also fully configurable from `Config.MemoryConfig`:
> ```zig
> const cfg = logly.Config.default()
>     .withMemoryPressureThreshold(0.85)
>     .withMemoryRefreshInterval(2_000)
>     .withMemoryPressureCallback(&on_pressure, null)
>     .withMemoryOomCallback(&on_oom, null);
> var tracker = logly.MemoryTracker.initWithConfig(gpa.allocator(), cfg.memory);
> ```
> Builders available on `Config.MemoryConfig` and `Config`:
> - `withThreshold(value)` / `withRefreshInterval(ms)` / `withEnabled(on)` / `withPressureEvents(on)`
> - `withPressureCallback(cb, ud)` / `withOomCallback(cb, ud)`
> - `Config.withMemory(...)` / `withMemoryConfig` / `withMemoryPressureThreshold` / `withMemoryRefreshInterval`
> - `Config.withMemoryPressureCallback` / `withMemoryOomCallback` / `withMemoryEnabled`
> - Aliases: `threshold`, `refreshInterval`, `pressure`, `onPressure`, `setPressureCallback`, `oom`, `onOom`, `setOomCallback`, `enable`, `disable`, `fireOnPressure`, and `Config.memoryConfig` / `memoryThreshold` / `memoryRefresh` / `memoryPressure` / `memoryOom` / `memoryEnabled`.
