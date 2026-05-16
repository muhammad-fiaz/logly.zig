//! Utility Functions Module
//!
//! Provides common utility functions used throughout the Logly logging library.
//! All functions are designed for high performance with minimal allocations.
//!
//! Categories:
//! - Size Parsing/Formatting: Parse "10MB" to bytes, format bytes to "10 MB"
//! - Duration Parsing/Formatting: Parse "30s" to milliseconds
//! - Time Utilities: Epoch conversion, time components, elapsed time
//! - Date/Time Formatting: ISO 8601, custom patterns, RFC 3339
//! - JSON Utilities: String escaping for JSON output
//! - Math Utilities: Rate calculations, averages, clamping
//! - ID Generation: Trace IDs, span IDs for distributed tracing
//! - Statistics: Error rates, throughput, averages
//!
//! Performance Characteristics:
//! - Most functions are O(1) or O(n) where n is string length
//! - Zero allocations for formatting to writers
//! - Thread-safe (no global state)

const std = @import("std");
const builtin = @import("builtin");
const Constants = @import("constants.zig");
var threaded = std.Io.Threaded.init_single_threaded;

pub fn io() std.Io {
    return threaded.io();
}

/// Adapts an unmanaged `std.ArrayList(u8)` to the Zig 0.16 `std.Io.Writer` interface.
pub const ArrayListWriter = struct {
    writer: std.Io.Writer,
    list: *std.ArrayList(u8),
    allocator: std.mem.Allocator,

    const vtable: std.Io.Writer.VTable = .{ .drain = drain };

    pub fn init(list: *std.ArrayList(u8), allocator: std.mem.Allocator) ArrayListWriter {
        return .{
            .writer = .{
                .vtable = &vtable,
                .buffer = &.{},
            },
            .list = list,
            .allocator = allocator,
        };
    }

    fn drain(w: *std.Io.Writer, data: []const []const u8, splat: usize) std.Io.Writer.Error!usize {
        const self: *ArrayListWriter = @fieldParentPtr("writer", w);
        var written: usize = 0;
        for (data) |bytes| {
            self.list.appendSlice(self.allocator, bytes) catch return error.WriteFailed;
            written += bytes.len;
        }
        if (splat == 0) {
            const pattern = data[data.len - 1];
            self.list.shrinkRetainingCapacity(self.list.items.len - pattern.len);
            written -= pattern.len;
        } else {
            const pattern = data[data.len - 1];
            for (1..splat) |_| {
                self.list.appendSlice(self.allocator, pattern) catch return error.WriteFailed;
                written += pattern.len;
            }
        }
        return written;
    }
};

fn nowReal() std.Io.Timestamp {
    return std.Io.Clock.real.now(io());
}

fn nowMonotonic() std.Io.Timestamp {
    return std.Io.Clock.awake.now(io());
}

/// Parses a size string (e.g., "10MB", "5GB") into bytes.
/// Supports B, KB, MB, GB, TB (case insensitive).
/// Also supports shorthand notations: K, M, G, T (without B).
///
/// Examples:
/// - "1024" -> 1024 bytes
/// - "10KB" -> 10240 bytes
/// - "5M" -> 5242880 bytes
/// - "1GB" -> 1073741824 bytes
/// - "100 MB" -> 104857600 bytes (whitespace allowed)
pub fn parseSize(s: []const u8) ?u64 {
    var end: usize = 0;
    while (end < s.len and std.ascii.isDigit(s[end])) : (end += 1) {}

    if (end == 0) return null;

    const num = std.fmt.parseInt(u64, s[0..end], 10) catch return null;

    // Skip whitespace
    var unit_start = end;
    while (unit_start < s.len and std.ascii.isWhitespace(s[unit_start])) : (unit_start += 1) {}

    if (unit_start >= s.len) return num; // Default to bytes if no unit

    const unit = s[unit_start..];

    // Supports B, KB, MB, GB, TB (case insensitive)
    if (std.ascii.eqlIgnoreCase(unit, "B")) return num;
    if (std.ascii.eqlIgnoreCase(unit, "K") or std.ascii.eqlIgnoreCase(unit, "KB")) return num * Constants.SizeConstants.bytes_per_kb;
    if (std.ascii.eqlIgnoreCase(unit, "M") or std.ascii.eqlIgnoreCase(unit, "MB")) return num * Constants.SizeConstants.bytes_per_mb;
    if (std.ascii.eqlIgnoreCase(unit, "G") or std.ascii.eqlIgnoreCase(unit, "GB")) return num * Constants.SizeConstants.bytes_per_gb;
    if (std.ascii.eqlIgnoreCase(unit, "T") or std.ascii.eqlIgnoreCase(unit, "TB")) return num * Constants.SizeConstants.bytes_per_tb;

    return num;
}

/// Writes a human-readable byte size to the writer.
pub fn writeSize(writer: anytype, bytes: u64) !void {
    const units = [_][]const u8{ "B", "KB", "MB", "GB", "TB" };
    const bytes_per_kb_f: f64 = @floatFromInt(Constants.SizeConstants.bytes_per_kb);
    var value: f64 = @floatFromInt(bytes);
    var unit_idx: usize = 0;

    while (value >= bytes_per_kb_f and unit_idx < units.len - 1) {
        value /= bytes_per_kb_f;
        unit_idx += 1;
    }

    if (unit_idx == 0) {
        try writer.print("{d} {s}", .{ bytes, units[unit_idx] });
    } else {
        try writer.print("{d:.2} {s}", .{ value, units[unit_idx] });
    }
}

/// Formats a byte size into a human-readable string.
/// Uses the most appropriate unit (B, KB, MB, GB, TB).
pub fn formatSize(allocator: std.mem.Allocator, bytes: u64) ![]u8 {
    var writer = std.Io.Writer.Allocating.init(allocator);
    errdefer writer.deinit();
    try writeSize(&writer.writer, bytes);
    return writer.toOwnedSlice();
}

/// Parses a duration string (e.g., "30s", "5m", "2h") into milliseconds.
/// Supports: ms (milliseconds), s (seconds), m (minutes), h (hours), d (days).
///
/// Examples:
/// - "1000ms" -> 1000
/// - "30s" -> 30000
/// - "5m" -> 300000
/// - "2h" -> 7200000
/// - "1d" -> 86400000
pub fn parseDuration(s: []const u8) ?i64 {
    var end: usize = 0;
    while (end < s.len and std.ascii.isDigit(s[end])) : (end += 1) {}

    if (end == 0) return null;

    const num = std.fmt.parseInt(i64, s[0..end], 10) catch return null;

    // Skip whitespace
    var unit_start = end;
    while (unit_start < s.len and std.ascii.isWhitespace(s[unit_start])) : (unit_start += 1) {}

    if (unit_start >= s.len) return num; // Default to milliseconds if no unit

    const unit = s[unit_start..];

    if (std.ascii.eqlIgnoreCase(unit, "ms")) return num;
    if (std.ascii.eqlIgnoreCase(unit, "s")) return num * @as(i64, @intCast(Constants.TimeConstants.ms_per_second));
    if (std.ascii.eqlIgnoreCase(unit, "m")) return num * @as(i64, @intCast(Constants.TimeConstants.seconds_per_minute * Constants.TimeConstants.ms_per_second));
    if (std.ascii.eqlIgnoreCase(unit, "h")) return num * @as(i64, @intCast(Constants.TimeConstants.seconds_per_hour * Constants.TimeConstants.ms_per_second));
    if (std.ascii.eqlIgnoreCase(unit, "d")) return num * @as(i64, @intCast(Constants.TimeConstants.seconds_per_day * Constants.TimeConstants.ms_per_second));

    return num;
}

/// Writes a human-readable duration to the writer.
pub fn writeDuration(writer: anytype, ms: i64) !void {
    const ms_per_sec = @as(i64, @intCast(Constants.TimeConstants.ms_per_second));
    const ms_per_min = @as(i64, @intCast(Constants.TimeConstants.seconds_per_minute * Constants.TimeConstants.ms_per_second));
    const ms_per_hour = @as(i64, @intCast(Constants.TimeConstants.seconds_per_hour * Constants.TimeConstants.ms_per_second));
    const ms_per_day = @as(i64, @intCast(Constants.TimeConstants.seconds_per_day * Constants.TimeConstants.ms_per_second));

    if (ms < ms_per_sec) {
        try writer.print("{d}ms", .{ms});
    } else if (ms < ms_per_min) {
        try writer.print("{d:.2}s", .{@as(f64, @floatFromInt(ms)) / @as(f64, @floatFromInt(ms_per_sec))});
    } else if (ms < ms_per_hour) {
        try writer.print("{d:.2}m", .{@as(f64, @floatFromInt(ms)) / @as(f64, @floatFromInt(ms_per_min))});
    } else if (ms < ms_per_day) {
        try writer.print("{d:.2}h", .{@as(f64, @floatFromInt(ms)) / @as(f64, @floatFromInt(ms_per_hour))});
    } else {
        try writer.print("{d:.2}d", .{@as(f64, @floatFromInt(ms)) / @as(f64, @floatFromInt(ms_per_day))});
    }
}

/// Formats a duration in milliseconds into a human-readable string.
pub fn formatDuration(allocator: std.mem.Allocator, ms: i64) ![]u8 {
    var writer = std.Io.Writer.Allocating.init(allocator);
    errdefer writer.deinit();
    try writeDuration(&writer.writer, ms);
    return writer.toOwnedSlice();
}

/// Time components extracted from an epoch timestamp.
pub const TimeComponents = struct {
    year: i32,
    month: u8,
    day: u8,
    hour: u64,
    minute: u64,
    second: u64,
};

/// Extracts time components from a Unix epoch timestamp (seconds).
pub fn fromEpochSeconds(timestamp: i64) TimeComponents {
    const safe_ts: u64 = if (timestamp < 0) 0 else @intCast(timestamp);
    const epoch = std.time.epoch.EpochSeconds{ .secs = safe_ts };
    const yd = epoch.getEpochDay().calculateYearDay();
    const md = yd.calculateMonthDay();
    const ds = epoch.getDaySeconds();

    return .{
        .year = yd.year,
        .month = md.month.numeric(),
        .day = md.day_index + 1,
        .hour = ds.getHoursIntoDay(),
        .minute = ds.getMinutesIntoHour(),
        .second = ds.getSecondsIntoMinute(),
    };
}

/// Extracts time components from a millisecond timestamp.
pub fn fromMilliTimestamp(timestamp: i64) TimeComponents {
    return fromEpochSeconds(@divFloor(timestamp, @as(i64, @intCast(Constants.TimeConstants.ms_per_second))));
}

/// Converts a civil date to days since Unix epoch (1970-01-01).
///
/// Uses Howard Hinnant's algorithm and performs only integer arithmetic.
fn daysFromCivil(year: i32, month: u8, day: u8) i64 {
    const y: i64 = @as(i64, @intCast(year));
    const m: i64 = @as(i64, @intCast(month));
    const d: i64 = @as(i64, @intCast(day));

    const adjusted_year = y - (if (m <= 2) @as(i64, 1) else @as(i64, 0));
    const era = @divFloor(if (adjusted_year >= 0) adjusted_year else adjusted_year - 399, 400);
    const yoe = adjusted_year - era * 400;
    const month_adjusted = m + (if (m > 2) @as(i64, -3) else @as(i64, 9));
    const doy = @divFloor(153 * month_adjusted + 2, 5) + d - 1;
    const doe = yoe * 365 + @divFloor(yoe, 4) - @divFloor(yoe, 100) + doy;

    return era * 146097 + doe - 719468;
}

/// Converts time components to epoch seconds.
///
/// Treats the components as a UTC-like civil instant.
fn epochSecondsFromComponents(tc: TimeComponents) i64 {
    const days = daysFromCivil(tc.year, tc.month, tc.day);
    const seconds_in_day: i64 = @as(i64, @intCast(tc.hour)) * @as(i64, @intCast(Constants.TimeConstants.seconds_per_hour)) +
        @as(i64, @intCast(tc.minute)) * @as(i64, @intCast(Constants.TimeConstants.seconds_per_minute)) +
        @as(i64, @intCast(tc.second));
    return days * @as(i64, @intCast(Constants.TimeConstants.seconds_per_day)) + seconds_in_day;
}

/// Converts epoch seconds to local-time components via libc.
///
/// Returns `null` when libc or timezone APIs are unavailable.
fn localTimeComponentsFromLibc(timestamp_seconds: i64) ?TimeComponents {
    if (!builtin.link_libc) return null;

    if (comptime (@hasDecl(std.c, "time_t") and @hasDecl(std.c, "tm"))) {
        var epoch_seconds: std.c.time_t = @intCast(timestamp_seconds);
        var local_tm: std.c.tm = undefined;

        if (@hasDecl(std.c, "localtime_r")) {
            if (std.c.localtime_r(&epoch_seconds, &local_tm) == null) return null;
        } else if (@hasDecl(std.c, "localtime")) {
            const tm_ptr = std.c.localtime(&epoch_seconds);
            if (tm_ptr == null) return null;
            local_tm = tm_ptr.*;
        } else {
            return null;
        }

        return .{
            .year = @as(i32, @intCast(local_tm.tm_year + 1900)),
            .month = @as(u8, @intCast(local_tm.tm_mon + 1)),
            .day = @as(u8, @intCast(local_tm.tm_mday)),
            .hour = @as(u64, @intCast(local_tm.tm_hour)),
            .minute = @as(u64, @intCast(local_tm.tm_min)),
            .second = @as(u64, @intCast(local_tm.tm_sec)),
        };
    }

    return null;
}

/// Extracts local-time components from a millisecond timestamp.
/// Falls back to UTC conversion when libc localtime support is unavailable.
pub fn fromMilliTimestampLocal(timestamp: i64) TimeComponents {
    const safe_seconds = @divFloor(if (timestamp < 0) 0 else timestamp, @as(i64, @intCast(Constants.TimeConstants.ms_per_second)));
    if (localTimeComponentsFromLibc(safe_seconds)) |tc| {
        return tc;
    }
    return fromEpochSeconds(safe_seconds);
}

/// Returns local UTC offset in minutes for a millisecond timestamp.
/// Returns 0 when local timezone conversion is unavailable.
pub fn localUtcOffsetMinutes(timestamp: i64) i16 {
    const safe_seconds = @divFloor(if (timestamp < 0) 0 else timestamp, @as(i64, @intCast(Constants.TimeConstants.ms_per_second)));
    const local_tc = localTimeComponentsFromLibc(safe_seconds) orelse return 0;

    const local_as_utc_seconds = epochSecondsFromComponents(local_tc);
    const offset_minutes = @divTrunc(local_as_utc_seconds - safe_seconds, @as(i64, @intCast(Constants.TimeConstants.seconds_per_minute)));

    const min_offset = @as(i64, Constants.TimeConstants.min_utc_offset_minutes);
    const max_offset = @as(i64, Constants.TimeConstants.max_utc_offset_minutes);
    const bounded = clamp(i64, offset_minutes, min_offset, max_offset);

    return @as(i16, @intCast(bounded));
}

fn splitUtcOffsetMinutes(offset_minutes: i16) struct { sign: u8, hours: u16, minutes: u16 } {
    const clamped_offset = clamp(i16, offset_minutes, Constants.TimeConstants.min_utc_offset_minutes, Constants.TimeConstants.max_utc_offset_minutes);
    const sign: u8 = if (clamped_offset < 0) '-' else '+';
    const abs_minutes_i32: i32 = if (clamped_offset < 0)
        -@as(i32, clamped_offset)
    else
        @as(i32, clamped_offset);
    const abs_minutes_u16: u16 = @intCast(abs_minutes_i32);
    const minutes_per_hour: u16 = Constants.TimeConstants.minutes_per_hour;

    return .{
        .sign = sign,
        .hours = @divFloor(abs_minutes_u16, minutes_per_hour),
        .minutes = @mod(abs_minutes_u16, minutes_per_hour),
    };
}

/// Writes a UTC offset in `+HH:MM` or `-HH:MM` format.
///
/// The offset is expressed in minutes and is clamped by callers to a safe range.
pub fn writeUtcOffset(writer: anytype, offset_minutes: i16) !void {
    const offset_parts = splitUtcOffsetMinutes(offset_minutes);

    try writer.writeByte(offset_parts.sign);
    try write2Digits(writer, offset_parts.hours);
    try writer.writeByte(':');
    try write2Digits(writer, offset_parts.minutes);
}

/// Writes a compact UTC offset in `+HHMM` or `-HHMM` format.
pub fn writeUtcOffsetCompact(writer: anytype, offset_minutes: i16) !void {
    const offset_parts = splitUtcOffsetMinutes(offset_minutes);

    try writer.writeByte(offset_parts.sign);
    try write2Digits(writer, offset_parts.hours);
    try write2Digits(writer, offset_parts.minutes);
}

/// Gets current time components.
pub fn nowComponents() TimeComponents {
    return fromMilliTimestamp(currentMillis());
}

/// Returns current Unix timestamp in seconds.
pub fn currentSeconds() i64 {
    return nowReal().toSeconds();
}

/// Returns current timestamp in milliseconds.
pub fn currentMillis() i64 {
    return nowReal().toMilliseconds();
}

/// Returns current timestamp in nanoseconds.
pub fn currentNanos() i128 {
    return @as(i128, nowMonotonic().toNanoseconds());
}

/// Sleeps for the specified duration in nanoseconds.
pub fn sleepNs(duration_ns: u64) void {
    const duration = std.Io.Duration.fromNanoseconds(@as(i96, @intCast(duration_ns)));
    _ = std.Io.sleep(io(), duration, .awake) catch {};
}

/// Sleeps for the specified duration in milliseconds.
pub fn sleepMs(duration_ms: u64) void {
    sleepNs(duration_ms * Constants.TimeConstants.ns_per_ms);
}

/// Checks if two timestamps are on the same day.
pub fn isSameDay(ts1: i64, ts2: i64) bool {
    const tc1 = fromEpochSeconds(ts1);
    const tc2 = fromEpochSeconds(ts2);
    return tc1.year == tc2.year and tc1.month == tc2.month and tc1.day == tc2.day;
}

/// Checks if two timestamps are in the same hour.
pub fn isSameHour(ts1: i64, ts2: i64) bool {
    const tc1 = fromEpochSeconds(ts1);
    const tc2 = fromEpochSeconds(ts2);
    return isSameDay(ts1, ts2) and tc1.hour == tc2.hour;
}

/// Returns the start of the current day (midnight) as epoch seconds.
pub fn startOfDay(timestamp: i64) i64 {
    const tc = fromEpochSeconds(timestamp);
    return timestamp - @as(i64, @intCast(tc.hour * Constants.TimeConstants.seconds_per_hour + tc.minute * Constants.TimeConstants.seconds_per_minute + tc.second));
}

/// Returns the start of the current hour as epoch seconds.
pub fn startOfHour(timestamp: i64) i64 {
    const tc = fromEpochSeconds(timestamp);
    return timestamp - @as(i64, @intCast(tc.minute * Constants.TimeConstants.seconds_per_minute + tc.second));
}

/// Calculates elapsed time in milliseconds since start_time.
pub fn elapsedMs(start_time: i64) u64 {
    const now_time = currentMillis();
    if (now_time < start_time) return 0;
    return @intCast(now_time - start_time);
}

/// Calculates elapsed time in seconds since start_time.
pub fn elapsedSeconds(start_time: i64) u64 {
    return elapsedMs(start_time) / Constants.TimeConstants.ms_per_second;
}

/// Formats a date/time string based on a format pattern using granular tokens.
/// Supports all ASCII symbols as separators between tokens.
///
/// Supported tokens:
/// YYYY - Year (4 digits)
/// YY   - Year (2 digits)
/// ZZZ  - Timezone offset with colon (+05:30)
/// MM   - Month (01-12)
/// DD   - Day (01-31)
/// HH   - Hour (00-23)
/// mm   - Minute (00-59)
/// ss   - Second (00-59)
/// ZZ   - Timezone offset compact (+0530)
/// M    - Month (1-12) - single digit
/// D    - Day (1-31) - single digit
/// H    - Hour (0-23) - single digit
pub fn formatDatePattern(writer: anytype, fmt: []const u8, year: i32, month: u8, day: u8, hour: u64, minute: u64, second: u64, millis: u64) !void {
    return formatDatePatternInternal(writer, fmt, year, month, day, hour, minute, second, millis, null);
}

/// Formats a date/time pattern and enables timezone tokens (`ZZZ`, `ZZ`).
pub fn formatDatePatternWithOffset(writer: anytype, fmt: []const u8, year: i32, month: u8, day: u8, hour: u64, minute: u64, second: u64, millis: u64, timezone_offset_minutes: i16) !void {
    return formatDatePatternInternal(writer, fmt, year, month, day, hour, minute, second, millis, timezone_offset_minutes);
}

fn formatDatePatternInternal(writer: anytype, fmt: []const u8, year: i32, month: u8, day: u8, hour: u64, minute: u64, second: u64, millis: u64, timezone_offset_minutes: ?i16) !void {
    var i: usize = 0;
    while (i < fmt.len) {
        if (i + 4 <= fmt.len and std.mem.eql(u8, fmt[i .. i + 4], "YYYY")) {
            try write4Digits(writer, year);
            i += 4;
        } else if (i + 2 <= fmt.len and std.mem.eql(u8, fmt[i .. i + 2], "YY")) {
            try write2Digits(writer, @mod(year, 100));
            i += 2;
        } else if (i + 3 <= fmt.len and std.mem.eql(u8, fmt[i .. i + 3], "ZZZ")) {
            if (timezone_offset_minutes) |offset| {
                try writeUtcOffset(writer, offset);
            } else {
                try writer.writeAll("ZZZ");
            }
            i += 3;
        } else if (i + 2 <= fmt.len and std.mem.eql(u8, fmt[i .. i + 2], "ZZ")) {
            if (timezone_offset_minutes) |offset| {
                try writeUtcOffsetCompact(writer, offset);
            } else {
                try writer.writeAll("ZZ");
            }
            i += 2;
        } else if (i + 3 <= fmt.len and std.mem.eql(u8, fmt[i .. i + 3], "SSS")) {
            try write3Digits(writer, millis);
            i += 3;
        } else if (i + 2 <= fmt.len and std.mem.eql(u8, fmt[i .. i + 2], "MM")) {
            try write2Digits(writer, month);
            i += 2;
        } else if (i + 2 <= fmt.len and std.mem.eql(u8, fmt[i .. i + 2], "DD")) {
            try write2Digits(writer, day);
            i += 2;
        } else if (i + 2 <= fmt.len and std.mem.eql(u8, fmt[i .. i + 2], "HH")) {
            try write2Digits(writer, hour);
            i += 2;
        } else if (i + 2 <= fmt.len and std.mem.eql(u8, fmt[i .. i + 2], "hh")) {
            const h12 = if (hour == 0) 12 else if (hour > 12) hour - 12 else hour;
            try write2Digits(writer, h12);
            i += 2;
        } else if (i + 2 <= fmt.len and std.mem.eql(u8, fmt[i .. i + 2], "mm")) {
            try write2Digits(writer, minute);
            i += 2;
        } else if (i + 2 <= fmt.len and std.mem.eql(u8, fmt[i .. i + 2], "ss")) {
            try write2Digits(writer, second);
            i += 2;
        } else if (fmt[i] == 'M' and (i + 1 >= fmt.len or fmt[i + 1] != 'M')) {
            try write1Or2Digits(writer, month);
            i += 1;
        } else if (fmt[i] == 'D' and (i + 1 >= fmt.len or fmt[i + 1] != 'D')) {
            try write1Or2Digits(writer, day);
            i += 1;
        } else if (fmt[i] == 'H' and (i + 1 >= fmt.len or fmt[i + 1] != 'H')) {
            try write1Or2Digits(writer, hour);
            i += 1;
        } else if (fmt[i] == 's' and (i + 1 >= fmt.len or fmt[i + 1] != 's')) {
            try write1Or2Digits(writer, second);
            i += 1;
        } else {
            try writer.writeByte(fmt[i]);
            i += 1;
        }
    }
}

/// Formats a date/time to a caller-provided buffer using a pattern.
pub fn formatDateToBuf(buf: []u8, fmt: []const u8, year: i32, month: u8, day: u8, hour: u64, minute: u64, second: u64, millis: u64) ![]u8 {
    var writer = std.Io.Writer.fixed(buf);
    try formatDatePattern(&writer, fmt, year, month, day, hour, minute, second, millis);
    return buf[0..writer.end];
}

/// Formats a date/time to a caller-provided buffer with timezone token support.
pub fn formatDateToBufWithOffset(buf: []u8, fmt: []const u8, year: i32, month: u8, day: u8, hour: u64, minute: u64, second: u64, millis: u64, timezone_offset_minutes: i16) ![]u8 {
    var writer = std.Io.Writer.fixed(buf);
    try formatDatePatternWithOffset(&writer, fmt, year, month, day, hour, minute, second, millis, timezone_offset_minutes);
    return buf[0..writer.end];
}

/// Writes an ISO 8601 date (YYYY-MM-DD) to the writer.
pub fn writeIsoDate(writer: anytype, tc: TimeComponents) !void {
    try write4Digits(writer, tc.year);
    try writer.writeByte('-');
    try write2Digits(writer, tc.month);
    try writer.writeByte('-');
    try write2Digits(writer, tc.day);
}

/// Formats an ISO 8601 date string (YYYY-MM-DD) to buffer.
pub fn formatIsoDate(buf: []u8, tc: TimeComponents) ![]u8 {
    var writer = std.Io.Writer.fixed(buf);
    try writeIsoDate(&writer, tc);
    return buf[0..writer.end];
}

/// Writes an ISO 8601 time (HH:MM:SS) to the writer.
pub fn writeIsoTime(writer: anytype, tc: TimeComponents) !void {
    try write2Digits(writer, tc.hour);
    try writer.writeByte(':');
    try write2Digits(writer, tc.minute);
    try writer.writeByte(':');
    try write2Digits(writer, tc.second);
}

/// Formats an ISO 8601 time string (HH:MM:SS) to buffer.
pub fn formatIsoTime(buf: []u8, tc: TimeComponents) ![]u8 {
    var writer = std.Io.Writer.fixed(buf);
    try writeIsoTime(&writer, tc);
    return buf[0..writer.end];
}

/// Writes an ISO 8601 datetime (YYYY-MM-DDTHH:MM:SS) to the writer.
pub fn writeIsoDateTime(writer: anytype, tc: TimeComponents) !void {
    try writeIsoDate(writer, tc);
    try writer.writeByte('T');
    try writeIsoTime(writer, tc);
}

/// Formats an ISO 8601 datetime string (YYYY-MM-DDTHH:MM:SS) to buffer.
pub fn formatIsoDateTime(buf: []u8, tc: TimeComponents) ![]u8 {
    var writer = std.Io.Writer.fixed(buf);
    try writeIsoDateTime(&writer, tc);
    return buf[0..writer.end];
}

/// Writes a filename-safe datetime (YYYY-MM-DD_HH-MM-SS) to the writer.
pub fn writeFilenameSafe(writer: anytype, tc: TimeComponents) !void {
    try write4Digits(writer, tc.year);
    try writer.writeByte('-');
    try write2Digits(writer, tc.month);
    try writer.writeByte('-');
    try write2Digits(writer, tc.day);
    try writer.writeByte('_');
    try write2Digits(writer, tc.hour);
    try writer.writeByte('-');
    try write2Digits(writer, tc.minute);
    try writer.writeByte('-');
    try write2Digits(writer, tc.second);
}

/// Formats a filename-safe datetime string (YYYY-MM-DD_HH-MM-SS) to buffer.
pub fn formatFilenameSafe(buf: []u8, tc: TimeComponents) ![]u8 {
    var writer = std.Io.Writer.fixed(buf);
    try writeFilenameSafe(&writer, tc);
    return buf[0..writer.end];
}

/// Clamps a value between min and max bounds.
pub fn clamp(comptime T: type, value: T, min_val: T, max_val: T) T {
    if (value < min_val) return min_val;
    if (value > max_val) return max_val;
    return value;
}

/// Safely converts a signed integer to unsigned, returning 0 for negative values.
pub fn safeToUnsigned(comptime T: type, value: anytype) T {
    if (value < 0) return 0;
    return @intCast(value);
}

/// Returns the minimum of two values.
pub fn min(comptime T: type, a: T, b: T) T {
    return if (a < b) a else b;
}

/// Returns the maximum of two values.
pub fn max(comptime T: type, a: T, b: T) T {
    return if (a > b) a else b;
}

/// Alias for formatDatePattern (for date_formatting module compatibility)
pub const format = formatDatePattern;

/// Alias for formatDateToBuf
pub const formatToBuf = formatDateToBuf;

/// Escapes a string for safe inclusion in JSON output.
/// Handles all JSON special characters including control characters.
///
/// Performance: O(n) where n = string length
/// Memory: Zero allocations - writes directly to the provided writer
///
/// Example:
/// ```zig
/// var buf: [256]u8 = undefined;
/// var writer = std.Io.Writer.fixed(&buf);
/// try escapeJsonString(fbs.writer(), "Hello\nWorld");
/// // Result: Hello\nWorld (with escaped newline)
/// ```
pub fn escapeJsonString(writer: anytype, s: []const u8) !void {
    for (s) |c| {
        switch (c) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\x08' => try writer.writeAll("\\b"),
            '\x0c' => try writer.writeAll("\\f"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            else => {
                if (c < 0x20) {
                    try writer.writeAll("\\u");
                    try write4Hex(writer, @intCast(c));
                } else {
                    try writer.writeByte(c);
                }
            },
        }
    }
}

/// Escapes a string for JSON and writes it to a buffer.
/// Returns the written slice.
///
/// Arguments:
///     buf: Output buffer
///     s: String to escape
///
/// Returns:
///     Slice of written content
pub fn escapeJsonStringToBuf(buf: []u8, s: []const u8) ![]u8 {
    var writer = std.Io.Writer.fixed(buf);
    try escapeJsonString(&writer, s);
    return buf[0..writer.end];
}

/// Calculates a rate as a floating-point ratio (0.0 - 1.0).
/// Safely handles division by zero by returning 0.
///
/// Performance: O(1)
///
/// Arguments:
///     numerator: The count of specific items
///     denominator: The total count
///
/// Returns:
///     The rate as a float between 0.0 and 1.0
pub fn calculateRate(numerator: u64, denominator: u64) f64 {
    if (denominator == 0) return 0.0;
    return @as(f64, @floatFromInt(numerator)) / @as(f64, @floatFromInt(denominator));
}

/// Calculates a percentage (0.0 - 100.0).
/// Safely handles division by zero by returning 0.
///
/// Performance: O(1)
///
/// Arguments:
///     numerator: The count of specific items
///     denominator: The total count
///
/// Returns:
///     The percentage as a float between 0.0 and 100.0
pub fn calculatePercentage(numerator: u64, denominator: u64) f64 {
    return calculateRate(numerator, denominator) * 100.0;
}

/// Calculates throughput (items per second) given a count and elapsed time.
///
/// Performance: O(1)
///
/// Arguments:
///     count: Number of items processed
///     elapsed_ns: Elapsed time in nanoseconds
///
/// Returns:
///     Items per second as a float
pub fn calculateThroughput(count: u64, elapsed_ns: u64) f64 {
    if (elapsed_ns == 0) return 0.0;
    const ns_per_sec = @as(f64, @floatFromInt(Constants.TimeConstants.ns_per_second));
    const seconds = @as(f64, @floatFromInt(elapsed_ns)) / ns_per_sec;
    return @as(f64, @floatFromInt(count)) / seconds;
}

/// Calculates throughput in milliseconds.
///
/// Performance: O(1)
///
/// Arguments:
///     count: Number of items processed
///     elapsed_ms: Elapsed time in milliseconds
///
/// Returns:
///     Items per second as a float
pub fn calculateThroughputMs(count: u64, elapsed_ms: i64) f64 {
    if (elapsed_ms <= 0) return 0.0;
    const seconds = @as(f64, @floatFromInt(elapsed_ms)) / @as(f64, @floatFromInt(Constants.TimeConstants.ms_per_second));
    return @as(f64, @floatFromInt(count)) / seconds;
}

test "escapeJsonString" {
    var buf: [256]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);

    try escapeJsonString(&writer, "Hello\"World");
    try std.testing.expectEqualStrings("Hello\\\"World", buf[0..writer.end]);

    writer.end = 0;
    try escapeJsonString(&writer, "Line1\nLine2");
    try std.testing.expectEqualStrings("Line1\\nLine2", buf[0..writer.end]);

    writer.end = 0;
    try escapeJsonString(&writer, "Tab\there");
    try std.testing.expectEqualStrings("Tab\\there", buf[0..writer.end]);
}

test "calculateRate" {
    try std.testing.expectEqual(@as(f64, 0.0), calculateRate(0, 0));
    try std.testing.expectEqual(@as(f64, 0.5), calculateRate(50, 100));
    try std.testing.expectEqual(@as(f64, 1.0), calculateRate(100, 100));
}

test "calculatePercentage" {
    try std.testing.expectEqual(@as(f64, 0.0), calculatePercentage(0, 0));
    try std.testing.expectEqual(@as(f64, 50.0), calculatePercentage(50, 100));
    try std.testing.expectEqual(@as(f64, 100.0), calculatePercentage(100, 100));
}

test "calculateThroughput" {
    // 100 items in 1 second = 100 items/sec
    try std.testing.expectEqual(@as(f64, 100.0), calculateThroughput(100, 1_000_000_000));
    // 0 elapsed time = 0 throughput
    try std.testing.expectEqual(@as(f64, 0.0), calculateThroughput(100, 0));
}

test "parseSize bytes" {
    try std.testing.expectEqual(@as(?u64, 1024), parseSize("1024"));
    try std.testing.expectEqual(@as(?u64, 100), parseSize("100B"));
}

test "parseSize kilobytes" {
    try std.testing.expectEqual(@as(?u64, 1024), parseSize("1KB"));
    try std.testing.expectEqual(@as(?u64, 1024), parseSize("1K"));
    try std.testing.expectEqual(@as(?u64, 10240), parseSize("10KB"));
}

test "parseSize megabytes" {
    try std.testing.expectEqual(@as(?u64, 1048576), parseSize("1MB"));
    try std.testing.expectEqual(@as(?u64, 1048576), parseSize("1M"));
}

test "parseSize gigabytes" {
    try std.testing.expectEqual(@as(?u64, 1073741824), parseSize("1GB"));
    try std.testing.expectEqual(@as(?u64, 1073741824), parseSize("1G"));
}

test "parseSize with whitespace" {
    try std.testing.expectEqual(@as(?u64, 10485760), parseSize("10 MB"));
}

test "parseSize invalid" {
    try std.testing.expectEqual(@as(?u64, null), parseSize(""));
    try std.testing.expectEqual(@as(?u64, null), parseSize("invalid"));
}

test "parseDuration" {
    try std.testing.expectEqual(@as(?i64, 1000), parseDuration("1000ms"));
    try std.testing.expectEqual(@as(?i64, 30000), parseDuration("30s"));
    try std.testing.expectEqual(@as(?i64, 300000), parseDuration("5m"));
    try std.testing.expectEqual(@as(?i64, 7200000), parseDuration("2h"));
    const one_day_ms = @as(i64, @intCast(Constants.TimeConstants.seconds_per_day * Constants.TimeConstants.ms_per_second));
    try std.testing.expectEqual(@as(?i64, one_day_ms), parseDuration("1d"));
}

test "fromEpochSeconds" {
    const tc = fromEpochSeconds(1735689600);
    try std.testing.expectEqual(@as(i32, 2025), tc.year);
    try std.testing.expectEqual(@as(u8, 1), tc.month);
    try std.testing.expectEqual(@as(u8, 1), tc.day);
}

test "fromMilliTimestampLocal returns valid components" {
    const tc = fromMilliTimestampLocal(1735689600000);
    try std.testing.expect(tc.month >= 1 and tc.month <= 12);
    try std.testing.expect(tc.day >= 1 and tc.day <= 31);
    try std.testing.expect(tc.hour <= 23);
    try std.testing.expect(tc.minute <= 59);
    try std.testing.expect(tc.second <= 59);
}

test "localUtcOffsetMinutes is bounded" {
    const offset = localUtcOffsetMinutes(1735689600000);
    try std.testing.expect(offset >= Constants.TimeConstants.min_utc_offset_minutes and offset <= Constants.TimeConstants.max_utc_offset_minutes);
}

test "isSameDay" {
    try std.testing.expect(isSameDay(1735689600, 1735689600 + @as(i64, @intCast(Constants.TimeConstants.seconds_per_hour))));
    try std.testing.expect(!isSameDay(1735689600, 1735689600 + @as(i64, @intCast(Constants.TimeConstants.seconds_per_day))));
}

test "clamp" {
    try std.testing.expectEqual(@as(i32, 5), clamp(i32, 3, 5, 10));
    try std.testing.expectEqual(@as(i32, 10), clamp(i32, 15, 5, 10));
    try std.testing.expectEqual(@as(i32, 7), clamp(i32, 7, 5, 10));
}

test "safeToUnsigned" {
    try std.testing.expectEqual(@as(u64, 0), safeToUnsigned(u64, @as(i64, -5)));
    try std.testing.expectEqual(@as(u64, 100), safeToUnsigned(u64, @as(i64, 100)));
}

test "formatDatePattern basic" {
    var buf: [64]u8 = undefined;
    const result = try formatDateToBuf(&buf, "YYYY-MM-DD | HH:mm:ss.SSS", 2025, 12, 25, 14, 30, 45, 123);
    try std.testing.expectEqualStrings("2025-12-25 | 14:30:45.123", result);
}

test "formatDatePatternWithOffset timezone tokens" {
    var buf: [64]u8 = undefined;
    const result = try formatDateToBufWithOffset(&buf, "YYYY-MM-DD HH:mm:ss ZZZ ZZ", 2025, 12, 25, 14, 30, 45, 123, 330);
    try std.testing.expectEqualStrings("2025-12-25 14:30:45 +05:30 +0530", result);
}

test "formatDatePattern timezone tokens are literal without offset" {
    var buf: [16]u8 = undefined;
    const result = try formatDateToBuf(&buf, "ZZZ ZZ", 2025, 12, 25, 14, 30, 45, 123);
    try std.testing.expectEqualStrings("ZZZ ZZ", result);
}

test "formatIsoDate basic" {
    const tc = TimeComponents{ .year = 2025, .month = 12, .day = 25, .hour = 14, .minute = 30, .second = 45 };
    var buf: [32]u8 = undefined;
    const result = try formatIsoDate(&buf, tc);
    try std.testing.expect(result.len > 0);
}

test "formatIsoDateTime basic" {
    const tc = TimeComponents{ .year = 2025, .month = 12, .day = 25, .hour = 14, .minute = 30, .second = 45 };
    var buf: [32]u8 = undefined;
    const result = try formatIsoDateTime(&buf, tc);
    try std.testing.expect(result.len > 0);
}

/// Writes a value as exactly 2 decimal digits (zero-padded).
pub fn write2Digits(writer: anytype, value: anytype) !void {
    const v: u64 = @intCast(value);
    const v2 = v % 100;
    try writer.writeByte(@intCast('0' + (v2 / 10)));
    try writer.writeByte(@intCast('0' + (v2 % 10)));
}

/// Writes a value as exactly 3 decimal digits (zero-padded).
pub fn write3Digits(writer: anytype, value: anytype) !void {
    const v: u64 = @intCast(value);
    const v3 = v % 1000;
    try writer.writeByte(@intCast('0' + (v3 / 100)));
    try writer.writeByte(@intCast('0' + ((v3 / 10) % 10)));
    try writer.writeByte(@intCast('0' + (v3 % 10)));
}

/// Writes a value as exactly 4 decimal digits (zero-padded).
pub fn write4Digits(writer: anytype, value: anytype) !void {
    const v: u64 = @intCast(value);
    const v4 = v % 10000;
    try writer.writeByte(@intCast('0' + (v4 / 1000)));
    try writer.writeByte(@intCast('0' + ((v4 / 100) % 10)));
    try writer.writeByte(@intCast('0' + ((v4 / 10) % 10)));
    try writer.writeByte(@intCast('0' + (v4 % 10)));
}

/// Writes a value using 1 or 2 decimal digits.
pub fn write1Or2Digits(writer: anytype, value: anytype) !void {
    const v: u64 = @intCast(value);
    if (v < 10) {
        try writer.writeByte(@intCast('0' + v));
    } else {
        try write2Digits(writer, v);
    }
}

/// Writes a 16-bit value as 4 lowercase hexadecimal digits.
pub fn write4Hex(writer: anytype, value: u16) !void {
    const hex = "0123456789abcdef";
    try writer.writeByte(hex[(value >> 12) & 0xF]);
    try writer.writeByte(hex[(value >> 8) & 0xF]);
    try writer.writeByte(hex[(value >> 4) & 0xF]);
    try writer.writeByte(hex[value & 0xF]);
}
/// Writes an integer value using decimal representation.
pub fn writeInt(writer: anytype, value: anytype) !void {
    try writer.print("{d}", .{value});
}

/// Generates a random 128-bit Trace ID as a hex string (32 chars).
/// Allocator is required to allocate the string.
pub fn generateTraceId(allocator: std.mem.Allocator) ![]u8 {
    var bytes: [16]u8 = undefined;
    io().random(&bytes);
    const hex_chars = "0123456789abcdef";
    var result = try allocator.alloc(u8, 32);
    for (bytes, 0..) |b, i| {
        result[i * 2] = hex_chars[b >> 4];
        result[i * 2 + 1] = hex_chars[b & 0xF];
    }
    return result;
}

/// Generates a random 64-bit Span ID as a hex string (16 chars).
/// Allocator is required to allocate the string.
pub fn generateSpanId(allocator: std.mem.Allocator) ![]u8 {
    var bytes: [8]u8 = undefined;
    io().random(&bytes);
    const hex_chars = "0123456789abcdef";
    var result = try allocator.alloc(u8, 16);
    for (bytes, 0..) |b, i| {
        result[i * 2] = hex_chars[b >> 4];
        result[i * 2 + 1] = hex_chars[b & 0xF];
    }
    return result;
}

/// Parsed W3C traceparent context.
pub const TraceparentContext = struct {
    version: []const u8,
    trace_id: []const u8,
    span_id: []const u8,
    flags: []const u8,
    sampled: bool,
};

/// Errors returned by traceparent helpers.
pub const TraceparentError = error{
    InvalidTraceId,
    InvalidSpanId,
};

fn isHexSlice(value: []const u8) bool {
    for (value) |c| {
        if (!std.ascii.isHex(c)) return false;
    }
    return true;
}

fn isAllZerosHex(value: []const u8) bool {
    for (value) |c| {
        if (c != '0') return false;
    }
    return true;
}

/// Parses a W3C `traceparent` header.
///
/// Expected format: `00-<32_hex_trace_id>-<16_hex_span_id>-<2_hex_flags>`.
pub fn parseTraceparentHeader(header: []const u8) ?TraceparentContext {
    if (header.len != 55) return null;
    if (header[2] != '-' or header[35] != '-' or header[52] != '-') return null;

    const version = header[0..2];
    const trace_id = header[3..35];
    const span_id = header[36..52];
    const flags = header[53..55];

    if (!isHexSlice(version) or !isHexSlice(trace_id) or !isHexSlice(span_id) or !isHexSlice(flags)) {
        return null;
    }

    if (isAllZerosHex(trace_id) or isAllZerosHex(span_id)) {
        return null;
    }

    const flags_byte = std.fmt.parseInt(u8, flags, 16) catch return null;

    return .{
        .version = version,
        .trace_id = trace_id,
        .span_id = span_id,
        .flags = flags,
        .sampled = (flags_byte & 0x01) == 0x01,
    };
}

/// Formats a W3C `traceparent` header string.
pub fn formatTraceparentHeader(allocator: std.mem.Allocator, trace_id: []const u8, span_id: []const u8, sampled: bool) ![]u8 {
    if (trace_id.len != 32 or !isHexSlice(trace_id) or isAllZerosHex(trace_id)) {
        return TraceparentError.InvalidTraceId;
    }

    if (span_id.len != 16 or !isHexSlice(span_id) or isAllZerosHex(span_id)) {
        return TraceparentError.InvalidSpanId;
    }

    const flags = if (sampled) "01" else "00";
    return std.fmt.allocPrint(allocator, "00-{s}-{s}-{s}", .{ trace_id, span_id, flags });
}

/// Determines if a trace should be sampled based on the sampling rate.
/// rate: 0.0 to 1.0 (0% to 100%)
pub fn shouldSample(rate: f64) bool {
    if (rate >= 1.0) return true;
    if (rate <= 0.0) return false;
    const rng_impl: std.Random.IoSource = .{ .io = io() };
    const rng = rng_impl.interface();
    return rng.float(f64) < rate;
}

test "generateTraceId" {
    const allocator = std.testing.allocator;
    const trace_id = try generateTraceId(allocator);
    defer allocator.free(trace_id);
    try std.testing.expectEqual(trace_id.len, 32);
}

test "generateSpanId" {
    const allocator = std.testing.allocator;
    const span_id = try generateSpanId(allocator);
    defer allocator.free(span_id);
    try std.testing.expectEqual(span_id.len, 16);
}

test "parseTraceparentHeader valid and sampled" {
    const ctx = parseTraceparentHeader("00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01");
    try std.testing.expect(ctx != null);
    try std.testing.expectEqualStrings("00", ctx.?.version);
    try std.testing.expectEqualStrings("4bf92f3577b34da6a3ce929d0e0e4736", ctx.?.trace_id);
    try std.testing.expectEqualStrings("00f067aa0ba902b7", ctx.?.span_id);
    try std.testing.expect(ctx.?.sampled);
}

test "parseTraceparentHeader rejects invalid values" {
    try std.testing.expect(parseTraceparentHeader("00-short-span-01") == null);
    try std.testing.expect(parseTraceparentHeader("00-00000000000000000000000000000000-00f067aa0ba902b7-01") == null);
    try std.testing.expect(parseTraceparentHeader("00-4bf92f3577b34da6a3ce929d0e0e4736-0000000000000000-01") == null);
    try std.testing.expect(parseTraceparentHeader("00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-zz") == null);
}

test "formatTraceparentHeader" {
    const allocator = std.testing.allocator;
    const traceparent = try formatTraceparentHeader(allocator, "4bf92f3577b34da6a3ce929d0e0e4736", "00f067aa0ba902b7", true);
    defer allocator.free(traceparent);
    try std.testing.expectEqualStrings("00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01", traceparent);

    try std.testing.expectError(TraceparentError.InvalidTraceId, formatTraceparentHeader(allocator, "short", "00f067aa0ba902b7", true));
    try std.testing.expectError(TraceparentError.InvalidSpanId, formatTraceparentHeader(allocator, "4bf92f3577b34da6a3ce929d0e0e4736", "short", true));
}

test "shouldSample" {
    try std.testing.expect(shouldSample(1.0));
    try std.testing.expect(!shouldSample(0.0));
}

/// Calculates an error rate from atomic counter values.
/// This is a common pattern used in stats structs across the codebase.
///
/// Arguments:
///     errors: Number of errors (or numerator)
///     total: Total number of operations (or denominator)
///
/// Returns:
///     Error rate as a float between 0.0 and 1.0
///
/// Performance: O(1)
pub fn calculateErrorRate(errors: u64, total: u64) f64 {
    if (total == 0) return 0.0;
    return @as(f64, @floatFromInt(errors)) / @as(f64, @floatFromInt(total));
}

/// Calculates an average value from a sum and count.
/// Safely handles division by zero.
///
/// Arguments:
///     sum: Total sum of values
///     count: Number of values
///
/// Returns:
///     Average as a float
///
/// Performance: O(1)
pub fn calculateAverage(sum: u64, count: u64) f64 {
    if (count == 0) return 0.0;
    return @as(f64, @floatFromInt(sum)) / @as(f64, @floatFromInt(count));
}

/// Safe floating-point division that returns 0.0 for division by zero.
///
/// Arguments:
///     numerator: The dividend
///     denominator: The divisor
///
/// Returns:
///     Result of division, or 0.0 if denominator is 0
///
/// Performance: O(1)
pub fn safeFloatDiv(numerator: f64, denominator: f64) f64 {
    if (denominator == 0.0) return 0.0;
    return numerator / denominator;
}

/// Loads a u64 value from an atomic counter, handling different atomic unsigned types.
/// This is useful for cross-platform compatibility where atomic types vary.
///
/// Arguments:
///     atomic: Pointer to the atomic value
///
/// Returns:
///     The loaded value as u64
///
/// Performance: O(1)
pub fn atomicLoadU64(atomic: anytype) u64 {
    return @as(u64, atomic.load(.monotonic));
}

/// Calculates bytes per second throughput.
///
/// Arguments:
///     bytes: Total bytes transferred
///     elapsed_ms: Elapsed time in milliseconds
///
/// Returns:
///     Bytes per second as a float
///
/// Performance: O(1)
pub fn calculateThroughputBytes(bytes: u64, elapsed_ms: i64) f64 {
    return calculateBytesPerSecond(bytes, elapsed_ms);
}

/// Calculates CRC32 checksum of data.
/// Uses standard IEEE polynomial.
pub fn calculateCRC32(data: []const u8) u32 {
    return std.hash.Crc32.hash(data);
}

/// Calculates bytes per second throughput from bytes and elapsed milliseconds.
pub fn calculateBytesPerSecond(bytes: u64, elapsed_ms: i64) f64 {
    if (elapsed_ms <= 0) return 0.0;
    const seconds = @as(f64, @floatFromInt(elapsed_ms)) / @as(f64, @floatFromInt(Constants.TimeConstants.ms_per_second));
    return @as(f64, @floatFromInt(bytes)) / seconds;
}

/// Calculates records per second throughput.
///
/// Arguments:
///     records: Total records processed
///     elapsed_ms: Elapsed time in milliseconds
///
/// Returns:
///     Records per second as a float
///
/// Performance: O(1)
pub fn calculateRecordsPerSecond(records: u64, elapsed_ms: i64) f64 {
    return calculateBytesPerSecond(records, elapsed_ms);
}

/// Creates a nanosecond duration from a start time to now.
///
/// Arguments:
///     start_time: The start timestamp in nanoseconds
///
/// Returns:
///     Duration in nanoseconds as u64
///
/// Performance: O(1)
pub fn durationSinceNs(start_time: i128) u64 {
    const now = currentNanos();
    if (now < start_time) return 0;
    return @intCast(@max(0, now - start_time));
}

/// Formats a nanosecond duration to a human-readable string.
///
/// Arguments:
///     writer: Output writer
///     ns: Duration in nanoseconds
///
/// Performance: O(1)
pub fn writeDurationNs(writer: anytype, ns: u64) !void {
    const ns_per_us = Constants.TimeConstants.ns_per_us;
    const ns_per_ms = Constants.TimeConstants.ns_per_ms;
    const ns_per_sec = Constants.TimeConstants.ns_per_second;

    if (ns < ns_per_us) {
        try writer.print("{d}ns", .{ns});
    } else if (ns < ns_per_ms) {
        try writer.print("{d:.2}µs", .{@as(f64, @floatFromInt(ns)) / @as(f64, @floatFromInt(ns_per_us))});
    } else if (ns < ns_per_sec) {
        try writer.print("{d:.2}ms", .{@as(f64, @floatFromInt(ns)) / @as(f64, @floatFromInt(ns_per_ms))});
    } else {
        try writer.print("{d:.2}s", .{@as(f64, @floatFromInt(ns)) / @as(f64, @floatFromInt(ns_per_sec))});
    }
}

/// Simple regex-like pattern matcher.
/// Supports:
/// - \d: Digit
/// - \w: Alphanumeric or _
/// - \s: Whitespace
/// - \D, \W, \S: Negated versions
/// - *: Zero or more of previous token
/// - +: One or more of previous token
/// - ?: Zero or one of previous token
/// - .: Any single character
/// - Literals match exactly
///
/// Returns the length of the match if successful (anchored at start), null otherwise.
pub fn matchRegexPattern(input: []const u8, pattern: []const u8) ?usize {
    return matchInternal(input, pattern, 0, 0);
}

/// Finds the first occurrence of a regex pattern in the input string.
/// Returns the matched slice if found, null otherwise.
pub fn findRegexPattern(input: []const u8, pattern: []const u8) ?[]const u8 {
    if (pattern.len == 0) return input[0..0];
    var i: usize = 0;
    while (i <= input.len) : (i += 1) {
        if (matchInternal(input, pattern, i, 0)) |end_idx| {
            return input[i..end_idx];
        }
    }
    return null;
}

fn matchInternal(input: []const u8, pattern: []const u8, i_idx: usize, p_idx: usize) ?usize {
    if (p_idx == pattern.len) return i_idx;

    // Handle special case: * or + at the very beginning or after another quantifier
    // Treat as matching ANY character (.)
    var p_char: u8 = undefined;
    var is_escaped = false;
    var current_p_idx = p_idx;

    if (pattern[p_idx] == '\\' and p_idx + 1 < pattern.len) {
        is_escaped = true;
        p_char = pattern[p_idx + 1];
        current_p_idx += 2;
    } else {
        p_char = pattern[p_idx];
        current_p_idx += 1;
    }

    // Check for quantifiers after the current token
    if (current_p_idx < pattern.len) {
        const quant = pattern[current_p_idx];
        if (quant == '*' or quant == '+' or quant == '?') {
            const next_pattern_idx = current_p_idx + 1;

            if (quant == '?') {
                // Try matching one
                if (i_idx < input.len and matchesToken(input[i_idx], p_char, is_escaped)) {
                    if (matchInternal(input, pattern, i_idx + 1, next_pattern_idx)) |res| return res;
                }
                // Try matching zero
                return matchInternal(input, pattern, i_idx, next_pattern_idx);
            }

            if (quant == '*') {
                // Greedy match zero or more
                var max_matches: usize = 0;
                while (i_idx + max_matches < input.len and matchesToken(input[i_idx + max_matches], p_char, is_escaped)) {
                    max_matches += 1;
                }

                while (true) {
                    if (matchInternal(input, pattern, i_idx + max_matches, next_pattern_idx)) |res| return res;
                    if (max_matches == 0) break;
                    max_matches -= 1;
                }
                return null;
            }

            if (quant == '+') {
                // Greedy match one or more
                var count: usize = 0;
                while (i_idx + count < input.len and matchesToken(input[i_idx + count], p_char, is_escaped)) {
                    count += 1;
                }
                if (count == 0) return null;

                while (count > 0) {
                    if (matchInternal(input, pattern, i_idx + count, next_pattern_idx)) |res| return res;
                    count -= 1;
                }
                return null;
            }
        }
    }

    // Single token match
    if (i_idx < input.len and matchesToken(input[i_idx], p_char, is_escaped)) {
        return matchInternal(input, pattern, i_idx + 1, current_p_idx);
    }

    return null;
}

fn matchesToken(c: u8, p_char: u8, is_escaped: bool) bool {
    if (is_escaped) {
        return switch (p_char) {
            'd' => std.ascii.isDigit(c),
            'w' => std.ascii.isAlphanumeric(c) or c == '_',
            's' => std.ascii.isWhitespace(c),
            'D' => !std.ascii.isDigit(c),
            'W' => !(std.ascii.isAlphanumeric(c) or c == '_'),
            'S' => !std.ascii.isWhitespace(c),
            else => c == p_char,
        };
    }
    if (p_char == '.') return true;
    return c == p_char;
}

/// Masks a string for redaction purposes.
/// Supports full masking, partial start/end, and middle masking.
pub fn maskString(
    allocator: std.mem.Allocator,
    value: []const u8,
    mask_char: u8,
    start_reveal: usize,
    end_reveal: usize,
    mode: enum { full, partial_start, partial_end, mask_middle },
) ![]u8 {
    if (mode == .full) {
        // Create a masked string of the same length as the input.
        const result = try allocator.alloc(u8, value.len);
        @memset(result, mask_char);
        return result;
    }

    if (mode == .partial_start) {
        if (value.len <= end_reveal) {
            const result = try allocator.alloc(u8, end_reveal);
            @memset(result, mask_char);
            return result;
        }
        const result = try allocator.alloc(u8, value.len);
        @memset(result[0 .. value.len - end_reveal], mask_char);
        @memcpy(result[value.len - end_reveal ..], value[value.len - end_reveal ..]);
        return result;
    }

    if (mode == .partial_end) {
        if (value.len <= start_reveal) {
            const result = try allocator.alloc(u8, start_reveal);
            @memset(result, mask_char);
            return result;
        }
        const result = try allocator.alloc(u8, value.len);
        @memcpy(result[0..start_reveal], value[0..start_reveal]);
        @memset(result[start_reveal..], mask_char);
        return result;
    }

    if (mode == .mask_middle) {
        const reveal = @min(start_reveal, 3);
        if (value.len <= reveal * 2) {
            const result = try allocator.alloc(u8, 3);
            @memset(result, mask_char);
            return result;
        }
        const result = try allocator.alloc(u8, value.len);
        @memcpy(result[0..reveal], value[0..reveal]);
        @memset(result[reveal .. value.len - reveal], mask_char);
        @memcpy(result[value.len - reveal ..], value[value.len - reveal ..]);
        return result;
    }

    return allocator.dupe(u8, value);
}

/// Computes a short SHA256 hash (first 8 bytes) formatted as hex.
/// Format: "[HASH:<16_char_hex>]"
pub fn computeRedactionHash(allocator: std.mem.Allocator, value: []const u8) ![]u8 {
    var hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(value, &hash, .{});
    const hex_val = std.fmt.bytesToHex(hash[0..8], .lower);
    return std.fmt.allocPrint(allocator, "[HASH:{s}]", .{hex_val});
}

/// Replaces all occurrences of a substring with a replacement string.
/// Allocates a new string for the result.
///
/// Performance: O(N) where N is output length.
pub fn replaceString(allocator: std.mem.Allocator, input: []const u8, needle: []const u8, replacement: []const u8) ![]u8 {
    const size = std.mem.replacementSize(u8, input, needle, replacement);
    const result = try allocator.alloc(u8, size);
    _ = std.mem.replace(u8, input, needle, replacement, result);
    return result;
}
/// Returns the file extension for a given compression algorithm.
/// Supports both CompressionConfig.CompressionAlgorithm and other similar enums.
///
/// Performance: O(1)
pub fn getCompressionExtension(algo: anytype) []const u8 {
    return switch (algo) {
        .deflate, .zlib, .raw_deflate, .gzip => Constants.CompressionConstants.ArchivingExtensions.gzip,
        .zstd => Constants.CompressionConstants.ArchivingExtensions.zstd,
        .lzma => Constants.CompressionConstants.ArchivingExtensions.lzma,
        .lzma2 => Constants.CompressionConstants.ArchivingExtensions.lzma2,
        .xz => Constants.CompressionConstants.ArchivingExtensions.xz,
        .tar_gz => Constants.CompressionConstants.ArchivingExtensions.tar_gz,
        .zip => Constants.CompressionConstants.ArchivingExtensions.zip,
        .lz4 => Constants.CompressionConstants.ArchivingExtensions.lz4,
        .none => Constants.CompressionConstants.ArchivingExtensions.none,
    };
}

test "getCompressionExtension" {
    const Algo = enum { none, deflate, zlib, raw_deflate, gzip, zstd, lzma, lzma2, xz, tar_gz, zip, lz4 };
    try std.testing.expectEqualStrings(".gz", getCompressionExtension(Algo.gzip));
    try std.testing.expectEqualStrings(".gz", getCompressionExtension(Algo.deflate));
    try std.testing.expectEqualStrings(".zst", getCompressionExtension(Algo.zstd));
    try std.testing.expectEqualStrings(".lzma", getCompressionExtension(Algo.lzma));
    try std.testing.expectEqualStrings(".xz", getCompressionExtension(Algo.xz));
    try std.testing.expectEqualStrings(".tar.gz", getCompressionExtension(Algo.tar_gz));
    try std.testing.expectEqualStrings(".zip", getCompressionExtension(Algo.zip));
    try std.testing.expectEqualStrings("", getCompressionExtension(Algo.none));
}

test "calculateErrorRate" {
    try std.testing.expectEqual(@as(f64, 0.0), calculateErrorRate(0, 0));
    try std.testing.expectEqual(@as(f64, 0.0), calculateErrorRate(0, 100));
    try std.testing.expectEqual(@as(f64, 0.1), calculateErrorRate(10, 100));
    try std.testing.expectEqual(@as(f64, 1.0), calculateErrorRate(100, 100));
}

test "calculateAverage" {
    try std.testing.expectEqual(@as(f64, 0.0), calculateAverage(0, 0));
    try std.testing.expectEqual(@as(f64, 50.0), calculateAverage(500, 10));
    try std.testing.expectEqual(@as(f64, 100.0), calculateAverage(100, 1));
}

test "safeFloatDiv" {
    try std.testing.expectEqual(@as(f64, 0.0), safeFloatDiv(100.0, 0.0));
    try std.testing.expectEqual(@as(f64, 2.0), safeFloatDiv(100.0, 50.0));
}

test "calculateBytesPerSecond" {
    try std.testing.expectEqual(@as(f64, 0.0), calculateBytesPerSecond(100, 0));
    try std.testing.expectEqual(@as(f64, 100.0), calculateBytesPerSecond(100, 1000));
}

/// LZMA hash function
pub fn lzmaHash(data: []const u8, len: usize) u14 {
    if (len < 2) return 0;
    var hash: u32 = 0;
    for (0..len) |i| {
        hash = (hash *% 31) +% data[i];
    }
    return @truncate(hash);
}

test "durationSinceNs" {
    const start = currentNanos();
    // Simple test - just verify duration is non-negative without sleep
    const duration = durationSinceNs(start);
    // Duration should be very small (microseconds to milliseconds) since we just started
    try std.testing.expect(duration < 1_000_000_000); // Less than 1 second
}
