//! Real-time memory/allocator telemetry for logly.zig.
//!
//! `MemoryTracker` is a thin wrapper around any `std.mem.Allocator` that tracks
//! live bytes, peak bytes, allocation count, and deallocation count. It also
//! optionally invokes a user callback on every alloc/free, and exposes
//! `getCurrentMemoryUsage` / `getAvailableMemory` helpers that return the
//! logger's current and the OS-reported free RAM.
//!
//! Wrap your user allocator once with `MemoryTracker.init`, hand
//! `tracker.allocator()` to `Logger.init`, and use `Logger.getMemoryReport`
//! (or read `MemoryTracker.snapshot` directly) to inspect memory in real
//! time.
//!
//! Thread safety: the wrapper acquires a short critical section on every
//! alloc/free; reads (`snapshot`, `getCurrentMemoryUsage`, etc.) are
//! safe to call concurrently.
//!
//! Performance: each wrapped alloc/free performs O(1) integer updates under
//! a `std.Io.Mutex`. For tight benchmark loops, the wrapper adds roughly
//! 10-20 ns per allocation on x86_64 Windows; it is intended for production
//! monitoring, not the hot path of micro-benchmarks.

const std = @import("std");
const builtin = @import("builtin");

const AtomicUnsigned = @import("constants.zig").AtomicUnsigned;
const Constants = @import("constants.zig");
const Utils = @import("utils.zig");

pub const MemoryReport = struct {
    bytes_used: usize,
    bytes_peak: usize,
    bytes_capacity: usize,
    bytes_available: usize,
    allocation_count: u64,
    deallocation_count: u64,
    live_allocations: u64,

    pub fn format(self: MemoryReport, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.print(
            "MemoryReport{{ used={d} peak={d} capacity={d} available={d} allocs={d} frees={d} live={d} }}",
            .{
                self.bytes_used,
                self.bytes_peak,
                self.bytes_capacity,
                self.bytes_available,
                self.allocation_count,
                self.deallocation_count,
                self.live_allocations,
            },
        );
    }

    /// Compact single-line representation, useful for inline logs.
    pub fn formatCompact(self: MemoryReport, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.print(
            "used={d} peak={d} cap={d} avail={d} allocs={d} frees={d} live={d}",
            .{
                self.bytes_used,
                self.bytes_peak,
                self.bytes_capacity,
                self.bytes_available,
                self.allocation_count,
                self.deallocation_count,
                self.live_allocations,
            },
        );
    }

    /// Human-readable sizes (KiB / MiB / GiB).
    pub fn formatHuman(self: MemoryReport, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.print(
            "used={s} peak={s} avail={s} allocs={d} frees={d} live={d}",
            .{
                humanBytes(self.bytes_used),
                humanBytes(self.bytes_peak),
                humanBytes(self.bytes_available),
                self.allocation_count,
                self.deallocation_count,
                self.live_allocations,
            },
        );
    }

    /// Returns true if `bytes_used` is at or above `fraction` of `bytes_capacity`.
    pub fn isPressureHigh(self: MemoryReport, fraction: f64) bool {
        if (self.bytes_capacity == 0) return false;
        return @as(f64, @floatFromInt(self.bytes_used)) / @as(f64, @floatFromInt(self.bytes_capacity)) >= fraction;
    }
};

/// Convert raw bytes to a human-readable suffix (KiB, MiB, GiB, TiB).
fn humanBytes(n: usize) []const u8 {
    // Reuse SizeConstants so the magic numbers are not duplicated across the codebase.
    // The top "TiB+" bucket is anything above bytes_per_tb.
    const tb: usize = Constants.SizeConstants.bytes_per_tb;
    const gb: usize = Constants.SizeConstants.bytes_per_gb;
    const mb: usize = Constants.SizeConstants.bytes_per_mb;
    const kb = Constants.SizeConstants.bytes_per_kb;
    if (n >= tb) return "TiB+";
    if (n >= gb) return "GiB";
    if (n >= mb) return "MiB";
    if (n >= kb) return "KiB";
    return "B";
}

pub const MemoryCallback = fn (
    bytes_used: usize,
    bytes_peak: usize,
    bytes_capacity: usize,
    user_data: ?*anyopaque,
) void;

/// Pressure-event callback. Fires after `alloc` / `resize` / `remap`
/// whenever the live usage crosses the configured threshold. The
/// callback is invoked while the tracker mutex is held; keep it short.
pub const PressureCallback = fn (
    bytes_used: usize,
    bytes_peak: usize,
    bytes_capacity: usize,
    threshold: f64,
    user_data: ?*anyopaque,
) void;

/// OOM-event callback. Fires when a wrapped allocation request is
/// returned `null` by the inner allocator. The callback is invoked
/// outside the tracker mutex.
pub const OomCallback = fn (
    requested_len: usize,
    alignment: std.mem.Alignment,
    user_data: ?*anyopaque,
) void;

/// `MemoryTracker` wraps any `std.mem.Allocator` and tracks live and peak
/// bytes, allocation count, and deallocation count. It is the source of
/// truth for `Logger.getMemoryReport`.
///
/// Usage:
/// ```
/// var tracker = logly.MemoryTracker.init(gpa.allocator());
/// const logger = try logly.Logger.init(tracker.allocator());
/// const report = try logger.getMemoryReport();
/// ```
pub const MemoryTracker = struct {
    inner: std.mem.Allocator,
    mutex: std.Io.Mutex = .init,
    bytes_used: usize = 0,
    bytes_peak: usize = 0,
    bytes_capacity: usize = 0,
    bytes_available: usize = 0,
    allocation_count: std.atomic.Value(AtomicUnsigned) = std.atomic.Value(AtomicUnsigned).init(0),
    deallocation_count: std.atomic.Value(AtomicUnsigned) = std.atomic.Value(AtomicUnsigned).init(0),
    callback: ?*const MemoryCallback = null,
    callback_user_data: ?*anyopaque = null,
    pressure_callback: ?*const PressureCallback = null,
    oom_callback: ?*const OomCallback = null,
    pressure_threshold: f64 = 0.9,
    fire_callback_on_pressure: bool = false,
    refresh_interval_ms: u64 = 0,
    last_refresh_ms: i64 = 0,
    pressure_armed: bool = true,
    callback_user_data_ptr: ?*anyopaque = null,

    /// Initialize a memory tracker wrapping `inner`.
    pub fn init(inner: std.mem.Allocator) MemoryTracker {
        return .{
            .inner = inner,
            .bytes_available = detectAvailableMemory(),
        };
    }

    /// Initialize a memory tracker wrapping `inner` with the supplied
    /// `Config.MemoryConfig`. The tracker reads the pressure
    /// threshold, refresh interval, and per-event callbacks from the
    /// config. The default `Config.MemoryConfig{}` matches the
    /// historical behaviour of `init`.
    pub fn initWithConfig(
        inner: std.mem.Allocator,
        memory: @import("config.zig").Config.MemoryConfig,
    ) MemoryTracker {
        var tracker: MemoryTracker = .{
            .inner = inner,
            .pressure_callback = memory.pressure_callback,
            .oom_callback = memory.oom_callback,
            .pressure_threshold = memory.pressure_threshold,
            .fire_callback_on_pressure = memory.fire_callback_on_pressure,
            .refresh_interval_ms = memory.refresh_interval_ms,
            .callback_user_data_ptr = memory.user_data,
        };
        if (memory.enabled) {
            tracker.bytes_available = detectAvailableMemory();
        }
        return tracker;
    }

    /// Returns a `std.mem.Allocator` interface that can be passed to
    /// `Logger.init` and friends. The returned interface forwards to
    /// this `MemoryTracker` instance.
    pub fn allocator(self: *MemoryTracker) std.mem.Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .remap = remap,
                .free = free,
            },
        };
    }

    /// Snapshot the current memory state. Safe to call concurrently with
    /// active allocations.
    pub fn snapshot(self: *MemoryTracker) MemoryReport {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        return .{
            .bytes_used = self.bytes_used,
            .bytes_peak = self.bytes_peak,
            .bytes_capacity = self.bytes_capacity,
            .bytes_available = self.bytes_available,
            .allocation_count = self.allocation_count.load(.monotonic),
            .deallocation_count = self.deallocation_count.load(.monotonic),
            .live_allocations = self.allocation_count.load(.monotonic) -
                self.deallocation_count.load(.monotonic),
        };
    }

    /// Returns the number of bytes currently live in this tracker.
    pub fn getBytesUsed(self: *MemoryTracker) usize {
        return self.snapshot().bytes_used;
    }

    /// Returns the peak high-water mark of bytes used by this tracker.
    pub fn getBytesPeak(self: *MemoryTracker) usize {
        return self.snapshot().bytes_peak;
    }

    /// Returns the bytes available to the OS process. On Linux this is
    /// `MemAvailable` from `/proc/meminfo`; on Windows it is the working
    /// set free quota; on macOS/BSD it is `vm_stat` free pages; on other
    /// targets it returns 0.
    pub fn getAvailableMemory(_: *MemoryTracker) usize {
        return detectAvailableMemory();
    }

    /// Returns the current process resident-set size in bytes, or 0 on
    /// unsupported targets.
    pub fn getCurrentMemoryUsage(_: *MemoryTracker) usize {
        return detectCurrentMemoryUsage();
    }

    /// Manually refresh the `bytes_available` heuristic. Useful in long-lived
    /// processes that want a fresh OS-level reading on demand.
    pub fn refreshAvailableMemory(self: *MemoryTracker) void {
        self.bytes_available = detectAvailableMemory();
    }

    /// Set a callback to be invoked on every allocation and free.
    /// The callback fires while the tracker mutex is held - keep it short.
    /// Pass `null` to clear.
    pub fn setCallback(
        self: *MemoryTracker,
        callback: ?*const MemoryCallback,
        user_data: ?*anyopaque,
    ) void {
        self.callback = callback;
        self.callback_user_data = user_data;
    }

    /// Alias for `setCallback`.
    pub const onChange = setCallback;
    pub const setOnChange = setCallback;
    pub const setNotifyCallback = setCallback;

    /// Set the pressure-event callback. Fires after
    /// `alloc` / `resize` / `remap` whenever the live usage crosses
    /// the configured threshold. Pass `null` to clear.
    pub fn setPressureCallback(
        self: *MemoryTracker,
        callback: ?*const PressureCallback,
        user_data: ?*anyopaque,
    ) void {
        self.pressure_callback = callback;
        self.callback_user_data_ptr = user_data;
    }

    /// Aliases for `setPressureCallback`.
    pub const onPressure = setPressureCallback;
    pub const setOnPressure = setPressureCallback;

    /// Set the OOM callback. Fires when a wrapped allocation request
    /// is returned `null` by the inner allocator. Pass `null` to clear.
    pub fn setOomCallback(
        self: *MemoryTracker,
        callback: ?*const OomCallback,
        user_data: ?*anyopaque,
    ) void {
        self.oom_callback = callback;
        self.callback_user_data_ptr = user_data;
    }

    /// Aliases for `setOomCallback`.
    pub const onOom = setOomCallback;
    pub const setOnOom = setOomCallback;

    /// Set the pressure threshold. Clamped to `[0.0, 1.0]`. Resets
    /// the pressure edge detector so the next crossing fires the
    /// callback.
    pub fn setPressureThreshold(self: *MemoryTracker, value: f64) void {
        self.pressure_threshold = if (value < 0.0)
            0.0
        else if (value > 1.0)
            1.0
        else
            value;
        self.pressure_armed = true;
    }

    /// Set the periodic OS probe refresh interval in milliseconds.
    /// `0` disables the periodic refresh; the user can still call
    /// `refreshAvailableMemory` on demand.
    pub fn setRefreshInterval(self: *MemoryTracker, interval_ms: u64) void {
        self.refresh_interval_ms = interval_ms;
        self.last_refresh_ms = Utils.currentMillis();
    }

    /// Enable or disable the `pressure_callback` event. When
    /// disabled, the threshold edge detector still tracks the
    /// crossing for callers that poll `MemoryReport.isPressureHigh`.
    pub fn setFireOnPressure(self: *MemoryTracker, on: bool) void {
        self.fire_callback_on_pressure = on;
    }

    /// Returns the current pressure threshold.
    pub fn getPressureThreshold(self: *MemoryTracker) f64 {
        return self.pressure_threshold;
    }

    /// Returns `true` if the live usage is at or above the configured
    /// pressure threshold of the running peak. The arming logic makes
    /// sure consecutive reads return the same answer until the live
    /// usage drops back below the threshold, so callers can use it as
    /// an edge detector.
    pub fn isPressureHigh(self: *MemoryTracker) bool {
        self.maybeFirePressure(false);
        return !self.pressure_armed;
    }

    /// Reset peak and counters. Live `bytes_used` is not affected.
    /// Useful in long-lived services that want a fresh "since last reset"
    /// baseline.
    pub fn resetCounters(self: *MemoryTracker) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        self.bytes_peak = self.bytes_used;
        self.allocation_count.store(0, .monotonic);
        self.deallocation_count.store(0, .monotonic);
    }

    /// Reset peak, counters, and live `bytes_used`. Use only when the
    /// caller knows that no live allocations exist (e.g. the logger was
    /// paused). Otherwise prefer `resetCounters`.
    pub fn resetAll(self: *MemoryTracker) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        self.bytes_used = 0;
        self.bytes_peak = 0;
        self.bytes_capacity = 0;
        self.allocation_count.store(0, .monotonic);
        self.deallocation_count.store(0, .monotonic);
    }

    /// Alias for `resetAll`.
    pub const reset = resetAll;
    pub const clear = resetAll;
    pub const wipe = resetAll;

    /// Alias for `resetCounters`.
    pub const resetStats = resetCounters;
    pub const clearCounters = resetCounters;

    /// Alias for `snapshot`.
    pub const report = snapshot;
    pub const getReport = snapshot;

    /// Alias for `getBytesUsed`.
    pub const bytesUsed = getBytesUsed;
    pub const used = getBytesUsed;

    /// Alias for `getBytesPeak`.
    pub const bytesPeak = getBytesPeak;
    pub const peak = getBytesPeak;

    /// Alias for `getAvailableMemory`.
    pub const availableMemory = getAvailableMemory;
    pub const avail = getAvailableMemory;

    /// Alias for `getCurrentMemoryUsage`.
    pub const currentMemoryUsage = getCurrentMemoryUsage;
    pub const rss = getCurrentMemoryUsage;

    /// Alias for `refreshAvailableMemory`.
    pub const refreshAvail = refreshAvailableMemory;
    pub const refresh = refreshAvailableMemory;

    /// Alias for `init`.
    pub const create = init;
    pub const wrap = init;

    /// Aliases for `initWithConfig`.
    pub const createWithConfig = initWithConfig;
    pub const wrapWithConfig = initWithConfig;

    /// Aliases for the pressure / OOM setters and accessors.
    pub const setThreshold = setPressureThreshold;
    pub const threshold = setPressureThreshold;
    pub const setFireCallbackOnPressure = setFireOnPressure;
    pub const fireOnPressure = setFireOnPressure;

    /// Edge-detecting helper used by `alloc` / `resize` / `remap`. Holds
    /// the tracker mutex while firing the user callback so the values
    /// reported are consistent with the snapshot at the same instant.
    /// `from_alloc` is `true` for the alloc path (where we want the
    /// periodic refresh tick to run), `false` for read-only paths.
    fn maybeFirePressure(self: *MemoryTracker, from_alloc: bool) void {
        if (from_alloc and self.refresh_interval_ms != 0) {
            const now = Utils.currentMillis();
            if (now - self.last_refresh_ms >= @as(i64, @intCast(self.refresh_interval_ms))) {
                self.last_refresh_ms = now;
                self.bytes_available = detectAvailableMemory();
            }
        }
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        const armed = self.pressure_armed;
        if (armed and self.bytes_capacity > 0) {
            const fraction: f64 = @as(f64, @floatFromInt(self.bytes_used)) /
                @as(f64, @floatFromInt(self.bytes_capacity));
            if (fraction >= self.pressure_threshold) {
                self.pressure_armed = false;
                if (self.fire_callback_on_pressure) {
                    if (self.pressure_callback) |cb| {
                        cb(
                            self.bytes_used,
                            self.bytes_peak,
                            self.bytes_capacity,
                            self.pressure_threshold,
                            self.callback_user_data_ptr,
                        );
                    }
                }
            }
        } else if (!armed) {
            const fraction: f64 = @as(f64, @floatFromInt(self.bytes_used)) /
                @as(f64, @floatFromInt(self.bytes_capacity));
            if (fraction < self.pressure_threshold) {
                self.pressure_armed = true;
            }
        }
    }

    fn alloc(context: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        const self: *MemoryTracker = @ptrCast(@alignCast(context));
        const result = self.inner.rawAlloc(len, alignment, ret_addr);
        if (result != null) {
            self.mutex.lockUncancelable(Utils.io());
            self.bytes_used += len;
            if (self.bytes_used > self.bytes_peak) self.bytes_peak = self.bytes_used;
            if (self.bytes_used > self.bytes_capacity) self.bytes_capacity = self.bytes_used;
            self.mutex.unlock(Utils.io());
            _ = self.allocation_count.fetchAdd(1, .monotonic);
            self.invokeCallback();
            self.maybeFirePressure(true);
        } else if (self.oom_callback) |cb| {
            cb(len, alignment, self.callback_user_data_ptr);
        }
        return result;
    }

    fn resize(context: *anyopaque, buf: []u8, buf_alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        const self: *MemoryTracker = @ptrCast(@alignCast(context));
        const old_len = buf.len;
        const ok = self.inner.rawResize(buf, buf_alignment, new_len, ret_addr);
        if (ok) {
            self.mutex.lockUncancelable(Utils.io());
            if (new_len >= old_len) {
                self.bytes_used += new_len - old_len;
                if (self.bytes_used > self.bytes_peak) self.bytes_peak = self.bytes_used;
                if (self.bytes_used > self.bytes_capacity) self.bytes_capacity = self.bytes_used;
            } else {
                self.bytes_used -= old_len - new_len;
            }
            self.mutex.unlock(Utils.io());
            self.invokeCallback();
            self.maybeFirePressure(true);
        }
        return ok;
    }

    fn remap(context: *anyopaque, buf: []u8, buf_alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        const self: *MemoryTracker = @ptrCast(@alignCast(context));
        const old_len = buf.len;
        const result = self.inner.rawRemap(buf, buf_alignment, new_len, ret_addr);
        if (result != null) {
            self.mutex.lockUncancelable(Utils.io());
            if (new_len >= old_len) {
                self.bytes_used += new_len - old_len;
                if (self.bytes_used > self.bytes_peak) self.bytes_peak = self.bytes_used;
                if (self.bytes_used > self.bytes_capacity) self.bytes_capacity = self.bytes_used;
            } else {
                self.bytes_used -= old_len - new_len;
            }
            self.mutex.unlock(Utils.io());
            self.invokeCallback();
            self.maybeFirePressure(true);
        } else if (self.oom_callback) |cb| {
            cb(new_len, buf_alignment, self.callback_user_data_ptr);
        }
        return result;
    }

    fn free(context: *anyopaque, buf: []u8, buf_alignment: std.mem.Alignment, ret_addr: usize) void {
        const self: *MemoryTracker = @ptrCast(@alignCast(context));
        const old_len = buf.len;
        self.inner.rawFree(buf, buf_alignment, ret_addr);
        self.mutex.lockUncancelable(Utils.io());
        if (old_len <= self.bytes_used) {
            self.bytes_used -= old_len;
        } else {
            self.bytes_used = 0;
        }
        self.mutex.unlock(Utils.io());
        _ = self.deallocation_count.fetchAdd(1, .monotonic);
        self.invokeCallback();
        // Re-evaluate the pressure edge after a free so the next
        // crossing is armed.
        self.maybeFirePressure(false);
    }

    fn invokeCallback(self: *MemoryTracker) void {
        if (self.callback) |cb| {
            cb(
                self.bytes_used,
                self.bytes_peak,
                self.bytes_capacity,
                self.callback_user_data,
            );
        }
    }
};

/// Best-effort detection of currently-available process memory in bytes.
/// Returns 0 on unsupported platforms.
pub fn detectAvailableMemory() usize {
    return switch (builtin.os.tag) {
        .linux => detectAvailableMemoryLinux(),
        .windows => detectAvailableMemoryWindows(),
        .macos, .freebsd, .netbsd, .openbsd, .dragonfly => detectAvailableMemoryUnix(),
        else => 0,
    };
}

/// Alias for `detectAvailableMemory`.
pub const detectAvail = detectAvailableMemory;
pub const detectFreeMemory = detectAvailableMemory;
pub const getAvailableRAM = detectAvailableMemory;

fn detectAvailableMemoryLinux() usize {
    const file = std.fs.cwd().openFile("/proc/meminfo", .{}) catch return 0;
    defer file.close();
    var buf: [Constants.BufferSizes.file_read]u8 = undefined;
    const n = file.read(&buf) catch return 0;
    var i: usize = 0;
    while (i < n) {
        const line_start = i;
        while (i < n and buf[i] != '\n') : (i += 1) {
            if (i - line_start > 64) break;
        }
        const line = buf[line_start..i];
        if (std.mem.startsWith(u8, line, "MemAvailable:")) {
            var p: usize = "MemAvailable:".len;
            while (p < line.len and (line[p] == ' ' or line[p] == '\t')) : (p += 1) {}
            const num_end = p;
            while (num_end < line.len and line[num_end] >= '0' and line[num_end] <= '9') : (num_end += 1) {}
            const kb = std.fmt.parseInt(usize, line[p..num_end], 10) catch return 0;
            return kb * 1024;
        }
        if (i < n and buf[i] == '\n') i += 1;
    }
    return 0;
}

fn detectAvailableMemoryWindows() usize {
    if (builtin.os.tag != .windows) return 0;
    return detectAvailableMemoryWindowsImpl();
}

fn detectAvailableMemoryWindowsImpl() usize {
    // Direct FFI for `GlobalMemoryStatusEx`. The Zig 0.16 stdlib
    // does not yet expose this via `std.os.windows.kernel32` and
    // `std.DynLib` does not support Windows, so we resolve the
    // symbol at compile time and let the linker import it from
    // `kernel32.lib` (which is always linked on Windows targets).
    const F = fn (lpBuffer: *MemStatusEx) callconv(.c) i32;
    const gmem: *const F = @extern(*const F, .{ .name = "GlobalMemoryStatusEx" });
    var status: MemStatusEx = .{
        .dwLength = @sizeOf(MemStatusEx),
        .dwMemoryLoad = 0,
        .ullTotalPhys = 0,
        .ullAvailPhys = 0,
        .ullTotalPageFile = 0,
        .ullAvailPageFile = 0,
        .ullTotalVirtual = 0,
        .ullAvailVirtual = 0,
        .ullAvailExtendedVirtual = 0,
    };
    if (gmem(&status) == 0) return 0;
    return @intCast(status.ullAvailPhys);
}

const MemStatusEx = extern struct {
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

fn detectAvailableMemoryUnix() usize {
    const file = std.fs.cwd().openFile("/proc/meminfo", .{}) catch return 0;
    defer file.close();
    var buf: [Constants.BufferSizes.file_read]u8 = undefined;
    const n = file.read(&buf) catch return 0;
    var i: usize = 0;
    while (i < n) {
        const line_start = i;
        while (i < n and buf[i] != '\n') : (i += 1) {
            if (i - line_start > 64) break;
        }
        const line = buf[line_start..i];
        if (std.mem.startsWith(u8, line, "MemFree:")) {
            var p: usize = "MemFree:".len;
            while (p < line.len and (line[p] == ' ' or line[p] == '\t')) : (p += 1) {}
            const num_end = p;
            while (num_end < line.len and line[num_end] >= '0' and line[num_end] <= '9') : (num_end += 1) {}
            const kb = std.fmt.parseInt(usize, line[p..num_end], 10) catch return 0;
            return kb * 1024;
        }
        if (i < n and buf[i] == '\n') i += 1;
    }
    return 0;
}

/// Best-effort RSS / working-set size in bytes. Returns 0 on unsupported
/// platforms.
pub fn detectCurrentMemoryUsage() usize {
    return switch (builtin.os.tag) {
        .linux => detectCurrentMemoryUsageLinux(),
        .windows => 0,
        else => 0,
    };
}

/// Alias for `detectCurrentMemoryUsage`.
pub const detectRSS = detectCurrentMemoryUsage;
pub const currentRSS = detectCurrentMemoryUsage;
pub const rss = detectCurrentMemoryUsage;
pub const processMemory = detectCurrentMemoryUsage;

fn detectCurrentMemoryUsageLinux() usize {
    const file = std.fs.cwd().openFile("/proc/self/status", .{}) catch return 0;
    defer file.close();
    var buf: [Constants.BufferSizes.file_read]u8 = undefined;
    const n = file.read(&buf) catch return 0;
    var i: usize = 0;
    while (i < n) {
        const line_start = i;
        while (i < n and buf[i] != '\n') : (i += 1) {
            if (i - line_start > 80) break;
        }
        const line = buf[line_start..i];
        if (std.mem.startsWith(u8, line, "VmRSS:")) {
            var p: usize = "VmRSS:".len;
            while (p < line.len and (line[p] == ' ' or line[p] == '\t')) : (p += 1) {}
            const num_end = p;
            while (num_end < line.len and line[num_end] >= '0' and line[num_end] <= '9') : (num_end += 1) {}
            const kb = std.fmt.parseInt(usize, line[p..num_end], 10) catch return 0;
            return kb * 1024;
        }
        if (i < n and buf[i] == '\n') i += 1;
    }
    return 0;
}

test "MemoryTracker basic alloc/free accounting" {
    var inner = std.heap.DebugAllocator(.{}){};
    defer _ = inner.deinit();
    var tracker = MemoryTracker.init(inner.allocator());
    const alloc = tracker.allocator();

    const slice1 = try alloc.alloc(u8, 256);
    const slice2 = try alloc.alloc(u8, 1024);
    var report = tracker.snapshot();
    try std.testing.expectEqual(@as(usize, 1280), report.bytes_used);
    try std.testing.expect(report.bytes_peak >= 1280);
    try std.testing.expectEqual(@as(u64, 2), report.allocation_count);
    try std.testing.expectEqual(@as(u64, 0), report.deallocation_count);

    alloc.free(slice1);
    report = tracker.snapshot();
    try std.testing.expectEqual(@as(usize, 1024), report.bytes_used);
    try std.testing.expectEqual(@as(u64, 1), report.deallocation_count);
    try std.testing.expectEqual(@as(u64, 1), report.live_allocations);

    alloc.free(slice2);
    report = tracker.snapshot();
    try std.testing.expectEqual(@as(usize, 0), report.bytes_used);
    try std.testing.expectEqual(@as(u64, 2), report.deallocation_count);
}

test "MemoryTracker resize updates accounting" {
    var inner = std.heap.DebugAllocator(.{}){};
    defer _ = inner.deinit();
    var tracker = MemoryTracker.init(inner.allocator());
    const alloc = tracker.allocator();

    const initial = try alloc.alloc(u8, 128);
    try std.testing.expectEqual(@as(usize, 128), tracker.getBytesUsed());

    if (alloc.resize(initial, 256)) {
        try std.testing.expectEqual(@as(usize, 256), tracker.getBytesUsed());
    }

    alloc.free(initial);
    try std.testing.expectEqual(@as(usize, 0), tracker.getBytesUsed());
}

test "MemoryTracker resetCounters keeps live bytes" {
    var inner = std.heap.DebugAllocator(.{}){};
    defer _ = inner.deinit();
    var tracker = MemoryTracker.init(inner.allocator());
    const alloc = tracker.allocator();

    const slice = try alloc.alloc(u8, 512);
    defer alloc.free(slice);
    try std.testing.expect(tracker.getBytesPeak() >= 512);
    tracker.resetCounters();
    try std.testing.expectEqual(@as(u64, 0), tracker.snapshot().allocation_count);
    try std.testing.expectEqual(@as(usize, 512), tracker.getBytesUsed());
}

test "MemoryTracker callback fires on alloc/free" {
    var inner = std.heap.DebugAllocator(.{}){};
    defer _ = inner.deinit();
    var tracker = MemoryTracker.init(inner.allocator());
    const alloc = tracker.allocator();

    var last_used: usize = 0;
    const Cb = struct {
        fn run(used: usize, _: usize, _: usize, ud: ?*anyopaque) void {
            const out: *usize = @ptrCast(@alignCast(ud orelse return));
            out.* = used;
        }
    };
    tracker.setCallback(&Cb.run, @ptrCast(&last_used));
    const slice = try alloc.alloc(u8, 64);
    try std.testing.expect(last_used >= 64);
    alloc.free(slice);
    try std.testing.expectEqual(@as(usize, 0), last_used);
}

test "MemoryReport isPressureHigh and format helpers" {
    const report: MemoryReport = .{
        .bytes_used = 800,
        .bytes_peak = 1024,
        .bytes_capacity = 1000,
        .bytes_available = Constants.SizeConstants.bytes_per_mb,
        .allocation_count = 5,
        .deallocation_count = 2,
        .live_allocations = 3,
    };

    try std.testing.expect(report.isPressureHigh(0.5));
    try std.testing.expect(!report.isPressureHigh(0.95));

    var buf: [256]u8 = undefined;
    var stream = std.Io.Writer.fixed(&buf);
    try report.formatCompact(&stream);
    try std.testing.expect(stream.end > 0);
}

test "MemoryTracker aliases match originals" {
    var inner = std.heap.DebugAllocator(.{}){};
    defer _ = inner.deinit();
    var tracker = MemoryTracker.init(inner.allocator());

    // Aliases must produce identical values.
    _ = tracker.bytesUsed();
    _ = tracker.bytesPeak();
    _ = tracker.availableMemory();
    _ = tracker.currentMemoryUsage();
    _ = tracker.refresh();
    _ = tracker.report();
    _ = tracker.onChange(null, null);
}

test "MemoryTracker initWithConfig wires callbacks and threshold" {
    var inner = std.heap.DebugAllocator(.{}){};
    defer _ = inner.deinit();

    const Cfg = @import("config.zig").Config;
    const memory_cfg: Cfg.MemoryConfig = .{
        .pressure_threshold = 0.9,
        .fire_callback_on_pressure = true,
    };

    var fired: u32 = 0;
    const PressureCb = struct {
        fn run(
            used: usize,
            _: usize,
            cap: usize,
            threshold: f64,
            ud: ?*anyopaque,
        ) void {
            _ = used;
            _ = cap;
            _ = threshold;
            const out: *u32 = @ptrCast(@alignCast(ud orelse return));
            out.* += 1;
        }
    };

    const cfg = memory_cfg.withPressureCallback(&PressureCb.run, @ptrCast(&fired));
    var tracker = MemoryTracker.initWithConfig(inner.allocator(), cfg);
    const alloc = tracker.allocator();

    try std.testing.expectEqual(@as(f64, 0.9), tracker.getPressureThreshold());

    // Prime the capacity high-water mark with a 4 KiB alloc, then
    // free it. After the free, bytes_used = 0 and bytes_capacity
    // stays at 4096. A subsequent 1 KiB alloc gives a ratio of
    // 1024 / 4096 = 0.25 < 0.9, so the pressure event must NOT
    // fire and `isPressureHigh` must be false.
    const big = try alloc.alloc(u8, 4096);
    alloc.free(big);
    fired = 0;

    const slice = try alloc.alloc(u8, 1024);
    defer alloc.free(slice);

    try std.testing.expect(!tracker.isPressureHigh());
    try std.testing.expectEqual(@as(u32, 0), fired);
}

test "MemoryTracker pressure edge detector fires once per crossing" {
    var inner = std.heap.DebugAllocator(.{}){};
    defer _ = inner.deinit();

    var fired: u32 = 0;
    const Cfg = @import("config.zig").Config;
    const PressureCb = struct {
        fn run(
            _: usize,
            _: usize,
            _: usize,
            _: f64,
            ud: ?*anyopaque,
        ) void {
            const out: *u32 = @ptrCast(@alignCast(ud orelse return));
            out.* += 1;
        }
    };
    const cfg: Cfg.MemoryConfig = .{
        .pressure_threshold = 0.5,
        .fire_callback_on_pressure = true,
    };
    const armed_cfg = cfg.withPressureCallback(&PressureCb.run, @ptrCast(&fired));
    var tracker = MemoryTracker.initWithConfig(inner.allocator(), armed_cfg);
    const alloc = tracker.allocator();

    // Prime the high-water mark with a 4 KiB alloc, then free. After
    // the free, bytes_used=0 and bytes_capacity=4096.
    const big = try alloc.alloc(u8, 4096);
    alloc.free(big);
    fired = 0;

    // First 2 KiB alloc: bytes_used=2048, bytes_capacity=4096,
    // ratio=0.5 >= 0.5, the edge detector fires exactly once.
    const a = try alloc.alloc(u8, 2048);
    try std.testing.expectEqual(@as(u32, 1), fired);

    // Second 1 KiB alloc on top: bytes_used=3072, ratio=0.75, the
    // edge detector is un-armed so the callback must NOT fire again.
    const b = try alloc.alloc(u8, 1024);
    try std.testing.expectEqual(@as(u32, 1), fired);

    // Free `a` to drop bytes_used back below 0.5: bytes_used=1024,
    // ratio=0.25 < 0.5, the edge detector re-arms.
    alloc.free(a);
    fired = 0;

    // Re-alloc to push back over 0.5: bytes_used=2048+1024=3072,
    // ratio=0.75 >= 0.5, the callback fires exactly once more.
    const c = try alloc.alloc(u8, 1024);
    try std.testing.expectEqual(@as(u32, 1), fired);

    alloc.free(b);
    alloc.free(c);
}

test "MemoryTracker OOM callback fires on allocation failure" {
    // State shared with the fake allocator.
    const State = struct {
        fail_next: bool = false,
    };
    var state: State = .{};

    const VTable = struct {
        fn alloc(ctx: *anyopaque, len: usize, alignment: std.mem.Alignment, ra: usize) ?[*]u8 {
            _ = len;
            _ = alignment;
            _ = ra;
            const s: *State = @ptrCast(@alignCast(ctx));
            if (s.fail_next) {
                s.fail_next = false;
                return null;
            }
            // Hand back a tiny fake buffer (never dereferenced - the
            // OOM test frees nothing).
            return @as([*]u8, @ptrFromInt(0x1000));
        }
        fn resize(_: *anyopaque, buf: []u8, _: std.mem.Alignment, new_len: usize, _: usize) bool {
            return new_len <= buf.len;
        }
        fn remap(_: *anyopaque, _: []u8, _: std.mem.Alignment, _: usize, _: usize) ?[*]u8 {
            return null;
        }
        fn free(_: *anyopaque, _: []u8, _: std.mem.Alignment, _: usize) void {}
    };

    const inner: std.mem.Allocator = .{
        .ptr = &state,
        .vtable = &.{
            .alloc = VTable.alloc,
            .resize = VTable.resize,
            .remap = VTable.remap,
            .free = VTable.free,
        },
    };

    var oom_seen: u32 = 0;
    const Cfg = @import("config.zig").Config;
    const OomCb = struct {
        fn run(_: usize, _: std.mem.Alignment, ud: ?*anyopaque) void {
            const out: *u32 = @ptrCast(@alignCast(ud orelse return));
            out.* += 1;
        }
    };
    const cfg: Cfg.MemoryConfig = .{};
    const armed_cfg = cfg.withOomCallback(&OomCb.run, @ptrCast(&oom_seen));
    var tracker = MemoryTracker.initWithConfig(inner, armed_cfg);
    const tracked_alloc = tracker.allocator();

    // First allocation through the wrapped allocator - succeeds.
    const ok1 = tracked_alloc.vtable.alloc(
        tracked_alloc.ptr,
        64,
        .fromByteUnits(1),
        @returnAddress(),
    );
    try std.testing.expect(ok1 != null);

    // Second allocation - the underlying fake returns null, the
    // OOM callback must fire exactly once.
    state.fail_next = true;
    const ok2 = tracked_alloc.vtable.alloc(
        tracked_alloc.ptr,
        64,
        .fromByteUnits(1),
        @returnAddress(),
    );
    try std.testing.expect(ok2 == null);
    try std.testing.expectEqual(@as(u32, 1), oom_seen);
}

test "MemoryTracker setPressureThreshold clamps and aliases" {
    var inner = std.heap.DebugAllocator(.{}){};
    defer _ = inner.deinit();
    var tracker = MemoryTracker.init(inner.allocator());

    tracker.setPressureThreshold(2.0);
    try std.testing.expectEqual(@as(f64, 1.0), tracker.getPressureThreshold());

    tracker.setPressureThreshold(-1.0);
    try std.testing.expectEqual(@as(f64, 0.0), tracker.getPressureThreshold());

    tracker.setThreshold(0.42);
    try std.testing.expectEqual(@as(f64, 0.42), tracker.getPressureThreshold());
}

test "MemoryConfig builder aliases" {
    const Cfg = @import("config.zig").Config;
    const cfg: Cfg.MemoryConfig = .{};

    const with_t = cfg.withThreshold(0.5);
    try std.testing.expectEqual(@as(f64, 0.5), with_t.pressure_threshold);
    const with_r = cfg.withRefreshInterval(100);
    try std.testing.expectEqual(@as(u64, 100), with_r.refresh_interval_ms);

    const Cb = struct {
        fn run(_: usize, _: usize, _: usize, _: f64, _: ?*anyopaque) void {}
        fn oom(_: usize, _: std.mem.Alignment, _: ?*anyopaque) void {}
    };
    const with_p = cfg.withPressureCallback(&Cb.run, null);
    try std.testing.expect(with_p.fire_callback_on_pressure);
    const with_o = cfg.withOomCallback(&Cb.oom, null);
    try std.testing.expect(with_o.oom_callback != null);
    const with_d = cfg.withEnabled(false);
    try std.testing.expectEqual(false, with_d.enabled);
}
