# Diagnostics API

The `Diagnostics` module collects host information and formats it for logging.

> Import via `const Diagnostics = logly.Diagnostics;` (re-exported from `src/logly.zig`).

## Types

### `Diagnostics`

Fields:
- `os_tag: []const u8` — OS tag from `builtin.os.tag`.
- `arch: []const u8` — CPU architecture from `builtin.cpu.arch`.
- `cpu_model: []const u8` — Human-readable CPU model string.
- `logical_cores: usize` — Logical processor count (fallbacks to 1 if detection fails).
- `total_mem: ?u64` — Total physical memory in bytes (null if unavailable).
- `avail_mem: ?u64` — Available physical memory in bytes (null if unavailable).
- `drives: []DriveInfo` — Per-drive totals when collected.

Methods:
- `deinit(allocator)` — Frees drive name buffers and the drives slice.

### `DriveInfo`

Fields:
- `name: []const u8` — Drive name such as `"C:\\"`.
- `total_bytes: u64` — Total capacity in bytes.
- `free_bytes: u64` — Free bytes available to the caller.

## Functions

### `collect(allocator: std.mem.Allocator, include_drives: bool) !Diagnostics`

Collects diagnostics. On Windows, uses Win32 APIs for memory and drive data. On other platforms, returns OS/arch/CPU without drives. Returns a `Diagnostics` instance you must deinit with the same allocator.

```zig
const logly = @import("logly");
const Diagnostics = logly.Diagnostics;

var diag = try Diagnostics.collect(allocator, true);
defer diag.deinit(allocator);

std.debug.print("os={s} arch={s} cpu={s} cores={d}\n", .{ diag.os_tag, diag.arch, diag.cpu_model, diag.logical_cores });
```

### `Logger.logSystemDiagnostics(src: ?std.builtin.SourceLocation) !void`

Helper on `Logger` that calls `Diagnostics.collect` with the logger's scratch allocator and current config (`include_drive_diagnostics`). Logs a single `info` line summarizing the snapshot.

```zig
try logger.logSystemDiagnostics(@src());
```
