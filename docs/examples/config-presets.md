---
title: Configuration Presets Example
description: Try Logly.zig log-only, display-only, custom, and silent modes with enforced storage rules.
head:
  - - meta
    - name: keywords
      content: config presets, log-only, display-only, silent mode, zig logging
  - - meta
    - property: og:title
      content: Configuration Presets Example | Logly.zig
---

# Configuration Presets

Log-only writes files without console output. Display-only writes console and rejects file sinks with `error.FileStorageDisabled` (no stray files created). Silent rejects everything.

```zig
// Files only
const logCfg = logly.Config.logOnly();
var logLogger = try logly.Logger.initWithConfig(allocator, logCfg);
defer logLogger.deinit();
_ = try logLogger.addSink(logly.SinkConfig.file("app.log"));

// Console only
const dispCfg = logly.Config.displayOnly();
var dispLogger = try logly.Logger.initWithConfig(allocator, dispCfg);
defer dispLogger.deinit();
// Returns error.FileStorageDisabled; no file created:
_ = dispLogger.addSink(logly.SinkConfig.file("nope.log")) catch {};
```

Output:

```text
File sink correctly rejected: FileStorageDisabled (no file created)
[INFO] This message appears in console only
```
