---
title: Minimal Compression Example
description: Minimal Logly.zig compression setup using builder methods and presets.
head:
  - - meta
    - name: keywords
      content: minimal compression, compression presets, zig logging
  - - meta
    - property: og:title
      content: Minimal Compression Example | Logly.zig
---

# Minimal Compression

Builder methods and presets for common setups.

```zig
// One-liner presets
const fast = logly.CompressionConfig.fast();
const prod = logly.CompressionConfig.production();

// Explicit control
var comp = logly.Compression.explicit(allocator);
defer comp.deinit();
const compressed = try comp.compress(data);
defer allocator.free(compressed);
```

Output:

```text
Original size: 2600 bytes
Compressed size: 91 bytes
Compression ratio: 96.5%
```
