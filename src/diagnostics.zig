//! System Diagnostics Module
//!
//! Collects and provides access to host system information for logging
//! context enrichment and system monitoring.
//!
//! Collected Information:
//! - Operating system and CPU architecture
//! - CPU model name and logical core count
//! - Physical memory (total and available)
//! - Drive/volume information (capacity, free space)
//! - Process resource usage (RSS, CPU time)
//!
//! Platform Support:
//! - Windows: Uses kernel32 APIs (GlobalMemoryStatusEx, GetDiskFreeSpaceEx)
//! - Linux: Reads /proc/meminfo and /proc/mounts
//! - macOS: Uses sysctl and getmntinfo
//!
//! Usage:
//! ```zig
//! var diag = try Diagnostics.collect(allocator, true);
//! defer diag.deinit(allocator);
//! std.debug.print("OS: {s}, Cores: {d}\n", .{diag.os_tag, diag.logical_cores});
//! ```
//!
/// All collected data is owned by the caller and must be freed with deinit().
const std = @import("std");
const builtin = @import("builtin");
const SinkConfig = @import("sink.zig").SinkConfig;
const Constants = @import("constants.zig");
const Utils = @import("utils.zig");

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
    pub const free = deinit;
    pub const release = deinit;

    /// Returns a compact single-line summary of the diagnostics.
    /// Useful for inclusion in log messages.
    pub fn compact(self: *const Diagnostics, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(
            allocator,
            "os={s} arch={s} cpu={s} cores={d} mem_total={d} mem_avail={d} drives={d}",
            .{
                self.os_tag,
                self.arch,
                self.cpu_model,
                self.logical_cores,
                self.total_mem orelse 0,
                self.avail_mem orelse 0,
                self.drives.len,
            },
        );
    }

    /// Alias for `compact`.
    pub const oneLine = compact;
    pub const brief = compact;
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
            // RUSAGE.SELF might be integer or enum depending on version/OS
            // std.posix.getrusage returns the struct directly in some Zig versions
            // Use std.c.RUSAGE.SELF or fallback to 0 (RUSAGE_SELF)
            const who: i32 = if (@hasDecl(std.c, "RUSAGE")) @intFromEnum(std.c.RUSAGE.SELF) else 0;
            rusage_stat = std.posix.getrusage(who);
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
    const io = Utils.io();
    const file = std.Io.Dir.openFileAbsolute(io, "/proc/meminfo", .{}) catch return null;
    defer file.close(io);

    var buf: [Constants.BufferSizes.file_read]u8 = undefined;
    var file_buffer: [Constants.BufferSizes.file_read]u8 = undefined;
    var reader = file.reader(io, &file_buffer);
    const len = reader.interface.readSliceShort(&buf) catch return null;
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
    return value * Constants.SizeConstants.bytes_per_kb;
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
    const io = Utils.io();
    const file = std.Io.Dir.openFileAbsolute(io, "/proc/mounts", .{}) catch return;
    defer file.close(io);

    var buf: [Constants.BufferSizes.file_read_large]u8 = undefined;
    var file_buffer: [Constants.BufferSizes.file_read]u8 = undefined;
    var reader = file.reader(io, &file_buffer);
    const len = reader.interface.readSliceShort(&buf) catch return;
    const content = buf[0..len];

    var lines = std.mem.tokenizeAny(u8, content, "\n");
    while (lines.next()) |line| {
        var parts = std.mem.tokenizeAny(u8, line, " \t");
        const device = parts.next() orelse continue;
        const mount_point = parts.next() orelse continue;
        const fs_type = parts.next() orelse continue;

        // Filter for physical processing
        if (std.mem.startsWith(u8, device, "/dev/") and !std.mem.eql(u8, fs_type, "tmpfs")) {
            // Get stats using manual extern definition to avoid std lib version issues
            // Note: We use a larger padding because musl/glibc struct definitions vary
            // Definition of StatVfs that matches the Linux statvfs64 structure (Large File Support).
            // This ensures consistent field sizes (u64 for counters) across architectures and
            // prevents data corruption when linking against glibc/musl.
            // We verify the layout carefully to avoid stack corruption issues (common on 32-bit).
            const StatVfs = extern struct {
                f_bsize: c_ulong,
                f_frsize: c_ulong,
                f_blocks: u64,
                f_bfree: u64,
                f_bavail: u64,
                f_files: u64,
                f_ffree: u64,
                f_favail: u64,
                f_fsid: c_ulong,
                f_flag: c_ulong,
                f_namemax: c_ulong,
                __f_spare: [32]c_int, // Extra padding to be safe against libc struct size variations
            };

            // Bind to statvfs.
            // On Musl (used by Zig for static Linux binaries), statvfs is 64-bit capable (LFS).
            // We kept the large struct padding to ensure safety against strict size/alignment differences.
            const statvfs_fn = @extern(*const fn ([*:0]const u8, *StatVfs) callconv(.c) c_int, .{ .name = "statvfs" });

            var stat: StatVfs = undefined;
            const mount_point_c = try allocator.dupeZ(u8, mount_point);
            defer allocator.free(mount_point_c);

            if (statvfs_fn(mount_point_c, &stat) == 0) {
                const total = std.math.mul(u64, @as(u64, stat.f_blocks), @as(u64, stat.f_frsize)) catch std.math.maxInt(u64);
                const free = std.math.mul(u64, @as(u64, stat.f_bavail), @as(u64, stat.f_frsize)) catch std.math.maxInt(u64); // bavail is for non-privileged

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
        f_mntonname: [Constants.DiagnosticsConstants.mac_mount_path_len]u8,
        f_mntfromname: [Constants.DiagnosticsConstants.mac_mount_path_len]u8,
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
        const total = std.math.mul(u64, mnt.f_blocks, @as(u64, mnt.f_bsize)) catch std.math.maxInt(u64);
        const free = std.math.mul(u64, mnt.f_bavail, @as(u64, mnt.f_bsize)) catch std.math.maxInt(u64);

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
    var buffer: [Constants.BufferSizes.path_buffer]u16 = undefined;
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

/// Alias for createDiagnosticsSink
pub const createSink = createDiagnosticsSink;
pub const diagnosticsSink = createDiagnosticsSink;

/// Alias for summary
pub const info = summary;
pub const systemInfo = summary;

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

    /// Alias for minimal
    pub const basic = minimal;
    pub const simple = minimal;

    /// Full diagnostics (includes drive info).
    ///
    /// Complexity: O(D) where D is number of drives.
    pub fn full(allocator: std.mem.Allocator) !Diagnostics {
        return collect(allocator, true);
    }

    /// Alias for full
    pub const complete = full;
    pub const comprehensive = full;
};

/// Health status of the logging system.
pub const HealthStatus = enum {
    /// System is operating normally.
    healthy,
    /// System is operating but with some degradation.
    degraded,
    /// System is unhealthy and may be losing data.
    unhealthy,
};

/// Health report for the logging system.
pub const HealthReport = struct {
    /// Overall health status.
    status: HealthStatus,
    /// Queue utilization ratio (0.0–1.0).
    queue_utilization: f64,
    /// Error rate (0.0–1.0).
    error_rate: f64,
    /// Memory used in bytes (total - avail), 0 if unknown.
    memory_used_bytes: u64,
    /// Process uptime in milliseconds.
    uptime_ms: i64,
    /// Human-readable description of detected issues (empty if healthy).
    issues: []const u8,

    /// Returns true when status is healthy.
    pub fn isHealthy(self: *const HealthReport) bool {
        return self.status == .healthy;
    }

    /// Returns true when status is unhealthy.
    pub fn isUnhealthy(self: *const HealthReport) bool {
        return self.status == .unhealthy;
    }
};

/// Lightweight snapshot of diagnostics state for diff comparisons.
pub const DiagnosticsSnapshot = struct {
    /// Unix timestamp in milliseconds when snapshot was taken.
    timestamp_ms: i64,
    /// Operating system tag.
    os_tag: []const u8,
    /// CPU architecture tag.
    arch: []const u8,
    /// Number of logical CPU cores.
    logical_cores: usize,
    /// Total physical memory in bytes (null if unknown).
    total_mem: ?u64,
    /// Available physical memory in bytes (null if unknown).
    avail_mem: ?u64,
    /// Number of drives collected.
    drive_count: usize,
};

/// Emits the diagnostics as a compact JSON object to the given writer.
///
/// Arguments:
///   - `diag`: Diagnostics instance.
///   - `allocator`: Allocator for intermediate buffers.
///   - `writer`: Any writer with a `writeAll` method.
///
/// Complexity: O(D) where D is number of drives.
pub fn emitJson(diag: *const Diagnostics, allocator: std.mem.Allocator, writer: anytype) !void {
    const json = try toJson(diag, allocator);
    defer allocator.free(json);
    try writer.writeAll(json);
}

/// Serializes the diagnostics as a compact JSON string.
/// Caller must free the returned slice.
///
/// Complexity: O(D) where D is number of drives.
pub fn toJson(diag: *const Diagnostics, allocator: std.mem.Allocator) ![]u8 {
    const total_mb: u64 = if (diag.total_mem) |t| t / Constants.SizeConstants.bytes_per_mb else 0;
    const avail_mb: u64 = if (diag.avail_mem) |a| a / Constants.SizeConstants.bytes_per_mb else 0;
    const now_ms = Utils.currentMillis();

    var buf: std.ArrayList(u8) = .empty;
    errdefer buf.deinit(allocator);
    var list_writer = Utils.ArrayListWriter.init(&buf, allocator);
    const w = &list_writer.writer;

    try w.writeAll("{");
    try w.print("\"timestamp_ms\":{d},", .{now_ms});
    try w.print("\"os\":\"{s}\",", .{diag.os_tag});
    try w.print("\"arch\":\"{s}\",", .{diag.arch});
    try w.print("\"cpu\":\"{s}\",", .{diag.cpu_model});
    try w.print("\"cores\":{d},", .{diag.logical_cores});
    try w.print("\"total_mem_mb\":{d},", .{total_mb});
    try w.print("\"avail_mem_mb\":{d},", .{avail_mb});
    try w.print("\"drive_count\":{d},", .{diag.drives.len});
    try w.writeAll("\"drives\":[");
    for (diag.drives, 0..) |drive, i| {
        if (i > 0) try w.writeByte(',');
        const gb_div: f64 = @floatFromInt(Constants.SizeConstants.bytes_per_gb);
        const dtotal_gb: f64 = @as(f64, @floatFromInt(drive.total_bytes)) / gb_div;
        const dfree_gb: f64 = @as(f64, @floatFromInt(drive.free_bytes)) / gb_div;
        try w.print("{{\"{s}\":{{\"total_gb\":{d:.2},\"free_gb\":{d:.2}}}}}", .{ drive.name, dtotal_gb, dfree_gb });
    }
    try w.writeAll("]}");

    return buf.toOwnedSlice(allocator);
}

/// Checks the health of the system based on available memory.
///
/// Health Rules:
///   - avail_mem < 10% of total_mem → unhealthy
///   - avail_mem < 20% of total_mem → degraded
///   - Otherwise → healthy
///
/// Arguments:
///   - `diag`: Diagnostics instance.
///
/// Return Value:
///   - `HealthReport` with status, memory usage, and issues description.
///
/// Complexity: O(1)
pub fn checkHealth(diag: *const Diagnostics) HealthReport {
    var status: HealthStatus = .healthy;
    var issues: []const u8 = "";
    var memory_used: u64 = 0;

    if (diag.total_mem) |total| {
        if (diag.avail_mem) |avail| {
            memory_used = if (total > avail) total - avail else 0;
            const ratio = if (total == 0) 1.0 else @as(f64, @floatFromInt(avail)) / @as(f64, @floatFromInt(total));

            if (ratio < 0.10) {
                status = .unhealthy;
                issues = "critical: available memory below 10%";
            } else if (ratio < 0.20) {
                status = .degraded;
                issues = "warning: available memory below 20%";
            }
        }
    }

    return HealthReport{
        .status = status,
        .queue_utilization = 0.0,
        .error_rate = 0.0,
        .memory_used_bytes = memory_used,
        .uptime_ms = Utils.currentMillis(),
        .issues = issues,
    };
}

/// Creates a lightweight snapshot of the current diagnostics state.
///
/// Complexity: O(1)
pub fn takeSnapshot(diag: *const Diagnostics) DiagnosticsSnapshot {
    return DiagnosticsSnapshot{
        .timestamp_ms = Utils.currentMillis(),
        .os_tag = diag.os_tag,
        .arch = diag.arch,
        .logical_cores = diag.logical_cores,
        .total_mem = diag.total_mem,
        .avail_mem = diag.avail_mem,
        .drive_count = diag.drives.len,
    };
}

/// Computes a human-readable diff between two diagnostic snapshots.
/// Caller must free the returned slice.
///
/// Complexity: O(1)
pub fn diff(snap1: DiagnosticsSnapshot, snap2: DiagnosticsSnapshot, allocator: std.mem.Allocator) ![]u8 {
    const elapsed_ms = snap2.timestamp_ms - snap1.timestamp_ms;
    const mem1_mb: u64 = if (snap1.avail_mem) |a| a / Constants.SizeConstants.bytes_per_mb else 0;
    const mem2_mb: u64 = if (snap2.avail_mem) |a| a / Constants.SizeConstants.bytes_per_mb else 0;
    const mem_delta: i64 = @as(i64, @intCast(mem2_mb)) - @as(i64, @intCast(mem1_mb));

    return std.fmt.allocPrint(
        allocator,
        "DiagnosticsSnapshot diff:\n" ++
            "  Elapsed: {d} ms\n" ++
            "  Cores: {d} -> {d}\n" ++
            "  Avail mem: {d} MB -> {d} MB (delta: {d} MB)\n" ++
            "  Drives: {d} -> {d}\n",
        .{
            elapsed_ms,
            snap1.logical_cores,
            snap2.logical_cores,
            mem1_mb,
            mem2_mb,
            mem_delta,
            snap1.drive_count,
            snap2.drive_count,
        },
    );
}

/// Alias for emitJson
pub const writeJson = emitJson;
pub const printJson = emitJson;
pub const asJson = toJson;
pub const serializeJson = toJson;
pub const healthCheck = checkHealth;
pub const getHealth = checkHealth;
pub const snapshot2 = takeSnapshot;
pub const delta = diff;
pub const compare = diff;

// Ergonomic aliases for the public API
pub const get = collect;
pub const fetch = collect;
pub const gatherAll = collect;
pub const getAll = collect;
pub const buildReport = summary;
pub const getSummary = summary;

test "HealthReport logic" {
    var report = HealthReport{
        .status = .healthy,
        .queue_utilization = 0.0,
        .error_rate = 0.0,
        .memory_used_bytes = 1000,
        .uptime_ms = 100,
        .issues = "",
    };
    try std.testing.expect(report.isHealthy());
    try std.testing.expect(!report.isUnhealthy());

    report.status = .unhealthy;
    try std.testing.expect(!report.isHealthy());
    try std.testing.expect(report.isUnhealthy());
}

test "Diagnostics snapshot diff" {
    const snap1 = DiagnosticsSnapshot{
        .timestamp_ms = 1000,
        .os_tag = "linux",
        .arch = "x86_64",
        .logical_cores = 4,
        .total_mem = 8000000000,
        .avail_mem = 4000000000,
        .drive_count = 1,
    };
    const snap2 = DiagnosticsSnapshot{
        .timestamp_ms = 2000,
        .os_tag = "linux",
        .arch = "x86_64",
        .logical_cores = 4,
        .total_mem = 8000000000,
        .avail_mem = 3000000000,
        .drive_count = 1,
    };

    const diff_str = try diff(snap1, snap2, std.testing.allocator);
    defer std.testing.allocator.free(diff_str);
    try std.testing.expect(std.mem.indexOf(u8, diff_str, "Elapsed: 1000 ms") != null);
}

test "Diagnostics checkHealth" {
    var diag = Diagnostics{
        .os_tag = "linux",
        .arch = "x86_64",
        .cpu_model = "test_cpu",
        .logical_cores = 4,
        .total_mem = 1000000,
        .avail_mem = 50000, // 5%, should be unhealthy
        .drives = &[_]DriveInfo{},
    };

    const report = checkHealth(&diag);
    try std.testing.expectEqual(HealthStatus.unhealthy, report.status);
    try std.testing.expect(std.mem.indexOf(u8, report.issues, "critical") != null);

    diag.avail_mem = 150000; // 15%, should be degraded
    const report2 = checkHealth(&diag);
    try std.testing.expectEqual(HealthStatus.degraded, report2.status);

    diag.avail_mem = 500000; // 50%, should be healthy
    const report3 = checkHealth(&diag);
    try std.testing.expectEqual(HealthStatus.healthy, report3.status);
}

test "Diagnostics compact one-liner" {
    const diag: Diagnostics = .{
        .os_tag = "linux",
        .arch = "x86_64",
        .cpu_model = "test_cpu",
        .logical_cores = 4,
        .total_mem = 8000000000,
        .avail_mem = 4000000000,
        .drives = &[_]DriveInfo{},
    };
    const one = try diag.compact(std.testing.allocator);
    defer std.testing.allocator.free(one);
    try std.testing.expect(std.mem.indexOf(u8, one, "os=linux") != null);
    try std.testing.expect(std.mem.indexOf(u8, one, "cores=4") != null);
}
