---
title: Sink Write Modes Example
description: Compare Logly.zig sink write modes append, overwrite, and append-rotate with rotation.
head:
  - - meta
    - name: keywords
      content: sink write modes, append, overwrite, rotation, zig logging
  - - meta
    - property: og:title
      content: Sink Write Modes Example | Logly.zig
---

# Sink Write Modes

`.append` grows the file, `.overwrite` truncates on startup, `.appendRotate` appends with rotation triggers. JSON sinks respect the mode too.

```zig
_ = try logger.addSink(.{ .path = "logs/app.log", .writeMode = .append });
_ = try logger.addSink(.{ .path = "logs/session.log", .writeMode = .overwrite });
```

Resulting files:

```text
logs/
├── append_mode.log      (growing file)
├── overwrite_mode.log   (fresh each run)
├── persistent.log       (all history)
├── session.log          (current run only)
└── logs.json            (JSON array)
```
