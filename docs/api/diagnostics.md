# Diagnostics API Reference

The `Diagnostics` module collects comprehensive host information including OS, CPU, memory, and storage details for logging and monitoring.

## Overview

Diagnostics provides:
- **OS Information**: Operating system and architecture detection
- **CPU Details**: Model name and logical core count
- **Memory Stats**: Total and available physical memory
- **Drive Information**: Capacity and free space for all drives (Windows/Linux)
- **Structured Output**: Context fields for custom formatting
- **Cross-Platform**: Works on Windows, Linux, and macOS

## Core Types

### Diagnostics

Complete system information snapshot.

```zig
pub const Diagnostics = struct {
    os_tag: []const u8,           // OS tag from builtin (e.g., "windows")
    arch: []const u8,              // CPU architecture (e.g., "x86_64")
    cpu_model: []const u8,         // Human-readable CPU model name
    logical_cores: usize,          // Number of logical CPU cores
    total_mem: ?u64,               // Total physical memory in bytes (null if unavailable)
    avail_mem: ?u64,               // Available physical memory in bytes (null if unavailable)
    drives: []DriveInfo,           // Array of drive information
    
    pub fn deinit(self: *Diagnostics, allocator: std.mem.Allocator) void;
};
```

**Fields:**

| Field | Type | Description | Platform |
|-------|------|-------------|----------|
| `os_tag` | `[]const u8` | Operating system tag | All |
| `arch` | `[]const u8` | CPU architecture | All |
| `cpu_model` | `[]const u8` | Processor model name | All |
| `logical_cores` | `usize` | Logical processor count | All |
| `total_mem` | `?u64` | Total RAM in bytes | All platforms |
| `avail_mem` | `?u64` | Available RAM in bytes | All platforms |
| `drives` | `[]DriveInfo` | Drive information | Windows/Linux |

**Examples:**

```zig
std.debug.print("OS: {s}\n", .{diag.os_tag});           // Output: "windows"
std.debug.print("Arch: {s}\n", .{diag.arch});           // Output: "x86_64"
std.debug.print("CPU: {s}\n", .{diag.cpu_model});       // Output: "Intel Core i7-9700K"
std.debug.print("Cores: {d}\n", .{diag.logical_cores}); // Output: 8

if (diag.total_mem) |total| {
    std.debug.print("Total RAM: {d} MB\n", .{total / (1024 * 1024)});
}

if (diag.avail_mem) |avail| {
    std.debug.print("Available RAM: {d} MB\n", .{avail / (1024 * 1024)});
}
```

### DriveInfo

Information about a single drive or volume.

```zig
pub const DriveInfo = struct {
    name: []const u8,        // Drive name (e.g., "C:\" or "/mnt/data")
    total_bytes: u64,        // Total capacity in bytes
    free_bytes: u64,         // Free bytes available
};
```

**Fields:**

| Field | Type | Description |
|-------|------|-------------|
| `name` | `[]const u8` | Drive identifier (path or letter) |
| `total_bytes` | `u64` | Total capacity in bytes |
| `free_bytes` | `u64` | Available space in bytes |

**Examples:**

```zig
for (diag.drives) |drive| {
    const total_gb = @as(f64, @floatFromInt(drive.total_bytes)) / (1024 * 1024 * 1024);
    const free_gb = @as(f64, @floatFromInt(drive.free_bytes)) / (1024 * 1024 * 1024);
    const used_percent = 100.0 - (free_gb / total_gb * 100.0);
    
    std.debug.print("{s}: {d:.1} GB total, {d:.1} GB free ({d:.1}% used)\n", 
        .{drive.name, total_gb, free_gb, used_percent});
}
```

## Functions

### collect()

Collects system diagnostics information.

```zig
pub fn collect(allocator: std.mem.Allocator, include_drives: bool) !Diagnostics
```

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `allocator` | `std.mem.Allocator` | Memory allocator for diagnostic data (must call `deinit()` to free) |
| `include_drives` | `bool` | Include drive enumeration (adds ~1-5ms on Windows) |

**Returns:** `Diagnostics` struct with collected information

**Errors:** 
- `error.OutOfMemory` - If allocation fails

**Behavior:**
- **Windows**: Uses Win32 APIs (`GlobalMemoryStatusEx`, `GetLogicalDriveStrings`, `GetDiskFreeSpaceEx`)
- **Linux**: Parses `/proc/meminfo` for memory, `/proc/mounts` for drives
- **macOS**: Uses `sysctl` for memory information

**Example:**

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Collect diagnostics with drive information
    var diag = try logly.Diagnostics.collect(allocator, true);
    defer diag.deinit(allocator);
    
    std.debug.print("System Information:\n", .{});
    std.debug.print("  OS: {s}\n", .{diag.os_tag});
    std.debug.print("  Architecture: {s}\n", .{diag.arch});
    std.debug.print("  CPU: {s}\n", .{diag.cpu_model});
    std.debug.print("  Cores: {d}\n", .{diag.logical_cores});
    
    if (diag.total_mem) |total| {
        if (diag.avail_mem) |avail| {
            std.debug.print("  Memory: {d} MB / {d} MB\n", 
                .{avail / (1024 * 1024), total / (1024 * 1024)});
        }
    }
    
    std.debug.print("\nDrives:\n", .{});
    for (diag.drives) |drive| {
        const total_gb = @as(f64, @floatFromInt(drive.total_bytes)) / (1024 * 1024 * 1024);
        const free_gb = @as(f64, @floatFromInt(drive.free_bytes)) / (1024 * 1024 * 1024);
        std.debug.print("  {s}: {d:.1} GB total, {d:.1} GB free\n", 
            .{drive.name, total_gb, free_gb});
    }
}
```

### deinit()

Frees allocated memory for diagnostics data.

```zig
pub fn deinit(self: *Diagnostics, allocator: std.mem.Allocator) void
```

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `self` | `*Diagnostics` | The Diagnostics struct to deinitialize |
| `allocator` | `std.mem.Allocator` | The same allocator used in `collect()` |

**Example:**

```zig
var diag = try logly.Diagnostics.collect(allocator, true);
defer diag.deinit(allocator);  // Always call deinit to free memory
```

## Logger Integration

### logSystemDiagnostics()

Logger helper method that collects and logs diagnostics.

```zig
pub fn logSystemDiagnostics(self: *Logger, src: ?std.builtin.SourceLocation) !void
```

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `self` | `*Logger` | Logger instance |
| `src` | `?std.builtin.SourceLocation` | Source location (typically `@src()`) |

**Example:**

```zig
const logger = try logly.Logger.init(allocator);
defer logger.deinit();

// Log system diagnostics
try logger.logSystemDiagnostics(@src());
```

**Output Example:**

```
[INFO] [DIAGNOSTICS] os=windows arch=x86_64 cpu=Intel(R) Core(TM) i7-9700K CPU @ 3.60GHz cores=8 ram_total=32768MB ram_available=16384MB drives=[C:\ total=931GB free=256GB; D:\ total=1863GB free=512GB]
```

## Context Fields

When diagnostics are logged via `logSystemDiagnostics()`, the following fields are available in the log record context for custom formatting:

| Field | Type | Description | Example Value |
|-------|------|-------------|---------------|
| `diag.os` | string | OS tag | `"windows"`, `"linux"`, `"macos"` |
| `diag.arch` | string | CPU architecture | `"x86_64"`, `"aarch64"` |
| `diag.cpu` | string | CPU model name | `"Intel Core i7-9700K"` |
| `diag.cores` | integer | Logical cores | `8`, `16` |
| `diag.ram_total_mb` | integer | Total RAM in MB | `32768` |
| `diag.ram_avail_mb` | integer | Available RAM in MB | `16384` |

**Custom Format Example:**

```zig
config.log_format = "[{level}] System: {diag.os}/{diag.arch} | CPU: {diag.cpu} ({diag.cores} cores) | RAM: {diag.ram_avail_mb}/{diag.ram_total_mb} MB";
```

## Configuration Options

### emit_system_diagnostics_on_init

Automatically emit diagnostics when logger initializes.

```zig
config.emit_system_diagnostics_on_init = true;  // Default: false
```

**Type:** `bool`  
**Default:** `false`  
**Effect:** Emits diagnostics at INFO level during `Logger.init()` or `Logger.initWithConfig()`

### include_drive_diagnostics

Include drive/volume information in diagnostics collection.

```zig
config.include_drive_diagnostics = true;  // Default: true
```

**Type:** `bool`  
**Default:** `true`  
**Effect:** Adds drive enumeration to diagnostics output (adds 1-5ms on Windows)

### color

Enable color-coded diagnostic output.

```zig
config.color = true;  // Default: true
```

**Type:** `bool`  
**Default:** `true`  
**Effect:** Enables ANSI color codes in diagnostic output

**Note:** On Windows, requires calling `logly.Terminal.enableAnsiColors()` first.

## Platform-Specific Behavior

### Windows

| Feature | Implementation | Notes |
|---------|----------------|-------|
| **Memory Info** | `GlobalMemoryStatusEx` API | Reports physical RAM |
| **Drive Enumeration** | `GetLogicalDriveStrings` + `GetDiskFreeSpaceEx` | All logical drives (C:\, D:\, etc.) |
| **ANSI Colors** | Virtual Terminal Processing | Requires `Terminal.enableAnsiColors()` |
| **Performance** | ~2-7ms total | With drive enumeration |

### Linux

| Feature | Implementation | Notes |
|---------|----------------|-------|
| **Memory Info** | `/proc/meminfo` parsing | `MemTotal` and `MemAvailable` |
| **Drive Enumeration** | `/proc/mounts` | Mounted filesystems |
| **ANSI Colors** | Native support | Works out of the box |
| **Performance** | ~1-3ms total | Fast file parsing |

### macOS

| Feature | Implementation | Notes |
|---------|----------------|-------|
| **Memory Info** | `sysctl` queries | `hw.memsize` and `vm.stats` |
| **Drive Enumeration** | Mount points | Via system calls |
| **ANSI Colors** | Native support | Works out of the box |
| **Performance** | ~1-3ms total | Efficient system calls |

## Complete Example

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Enable ANSI colors on Windows
    _ = logly.Terminal.enableAnsiColors();

    // Example 1: Auto-emit at startup
    {
        var config = logly.Config.default();
        config.emit_system_diagnostics_on_init = true;
        config.include_drive_diagnostics = true;
        config.color = true;

        const logger = try logly.Logger.initWithConfig(allocator, config);
        defer logger.deinit();
        
        // Diagnostics already logged during init
    }

    // Example 2: Manual on-demand
    {
        const logger = try logly.Logger.init(allocator);
        defer logger.deinit();

        try logger.logSystemDiagnostics(@src());
    }

    // Example 3: Direct collection
    {
        var diag = try logly.Diagnostics.collect(allocator, true);
        defer diag.deinit(allocator);

        std.debug.print("CPU: {s} ({d} cores)\n", .{diag.cpu_model, diag.logical_cores});
        
        if (diag.total_mem) |total| {
            if (diag.avail_mem) |avail| {
                const used_mb = (total - avail) / (1024 * 1024);
                const total_mb = total / (1024 * 1024);
                std.debug.print("Memory: {d}/{d} MB\n", .{used_mb, total_mb});
            }
        }
    }
}
```

## Aliases

The Diagnostics module provides convenience aliases:

| Alias | Method |
|-------|--------|
| `gather` | `collect` |
| `snapshot` | `collect` |

## Additional Methods

- `summary() []const u8` - Returns a compact summary string of system info

## DiagnosticsPresets

Pre-configured diagnostic collection options:

```zig
pub const DiagnosticsPresets = struct {
    /// Minimal diagnostics (no drives).
    pub fn minimal() DiagnosticsConfig {
        return .{ .include_drives = false };
    }
    
    /// Full diagnostics with all information.
    pub fn full() DiagnosticsConfig {
        return .{ .include_drives = true };
    }
};
```

## See Also

- [Diagnostics Guide](../guide/diagnostics.md) - Usage patterns and best practices
- [Configuration API](config.md) - All configuration options
- [Logger API](logger.md) - Logger methods and usage
- [Formatting Guide](../guide/formatting.md) - Custom format strings
- [Example Code](../../examples/diagnostics.zig) - Complete working example

