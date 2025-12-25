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

/// Rules system constants for diagnostic message formatting.
pub const RulesConstants = struct {
    /// Default indentation for rule messages.
    pub const default_indent: []const u8 = "    ";
    /// Default prefix character for rule messages.
    pub const default_prefix: []const u8 = "↳";
    /// Default prefix character for ASCII mode.
    pub const default_prefix_ascii: []const u8 = "|--";
    /// Maximum number of rules allowed by default.
    pub const default_max_rules: usize = 1000;
    /// Maximum messages per rule allowed by default.
    pub const default_max_messages: usize = 10;

    /// Unicode prefixes for each message category.
    pub const Prefixes = struct {
        pub const cause: []const u8 = "⦿ cause:";
        pub const fix: []const u8 = "✦ fix:";
        pub const suggest: []const u8 = "→ suggest:";
        pub const action: []const u8 = "▸ action:";
        pub const docs: []const u8 = "📖 docs:";
        pub const report: []const u8 = "🔗 report:";
        pub const note: []const u8 = "ℹ note:";
        pub const caution: []const u8 = "⚠ caution:";
        pub const perf: []const u8 = "⚡ perf:";
        pub const security: []const u8 = "🛡 security:";
        pub const custom: []const u8 = "•";
    };

    /// ASCII-only prefixes for each message category.
    pub const PrefixesAscii = struct {
        pub const cause: []const u8 = "[CAUSE]";
        pub const fix: []const u8 = "[FIX]";
        pub const suggest: []const u8 = "[SUGGEST]";
        pub const action: []const u8 = "[ACTION]";
        pub const docs: []const u8 = "[DOCS]";
        pub const report: []const u8 = "[REPORT]";
        pub const note: []const u8 = "[NOTE]";
        pub const caution: []const u8 = "[CAUTION]";
        pub const perf: []const u8 = "[PERF]";
        pub const security: []const u8 = "[SECURITY]";
        pub const custom: []const u8 = "[*]";
    };

    /// ANSI color codes for each message category.
    pub const Colors = struct {
        pub const cause: []const u8 = "91;1"; // Bright red
        pub const fix: []const u8 = "96;1"; // Bright cyan
        pub const suggest: []const u8 = "93;1"; // Bright yellow
        pub const action: []const u8 = "91;1"; // Bold red
        pub const docs: []const u8 = "35"; // Magenta
        pub const report: []const u8 = "33"; // Yellow
        pub const note: []const u8 = "37"; // White
        pub const caution: []const u8 = "33"; // Yellow
        pub const perf: []const u8 = "36"; // Cyan
        pub const security: []const u8 = "95;1"; // Bright magenta
        pub const custom: []const u8 = "37"; // White
    };
};

test "atomic types exist" {
    // Verify atomic types are defined for cross-platform compatibility
    try std.testing.expect(@sizeOf(AtomicUnsigned) > 0);
    try std.testing.expect(@sizeOf(AtomicSigned) > 0);
    try std.testing.expect(@sizeOf(NativeUint) > 0);
    try std.testing.expect(@sizeOf(NativeInt) > 0);
}

test "buffer sizes are reasonable" {
    try std.testing.expect(BufferSizes.message > 0);
    try std.testing.expect(BufferSizes.format >= BufferSizes.message);
    try std.testing.expect(BufferSizes.sink >= BufferSizes.format);
    try std.testing.expect(BufferSizes.max_message >= BufferSizes.sink);
}

test "thread defaults are reasonable" {
    try std.testing.expect(ThreadDefaults.stack_size > 0);
    try std.testing.expect(ThreadDefaults.queue_size > 0);
    try std.testing.expect(ThreadDefaults.max_tasks > 0);
    try std.testing.expect(ThreadDefaults.wait_timeout_ns > 0);
}

test "level constants are valid" {
    try std.testing.expect(LevelConstants.count > 0);
    try std.testing.expect(LevelConstants.min_priority < LevelConstants.max_priority);
    try std.testing.expect(LevelConstants.default_priority >= LevelConstants.min_priority);
    try std.testing.expect(LevelConstants.default_priority <= LevelConstants.max_priority);
}

test "time constants are correct" {
    try std.testing.expectEqual(@as(u64, 1000), TimeConstants.ms_per_second);
    try std.testing.expectEqual(@as(u64, 1_000_000), TimeConstants.us_per_second);
    try std.testing.expectEqual(@as(u64, 1_000_000_000), TimeConstants.ns_per_second);
}

test "rotation constants are reasonable" {
    try std.testing.expect(RotationConstants.default_max_size > 0);
    try std.testing.expect(RotationConstants.default_max_files > 0);
    try std.testing.expect(RotationConstants.compressed_ext.len > 0);
}

test "network constants are reasonable" {
    try std.testing.expect(NetworkConstants.tcp_buffer_size > 0);
    try std.testing.expect(NetworkConstants.udp_max_packet > 0);
    try std.testing.expect(NetworkConstants.connect_timeout_ms > 0);
    try std.testing.expect(NetworkConstants.send_timeout_ms > 0);
}

test "rules constants exist" {
    // Default values
    try std.testing.expect(RulesConstants.default_indent.len > 0);
    try std.testing.expect(RulesConstants.default_prefix.len > 0);
    try std.testing.expect(RulesConstants.default_prefix_ascii.len > 0);
    try std.testing.expect(RulesConstants.default_max_rules > 0);
    try std.testing.expect(RulesConstants.default_max_messages > 0);

    // Unicode prefixes
    try std.testing.expect(RulesConstants.Prefixes.cause.len > 0);
    try std.testing.expect(RulesConstants.Prefixes.fix.len > 0);
    try std.testing.expect(RulesConstants.Prefixes.suggest.len > 0);
    try std.testing.expect(RulesConstants.Prefixes.action.len > 0);
    try std.testing.expect(RulesConstants.Prefixes.docs.len > 0);
    try std.testing.expect(RulesConstants.Prefixes.report.len > 0);
    try std.testing.expect(RulesConstants.Prefixes.note.len > 0);
    try std.testing.expect(RulesConstants.Prefixes.caution.len > 0);
    try std.testing.expect(RulesConstants.Prefixes.perf.len > 0);
    try std.testing.expect(RulesConstants.Prefixes.security.len > 0);
    try std.testing.expect(RulesConstants.Prefixes.custom.len > 0);

    // ASCII prefixes
    try std.testing.expect(RulesConstants.PrefixesAscii.cause.len > 0);
    try std.testing.expect(RulesConstants.PrefixesAscii.fix.len > 0);
    try std.testing.expect(RulesConstants.PrefixesAscii.security.len > 0);

    // Colors
    try std.testing.expect(RulesConstants.Colors.cause.len > 0);
    try std.testing.expect(RulesConstants.Colors.fix.len > 0);
    try std.testing.expect(RulesConstants.Colors.security.len > 0);
}
