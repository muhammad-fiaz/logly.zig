---
title: Styled Terminal UI Formatter
description: Learn how to enable Logly's premium real-time styled Terminal UI console cards for local development and debugging.
---

# Styled Terminal UI Formatter

Standard log outputs in development consoles are usually linear, scrolling streams of text. While colors can help, scanning through highly structured, multi-field log records with nested contexts, error stacks, and execution details can quickly become a challenge.

Logly addresses this by introducing a premium **Terminal UI (TUI) Dashboard Formatter**. Designed explicitly to enhance local development, the TUI formatter converts structured log records into gorgeous, self-contained **Console Cards**. These cards feature dynamic borders, color-coded level badges, structured metadata tables, and real-time execution statistics.

---

## Interactive Card Layout

When TUI mode is enabled, standard log output is formatted as an elegant, styled card:

```
┌─────────────────────────────────[ WARNING ]─────────────────────────────────┐
│ Time: 2026-05-24 10:45:12.388                                               │
│ Module: sys.monitor             File: monitor.zig:88                        │
│ Message: High memory utilisation detected                                   │
├──────────────────────────────[ Record Context ]─────────────────────────────┤
│ • host: prod-node-01                                                        │
│ • mem_used_pct: 87.40                                                       │
│ • pid: 1234                                                                 │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Enabling Terminal UI Formatting

To enable the TUI formatter, set `tui = true` in your logger's configuration:

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Enable TUI formatting
    var config = logly.Config.default();
    config.tui = true; // [!code hl] // Enable interactive CLI cards!
    config.json = false;

    const logger = try logly.Logger.initWithConfig(allocator, config);
    defer logger.deinit();

    // Bind some structured context fields
    try logger.bind("pid", .{ .integer = 1234 });
    try logger.bind("host", .{ .string = "dev-workstation" });

    try logger.warning("High CPU consumption detected on local thread.", @src());
    try logger.flush();
}
```

---

## API Reference

### Manual TUI Formatting

You can manually format a record into a TUI console card string using `formatTuiWithAllocator`:

```zig
const record = logly.Record.init(allocator, .warning, "Disk threshold reached");
defer record.deinit();

var formatter = logly.Formatter.init(allocator);
defer formatter.deinit();

const card_string = try formatter.formatTuiWithAllocator(&record, allocator);
defer allocator.free(card_string);

std.debug.print("{s}\n", .{card_string});
```

---

## Best Practices & Customization

> [!IMPORTANT]
> The TUI formatter uses standard ANSI escape codes for border colors, text effects, and badges. While it works beautifully on Linux, macOS, and Windows 10/11 Terminal, you should disable colors or TUI formatting when redirecting output to standard files to avoid polluting logs with raw ANSI codes.

* **Development Only**: Keep TUI enabled for your `Config.development()` profile, and turn it off in production (`Config.production()`) where text/JSON formats are required.
* **ANSI Color Check**: On Windows, ensure you call `_ = logly.Terminal.enableAnsiColors()` during initialization to guarantee borders and badges render correctly.
* **Exclude Sinks**: Do not attach the TUI formatter to persistent file sinks. Use standard, flat log formatting for files to ensure they remain easy to parse with `grep` or standard log tools.
