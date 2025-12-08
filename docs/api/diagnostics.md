# Diagnostics API Reference

The \Diagnostics\ module collects comprehensive host information including OS, CPU, memory, and storage details for logging and monitoring.

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

\\\zig
pub const Diagnostics = struct {
    os_tag: []const u8,           // OS tag from builtin (e.g., \"windows\")
    arch: []const u8,              // CPU architecture (e.g., \"x86_64\")
    cpu_model: []const u8,         // Human-readable CPU model name
    logical_cores: usize,          // Number of logical CPU cores
    total_mem: ?u64,               // Total physical memory in bytes (null if unavailable)
    avail_mem: ?u64,               // Available physical memory in bytes (null if unavailable)
    drives: []DriveInfo,           // Array of drive information
    
    pub fn deinit(self: *Diagnostics, allocator: std.mem.Allocator) void;
};
\\\

**Fields:**

| Field | Type | Description | Platform |
|-------|------|-------------|----------|
| \os_tag\ | string | Operating system tag | All |
| \rch\ | string | CPU architecture | All |
| \cpu_model\ | string | Processor model name | All |
| \logical_cores\ | integer | Logical processor count | All |
| \	otal_mem\ | integer? | Total RAM in bytes | Windows only |
| \vail_mem\ | integer? | Available RAM in bytes | Windows only |
| \drives\ | array | Drive information | Windows/Linux |

**Examples:**

\\\zig
std.debug.print(\"OS: {s}\n\", .{diag.os_tag});      // Output: \"windows\"
std.debug.print(\"Arch: {s}\n\", .{diag.arch});      // Output: \"x86_64\"
std.debug.print(\"CPU: {s}\n\", .{diag.cpu_model});  // Output: \"Intel Core i7-9700K\"
std.debug.print(\"Cores: {d}\n\", .{diag.logical_cores}); // Output: 8

if (diag.total_mem) |total| {
    std.debug.print(\"Total RAM: {d} MB\n\", .{total / (1024 * 1024)});
}
\\\

### DriveInfo

Information about a single drive or volume.

\\\zig
pub const DriveInfo = struct {
    name: []const u8,        // Drive name (e.g., \"C:\\\\" or \"/mnt/data\")
    total_bytes: u64,        // Total capacity in bytes
    free_bytes: u64,         // Free bytes available
};
\\\

**Fields:**

| Field | Type | Description |
|-------|------|-------------|
| \
ame\ | string | Drive identifier |
| \	otal_bytes\ | integer | Total capacity |
| \ree_bytes\ | integer | Available space |

## Functions

### collect()

Collects system diagnostics information.

\\\zig
pub fn collect(allocator: std.mem.Allocator, include_drives: bool) !Diagnostics
\\\

**Parameters:**
- \llocator\ - Memory allocator for diagnostic data (must call \deinit()\ to free)
- \include_drives\ - Include drive enumeration (adds ~1-5ms on Windows)

**Returns:** \Diagnostics\ struct with collected information

**Errors:** \error.OutOfMemory\ if allocation fails

**Behavior:**
- **Windows**: Uses Win32 APIs for memory and drive enumeration
- **Linux**: Parses /proc/meminfo for memory
- **macOS**: Uses sysctl for memory information

### deinit()

Frees allocated memory for diagnostics data.

\\\zig
pub fn deinit(self: *Diagnostics, allocator: std.mem.Allocator) void
\\\

**Parameters:**
- \self\ - The Diagnostics struct to deinitialize
- \llocator\ - The same allocator used in \collect()\

## Logger Integration

### logSystemDiagnostics()

Logger helper method that collects and logs diagnostics.

\\\zig
pub fn logSystemDiagnostics(self: *Logger, src: ?std.builtin.SourceLocation) !void
\\\

**Parameters:**
- \self\ - Logger instance
- \src\ - Source location (typically \@src()\)

## Context Fields

When diagnostics are logged, the following fields are available in the log record context for custom formatting:

| Field | Type | Description |
|-------|------|-------------|
| \diag.os\ | string | OS tag (\"windows\", \"linux\", \"macos\") |
| \diag.arch\ | string | CPU architecture |
| \diag.cpu\ | string | CPU model name |
| \diag.cores\ | integer | Logical cores |
| \diag.ram_total_mb\ | integer | Total RAM in MB |
| \diag.ram_avail_mb\ | integer | Available RAM in MB |

## Configuration Options

### emit_system_diagnostics_on_init

Automatically emit diagnostics when logger initializes.

### include_drive_diagnostics

Include drive/volume information in diagnostics collection.

### use_colors

Enable color-coded diagnostic output.

## Platform-Specific Behavior

### Windows
- **Memory Info**: Via GlobalMemoryStatusEx API
- **Drive Enumeration**: Via GetLogicalDriveStrings + GetDiskFreeSpaceEx
- **ANSI Colors**: Requires \Terminal.enableAnsiColors()\ call
- **Performance**: ~2-7ms total (with drives)

### Linux
- **Memory Info**: Parsed from /proc/meminfo
- **Drive Enumeration**: Via /proc/mounts
- **ANSI Colors**: Fully supported
- **Performance**: ~1-3ms total

### macOS
- **Memory Info**: Via sysctl queries
- **Drive Enumeration**: Via mount points
- **ANSI Colors**: Fully supported
- **Performance**: ~1-3ms total

## See Also

- [Diagnostics Guide](../guide/diagnostics.md) - Usage patterns and examples
- [Configuration](../guide/configuration.md) - Config options
- [Formatting Guide](../guide/formatting.md) - Custom format strings
- [Example Code](../../examples/diagnostics.zig) - Complete working example
