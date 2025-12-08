# System Diagnostics

Logly can emit a snapshot of host information (OS, CPU model, logical cores, memory totals, and optional per-drive storage) when the logger starts or on-demand. Diagnostics data is stored in structured format for custom formatting.

## Enabling at Startup

```zig
const logly = @import("logly");

var cfg = logly.Config.default();
cfg.emit_system_diagnostics_on_init = true; // emit once during init
cfg.include_drive_diagnostics = true;      // include per-drive totals and free space

const logger = try logly.Logger.initWithConfig(allocator, cfg);
// diagnostics are logged immediately
```

## Emit On-Demand

Use the `logSystemDiagnostics` helper to capture diagnostics at any point in your program.

```zig
try logger.logSystemDiagnostics(@src());
```

- The helper respects `config.include_drive_diagnostics`.
- Uses the logger's scratch allocator (arena-aware) to avoid heap churn.
- Logs at `info` level with structured context data.

## Structured Context Fields

When diagnostics are logged, the following fields are stored in the Record context and available for custom format strings:

- `diag.os` — Operating system tag (e.g., "windows", "linux", "macos")
- `diag.arch` — CPU architecture (e.g., "x86_64", "aarch64")
- `diag.cpu` — CPU model name
- `diag.cores` — Logical core count (integer)
- `diag.ram_total_mb` — Total RAM in MB (integer)
- `diag.ram_avail_mb` — Available RAM in MB (integer)

## Custom Format Example

```zig
var config = logly.Config.default();
config.log_format = "[{level}] {message} | CPU={diag.cpu} Cores={diag.cores}";

const logger = try logly.Logger.initWithConfig(allocator, config);
try logger.logSystemDiagnostics(@src());
```

## Platform Support

- **Windows**: Supports ANSI colors via Virtual Terminal Processing (requires `Terminal.enableAnsiColors()`)
- **Linux**: Full ANSI support
- **macOS**: Full ANSI support
- **Terminal Compatibility**: Works in PowerShell, Windows Terminal, VSCode, iTerm, and standard terminals

## When to Disable Drive Stats

Drive enumeration can take a few milliseconds on Windows if many volumes exist. Set `include_drive_diagnostics = false` when:

- Running inside container images with ephemeral storage.
- You only need OS/CPU/memory details.
- Startup latency is critical and you prefer to collect drives later.

## Tips

- Enable diagnostics on startup in production to capture baseline system info in early logs.
- Use custom format strings to structure diagnostic data for log aggregation systems.
- Combine with update checker output to spot outdated binaries alongside system data.
- Integrate with thread pool and metrics for comprehensive observability.

