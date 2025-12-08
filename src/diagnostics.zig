const std = @import("std");
const builtin = @import("builtin");

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

pub const DriveInfo = struct {
    name: []const u8,
    total_bytes: u64,
    free_bytes: u64,
};

pub const Diagnostics = struct {
    os_tag: []const u8,
    arch: []const u8,
    cpu_model: []const u8,
    logical_cores: usize,
    total_mem: ?u64,
    avail_mem: ?u64,
    drives: []DriveInfo,

    pub fn deinit(self: *Diagnostics, allocator: std.mem.Allocator) void {
        for (self.drives) |d| {
            allocator.free(d.name);
        }
        allocator.free(self.drives);
    }
};

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
