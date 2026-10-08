---
title: Pipeline Controls Example
description: Tune the Logly.zig logging pipeline with async, thread pool, metrics, rotation, and scheduler controls.
head:
  - - meta
    - name: keywords
      content: pipeline controls, async, thread pool, metrics, rotation, scheduler, zig logging
  - - meta
    - property: og:title
      content: Pipeline Controls Example | Logly.zig
---

# Pipeline Controls

Builds an observability pipeline with async buffering, thread pool, Prometheus metrics, rotation, and scheduler in one config.

```zig
var config = logly.Config.default()
    .withAsync(logly.AsyncConfig.lowLatency().withBufferSize(256).withBatchSize(8))
    .withThreadPool(logly.ThreadPoolConfig.ioBound().withThreadCount(4))
    .withRotation(logly.Config.RotationConfig.daily(7).withCompression(.zstd));
var logger = try logly.Logger.initWithConfig(allocator, config);
defer logger.deinit();
```

Output:

```text
Async enabled:       yes
Thread pool enabled: yes
Async queue drained: yes
```

```text
checkout_api_records_total 2
checkout_api_errors_total 0
```
