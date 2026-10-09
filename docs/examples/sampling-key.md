---
title: Key-Based Sampling Example
description: Deterministic per-key sampling with Logly.zig so the same IDs always sample the same way.
head:
  - - meta
    - name: keywords
      content: key sampling, deterministic sampling, user sampling, zig logging
  - - meta
    - property: og:title
      content: Key-Based Sampling Example | Logly.zig
---

# Key-Based Sampling

`shouldSampleKey` hashes the key, so `user-123` always gets the same decision.

```zig
var sampler = logly.Sampler.init(allocator, .{ .probability = 0.2 });
defer sampler.deinit();

for (users) |user| {
    if (sampler.shouldSampleKey(user)) {
        try logger.info("sampled", @src());
    }
}
```

Output:

```text
user-123: skip
user-456: skip
user-789: skip
```
