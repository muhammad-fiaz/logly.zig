---
title: Color Modes Example
description: Horizontal whole-line, vertical per-column, and disabled color modes with Logly.zig.
head:
  - - meta
    - name: keywords
      content: color modes, horizontal color, vertical color, column colors, zig logging
  - - meta
    - property: og:title
      content: Color Modes Example | Logly.zig
---

# Color Modes

Three modes: `.horizontal` colors the whole record, `.vertical` colors configured columns independently, `.none` disables.

```zig
var config = logly.Config.default();
config.colorMode = .horizontal;
var hLogger = try logly.Logger.initWithConfig(allocator, config);
defer hLogger.deinit();
try hLogger.info("Horizontal info", @src());

config.colorMode = .vertical;
config.columnColors.timestamp = logly.Color.Tint.color.ansi4.blue;
config.columnColors.message = logly.Color.Tint.color.ansi4.yellow;
var vLogger = try logly.Logger.initWithConfig(allocator, config);
defer vLogger.deinit();
try vLogger.info("Vertical info", @src());
```

Output (colors rendered by the terminal):

```text
--- Horizontal (whole line) ---
[INFO] Horizontal info
--- Vertical (timestamp blue, level default, message yellow) ---
[INFO] Vertical info
--- None (plain) ---
[INFO] Plain info
```
