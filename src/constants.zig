const builtin = @import("builtin");
const std = @import("std");

/// Architecture-dependent atomic integer sizes.
/// Use these aliases for any atomic counters to ensure compatibility
/// across 32-bit and 64-bit targets (e.g., x86 vs x86_64).
/// fixes: https://github.com/muhammad-fiaz/logly.zig/issues/11
pub const AtomicUnsigned = switch (builtin.target.cpu.arch) {
    .x86_64 => u64,
    .aarch64 => u64,
    .riscv64 => u64,
    .powerpc64 => u64,
    .x86 => u32,
    .arm => u32,
    else => u32,
};

pub const AtomicSigned = switch (builtin.target.cpu.arch) {
    .x86_64 => i64,
    .aarch64 => i64,
    .riscv64 => i64,
    .powerpc64 => i64,
    .x86 => i32,
    .arm => i32,
    else => i32,
};

// For convenience expose the native pointer-sized unsigned integer
pub const NativeUint = switch (builtin.target.cpu.arch) {
    .x86_64 => u64,
    .aarch64 => u64,
    .riscv64 => u64,
    .powerpc64 => u64,
    else => u32,
};

// For convenience expose the native pointer-sized signed integer
pub const NativeInt = switch (builtin.target.cpu.arch) {
    .x86_64 => i64,
    .aarch64 => i64,
    .riscv64 => i64,
    .powerpc64 => i64,
    else => i32,
};

/// Default buffer sizes for various operations.
pub const BufferSizes = struct {
    /// Default log message buffer size.
    pub const message: usize = 4096;
    /// Default format buffer size.
    pub const format: usize = 8192;
    /// Default sink buffer size.
    pub const sink: usize = 16384;
    /// Default async queue buffer size.
    pub const async_queue: usize = 8192;
    /// Default compression buffer size.
    pub const compression: usize = 32768;
    /// Maximum log message size.
    pub const max_message: usize = 1024 * 1024; // 1MB
};

/// Default thread pool settings.
pub const ThreadDefaults = struct {
    /// Default number of threads (0 = auto-detect).
    pub const thread_count: usize = 0;
    /// Default queue size per thread.
    pub const queue_size: usize = 1024;
    /// Default stack size for worker threads.
    pub const stack_size: usize = 1024 * 1024; // 1MB
    /// Default wait timeout in nanoseconds.
    pub const wait_timeout_ns: u64 = 100 * std.time.ns_per_ms;
    /// Maximum concurrent tasks.
    pub const max_tasks: usize = 10000;

    /// Returns recommended thread count for current CPU.
    pub fn recommendedThreadCount() usize {
        return std.Thread.getCpuCount() catch 4;
    }

    /// Returns recommended thread count for I/O bound workloads.
    pub fn ioBoundThreadCount() usize {
        return (std.Thread.getCpuCount() catch 4) * 2;
    }

    /// Returns recommended thread count for CPU bound workloads.
    pub fn cpuBoundThreadCount() usize {
        return std.Thread.getCpuCount() catch 4;
    }
};

/// Log level count and priorities.
pub const LevelConstants = struct {
    /// Total number of built-in log levels.
    pub const count: usize = 10;
    /// Minimum priority value.
    pub const min_priority: u8 = 5; // TRACE
    /// Maximum priority value.
    pub const max_priority: u8 = 55; // FATAL
    /// Default level priority.
    pub const default_priority: u8 = 20; // INFO
};

/// Time-related constants.
pub const TimeConstants = struct {
    /// Milliseconds per second.
    pub const ms_per_second: u64 = 1000;
    /// Microseconds per second.
    pub const us_per_second: u64 = 1_000_000;
    /// Nanoseconds per second.
    pub const ns_per_second: u64 = 1_000_000_000;
    /// Default flush interval in milliseconds.
    pub const default_flush_interval_ms: u64 = 100;
    /// Default rotation check interval in milliseconds.
    pub const rotation_check_interval_ms: u64 = 60_000; // 1 minute
};

/// File rotation constants.
pub const RotationConstants = struct {
    /// Default max file size before rotation (10MB).
    pub const default_max_size: u64 = 10 * 1024 * 1024;
    /// Default max number of backup files.
    pub const default_max_files: usize = 5;
    /// Default compressed file extension.
    pub const compressed_ext: []const u8 = ".gz";
};

/// Network logging constants.
pub const NetworkConstants = struct {
    /// Default TCP buffer size.
    pub const tcp_buffer_size: usize = 8192;
    /// Default UDP max packet size.
    pub const udp_max_packet: usize = 65507;
    /// Default connection timeout in milliseconds.
    pub const connect_timeout_ms: u64 = 5000;
    /// Default send timeout in milliseconds.
    pub const send_timeout_ms: u64 = 1000;
};
