# System Diagnostics Guide

Logly provides comprehensive system diagnostics with automatic collection of OS, CPU, memory, and drive information. Diagnostics can be emitted at startup or on-demand with full color support and custom formatting.

## Quick Start

### Auto-emit at Startup

```zig
const logly = @import("logly");

var config = logly.Config.default();
config.emit_system_diagnostics_on_init = true; // Emit during init
config.include_drive_diagnostics = true;        // Include drive info
config.use_colors = true;                        // Enable colors

const logger = try logly.Logger.initWithConfig(allocator, config);
// System diagnostics are automatically logged
```

### On-Demand Emission

```zig
try logger.logSystemDiagnostics(@src());
```

## Configuration Options

### emit_system_diagnostics_on_init

Automatically emit system diagnostics when logger initializes.

```zig
config.emit_system_diagnostics_on_init = true;
```

- Emits once during logger initialization
- Useful for production logs to capture baseline system info
- Logs at `info` level

### include_drive_diagnostics

Include disk drive information in diagnostics output.

```zig
config.include_drive_diagnostics = true; // Include all drives
```

- Windows: Enumerates all logical drives (C:\, D:\, etc.)
- Linux: Includes mounted filesystems
- macOS: Includes mounted volumes
- Adds ~1-5ms latency (optional)

### use_colors

Enable color-coded output for better visibility.

```zig
config.use_colors = true;
```

- Automatically enables ANSI colors
- Windows Terminal, PowerShell, VSCode all supported
- On Windows, call `Terminal.enableAnsiColors()` first

## Enabling ANSI Colors

On Windows, enable ANSI support before using colors:

```zig
_ = logly.Terminal.enableAnsiColors();

var config = logly.Config.default();
config.use_colors = true;
const logger = try logly.Logger.initWithConfig(allocator, config);
```

This is a no-op on Linux/macOS where ANSI is always supported.

## Diagnostic Information

### Collected Data

System diagnostics include:

| Field | Type | Description | Example |
|-------|------|-------------|---------|
| `diag.os` | string | Operating system tag | "windows", "linux", "macos" |
| `diag.arch` | string | CPU architecture | "x86_64", "aarch64", "arm" |
| `diag.cpu` | string | CPU model name | "Intel Core i7-9700K" |
| `diag.cores` | integer | Logical CPU cores | 8, 16, 32 |
| `diag.ram_total_mb` | integer | Total RAM in MB | 16384, 32768 |
| `diag.ram_avail_mb` | integer | Available RAM in MB | 8192, 15000 |

### Drive Information (Windows/Linux)

When `include_drive_diagnostics = true`:

| Field | Type | Description |
|-------|------|-------------|
| Drive name | string | "C:\\", "D:\\", "/mnt/data" |
| Total bytes | integer | Drive capacity |
| Free bytes | integer | Available space |

## Custom Formatting

### Basic Custom Format

Use diagnostic context fields in format strings:

```zig
config.log_format = "[{level}] {message} | CPU={diag.cpu} Cores={diag.cores}";

try logger.logSystemDiagnostics(@src());
// Output: [INFO] System initialized | CPU=Intel Core i7-9700K Cores=8
```

### Emoji Format

Add emojis for visual appeal:

```zig
config.log_format = "🖥️  {diag.os} | 🏗️  {diag.arch} | 💻 {diag.cpu} | ⚙️  {diag.cores} cores";

try logger.logSystemDiagnostics(@src());
// Output: 🖥️  windows | 🏗️  x86_64 | 💻 Intel Core i7-9700K | ⚙️  8 cores
```

### Memory Information Format

```zig
config.log_format = "🧠 Total: {diag.ram_total_mb} MB | Available: {diag.ram_avail_mb} MB";

try logger.logSystemDiagnostics(@src());
// Output: 🧠 Total: 32768 MB | Available: 16384 MB
```

### Comprehensive Format with Timestamp

```zig
config.log_format = "[{timestamp:s}] {level:>5} | System: {diag.os}/{diag.arch} | CPU: {diag.cpu} ({diag.cores} cores) | RAM: {diag.ram_total_mb}MB";

try logger.logSystemDiagnostics(@src());
```

## Programmatic Collection

Collect diagnostics directly without a logger:

```zig
// Collect system information
var diagnostics = try logly.Diagnostics.collect(allocator, true);
defer diagnostics.deinit(allocator);

// Access fields
std.debug.print("OS: {s}\n", .{diagnostics.os_tag});
std.debug.print("Arch: {s}\n", .{diagnostics.arch});
std.debug.print("CPU: {s}\n", .{diagnostics.cpu_model});
std.debug.print("Cores: {d}\n", .{diagnostics.logical_cores});

// Memory info
if (diagnostics.total_mem) |total| {
    std.debug.print("Total RAM: {d} MB\n", .{total / (1024 * 1024)});
}

// Drive info
for (diagnostics.drives) |drive| {
    std.debug.print("Drive {s}: {d} bytes free\n", .{drive.name, drive.free_bytes});
}
```

## Platform Support

### Windows
- ✅ Full ANSI color support (requires `Terminal.enableAnsiColors()`)
- ✅ Memory information via GlobalMemoryStatusEx
- ✅ Drive enumeration via GetLogicalDriveStrings
- ✅ Works in PowerShell, Windows Terminal, VSCode

### Linux
- ✅ Full ANSI color support
- ✅ Memory information via /proc/meminfo
- ✅ Drive enumeration via /proc/mounts

### macOS
- ✅ Full ANSI color support
- ✅ Memory information via sysctl
- ✅ Drive enumeration via mount points

## Performance Considerations

### Startup Emission
- OS/CPU info: ~1ms
- Memory info: ~0.5ms
- Drive enumeration: ~1-5ms (optional)
- Total: ~2-7ms

### On-Demand Emission
- Same as startup (uses arena allocator)
- No significant performance impact

### Drive Enumeration Latency
Drive info adds ~1-5ms depending on number of volumes:

```zig
// Fast startup - skip drive info
config.include_drive_diagnostics = false;

// Full diagnostics
config.include_drive_diagnostics = true;
```

## Best Practices

### 1. Enable at Startup in Production

```zig
#if production
config.emit_system_diagnostics_on_init = true;
config.use_colors = false; // Colors not needed in file logs
#endif
```

### 2. Include Drive Info for Long-Running Services

```zig
// Useful for detecting disk space issues early
config.include_drive_diagnostics = true;
```

### 3. Custom Format for Log Aggregation

```zig
// Structured format for parsing by aggregation tools
config.log_format = "diag os={diag.os} arch={diag.arch} cpu={diag.cpu} cores={diag.cores} ram={diag.ram_total_mb}";
```

### 4. Use Colors in Development/Interactive

```zig
if (std.io.getStdIn().isTty()) {
    config.use_colors = true;
}
```

### 5. Collect Programmatically for Custom Display

```zig
var diagnostics = try logly.Diagnostics.collect(allocator, true);
defer diagnostics.deinit(allocator);

// Custom display logic
displaySystemInfo(diagnostics);
```

## Color Scheme

When colors are enabled, diagnostics output uses:

- **OS/Architecture**: Cyan (system information)
- **CPU**: Magenta (processor details)
- **Memory**: Green (resource info)
- **Drives**: Yellow (storage information)

Colors are automatically stripped when output is redirected to files.

## Examples

### Example 1: Development Setup

```zig
var config = logly.Config.default();
config.emit_system_diagnostics_on_init = true;
config.include_drive_diagnostics = true;
config.use_colors = true;
config.log_level = .debug;

_ = logly.Terminal.enableAnsiColors();
const logger = try logly.Logger.initWithConfig(allocator, config);

// Output includes full colored diagnostics at startup
```

### Example 2: Production Setup

```zig
var config = logly.Config.default();
config.emit_system_diagnostics_on_init = true;
config.include_drive_diagnostics = true;
config.use_colors = false; // Disable colors for file logging
config.log_level = .info;

const logger = try logly.Logger.initWithConfig(allocator, config);

// Output includes diagnostics in structured format, parseable by log aggregators
```

### Example 3: Monitoring Dashboard

```zig
var diagnostics = try logly.Diagnostics.collect(allocator, true);
defer diagnostics.deinit(allocator);

// Display in dashboard or monitoring tool
std.debug.print("System Health Report\n", .{});
std.debug.print("  OS: {s} ({s})\n", .{diagnostics.os_tag, diagnostics.arch});
std.debug.print("  CPU: {s} ({d} cores)\n", .{diagnostics.cpu_model, diagnostics.logical_cores});

if (diagnostics.total_mem) |total| {
    if (diagnostics.avail_mem) |avail| {
        const usage = 100.0 * (1.0 - (@as(f64, @floatFromInt(avail)) / @as(f64, @floatFromInt(total))));
        std.debug.print("  Memory: {d:.1}% used\n", .{usage});
    }
}
```

### Example 4: Conditional Diagnostics

```zig
try logger.info("Application starting", .{});

// Only include drive info on startup
if (should_include_drives) {
    try logger.logSystemDiagnostics(@src());
}

// Collect diagnostics programmatically for analysis
var diag = try logly.Diagnostics.collect(allocator, false);
defer diag.deinit(allocator);

if (isLowMemory(diag)) {
    try logger.warn("System running low on memory", .{});
}
```

## Troubleshooting

### Colors Not Showing on Windows

Ensure you call `Terminal.enableAnsiColors()` before creating the logger:

```zig
_ = logly.Terminal.enableAnsiColors();
var config = logly.Config.default();
config.use_colors = true;
```

### Drive Info Takes Too Long

If drive enumeration is slow, disable it:

```zig
config.include_drive_diagnostics = false;
```

### Memory Info Shows as Null

On non-Windows platforms, memory info may be unavailable. Check for `null`:

```zig
if (diagnostics.total_mem) |total| {
    // Use memory info
} else {
    // Fallback
}
```

### Garbled Output in File Logs

Colors in file logs appear as ANSI escape codes. Disable colors for file output:

```zig
config.use_colors = false; // Or auto-detect TTY
```

## See Also

- [Configuration Guide](configuration.md) - Full config options
- [Formatting Guide](formatting.md) - Custom format strings
- [Colors Guide](colors.md) - Color customization
- [Examples](../../examples/diagnostics.zig) - Complete working examples
