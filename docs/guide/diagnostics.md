# System Diagnostics Guide

Logly provides comprehensive system diagnostics with automatic collection of OS, CPU, memory, and drive information. Diagnostics can be emitted at startup or on-demand with full color support and custom formatting.

## Quick Start

### Auto-emit at Startup

The simplest way to enable diagnostics is to have them automatically logged when your logger initializes:

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Enable ANSI colors on Windows
    _ = logly.Terminal.enableAnsiColors();

    var config = logly.Config.default();
    config.emit_system_diagnostics_on_init = true;  // Auto-emit on init
    config.include_drive_diagnostics = true;         // Include drive info
    config.color = true;                              // Enable colors

    const logger = try logly.Logger.initWithConfig(allocator, config);
    defer logger.deinit();
    
    // System diagnostics are automatically logged at INFO level
    try logger.info("Application started", @src());
}
```

**Output:**
```
[INFO] [DIAGNOSTICS] os=windows arch=x86_64 cpu=Intel(R) Core(TM) i7-9700K CPU @ 3.60GHz cores=8 ram_total=32768MB ram_available=16384MB drives=[C:\ total=931GB free=256GB; D:\ total=1863GB free=512GB]
[INFO] Application started
```

### On-Demand Emission

You can also emit diagnostics at any time during your application's lifecycle:

```zig
const logger = try logly.Logger.init(allocator);
defer logger.deinit();

// Emit diagnostics on demand
try logger.logSystemDiagnostics(@src());

// Continue with normal logging
try logger.info("After diagnostics", @src());
```

### Direct Collection

For custom processing, you can collect diagnostics directly without logging:

```zig
var diag = try logly.Diagnostics.collect(allocator, true);
defer diag.deinit(allocator);

std.debug.print("System: {s} on {s}\n", .{diag.os_tag, diag.arch});
std.debug.print("CPU: {s} ({d} cores)\n", .{diag.cpu_model, diag.logical_cores});

if (diag.total_mem) |total| {
    if (diag.avail_mem) |avail| {
        const used_mb = (total - avail) / (1024 * 1024);
        const total_mb = total / (1024 * 1024);
        std.debug.print("Memory: {d}/{d} MB ({d:.1}% used)\n", 
            .{used_mb, total_mb, (@as(f64, @floatFromInt(used_mb)) / @as(f64, @floatFromInt(total_mb))) * 100.0});
    }
}

for (diag.drives) |drive| {
    const total_gb = @as(f64, @floatFromInt(drive.total_bytes)) / (1024 * 1024 * 1024);
    const free_gb = @as(f64, @floatFromInt(drive.free_bytes)) / (1024 * 1024 * 1024);
    std.debug.print("Drive {s}: {d:.1} GB / {d:.1} GB free\n", 
        .{drive.name, free_gb, total_gb});
}
```

## Configuration Options

### emit_system_diagnostics_on_init

**Type:** `bool`  
**Default:** `false`

Automatically emit system diagnostics when the logger initializes.

```zig
config.emit_system_diagnostics_on_init = true;
```

- Emits once during `Logger.init()` or `Logger.initWithConfig()`
- Logs at `INFO` level
- Useful for production logs to capture baseline system information
- Adds ~2-7ms to initialization time (with drives)

**Best Practices:**
- Enable for production applications to track deployment environments
- Disable for high-frequency test runs to reduce noise
- Combine with structured logging to parse system info programmatically

### include_drive_diagnostics

**Type:** `bool`  
**Default:** `true`

Include disk drive information in diagnostics output.

```zig
config.include_drive_diagnostics = true;  // Include all drives
config.include_drive_diagnostics = false; // Skip drive enumeration
```

- **Windows**: Enumerates all logical drives (C:\, D:\, E:\, etc.)
- **Linux**: Includes mounted filesystems from `/proc/mounts`
- **macOS**: Enumerates mount points

**Performance:**
- Windows: Adds ~1-5ms (varies by number of drives)
- Linux: Adds ~1-2ms
- macOS: Adds ~1-2ms

**When to disable:**
- High-frequency diagnostic calls
- Containerized environments with limited drive access
- Systems with many network drives (Windows)

### color

**Type:** `bool`  
**Default:** `true`

Enable color-coded diagnostic output.

```zig
config.color = true;  // Enable ANSI colors
```

**Platform Notes:**
- **Windows**: Requires `logly.Terminal.enableAnsiColors()` call before logger init
- **Linux/macOS**: Works out of the box

**Example:**
```zig
// Enable colors on Windows
_ = logly.Terminal.enableAnsiColors();

var config = logly.Config.default();
config.color = true;

const logger = try logly.Logger.initWithConfig(allocator, config);
```

## Custom Formatting

### Using Context Fields

When diagnostics are logged, context fields are automatically populated:

```zig
config.log_format = "[{level}] {diag.os}/{diag.arch} | CPU: {diag.cpu} ({diag.cores} cores) | RAM: {diag.ram_avail_mb}/{diag.ram_total_mb} MB";
```

**Available Fields:**
- `{diag.os}` - Operating system (`windows`, `linux`, `macos`)
- `{diag.arch}` - Architecture (`x86_64`, `aarch64`)
- `{diag.cpu}` - CPU model name
- `{diag.cores}` - Logical core count
- `{diag.ram_total_mb}` - Total RAM in MB
- `{diag.ram_avail_mb}` - Available RAM in MB

**Example Output:**
```
[INFO] windows/x86_64 | CPU: Intel Core i7-9700K (8 cores) | RAM: 16384/32768 MB
```

### Table Format

For a more structured output:

```zig
config.log_format = 
\\[{level}] System Diagnostics:
\\  OS:       {diag.os}
\\  Arch:     {diag.arch}
\\  CPU:      {diag.cpu}
\\  Cores:    {diag.cores}
\\  RAM:      {diag.ram_avail_mb}/{diag.ram_total_mb} MB
;
```

## Use Cases

### 1. Production Monitoring

Track system resources in production environments:

```zig
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var config = logly.Config.default();
    config.emit_system_diagnostics_on_init = true;
    config.include_drive_diagnostics = true;
    
    const logger = try logly.Logger.initWithConfig(allocator, config);
    defer logger.deinit();

    // Application continues with system info logged
    try logger.info("Application started", @src());
    
    // Periodically re-emit to track changes
    while (app_running) {
        // ... application logic ...
        
        if (should_emit_diagnostics()) {
            try logger.logSystemDiagnostics(@src());
        }
    }
}
```

### 2. Debug Information

Collect comprehensive system info for bug reports:

```zig
fn reportBug(logger: *logly.Logger, error_msg: []const u8) !void {
    try logger.error(error_msg, @src());
    
    // Include full system diagnostics
    try logger.logSystemDiagnostics(@src());
    
    // Additional debug info
    try logger.debug("Application version: 1.0.0", @src());
    try logger.debug("Build: Release", @src());
}
```

### 3. Performance Baselines

Establish performance baselines based on system capabilities:

```zig
var diag = try logly.Diagnostics.collect(allocator, false);
defer diag.deinit(allocator);

// Adjust worker pool size based on cores
const worker_count = if (diag.logical_cores > 4) 
    diag.logical_cores - 1  // Leave one core free
else 
    diag.logical_cores;

std.debug.print("Starting {d} workers (system has {d} cores)\n", 
    .{worker_count, diag.logical_cores});
```

### 4. Health Checks

Include diagnostics in application health endpoints:

```zig
fn healthCheck(logger: *logly.Logger) !HealthStatus {
    var diag = try logly.Diagnostics.collect(allocator, true);
    defer diag.deinit(allocator);

    var status = HealthStatus{ .healthy = true };

    // Check memory availability
    if (diag.avail_mem) |avail| {
        if (diag.total_mem) |total| {
            const avail_percent = (@as(f64, @floatFromInt(avail)) / @as(f64, @floatFromInt(total))) * 100.0;
            if (avail_percent < 10.0) {
                status.healthy = false;
                try logger.warningf("Low memory: {d:.1}% available", .{avail_percent}, @src());
            }
        }
    }

    // Check drive space
    for (diag.drives) |drive| {
        const free_percent = (@as(f64, @floatFromInt(drive.free_bytes)) / @as(f64, @floatFromInt(drive.total_bytes))) * 100.0;
        if (free_percent < 5.0) {
            status.healthy = false;
            try logger.warningf("Low disk space on {s}: {d:.1}% free", .{drive.name, free_percent}, @src());
        }
    }

    return status;
}
```

### 5. Containerized Applications

Detect container environments and adjust behavior:

```zig
var diag = try logly.Diagnostics.collect(allocator, false);
defer diag.deinit(allocator);

// Check if running in a container (typically has fewer cores)
const is_container = diag.logical_cores <= 2 or 
    (diag.total_mem != null and diag.total_mem.? < 4 * 1024 * 1024 * 1024);

if (is_container) {
    std.debug.print("Detected container environment\n", .{});
    // Adjust resource usage accordingly
}
```

## Platform-Specific Examples

### Windows

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Enable Virtual Terminal Processing for colors
    _ = logly.Terminal.enableAnsiColors();

    var diag = try logly.Diagnostics.collect(allocator, true);
    defer diag.deinit(allocator);

    std.debug.print("Windows System Information:\n", .{});
    std.debug.print("  Edition: {s}\n", .{diag.os_tag});
    std.debug.print("  CPU: {s}\n", .{diag.cpu_model});
    
    if (diag.total_mem) |total| {
        if (diag.avail_mem) |avail| {
            std.debug.print("  Physical Memory: {d} MB total, {d} MB available\n",
                .{total / (1024 * 1024), avail / (1024 * 1024)});
        }
    }

    std.debug.print("\nLogical Drives:\n", .{});
    for (diag.drives) |drive| {
        const total_gb = @as(f64, @floatFromInt(drive.total_bytes)) / (1024 * 1024 * 1024);
        const free_gb = @as(f64, @floatFromInt(drive.free_bytes)) / (1024 * 1024 * 1024);
        std.debug.print("  {s} {d:.1} GB / {d:.1} GB free\n",
            .{drive.name, free_gb, total_gb});
    }
}
```

### Linux

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var diag = try logly.Diagnostics.collect(allocator, true);
    defer diag.deinit(allocator);

    std.debug.print("Linux System Information:\n", .{});
    std.debug.print("  Kernel: {s}\n", .{diag.os_tag});
    std.debug.print("  Architecture: {s}\n", .{diag.arch});
    std.debug.print("  CPU: {s}\n", .{diag.cpu_model});
    std.debug.print("  Cores: {d}\n", .{diag.logical_cores});
    
    if (diag.total_mem) |total| {
        if (diag.avail_mem) |avail| {
            std.debug.print("  Memory: {d} MB / {d} MB (from /proc/meminfo)\n",
                .{avail / (1024 * 1024), total / (1024 * 1024)});
        }
    }

    std.debug.print("\nMounted Filesystems:\n", .{});
    for (diag.drives) |drive| {
        const total_gb = @as(f64, @floatFromInt(drive.total_bytes)) / (1024 * 1024 * 1024);
        const free_gb = @as(f64, @floatFromInt(drive.free_bytes)) / (1024 * 1024 * 1024);
        std.debug.print("  {s}: {d:.1} GB / {d:.1} GB free\n",
            .{drive.name, free_gb, total_gb});
    }
}
```

### macOS

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var diag = try logly.Diagnostics.collect(allocator, true);
    defer diag.deinit(allocator);

    std.debug.print("macOS System Information:\n", .{});
    std.debug.print("  OS: {s}\n", .{diag.os_tag});
    std.debug.print("  Architecture: {s}\n", .{diag.arch});
    std.debug.print("  CPU: {s}\n", .{diag.cpu_model});
    std.debug.print("  Logical Cores: {d}\n", .{diag.logical_cores});
    
    if (diag.total_mem) |total| {
        if (diag.avail_mem) |avail| {
            std.debug.print("  Memory: {d} GB / {d} GB (via sysctl)\n",
                .{avail / (1024 * 1024 * 1024), total / (1024 * 1024 * 1024)});
        }
    }

    std.debug.print("\nMount Points:\n", .{});
    for (diag.drives) |drive| {
        const total_gb = @as(f64, @floatFromInt(drive.total_bytes)) / (1024 * 1024 * 1024);
        const free_gb = @as(f64, @floatFromInt(drive.free_bytes)) / (1024 * 1024 * 1024);
        std.debug.print("  {s}: {d:.1} GB / {d:.1} GB free\n",
            .{drive.name, free_gb, total_gb});
    }
}
```

## Performance Considerations

### Collection Overhead

Diagnostic collection has minimal overhead:

| Platform | Without Drives | With Drives | Notes |
|----------|----------------|-------------|-------|
| Windows  | ~1-2ms        | ~2-7ms      | Varies by drive count |
| Linux    | ~0.5-1ms      | ~1-3ms      | Fast file parsing |
| macOS    | ~0.5-1ms      | ~1-3ms      | Efficient syscalls |

### Best Practices

1. **Cache Results**: If collecting frequently, cache diagnostics:
   ```zig
   var cached_diag: ?Diagnostics = null;
   var last_collection: i64 = 0;
   
   fn getDiagnostics(allocator: std.mem.Allocator) !Diagnostics {
       const now = std.time.milliTimestamp();
       if (cached_diag == null or (now - last_collection) > 60000) {
           if (cached_diag) |*old| {
               old.deinit(allocator);
           }
           cached_diag = try logly.Diagnostics.collect(allocator, true);
           last_collection = now;
       }
       return cached_diag.?;
   }
   ```

2. **Disable Drives When Not Needed**: Save 1-5ms per collection:
   ```zig
   var diag = try logly.Diagnostics.collect(allocator, false);  // Skip drives
   ```

3. **Async Collection**: For web servers, collect diagnostics asynchronously:
   ```zig
   const thread = try std.Thread.spawn(.{}, collectDiagnosticsAsync, .{allocator});
   thread.detach();
   ```

## Troubleshooting

### No Memory Information (null values)

**Symptom**: `total_mem` and `avail_mem` are `null`

**Causes:**
- **Windows**: Insufficient permissions for `GlobalMemoryStatusEx`
- **Linux**: Unable to read `/proc/meminfo`
- **macOS**: `sysctl` query failed

**Solution:**
```zig
if (diag.total_mem) |total| {
    std.debug.print("Memory: {d} MB\n", .{total / (1024 * 1024)});
} else {
    std.debug.print("Memory information unavailable\n", .{});
}
```

### No Drives Listed

**Symptom**: `drives` array is empty

**Causes:**
- `include_drive_diagnostics = false` in config
- **Windows**: No logical drives found
- **Linux**: `/proc/mounts` unavailable or empty
- **macOS**: Mount point enumeration failed

**Solution:**
```zig
config.include_drive_diagnostics = true;  // Ensure enabled

if (diag.drives.len == 0) {
    std.debug.print("No drives found or enumeration disabled\n", .{});
}
```

### Colors Not Working (Windows)

**Symptom**: ANSI escape codes appear as text

**Cause**: Virtual Terminal Processing not enabled

**Solution:**
```zig
// Call BEFORE logger init
_ = logly.Terminal.enableAnsiColors();

var config = logly.Config.default();
config.color = true;
const logger = try logly.Logger.initWithConfig(allocator, config);
```

## See Also

- [Diagnostics API Reference](../api/diagnostics.md) - Complete API documentation
- [Configuration Guide](configuration.md) - All config options
- [Formatting Guide](formatting.md) - Custom format strings
- [Colors Guide](colors.md) - Color customization
- [Complete Example](../../examples/diagnostics.zig) - Working code
