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

const std = @import("std");

// Internal buffer pool used by color formatting helpers (fg256/bg256/fgRgb/bgRgb).
// Uses a small ring of static buffers to avoid heap allocations and return stable slices.
var colorBufIndex: std.atomic.Value(usize) = std.atomic.Value(usize).init(0);
var colorBufs: [8][32]u8 = undefined;

/// Architecture-dependent unsigned atomic integer type.
///
/// Derived from native pointer width, so it naturally supports both
/// current and future 32-bit / 64-bit architectures.
///
/// Fixes: https://github.com/muhammad-fiaz/logly.zig/issues/11
pub const AtomicUnsigned = @Int(.unsigned, @bitSizeOf(usize));

/// Architecture-dependent signed atomic integer type.
///
/// Derived from native pointer width to keep signed counters aligned with
/// platform word size across 32-bit and 64-bit targets.
pub const AtomicSigned = @Int(.signed, @bitSizeOf(usize));

/// Native pointer-sized unsigned integer for the target architecture.
pub const NativeUint = usize;

/// Native pointer-sized signed integer for the target architecture.
pub const NativeInt = isize;

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
    /// Default telemetry buffer size.
    pub const telemetry: usize = 4096;
    /// Maximum log message size.
    pub const max_message: usize = 1024 * 1024; // 1MB
    /// Async batch size.
    pub const async_batch: usize = 64;
    /// Small buffer for thread IDs etc.
    pub const tiny: usize = 32;
    /// Small buffer for context values etc.
    pub const small: usize = 256;
    /// Standard file read buffer.
    pub const file_read: usize = 4096;
    /// Large file read buffer.
    pub const file_read_large: usize = 8192;
    /// Path buffer size.
    pub const path_buffer: usize = 512;
};

/// Size unit constants for consistent byte/KB/MB/GB conversions.
///
/// Usage:
///   Use these constants for consistent size calculations and conversions.
///
/// Complexity: O(1)
pub const SizeConstants = struct {
    /// Bytes per kilobyte (1024).
    pub const bytes_per_kb: u64 = 1024;
    /// Bytes per megabyte (1024 * 1024).
    pub const bytes_per_mb: u64 = 1024 * 1024;
    /// Bytes per gigabyte (1024 * 1024 * 1024).
    pub const bytes_per_gb: u64 = 1024 * 1024 * 1024;
    /// Bytes per terabyte (1024 * 1024 * 1024 * 1024).
    pub const bytes_per_tb: u64 = 1024 * 1024 * 1024 * 1024;
};

/// Compression file extension constants.
///
/// Usage:
///   Use these constants to check if a file is already compressed,
///   or to determine the compression format of a file.
///
/// Complexity: O(1)
pub const CompressionExtensions = struct {
    /// Gzip compressed file extension.
    pub const gz: []const u8 = ".gz";
    /// Logly gzip compressed file extension.
    pub const lgz: []const u8 = ".lgz";
    /// Zstandard compressed file extension.
    pub const zst: []const u8 = ".zst";
    /// Deflate compressed file extension.
    pub const deflate: []const u8 = ".deflate";
    /// LZMA compressed file extension.
    pub const lzma: []const u8 = ".lzma";
    /// LZMA2 compressed file extension.
    pub const lzma2: []const u8 = ".lzma2";
    /// XZ compressed file extension.
    pub const xz: []const u8 = ".xz";
    /// Tar Gzip compressed file extension.
    pub const tar_gz: []const u8 = ".tar.gz";
    /// Zip compressed file extension.
    pub const zip: []const u8 = ".zip";
    /// LZ4 compressed file extension.
    pub const lz4: []const u8 = ".lz4";

    /// All compression extensions for iteration.
    pub const all: [10][]const u8 = .{ gz, lgz, zst, deflate, lzma, lzma2, xz, tar_gz, zip, lz4 };

    /// Check if a filename ends with any known compression extension.
    pub fn isCompressed(name: []const u8) bool {
        return std.mem.endsWith(u8, name, gz) or
            std.mem.endsWith(u8, name, lgz) or
            std.mem.endsWith(u8, name, zst) or
            std.mem.endsWith(u8, name, deflate) or
            std.mem.endsWith(u8, name, lzma) or
            std.mem.endsWith(u8, name, lzma2) or
            std.mem.endsWith(u8, name, xz) or
            std.mem.endsWith(u8, name, tar_gz) or
            std.mem.endsWith(u8, name, zip) or
            std.mem.endsWith(u8, name, lz4);
    }

    /// Check if a filename ends with a specific compression extension.
    pub fn hasExtension(name: []const u8, ext: []const u8) bool {
        return std.mem.endsWith(u8, name, ext);
    }
};

/// Default time intervals and timeouts.
///
/// Usage:
///   Use these constants for consistent timing across async operations.
///
/// Complexity: O(1)
pub const TimeDefaults = struct {
    /// Default flush interval in milliseconds.
    pub const flush_interval_ms: u64 = 1000;
    /// Default async write timeout in milliseconds.
    pub const write_timeout_ms: u64 = 5000;
    /// Default connection timeout in milliseconds.
    pub const connection_timeout_ms: u64 = 10000;
    /// Default retry delay in milliseconds.
    pub const retry_delay_ms: u64 = 100;
    /// Maximum retry attempts for network operations.
    pub const max_retries: u32 = 3;
};

/// Async configuration constants.
///
/// Usage:
///   Constants specific to async logging behavior.
///
/// Complexity: O(1)
pub const AsyncConstants = struct {
    /// Sleep duration when blocking on full queue.
    pub const block_sleep_ns: u64 = 1 * TimeConstants.ns_per_ms;
    /// Default batch size for async processing.
    pub const batch_size: usize = BufferSizes.async_batch;
    /// Queue utilization ratio that counts as backpressure.
    pub const backpressure_threshold_ratio: f64 = 0.9;
    /// Default time to wait for an async queue to drain during explicit waits.
    pub const drain_timeout_ms: u64 = 5000;
};

/// Default limits for queues and buffers.
///
/// Usage:
///   Use these constants for queue sizing and overflow handling.
///
/// Complexity: O(1)
pub const Limits = struct {
    /// Maximum async queue size.
    pub const max_async_queue_size: usize = 10000;
    /// Maximum pending log records.
    pub const max_pending_records: usize = 50000;
    /// Maximum sinks per logger.
    pub const max_sinks: usize = 64;
    /// Maximum custom levels per logger.
    pub const max_custom_levels: usize = 32;
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
    /// Low-latency preset thread count.
    pub const low_latency_thread_count: usize = 2;
    /// Default queue size per thread.
    pub const queue_size: usize = 1024;
    /// Default stack size for worker threads.
    pub const stack_size: usize = 1024 * 1024; // 1MB
    /// High-throughput preset stack size.
    pub const high_throughput_stack_size: usize = stack_size * 2;
    /// I/O-bound preset queue size.
    pub const io_bound_queue_size: usize = queue_size * 2;
    /// Low-resource preset stack size.
    pub const low_resource_stack_size: usize = stack_size / 2;
    /// Default wait timeout in nanoseconds.
    pub const wait_timeout_ns: u64 = 100 * TimeConstants.ns_per_ms;
    /// Maximum concurrent tasks.
    pub const max_tasks: usize = 10000;
    /// Queue size for low resource environments.
    pub const queue_size_low: usize = 128;
    /// Default thread name prefix.
    pub const thread_name_prefix: []const u8 = "logly-worker";

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

/// OpenTelemetry configuration defaults.
pub const TelemetryDefaults = struct {
    /// Default batch span export size.
    pub const batch_size: usize = 256;
    /// Default batch export timeout in milliseconds.
    pub const batch_timeout_ms: u64 = 5000;
    /// Default initial capacity for formatting baggage header values.
    pub const header_initial_capacity: usize = 256;
    /// Default sampling rate (1.0 = 100%).
    pub const sampling_rate: f64 = 1.0;
    /// Default W3C traceparent header name.
    pub const trace_header: []const u8 = "traceparent";
    /// Default baggage/correlation context header name.
    pub const baggage_header: []const u8 = "baggage";
    /// Default prefix for exported metric names.
    pub const metric_prefix: []const u8 = "";
    /// Default separator inserted between a metric prefix and metric name.
    pub const metric_prefix_separator: []const u8 = "_";
    /// Whether metric names should be sanitized for exporter compatibility.
    pub const sanitize_metric_names: bool = true;

    /// Zipkin default batch size.
    pub const zipkin_batch_size: usize = 512;
    /// OpenTelemetry Collector default batch size.
    pub const collector_batch_size: usize = 512;
    /// High-throughput batch size for telemetry exports.
    pub const high_throughput_batch_size: usize = 1024;
    /// High-throughput batch timeout in milliseconds.
    pub const high_throughput_batch_timeout_ms: u64 = 2000;
    /// High-throughput sampling rate (1%).
    pub const high_throughput_sampling_rate: f64 = 0.01;
    /// Google Analytics 4 batch limit per request.
    pub const google_analytics_batch_limit: usize = 25;
};

/// Async preset tuning defaults.
///
/// Usage:
///   Shared values used by async-related configuration presets.
///
/// Complexity: O(1)
pub const AsyncPresetDefaults = struct {
    /// High-throughput preset values.
    pub const high_throughput_buffer_size: usize = 64 * 1024;
    pub const high_throughput_flush_interval_ms: u64 = 500;
    pub const high_throughput_min_flush_interval_ms: u64 = 50;
    pub const high_throughput_max_latency_ms: u64 = 1000;
    pub const high_throughput_batch_size: usize = TelemetryDefaults.batch_size;

    /// Low-latency preset values.
    pub const low_latency_buffer_size: usize = 1024;
    pub const low_latency_flush_interval_ms: u64 = 10;
    pub const low_latency_min_flush_interval_ms: u64 = 1;
    pub const low_latency_max_latency_ms: u64 = 50;
    pub const low_latency_batch_size: usize = 16;

    /// Balanced / no-drop preset values.
    pub const balanced_flush_interval_ms: u64 = 100;
    pub const balanced_min_flush_interval_ms: u64 = 10;
    pub const balanced_max_latency_ms: u64 = 500;
    /// No-drop preset buffer size.
    pub const no_drop_buffer_size: usize = BufferSizes.async_queue * 2;
};

/// Logger config preset tuning defaults.
///
/// Usage:
///   Shared values used by top-level `Config` presets.
///
/// Complexity: O(1)
pub const ConfigPresetDefaults = struct {
    /// High-throughput preset values.
    pub const high_throughput_sampling_target_rate: u32 = 1000;
    pub const high_throughput_rate_limit_per_second: u32 = 10000;
    pub const high_throughput_buffer_size: usize = AsyncPresetDefaults.high_throughput_buffer_size;
    pub const high_throughput_buffer_flush_interval_ms: u64 = AsyncPresetDefaults.high_throughput_flush_interval_ms;
    pub const high_throughput_max_pending: usize = Limits.max_pending_records * 2;
    pub const high_throughput_thread_pool_queue_size: usize = Limits.max_pending_records;
    pub const high_throughput_async_buffer_size: usize = BufferSizes.compression;
    pub const high_throughput_async_batch_size: usize = AsyncPresetDefaults.high_throughput_batch_size;
    pub const high_throughput_async_flush_interval_ms: u64 = AsyncPresetDefaults.high_throughput_min_flush_interval_ms;
};

test "telemetry defaults exist" {
    // Ensure central telemetry defaults are present and correct
    try std.testing.expectEqual(@as(usize, TelemetryDefaults.batch_size), @as(usize, 256));
    try std.testing.expectEqual(@as(u64, TelemetryDefaults.batch_timeout_ms), @as(u64, 5000));
    try std.testing.expectEqual(@as(usize, TelemetryDefaults.header_initial_capacity), @as(usize, 256));
    try std.testing.expectEqualStrings(TelemetryDefaults.trace_header, "traceparent");
    try std.testing.expectEqualStrings(TelemetryDefaults.baggage_header, "baggage");
    try std.testing.expectEqualStrings(TelemetryDefaults.metric_prefix, "");
    try std.testing.expectEqualStrings(TelemetryDefaults.metric_prefix_separator, "_");
    try std.testing.expect(TelemetryDefaults.sanitize_metric_names);
}

test "shared metrics and async defaults exist" {
    try std.testing.expectEqualStrings("logly", MetricsConstants.default_prefix);
    try std.testing.expectEqualStrings("_", MetricsConstants.prometheus_separator);
    try std.testing.expectEqualStrings(".", MetricsConstants.statsd_separator);
    try std.testing.expect(MetricsConstants.sanitize_names);
    try std.testing.expect(MetricsConstants.include_level_breakdown);
    try std.testing.expect(MetricsConstants.include_sink_breakdown);
    try std.testing.expect(AsyncConstants.backpressure_threshold_ratio > 0.0);
    try std.testing.expect(AsyncConstants.drain_timeout_ms > 0);
}

/// Log level count and priorities.
///
/// Usage:
///   Reference constants for defining new log levels or validating priority ranges.
///
/// Complexity: O(1)
pub const LevelConstants = struct {
    /// Total number of built-in log levels.
    pub const count: usize = 10;
    /// Minimum priority value (TRACE).
    pub const min_priority: u8 = 5;
    /// Maximum priority value (FATAL).
    pub const max_priority: u8 = 55;
    /// Default level priority (INFO).
    pub const default_priority: u8 = 20;

    /// Specific level priorities.
    pub const Priorities = struct {
        pub const trace: u8 = 5;
        pub const debug: u8 = 10;
        pub const info: u8 = 20;
        pub const notice: u8 = 22;
        pub const success: u8 = 25;
        pub const warning: u8 = 30;
        pub const err: u8 = 40;
        pub const fail: u8 = 45;
        pub const critical: u8 = 50;
        pub const fatal: u8 = 55;
    };

    /// Level index mapping for metrics array.
    /// Used by metrics and other modules to map log levels to array indices.
    pub const LevelIndex = enum(u4) {
        trace = 0,
        debug = 1,
        info = 2,
        notice = 3,
        success = 4,
        warning = 5,
        err = 6,
        fail = 7,
        critical = 8,
        fatal = 9,
    };
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

    /// Seconds-based helpers for interval reuse (avoid repeating literal values).
    pub const seconds_per_minute: u64 = 60;
    pub const seconds_per_hour: u64 = seconds_per_minute * 60;
    pub const seconds_per_day: u64 = seconds_per_hour * 24;
    pub const seconds_per_week: u64 = seconds_per_day * 7;
    pub const seconds_per_month: u64 = seconds_per_day * 30; // 30-day month approximation
    pub const seconds_per_year: u64 = seconds_per_day * 365;

    /// Minute-based helpers for timestamp and offset calculations.
    pub const minutes_per_hour: u16 = @intCast(seconds_per_hour / seconds_per_minute);
    pub const minutes_per_day: u16 = @intCast(seconds_per_day / seconds_per_minute);

    /// Supported UTC offset bounds in minutes (derived from 24h clock constraints).
    pub const max_utc_offset_minutes: i16 = @as(i16, @intCast(minutes_per_day - 1));
    pub const min_utc_offset_minutes: i16 = -max_utc_offset_minutes;

    /// Default human-readable timestamp pattern.
    pub const default_time_pattern: []const u8 = "YYYY-MM-DD HH:mm:ss.SSS";

    /// Derived conversions for convenient, consistent unit conversions.
    /// - `us_per_ms`: microseconds per millisecond (1_000)
    /// - `ns_per_ms`: nanoseconds per millisecond (1_000_000)
    /// - `ns_per_us`: nanoseconds per microsecond (1_000)
    pub const us_per_ms: u64 = us_per_second / ms_per_second;
    pub const ns_per_ms: u64 = ns_per_second / ms_per_second;
    pub const ns_per_us: u64 = ns_per_second / us_per_second;

    /// Default flush interval in milliseconds (derived from TimeDefaults).
    pub const default_flush_interval_ms: u64 = TimeDefaults.flush_interval_ms;
    /// Default rotation check interval in milliseconds (derived from seconds_per_minute).
    pub const rotation_check_interval_ms: u64 = seconds_per_minute * ms_per_second; // 1 minute
};

/// Metrics-related constants.
pub const MetricsConstants = struct {
    /// Default exported metric namespace.
    pub const default_prefix: []const u8 = "logly";
    /// Separator used by Prometheus-compatible metric names.
    pub const prometheus_separator: []const u8 = "_";
    /// Separator used by StatsD metric names.
    pub const statsd_separator: []const u8 = ".";
    /// Sanitize metric names by default for exporter compatibility.
    pub const sanitize_names: bool = true;
    /// Include per-level counters in metrics exports by default.
    pub const include_level_breakdown: bool = true;
    /// Include per-sink counters in metrics exports by default.
    pub const include_sink_breakdown: bool = true;

    /// Default histogram bucket boundaries in nanoseconds.
    pub const histogram_boundaries = [_]u64{
        1_000,         2_000,                5_000,     10_000,     20_000,     50_000,     100_000,     200_000,     500_000,
        1_000_000,     2_000_000,            5_000_000, 10_000_000, 20_000_000, 50_000_000, 100_000_000, 200_000_000, 500_000_000,
        1_000_000_000, std.math.maxInt(u64),
    };

    /// Uppercase log level names for metrics display.
    pub const level_names = [_][]const u8{
        "TRACE", "DEBUG", "INFO", "NOTICE", "SUCCESS", "WARNING", "ERROR", "FAIL", "CRITICAL", "FATAL",
    };
};

/// Message category constants for diagnostic rules.
///
/// Usage:
///   Use these constants for consistent message category display names
///   and prefixes in the diagnostic rules system.
///
/// Complexity: O(1)
pub const MessageCategoryConstants = struct {
    /// Display names for message categories.
    pub const DisplayNames = struct {
        pub const error_analysis: []const u8 = "Error Analysis";
        pub const solution_suggestion: []const u8 = "Solution";
        pub const best_practice: []const u8 = "Best Practice";
        pub const action_required: []const u8 = "Action Required";
        pub const documentation_link: []const u8 = "Documentation";
        pub const bug_report: []const u8 = "Report Issue";
        pub const general_information: []const u8 = "Information";
        pub const warning_explanation: []const u8 = "Warning Details";
        pub const performance_tip: []const u8 = "Performance";
        pub const security_notice: []const u8 = "Security";
        pub const custom: []const u8 = "Note";
    };

    /// Unicode prefixes for message categories.
    pub const Prefixes = struct {
        pub const error_analysis: []const u8 = "    » 🔍 [cause]";
        pub const solution_suggestion: []const u8 = "    » 💡 [fix]";
        pub const best_practice: []const u8 = "    » ✨ [suggest]";
        pub const action_required: []const u8 = "    » ⚡ [action]";
        pub const documentation_link: []const u8 = "    » 📚 [docs]";
        pub const bug_report: []const u8 = "    » 🐛 [report]";
        pub const general_information: []const u8 = "    » 📝 [note]";
        pub const warning_explanation: []const u8 = "    » ⚠️  [caution]";
        pub const performance_tip: []const u8 = "    » 🚀 [perf]";
        pub const security_notice: []const u8 = "    » 🔒 [security]";
        pub const custom: []const u8 = "    » 🔹 [custom]";
    };

    /// ASCII-only prefixes for non-UTF8 terminals.
    pub const PrefixesAscii = struct {
        pub const error_analysis: []const u8 = "    >> [cause]";
        pub const solution_suggestion: []const u8 = "    >> [fix]";
        pub const best_practice: []const u8 = "    >> [suggest]";
        pub const action_required: []const u8 = "    >> [action]";
        pub const documentation_link: []const u8 = "    >> [docs]";
        pub const bug_report: []const u8 = "    >> [report]";
        pub const general_information: []const u8 = "    >> [note]";
        pub const warning_explanation: []const u8 = "    >> [caution]";
        pub const performance_tip: []const u8 = "    >> [perf]";
        pub const security_notice: []const u8 = "    >> [security]";
        pub const custom: []const u8 = "    >> [custom]";
    };

    /// Short symbols for rule configuration.
    pub const RuleSymbols = struct {
        pub const error_analysis: []const u8 = ">> [ERROR]";
        pub const solution_suggestion: []const u8 = ">> [FIX]";
        pub const performance_hint: []const u8 = ">> [PERF]";
        pub const security_alert: []const u8 = ">> [SEC]";
        pub const deprecation_warning: []const u8 = ">> [DEP]";
        pub const best_practice: []const u8 = ">> [HINT]";
        pub const accessibility: []const u8 = ">> [A11Y]";
        pub const documentation: []const u8 = ">> [DOC]";
        pub const action_required: []const u8 = ">> [ACTION]";
        pub const bug_report: []const u8 = ">> [BUG]";
        pub const general_information: []const u8 = ">> [INFO]";
        pub const warning_explanation: []const u8 = ">> [WARN]";
        pub const default: []const u8 = ">>";
    };
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
    ///
    /// Returns a stable slice backed by a small ring of static buffers to avoid
    /// heap allocations and to be safe to return from the function.
    pub fn fg256(color_index: u8) []const u8 {
        const raw_idx = colorBufIndex.fetchAdd(1, .monotonic);
        const idx = @as(usize, raw_idx) % colorBufs.len;
        const out = std.fmt.bufPrint(&colorBufs[idx], "38;5;{d}", .{color_index}) catch return "38;5;0";
        return out;
    }

    /// Generate 256-color background code (0-255).
    ///
    /// Returns a stable slice backed by the shared buffer pool.
    pub fn bg256(color_index: u8) []const u8 {
        const raw_idx = colorBufIndex.fetchAdd(1, .monotonic);
        const idx = @as(usize, raw_idx) % colorBufs.len;
        const out = std.fmt.bufPrint(&colorBufs[idx], "48;5;{d}", .{color_index}) catch return "48;5;0";
        return out;
    }

    /// Generate RGB foreground color code.
    ///
    /// Uses the shared buffer pool and returns a stable slice.
    pub fn fgRgb(r: u8, g: u8, b: u8) []const u8 {
        const raw_idx = colorBufIndex.fetchAdd(1, .monotonic);
        const idx = @as(usize, raw_idx) % colorBufs.len;
        const out = std.fmt.bufPrint(&colorBufs[idx], "38;2;{d};{d};{d}", .{ r, g, b }) catch return "38;2;0;0;0";
        return out;
    }

    /// Generate RGB background color code.
    ///
    /// Uses the shared buffer pool and returns a stable slice.
    pub fn bgRgb(r: u8, g: u8, b: u8) []const u8 {
        const raw_idx = colorBufIndex.fetchAdd(1, .monotonic);
        const idx = @as(usize, raw_idx) % colorBufs.len;
        const out = std.fmt.bufPrint(&colorBufs[idx], "48;2;{d};{d};{d}", .{ r, g, b }) catch return "48;2;0;0;0";
        return out;
    }

    /// Combine multiple codes (e.g., "1;31" for bold red).
    ///
    /// Accepts a comptime iterable (anytype), allowing array literals to be
    /// passed directly without special length annotations.
    pub fn combine(comptime codes: anytype) []const u8 {
        comptime {
            var result: []const u8 = "";
            var idx: usize = 0;
            for (codes) |code| {
                if (idx > 0) result = result ++ ";";
                result = result ++ code;
                idx += 1;
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
        /// Default theme with standard colors. Aliased to `LevelColors` to avoid duplication.
        pub const default_theme = LevelColors;

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

        /// Dim theme with subtle colors (composed from base colors + dim style).
        pub const dim = struct {
            pub const trace: []const u8 = combine(.{ LevelColors.trace, Style.dim });
            pub const debug: []const u8 = combine(.{ LevelColors.debug, Style.dim });
            pub const info: []const u8 = combine(.{ LevelColors.info, Style.dim });
            pub const notice: []const u8 = combine(.{ LevelColors.notice, Style.dim });
            pub const success: []const u8 = combine(.{ LevelColors.success, Style.dim });
            pub const warning: []const u8 = combine(.{ LevelColors.warning, Style.dim });
            pub const err: []const u8 = combine(.{ LevelColors.err, Style.dim });
            pub const fail: []const u8 = combine(.{ LevelColors.fail, Style.dim });
            pub const critical: []const u8 = combine(.{ LevelColors.critical, Style.dim });
            pub const fatal: []const u8 = combine(.{ LevelColors.fatal, Style.dim });
        };

        /// Underlined theme for highlighted levels (composed from base colors + underline style).
        pub const underlined = struct {
            pub const trace: []const u8 = combine(.{ LevelColors.trace, Style.underline });
            pub const debug: []const u8 = combine(.{ LevelColors.debug, Style.underline });
            pub const info: []const u8 = combine(.{ LevelColors.info, Style.underline });
            pub const notice: []const u8 = combine(.{ LevelColors.notice, Style.underline });
            pub const success: []const u8 = combine(.{ LevelColors.success, Style.underline });
            pub const warning: []const u8 = combine(.{ LevelColors.warning, Style.underline });
            pub const err: []const u8 = combine(.{ LevelColors.err, Style.underline });
            pub const fail: []const u8 = combine(.{ LevelColors.fail, Style.underline });
            pub const critical: []const u8 = combine(.{ LevelColors.critical, Style.underline });
            pub const fatal: []const u8 = combine(.{ LevelColors.fatal, Style.underline });
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

/// Syslog constants for RFC 5424 compliance.
///
/// Usage:
///   Standard syslog severity levels and facility codes for network logging.
///
/// Complexity: O(1)
pub const SyslogConstants = struct {
    /// Syslog severity levels (RFC 5424)
    pub const Severity = enum(u3) {
        emergency = 0,
        alert = 1,
        critical = 2,
        err = 3,
        warning = 4,
        notice = 5,
        info = 6,
        debug = 7,

        /// Convert from log level to syslog severity
        pub fn fromLogLevel(level: @import("level.zig").Level) Severity {
            return switch (level) {
                .trace, .debug => .debug,
                .info => .info,
                .notice => .notice,
                .success => .info,
                .warning => .warning,
                .err => .err,
                .fail => .err,
                .critical => .critical,
                .fatal => .emergency,
            };
        }

        /// Alias for fromLogLevel
        pub const fromLevel = fromLogLevel;
        pub const convertFromLevel = fromLogLevel;
    };

    /// Syslog facilities (RFC 5424)
    pub const Facility = enum(u5) {
        kern = 0,
        user = 1,
        mail = 2,
        daemon = 3,
        auth = 4,
        syslog = 5,
        lpr = 6,
        news = 7,
        uucp = 8,
        cron = 9,
        authpriv = 10,
        ftp = 11,
        local0 = 16,
        local1 = 17,
        local2 = 18,
        local3 = 19,
        local4 = 20,
        local5 = 21,
        local6 = 22,
        local7 = 23,
    };

    /// Default syslog UDP port.
    pub const default_port: u16 = 514;
};

/// Compression algorithm constants.
///
/// Usage:
///   Constants for DEFLATE/LZ77 window sizes and limits.
///
/// Complexity: O(1)
pub const CompressionConstants = struct {
    /// Window size for fast compression (256).
    pub const window_fast: usize = 256;
    /// Window size for default compression (1024).
    pub const window_default: usize = 1024;
    /// Window size for best compression (4096).
    pub const window_best: usize = 4096;
    /// Minimum match length (3).
    pub const min_match: usize = 3;
    /// Maximum match length (255).
    pub const max_match: usize = 255;
    /// Maximum run length for RLE (127).
    pub const max_run_length: usize = 127;
    /// LZMA dictionary size (64KB).
    pub const lzma_dict_size: u32 = 65536;
    /// LZMA maximum offset (64KB - 1).
    pub const lzma_max_offset: usize = 65535;
    /// LZMA hash bits (14).
    pub const lzma_hash_bits: u5 = 14;
    /// LZMA maximum match length (272).
    pub const lzma_max_match: usize = 272;
    /// LZMA2 chunk size (32KB).
    pub const lzma2_chunk_size: usize = 32768;

    /// LZ4 minimum match length.
    pub const lz4_min_match: usize = 4;
    /// LZ4 maximum back-reference offset (16-bit).
    pub const lz4_max_offset: usize = 65535;
    /// LZ4 hash table bit width.
    pub const lz4_hash_bits: u5 = 16;
    /// Maximum chain depth for LZMA match search.
    pub const lzma_max_chain_search: usize = 32;

    /// Magic bytes for various formats
    pub const Magic = struct {
        pub const lzma = "\x5D\x00\x00\x80\x00"; // Typical start, but varied
        pub const xz = "\xFD\x37\x7A\x58\x5A\x00";
        pub const gzip = "\x1F\x8B";
        pub const zlib = "\x78\x9C"; // Default
        pub const logly = "LGZ";
    };

    /// LZMA properties: lc=3, lp=0, pb=2 (standard)
    pub const lzma_properties_byte: u8 = (2 * 5 + 0) * 9 + 3;

    /// RLE Markers
    pub const Rle = struct {
        pub const marker: u8 = 0xFE;
        pub const escape: u8 = 0xFD;
    };

    /// File extensions for different compression algorithms.
    pub const ArchivingExtensions = struct {
        pub const gzip = CompressionExtensions.gz;
        pub const zstd = CompressionExtensions.zst;
        pub const lzma = CompressionExtensions.lzma;
        pub const lzma2 = CompressionExtensions.lzma2;
        pub const xz = CompressionExtensions.xz;
        pub const tar_gz = CompressionExtensions.tar_gz;
        pub const zip = CompressionExtensions.zip;
        pub const lz4 = CompressionExtensions.lz4;
        pub const none = "";
    };
};

/// Windows Event Log constants (Word values for ReportEvent)
pub const EventLogConstants = struct {
    pub const success: u16 = 0x0000;
    pub const error_type: u16 = 0x0001;
    pub const warning_type: u16 = 0x0002;
    pub const information_type: u16 = 0x0004;
};

test "event log constants exist" {
    try std.testing.expectEqual(@as(u16, EventLogConstants.success), @as(u16, 0x0000));
    try std.testing.expectEqual(@as(u16, EventLogConstants.error_type), @as(u16, 0x0001));
    try std.testing.expectEqual(@as(u16, EventLogConstants.warning_type), @as(u16, 0x0002));
    try std.testing.expectEqual(@as(u16, EventLogConstants.information_type), @as(u16, 0x0004));
}

/// Scheduler defaults.
///
/// Usage:
///   Default values for task scheduling and maintenance.
///
/// Complexity: O(1)
pub const SchedulerDefaults = struct {
    /// Default retry interval in milliseconds (5s).
    pub const retry_interval_ms: u32 = 5000;
    /// Default cleanup max age in seconds (7 days).
    pub const max_age_seconds: u64 = 7 * TimeConstants.seconds_per_day;
    /// Cron fallback interval in milliseconds (1 min).
    pub const cron_fallback_interval_ms: i64 = @as(i64, TimeConstants.seconds_per_minute * TimeConstants.ms_per_second);
};

/// Rotation default settings.
///
/// Usage:
///   Default values for log rotation.
///
/// Complexity: O(1)
pub const RotationDefaults = struct {
    /// Default retention count (10).
    pub const retention_count: usize = 10;
};

/// General configuration defaults.
///
/// Usage:
///   Default values for general logger configuration.
///
/// Complexity: O(1)
pub const ConfigDefaults = struct {
    /// Default stack size for stack trace capturing (1MB).
    pub const stack_size: usize = 1024 * 1024;
    /// Default arena reset threshold (64KB).
    pub const arena_reset_threshold: usize = 64 * 1024;
    /// Default distributed trace header name.
    pub const distributed_trace_header: []const u8 = "X-Trace-ID";
    /// Default distributed span header name.
    pub const distributed_span_header: []const u8 = "X-Span-ID";
    /// Default distributed parent span header name.
    pub const distributed_parent_header: []const u8 = "X-Parent-ID";
    /// Default distributed baggage header name.
    pub const distributed_baggage_header: []const u8 = "Correlation-Context";
};

/// Redaction defaults.
///
/// Usage:
///   Default values for redaction configuration.
///
/// Complexity: O(1)
pub const RedactionDefaults = struct {
    /// Default characters to reveal at start.
    pub const partial_start_chars: u8 = 4;
    /// Default characters to reveal at end.
    pub const partial_end_chars: u8 = 4;
    /// Default mask character.
    pub const mask_char: u8 = '*';
    /// Default max length for truncate redaction.
    pub const truncate_length: u8 = 8;
    /// Default suffix for truncate redaction.
    pub const truncate_suffix: []const u8 = "...";
    /// Default replacement text for full redaction.
    pub const replacement: []const u8 = "[REDACTED]";
};

/// Rate limiting defaults.
///
/// Usage:
///   Default values for rate limiting configuration.
///
/// Complexity: O(1)
pub const RateLimitDefaults = struct {
    /// Default max requests per second.
    pub const max_per_second: u32 = 1000;
    /// Default burst size.
    pub const burst_size: u32 = 100;
};

/// Sampling defaults.
///
/// Usage:
///   Default values for sampling configuration.
///
/// Complexity: O(1)
pub const SamplingDefaults = struct {
    /// Default rate limit window in milliseconds.
    pub const rate_limit_window_ms: u64 = 1000;
    /// Default adaptive adjustment interval in milliseconds.
    pub const adaptive_adjustment_interval_ms: u64 = 1000;
    /// Default minimum adaptive sample rate.
    pub const adaptive_min_rate: f64 = 0.01;
    /// Default maximum adaptive sample rate.
    pub const adaptive_max_rate: f64 = 1.0;
};

/// Parallel sink writing defaults.
///
/// Usage:
///   Default values for parallel sink configuration.
///
/// Complexity: O(1)
pub const ParallelDefaults = struct {
    /// Default maximum concurrent writes.
    pub const max_concurrent: usize = 8;
    /// High throughput maximum concurrent writes.
    pub const high_throughput_max_concurrent: usize = 16;
    /// Default buffer size.
    pub const buffer_size: usize = 64;
    /// High throughput buffer size.
    pub const high_throughput_buffer_size: usize = 128;
    /// Default maximum retries.
    pub const max_retries: u3 = 3;
    /// Default write timeout in milliseconds.
    pub const write_timeout_ms: u64 = 5000;

    /// Low latency configuration presets.
    pub const low_latency_max_concurrent: usize = 4;
    pub const low_latency_timeout_ms: u64 = 500;

    /// Reliable configuration presets.
    pub const reliable_max_concurrent: usize = 8;
    pub const reliable_timeout_ms: u64 = 2000;
    pub const reliable_max_retries: u3 = 5;
};

test "atomic types exist" {
    // Verify atomic types are defined for cross-platform compatibility
    try std.testing.expect(@sizeOf(AtomicUnsigned) > 0);
    try std.testing.expect(@sizeOf(AtomicSigned) > 0);
    try std.testing.expect(@sizeOf(NativeUint) > 0);
    try std.testing.expect(@sizeOf(NativeInt) > 0);
}

test "atomic and native types match pointer width" {
    const ptr_bits = @bitSizeOf(usize);
    try std.testing.expectEqual(ptr_bits, @bitSizeOf(AtomicUnsigned));
    try std.testing.expectEqual(ptr_bits, @bitSizeOf(AtomicSigned));
    try std.testing.expectEqual(ptr_bits, @bitSizeOf(NativeUint));
    try std.testing.expectEqual(ptr_bits, @bitSizeOf(NativeInt));
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

    try std.testing.expectEqual(@as(u64, 60), TimeConstants.seconds_per_minute);
    try std.testing.expectEqual(@as(u64, 3600), TimeConstants.seconds_per_hour);
    try std.testing.expectEqual(@as(u64, 86400), TimeConstants.seconds_per_day);
    try std.testing.expectEqual(@as(u64, 604800), TimeConstants.seconds_per_week);
    try std.testing.expectEqual(@as(u64, 2592000), TimeConstants.seconds_per_month);
    try std.testing.expectEqual(@as(u64, 31536000), TimeConstants.seconds_per_year);

    try std.testing.expectEqual(@as(u16, 60), TimeConstants.minutes_per_hour);
    try std.testing.expectEqual(@as(u16, 1440), TimeConstants.minutes_per_day);
    try std.testing.expectEqual(@as(i16, 1439), TimeConstants.max_utc_offset_minutes);
    try std.testing.expectEqual(@as(i16, -1439), TimeConstants.min_utc_offset_minutes);
    try std.testing.expectEqualStrings("YYYY-MM-DD HH:mm:ss.SSS", TimeConstants.default_time_pattern);

    // Rotation check interval must be consistent with seconds_per_minute and ms_per_second
    try std.testing.expectEqual(TimeConstants.seconds_per_minute * TimeConstants.ms_per_second, TimeConstants.rotation_check_interval_ms);
    try std.testing.expectEqual(@as(u64, 60_000), TimeConstants.rotation_check_interval_ms);
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

test "syslog constants exist" {
    // Test severity enum values
    try std.testing.expectEqual(@as(u3, 0), @intFromEnum(SyslogConstants.Severity.emergency));
    try std.testing.expectEqual(@as(u3, 6), @intFromEnum(SyslogConstants.Severity.info));
    try std.testing.expectEqual(@as(u3, 7), @intFromEnum(SyslogConstants.Severity.debug));

    // Test facility enum values
    try std.testing.expectEqual(@as(u5, 0), @intFromEnum(SyslogConstants.Facility.kern));
    try std.testing.expectEqual(@as(u5, 1), @intFromEnum(SyslogConstants.Facility.user));
    try std.testing.expectEqual(@as(u5, 16), @intFromEnum(SyslogConstants.Facility.local0));

    // Test severity conversion
    try std.testing.expectEqual(SyslogConstants.Severity.debug, SyslogConstants.Severity.fromLogLevel(.debug));
    try std.testing.expectEqual(SyslogConstants.Severity.info, SyslogConstants.Severity.fromLogLevel(.info));
    try std.testing.expectEqual(SyslogConstants.Severity.err, SyslogConstants.Severity.fromLogLevel(.err));
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

test "async batch reuses buffer sizes" {
    try std.testing.expectEqual(BufferSizes.async_batch, AsyncConstants.batch_size);
}

test "time default flush is consistent" {
    try std.testing.expectEqual(TimeDefaults.flush_interval_ms, TimeConstants.default_flush_interval_ms);
}

test "compression gzip extension reused" {
    try std.testing.expectEqualStrings(CompressionConstants.ArchivingExtensions.gzip, RotationConstants.compressed_ext);
}

test "preset defaults are reasonable" {
    try std.testing.expect(AsyncPresetDefaults.high_throughput_buffer_size > 0);
    try std.testing.expect(AsyncPresetDefaults.low_latency_buffer_size > 0);
    try std.testing.expect(AsyncPresetDefaults.high_throughput_batch_size > 0);
    try std.testing.expect(ConfigPresetDefaults.high_throughput_buffer_size > 0);
    try std.testing.expect(ConfigPresetDefaults.high_throughput_thread_pool_queue_size > 0);
    try std.testing.expect(ConfigPresetDefaults.high_throughput_max_pending > ConfigPresetDefaults.high_throughput_thread_pool_queue_size);
}

/// System diagnostics constants.
///
/// Usage:
///   Max buffer sizes and resource limits for system diagnostics.
///
/// Complexity: O(1)
pub const DiagnosticsConstants = struct {
    /// Maximum mount point path length (macOS/BSD/Linux).
    pub const mac_mount_path_len: usize = 1024;
};

/// Update checker constants.
///
/// Usage:
///   Repository information for version checking.
///
/// Complexity: O(1)
pub const UpdateCheckerConstants = struct {
    /// GitHub repository owner.
    pub const repo_owner: []const u8 = "muhammad-fiaz";
    /// GitHub repository name.
    pub const repo_name: []const u8 = "logly.zig";
};

test "color helpers produce valid prefixes" {
    const s = Colors.fg256(208);
    try std.testing.expect(s.len >= 5);
    try std.testing.expectEqualStrings(s[0..5], "38;5;");

    const r = Colors.fgRgb(255, 127, 80);
    try std.testing.expect(r.len >= 4);
    try std.testing.expectEqualStrings(r[0..4], "38;2");
}

/// Filter system defaults.
pub const FilterDefaults = struct {
    /// Default maximum rules per filter instance.
    pub const max_rules: usize = 256;
    /// Default time-window start hour (0-23).
    pub const default_quiet_hour_start: u8 = 22;
    /// Default time-window end hour (0-23).
    pub const default_quiet_hour_end: u8 = 6;
    /// Default rate-based filter max messages per second per module.
    pub const default_rate_per_second: u32 = 1000;
    /// Default deny-list initial capacity.
    pub const deny_list_capacity: usize = 64;
    /// Token bucket refill interval for rate-based filters (ms).
    pub const token_bucket_interval_ms: u64 = 1000;
};

/// Formatter output format defaults.
pub const FormatterDefaults = struct {
    /// Default field separator for logfmt output.
    pub const logfmt_separator: []const u8 = " ";
    /// Default field assignment character for logfmt.
    pub const logfmt_assign: []const u8 = "=";
    /// Default level field width (padded to align output).
    pub const level_field_width: usize = 8;
    /// Default module field width.
    pub const module_field_width: usize = 20;
    /// Default padding character.
    pub const pad_char: u8 = ' ';
    /// NDJSON line terminator.
    pub const ndjson_terminator: u8 = '\n';
    /// CEF version string.
    pub const cef_version: []const u8 = "CEF:0";
    /// CEF default device vendor.
    pub const cef_vendor: []const u8 = "logly";
    /// CEF default device product.
    pub const cef_product: []const u8 = "logly.zig";
    /// CEF default device version (should match library version).
    pub const cef_device_version: []const u8 = "0.2.0";
    /// Template default format string.
    pub const default_template: []const u8 = "{time} [{level}] {message}";
    /// Maximum template field name length.
    pub const max_template_field_len: usize = 32;
};

/// Sink system defaults.
pub const SinkDefaults = struct {
    /// Default max buffer records.
    pub const max_buffer_records: usize = 1000;
    /// Default flush interval in milliseconds.
    pub const flush_interval_ms: u64 = 1000;
    /// Default memory sink ring-buffer capacity (records).
    pub const memory_ring_size: usize = 1024;
    /// Default per-sink rate limit (messages per second, 0 = unlimited).
    pub const rate_limit_per_second: u32 = 0;
    /// Number of consecutive errors before a sink is considered unhealthy.
    pub const unhealthy_error_threshold: u32 = 10;
    /// Default flush period for buffered sinks (ms).
    pub const flush_period_ms: u64 = TimeConstants.default_flush_interval_ms;
    /// Stderr sink name.
    pub const stderr_name: []const u8 = "stderr";
    /// Stdout sink name.
    pub const stdout_name: []const u8 = "stdout";
    /// Memory sink name.
    pub const memory_name: []const u8 = "memory";
};

/// Record field defaults.
pub const RecordDefaults = struct {
    /// Maximum number of context fields per record.
    pub const max_context_fields: usize = 64;
    /// Maximum stack trace depth.
    pub const max_stack_depth: usize = 32;
    /// Severity scale maximum.
    pub const severity_max: u8 = 100;
    /// Tag separator for multi-tag strings.
    pub const tag_separator: []const u8 = ",";
    /// Unknown module name placeholder.
    pub const unknown_module: []const u8 = "unknown";
    /// Error category names.
    pub const ErrorCategoryNames = struct {
        pub const io: []const u8 = "io";
        pub const network: []const u8 = "network";
        pub const logic: []const u8 = "logic";
        pub const oom: []const u8 = "oom";
        pub const unknown: []const u8 = "unknown";
    };
};

/// Async system defaults (extended from AsyncConstants).
pub const AsyncExtendedDefaults = struct {
    /// Backoff base sleep in nanoseconds.
    pub const backoff_base_ns: u64 = 100 * TimeConstants.ns_per_us;
    /// Backoff maximum sleep in nanoseconds.
    pub const backoff_max_ns: u64 = 10 * TimeConstants.ns_per_ms;
    /// Backoff multiplier.
    pub const backoff_multiplier: u64 = 2;
    /// Priority queue fast-path levels (critical and above bypass normal queue).
    pub const priority_bypass_threshold: u8 = 50; // maps to .critical priority
    /// Default shutdown grace period (ms).
    pub const shutdown_timeout_ms: u64 = 5000;
    /// Default batch flush callback label.
    pub const batch_flush_label: []const u8 = "batch_flush";
};

/// Redaction pattern defaults.
pub const RedactionPatterns = struct {
    /// Regex-like pattern for email addresses.
    pub const email: []const u8 = "[\\w.+-]+@[\\w-]+\\.[\\w.]+";
    /// Pattern prefix for JWT detection (base64url encoded JSON).
    pub const jwt_prefix: []const u8 = "ey";
    /// Minimum JWT token length (header.payload.sig).
    pub const jwt_min_length: usize = 20;
    /// IPv4 pattern approximation.
    pub const ipv4_segment: []const u8 = "\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}";
    /// Credit card minimum digit count.
    pub const cc_min_digits: usize = 13;
    /// Credit card maximum digit count.
    pub const cc_max_digits: usize = 19;
    /// Default redaction replacement for sensitive patterns.
    pub const sensitive_replacement: []const u8 = "[REDACTED]";
    /// Email redaction replacement.
    pub const email_replacement: []const u8 = "[EMAIL]";
    /// IP address redaction replacement.
    pub const ip_replacement: []const u8 = "[IP]";
    /// JWT redaction replacement.
    pub const jwt_replacement: []const u8 = "[JWT]";
    /// Credit card redaction replacement.
    pub const cc_replacement: []const u8 = "[CARD]";
};

/// Network sink defaults (extended).
pub const NetworkExtendedDefaults = struct {
    /// Auto-reconnect initial delay (ms).
    pub const reconnect_initial_delay_ms: u64 = 100;
    /// Auto-reconnect max delay (ms).
    pub const reconnect_max_delay_ms: u64 = 30_000;
    /// Auto-reconnect backoff multiplier.
    pub const reconnect_backoff_mult: u64 = 2;
    /// TCP keepalive idle time (seconds).
    pub const keepalive_idle_secs: u32 = 60;
    /// TCP keepalive probe interval (seconds).
    pub const keepalive_interval_secs: u32 = 10;
    /// TCP keepalive max probe count.
    pub const keepalive_max_probes: u32 = 6;
    /// Default chunk size for HTTP chunked streaming (bytes).
    pub const chunked_chunk_size: usize = 4096;
    /// Syslog RFC-5424 version number.
    pub const syslog_version: u8 = 1;
    /// Syslog default facility (16 = local0).
    pub const syslog_default_facility: u8 = 16;
    /// Syslog default app name.
    pub const syslog_app_name: []const u8 = "logly";
    /// Syslog nilvalue.
    pub const syslog_nilvalue: []const u8 = "-";
};

/// Scheduler system constants (extended).
pub const SchedulerExtendedDefaults = struct {
    /// Maximum jitter in milliseconds (added as random ±jitter to task intervals).
    pub const max_jitter_ms: u64 = 5000;
    /// Default jitter percentage of interval (0.0 = no jitter, 0.1 = ±10%).
    pub const default_jitter_fraction: f64 = 0.0;
    /// Cron-expression field count.
    pub const cron_field_count: usize = 5;
    /// Task history ring size (entries).
    pub const task_history_size: usize = 32;
    /// One-shot task min delay (ms).
    pub const one_shot_min_delay_ms: u64 = 1;
};

/// Diagnostic system constants.
pub const DiagnosticsDefaults = struct {
    /// Maximum health-check entries per report.
    pub const max_health_checks: usize = 64;
    /// JSON report buffer initial size.
    pub const json_report_buffer: usize = BufferSizes.format;
    /// Health check name max length.
    pub const health_check_name_len: usize = 64;
    /// Default report interval (ms).
    pub const report_interval_ms: u64 = 60_000;
    /// Queue depth warning threshold (0.0-1.0).
    pub const queue_depth_warn_threshold: f64 = 0.8;
    /// Memory warning threshold (bytes, 512MB default).
    pub const memory_warn_bytes: u64 = 512 * 1024 * 1024;
};

/// Telemetry extended constants.
pub const TelemetryExtendedDefaults = struct {
    /// OTLP Logs signal JSON content-type.
    pub const otlp_content_type: []const u8 = "application/json";
    /// Google Cloud Logging JSON severity field name.
    pub const gcp_severity_field: []const u8 = "severity";
    /// Google Cloud Logging timestamp field.
    pub const gcp_timestamp_field: []const u8 = "timestamp";
    /// Google Cloud Logging message field.
    pub const gcp_message_field: []const u8 = "message";
    /// Datadog log level field name.
    pub const datadog_level_field: []const u8 = "status";
    /// Datadog source field name.
    pub const datadog_source_field: []const u8 = "ddsource";
    /// Datadog service field name.
    pub const datadog_service_field: []const u8 = "service";
    /// Datadog tags field name.
    pub const datadog_tags_field: []const u8 = "ddtags";
    /// W3C Baggage header name.
    pub const w3c_baggage_header: []const u8 = "baggage";
    /// OTLP Logs resource attributes key.
    pub const otlp_resource_key: []const u8 = "resource";
    /// OTLP Logs attributes key.
    pub const otlp_attrs_key: []const u8 = "attributes";
};

/// Compression level constants.
pub const CompressionLevelDefaults = struct {
    /// Default gzip/deflate compression level (1-9).
    pub const gzip_default: u8 = 6;
    /// Fast gzip/deflate compression level.
    pub const gzip_fast: u8 = 1;
    /// Maximum gzip/deflate compression level.
    pub const gzip_max: u8 = 9;
    /// Default zstd compression level (1-22).
    pub const zstd_default: u8 = 3;
    /// Fast zstd compression level.
    pub const zstd_fast: u8 = 1;
    /// Maximum zstd compression level.
    pub const zstd_max: u8 = 22;
};

/// Default crash handler settings and strings.
pub const CrashConstants = struct {
    /// Prefix prepended to panics in the log.
    pub const panic_message_prefix: []const u8 = "CRITICAL PANIC OCCURRED: ";
    /// Stderr fallback message prefix.
    pub const panic_interceptor_prefix: []const u8 = "Logly Panic Interceptor: ";
    /// Prefix prepended to OS-level crashes in the log.
    pub const crash_message_prefix: []const u8 = "CRITICAL CRASH: ";
    /// Stderr fallback message prefix for OS-level crashes.
    pub const crash_interceptor_prefix: []const u8 = "Logly Crash Interceptor: ";

    /// Windows exception code mapping structure.
    pub const WindowsException = struct {
        code: u32,
        name: []const u8,
        is_fatal: bool,
    };

    /// List of Windows Vectored Exception codes, names, and whether they are fatal.
    pub const windows_exceptions = [_]WindowsException{
        .{ .code = 0xC0000005, .name = "STATUS_ACCESS_VIOLATION (Access Violation)", .is_fatal = true },
        .{ .code = 0xC0000094, .name = "STATUS_INTEGER_DIVIDE_BY_ZERO (Integer Division by Zero)", .is_fatal = true },
        .{ .code = 0xC000001D, .name = "STATUS_ILLEGAL_INSTRUCTION (Illegal Instruction)", .is_fatal = true },
        .{ .code = 0xC00000FD, .name = "STATUS_STACK_OVERFLOW (Stack Overflow)", .is_fatal = true },
        .{ .code = 0xC0000025, .name = "STATUS_NONCONTINUABLE_EXCEPTION (Noncontinuable Exception)", .is_fatal = true },
        .{ .code = 0xC0000008, .name = "STATUS_INVALID_HANDLE (Invalid Handle)", .is_fatal = true },
        .{ .code = 0x80000003, .name = "STATUS_BREAKPOINT (Breakpoint)", .is_fatal = false },
    };

    pub const unknown_windows_exception: []const u8 = "UNKNOWN_WINDOWS_EXCEPTION";
    pub const windows_fallback_msg: []const u8 = "CRITICAL CRASH: Windows native exception triggered\n";
    pub const windows_triggered_fmt: []const u8 = "Windows exception triggered: {s} (Code: 0x{X})\n";
    pub const windows_stderr_fmt: []const u8 = "Process triggered fatal exception 0x{X}\n";

    /// POSIX signal names mapping.
    pub const posix_sigsegv: []const u8 = "SIGSEGV (Segmentation Fault)";
    pub const posix_sigill: []const u8 = "SIGILL (Illegal Instruction)";
    pub const posix_sigfpe: []const u8 = "SIGFPE (Floating Point Exception)";
    pub const posix_sigabrt: []const u8 = "SIGABRT (Abort Signal)";
    pub const posix_sigbus: []const u8 = "SIGBUS (Bus Error)";
    pub const posix_unknown_signal: []const u8 = "Unknown Signal";

    pub const posix_fallback_msg: []const u8 = "CRITICAL CRASH: Process received standard POSIX signal\n";
    pub const posix_received_fmt: []const u8 = "Process received POSIX signal {s} ({d})\n";
    pub const posix_stderr_fmt: []const u8 = "Process received standard POSIX signal {d}\n";
};
