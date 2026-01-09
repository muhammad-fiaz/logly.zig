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
const SinkConfig = @import("sink.zig").SinkConfig;

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
/// Usage:
///   Obtain via `collect()` and use to inspect system state.
///
/// Fields:
///   - os_tag: Operating system tag (e.g., "windows", "linux", "macos")
///   - arch: CPU architecture (e.g., "x86_64", "aarch64", "arm")
///   - cpu_model: Human-readable CPU model name
///   - logical_cores: Number of logical CPU cores (minimum 1)
///   - total_mem: Total physical RAM in bytes (null if unavailable)
///   - avail_mem: Available physical RAM in bytes (null if unavailable)
///   - drives: Array of drive information (empty if not collected)
pub const Diagnostics = struct {
    os_tag: []const u8,
    arch: []const u8,
    cpu_model: []const u8,
    logical_cores: usize,
    total_mem: ?u64,
    avail_mem: ?u64,
    drives: []DriveInfo,
    /// Resource usage statistics for the current process (RSS, etc.)
    rusage: ?std.posix.rusage = null,

    /// Releases all dynamically allocated memory associated with diagnostics.
    ///
    /// Must be called exactly once with the same allocator used in collect().
    /// After calling deinit(), the Diagnostics struct becomes invalid.
    ///
    /// Complexity: O(N) where N is the number of drives.
    pub fn deinit(self: *Diagnostics, allocator: std.mem.Allocator) void {
        for (self.drives) |d| {
            allocator.free(d.name);
        }
        allocator.free(self.drives);
    }

    pub const destroy = deinit;
};

/// Collects system diagnostics information.
///
/// Gathers host system information including OS, CPU, memory, and optionally
/// drive/volume information. The returned Diagnostics struct owns all allocated
/// memory and must be freed with deinit().
///
/// Algorithm:
///   - Detects CPU info via builtin and std.Thread.
///   - On Windows: Uses `GlobalMemoryStatusEx` and `GetLogicalDriveStringsW`.
///   - On Linux: Reads `/proc/meminfo` and `/proc/mounts`.
///   - On macOS: Uses `sysctl` and `statvfs`.
///   - Collects resource usage via `getrusage` (POSIX) or equivalent.
///
/// Arguments:
///   - `allocator`: Memory allocator for diagnostic data ownership.
///   - `include_drives`: Whether to collect drive/volume information.
///
/// Return Value:
///   - `Diagnostics` struct with collected system information.
///
/// Errors:
///   - `error.OutOfMemory`: If memory allocation fails.
///
/// Complexity: O(1) for memory/CPU, O(D) for drives where D is number of drives.
pub fn collect(allocator: std.mem.Allocator, include_drives: bool) !Diagnostics {
    var drives: std.ArrayList(DriveInfo) = .empty;
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
    } else if (builtin.os.tag == .linux) {
        if (getLinuxMemory()) |mem| {
            total_mem = mem.total;
            avail_mem = mem.avail;
        }
        if (include_drives) {
            try collectLinuxDrives(allocator, &drives);
        }
    } else if (builtin.os.tag == .macos) {
        if (getMacMemory()) |mem| {
            total_mem = mem.total;
            avail_mem = mem.avail;
        }
        if (include_drives) {
            try collectMacDrives(allocator, &drives);
        }
    }

    // Collect resource usage using std.posix where available
    var rusage_stat: ?std.posix.rusage = null;
    if (builtin.os.tag != .windows) {
        // POSIX systems (Linux, macOS, BSD) usually support getrusage
        if (@hasDecl(std.posix, "getrusage") and @hasDecl(std.posix, "rusage")) {
            var ru: std.posix.rusage = undefined;
            // RUSAGE.SELF might be integer or enum depending on version/OS
            // Using standard value 0 (RUSAGE_SELF) if not strictly typed,
            // but std.posix.RUSAGE.SELF should exist.
            if (std.posix.getrusage(std.posix.RUSAGE.SELF, &ru) catch null) |_| {
                rusage_stat = ru;
            }
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
        .rusage = rusage_stat,
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

fn getLinuxMemory() ?struct { total: u64, avail: u64 } {
    const file = std.fs.openFileAbsolute("/proc/meminfo", .{}) catch return null;
    defer file.close();

    var buf: [4096]u8 = undefined;
    const len = file.readAll(&buf) catch return null;
    const content = buf[0..len];

    var total: u64 = 0;
    var avail: u64 = 0;

    var iter = std.mem.tokenizeAny(u8, content, "\n");
    while (iter.next()) |line| {
        if (std.mem.startsWith(u8, line, "MemTotal:")) {
            total = parseMeminfoLine(line) catch 0;
        } else if (std.mem.startsWith(u8, line, "MemAvailable:")) {
            avail = parseMeminfoLine(line) catch 0;
        }
    }

    if (total == 0) return null;
    return .{ .total = total, .avail = avail };
}

fn parseMeminfoLine(line: []const u8) !u64 {
    var iter = std.mem.tokenizeAny(u8, line, " \t");
    _ = iter.next(); // "MemTotal:"
    const value_str = iter.next() orelse return error.InvalidFormat;
    const value = try std.fmt.parseInt(u64, value_str, 10);
    // Unit is usually kB
    return value * 1024;
}

fn getMacMemory() ?struct { total: u64, avail: u64 } {
    var total: u64 = 0;
    var size: usize = @sizeOf(u64);
    // Use std.c.sysctlbyname if available. Zig links libc on macOS by default.
    if (std.c.sysctlbyname("hw.memsize", &total, &size, null, 0) == 0) {
        // "Available" is hard to get via sysctl simple keys (requires Mach calls).
        // returning 0 for avail indicates unknown.
        return .{ .total = total, .avail = 0 };
    }
    return null;
}

fn collectLinuxDrives(allocator: std.mem.Allocator, list: *std.ArrayList(DriveInfo)) !void {
    const file = std.fs.openFileAbsolute("/proc/mounts", .{}) catch return;
    defer file.close();

    var buf: [8192]u8 = undefined;
    const len = file.readAll(&buf) catch return;
    const content = buf[0..len];

    var lines = std.mem.tokenizeAny(u8, content, "\n");
    while (lines.next()) |line| {
        var parts = std.mem.tokenizeAny(u8, line, " \t");
        const device = parts.next() orelse continue;
        const mount_point = parts.next() orelse continue;
        const fs_type = parts.next() orelse continue;

        // Filter for physical processing
        if (std.mem.startsWith(u8, device, "/dev/") and !std.mem.eql(u8, fs_type, "tmpfs")) {
            // Get stats
            var stat: std.posix.StatVfs = undefined;
            if (std.posix.statvfs(mount_point, &stat) catch null) |_| {
                const total = @as(u64, stat.f_blocks) * @as(u64, stat.f_frsize);
                const free = @as(u64, stat.f_bavail) * @as(u64, stat.f_frsize); // bavail is for non-privileged

                const name = try allocator.dupe(u8, mount_point);
                try list.append(allocator, .{ .name = name, .total_bytes = total, .free_bytes = free });
            }
        }
    }
}

fn collectMacDrives(allocator: std.mem.Allocator, list: *std.ArrayList(DriveInfo)) !void {
    const MNT_NOWAIT = 2;

    const Statfs = extern struct {
        f_bsize: u32,
        f_iosize: i32,
        f_blocks: u64,
        f_bfree: u64,
        f_bavail: u64,
        f_files: u64,
        f_ffree: u64,
        f_fsid: [2]i32,
        f_owner: u32,
        f_type: u32,
        f_flags: u32,
        f_fssubtype: u32,
        f_fstypename: [16]u8,
        f_mntonname: [1024]u8,
        f_mntfromname: [1024]u8,
        f_reserved: [8]u32,
    };

    const LibC = struct {
        pub extern "c" fn getmntinfo(mntbufp: *[*c]Statfs, flags: c_int) c_int;
    };

    var mounts: [*c]Statfs = undefined;
    const count = LibC.getmntinfo(&mounts, MNT_NOWAIT);

    if (count == 0) return;
    const num_mounts = @as(usize, @intCast(count));

    var i: usize = 0;
    while (i < num_mounts) : (i += 1) {
        const mnt = mounts[i];
        const total = mnt.f_blocks * mnt.f_bsize;
        const free = mnt.f_bavail * mnt.f_bsize;

        if (total == 0) continue;

        const path = std.mem.sliceTo(&mnt.f_mntonname, 0);
        const name = try allocator.dupe(u8, path);
        try list.append(allocator, .{ .name = name, .total_bytes = total, .free_bytes = free });
    }
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

/// Creates a diagnostics-specific file sink configuration.
///
/// Usage:
///   Helper to generate a `SinkConfig` tailored for diagnostic dumps (JSON, no color).
///
/// Arguments:
///   - `file_path`: Path to the output file.
///
/// Return Value:
///   - `SinkConfig` for diagnostics.
///
/// Complexity: O(1)
pub fn createDiagnosticsSink(file_path: []const u8) SinkConfig {
    return SinkConfig{
        .path = file_path,
        .json = true,
        .pretty_json = true,
        .color = false,
        .include_timestamp = true,
    };
}

/// Alias for collect
pub const gather = collect;
pub const snapshot = collect;

/// Returns a quick system summary string.
///
/// Formats key system stats into a human-readable string.
/// Caller owns the returned string memory.
///
/// Algorithm:
///   - Collects minimal diagnostics.
///   - Formats string with OS, Arch, CPU, Cores.
///   - Frees diagnostics.
///
/// Arguments:
///   - `allocator`: Memory source.
///
/// Return Value:
///   - `[]u8` string (caller must free).
///
/// Complexity: O(1)
pub fn summary(allocator: std.mem.Allocator) ![]u8 {
    const diag = try collect(allocator, false);
    defer @constCast(&diag).deinit(allocator);

    return std.fmt.allocPrint(allocator, "{s}/{s} - {s} ({d} cores)", .{
        diag.os_tag,
        diag.arch,
        diag.cpu_model,
        diag.logical_cores,
    });
}

/// Diagnostics presets for common scenarios.
///
/// Usage:
///   Convenience wrappers around `collect`.
///
/// Complexity: O(1)
pub const DiagnosticsPresets = struct {
    /// Minimal diagnostics (no drive info).
    ///
    /// Complexity: O(1)
    pub fn minimal(allocator: std.mem.Allocator) !Diagnostics {
        return collect(allocator, false);
    }

    /// Full diagnostics (includes drive info).
    ///
    /// Complexity: O(D) where D is number of drives.
    pub fn full(allocator: std.mem.Allocator) !Diagnostics {
        return collect(allocator, true);
    }
};
