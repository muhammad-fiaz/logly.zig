---
title: Advanced Filtering Example
description: Advanced Logly.zig filtering example covering glob rules, rate limiting, time-window rules, and batch filtering.
head:
  - - meta
    - name: keywords
      content: advanced filtering, glob rules, rate limiting, time-window filtering, batch filtering
  - - meta
    - property: og:title
      content: Advanced Filtering Example | Logly.zig
---

# Advanced Filtering

Glob matching, rate limiting, time-window rules, and batch filtering.

```zig
var filter = logly.Filter.init(allocator);
defer filter.deinit();

try filter.addGlobModule("auth.*", .allow);
try filter.addRateRule(100, .deny);

// Batch evaluation
var first = logly.Record.init(allocator, .debug, "first");
defer first.deinit();
var second = logly.Record.init(allocator, .err, "second");
defer second.deinit();
var third = logly.Record.init(allocator, .info, "third");
defer third.deinit();
const records = [_]*const logly.Record{ &first, &second, &third };
var results: [3]bool = undefined;
filter.shouldLogBatch(&records, &results);
```

Output:

```text
--- 1. Glob matching and Rate Limiting ---
--- 3. Batch Filtering API ---
Evaluating batch of 3 records...
  - Record 0 Level DEBUG: Passed: No, Reason: denied: below minimum level
  - Record 1 Level ERROR: Passed: Yes, Reason: allowed by all rules
```
