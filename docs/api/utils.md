---
title: Utils API Reference
description: API reference for Logly.zig Utils module. Size parsing, duration parsing, time utilities, and date formatting functions.
head:
  - - meta
    - name: keywords
      content: utils api, size parsing, duration parsing, time utilities, date formatting
  - - meta
    - property: og:title
      content: Utils API Reference | Logly.zig
---

# Utils API

The Utils module provides consolidated utility functions for size parsing, duration parsing, time manipulation, and date formatting.

## Overview

```zig
const logly = @import("logly");
const Utils = logly.Utils;

// Parse size strings
const bytes = Utils.parseSize("10MB"); // 10485760

// Parse duration strings
const ms = Utils.parseDuration("5m"); // 300000

// Time utilities
const tc = Utils.nowComponents();
std.debug.print("Year: {d}\n", .{tc.year});

// Date formatting
var buf: [32]u8 = undefined;
const date = try Utils.formatIsoDate(&buf, tc);
```

## Quick Reference: Method Aliases

| Full Method           | Alias(es)       | Description              |
|-----------------------|-----------------|--------------------------|
| `formatDatePattern()` | `format()`      | Format date with pattern |
| `formatDateToBuf()`   | `formatToBuf()` | Format date to buffer    |

## Size Parsing

### parseSize

Parses a size string into bytes.

```zig
pub fn parseSize(s: []const u8) ?u64
```

**Supported units (case insensitive):**

- `B` - Bytes
- `K`, `KB` - Kilobytes (×1024)
- `M`, `MB` - Megabytes (×1024²)
- `G`, `GB` - Gigabytes (×1024³)
- `T`, `TB` - Terabytes (×1024⁴)

**Examples:**

```zig
Utils.parseSize("1024")     // 1024
Utils.parseSize("10KB")     // 10240
Utils.parseSize("5 MB")     // 5242880 (whitespace allowed)
Utils.parseSize("1GB")      // 1073741824
```

### formatSize

Formats a byte size into a human-readable string.

```zig
pub fn formatSize(allocator: std.mem.Allocator, bytes: u64) ![]u8
```

**Example:**

```zig
const str = try Utils.formatSize(allocator, 5242880);
defer allocator.free(str);
// str = "5.00 MB"
```

## Duration Parsing

### parseDuration

Parses a duration string into milliseconds.

```zig
pub fn parseDuration(s: []const u8) ?i64
```

**Supported units (case insensitive):**

- `ms` - Milliseconds
- `s` - Seconds (×1000)
- `m` - Minutes (×60000)
- `h` - Hours (×3600000)
- `d` - Days (×86400000)

**Examples:**

```zig
Utils.parseDuration("1000ms") // 1000
Utils.parseDuration("30s")    // 30000
Utils.parseDuration("5m")     // 300000
Utils.parseDuration("2h")     // 7200000
Utils.parseDuration("1d")     // 86400000
```

### formatDuration

Formats milliseconds into a human-readable string.

```zig
pub fn formatDuration(allocator: std.mem.Allocator, ms: i64) ![]u8
```

## Time Utilities

### TimeComponents

Structure containing extracted time components.

```zig
pub const TimeComponents = struct {
    year: i32,
    month: u8,      // 1-12
    day: u8,        // 1-31
    hour: u64,      // 0-23
    minute: u64,    // 0-59
    second: u64,    // 0-59
};
```

### fromEpochSeconds

Extracts time components from a Unix timestamp (seconds).

```zig
pub fn fromEpochSeconds(timestamp: i64) TimeComponents
```

### fromMilliTimestamp

Extracts time components from a millisecond timestamp.

```zig
pub fn fromMilliTimestamp(timestamp: i64) TimeComponents
```

### fromMilliTimestampLocal

Extracts local-time components from a millisecond timestamp.

```zig
pub fn fromMilliTimestampLocal(timestamp: i64) TimeComponents
```

### localUtcOffsetMinutes

Returns local UTC offset (in minutes) for a millisecond timestamp.
The result is bounded to `Constants.TimeConstants.min_utc_offset_minutes` through `Constants.TimeConstants.max_utc_offset_minutes`.

```zig
pub fn localUtcOffsetMinutes(timestamp: i64) i16
```

### writeUtcOffset

Writes a UTC offset in `+HH:MM`/`-HH:MM` form.

```zig
pub fn writeUtcOffset(writer: anytype, offset_minutes: i16) !void
```

### writeUtcOffsetCompact

Writes a compact UTC offset in `+HHMM`/`-HHMM` form.

```zig
pub fn writeUtcOffsetCompact(writer: anytype, offset_minutes: i16) !void
```

### nowComponents

Gets current time components.

```zig
pub fn nowComponents() TimeComponents
```

### currentSeconds

Returns current Unix timestamp in seconds.

```zig
pub fn currentSeconds() i64
```

### currentMillis

Returns current timestamp in milliseconds.

```zig
pub fn currentMillis() i64
```

### currentNanos

Returns current timestamp in nanoseconds.

```zig
pub fn currentNanos() i128
```

### isSameDay

Checks if two timestamps are on the same day.

```zig
pub fn isSameDay(ts1: i64, ts2: i64) bool
```

### isSameHour

Checks if two timestamps are in the same hour.

```zig
pub fn isSameHour(ts1: i64, ts2: i64) bool
```

### startOfDay

Returns the start of the day (midnight) as epoch seconds.

```zig
pub fn startOfDay(timestamp: i64) i64
```

### startOfHour

Returns the start of the hour as epoch seconds.

```zig
pub fn startOfHour(timestamp: i64) i64
```

### elapsedMs

Calculates elapsed time in milliseconds since start_time.

```zig
pub fn elapsedMs(start_time: i64) u64
```

### elapsedSeconds

Calculates elapsed time in seconds since start_time.

```zig
pub fn elapsedSeconds(start_time: i64) u64
```

### durationSinceNs

Calculates duration in nanoseconds since a start time.

```zig
pub fn durationSinceNs(start_time: i128) u64
```

## Math & Rate Utilities

### calculateRate

Calculates a rate (0.0 to 1.0) given a numerator and denominator.

```zig
pub fn calculateRate(numerator: u64, denominator: u64) f64
```

### calculateErrorRate

Calculates error rate (0.0 to 1.0) given error count and total count.

```zig
pub fn calculateErrorRate(errors: u64, total: u64) f64
```

### calculateAverage

Calculates average value given a sum and count.

```zig
pub fn calculateAverage(sum: u64, count: u64) f64
```

### calculateThroughput

Calculates throughput (items/sec) given a count and duration in nanoseconds.

```zig
pub fn calculateThroughput(count: u64, elapsed_ns: u64) f64
```

### calculateBytesPerSecond

Calculates bytes per second given bytes and duration in milliseconds.

```zig
pub fn calculateBytesPerSecond(bytes: u64, elapsed_ms: i64) f64
```

### calculateCRC32

Calculates CRC32 checksum of data.

```zig
pub fn calculateCRC32(data: []const u8) u32
```

### lzmaHash

Calculates LZMA hash for match finding.

```zig
pub fn lzmaHash(data: []const u8, len: usize) u14
```

### getCompressionExtension

Returns the canonical file extension for a given compression algorithm. Useful when generating archive or compressed file names consistently across rotation, scheduler, and compression utilities.

```zig
pub fn getCompressionExtension(algo: anytype) []const u8
```

Example:

```zig
const ext = Utils.getCompressionExtension(CompressionAlgorithm.zstd); // ".zst"
```

Note: Returns an empty string for `.none`.

## Trace Context Utilities

### TraceparentContext

Parsed W3C trace context fields returned by `parseTraceparentHeader`.

```zig
pub const TraceparentContext = struct {
    version: []const u8,
    trace_id: []const u8,
    span_id: []const u8,
    flags: []const u8,
    sampled: bool,
};
```

### TraceparentError

Errors returned by `formatTraceparentHeader` validation.

```zig
pub const TraceparentError = error{
    InvalidTraceId,
    InvalidSpanId,
};
```

### parseTraceparentHeader

Parses a W3C `traceparent` header.

Expected format: `00-<32_hex_trace_id>-<16_hex_span_id>-<2_hex_flags>`.

```zig
pub fn parseTraceparentHeader(header: []const u8) ?TraceparentContext
```

Returns `null` for malformed headers, invalid hex values, or all-zero trace/span IDs.

### formatTraceparentHeader

Formats a W3C `traceparent` header string from validated IDs.

```zig
pub fn formatTraceparentHeader(
    allocator: std.mem.Allocator,
    trace_id: []const u8,
    span_id: []const u8,
    sampled: bool
) ![]u8
```

Returns:

- `TraceparentError.InvalidTraceId` when `trace_id` is invalid.
- `TraceparentError.InvalidSpanId` when `span_id` is invalid.

Example:

```zig
const traceparent = try Utils.formatTraceparentHeader(
    allocator,
    "4bf92f3577b34da6a3ce929d0e0e4736",
    "00f067aa0ba902b7",
    true,
);
defer allocator.free(traceparent);
```

## Date Formatting

### formatDatePattern

Formats a date/time using a custom pattern.

```zig
pub fn formatDatePattern(
    writer: anytype,
    fmt: []const u8,
    year: i32,
    month: u8,
    day: u8,
    hour: u64,
    minute: u64,
    second: u64,
    millis: u64
) !void
```

### formatDatePatternWithOffset

Formats a date/time pattern and enables timezone tokens (`ZZZ`, `ZZ`).

```zig
pub fn formatDatePatternWithOffset(
    writer: anytype,
    fmt: []const u8,
    year: i32,
    month: u8,
    day: u8,
    hour: u64,
    minute: u64,
    second: u64,
    millis: u64,
    timezone_offset_minutes: i16
) !void
```

**Supported tokens:**

| Token | Description            |
|-------|------------------------|
| `YYYY`| 4-digit year           |
| `YY`  | 2-digit year           |
| `ZZZ` | Timezone offset (+HH:MM) |
| `MM`  | 2-digit month (01-12)  |
| `DD`  | 2-digit day (01-31)    |
| `HH`  | 2-digit hour (00-23)   |
| `mm`  | 2-digit minute (00-59) |
| `ss`  | 2-digit second (00-59) |
| `ZZ`  | Timezone offset (+HHMM) |
| `M`   | 1-2 digit month        |
| `D`   | 1-2 digit day          |
| `H`   | 1-2 digit hour         |

### formatDateToBuf

Formats a date/time to a buffer.

```zig
pub fn formatDateToBuf(buf: []u8, fmt: []const u8, year: i32, month: u8, day: u8, hour: u64, minute: u64, second: u64, millis: u64) ![]u8
```

### formatDateToBufWithOffset

Formats a date/time pattern to a buffer with timezone token support.

```zig
pub fn formatDateToBufWithOffset(buf: []u8, fmt: []const u8, year: i32, month: u8, day: u8, hour: u64, minute: u64, second: u64, millis: u64, timezone_offset_minutes: i16) ![]u8
```

### formatIsoDate

Formats an ISO 8601 date (YYYY-MM-DD).

```zig
pub fn formatIsoDate(buf: []u8, tc: TimeComponents) ![]u8
```

### formatIsoTime

Formats an ISO 8601 time (HH:MM:SS).

```zig
pub fn formatIsoTime(buf: []u8, tc: TimeComponents) ![]u8
```

### formatIsoDateTime

Formats an ISO 8601 datetime (YYYY-MM-DDTHH:MM:SS).

```zig
pub fn formatIsoDateTime(buf: []u8, tc: TimeComponents) ![]u8
```

### formatFilenameSafe

Formats a filename-safe datetime (YYYY-MM-DD_HH-MM-SS).

```zig
pub fn formatFilenameSafe(buf: []u8, tc: TimeComponents) ![]u8
```

## Pattern Matching

### matchRegexPattern

Anchored regex-like matching starting from the beginning of the string.

```zig
pub fn matchRegexPattern(input: []const u8, pattern: []const u8) ?usize
```

**Supported Syntax:**

- `.` - Any character
- `*` - Zero or more of previous token
- `+` - One or more of previous token
- `?` - Zero or one of previous token
- `\d`, `\D` - Digit / Non-digit
- `\w`, `\W` - Alphanumeric + `_` / Non-alphanumeric
- `\s`, `\S` - Whitespace / Non-whitespace

### findRegexPattern

Searches for the first occurrence of a regex pattern anywhere in the string.

```zig
pub fn findRegexPattern(input: []const u8, pattern: []const u8) ?[]const u8
```

**Example:**

```zig
if (Utils.findRegexPattern("error at line 42", "\\d+")) |match| {
    // match = "42"
}
```

## String & Redaction Utilities

### replaceString

Replaces all occurrences of a substring with a replacement string. Allocates a new string for the result.

```zig
pub fn replaceString(allocator: std.mem.Allocator, input: []const u8, needle: []const u8, replacement: []const u8) ![]u8
```

### maskString

Masks a string for redaction purposes. Supports full masking, partial start/end, and middle masking.

```zig
pub fn maskString(
    allocator: std.mem.Allocator,
    value: []const u8,
    mask_char: u8,
    start_reveal: usize,
    end_reveal: usize,
    mode: enum { full, partial_start, partial_end, mask_middle }
) ![]u8
```

**Modes:**

- `full`: Masks the entire string (result length = input length).
- `partial_start`: Shows the beginning of the string, masks the rest.
- `partial_end`: Shows the end of the string, masks the beginning.
- `mask_middle`: Shows start and end, masks the middle (e.g., credit cards).

### computeRedactionHash

Computes a short SHA256 hash (first 8 bytes) formatted as hex for consistent redaction replacement.

```zig
pub fn computeRedactionHash(allocator: std.mem.Allocator, value: []const u8) ![]u8
```

**Format:** `[HASH:<16_char_hex>]`

## General Utilities

### clamp

Clamps a value between min and max bounds.

```zig
pub fn clamp(comptime T: type, value: T, min_val: T, max_val: T) T
```

### safeToUnsigned

Safely converts a signed integer to unsigned (returns 0 for negatives).

```zig
pub fn safeToUnsigned(comptime T: type, value: anytype) T
```

### min / max

Returns the minimum or maximum of two values.

```zig
pub fn min(comptime T: type, a: T, b: T) T
pub fn max(comptime T: type, a: T, b: T) T
```

## Usage Example

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    // Parse configuration sizes
    const max_size = logly.Utils.parseSize("10MB") orelse 10485760;
    const timeout = logly.Utils.parseDuration("30s") orelse 30000;
    
    // Get current time
    const now = logly.Utils.nowComponents();
    
    // Format for display
    var buf: [32]u8 = undefined;
    const date_str = try logly.Utils.formatIsoDate(&buf, now);
    std.debug.print("Today: {s}\n", .{date_str});
    
    // Calculate elapsed time
    const start = logly.Utils.currentMillis();
    // ... do work ...
    const elapsed = logly.Utils.elapsedMs(start);
    std.debug.print("Elapsed: {d}ms\n", .{elapsed});
}
```

## See Also

- [Config API](config.md) - Configuration options
- [Rotation Guide](../guide/rotation.md) - Log rotation
