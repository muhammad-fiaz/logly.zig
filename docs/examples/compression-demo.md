---
title: Compression Demo Example
description: Compare all Logly.zig compression algorithms side by side with ratios and roundtrips.
head:
  - - meta
    - name: keywords
      content: compression demo, deflate, gzip, zstd, brotli, lzma, xz, zip, lz4, zig logging
  - - meta
    - property: og:title
      content: Compression Demo Example | Logly.zig
---

# Compression Demo

Compares deflate, gzip, zstd, brotli, lzma, lzma2, xz, zip, tar.gz, and lz4 on 25KB of log data.

```zig
var comp = logly.Compression.init(allocator);
defer comp.deinit();

comp.config.algorithm = .zstd;
const compressed = try comp.compress(data);
defer allocator.free(compressed);

const decompressed = try comp.decompress(compressed);
defer allocator.free(decompressed);
```

Output:

```text
Original:    25300 bytes
Zstd compressed: 380 bytes
Saved:       98.5%
Roundtrip:   [OK]
Brotli: 1260 -> 62 bytes ([OK])
```

Compressed files land in `logs/` (e.g. `app_zstd.log.zst`, `app_brotli.log.br`). Binary output is not shown; the roundtrip integrity check confirms correctness.
