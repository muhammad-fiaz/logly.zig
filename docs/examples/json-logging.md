---
title: JSON Logging Example
description: Structured JSON logging with Logly.zig including context, trace IDs, and stack traces.
head:
  - - meta
    - name: keywords
      content: json logging, structured logging, log context, zig logging
  - - meta
    - property: og:title
      content: JSON Logging Example | Logly.zig
---

# JSON Logging

Structured output with bound context and error stack traces.

```zig
var config = logly.Config.default();
config.format = .json;
var logger = try logly.Logger.initWithConfig(allocator, config);
defer logger.deinit();

try logger.bind("environment", .{ .string = "production" });
try logger.info("Application started", @src());
```

Output:

```json
{
  "timestamp": "2026-10-07 05:57:02.419",
  "level": "INFO",
  "message": "Application started",
  "context": {
    "environment": "production"
  }
}
```
