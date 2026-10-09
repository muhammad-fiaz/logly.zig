---
title: Telemetry Metric Names Example
description: Export Logly.zig telemetry metric names with prefixing and sanitization.
head:
  - - meta
    - name: keywords
      content: telemetry metric names, prometheus, sanitization, zig logging
  - - meta
    - property: og:title
      content: Telemetry Metric Names Example | Logly.zig
---

# Telemetry Metric Names

Prefixing (`api.v1` → `api_v1`) plus sanitization for Prometheus.

```zig
var config = logly.TelemetryConfig.development()
    .withPrometheusMetrics(path)
    .withMetricPrefix("api.v1");
```

Output:

```text
Telemetry metric names exported to telemetry_metric_names.prom
Sanitized examples:
  api.v1:http.requests-total -> api_v1:http_requests_total
```
