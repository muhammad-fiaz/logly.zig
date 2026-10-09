---
title: Telemetry Metrics Export Example
description: Export Logly.zig telemetry metrics to a JSONL file.
head:
  - - meta
    - name: keywords
      content: telemetry metrics export, jsonl, zig logging
  - - meta
    - property: og:title
      content: Telemetry Metrics Export Example | Logly.zig
---

# Telemetry Metrics Export

Writes metrics as JSON lines.

```zig
var config = logly.TelemetryConfig.development();
config.metricFormat = .json;
config.metricsFilePath = "telemetry_metrics.jsonl";
var telemetry = try logly.Telemetry.init(allocator, config);
defer telemetry.deinit();
```

Output:

```text
Metrics exported to telemetry_metrics.jsonl
```

File preview (`telemetry_metrics.jsonl` — one JSON object per line):

```json
{ "name": "http.request.duration", "value": 12.5, "kind": "histogram" }
```
