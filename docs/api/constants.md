---
title: Constants API Reference
description: API reference for Logly.zig Constants. Defines cross-platform atomic types, buffer sizes, and default configuration values.
head:
  - - meta
    - name: keywords
      content: constants api, atomic types, buffer sizes, default configuration, cross-platform
  - - meta
    - property: og:title
      content: Constants API Reference | Logly.zig
---

# Constants API

The `Constants` module provides architecture-dependent types and default configuration values used throughout the library.

## Atomic Types

Cross-platform atomic integer types ensuring compatibility between 32-bit and 64-bit architectures.

```zig
/// Architecture-dependent unsigned atomic integer type
pub const AtomicUnsigned = std.meta.Int(.unsigned, @bitSizeOf(usize));

/// Architecture-dependent signed atomic integer type
pub const AtomicSigned = std.meta.Int(.signed, @bitSizeOf(usize));

/// Native pointer-sized unsigned integer for the target architecture
pub const NativeUint = usize;

/// Native pointer-sized signed integer for the target architecture
pub const NativeInt = isize;
```

This pointer-width-driven approach keeps behavior correct on 32-bit and 64-bit targets across Windows, Linux, macOS, and freestanding toolchains, including `x86`, `x86_64`, and `aarch64`.

## Buffer Sizes

Default buffer sizes for various operations.

```zig
pub const BufferSizes = struct {
    /// Default log message buffer size
    pub const message: usize = 4096;
    /// Default format buffer size
    pub const format: usize = 8192;
    /// Default sink buffer size
    pub const sink: usize = 16384;
    /// Default async queue buffer size
    pub const asyncQueue: usize = 8192;
    /// Default compression buffer size
    pub const compression: usize = 32768;
    /// Default telemetry buffer size
    pub const telemetry: usize = 4096;
    /// Maximum log message size (1MB)
    pub const maxMessage: usize = 1024 * 1024;
    /// Async batch size
    pub const asyncBatch: usize = 64;
    /// Small buffer for thread IDs etc.
    pub const tiny: usize = 32;
    /// Small buffer for context values etc.
    pub const small: usize = 256;
    /// Standard file read buffer
    pub const fileRead: usize = 4096;
    /// Large file read buffer
    pub const fileReadLarge: usize = 8192;
    /// Path buffer size
    pub const pathBuffer: usize = 512;
};
```

## Thread Defaults

Default thread pool settings and helpers.

```zig
pub const ThreadDefaults = struct {
    /// Default number of threads (0 = auto-detect)
    pub const threadCount: usize = 0;
    /// Default queue size per thread
    pub const queueSize: usize = 1024;
    /// Default stack size for worker threads (1MB)
    pub const stackSize: usize = 1024 * 1024;
    /// Default wait timeout in nanoseconds
    pub const waitTimeoutNs: u64 = 100 * TimeConstants.nsPerMs;
    /// Maximum concurrent tasks
    pub const maxTasks: usize = 10000;
    /// Queue size for low resource environments
    pub const queueSizeLow: usize = 128;

    /// Returns recommended thread count for current CPU
    pub fn recommendedThreadCount() usize;
    /// Returns recommended thread count for I/O bound workloads
    pub fn ioBoundThreadCount() usize;
    /// Returns recommended thread count for CPU bound workloads
    pub fn cpuBoundThreadCount() usize;
};
```

## Level Constants

Log level counting and priorities.

```zig
pub const LevelConstants = struct {
    /// Total number of built-in log levels
    pub const count: usize = 10;
    /// Minimum priority value (TRACE)
    pub const minPriority: u8 = 5;
    /// Maximum priority value (FATAL)
    pub const maxPriority: u8 = 55;
    /// Default level priority (INFO)
    pub const defaultPriority: u8 = 20;
};
```

## Time Constants

Time conversion and default intervals.

```zig
pub const TimeConstants = struct {
    /// Milliseconds per second
    pub const msPerSecond: u64 = 1000;
    /// Microseconds per second
    pub const usPerSecond: u64 = 1_000_000;
    /// Nanoseconds per second
    pub const nsPerSecond: u64 = 1_000_000_000;

    /// Seconds-based helpers for interval reuse
    pub const secondsPerMinute: u64 = 60;
    pub const secondsPerHour: u64 = secondsPerMinute * 60;
    pub const secondsPerDay: u64 = secondsPerHour * 24;
    pub const secondsPerWeek: u64 = secondsPerDay * 7;
    pub const secondsPerMonth: u64 = secondsPerDay * 30;
    pub const secondsPerYear: u64 = secondsPerDay * 365;

    /// Derived conversions
    pub const usPerMs: u64 = usPerSecond / msPerSecond;
    pub const nsPerMs: u64 = nsPerSecond / msPerSecond;
    pub const nsPerUs: u64 = nsPerSecond / usPerSecond;

    /// Default flush interval in milliseconds
    pub const defaultFlushIntervalMs: u64 = TimeDefaults.flushIntervalMs;
    /// Default rotation check interval in milliseconds
    pub const rotationCheckIntervalMs: u64 = secondsPerMinute * msPerSecond;
};
```

## Time Defaults

Default time intervals and timeouts.

```zig
pub const TimeDefaults = struct {
    /// Default flush interval in milliseconds
    pub const flushIntervalMs: u64 = 1000;
    /// Default async write timeout in milliseconds
    pub const writeTimeoutMs: u64 = 5000;
    /// Default connection timeout in milliseconds
    pub const connectionTimeoutMs: u64 = 10000;
    /// Default retry delay in milliseconds
    pub const retryDelayMs: u64 = 100;
    /// Maximum retry attempts for network operations
    pub const maxRetries: u32 = 3;
};
```

## Config Defaults

Default values shared by top-level config and distributed logging configuration.

```zig
pub const ConfigDefaults = struct {
    /// Default stack size for stack trace capturing.
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
```

## Telemetry Defaults

OpenTelemetry configuration defaults (used by `TelemetryConfig`).

```zig
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
};
```

## Async Constants

Async configuration constants.

```zig
pub const AsyncConstants = struct {
    /// Sleep duration when blocking on full queue
    pub const blockSleepNs: u64 = 1 * TimeConstants.nsPerMs;
    /// Default batch size for async processing
    pub const batchSize: usize = BufferSizes.asyncBatch;
};
```

## Limits

Default limits for queues and buffers.

```zig
pub const Limits = struct {
    /// Maximum async queue size
    pub const maxAsyncQueueSize: usize = 10000;
    /// Maximum pending log records
    pub const maxPendingRecords: usize = 50000;
    /// Maximum sinks per logger
    pub const maxSinks: usize = 64;
    /// Maximum custom levels per logger
    pub const maxCustomLevels: usize = 32;
};
```

## Metrics Constants

Metrics-related constants.

```zig
pub const MetricsConstants = struct {
    /// Default histogram bucket boundaries in nanoseconds
    pub const histogramBoundaries = []u64{
        1_000, 2_000, 5_000, 10_000, 20_000, 50_000, 100_000, 200_000, 500_000,
        1_000_000, 2_000_000, 5_000_000, 10_000_000, 20_000_000, 50_000_000, 100_000_000, 200_000_000, 500_000_000,
        1_000_000_000, std.math.maxInt(u64),
    };

    /// Uppercase log level names for metrics display
    pub const levelNames = [][]const u8{
        "TRACE", "DEBUG", "INFO", "NOTICE", "SUCCESS", "WARNING", "ERROR", "FAIL", "CRITICAL", "FATAL",
    };
};
```

## Rotation Constants

Default file rotation settings.

```zig
pub const RotationConstants = struct {
    /// Default max file size before rotation (10MB)
    pub const defaultMaxSize: u64 = 10 * 1024 * 1024;
    /// Default max number of backup files
    pub const defaultMaxFiles: usize = 5;
    /// Default compressed file extension
    pub const compressedExt: []const u8 = ".gz";
};
```

## Network Constants

Default network logging settings.

```zig
pub const NetworkConstants = struct {
    /// Default TCP buffer size (8KB)
    pub const tcpBufferSize: usize = 8192;
    /// Default UDP max packet size (64KB)
    pub const udpMaxPacket: usize = 65507;
    /// Connect timeout (5s)
    pub const connectTimeoutMs: u64 = 5000;
    /// Send timeout (1s)
    pub const sendTimeoutMs: u64 = 1000;
};
```

## Invoke Constants

Invoke system limits for triggers and messages.

```zig
pub const InvokeConstants = struct {
    /// Maximum number of triggers allowed by default.
    pub const defaultMaxRules: usize = 1000;
    /// Maximum messages per trigger allowed by default.
    pub const defaultMaxMessages: usize = 10;
};
```

## Syslog Constants

Syslog constants for RFC 5424 compliance.

```zig
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
        pub fn fromLogLevel(level: @import("level.zig").Level) Severity;
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

    /// Default syslog UDP port
    pub const defaultPort: u16 = 514;
};
```

## Compression Constants

Compression algorithm constants.

```zig
pub const CompressionConstants = struct {
    /// Window size for fast compression
    pub const windowFast: usize = 256;
    /// Window size for default compression
    pub const windowDefault: usize = 1024;
    /// Window size for best compression
    pub const windowBest: usize = 4096;
    /// Minimum match length
    pub const minMatch: usize = 3;
    /// Maximum match length
    pub const maxMatch: usize = 255;
    /// Maximum run length for RLE
    pub const maxRunLength: usize = 127;
    /// LZMA dictionary size
    pub const lzmaDictSize: u32 = 65536;
    /// LZMA maximum offset
    pub const lzmaMaxOffset: usize = 65535;
    /// LZMA hash bits
    pub const lzmaHashBits: u5 = 14;
    /// LZMA maximum match length
    pub const lzmaMaxMatch: usize = 272;
    /// LZMA2 chunk size
    pub const lzma2ChunkSize: usize = 32768;

    /// Magic bytes for various formats
    pub const Magic = struct {
        pub const lzma = "\x5D\x00\x00\x80\x00";
        pub const xz = "\xFD\x37\x7A\x58\x5A\x00";
        pub const gzip = "\x1F\x8B";
        pub const zlib = "\x78\x9C";
        pub const logly = "LGZ";
    };

    /// LZMA properties
    pub const lzmaPropertiesByte: u8 = (2 * 5 + 0) * 9 + 3;

    /// RLE Markers
    pub const Rle = struct {
        pub const marker: u8 = 0xFE;
        pub const escape: u8 = 0xFD;
    };

    /// File extensions for different compression algorithms
    pub const ArchivingExtensions = struct {
        pub const gzip = RotationConstants.compressedExt;
        pub const zstd = ".zst";
        pub const lzma = ".lzma";
        pub const lzma2 = ".lzma2";
        pub const xz = ".xz";
        pub const tarGz = ".tar.gz";
        pub const zip = ".zip";
        pub const lz4 = ".lz4";
        pub const none = "";
    };
};
```

## Event Log Constants (Windows)

Windows Event Log constants.

```zig
pub const EventLogConstants = struct {
    pub const success: u16 = 0x0000;
    pub const errorType: u16 = 0x0001;
    pub const warningType: u16 = 0x0002;
    pub const informationType: u16 = 0x0004;
};
```

## Scheduler Defaults

Scheduler defaults.

```zig
pub const SchedulerDefaults = struct {
    /// Default retry interval in milliseconds
    pub const retryIntervalMs: u32 = 5000;
    /// Default cleanup max age in seconds
    pub const maxAgeSeconds: u64 = 7 * TimeConstants.secondsPerDay;
    /// Cron fallback interval in milliseconds
    pub const cronFallbackIntervalMs: i64 = @as(i64, TimeConstants.secondsPerMinute * TimeConstants.msPerSecond);
};
```

## Rotation Defaults

Rotation default settings.

```zig
pub const RotationDefaults = struct {
    /// Default retention count
    pub const retentionCount: usize = 10;
};
```

## Config Defaults

General configuration defaults.

```zig
pub const ConfigDefaults = struct {
    /// Default stack size for stack trace capturing (1MB)
    pub const stackSize: usize = 1024 * 1024;
};
```

## Redaction Defaults

Redaction defaults.

```zig
pub const RedactionDefaults = struct {
    /// Default characters to reveal at start
    pub const partialStartChars: u8 = 4;
    /// Default characters to reveal at end
    pub const partialEndChars: u8 = 4;
    /// Default mask character
    pub const maskChar: u8 = '*';
};
```

## Rate Limit Defaults

Rate limiting defaults.

```zig
pub const RateLimitDefaults = struct {
    /// Default max requests per second
    pub const maxPerSecond: u32 = 1000;
    /// Default burst size
    pub const burstSize: u32 = 100;
};
```

## Sampling Defaults

Sampling defaults.

```zig
pub const SamplingDefaults = struct {
    /// Default rate limit window in milliseconds
    pub const rateLimitWindowMs: u64 = 1000;
    /// Default adaptive adjustment interval in milliseconds
    pub const adaptiveAdjustmentIntervalMs: u64 = 1000;
    /// Default minimum adaptive sample rate
    pub const adaptiveMinRate: f64 = 0.01;
    /// Default maximum adaptive sample rate
    pub const adaptiveMaxRate: f64 = 1.0;
};
```

## Parallel Defaults

Parallel sink writing defaults.

```zig
pub const ParallelDefaults = struct {
    /// Default maximum concurrent writes
    pub const maxConcurrent: usize = 8;
    /// High throughput maximum concurrent writes
    pub const highThroughputMaxConcurrent: usize = 16;
    /// Default buffer size
    pub const bufferSize: usize = 64;
    /// High throughput buffer size
    pub const highThroughputBufferSize: usize = 128;
    /// Default maximum retries
    pub const maxRetries: u3 = 3;
    /// Default write timeout in milliseconds
    pub const writeTimeoutMs: u64 = 5000;
};
```

## Sink Defaults

Sink configuration defaults.

```zig
pub const SinkDefaults = struct {
    /// Default max buffer records
    pub const maxBufferRecords: usize = 1000;
    /// Default flush interval in milliseconds
    pub const flushIntervalMs: u64 = 1000;
};
```

## Colors (tint.zig)

Terminal colors are provided by tint.zig via `logly.Color`.
See the [Colors guide](../guide/colors.md) for full details.

```zig
const tint = logly.Color.Tint;

// Named colors.
const red = tint.color.ansi4.red;
const brightRed = tint.color.ansi4.brightRed;

// 256-color and RGB.
const orange = tint.color.ansi256.index(208);
const coral = tint.color.rgb(255, 127, 80);

// Render to an escape sequence.
const seq = logly.Color.sequence(red, .trueColor);
// seq.slice() gives "\\x1b[31m".

// Parse names, hex, or SGR params.
const magenta = logly.Color.parse("magenta").?;
```

## Example Usage

```zig
const Constants = @import("logly").Constants;

// Use platform-appropriate atomic type
var counter = std.atomic.Value(Constants.AtomicUnsigned).init(0);
 _ = counter.fetchAdd(1, .monotonic);

// Get recommended thread count
const threads = Constants.ThreadDefaults.recommendedThreadCount();

// Use buffer size constants
var buffer: [Constants.BufferSizes.message]u8 = undefined;

// Time conversion
const ms = timestamp / Constants.TimeConstants.msPerSecond;

// Color usage
const red_text = Constants.Colors.Fg.red;           // "31"
const orange = Constants.Colors.fg256(208);         // "38;5;208"
const traceColor = Constants.Colors.Themes.neon.trace;  // "38;5;51"
```

## See Also

- [Config API](config.md) - Configuration options
- [Thread Pool API](thread-pool.md) - Thread pool configuration
- [Invoke API](invoke.md) - Invoke system configuration
