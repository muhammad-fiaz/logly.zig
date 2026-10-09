---
title: Rotation Helpers Example
description: Preview rotation paths, schedules, and dry-run checks with Logly.zig rotation helpers.
head:
  - - meta
    - name: keywords
      content: rotation helpers, log rotation preview, zig logging
  - - meta
    - property: og:title
      content: Rotation Helpers Example | Logly.zig
---

# Rotation Helpers

Dry-run rotation checks without touching production files.

```zig
var rotation = try logly.Rotation.init(allocator, "logs/app.log", "hourly", null, 7);
defer rotation.deinit();

if (rotation.nextRotationAt()) |at| {
    std.debug.print("Next rotation at: {d}\n", .{at});
}
// shouldRotate(&file) previews without rotating
// previewNextPath() shows the destination name
```

Output:

```text
Next rotation at: 1791352377
Last rotation age: 0s
```
