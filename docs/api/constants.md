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
/// Unsigned atomic integer (u64 on 64-bit, u32 on 32-bit)
pub const AtomicUnsigned = ...;

/// Signed atomic integer (i64 on 64-bit, i32 on 32-bit)
pub const AtomicSigned = ...;

/// Native pointer-sized unsigned integer
pub const NativeUint = ...;

/// Native pointer-sized signed integer
pub const NativeInt = ...;
```

## Buffer Sizes

Default buffer sizes for various operations.

```zig
pub const BufferSizes = struct {
    /// Default log message buffer size (4KB)
    pub const message: usize = 4096;
    /// Default format buffer size (8KB)
    pub const format: usize = 8192;
    /// Default sink buffer size (16KB)
    pub const sink: usize = 16384;
    /// Default async queue buffer size (8KB)
    pub const async_queue: usize = 8192;
    /// Default compression buffer size (32KB)
    pub const compression: usize = 32768;
    /// Maximum log message size (1MB)
    pub const max_message: usize = 1024 * 1024;
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
    /// Default wait timeout (100ms)
    pub const wait_timeout_ns: u64 = 100 * std.time.ns_per_ms;
    /// Maximum concurrent tasks
    pub const max_tasks: usize = 10000;

    /// Recommended thread count for general use
    pub fn recommendedThreadCount() usize;
    /// Recommended thread count for I/O bound workloads
    pub fn ioBoundThreadCount() usize;
    /// Recommended thread count for CPU bound workloads
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
    pub const ms_per_second: u64 = 1000;
    pub const us_per_second: u64 = 1_000_000;
    pub const ns_per_second: u64 = 1_000_000_000;
    /// Default flush interval (100ms)
    pub const default_flush_interval_ms: u64 = 100;
    /// Default rotation check interval (1 min)
    pub const rotation_check_interval_ms: u64 = 60_000;
};
```

## Rotation Constants

Default file rotation settings.

```zig
pub const RotationConstants = struct {
    /// Default max file size (10MB)
    pub const default_max_size: u64 = 10 * 1024 * 1024;
    /// Default max backup files (5)
    pub const default_max_files: usize = 5;
    /// Default compressed extension (.gz)
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

Rules system configuration values.

```zig
pub const RulesConstants = struct {
    /// Default indentation for rule messages
    pub const default_indent: []const u8 = "    ";
    /// Unicode prefix character
    pub const default_prefix: []const u8 = "↳";
    /// ASCII prefix character
    pub const default_prefix_ascii: []const u8 = "|--";
    /// Maximum number of rules allowed
    pub const default_max_rules: usize = 1000;
    /// Maximum messages per rule
    pub const default_max_messages: usize = 10;

    /// Unicode prefixes for message categories
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

    /// ASCII prefixes for message categories
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

    /// ANSI color codes for message categories
    pub const Colors = struct {
        pub const cause: []const u8 = "91;1";    // Bright red
        pub const fix: []const u8 = "96;1";      // Bright cyan
        pub const suggest: []const u8 = "93;1";  // Bright yellow
        pub const action: []const u8 = "91;1";   // Bold red
        pub const docs: []const u8 = "35";       // Magenta
        pub const report: []const u8 = "33";     // Yellow
        pub const note: []const u8 = "37";       // White
        pub const caution: []const u8 = "33";    // Yellow
        pub const perf: []const u8 = "36";       // Cyan
        pub const security: []const u8 = "95;1"; // Bright magenta
        pub const custom: []const u8 = "37";     // White
    };
};
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
```

## See Also

- [Config API](config.md) - Configuration options
- [Thread Pool API](thread-pool.md) - Thread pool configuration
- [Rules API](rules.md) - Rules system configuration
