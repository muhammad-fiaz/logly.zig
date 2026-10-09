---
title: Advanced Sink Example
description: In-memory ring sinks, atomic fan-out groups, and health plus rate limiting with Logly.zig.
head:
  - - meta
    - name: keywords
      content: advanced sink, memory sink, sink group, fan-out, rate limiting, zig logging
  - - meta
    - property: og:title
      content: Advanced Sink Example | Logly.zig
---

# Advanced Sink

In-memory ring buffer (overwrites oldest when full), `SinkGroup` atomic fan-out, health checks, and per-sink rate limiting.

```zig
// Ring buffer sink (capacity 3)
var memCfg = logly.SinkConfig.memory();
memCfg.name = "ring";
const mem = try logly.Sink.init(allocator, memCfg);
defer mem.deinit();

// Fan-out to two sinks atomically
var group = logly.SinkGroup.init(allocator);
defer group.deinit();
try group.addSink(s1);
try group.addSink(s2);
try group.write(&record, config);
```

Output:

```text
Messages written: 3. Capacity: 3.
  [0] [INFO] Message One
Writing fourth message (overflowing ring buffer)...
  [0] [INFO] Message Two
Sink 1 got: '[WARNING] Group Alert: CPU High!'
Sink 2 got: '[WARNING] Group Alert: CPU High!'
Is memory sink healthy? Yes
```
