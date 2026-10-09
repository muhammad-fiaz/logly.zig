---
title: Distributed JSON Example
description: Emit distributed trace context as JSON with Logly.zig trace and span IDs.
head:
  - - meta
    - name: keywords
      content: distributed json, trace id, span id, zig logging
  - - meta
    - property: og:title
      content: Distributed JSON Example | Logly.zig
---

# Distributed JSON

Single JSON record with service identity and trace context.

```zig
var logger = try logly.Logger.init(allocator);
defer logger.deinit();

try logger.setTraceContext("trace-123", "span-456");
try logger.info("Test distributed log", @src());
```

Output:

```json
{
  "timestamp": "2026-10-07 05:57:18.979",
  "level": "INFO",
  "message": "Test distributed log",
  "service": "test-service",
  "traceId": "trace-123",
  "spanId": "span-456"
}
```
