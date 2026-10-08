---
title: Color Options Example
description: Control Logly.zig colors globally, per sink, and per output type with tint.zig styling.
head:
  - - meta
    - name: keywords
      content: log colors, color control, ansi colors, tint colors, zig logging
  - - meta
    - property: og:title
      content: Color Options Example | Logly.zig
---

# Color Options

Global toggles, per-sink control, and auto-detection. All colors render through tint.zig.

```zig
// Disable globally
var config = logly.Config.default();
config.globalColorDisplay = false;
logger.configure(config);

// Per-sink: colors on console, off in files
_ = try logger.addSink(.{ .color = true });
_ = try logger.addSink(.{ .path = "logs/app.log", .color = false });

// Force colors in a file (for ANSI viewers)
_ = try logger.addSink(.{ .path = "logs/colored.log", .color = true });
```

Output (colors rendered by the terminal):

```text
[INFO] Info message (with color)
[ERROR] Error message (with color)
```

JSON output disables colors automatically for parsability.
