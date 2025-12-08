# Diagnostics Example

Emit system diagnostics at startup and on-demand, including optional per-drive storage details.

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    _ = logly.Terminal.enableAnsiColors();

    var config = logly.Config.default();
    config.emit_system_diagnostics_on_init = true;
    config.include_drive_diagnostics = true;

    const logger = try logly.Logger.initWithConfig(allocator, config);
    defer logger.deinit();

    // Startup diagnostics already logged. Emit again on demand:
    try logger.logSystemDiagnostics(@src());
}
```

## What it Logs

- OS tag, architecture, CPU model, logical cores
- Total and available RAM (MB)
- Per-drive totals/free space when `include_drive_diagnostics = true`
