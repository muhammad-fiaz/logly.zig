//! Shared constants.
//!
//! Buffer sizes, timeouts, defaults, and protocol strings.
const std = @import("std");

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
pub const BufferSizes = struct {
    /// Default log message buffer size.
    pub const message: usize = 4096;
    /// Default format buffer size.
    pub const format: usize = 8192;
    /// Default sink buffer size.
    pub const sink: usize = 16384;
    /// Default async queue buffer size.
    pub const asyncQueue: usize = 8192;
    /// Default compression buffer size.
    pub const compression: usize = 32768;
    /// Default telemetry buffer size.
    pub const telemetry: usize = 4096;
    /// Maximum log message size.
    pub const maxMessage: usize = 1024 * 1024; // 1MB
    /// Async batch size.
    pub const asyncBatch: usize = 64;
    /// Small buffer for thread IDs etc.
    pub const tiny: usize = 32;
    /// Small buffer for context values etc.
    pub const small: usize = 256;
    /// Standard file read buffer.
    pub const fileRead: usize = 4096;
    /// Large file read buffer.
    pub const fileReadLarge: usize = 8192;
    /// Path buffer size.
    pub const pathBuffer: usize = 512;
};

/// Size unit constants for consistent byte/KB/MB/GB conversions.
///
/// Usage:
///   Use these constants for consistent size calculations and conversions.
pub const SizeConstants = struct {
    /// Bytes per kilobyte (1024).
    pub const bytesPerKb: u64 = 1024;
    /// Bytes per megabyte (1024 * 1024).
    pub const bytesPerMb: u64 = 1024 * 1024;
    /// Bytes per gigabyte (1024 * 1024 * 1024).
    pub const bytesPerGb: u64 = 1024 * 1024 * 1024;
    /// Bytes per terabyte (1024 * 1024 * 1024 * 1024).
    pub const bytesPerTb: u64 = 1024 * 1024 * 1024 * 1024;
};

/// Compression file extension constants.
///
/// Usage:
///   Use these constants to check if a file is already compressed,
///   or to determine the compression format of a file.
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
    pub const tarGz: []const u8 = ".tar.gz";
    /// Zip compressed file extension.
    pub const zip: []const u8 = ".zip";
    /// LZ4 compressed file extension.
    pub const lz4: []const u8 = ".lz4";
    /// Brotli compressed file extension.
    pub const brotli: []const u8 = ".br";

    /// All compression extensions for iteration.
    pub const all: [12][]const u8 = .{ gz, lgz, zst, deflate, lzma, lzma2, xz, tarGz, zip, lz4, brotli, "" };

    /// Check if a filename ends with any known compression extension.
    pub fn isCompressed(name: []const u8) bool {
        return std.mem.endsWith(u8, name, gz) or
            std.mem.endsWith(u8, name, lgz) or
            std.mem.endsWith(u8, name, zst) or
            std.mem.endsWith(u8, name, deflate) or
            std.mem.endsWith(u8, name, lzma) or
            std.mem.endsWith(u8, name, lzma2) or
            std.mem.endsWith(u8, name, xz) or
            std.mem.endsWith(u8, name, tarGz) or
            std.mem.endsWith(u8, name, zip) or
            std.mem.endsWith(u8, name, lz4) or
            std.mem.endsWith(u8, name, brotli);
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
pub const TimeDefaults = struct {
    /// Default flush interval in milliseconds.
    pub const flushIntervalMs: u64 = 1000;
    /// Default async write timeout in milliseconds.
    pub const writeTimeoutMs: u64 = 5000;
    /// Default connection timeout in milliseconds.
    pub const connectionTimeoutMs: u64 = 10000;
    /// Default retry delay in milliseconds.
    pub const retryDelayMs: u64 = 100;
    /// Maximum retry attempts for network operations.
    pub const maxRetries: u32 = 3;
};

/// Async configuration constants.
///
/// Usage:
///   Constants specific to async logging behavior.
pub const AsyncConstants = struct {
    /// Sleep duration when blocking on full queue.
    pub const blockSleepNs: u64 = 1 * TimeConstants.nsPerMs;
    /// Default batch size for async processing.
    pub const batchSize: usize = BufferSizes.asyncBatch;
    /// Queue utilization ratio that counts as backpressure.
    pub const backpressureThresholdRatio: f64 = 0.9;
    /// Default time to wait for an async queue to drain during explicit waits.
    pub const drainTimeoutMs: u64 = 5000;
};

/// Default limits for queues and buffers.
///
/// Usage:
///   Use these constants for queue sizing and overflow handling.
pub const Limits = struct {
    /// Maximum async queue size.
    pub const maxAsyncQueueSize: usize = 10000;
    /// Maximum pending log records.
    pub const maxPendingRecords: usize = 50000;
    /// Maximum sinks per logger.
    pub const maxSinks: usize = 64;
    /// Maximum custom levels per logger.
    pub const maxCustomLevels: usize = 32;
};

/// Default thread pool settings.
///
/// Usage:
///   Use these defaults when configuring the internal thread pool.
pub const ThreadDefaults = struct {
    /// Default number of threads (0 = auto-detect).
    pub const threadCount: usize = 0;
    /// Low-latency preset thread count.
    pub const lowLatencyThreadCount: usize = 2;
    /// Default queue size per thread.
    pub const queueSize: usize = 1024;
    /// Default stack size for worker threads.
    pub const stackSize: usize = 1024 * 1024; // 1MB
    /// High-throughput preset stack size.
    pub const highThroughputStackSize: usize = stackSize * 2;
    /// I/O-bound preset queue size.
    pub const ioBoundQueueSize: usize = queueSize * 2;
    /// Low-resource preset stack size.
    pub const lowResourceStackSize: usize = stackSize / 2;
    /// Default wait timeout in nanoseconds.
    pub const waitTimeoutNs: u64 = 100 * TimeConstants.nsPerMs;
    /// Maximum concurrent tasks.
    pub const maxTasks: usize = 10000;
    /// Queue size for low resource environments.
    pub const queueSizeLow: usize = 128;
    /// Default thread name prefix.
    pub const threadNamePrefix: []const u8 = "logly-worker";

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

/// OpenTelemetry configuration defaults.
pub const TelemetryDefaults = struct {
    /// Default batch span export size.
    pub const batchSize: usize = 256;
    /// Default batch export timeout in milliseconds.
    pub const batchTimeoutMs: u64 = 5000;
    /// Default initial capacity for formatting baggage header values.
    pub const headerInitialCapacity: usize = 256;
    /// Default sampling rate (1.0 = 100%).
    pub const samplingRate: f64 = 1.0;
    /// Default W3C traceparent header name.
    pub const traceHeader: []const u8 = "traceparent";
    /// Default baggage/correlation context header name.
    pub const baggageHeader: []const u8 = "baggage";
    /// Default prefix for exported metric names.
    pub const metricPrefix: []const u8 = "";
    /// Default separator inserted between a metric prefix and metric name.
    pub const metricPrefixSeparator: []const u8 = "_";
    /// Whether metric names should be sanitized for exporter compatibility.
    pub const sanitizeMetricNames: bool = true;

    /// Zipkin default batch size.
    pub const zipkinBatchSize: usize = 512;
    /// OpenTelemetry Collector default batch size.
    pub const collectorBatchSize: usize = 512;
    /// High-throughput batch size for telemetry exports.
    pub const highThroughputBatchSize: usize = 1024;
    /// High-throughput batch timeout in milliseconds.
    pub const highThroughputBatchTimeoutMs: u64 = 2000;
    /// High-throughput sampling rate (1%).
    pub const highThroughputSamplingRate: f64 = 0.01;
    /// Google Analytics 4 batch limit per request.
    pub const googleAnalyticsBatchLimit: usize = 25;
};

/// Async preset tuning defaults.
///
/// Usage:
///   Shared values used by async-related configuration presets.
pub const AsyncPresetDefaults = struct {
    /// High-throughput preset values.
    pub const highThroughputBufferSize: usize = 64 * 1024;
    pub const highThroughputFlushIntervalMs: u64 = 500;
    pub const highThroughputMinFlushIntervalMs: u64 = 50;
    pub const highThroughputMaxLatencyMs: u64 = 1000;
    pub const highThroughputBatchSize: usize = TelemetryDefaults.batchSize;

    /// Low-latency preset values.
    pub const lowLatencyBufferSize: usize = 1024;
    pub const lowLatencyFlushIntervalMs: u64 = 10;
    pub const lowLatencyMinFlushIntervalMs: u64 = 1;
    pub const lowLatencyMaxLatencyMs: u64 = 50;
    pub const lowLatencyBatchSize: usize = 16;

    /// Balanced / no-drop preset values.
    pub const balancedFlushIntervalMs: u64 = 100;
    pub const balancedMinFlushIntervalMs: u64 = 10;
    pub const balancedMaxLatencyMs: u64 = 500;
    /// No-drop preset buffer size.
    pub const noDropBufferSize: usize = BufferSizes.asyncQueue * 2;
};

/// Logger config preset tuning defaults.
///
/// Usage:
///   Shared values used by top-level `Config` presets.
pub const ConfigPresetDefaults = struct {
    /// High-throughput preset values.
    pub const highThroughputSamplingTargetRate: u32 = 1000;
    pub const highThroughputRateLimitPerSecond: u32 = 10000;
    pub const highThroughputBufferSize: usize = AsyncPresetDefaults.highThroughputBufferSize;
    pub const highThroughputBufferFlushIntervalMs: u64 = AsyncPresetDefaults.highThroughputFlushIntervalMs;
    pub const highThroughputMaxPending: usize = Limits.maxPendingRecords * 2;
    pub const highThroughputThreadPoolQueueSize: usize = Limits.maxPendingRecords;
    pub const highThroughputAsyncBufferSize: usize = BufferSizes.compression;
    pub const highThroughputAsyncBatchSize: usize = AsyncPresetDefaults.highThroughputBatchSize;
    pub const highThroughputAsyncFlushIntervalMs: u64 = AsyncPresetDefaults.highThroughputMinFlushIntervalMs;
};

test "telemetry defaults exist" {
    // Ensure central telemetry defaults are present and correct
    try std.testing.expectEqual(@as(usize, TelemetryDefaults.batchSize), @as(usize, 256));
    try std.testing.expectEqual(@as(u64, TelemetryDefaults.batchTimeoutMs), @as(u64, 5000));
    try std.testing.expectEqual(@as(usize, TelemetryDefaults.headerInitialCapacity), @as(usize, 256));
    try std.testing.expectEqualStrings(TelemetryDefaults.traceHeader, "traceparent");
    try std.testing.expectEqualStrings(TelemetryDefaults.baggageHeader, "baggage");
    try std.testing.expectEqualStrings(TelemetryDefaults.metricPrefix, "");
    try std.testing.expectEqualStrings(TelemetryDefaults.metricPrefixSeparator, "_");
    try std.testing.expect(TelemetryDefaults.sanitizeMetricNames);
}

test "shared metrics and async defaults exist" {
    try std.testing.expectEqualStrings("logly", MetricsConstants.defaultPrefix);
    try std.testing.expectEqualStrings("_", MetricsConstants.prometheusSeparator);
    try std.testing.expectEqualStrings(".", MetricsConstants.statsdSeparator);
    try std.testing.expect(MetricsConstants.sanitizeNames);
    try std.testing.expect(MetricsConstants.includeLevelBreakdown);
    try std.testing.expect(MetricsConstants.includeSinkBreakdown);
    try std.testing.expect(AsyncConstants.backpressureThresholdRatio > 0.0);
    try std.testing.expect(AsyncConstants.drainTimeoutMs > 0);
}

/// Log level count and priorities.
///
/// Usage:
///   Reference constants for defining new log levels or validating priority ranges.
pub const LevelConstants = struct {
    /// Total number of built-in log levels.
    pub const count: usize = 10;
    /// Minimum priority value (TRACE).
    pub const minPriority: u8 = 5;
    /// Maximum priority value (FATAL).
    pub const maxPriority: u8 = 55;
    /// Default level priority (INFO).
    pub const defaultPriority: u8 = 20;

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
pub const TimeConstants = struct {
    /// Milliseconds per second.
    pub const msPerSecond: u64 = 1000;
    /// Microseconds per second.
    pub const usPerSecond: u64 = 1_000_000;
    /// Nanoseconds per second.
    pub const nsPerSecond: u64 = 1_000_000_000;

    /// Seconds-based helpers for interval reuse (avoid repeating literal values).
    pub const secondsPerMinute: u64 = 60;
    pub const secondsPerHour: u64 = secondsPerMinute * 60;
    pub const secondsPerDay: u64 = secondsPerHour * 24;
    pub const secondsPerWeek: u64 = secondsPerDay * 7;
    pub const secondsPerMonth: u64 = secondsPerDay * 30; // 30-day month approximation
    pub const secondsPerYear: u64 = secondsPerDay * 365;

    /// Minute-based helpers for timestamp and offset calculations.
    pub const minutesPerHour: u16 = @intCast(secondsPerHour / secondsPerMinute);
    pub const minutesPerDay: u16 = @intCast(secondsPerDay / secondsPerMinute);

    /// Supported UTC offset bounds in minutes (derived from 24h clock constraints).
    pub const maxUtcOffsetMinutes: i16 = @as(i16, @intCast(minutesPerDay - 1));
    pub const minUtcOffsetMinutes: i16 = -maxUtcOffsetMinutes;

    /// Default human-readable timestamp pattern.
    pub const defaultTimePattern: []const u8 = "YYYY-MM-DD HH:mm:ss.SSS";

    /// Derived conversions for convenient, consistent unit conversions.
    /// - `us_per_ms`: microseconds per millisecond (1_000)
    /// - `ns_per_ms`: nanoseconds per millisecond (1_000_000)
    /// - `ns_per_us`: nanoseconds per microsecond (1_000)
    pub const usPerMs: u64 = usPerSecond / msPerSecond;
    pub const nsPerMs: u64 = nsPerSecond / msPerSecond;
    pub const nsPerUs: u64 = nsPerSecond / usPerSecond;

    /// Default flush interval in milliseconds (derived from TimeDefaults).
    pub const defaultFlushIntervalMs: u64 = TimeDefaults.flushIntervalMs;
    /// Default rotation check interval in milliseconds (derived from seconds_per_minute).
    pub const rotationCheckIntervalMs: u64 = secondsPerMinute * msPerSecond; // 1 minute
};

/// Metrics-related constants.
pub const MetricsConstants = struct {
    /// Default exported metric namespace.
    pub const defaultPrefix: []const u8 = "logly";
    /// Separator used by Prometheus-compatible metric names.
    pub const prometheusSeparator: []const u8 = "_";
    /// Separator used by StatsD metric names.
    pub const statsdSeparator: []const u8 = ".";
    /// Sanitize metric names by default for exporter compatibility.
    pub const sanitizeNames: bool = true;
    /// Include per-level counters in metrics exports by default.
    pub const includeLevelBreakdown: bool = true;
    /// Include per-sink counters in metrics exports by default.
    pub const includeSinkBreakdown: bool = true;

    /// Default histogram bucket boundaries in nanoseconds.
    pub const histogramBoundaries = [_]u64{
        1_000,         2_000,                5_000,     10_000,     20_000,     50_000,     100_000,     200_000,     500_000,
        1_000_000,     2_000_000,            5_000_000, 10_000_000, 20_000_000, 50_000_000, 100_000_000, 200_000_000, 500_000_000,
        1_000_000_000, std.math.maxInt(u64),
    };

    /// Uppercase log level names for metrics display.
    pub const levelNames = [_][]const u8{
        "TRACE", "DEBUG", "INFO", "NOTICE", "SUCCESS", "WARNING", "ERROR", "FAIL", "CRITICAL", "FATAL",
    };
};

/// File rotation constants.
///
/// Usage:
///   Defaults for file size limits and retention policies.
pub const RotationConstants = struct {
    /// Default max file size before rotation (10MB).
    pub const defaultMaxSize: u64 = 10 * 1024 * 1024;
    /// Default max number of backup files.
    pub const defaultMaxFiles: usize = 5;
    /// Default compressed file extension.
    pub const compressedExt: []const u8 = ".gz";
};
/// Terminal colors are provided by tint.zig via `color.zig`.
/// See `color.Color`, `color.Style`, and `color.Theme` for the authoritative
/// implementation; `Constants` no longer carries SGR string tables.
/// Network logging constants.
///
/// Usage:
///   Buffer sizes and timeouts for network sinks.
pub const NetworkConstants = struct {
    /// Default TCP buffer size.
    pub const tcpBufferSize: usize = 8192;
    /// Default UDP max packet size.
    pub const udpMaxPacket: usize = 65507;
    /// Default connection timeout in milliseconds.
    pub const connectTimeoutMs: u64 = 5000;
    /// Default send timeout in milliseconds.
    pub const sendTimeoutMs: u64 = 1000;
};

/// Invoke system constants.
///
/// Usage:
///   Limits for invoke triggers and messages.
pub const InvokeConstants = struct {
    /// Maximum number of triggers allowed by default.
    pub const defaultMaxRules: usize = 1000;
    /// Maximum messages per trigger allowed by default.
    pub const defaultMaxMessages: usize = 10;
};

/// Syslog constants for RFC 5424 compliance.
///
/// Usage:
///   Standard syslog severity levels and facility codes for network logging.
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
    pub const defaultPort: u16 = 514;
};

/// Compression algorithm constants.
///
/// Usage:
///   Constants for DEFLATE/LZ77 window sizes and limits.
pub const CompressionConstants = struct {
    /// Window size for fast compression (256).
    pub const windowFast: usize = 256;
    /// Window size for default compression (1024).
    pub const windowDefault: usize = 1024;
    /// Window size for best compression (4096).
    pub const windowBest: usize = 4096;
    /// Minimum match length (3).
    pub const minMatch: usize = 3;
    /// Maximum match length (255).
    pub const maxMatch: usize = 255;
    /// Maximum run length for RLE (127).
    pub const maxRunLength: usize = 127;
    /// LZMA dictionary size (64KB).
    pub const lzmaDictSize: u32 = 65536;
    /// LZMA maximum offset (64KB - 1).
    pub const lzmaMaxOffset: usize = 65535;
    /// LZMA hash bits (14).
    pub const lzmaHashBits: u5 = 14;
    /// LZMA maximum match length (272).
    pub const lzmaMaxMatch: usize = 272;
    /// LZMA2 chunk size (32KB).
    pub const lzma2ChunkSize: usize = 32768;

    /// LZ4 minimum match length.
    pub const lz4MinMatch: usize = 4;
    /// LZ4 maximum back-reference offset (16-bit).
    pub const lz4MaxOffset: usize = 65535;
    /// LZ4 hash table bit width.
    pub const lz4HashBits: u5 = 16;
    /// Maximum chain depth for LZMA match search.
    pub const lzmaMaxChainSearch: usize = 32;

    /// Magic bytes for various formats
    pub const Magic = struct {
        pub const lzma = "\x5D\x00\x00\x80\x00"; // Typical start, but varied
        pub const xz = "\xFD\x37\x7A\x58\x5A\x00";
        pub const gzip = "\x1F\x8B";
        pub const zlib = "\x78\x9C"; // Default
        pub const logly = "LGZ";
    };

    /// LZMA properties: lc=3, lp=0, pb=2 (standard)
    pub const lzmaPropertiesByte: u8 = (2 * 5 + 0) * 9 + 3;

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
        pub const tarGz = CompressionExtensions.tarGz;
        pub const zip = CompressionExtensions.zip;
        pub const lz4 = CompressionExtensions.lz4;
        pub const brotli = CompressionExtensions.brotli;
        pub const none = "";
    };
};

/// Windows Event Log constants (Word values for ReportEvent)
pub const EventLogConstants = struct {
    pub const success: u16 = 0x0000;
    pub const errorType: u16 = 0x0001;
    pub const warningType: u16 = 0x0002;
    pub const informationType: u16 = 0x0004;
};

test "event log constants exist" {
    try std.testing.expectEqual(@as(u16, EventLogConstants.success), @as(u16, 0x0000));
    try std.testing.expectEqual(@as(u16, EventLogConstants.errorType), @as(u16, 0x0001));
    try std.testing.expectEqual(@as(u16, EventLogConstants.warningType), @as(u16, 0x0002));
    try std.testing.expectEqual(@as(u16, EventLogConstants.informationType), @as(u16, 0x0004));
}

/// Scheduler defaults.
///
/// Usage:
///   Default values for task scheduling and maintenance.
pub const SchedulerDefaults = struct {
    /// Default retry interval in milliseconds (5s).
    pub const retryIntervalMs: u32 = 5000;
    /// Default cleanup max age in seconds (7 days).
    pub const maxAgeSeconds: u64 = 7 * TimeConstants.secondsPerDay;
    /// Cron fallback interval in milliseconds (1 min).
    pub const cronFallbackIntervalMs: i64 = @as(i64, TimeConstants.secondsPerMinute * TimeConstants.msPerSecond);
};

/// Rotation default settings.
///
/// Usage:
///   Default values for log rotation.
pub const RotationDefaults = struct {
    /// Default retention count (10).
    pub const retentionCount: usize = 10;
};

/// General configuration defaults.
///
/// Usage:
///   Default values for general logger configuration.
pub const ConfigDefaults = struct {
    /// Default stack size for stack trace capturing (1MB).
    pub const stackSize: usize = 1024 * 1024;
    /// Default distributed trace header name.
    pub const distributedTraceHeader: []const u8 = "X-Trace-ID";
    /// Default distributed span header name.
    pub const distributedSpanHeader: []const u8 = "X-Span-ID";
    /// Default distributed parent span header name.
    pub const distributedParentHeader: []const u8 = "X-Parent-ID";
    /// Default distributed baggage header name.
    pub const distributedBaggageHeader: []const u8 = "Correlation-Context";
};

/// Redaction defaults.
///
/// Usage:
///   Default values for redaction configuration.
pub const RedactionDefaults = struct {
    /// Default characters to reveal at start.
    pub const partialStartChars: u8 = 4;
    /// Default characters to reveal at end.
    pub const partialEndChars: u8 = 4;
    /// Default mask character.
    pub const maskChar: u8 = '*';
    /// Default max length for truncate redaction.
    pub const truncateLength: u8 = 8;
    /// Default suffix for truncate redaction.
    pub const truncateSuffix: []const u8 = "...";
    /// Default replacement text for full redaction.
    pub const replacement: []const u8 = "[REDACTED]";
};

/// Rate limiting defaults.
///
/// Usage:
///   Default values for rate limiting configuration.
pub const RateLimitDefaults = struct {
    /// Default max requests per second.
    pub const maxPerSecond: u32 = 1000;
    /// Default burst size.
    pub const burstSize: u32 = 100;
};

/// Sampling defaults.
///
/// Usage:
///   Default values for sampling configuration.
pub const SamplingDefaults = struct {
    /// Default rate limit window in milliseconds.
    pub const rateLimitWindowMs: u64 = 1000;
    /// Default adaptive adjustment interval in milliseconds.
    pub const adaptiveAdjustmentIntervalMs: u64 = 1000;
    /// Default minimum adaptive sample rate.
    pub const adaptiveMinRate: f64 = 0.01;
    /// Default maximum adaptive sample rate.
    pub const adaptiveMaxRate: f64 = 1.0;
};

/// Parallel sink writing defaults.
///
/// Usage:
///   Default values for parallel sink configuration.
pub const ParallelDefaults = struct {
    /// Default maximum concurrent writes.
    pub const maxConcurrent: usize = 8;
    /// High throughput maximum concurrent writes.
    pub const highThroughputMaxConcurrent: usize = 16;
    /// Default buffer size.
    pub const bufferSize: usize = 64;
    /// High throughput buffer size.
    pub const highThroughputBufferSize: usize = 128;
    /// Default maximum retries.
    pub const maxRetries: u3 = 3;
    /// Default write timeout in milliseconds.
    pub const writeTimeoutMs: u64 = 5000;

    /// Low latency configuration presets.
    pub const lowLatencyMaxConcurrent: usize = 4;
    pub const lowLatencyTimeoutMs: u64 = 500;

    /// Reliable configuration presets.
    pub const reliableMaxConcurrent: usize = 8;
    pub const reliableTimeoutMs: u64 = 2000;
    pub const reliableMaxRetries: u3 = 5;
};

test "atomic types exist" {
    // Verify atomic types are defined for cross-platform compatibility
    try std.testing.expect(@sizeOf(AtomicUnsigned) > 0);
    try std.testing.expect(@sizeOf(AtomicSigned) > 0);
    try std.testing.expect(@sizeOf(usize) > 0);
    try std.testing.expect(@sizeOf(isize) > 0);
}

test "atomic and native types match pointer width" {
    const ptrBits = @bitSizeOf(usize);
    try std.testing.expectEqual(ptrBits, @bitSizeOf(AtomicUnsigned));
    try std.testing.expectEqual(ptrBits, @bitSizeOf(AtomicSigned));
    try std.testing.expectEqual(ptrBits, @bitSizeOf(usize));
    try std.testing.expectEqual(ptrBits, @bitSizeOf(isize));
}

test "buffer sizes are reasonable" {
    try std.testing.expect(BufferSizes.message > 0);
    try std.testing.expect(BufferSizes.format >= BufferSizes.message);
    try std.testing.expect(BufferSizes.sink >= BufferSizes.format);
    try std.testing.expect(BufferSizes.maxMessage >= BufferSizes.sink);
}

test "thread defaults are reasonable" {
    try std.testing.expect(ThreadDefaults.stackSize > 0);
    try std.testing.expect(ThreadDefaults.queueSize > 0);
    try std.testing.expect(ThreadDefaults.maxTasks > 0);
    try std.testing.expect(ThreadDefaults.waitTimeoutNs > 0);
}

test "level constants are valid" {
    try std.testing.expect(LevelConstants.count > 0);
    try std.testing.expect(LevelConstants.minPriority < LevelConstants.maxPriority);
    try std.testing.expect(LevelConstants.defaultPriority >= LevelConstants.minPriority);
    try std.testing.expect(LevelConstants.defaultPriority <= LevelConstants.maxPriority);
}

test "time constants are correct" {
    try std.testing.expectEqual(@as(u64, 1000), TimeConstants.msPerSecond);
    try std.testing.expectEqual(@as(u64, 1_000_000), TimeConstants.usPerSecond);
    try std.testing.expectEqual(@as(u64, 1_000_000_000), TimeConstants.nsPerSecond);

    try std.testing.expectEqual(@as(u64, 60), TimeConstants.secondsPerMinute);
    try std.testing.expectEqual(@as(u64, 3600), TimeConstants.secondsPerHour);
    try std.testing.expectEqual(@as(u64, 86400), TimeConstants.secondsPerDay);
    try std.testing.expectEqual(@as(u64, 604800), TimeConstants.secondsPerWeek);
    try std.testing.expectEqual(@as(u64, 2592000), TimeConstants.secondsPerMonth);
    try std.testing.expectEqual(@as(u64, 31536000), TimeConstants.secondsPerYear);

    try std.testing.expectEqual(@as(u16, 60), TimeConstants.minutesPerHour);
    try std.testing.expectEqual(@as(u16, 1440), TimeConstants.minutesPerDay);
    try std.testing.expectEqual(@as(i16, 1439), TimeConstants.maxUtcOffsetMinutes);
    try std.testing.expectEqual(@as(i16, -1439), TimeConstants.minUtcOffsetMinutes);
    try std.testing.expectEqualStrings("YYYY-MM-DD HH:mm:ss.SSS", TimeConstants.defaultTimePattern);

    // Rotation check interval must be consistent with seconds_per_minute and ms_per_second
    try std.testing.expectEqual(TimeConstants.secondsPerMinute * TimeConstants.msPerSecond, TimeConstants.rotationCheckIntervalMs);
    try std.testing.expectEqual(@as(u64, 60_000), TimeConstants.rotationCheckIntervalMs);
}

test "rotation constants are reasonable" {
    try std.testing.expect(RotationConstants.defaultMaxSize > 0);
    try std.testing.expect(RotationConstants.defaultMaxFiles > 0);
    try std.testing.expect(RotationConstants.compressedExt.len > 0);
}

test "network constants are reasonable" {
    try std.testing.expect(NetworkConstants.tcpBufferSize > 0);
    try std.testing.expect(NetworkConstants.udpMaxPacket > 0);
    try std.testing.expect(NetworkConstants.connectTimeoutMs > 0);
    try std.testing.expect(NetworkConstants.sendTimeoutMs > 0);
}

test "invoke constants exist" {
    try std.testing.expect(InvokeConstants.defaultMaxRules > 0);
    try std.testing.expect(InvokeConstants.defaultMaxMessages > 0);
}

test "syslog constants exist" {
    // Test severity enum values
    try std.testing.expectEqual(@as(u3, 0), @backingInt(SyslogConstants.Severity.emergency));
    try std.testing.expectEqual(@as(u3, 6), @backingInt(SyslogConstants.Severity.info));
    try std.testing.expectEqual(@as(u3, 7), @backingInt(SyslogConstants.Severity.debug));

    // Test facility enum values
    try std.testing.expectEqual(@as(u5, 0), @backingInt(SyslogConstants.Facility.kern));
    try std.testing.expectEqual(@as(u5, 1), @backingInt(SyslogConstants.Facility.user));
    try std.testing.expectEqual(@as(u5, 16), @backingInt(SyslogConstants.Facility.local0));

    // Test severity conversion
    try std.testing.expectEqual(SyslogConstants.Severity.debug, SyslogConstants.Severity.fromLogLevel(.debug));
    try std.testing.expectEqual(SyslogConstants.Severity.info, SyslogConstants.Severity.fromLogLevel(.info));
    try std.testing.expectEqual(SyslogConstants.Severity.err, SyslogConstants.Severity.fromLogLevel(.err));
}

test "tint colors render expected sequences" {
    const tint = @import("color.zig").Tint;
    try std.testing.expectEqualStrings("\x1b[31m", tint.color.ansi4.red.fg().slice());
    try std.testing.expectEqualStrings("\x1b[91m", tint.color.ansi4.brightRed.fg().slice());
    try std.testing.expectEqualStrings("\x1b[38;5;196m", tint.color.ansi256.index(196).fg().slice());
    try std.testing.expectEqualStrings("\x1b[38;2;255;127;80m", tint.color.rgb(255, 127, 80).fg().slice());
    try std.testing.expectEqualStrings("\x1b[0m", tint.ansi.reset.all);
}

/// Filter system defaults.
pub const FilterDefaults = struct {
    /// Default maximum rules per filter instance.
    pub const maxRules: usize = 256;
    /// Default time-window start hour (0-23).
    pub const defaultQuietHourStart: u8 = 22;
    /// Default time-window end hour (0-23).
    pub const defaultQuietHourEnd: u8 = 6;
    /// Default rate-based filter max messages per second per module.
    pub const defaultRatePerSecond: u32 = 1000;
    /// Default deny-list initial capacity.
    pub const denyListCapacity: usize = 64;
    /// Token bucket refill interval for rate-based filters (ms).
    pub const tokenBucketIntervalMs: u64 = 1000;
};

/// Formatter output format defaults.
pub const FormatterDefaults = struct {
    /// Default field separator for logfmt output.
    pub const logfmtSeparator: []const u8 = " ";
    /// Default field assignment character for logfmt.
    pub const logfmtAssign: []const u8 = "=";
    /// Default level field width (padded to align output).
    pub const levelFieldWidth: usize = 8;
    /// Default module field width.
    pub const moduleFieldWidth: usize = 20;
    /// Default padding character.
    pub const padChar: u8 = ' ';
    /// NDJSON line terminator.
    pub const ndjsonTerminator: u8 = '\n';
    /// Template default format string.
    pub const defaultTemplate: []const u8 = "{time} [{level}] {message}";
    /// Maximum template field name length.
    pub const maxTemplateFieldLen: usize = 32;
};

/// Sink system defaults.
pub const SinkDefaults = struct {
    /// Default max buffer records.
    pub const maxBufferRecords: usize = 1000;
    /// Default flush interval in milliseconds.
    pub const flushIntervalMs: u64 = 1000;
    /// Default memory sink ring-buffer capacity (records).
    pub const memoryRingSize: usize = 1024;
    /// Default per-sink rate limit (messages per second, 0 = unlimited).
    pub const rateLimitPerSecond: u32 = 0;
    /// Number of consecutive errors before a sink is considered unhealthy.
    pub const unhealthyErrorThreshold: u32 = 10;
    /// Default flush period for buffered sinks (ms).
    pub const flushPeriodMs: u64 = TimeConstants.defaultFlushIntervalMs;
    /// Stderr sink name.
    pub const stderrName: []const u8 = "stderr";
    /// Stdout sink name.
    pub const stdoutName: []const u8 = "stdout";
    /// Memory sink name.
    pub const memoryName: []const u8 = "memory";
};

/// Record field defaults.
pub const RecordDefaults = struct {
    /// Maximum number of context fields per record.
    pub const maxContextFields: usize = 64;
    /// Maximum stack trace depth.
    pub const maxStackDepth: usize = 32;
    /// Severity scale maximum.
    pub const severityMax: u8 = 100;
    /// Tag separator for multi-tag strings.
    pub const tagSeparator: []const u8 = ",";
    /// Unknown module name placeholder.
    pub const unknownModule: []const u8 = "unknown";
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
    pub const backoffBaseNs: u64 = 100 * TimeConstants.nsPerUs;
    /// Backoff maximum sleep in nanoseconds.
    pub const backoffMaxNs: u64 = 10 * TimeConstants.nsPerMs;
    /// Backoff multiplier.
    pub const backoffMultiplier: u64 = 2;
    /// Priority queue fast-path levels (critical and above bypass normal queue).
    pub const priorityBypassThreshold: u8 = 50; // maps to .critical priority
    /// Default shutdown grace period (ms).
    pub const shutdownTimeoutMs: u64 = 5000;
    /// Default batch flush callback label.
    pub const batchFlushLabel: []const u8 = "batch_flush";
};

/// Redaction pattern defaults.
pub const RedactionPatterns = struct {
    /// Regex-like pattern for email addresses.
    pub const email: []const u8 = "[\\w.+-]+@[\\w-]+\\.[\\w.]+";
    /// Pattern prefix for JWT detection (base64url encoded JSON).
    pub const jwtPrefix: []const u8 = "ey";
    /// Minimum JWT token length (header.payload.sig).
    pub const jwtMinLength: usize = 20;
    /// IPv4 pattern approximation.
    pub const ipv4Segment: []const u8 = "\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}";
    /// Credit card minimum digit count.
    pub const ccMinDigits: usize = 13;
    /// Credit card maximum digit count.
    pub const ccMaxDigits: usize = 19;
    /// Default redaction replacement for sensitive patterns.
    pub const sensitiveReplacement: []const u8 = "[REDACTED]";
    /// Email redaction replacement.
    pub const emailReplacement: []const u8 = "[EMAIL]";
    /// IP address redaction replacement.
    pub const ipReplacement: []const u8 = "[IP]";
    /// JWT redaction replacement.
    pub const jwtReplacement: []const u8 = "[JWT]";
    /// Credit card redaction replacement.
    pub const ccReplacement: []const u8 = "[CARD]";
};

/// Network sink defaults (extended).
pub const NetworkExtendedDefaults = struct {
    /// Auto-reconnect initial delay (ms).
    pub const reconnectInitialDelayMs: u64 = 100;
    /// Auto-reconnect max delay (ms).
    pub const reconnectMaxDelayMs: u64 = 30_000;
    /// Auto-reconnect backoff multiplier.
    pub const reconnectBackoffMult: u64 = 2;
    /// TCP keepalive idle time (seconds).
    pub const keepaliveIdleSecs: u32 = 60;
    /// TCP keepalive probe interval (seconds).
    pub const keepaliveIntervalSecs: u32 = 10;
    /// TCP keepalive max probe count.
    pub const keepaliveMaxProbes: u32 = 6;
    /// Default chunk size for HTTP chunked streaming (bytes).
    pub const chunkedChunkSize: usize = 4096;
    /// Syslog RFC-5424 version number.
    pub const syslogVersion: u8 = 1;
    /// Syslog default facility (16 = local0).
    pub const syslogDefaultFacility: u8 = 16;
    /// Syslog default app name.
    pub const syslogAppName: []const u8 = "logly";
    /// Syslog nilvalue.
    pub const syslogNilvalue: []const u8 = "-";
};

/// Scheduler system constants (extended).
pub const SchedulerExtendedDefaults = struct {
    /// Maximum jitter in milliseconds (added as random +/-jitter to task intervals).
    pub const maxJitterMs: u64 = 5000;
    /// Default jitter percentage of interval (0.0 = no jitter, 0.1 = +/-10%).
    pub const defaultJitterFraction: f64 = 0.0;
    /// Cron-expression field count.
    pub const cronFieldCount: usize = 5;
    /// Task history ring size (entries).
    pub const taskHistorySize: usize = 32;
    /// One-shot task min delay (ms).
    pub const oneShotMinDelayMs: u64 = 1;
};

/// Telemetry extended constants.
pub const TelemetryExtendedDefaults = struct {
    /// OTLP Logs signal JSON content-type.
    pub const otlpContentType: []const u8 = "application/json";
    /// Google Cloud Logging JSON severity field name.
    pub const gcpSeverityField: []const u8 = "severity";
    /// Google Cloud Logging timestamp field.
    pub const gcpTimestampField: []const u8 = "timestamp";
    /// Google Cloud Logging message field.
    pub const gcpMessageField: []const u8 = "message";
    /// Datadog log level field name.
    pub const datadogLevelField: []const u8 = "status";
    /// Datadog source field name.
    pub const datadogSourceField: []const u8 = "ddsource";
    /// Datadog service field name.
    pub const datadogServiceField: []const u8 = "service";
    /// Datadog tags field name.
    pub const datadogTagsField: []const u8 = "ddtags";
    /// W3C Baggage header name.
    pub const w3cBaggageHeader: []const u8 = "baggage";
    /// OTLP Logs resource attributes key.
    pub const otlpResourceKey: []const u8 = "resource";
    /// OTLP Logs attributes key.
    pub const otlpAttrsKey: []const u8 = "attributes";
};

/// Compression level constants.
pub const CompressionLevelDefaults = struct {
    /// Default gzip/deflate compression level (1-9).
    pub const gzipDefault: u8 = 6;
    /// Fast gzip/deflate compression level.
    pub const gzipFast: u8 = 1;
    /// Maximum gzip/deflate compression level.
    pub const gzipMax: u8 = 9;
    /// Default zstd compression level (1-22).
    pub const zstdDefault: u8 = 3;
    /// Fast zstd compression level.
    pub const zstdFast: u8 = 1;
    /// Maximum zstd compression level.
    pub const zstdMax: u8 = 22;
};

/// Default crash handler settings and strings.
pub const CrashConstants = struct {
    /// Prefix prepended to panics in the log.
    pub const panicMessagePrefix: []const u8 = "CRITICAL PANIC OCCURRED: ";
    /// Stderr fallback message prefix.
    pub const panicInterceptorPrefix: []const u8 = "Logly Panic Interceptor: ";
    /// Prefix prepended to OS-level crashes in the log.
    pub const crashMessagePrefix: []const u8 = "CRITICAL CRASH: ";
    /// Stderr fallback message prefix for OS-level crashes.
    pub const crashInterceptorPrefix: []const u8 = "Logly Crash Interceptor: ";

    /// Windows exception code mapping structure.
    pub const WindowsException = struct {
        code: u32,
        name: []const u8,
        isFatal: bool,
    };

    /// List of Windows Vectored Exception codes, names, and whether they are fatal.
    pub const windowsExceptions = [_]WindowsException{
        .{ .code = 0xC0000005, .name = "STATUS_ACCESS_VIOLATION (Access Violation)", .isFatal = true },
        .{ .code = 0xC0000094, .name = "STATUS_INTEGER_DIVIDE_BY_ZERO (Integer Division by Zero)", .isFatal = true },
        .{ .code = 0xC000001D, .name = "STATUS_ILLEGAL_INSTRUCTION (Illegal Instruction)", .isFatal = true },
        .{ .code = 0xC00000FD, .name = "STATUS_STACK_OVERFLOW (Stack Overflow)", .isFatal = true },
        .{ .code = 0xC0000025, .name = "STATUS_NONCONTINUABLE_EXCEPTION (Noncontinuable Exception)", .isFatal = true },
        .{ .code = 0xC0000008, .name = "STATUS_INVALID_HANDLE (Invalid Handle)", .isFatal = true },
        .{ .code = 0x80000003, .name = "STATUS_BREAKPOINT (Breakpoint)", .isFatal = false },
    };

    pub const unknownWindowsException: []const u8 = "UNKNOWN_WINDOWS_EXCEPTION";
    pub const windowsFallbackMsg: []const u8 = "CRITICAL CRASH: Windows native exception triggered\n";
    pub const windowsTriggeredFmt: []const u8 = "Windows exception triggered: {s} (Code: 0x{X})\n";
    pub const windowsStderrFmt: []const u8 = "Process triggered fatal exception 0x{X}\n";

    /// POSIX signal names mapping.
    pub const posixSigsegv: []const u8 = "SIGSEGV (Segmentation Fault)";
    pub const posixSigill: []const u8 = "SIGILL (Illegal Instruction)";
    pub const posixSigfpe: []const u8 = "SIGFPE (Floating Point Exception)";
    pub const posixSigabrt: []const u8 = "SIGABRT (Abort Signal)";
    pub const posixSigbus: []const u8 = "SIGBUS (Bus Error)";
    pub const posixUnknownSignal: []const u8 = "Unknown Signal";

    pub const posixFallbackMsg: []const u8 = "CRITICAL CRASH: Process received standard POSIX signal\n";
    pub const posixReceivedFmt: []const u8 = "Process received POSIX signal {s} ({d})\n";
    pub const posixStderrFmt: []const u8 = "Process received standard POSIX signal {d}\n";
};
