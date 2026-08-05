---
title: Append/Overwrite with Rotation
description: Example of using append and overwrite write modes with file rotation in Logly.zig. Learn how different write modes interact with rotation configurations.
head:
  - - meta
    - name: keywords
      content: append mode, overwrite mode, file rotation, write modes, log rotation, daily rotation, size rotation
  - - meta
    - property: og:title
      content: Append/Overwrite with Rotation | Logly.zig
  - - meta
    - property: og:image
      content: https://muhammad-fiaz.github.io/logly.zig/cover.png
---

# Append/Overwrite with Rotation

This example demonstrates how different write modes interact with file rotation in Logly.zig.

## Write Modes

| Mode | Behavior | Use Case |
|------|----------|----------|
| `.append` | Append to existing file | Persistent logs, audit trails |
| `.overwrite` | Truncate on startup | Session logs, debug output |
| `.append_rotate` | Append with rotation trigger | Explicit rotation control |

## Code Example

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const logger = try logly.Logger.initWithConfig(allocator, logly.Config.default());
    defer logger.deinit();

    // Append mode with daily rotation
    var sink_append = logly.SinkConfig.file("app.log");
    sink_append.write_mode = .append;
    sink_append.rotation = "daily";
    sink_append.retention = 7;
    _ = try logger.addSink(sink_append);

    // Overwrite mode with size rotation
    var sink_overwrite = logly.SinkConfig.file("session.log");
    sink_overwrite.write_mode = .overwrite;
    sink_overwrite.size_limit = 1024 * 1024; // 1MB
    sink_overwrite.retention = 3;
    _ = try logger.addSink(sink_overwrite);

    try logger.info("Logged to both sinks", @src());
}
```

## How Rotation Works

After rotation, the old file is renamed (e.g., `app.log.2026-08-05`) and a new fresh file is created. This behavior is consistent across all write modes.

| Write Mode | Initial Behavior | After Rotation |
|------------|------------------|----------------|
| `.append` | Append to existing file | New file starts fresh |
| `.overwrite` | Truncate file on startup | New file starts fresh |
| `.append_rotate` | Append with rotation trigger | New file starts fresh |

## Expected Output

```
app.log              - Append mode, grows over time
app.log.2026-08-05   - Rotated daily, archived
session.log          - Overwrite mode, fresh each run
```

## See Also

- [Write Modes Guide](/guide/sinks#file-write-mode) - Full write mode documentation
- [Rotation Guide](/guide/rotation) - Rotation configuration
- [Sink Configuration](/guide/sinks) - All sink options
