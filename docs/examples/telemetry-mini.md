---
title: Minimal Telemetry Example
description: Minimal Logly.zig telemetry setup writing spans to a file.
head:
  - - meta
    - name: keywords
      content: minimal telemetry, spans, zig logging
  - - meta
    - property: og:title
      content: Minimal Telemetry Example | Logly.zig
---

# Minimal Telemetry

File-based telemetry with a service name.

```zig
var config = logly.TelemetryConfig.file("telemetry_test.jsonl");
config.serviceName = "test-app";
config.enabled = true;
var telemetry = try logly.Telemetry.init(allocator, config);
defer telemetry.deinit();
```

Output:

```text
Telemetry exported to telemetry_test.jsonl
```
