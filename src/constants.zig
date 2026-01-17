//! Logly Constants Module
//!
//! Provides compile-time constants and configuration defaults for the
//! Logly logging library. All values are tuned for optimal performance
//! across different platforms and use cases.
//!
//! Categories:
//! - Atomic Types: Cross-platform atomic integer types
//! - Buffer Sizes: Default buffer sizes for various operations
//! - Thread Pool: Thread pool configuration defaults
//! - Level Constants: Log level priority ranges
//! - Time Constants: Time-related conversion factors
//! - Rotation Constants: File rotation defaults
//! - Network Constants: Network I/O settings
//! - Rules System: Diagnostic rules formatting

const builtin = @import("builtin");
const std = @import("std");

/// Architecture-dependent unsigned atomic integer type.
///
/// Provides the optimal atomic integer size for the target architecture.
/// Use this type for all atomic counters to ensure compatibility across
/// 32-bit and 64-bit targets (e.g., x86 vs x86_64).
///
/// Fixes: https://github.com/muhammad-fiaz/logly.zig/issues/11
pub const AtomicUnsigned = switch (builtin.target.cpu.arch) {
    .x86_64 => u64,
    .aarch64 => u64,
    .riscv64 => u64,
    .powerpc64 => u64,
    .x86 => u32,
    .arm => u32,
    else => u32,
};

/// Architecture-dependent signed atomic integer type.
///
/// Provides the optimal atomic signed integer size for the target architecture.
/// Use this type for atomic counters that may hold negative values.
pub const AtomicSigned = switch (builtin.target.cpu.arch) {
    .x86_64 => i64,
    .aarch64 => i64,
    .riscv64 => i64,
    .powerpc64 => i64,
    .x86 => i32,
    .arm => i32,
    else => i32,
};

/// Native pointer-sized unsigned integer for the target architecture.
pub const NativeUint = switch (builtin.target.cpu.arch) {
    .x86_64 => u64,
    .aarch64 => u64,
    .riscv64 => u64,
    .powerpc64 => u64,
    else => u32,
};

/// Native pointer-sized signed integer for the target architecture.
pub const NativeInt = switch (builtin.target.cpu.arch) {
    .x86_64 => i64,
    .aarch64 => i64,
    .riscv64 => i64,
    .powerpc64 => i64,
    else => i32,
};

/// Default buffer sizes for various operations.
///
/// Usage:
///   Use these constants to size internal buffers for logging, formatting, and I/O.
///
/// Complexity: O(1)
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
///
/// Usage:
///   Use these defaults when configuring the internal thread pool.
///
/// Complexity: O(1)
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
    ///
    /// Algorithm:
    ///   - Attempts to get CPU count from OS.
    ///   - Fallbacks to 4 if detection fails.
    ///
    /// Return Value:
    ///   - `usize`: Number of logical cores.
    ///
    /// Complexity: O(1)
    pub fn recommendedThreadCount() usize {
        return std.Thread.getCpuCount() catch 4;
    }

    /// Returns recommended thread count for I/O bound workloads.
    ///
    /// Algorithm:
    ///   - Returns `2 * logical_cores`.
    ///   - Useful for network/disk intensive logging.
    ///
    /// Return Value:
    ///   - `usize`: 2x logical cores.
    ///
    /// Complexity: O(1)
    pub fn ioBoundThreadCount() usize {
        return (std.Thread.getCpuCount() catch 4) * 2;
    }

    /// Returns recommended thread count for CPU bound workloads.
    ///
    /// Algorithm:
    ///   - Returns `logical_cores`.
    ///   - Useful for heavy compression or complex formatting.
    ///
    /// Return Value:
    ///   - `usize`: Logical cores.
    ///
    /// Complexity: O(1)
    pub fn cpuBoundThreadCount() usize {
        return std.Thread.getCpuCount() catch 4;
    }
};

/// Log level count and priorities.
///
/// Usage:
///   Reference constants for defining new log levels or validating priority ranges.
///
/// Complexity: O(1)
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
///
/// Usage:
///   Unit conversions and default time intervals.
///
/// Complexity: O(1)
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
///
/// Usage:
///   Defaults for file size limits and retention policies.
///
/// Complexity: O(1)
pub const RotationConstants = struct {
    /// Default max file size before rotation (10MB).
    pub const default_max_size: u64 = 10 * 1024 * 1024;
    /// Default max number of backup files.
    pub const default_max_files: usize = 5;
    /// Default compressed file extension.
    pub const compressed_ext: []const u8 = ".gz";
};

/// ANSI color constants for terminal output.
///
/// Usage:
///   Use these constants for consistent color codes across the library.
///   Supports basic colors, bright colors, background colors, styles, RGB, and 256-color palette.
///
/// Complexity: O(1)
pub const Colors = struct {
    /// Reset all formatting.
    pub const reset: []const u8 = "0";

    /// Basic foreground colors (30-37).
    pub const Fg = struct {
        pub const black: []const u8 = "30";
        pub const red: []const u8 = "31";
        pub const green: []const u8 = "32";
        pub const yellow: []const u8 = "33";
        pub const blue: []const u8 = "34";
        pub const magenta: []const u8 = "35";
        pub const cyan: []const u8 = "36";
        pub const white: []const u8 = "37";
        pub const default: []const u8 = "39";
    };

    /// Bright foreground colors (90-97).
    pub const BrightFg = struct {
        pub const black: []const u8 = "90";
        pub const red: []const u8 = "91";
        pub const green: []const u8 = "92";
        pub const yellow: []const u8 = "93";
        pub const blue: []const u8 = "94";
        pub const magenta: []const u8 = "95";
        pub const cyan: []const u8 = "96";
        pub const white: []const u8 = "97";
    };

    /// Background colors (40-47).
    pub const Bg = struct {
        pub const black: []const u8 = "40";
        pub const red: []const u8 = "41";
        pub const green: []const u8 = "42";
        pub const yellow: []const u8 = "43";
        pub const blue: []const u8 = "44";
        pub const magenta: []const u8 = "45";
        pub const cyan: []const u8 = "46";
        pub const white: []const u8 = "47";
        pub const default: []const u8 = "49";
    };

    /// Bright background colors (100-107).
    pub const BrightBg = struct {
        pub const black: []const u8 = "100";
        pub const red: []const u8 = "101";
        pub const green: []const u8 = "102";
        pub const yellow: []const u8 = "103";
        pub const blue: []const u8 = "104";
        pub const magenta: []const u8 = "105";
        pub const cyan: []const u8 = "106";
        pub const white: []const u8 = "107";
    };

    /// Text styles.
    pub const Style = struct {
        pub const bold: []const u8 = "1";
        pub const dim: []const u8 = "2";
        pub const italic: []const u8 = "3";
        pub const underline: []const u8 = "4";
        pub const blink: []const u8 = "5";
        pub const rapid_blink: []const u8 = "6";
        pub const reverse: []const u8 = "7";
        pub const hidden: []const u8 = "8";
        pub const strikethrough: []const u8 = "9";
        pub const double_underline: []const u8 = "21";
        pub const framed: []const u8 = "51";
        pub const encircled: []const u8 = "52";
        pub const overlined: []const u8 = "53";
    };

    /// Generate 256-color foreground code (0-255).
    pub fn fg256(color_index: u8) []const u8 {
        const S = struct {
            var buf: [16]u8 = undefined;
        };
        const len = std.fmt.bufPrint(&S.buf, "38;5;{d}", .{color_index}) catch return "38;5;0";
        return S.buf[0..len.len];
    }

    /// Generate 256-color background code (0-255).
    pub fn bg256(color_index: u8) []const u8 {
        const S = struct {
            var buf: [16]u8 = undefined;
        };
        const len = std.fmt.bufPrint(&S.buf, "48;5;{d}", .{color_index}) catch return "48;5;0";
        return S.buf[0..len.len];
    }

    /// Generate RGB foreground color code.
    pub fn fgRgb(r: u8, g: u8, b: u8) []const u8 {
        const S = struct {
            var buf: [24]u8 = undefined;
        };
        const len = std.fmt.bufPrint(&S.buf, "38;2;{d};{d};{d}", .{ r, g, b }) catch return "38;2;0;0;0";
        return S.buf[0..len.len];
    }

    /// Generate RGB background color code.
    pub fn bgRgb(r: u8, g: u8, b: u8) []const u8 {
        const S = struct {
            var buf: [24]u8 = undefined;
        };
        const len = std.fmt.bufPrint(&S.buf, "48;2;{d};{d};{d}", .{ r, g, b }) catch return "48;2;0;0;0";
        return S.buf[0..len.len];
    }

    /// Combine multiple codes (e.g., "1;31" for bold red).
    pub fn combine(comptime codes: []const []const u8) []const u8 {
        comptime {
            var result: []const u8 = "";
            for (codes, 0..) |code, i| {
                if (i > 0) result = result ++ ";";
                result = result ++ code;
            }
            return result;
        }
    }

    /// Predefined log level colors.
    pub const LevelColors = struct {
        pub const trace: []const u8 = "36";
        pub const debug: []const u8 = "34";
        pub const info: []const u8 = "37";
        pub const notice: []const u8 = "96";
        pub const success: []const u8 = "32";
        pub const warning: []const u8 = "33";
        pub const err: []const u8 = "31";
        pub const fail: []const u8 = "35";
        pub const critical: []const u8 = "91";
        pub const fatal: []const u8 = "97;41";
    };

    /// Predefined theme presets.
    pub const Themes = struct {
        /// Default theme with standard colors.
        pub const default_theme = struct {
            pub const trace: []const u8 = "36";
            pub const debug: []const u8 = "34";
            pub const info: []const u8 = "37";
            pub const notice: []const u8 = "96";
            pub const success: []const u8 = "32";
            pub const warning: []const u8 = "33";
            pub const err: []const u8 = "31";
            pub const fail: []const u8 = "35";
            pub const critical: []const u8 = "91";
            pub const fatal: []const u8 = "97;41";
        };

        /// Bright theme with bold colors.
        pub const bright = struct {
            pub const trace: []const u8 = "96;1";
            pub const debug: []const u8 = "94;1";
            pub const info: []const u8 = "97;1";
            pub const notice: []const u8 = "96;1";
            pub const success: []const u8 = "92;1";
            pub const warning: []const u8 = "93;1";
            pub const err: []const u8 = "91;1";
            pub const fail: []const u8 = "95;1";
            pub const critical: []const u8 = "91;1;4";
            pub const fatal: []const u8 = "97;41;1";
        };

        /// Dim theme with subtle colors.
        pub const dim = struct {
            pub const trace: []const u8 = LevelColors.trace ++ ";" ++ Style.dim;
            pub const debug: []const u8 = LevelColors.debug ++ ";" ++ Style.dim;
            pub const info: []const u8 = LevelColors.info ++ ";" ++ Style.dim;
            pub const notice: []const u8 = LevelColors.notice ++ ";" ++ Style.dim;
            pub const success: []const u8 = LevelColors.success ++ ";" ++ Style.dim;
            pub const warning: []const u8 = LevelColors.warning ++ ";" ++ Style.dim;
            pub const err: []const u8 = LevelColors.err ++ ";" ++ Style.dim;
            pub const fail: []const u8 = LevelColors.fail ++ ";" ++ Style.dim;
            pub const critical: []const u8 = LevelColors.critical ++ ";" ++ Style.dim;
            pub const fatal: []const u8 = LevelColors.fatal ++ ";" ++ Style.dim;
        };

        /// Underlined theme for highlighted levels.
        pub const underlined = struct {
            pub const trace: []const u8 = LevelColors.trace ++ ";" ++ Style.underline;
            pub const debug: []const u8 = LevelColors.debug ++ ";" ++ Style.underline;
            pub const info: []const u8 = LevelColors.info ++ ";" ++ Style.underline;
            pub const notice: []const u8 = LevelColors.notice ++ ";" ++ Style.underline;
            pub const success: []const u8 = LevelColors.success ++ ";" ++ Style.underline;
            pub const warning: []const u8 = LevelColors.warning ++ ";" ++ Style.underline;
            pub const err: []const u8 = LevelColors.err ++ ";" ++ Style.underline;
            pub const fail: []const u8 = LevelColors.fail ++ ";" ++ Style.underline;
            pub const critical: []const u8 = LevelColors.critical ++ ";" ++ Style.underline;
            pub const fatal: []const u8 = LevelColors.fatal ++ ";" ++ Style.underline;
        };

        /// Minimal theme with subtle colors.
        pub const minimal = struct {
            pub const trace: []const u8 = "90";
            pub const debug: []const u8 = "90";
            pub const info: []const u8 = "37";
            pub const notice: []const u8 = "37";
            pub const success: []const u8 = "32";
            pub const warning: []const u8 = "33";
            pub const err: []const u8 = "31";
            pub const fail: []const u8 = "31";
            pub const critical: []const u8 = "31;1";
            pub const fatal: []const u8 = "31;1;4";
        };

        /// Neon theme with vivid 256-colors.
        pub const neon = struct {
            pub const trace: []const u8 = "38;5;51";
            pub const debug: []const u8 = "38;5;33";
            pub const info: []const u8 = "38;5;255";
            pub const notice: []const u8 = "38;5;123";
            pub const success: []const u8 = "38;5;46";
            pub const warning: []const u8 = "38;5;226";
            pub const err: []const u8 = "38;5;196";
            pub const fail: []const u8 = "38;5;201";
            pub const critical: []const u8 = "38;5;196;1";
            pub const fatal: []const u8 = "38;5;231;48;5;196;1";
        };

        /// Pastel theme with soft colors.
        pub const pastel = struct {
            pub const trace: []const u8 = "38;5;159";
            pub const debug: []const u8 = "38;5;117";
            pub const info: []const u8 = "38;5;188";
            pub const notice: []const u8 = "38;5;153";
            pub const success: []const u8 = "38;5;157";
            pub const warning: []const u8 = "38;5;222";
            pub const err: []const u8 = "38;5;210";
            pub const fail: []const u8 = "38;5;218";
            pub const critical: []const u8 = "38;5;203";
            pub const fatal: []const u8 = "38;5;231;48;5;203";
        };

        /// Dark theme optimized for dark terminals.
        pub const dark = struct {
            pub const trace: []const u8 = "38;5;244";
            pub const debug: []const u8 = "38;5;75";
            pub const info: []const u8 = "38;5;252";
            pub const notice: []const u8 = "38;5;81";
            pub const success: []const u8 = "38;5;114";
            pub const warning: []const u8 = "38;5;220";
            pub const err: []const u8 = "38;5;203";
            pub const fail: []const u8 = "38;5;168";
            pub const critical: []const u8 = "38;5;196;1";
            pub const fatal: []const u8 = "38;5;231;48;5;124;1";
        };

        /// Light theme optimized for light terminals.
        pub const light = struct {
            pub const trace: []const u8 = "38;5;242";
            pub const debug: []const u8 = "38;5;24";
            pub const info: []const u8 = "38;5;235";
            pub const notice: []const u8 = "38;5;30";
            pub const success: []const u8 = "38;5;28";
            pub const warning: []const u8 = "38;5;130";
            pub const err: []const u8 = "38;5;124";
            pub const fail: []const u8 = "38;5;127";
            pub const critical: []const u8 = "38;5;160;1";
            pub const fatal: []const u8 = "38;5;231;48;5;160;1";
        };
    };
};

/// Network logging constants.
///
/// Usage:
///   Buffer sizes and timeouts for network sinks.
///
/// Complexity: O(1)
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
///
/// Usage:
///   Definitions for formatting rule-based diagnostics (prefixes, colors).
///
/// Complexity: O(1)
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

test "color constants foreground" {
    try std.testing.expectEqualStrings("30", Colors.Fg.black);
    try std.testing.expectEqualStrings("31", Colors.Fg.red);
    try std.testing.expectEqualStrings("32", Colors.Fg.green);
    try std.testing.expectEqualStrings("33", Colors.Fg.yellow);
    try std.testing.expectEqualStrings("34", Colors.Fg.blue);
    try std.testing.expectEqualStrings("35", Colors.Fg.magenta);
    try std.testing.expectEqualStrings("36", Colors.Fg.cyan);
    try std.testing.expectEqualStrings("37", Colors.Fg.white);
}

test "color constants bright foreground" {
    try std.testing.expectEqualStrings("90", Colors.BrightFg.black);
    try std.testing.expectEqualStrings("91", Colors.BrightFg.red);
    try std.testing.expectEqualStrings("92", Colors.BrightFg.green);
    try std.testing.expectEqualStrings("93", Colors.BrightFg.yellow);
    try std.testing.expectEqualStrings("94", Colors.BrightFg.blue);
    try std.testing.expectEqualStrings("95", Colors.BrightFg.magenta);
    try std.testing.expectEqualStrings("96", Colors.BrightFg.cyan);
    try std.testing.expectEqualStrings("97", Colors.BrightFg.white);
}

test "color constants background" {
    try std.testing.expectEqualStrings("40", Colors.Bg.black);
    try std.testing.expectEqualStrings("41", Colors.Bg.red);
    try std.testing.expectEqualStrings("42", Colors.Bg.green);
    try std.testing.expectEqualStrings("47", Colors.Bg.white);
}

test "color constants styles" {
    try std.testing.expectEqualStrings("1", Colors.Style.bold);
    try std.testing.expectEqualStrings("2", Colors.Style.dim);
    try std.testing.expectEqualStrings("3", Colors.Style.italic);
    try std.testing.expectEqualStrings("4", Colors.Style.underline);
    try std.testing.expectEqualStrings("7", Colors.Style.reverse);
    try std.testing.expectEqualStrings("9", Colors.Style.strikethrough);
}

test "color constants level colors" {
    try std.testing.expectEqualStrings("36", Colors.LevelColors.trace);
    try std.testing.expectEqualStrings("34", Colors.LevelColors.debug);
    try std.testing.expectEqualStrings("37", Colors.LevelColors.info);
    try std.testing.expectEqualStrings("32", Colors.LevelColors.success);
    try std.testing.expectEqualStrings("33", Colors.LevelColors.warning);
    try std.testing.expectEqualStrings("31", Colors.LevelColors.err);
    try std.testing.expectEqualStrings("91", Colors.LevelColors.critical);
    try std.testing.expectEqualStrings("97;41", Colors.LevelColors.fatal);
}

test "color themes default" {
    try std.testing.expectEqualStrings("36", Colors.Themes.default_theme.trace);
    try std.testing.expectEqualStrings("34", Colors.Themes.default_theme.debug);
    try std.testing.expectEqualStrings("37", Colors.Themes.default_theme.info);
    try std.testing.expectEqualStrings("31", Colors.Themes.default_theme.err);
}

test "color themes bright" {
    try std.testing.expectEqualStrings("96;1", Colors.Themes.bright.trace);
    try std.testing.expectEqualStrings("94;1", Colors.Themes.bright.debug);
    try std.testing.expectEqualStrings("97;1", Colors.Themes.bright.info);
    try std.testing.expectEqualStrings("91;1", Colors.Themes.bright.err);
}

test "color themes neon 256-color" {
    try std.testing.expectEqualStrings("38;5;51", Colors.Themes.neon.trace);
    try std.testing.expectEqualStrings("38;5;33", Colors.Themes.neon.debug);
    try std.testing.expectEqualStrings("38;5;196", Colors.Themes.neon.err);
}

test "color themes pastel" {
    try std.testing.expectEqualStrings("38;5;159", Colors.Themes.pastel.trace);
    try std.testing.expectEqualStrings("38;5;210", Colors.Themes.pastel.err);
}

test "color themes dark and light" {
    try std.testing.expect(Colors.Themes.dark.trace.len > 0);
    try std.testing.expect(Colors.Themes.light.trace.len > 0);
    try std.testing.expect(Colors.Themes.dark.err.len > 0);
    try std.testing.expect(Colors.Themes.light.err.len > 0);
}
