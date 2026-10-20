---
title: Memory-Mapped (mmap) Sinks
description: Configure memory-mapped file sinks for high-throughput logging.
---

# Memory-Mapped (mmap) Sinks

For high-throughput loggers, a `write`/`WriteFile` syscall per record adds context-switch and call overhead. **Memory-mapped (mmap) sinks** map the log file into the process address space so records can be copied into mapped pages with ordinary memory stores. The OS flushes dirty pages to disk asynchronously. Unlike a standard write path, no syscall is issued per record; bytes are still copied from the logger buffer into the mapping.

---

## Architectural Performance Comparison

### Standard File Write (Heavy Syscall Overhead)
```
[User Space]  Logger Buffer --(alloc/copy)--> File Handle Buffer
                                                     |
                                              (syscall write())
                                                     v
[Kernel Space]                          OS Page Cache -> Disk Controller
```

### Memory-Mapped Write (No Per-Record Syscall)
```
[User Space]  Logger Buffer --(memcpy)--> Mapped Page (RAM)
                                                |
                                         (flushed by OS)
                                                v
[Kernel Space]                            Filesystem -> Disk
```

With `mmap`:
1. **No Write Syscall per Record**: The write path becomes a memory copy into mapped pages.
2. **One Copy**: Bytes move from the logger buffer into the page cache; mmap avoids a separate kernel copy at a syscall boundary.
3. **OS-Managed Flushing**: The OS writes dirty pages to disk asynchronously. Call `flush()` when a record must be durable before proceeding.

---

## Usage Guide

To use memory-mapped writing, set `mmap = true` on your file sink configuration. Logly handles all platform-specific details automatically using Win32 API (`CreateFileMapping`, `MapViewOfFile`) on Windows, and POSIX (`mmap`, `munmap`) on Linux and macOS.

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const logger = try logly.Logger.init(allocator);
    defer logger.deinit();

    // Create a memory-mapped file sink config
    var sinkConfig = logly.SinkConfig.file("logs/performance.log");
    sinkConfig.name = "mmap_perf_sink";
    sinkConfig.mmap = true; // [!code hl] // Enable memory mapping!

    // Add the sink to the logger
     _ = try logger.addSink(sinkConfig);

    try logger.info("High performance log using virtual memory-mapping!", @src());
    try logger.flush();
}
```

---

## Internal Management & Resilience

### Dynamic Pre-sizing & Growth
When a memory-mapped sink is initialized, it maps an initial capacity derived from `Constants.SizeConstants.mmap_default_size` and grows the mapping when needed.
If your logs exceed this pre-allocated capacity, Logly's mmap sink automatically:
1. Doubles the file mapping capacity.
2. Re-maps the virtual memory pages.
3. Continues writing without losing records or crashing the application.

### Graceful Truncation
Because virtual memory maps are pre-allocated in chunks, the file on disk will naturally be larger than the actual written log content.
During shutdown (`deinit` or `close`), Logly automatically **truncates** the physical file down to the exact byte offset of the last written character, ensuring your log files take up only the space they actually need.

---

## Configuration Settings

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `mmap` | `bool` | `false` | Master switch to enable memory-mapped file writes on this sink. |

---

## Best Practices & Caveats

> [!WARNING]
> Data written through `mmap` is not durable until the OS flushes the affected pages. If the machine loses power before a flush, recent pages can be lost.

* **Use for High-Throughput**: Prefer `mmap` for telemetry, debug logs, metrics, and high-frequency trace logs where write speed is critical.
* **Combine with Async**: Combine `mmap` sinks with `AsyncLogger` to move formatting and writing off the calling thread.
* **Regular Flushes**: Call `logger.flush()` or set up an auto-flush timer if you have periods of low log activity, which forces the OS to synchronize dirty pages (`msync` / `FlushViewOfFile`) to physical storage.
