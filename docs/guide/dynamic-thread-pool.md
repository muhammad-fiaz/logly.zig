---
title: Dynamic Thread Pool
description: Auto-detect the host core count, validate thread pool sizing, and resize a running pool.
head:
  - - meta
    - name: keywords
      content: logly, zig, thread pool, auto-detect, dynamic sizing, worker callback
---

# Dynamic Thread Pool

`logly.ThreadPool` now auto-detects the host's recommended thread count, validates requested counts against the host's hardware cores, and supports resizing a running pool.

## Auto-Detection

Pass `0` to ask the pool to pick a thread count for you:

```zig
const logly = @import("logly");

const pool = try logly.ThreadPool.initWithConfig(.{
    .thread_count = 0, // auto-detect
});
defer pool.deinit();
```

The detected count is recorded in `pool.config.thread_count` and is observable through `pool.numWorkers()` / `pool.workerTotal()`.

## Validation

Requesting more workers than the host can schedule in parallel is rejected with `error.ThreadCountExceedsCores`:

```zig
const max = logly.ThreadPool.getMaxThreads();
std.debug.print("max threads on this host: {d}\n", .{max});

const pool = logly.ThreadPool.initWithConfig(.{
    .thread_count = max + 1,
}) catch |err| {
    std.log.warn("rejected: {s}", .{@errorName(err)});
    return;
};
```

> [!WARNING]
> The `ThreadPool` rejects `thread_count` values larger than the host's hardware cores with `error.ThreadCountExceedsCores` and a `std.log.warn` (which is captured by your active logger when wired to `logly.stdLogFn`).

## Resizing

```zig
const pool = try logly.ThreadPool.initWithConfig(.{ .thread_count = 4 });
defer pool.deinit();
_ = pool.start();

try pool.setThreadCount(8); // up
try pool.setThreadCount(2); // down
```

Resizing is bounded by the same hardware limit.

## Worker Callbacks

```zig
fn onStart(user_data: *anyopaque) void {
    _ = user_data;
    std.debug.print("worker started\n", .{});
}

fn onStop(user_data: *anyopaque) void {
    _ = user_data;
    std.debug.print("worker stopped\n", .{});
}

pool.setOnWorkerStart(.{ .user_data = null, .fn = onStart });
pool.setOnWorkerStop(.{ .user_data = null, .fn = onStop });
```

## Submit & Wait

```zig
const counter = std.atomic.Value(u32).init(0);

const work = try pool.submitBatch(&[_]fn (*anyopaque) void{
    incrementCounter, incrementCounter, incrementCounter, incrementCounter,
}, &counter);

try work.waitAll();
```

> [!TIP]
> `submitBatch` accepts an array of task functions and a shared `*anyopaque`. Each function is invoked exactly once. `waitAll` blocks the calling thread until every task has completed.

## Aliases

`logly.ThreadPool` is also reachable through `createWithConfig` / `open` (init alias), `maxHardwareThreads` / `detectCores` / `hardwareCores` (max thread queries), `isActive` / `started` (state), `workerTotal` (size), `loadFactor` / `load` (utilization), and `clearStats` / `zeroStats` (reset stats).
