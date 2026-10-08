---
title: Memory-Mapped Sink Example
description: High-performance logging with Logly.zig memory-mapped file sinks.
head:
  - - meta
    - name: keywords
      content: mmap sink, memory mapped logging, high performance logging, zig logging
  - - meta
    - property: og:title
      content: Memory-Mapped Sink Example | Logly.zig
---

# Memory-Mapped Sink

Writes 100 records through an `mmap` file sink. See the [mmap guide](../guide/mmap.md) for platform notes (not universally available; falls back to regular writes).

```zig
var sinkCfg = logly.SinkConfig.file("mmap_example.log");
sinkCfg.mmap = true;
sinkCfg.asyncWrite = false;
_ = try logger.addSink(sinkCfg);
```

Output:

```text
[mmap] Writing 100 log records via memory-mapped sink...
[mmap] Completed. Log written to: mmap_example.log
```

File preview (`mmap_example.log`):

```text
[INFO] mmap record #0: high-performance write
[INFO] mmap record #1: high-performance write
```
