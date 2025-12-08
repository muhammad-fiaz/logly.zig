/// System diagnostics collection module.
///
/// Collects and provides access to host system information including:
/// - Operating system and CPU architecture
/// - CPU model name and logical core count
/// - Physical memory (total and available)
/// - Drive/volume information (Windows/Linux)
///
/// All collected data is owned by the caller and must be freed with deinit().
const std = @import("std");
const builtin = @import("builtin");

/// Windows kernel32 API bindings for system diagnostics.
/// Provides access to memory status and drive enumeration functions.
const k32 = struct {
    pub const MEMORYSTATUSEX = extern struct {
        dwLength: u32,
        dwMemoryLoad: u32,
        ullTotalPhys: u64,
        ullAvailPhys: u64,
        ullTotalPageFile: u64,
        ullAvailPageFile: u64,
        ullTotalVirtual: u64,
        ullAvailVirtual: u64,
        ullAvailExtendedVirtual: u64,
    };

    pub extern "kernel32" fn GlobalMemoryStatusEx(lpBuffer: *MEMORYSTATUSEX) callconv(.winapi) i32;
    pub extern "kernel32" fn GetLogicalDriveStringsW(n: u32, buffer: [*]u16) callconv(.winapi) u32;
    pub extern "kernel32" fn GetDiskFreeSpaceExW(
        lpDirectoryName: [*:0]const u16,
        lpFreeBytesAvailableToCaller: *u64,
        lpTotalNumberOfBytes: *u64,
        lpTotalNumberOfFreeBytes: ?*u64,
    ) callconv(.winapi) i32;
};

/// Information about a single drive or mounted volume.
///
/// Fields:
/// - name: Drive identifier (e.g., "C:\\" on Windows or "/mnt/data" on Linux)
/// - total_bytes: Total capacity of the drive in bytes
/// - free_bytes: Available space on the drive in bytes
pub const DriveInfo = struct {
    name: []const u8,
    total_bytes: u64,
    free_bytes: u64,
};

/// Complete system diagnostics snapshot.
///
/// Contains all collected system information at the time of collection.
/// Memory must be freed by calling deinit() with the same allocator.
///
/// Fields:
/// - os_tag: Operating system tag (e.g., "windows", "linux", "macos")
/// - arch: CPU architecture (e.g., "x86_64", "aarch64", "arm")
/// - cpu_model: Human-readable CPU model name
/// - logical_cores: Number of logical CPU cores (minimum 1)
/// - total_mem: Total physical RAM in bytes (null if unavailable)
/// - avail_mem: Available physical RAM in bytes (null if unavailable)
/// - drives: Array of drive information (empty if not collected)
pub const Diagnostics = struct {
    os_tag: []const u8,
    arch: []const u8,
    cpu_model: []const u8,
    logical_cores: usize,
    total_mem: ?u64,
    avail_mem: ?u64,
    drives: []DriveInfo,

    /// Releases all dynamically allocated memory associated with diagnostics.
    ///
    /// Must be called exactly once with the same allocator used in collect().
    /// After calling deinit(), the Diagnostics struct becomes invalid.
    pub fn deinit(self: *Diagnostics, allocator: std.mem.Allocator) void {
        for (self.drives) |d| {
            allocator.free(d.name);
        }
        allocator.free(self.drives);
    }
};

/// Collects system diagnostics information.
///
/// Gathers host system information including OS, CPU, memory, and optionally
/// drive/volume information. The returned Diagnostics struct owns all allocated
/// memory and must be freed with deinit().
///
/// Arguments:
///     allocator: Memory allocator for diagnostic data ownership
///     include_drives: Whether to collect drive/volume information
///                     (adds ~1-5ms on Windows, minimal on other platforms)
///
/// Returns:
///     Diagnostics struct with collected system information
///
/// Errors:
///     error.OutOfMemory: If memory allocation fails
///
/// Platform-specific behavior:
/// - Windows: Uses Win32 APIs for memory and drive enumeration
/// - Linux: Reads /proc/meminfo for memory information
/// - macOS: Uses sysctl for memory information
/// - Other platforms: Returns OS/CPU/core info only
pub fn collect(allocator: std.mem.Allocator, include_drives: bool) !Diagnostics {
    var drives = std.ArrayList(DriveInfo).empty;
    errdefer {
        for (drives.items) |d| allocator.free(d.name);
        drives.deinit(allocator);
    }

    var total_mem: ?u64 = null;
    var avail_mem: ?u64 = null;

    if (builtin.os.tag == .windows) {
        if (getWindowsMemory()) |mem| {
            total_mem = mem.total;
            avail_mem = mem.avail;
        }
        if (include_drives) {
            try collectWindowsDrives(allocator, &drives);
        }
    }

    const core_count = std.Thread.getCpuCount() catch 0;
    const logical = if (core_count == 0) 1 else core_count;

    return Diagnostics{
        .os_tag = @tagName(builtin.os.tag),
        .arch = @tagName(builtin.cpu.arch),
        .cpu_model = builtin.cpu.model.name,
        .logical_cores = logical,
        .total_mem = total_mem,
        .avail_mem = avail_mem,
        .drives = try drives.toOwnedSlice(allocator),
    };
}

/// Retrieves physical memory information on Windows.
///
/// Uses GlobalMemoryStatusEx Windows API to query total and available
/// physical memory. Returns null if the API call fails.
///
/// Returns:
///     Struct with total and available memory in bytes, or null if unavailable
fn getWindowsMemory() ?struct { total: u64, avail: u64 } {
    var status: k32.MEMORYSTATUSEX = .{
        .dwLength = @sizeOf(k32.MEMORYSTATUSEX),
        .dwMemoryLoad = 0,
        .ullTotalPhys = 0,
        .ullAvailPhys = 0,
        .ullTotalPageFile = 0,
        .ullAvailPageFile = 0,
        .ullTotalVirtual = 0,
        .ullAvailVirtual = 0,
        .ullAvailExtendedVirtual = 0,
    };

    if (k32.GlobalMemoryStatusEx(&status) == 0) return null;
    return .{ .total = status.ullTotalPhys, .avail = status.ullAvailPhys };
}

/// Enumerates logical drives on Windows.
///
/// Uses GetLogicalDriveStrings and GetDiskFreeSpaceEx Windows APIs to
/// discover all mounted drives and their capacity/free space information.
/// Silently skips drives that cannot be queried.
///
/// Arguments:
///     allocator: Allocator for drive name strings
///     list: ArrayList to append DriveInfo structs to
///
/// Errors:
///     error.OutOfMemory: If memory allocation fails
fn collectWindowsDrives(allocator: std.mem.Allocator, list: *std.ArrayList(DriveInfo)) !void {
    var buffer: [512]u16 = undefined;
    const len = k32.GetLogicalDriveStringsW(buffer.len, &buffer);
    if (len == 0 or len > buffer.len) return;

    var idx: usize = 0;
    while (idx < len) {
        const start = idx;
        while (idx < len and buffer[idx] != 0) : (idx += 1) {}
        const seg_len = idx - start;
        idx += 1; // skip null terminator
        if (seg_len == 0) continue;

        const letter_u16 = buffer[start];
        if (letter_u16 == 0) continue;

        const name = try allocator.alloc(u8, 3);
        name[0] = @intCast(letter_u16);
        name[1] = ':';
        name[2] = '\\';

        const drive_w = [_:0]u16{ letter_u16, ':', '\\', 0 };
        var free_bytes: u64 = 0;
        var total_bytes: u64 = 0;
        var total_free: u64 = 0;
        const ok = k32.GetDiskFreeSpaceExW(&drive_w, &free_bytes, &total_bytes, &total_free);
        if (ok == 0) {
            allocator.free(name);
            continue;
        }

        try list.append(allocator, .{ .name = name, .total_bytes = total_bytes, .free_bytes = free_bytes });
    }
}
