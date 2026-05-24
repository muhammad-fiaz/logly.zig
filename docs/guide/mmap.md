---
title: Memory-Mapped (mmap) Sinks
description: Explore Logly's ultra-high-performance memory-mapped file sinks for zero-copy, microsecond-latency disk writes.
---

# Memory-Mapped (mmap) Sinks

For high-throughput structured loggers, the primary performance bottleneck is the physical cost of filesystem write system calls (`write()`, `pwrite()`, or standard Win32 `WriteFile`). System calls force context switches between user space and kernel space, adding significant overhead and cache disruption under heavy loads.

Logly addresses this by introducing portable **Memory-Mapped (mmap) Sinks**. By mapping a log file directly into the virtual address space of the process, Logly can perform zero-copy, microsecond-latency writes directly to RAM. The operating system's virtual memory subsystem handles flushing these dirty pages to physical disk asynchronously in the background.

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

### Memory-Mapped Write (Zero-Copy Virtual Memory)
```
[User Space]  Logger Buffer --(direct memory write)--> Virtual Memory Pointer (RAM)
                                                             |
                                                      (flushed by OS page system)
                                                             v
[Kernel Space]                                           Disk Controller
```

By switching to `mmap`:
1. **Context Switches Are Eliminated**: Writing logs becomes a standard memory write (`memcpy`), which is orders of magnitude faster than a system call.
2. **True Zero-Copy**: Data goes directly to virtual memory without passing through intermediate userspace buffers.
3. **OS-Managed Durability**: The OS writes pages to disk asynchronously, optimizing hardware I/O scheduling.

---

## Usage Guide

To use memory-mapped writing, you simply set `mmap = true` on your file sink configuration. Logly handles all platform-specific details automatically using Win32 API (`CreateFileMapping`, `MapViewOfFile`) on Windows, and POSIX (`mmap`, `munmap`) on Linux and macOS.

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
    var sink_config = logly.SinkConfig.file("logs/performance.log");
    sink_config.name = "mmap_perf_sink";
    sink_config.mmap = true; // [!code hl] // Enable memory mapping!

    // Add the sink to the logger
    _ = try logger.addSink(sink_config);

    try logger.info("High performance log using virtual memory-mapping!", @src());
    try logger.flush();
}
```

---

## Internal Management & Resilience

### Dynamic Pre-sizing & Growth
When a memory-mapped sink is initialized, it maps a chunk of memory representing a default pre-allocated capacity (configured via `Constants.SizeConstants.mmap_default_size`). 
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
| `mmap_default_size` | `usize` | `10MB` | Initial virtual memory allocation block size. Sourced from `Constants`. |

---

## Best Practices & Caveats

> [!WARNING]
> While `mmap` logging offers unrivaled performance, it is vital to know that if the physical machine suddenly loses power (e.g., hard plug pull), the final pages held in virtual RAM that were not yet flushed to physical disk by the OS could be lost.

* **Use for High-Throughput**: Prefer `mmap` for telemetry, debug logs, metrics, and high-frequency trace logs where write speed is critical.
* **Combine with Async**: Combine `mmap` sinks with Logly's `AsyncLogger` to offload formatting and writing, achieving microsecond latency.
* **Regular Flushes**: Call `logger.flush()` or set up an auto-flush timer if you have periods of low log activity, which forces the OS to synchronize dirty pages (`msync` / `FlushViewOfFile`) to physical storage.
