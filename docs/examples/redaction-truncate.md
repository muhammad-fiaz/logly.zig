---
title: Redaction Truncate Example
description: Truncate sensitive values to a fixed length with Logly.zig redaction.
head:
  - - meta
    - name: keywords
      content: redaction truncate, sensitive data, zig logging
  - - meta
    - property: og:title
      content: Redaction Truncate Example | Logly.zig
---

# Redaction Truncate

Truncates token values to 4 chars plus `...`.

```zig
var redactor = logly.Redactor.init(allocator);
defer redactor.deinit();

redactor.config.truncateLength = 4;
redactor.config.truncateSuffix = "...";
try redactor.addField("token", .truncate);

const redacted = try redactor.redactField("token", "abcdef");
defer allocator.free(redacted);
// redacted == "abcd..."
```

Output:

```text
Truncated: supersec...
Hashed: [HASH:d5b9ce540d31f2d3]
```
