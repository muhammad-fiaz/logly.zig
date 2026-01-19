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
/// Architecture-dependent unsigned atomic integer type (u64 on 64-bit, u32 on 32-bit)
pub const AtomicUnsigned = switch (builtin.target.cpu.arch) {
    .x86_64 => u64,
    .aarch64 => u64,
    .riscv64 => u64,
    .powerpc64 => u64,
    .x86 => u32,
    .arm => u32,
    else => u32,
};

/// Architecture-dependent signed atomic integer type (i64 on 64-bit, i32 on 32-bit)
pub const AtomicSigned = switch (builtin.target.cpu.arch) {
    .x86_64 => i64,
    .aarch64 => i64,
    .riscv64 => i64,
    .powerpc64 => i64,
    .x86 => i32,
    .arm => i32,
    else => i32,
};

/// Native pointer-sized unsigned integer for the target architecture
pub const NativeUint = switch (builtin.target.cpu.arch) {
    .x86_64 => u64,
    .aarch64 => u64,
    .riscv64 => u64,
    .powerpc64 => u64,
    else => u32,
};

/// Native pointer-sized signed integer for the target architecture
pub const NativeInt = switch (builtin.target.cpu.arch) {
    .x86_64 => i64,
    .aarch64 => i64,
    .riscv64 => i64,
    .powerpc64 => i64,
    else => i32,
};
```

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
    pub const async_queue: usize = 8192;
    /// Default compression buffer size
    pub const compression: usize = 32768;
    /// Default telemetry buffer size
    pub const telemetry: usize = 4096;
    /// Maximum log message size (1MB)
    pub const max_message: usize = 1024 * 1024;
    /// Async batch size
    pub const async_batch: usize = 64;
    /// Small buffer for thread IDs etc.
    pub const tiny: usize = 32;
    /// Small buffer for context values etc.
    pub const small: usize = 256;
    /// Standard file read buffer
    pub const file_read: usize = 4096;
    /// Large file read buffer
    pub const file_read_large: usize = 8192;
    /// Path buffer size
    pub const path_buffer: usize = 512;
};
```

## Thread Defaults

Default thread pool settings and helpers.

```zig
pub const ThreadDefaults = struct {
    /// Default number of threads (0 = auto-detect)
    pub const thread_count: usize = 0;
    /// Default queue size per thread
    pub const queue_size: usize = 1024;
    /// Default stack size for worker threads (1MB)
    pub const stack_size: usize = 1024 * 1024;
    /// Default wait timeout in nanoseconds
    pub const wait_timeout_ns: u64 = 100 * TimeConstants.ns_per_ms;
    /// Maximum concurrent tasks
    pub const max_tasks: usize = 10000;
    /// Queue size for low resource environments
    pub const queue_size_low: usize = 128;

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
    pub const min_priority: u8 = 5;
    /// Maximum priority value (FATAL)
    pub const max_priority: u8 = 55;
    /// Default level priority (INFO)
    pub const default_priority: u8 = 20;
};
```

## Time Constants

Time conversion and default intervals.

```zig
pub const TimeConstants = struct {
    /// Milliseconds per second
    pub const ms_per_second: u64 = 1000;
    /// Microseconds per second
    pub const us_per_second: u64 = 1_000_000;
    /// Nanoseconds per second
    pub const ns_per_second: u64 = 1_000_000_000;

    /// Seconds-based helpers for interval reuse
    pub const seconds_per_minute: u64 = 60;
    pub const seconds_per_hour: u64 = seconds_per_minute * 60;
    pub const seconds_per_day: u64 = seconds_per_hour * 24;
    pub const seconds_per_week: u64 = seconds_per_day * 7;
    pub const seconds_per_month: u64 = seconds_per_day * 30;
    pub const seconds_per_year: u64 = seconds_per_day * 365;

    /// Derived conversions
    pub const us_per_ms: u64 = us_per_second / ms_per_second;
    pub const ns_per_ms: u64 = ns_per_second / ms_per_second;
    pub const ns_per_us: u64 = ns_per_second / us_per_second;

    /// Default flush interval in milliseconds
    pub const default_flush_interval_ms: u64 = TimeDefaults.flush_interval_ms;
    /// Default rotation check interval in milliseconds
    pub const rotation_check_interval_ms: u64 = seconds_per_minute * ms_per_second;
};
```

## Time Defaults

Default time intervals and timeouts.

```zig
pub const TimeDefaults = struct {
    /// Default flush interval in milliseconds
    pub const flush_interval_ms: u64 = 1000;
    /// Default async write timeout in milliseconds
    pub const write_timeout_ms: u64 = 5000;
    /// Default connection timeout in milliseconds
    pub const connection_timeout_ms: u64 = 10000;
    /// Default retry delay in milliseconds
    pub const retry_delay_ms: u64 = 100;
    /// Maximum retry attempts for network operations
    pub const max_retries: u32 = 3;
};
```

## Telemetry Defaults

OpenTelemetry configuration defaults (used by `TelemetryConfig`).

```zig
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
};
```

## Async Constants

Async configuration constants.

```zig
pub const AsyncConstants = struct {
    /// Sleep duration when blocking on full queue
    pub const block_sleep_ns: u64 = 1 * TimeConstants.ns_per_ms;
    /// Default batch size for async processing
    pub const batch_size: usize = BufferSizes.async_batch;
};
```

## Limits

Default limits for queues and buffers.

```zig
pub const Limits = struct {
    /// Maximum async queue size
    pub const max_async_queue_size: usize = 10000;
    /// Maximum pending log records
    pub const max_pending_records: usize = 50000;
    /// Maximum sinks per logger
    pub const max_sinks: usize = 64;
    /// Maximum custom levels per logger
    pub const max_custom_levels: usize = 32;
};
```

## Metrics Constants

Metrics-related constants.

```zig
pub const MetricsConstants = struct {
    /// Default histogram bucket boundaries in nanoseconds
    pub const histogram_boundaries = [_]u64{
        1_000, 2_000, 5_000, 10_000, 20_000, 50_000, 100_000, 200_000, 500_000,
        1_000_000, 2_000_000, 5_000_000, 10_000_000, 20_000_000, 50_000_000, 100_000_000, 200_000_000, 500_000_000,
        1_000_000_000, std.math.maxInt(u64),
    };

    /// Uppercase log level names for metrics display
    pub const level_names = [_][]const u8{
        "TRACE", "DEBUG", "INFO", "NOTICE", "SUCCESS", "WARNING", "ERROR", "FAIL", "CRITICAL", "FATAL",
    };
};
```

## Rotation Constants

Default file rotation settings.

```zig
pub const RotationConstants = struct {
    /// Default max file size before rotation (10MB)
    pub const default_max_size: u64 = 10 * 1024 * 1024;
    /// Default max number of backup files
    pub const default_max_files: usize = 5;
    /// Default compressed file extension
    pub const compressed_ext: []const u8 = ".gz";
};
```

## Network Constants

Default network logging settings.

```zig
pub const NetworkConstants = struct {
    /// Default TCP buffer size (8KB)
    pub const tcp_buffer_size: usize = 8192;
    /// Default UDP max packet size (64KB)
    pub const udp_max_packet: usize = 65507;
    /// Connect timeout (5s)
    pub const connect_timeout_ms: u64 = 5000;
    /// Send timeout (1s)
    pub const send_timeout_ms: u64 = 1000;
};
```

## Rules Constants

Rules system constants for diagnostic message formatting.

```zig
pub const RulesConstants = struct {
    /// Default indentation for rule messages
    pub const default_indent: []const u8 = "    ";
    /// Default prefix character for rule messages
    pub const default_prefix: []const u8 = "↳";
    /// Default prefix character for ASCII mode
    pub const default_prefix_ascii: []const u8 = "|--";
    /// Maximum number of rules allowed by default
    pub const default_max_rules: usize = 1000;
    /// Maximum messages per rule allowed by default
    pub const default_max_messages: usize = 10;

    /// Unicode prefixes for each message category
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

    /// ASCII-only prefixes for each message category
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

    /// Customizable symbols for rule message categories
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

    /// ANSI color codes for each message category
    pub const Colors = struct {
        pub const cause: []const u8 = "91;1";
        pub const fix: []const u8 = "96;1";
        pub const suggest: []const u8 = "93;1";
        pub const action: []const u8 = "91;1";
        pub const docs: []const u8 = "35";
        pub const report: []const u8 = "33";
        pub const note: []const u8 = "37";
        pub const caution: []const u8 = "33";
        pub const perf: []const u8 = "36";
        pub const security: []const u8 = "95;1";
        pub const custom: []const u8 = "37";
    };
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
    pub const default_port: u16 = 514;
};
```

## Compression Constants

Compression algorithm constants.

```zig
pub const CompressionConstants = struct {
    /// Window size for fast compression
    pub const window_fast: usize = 256;
    /// Window size for default compression
    pub const window_default: usize = 1024;
    /// Window size for best compression
    pub const window_best: usize = 4096;
    /// Minimum match length
    pub const min_match: usize = 3;
    /// Maximum match length
    pub const max_match: usize = 255;
    /// Maximum run length for RLE
    pub const max_run_length: usize = 127;
    /// LZMA dictionary size
    pub const lzma_dict_size: u32 = 65536;
    /// LZMA maximum offset
    pub const lzma_max_offset: usize = 65535;
    /// LZMA hash bits
    pub const lzma_hash_bits: u5 = 14;
    /// LZMA maximum match length
    pub const lzma_max_match: usize = 272;
    /// LZMA2 chunk size
    pub const lzma2_chunk_size: usize = 32768;

    /// Magic bytes for various formats
    pub const Magic = struct {
        pub const lzma = "\x5D\x00\x00\x80\x00";
        pub const xz = "\xFD\x37\x7A\x58\x5A\x00";
        pub const gzip = "\x1F\x8B";
        pub const zlib = "\x78\x9C";
        pub const logly = "LGZ";
    };

    /// LZMA properties
    pub const lzma_properties_byte: u8 = (2 * 5 + 0) * 9 + 3;

    /// RLE Markers
    pub const Rle = struct {
        pub const marker: u8 = 0xFE;
        pub const escape: u8 = 0xFD;
    };

    /// File extensions for different compression algorithms
    pub const ArchivingExtensions = struct {
        pub const gzip = RotationConstants.compressed_ext;
        pub const zstd = ".zst";
        pub const lzma = ".lzma";
        pub const lzma2 = ".lzma2";
        pub const xz = ".xz";
        pub const tar_gz = ".tar.gz";
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
    pub const error_type: u16 = 0x0001;
    pub const warning_type: u16 = 0x0002;
    pub const information_type: u16 = 0x0004;
};
```

## Scheduler Defaults

Scheduler defaults.

```zig
pub const SchedulerDefaults = struct {
    /// Default retry interval in milliseconds
    pub const retry_interval_ms: u32 = 5000;
    /// Default cleanup max age in seconds
    pub const max_age_seconds: u64 = 7 * TimeConstants.seconds_per_day;
    /// Cron fallback interval in milliseconds
    pub const cron_fallback_interval_ms: i64 = @as(i64, TimeConstants.seconds_per_minute * TimeConstants.ms_per_second);
};
```

## Rotation Defaults

Rotation default settings.

```zig
pub const RotationDefaults = struct {
    /// Default retention count
    pub const retention_count: usize = 10;
};
```

## Config Defaults

General configuration defaults.

```zig
pub const ConfigDefaults = struct {
    /// Default stack size for stack trace capturing (1MB)
    pub const stack_size: usize = 1024 * 1024;
    /// Default arena reset threshold (64KB)
    pub const arena_reset_threshold: usize = 64 * 1024;
};
```

## Redaction Defaults

Redaction defaults.

```zig
pub const RedactionDefaults = struct {
    /// Default characters to reveal at start
    pub const partial_start_chars: u8 = 4;
    /// Default characters to reveal at end
    pub const partial_end_chars: u8 = 4;
    /// Default mask character
    pub const mask_char: u8 = '*';
};
```

## Rate Limit Defaults

Rate limiting defaults.

```zig
pub const RateLimitDefaults = struct {
    /// Default max requests per second
    pub const max_per_second: u32 = 1000;
    /// Default burst size
    pub const burst_size: u32 = 100;
};
```

## Sampling Defaults

Sampling defaults.

```zig
pub const SamplingDefaults = struct {
    /// Default rate limit window in milliseconds
    pub const rate_limit_window_ms: u64 = 1000;
    /// Default adaptive adjustment interval in milliseconds
    pub const adaptive_adjustment_interval_ms: u64 = 1000;
    /// Default minimum adaptive sample rate
    pub const adaptive_min_rate: f64 = 0.01;
    /// Default maximum adaptive sample rate
    pub const adaptive_max_rate: f64 = 1.0;
};
```

## Parallel Defaults

Parallel sink writing defaults.

```zig
pub const ParallelDefaults = struct {
    /// Default maximum concurrent writes
    pub const max_concurrent: usize = 8;
    /// High throughput maximum concurrent writes
    pub const high_throughput_max_concurrent: usize = 16;
    /// Default buffer size
    pub const buffer_size: usize = 64;
    /// High throughput buffer size
    pub const high_throughput_buffer_size: usize = 128;
    /// Default maximum retries
    pub const max_retries: u3 = 3;
    /// Default write timeout in milliseconds
    pub const write_timeout_ms: u64 = 5000;
};
```

## Sink Defaults

Sink configuration defaults.

```zig
pub const SinkDefaults = struct {
    /// Default max buffer records
    pub const max_buffer_records: usize = 1000;
    /// Default flush interval in milliseconds
    pub const flush_interval_ms: u64 = 1000;
};
```

## Colors Constants (v0.1.5)

Comprehensive color system with ANSI codes, 256-color, and RGB support.

```zig
pub const Colors = struct {
    /// Standard foreground colors (30-37)
    pub const Fg = struct {
        pub const black: []const u8 = "30";
        pub const red: []const u8 = "31";
        pub const green: []const u8 = "32";
        pub const yellow: []const u8 = "33";
        pub const blue: []const u8 = "34";
        pub const magenta: []const u8 = "35";
        pub const cyan: []const u8 = "36";
        pub const white: []const u8 = "37";
    };

    /// Bright foreground colors (90-97)
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

    /// Standard background colors (40-47)
    pub const Bg = struct {
        pub const black: []const u8 = "40";
        pub const red: []const u8 = "41";
        pub const green: []const u8 = "42";
        pub const yellow: []const u8 = "43";
        pub const blue: []const u8 = "44";
        pub const magenta: []const u8 = "45";
        pub const cyan: []const u8 = "46";
        pub const white: []const u8 = "47";
    };

    /// Bright background colors (100-107)
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

    /// Text style modifiers
    pub const Style = struct {
        pub const reset: []const u8 = "0";
        pub const bold: []const u8 = "1";
        pub const dim: []const u8 = "2";
        pub const italic: []const u8 = "3";
        pub const underline: []const u8 = "4";
        pub const blink: []const u8 = "5";
        pub const rapid_blink: []const u8 = "6";
        pub const reverse: []const u8 = "7";
        pub const hidden: []const u8 = "8";
        pub const strikethrough: []const u8 = "9";
    };

    /// Reset all formatting
    pub const reset: []const u8 = "0";

    /// Basic foreground colors (30-37)
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

    /// Bright foreground colors (90-97)
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

    /// Background colors (40-47)
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

    /// Bright background colors (100-107)
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

    /// Text styles
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

    /// Generate 256-color foreground code (0-255)
    pub fn fg256(color_index: u8) []const u8;

    /// Generate 256-color background code (0-255)
    pub fn bg256(color_index: u8) []const u8;

    /// Generate RGB foreground color code
    pub fn fgRgb(r: u8, g: u8, b: u8) []const u8;

    /// Generate RGB background color code
    pub fn bgRgb(r: u8, g: u8, b: u8) []const u8;

    /// Combine multiple codes
    pub fn combine(comptime codes: anytype) []const u8;

    /// Predefined log level colors
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

    /// Predefined theme presets
    pub const Themes = struct {
        /// Default theme with standard colors
        pub const default_theme = LevelColors;

        /// Bright theme with bold colors
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

        /// Dim theme with subtle colors
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

        /// Underlined theme for highlighted levels
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

        /// Minimal theme with subtle colors
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

        /// Neon theme with vivid 256-colors
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

        /// Pastel theme with soft colors
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

        /// Dark theme optimized for dark terminals
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

        /// Light theme optimized for light terminals
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
```

### Using Colors

```zig
const Colors = logly.Constants.Colors;

// Basic colors
const red_text = Colors.Fg.red;           // "31"
const bright_red = Colors.BrightFg.red;   // "91"

// With background
const on_red = Colors.Bg.red;             // "41"
const white_on_red = "97;41";             // Combined

// With styles
const bold = Colors.Style.bold;           // "1"
const underline = Colors.Style.underline; // "4"
const bold_red = "31;1";                  // Combined

// 256-color palette
const orange = Colors.fg256(208);         // "38;5;208"
const purple_bg = Colors.bg256(141);      // "48;5;141"

// RGB colors
const coral = Colors.fgRgb(255, 127, 80); // "38;2;255;127;80"

/// Theme colors
const trace_color = Colors.Themes.default_theme.trace;  // "36"
const neon_trace = Colors.Themes.neon.trace;      // "38;5;51"
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
const ms = timestamp / Constants.TimeConstants.ms_per_second;

// Color usage
const red_text = Constants.Colors.Fg.red;           // "31"
const orange = Constants.Colors.fg256(208);         // "38;5;208"
const trace_color = Constants.Colors.Themes.neon.trace;  // "38;5;51"
```

## See Also

- [Config API](config.md) - Configuration options
- [Thread Pool API](thread-pool.md) - Thread pool configuration
- [Rules API](rules.md) - Rules system configuration
