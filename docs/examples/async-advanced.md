---
title: Advanced Async Logging Example
description: Deep dive into Logly.zig async logging with ring buffers, overflow policies, and throughput tuning.
head:
  - - meta
    - name: keywords
      content: async logging, ring buffer, overflow policy, background worker, zig logging
  - - meta
    - property: og:title
      content: Advanced Async Logging Example | Logly.zig
---

# Advanced Async Logging

`AsyncLogger` presets plus ring buffer operations and overflow policies.

```zig
const highThroughput = logly.AsyncPresets.highThroughput();
const lowLatency = logly.AsyncPresets.lowLatency();
const balanced = logly.AsyncPresets.balanced();
const noDrop = logly.AsyncPresets.noDrop();

var logger = try logly.AsyncLogger.initWithConfig(allocator, highThroughput);
defer logger.deinit();

_ = logger.queue("message", 1);
logger.flushSync();
_ = logger.waitUntilDrainedDefault();
```

Output:

```text
Buffer size: 65536
Records queued: 1000
Records written: 990
Drop rate: 1.00%
Async queue drained: yes
```

Overflow policies: `dropOldest` removes old entries, `dropNewest` drops new ones, `block` waits for space.
