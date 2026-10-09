//! Shared utilities.
//!
//! Time, formatting, parsing, IDs, and statistics helpers used across Logly.
const std = @import("std");
const builtin = @import("builtin");
const Constants = @import("constants.zig");

/// Stateless default single-threaded Io handle.
pub fn defaultIo() std.Io {
    const Holder = struct {
        var threaded = std.Io.Threaded.init_single_threaded;
    };
    return Holder.threaded.io();
}

/// Pure stateless default I/O accessor.
pub const io = defaultIo;

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
    var unitStart = end;
    while (unitStart < s.len and std.ascii.isWhitespace(s[unitStart])) : (unitStart += 1) {}

    if (unitStart >= s.len) return num; // Default to bytes if no unit

    const unit = s[unitStart..];

    // Supports B, KB, MB, GB, TB (case insensitive)
    if (std.ascii.eqlIgnoreCase(unit, "B")) return num;
    if (std.ascii.eqlIgnoreCase(unit, "K") or std.ascii.eqlIgnoreCase(unit, "KB")) return num * Constants.SizeConstants.bytesPerKb;
    if (std.ascii.eqlIgnoreCase(unit, "M") or std.ascii.eqlIgnoreCase(unit, "MB")) return num * Constants.SizeConstants.bytesPerMb;
    if (std.ascii.eqlIgnoreCase(unit, "G") or std.ascii.eqlIgnoreCase(unit, "GB")) return num * Constants.SizeConstants.bytesPerGb;
    if (std.ascii.eqlIgnoreCase(unit, "T") or std.ascii.eqlIgnoreCase(unit, "TB")) return num * Constants.SizeConstants.bytesPerTb;

    return num;
}

/// Writes a human-readable byte size to the writer.
pub fn writeSize(writer: anytype, bytes: u64) !void {
    const units = [][]const u8{ "B", "KB", "MB", "GB", "TB" };
    const bytesPerKbF: f64 = @floatFromInt(Constants.SizeConstants.bytesPerKb);
    var value: f64 = @floatFromInt(bytes);
    var unitIdx: usize = 0;

    while (value >= bytesPerKbF and unitIdx < units.len - 1) {
        value /= bytesPerKbF;
        unitIdx += 1;
    }

    if (unitIdx == 0) {
        try writer.print("{d} {s}", .{ bytes, units[unitIdx] });
    } else {
        try writer.print("{d:.2} {s}", .{ value, units[unitIdx] });
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
    var unitStart = end;
    while (unitStart < s.len and std.ascii.isWhitespace(s[unitStart])) : (unitStart += 1) {}

    if (unitStart >= s.len) return num; // Default to milliseconds if no unit

    const unit = s[unitStart..];

    if (std.ascii.eqlIgnoreCase(unit, "ms")) return num;
    if (std.ascii.eqlIgnoreCase(unit, "s")) return num * @as(i64, @intCast(Constants.TimeConstants.msPerSecond));
    if (std.ascii.eqlIgnoreCase(unit, "m")) return num * @as(i64, @intCast(Constants.TimeConstants.secondsPerMinute * Constants.TimeConstants.msPerSecond));
    if (std.ascii.eqlIgnoreCase(unit, "h")) return num * @as(i64, @intCast(Constants.TimeConstants.secondsPerHour * Constants.TimeConstants.msPerSecond));
    if (std.ascii.eqlIgnoreCase(unit, "d")) return num * @as(i64, @intCast(Constants.TimeConstants.secondsPerDay * Constants.TimeConstants.msPerSecond));

    return num;
}

/// Writes a human-readable duration to the writer.
pub fn writeDuration(writer: anytype, ms: i64) !void {
    const msPerSec = @as(i64, @intCast(Constants.TimeConstants.msPerSecond));
    const msPerMin = @as(i64, @intCast(Constants.TimeConstants.secondsPerMinute * Constants.TimeConstants.msPerSecond));
    const msPerHour = @as(i64, @intCast(Constants.TimeConstants.secondsPerHour * Constants.TimeConstants.msPerSecond));
    const msPerDay = @as(i64, @intCast(Constants.TimeConstants.secondsPerDay * Constants.TimeConstants.msPerSecond));

    if (ms < msPerSec) {
        try writer.print("{d}ms", .{ms});
    } else if (ms < msPerMin) {
        try writer.print("{d:.2}s", .{@as(f64, @floatFromInt(ms)) / @as(f64, @floatFromInt(msPerSec))});
    } else if (ms < msPerHour) {
        try writer.print("{d:.2}m", .{@as(f64, @floatFromInt(ms)) / @as(f64, @floatFromInt(msPerMin))});
    } else if (ms < msPerDay) {
        try writer.print("{d:.2}h", .{@as(f64, @floatFromInt(ms)) / @as(f64, @floatFromInt(msPerHour))});
    } else {
        try writer.print("{d:.2}d", .{@as(f64, @floatFromInt(ms)) / @as(f64, @floatFromInt(msPerDay))});
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
    const safeTs: u64 = if (timestamp < 0) 0 else @intCast(timestamp);
    const epoch = std.time.epoch.EpochSeconds{ .secs = safeTs };
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
    return fromEpochSeconds(@divFloor(timestamp, @as(i64, @intCast(Constants.TimeConstants.msPerSecond))));
}

/// Converts a civil date to days since Unix epoch (1970-01-01).
///
/// Uses Howard Hinnant's algorithm and performs only integer arithmetic.
fn daysFromCivil(year: i32, month: u8, day: u8) i64 {
    const y: i64 = @as(i64, @intCast(year));
    const m: i64 = @as(i64, @intCast(month));
    const d: i64 = @as(i64, @intCast(day));

    const adjustedYear = y - (if (m <= 2) @as(i64, 1) else @as(i64, 0));
    const era = @divFloor(if (adjustedYear >= 0) adjustedYear else adjustedYear - 399, 400);
    const yoe = adjustedYear - era * 400;
    const monthAdjusted = m + (if (m > 2) @as(i64, -3) else @as(i64, 9));
    const doy = @divFloor(153 * monthAdjusted + 2, 5) + d - 1;
    const doe = yoe * 365 + @divFloor(yoe, 4) - @divFloor(yoe, 100) + doy;

    return era * 146097 + doe - 719468;
}

/// Converts time components to epoch seconds.
///
/// Treats the components as a UTC-like civil instant.
fn epochSecondsFromComponents(tc: TimeComponents) i64 {
    const days = daysFromCivil(tc.year, tc.month, tc.day);
    const secondsInDay: i64 = @as(i64, @intCast(tc.hour)) * @as(i64, @intCast(Constants.TimeConstants.secondsPerHour)) +
        @as(i64, @intCast(tc.minute)) * @as(i64, @intCast(Constants.TimeConstants.secondsPerMinute)) +
        @as(i64, @intCast(tc.second));
    return days * @as(i64, @intCast(Constants.TimeConstants.secondsPerDay)) + secondsInDay;
}

/// Converts epoch seconds to local-time components via libc.
///
/// Returns `null` when libc or timezone APIs are unavailable.
fn localTimeComponentsFromLibc(timestampSeconds: i64) ?TimeComponents {
    if (!builtin.link_libc) return null;

    if (comptime (@hasDecl(std.c, "time_t") and @hasDecl(std.c, "tm"))) {
        var epochSeconds: std.c.time_t = @intCast(timestampSeconds);
        var localTm: std.c.tm = undefined;

        if (@hasDecl(std.c, "localtime_r")) {
            if (std.c.localtime_r(&epochSeconds, &localTm) == null) return null;
        } else if (@hasDecl(std.c, "localtime")) {
            const tmPtr = std.c.localtime(&epochSeconds);
            if (tmPtr == null) return null;
            localTm = tmPtr.*;
        } else {
            return null;
        }

        return .{
            .year = @as(i32, @intCast(localTm.tm_year + 1900)),
            .month = @as(u8, @intCast(localTm.tm_mon + 1)),
            .day = @as(u8, @intCast(localTm.tm_mday)),
            .hour = @as(u64, @intCast(localTm.tm_hour)),
            .minute = @as(u64, @intCast(localTm.tm_min)),
            .second = @as(u64, @intCast(localTm.tm_sec)),
        };
    }

    return null;
}

/// Extracts local-time components from a millisecond timestamp.
/// Falls back to UTC conversion when libc localtime support is unavailable.
pub fn fromMilliTimestampLocal(timestamp: i64) TimeComponents {
    const safeSeconds = @divFloor(if (timestamp < 0) 0 else timestamp, @as(i64, @intCast(Constants.TimeConstants.msPerSecond)));
    if (localTimeComponentsFromLibc(safeSeconds)) |tc| {
        return tc;
    }
    return fromEpochSeconds(safeSeconds);
}

/// Returns local UTC offset in minutes for a millisecond timestamp.
/// Returns 0 when local timezone conversion is unavailable.
pub fn localUtcOffsetMinutes(timestamp: i64) i16 {
    const safeSeconds = @divFloor(if (timestamp < 0) 0 else timestamp, @as(i64, @intCast(Constants.TimeConstants.msPerSecond)));
    const localTc = localTimeComponentsFromLibc(safeSeconds) orelse return 0;

    const localAsUtcSeconds = epochSecondsFromComponents(localTc);
    const offsetMinutes = @divTrunc(localAsUtcSeconds - safeSeconds, @as(i64, @intCast(Constants.TimeConstants.secondsPerMinute)));

    const minOffset = @as(i64, Constants.TimeConstants.minUtcOffsetMinutes);
    const maxOffset = @as(i64, Constants.TimeConstants.maxUtcOffsetMinutes);
    const bounded = std.math.clamp(offsetMinutes, minOffset, maxOffset);

    return @as(i16, @intCast(bounded));
}

fn splitUtcOffsetMinutes(offsetMinutes: i16) struct { sign: u8, hours: u16, minutes: u16 } {
    const clampedOffset = std.math.clamp(offsetMinutes, Constants.TimeConstants.minUtcOffsetMinutes, Constants.TimeConstants.maxUtcOffsetMinutes);
    const sign: u8 = if (clampedOffset < 0) '-' else '+';
    const absMinutesI32: i32 = if (clampedOffset < 0)
        -@as(i32, clampedOffset)
    else
        @as(i32, clampedOffset);
    const absMinutesU16: u16 = @intCast(absMinutesI32);
    const minutesPerHour: u16 = Constants.TimeConstants.minutesPerHour;

    return .{
        .sign = sign,
        .hours = @divFloor(absMinutesU16, minutesPerHour),
        .minutes = @mod(absMinutesU16, minutesPerHour),
    };
}

/// Writes a UTC offset in `+HH:MM` or `-HH:MM` format.
///
/// The offset is expressed in minutes and is clamped by callers to a safe range.
pub fn writeUtcOffset(writer: anytype, offsetMinutes: i16) !void {
    const offsetParts = splitUtcOffsetMinutes(offsetMinutes);

    try writer.writeByte(offsetParts.sign);
    try write2Digits(writer, offsetParts.hours);
    try writer.writeByte(':');
    try write2Digits(writer, offsetParts.minutes);
}

/// Writes a compact UTC offset in `+HHMM` or `-HHMM` format.
pub fn writeUtcOffsetCompact(writer: anytype, offsetMinutes: i16) !void {
    const offsetParts = splitUtcOffsetMinutes(offsetMinutes);

    try writer.writeByte(offsetParts.sign);
    try write2Digits(writer, offsetParts.hours);
    try write2Digits(writer, offsetParts.minutes);
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
pub fn sleepNs(durationNs: u64) void {
    const duration = std.Io.Duration.fromNanoseconds(@as(i96, @intCast(durationNs)));
    _ = std.Io.sleep(io(), duration, .awake) catch {};
}

/// Sleeps for the specified duration in milliseconds.
pub fn sleepMs(durationMs: u64) void {
    sleepNs(durationMs * Constants.TimeConstants.nsPerMs);
}

/// Whether stdout refers to an interactive terminal.
///
/// Never fails; returns false on any error (including missing TTY support
/// on the platform). Used to gate automatic console coloring: piped,
/// redirected, and CI output stays plain unless colors are explicitly
/// forced. Pure query with no shared state; safe from any thread.
pub fn stdoutIsTty() bool {
    return std.Io.File.stdout().isTty(io()) catch false;
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
    return timestamp - @as(i64, @intCast(tc.hour * Constants.TimeConstants.secondsPerHour + tc.minute * Constants.TimeConstants.secondsPerMinute + tc.second));
}

/// Returns the start of the current hour as epoch seconds.
pub fn startOfHour(timestamp: i64) i64 {
    const tc = fromEpochSeconds(timestamp);
    return timestamp - @as(i64, @intCast(tc.minute * Constants.TimeConstants.secondsPerMinute + tc.second));
}

/// Returns monotonic milliseconds (saturating on overflow).
///
/// Use for durations, timeouts, intervals, and uptime. Immune to
/// wall-clock jumps (NTP, DST, manual changes). For calendar timestamps
/// shown to users, use `currentMillis` instead.
pub fn monotonicMillis() i64 {
    const ns = nowMonotonic().toNanoseconds();
    const ms = @divFloor(ns, @as(i96, 1_000_000));
    const clamped = std.math.clamp(ms, @as(i96, std.math.minInt(i64)), @as(i96, std.math.maxInt(i64)));
    return @intCast(clamped);
}

/// Calculates elapsed milliseconds since a monotonic start time.
///
/// Both this call and `startTime` must use the monotonic clock
/// (`monotonicMillis`). Never pass wall-clock timestamps here;
/// wall-clock jumps would corrupt the result. Returns 0 on backward jump
/// (defensive; monotonic time should never go backward).
pub fn elapsedMs(startTime: i64) u64 {
    const nowTime = monotonicMillis();
    if (nowTime < startTime) return 0;
    return @intCast(nowTime - startTime);
}

/// Calculates elapsed time in seconds since start_time.
pub fn elapsedSeconds(startTime: i64) u64 {
    return elapsedMs(startTime) / Constants.TimeConstants.msPerSecond;
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
pub fn formatDatePatternWithOffset(writer: anytype, fmt: []const u8, year: i32, month: u8, day: u8, hour: u64, minute: u64, second: u64, millis: u64, timezoneOffsetMinutes: i16) !void {
    return formatDatePatternInternal(writer, fmt, year, month, day, hour, minute, second, millis, timezoneOffsetMinutes);
}

fn formatDatePatternInternal(writer: anytype, fmt: []const u8, year: i32, month: u8, day: u8, hour: u64, minute: u64, second: u64, millis: u64, timezoneOffsetMinutes: ?i16) !void {
    var i: usize = 0;
    while (i < fmt.len) {
        if (i + 4 <= fmt.len and std.mem.eql(u8, fmt[i .. i + 4], "YYYY")) {
            try write4Digits(writer, year);
            i += 4;
        } else if (i + 2 <= fmt.len and std.mem.eql(u8, fmt[i .. i + 2], "YY")) {
            try write2Digits(writer, @mod(year, 100));
            i += 2;
        } else if (i + 3 <= fmt.len and std.mem.eql(u8, fmt[i .. i + 3], "ZZZ")) {
            if (timezoneOffsetMinutes) |offset| {
                try writeUtcOffset(writer, offset);
            } else {
                try writer.writeAll("ZZZ");
            }
            i += 3;
        } else if (i + 2 <= fmt.len and std.mem.eql(u8, fmt[i .. i + 2], "ZZ")) {
            if (timezoneOffsetMinutes) |offset| {
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
pub fn formatDateToBufWithOffset(buf: []u8, fmt: []const u8, year: i32, month: u8, day: u8, hour: u64, minute: u64, second: u64, millis: u64, timezoneOffsetMinutes: i16) ![]u8 {
    var writer = std.Io.Writer.fixed(buf);
    try formatDatePatternWithOffset(&writer, fmt, year, month, day, hour, minute, second, millis, timezoneOffsetMinutes);
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

/// Safely converts a signed integer to unsigned, returning 0 for negative values.
pub fn safeToUnsigned(comptime T: type, value: anytype) T {
    if (value < 0) return 0;
    return @intCast(value);
}

/// Escapes a string for safe inclusion in JSON output.
/// Handles all JSON special characters including control characters.
///
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
pub fn escapeJsonStringToBuf(buf: []u8, s: []const u8) ![]u8 {
    var writer = std.Io.Writer.fixed(buf);
    try escapeJsonString(&writer, s);
    return buf[0..writer.end];
}

/// Calculates a rate as a floating-point ratio (0.0 - 1.0).
/// Safely handles division by zero by returning 0.
pub fn calculateRate(numerator: u64, denominator: u64) f64 {
    if (denominator == 0) return 0.0;
    return @as(f64, @floatFromInt(numerator)) / @as(f64, @floatFromInt(denominator));
}

/// Calculates a percentage (0.0 - 100.0).
/// Safely handles division by zero by returning 0.
pub fn calculatePercentage(numerator: u64, denominator: u64) f64 {
    return calculateRate(numerator, denominator) * 100.0;
}

/// Calculates throughput (items per second) given a count and elapsed time.
pub fn calculateThroughput(count: u64, elapsedNs: u64) f64 {
    if (elapsedNs == 0) return 0.0;
    const nsPerSec = @as(f64, @floatFromInt(Constants.TimeConstants.nsPerSecond));
    const seconds = @as(f64, @floatFromInt(elapsedNs)) / nsPerSec;
    return @as(f64, @floatFromInt(count)) / seconds;
}

/// Calculates throughput in milliseconds.
pub fn calculateThroughputMs(count: u64, durationMs: i64) f64 {
    if (durationMs <= 0) return 0.0;
    const seconds = @as(f64, @floatFromInt(durationMs)) / @as(f64, @floatFromInt(Constants.TimeConstants.msPerSecond));
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
    try std.testing.expectEqual(@as(f64, 100.0), calculateThroughput(100, Constants.TimeConstants.nsPerSecond));
    // 0 elapsed time = 0 throughput
    try std.testing.expectEqual(@as(f64, 0.0), calculateThroughput(100, 0));
}

test "parseSize bytes" {
    try std.testing.expectEqual(@as(?u64, Constants.SizeConstants.bytesPerKb), parseSize("1024"));
    try std.testing.expectEqual(@as(?u64, 100), parseSize("100B"));
}

test "parseSize kilobytes" {
    try std.testing.expectEqual(@as(?u64, Constants.SizeConstants.bytesPerKb), parseSize("1KB"));
    try std.testing.expectEqual(@as(?u64, Constants.SizeConstants.bytesPerKb), parseSize("1K"));
    try std.testing.expectEqual(@as(?u64, 10 * Constants.SizeConstants.bytesPerKb), parseSize("10KB"));
}

test "parseSize megabytes" {
    try std.testing.expectEqual(@as(?u64, Constants.SizeConstants.bytesPerMb), parseSize("1MB"));
    try std.testing.expectEqual(@as(?u64, Constants.SizeConstants.bytesPerMb), parseSize("1M"));
}

test "parseSize gigabytes" {
    try std.testing.expectEqual(@as(?u64, Constants.SizeConstants.bytesPerGb), parseSize("1GB"));
    try std.testing.expectEqual(@as(?u64, Constants.SizeConstants.bytesPerGb), parseSize("1G"));
}

test "parseSize with whitespace" {
    try std.testing.expectEqual(@as(?u64, 10 * Constants.SizeConstants.bytesPerMb), parseSize("10 MB"));
}

test "parseSize invalid" {
    try std.testing.expectEqual(@as(?u64, null), parseSize(""));
    try std.testing.expectEqual(@as(?u64, null), parseSize("invalid"));
}

test "parseDuration" {
    try std.testing.expectEqual(@as(?i64, @intCast(Constants.TimeConstants.msPerSecond)), parseDuration("1000ms"));
    try std.testing.expectEqual(@as(?i64, @intCast(30 * Constants.TimeConstants.msPerSecond)), parseDuration("30s"));
    try std.testing.expectEqual(@as(?i64, @intCast(5 * Constants.TimeConstants.secondsPerMinute * Constants.TimeConstants.msPerSecond)), parseDuration("5m"));
    try std.testing.expectEqual(@as(?i64, @intCast(2 * Constants.TimeConstants.secondsPerHour * Constants.TimeConstants.msPerSecond)), parseDuration("2h"));
    const oneDayMs = @as(i64, @intCast(Constants.TimeConstants.secondsPerDay * Constants.TimeConstants.msPerSecond));
    try std.testing.expectEqual(@as(?i64, oneDayMs), parseDuration("1d"));
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
    try std.testing.expect(offset >= Constants.TimeConstants.minUtcOffsetMinutes and offset <= Constants.TimeConstants.maxUtcOffsetMinutes);
}

test "isSameDay" {
    try std.testing.expect(isSameDay(1735689600, 1735689600 + @as(i64, @intCast(Constants.TimeConstants.secondsPerHour))));
    try std.testing.expect(!isSameDay(1735689600, 1735689600 + @as(i64, @intCast(Constants.TimeConstants.secondsPerDay))));
}

test "clamp" {
    try std.testing.expectEqual(@as(i32, 5), std.math.clamp(@as(i32, 3), 5, 10));
    try std.testing.expectEqual(@as(i32, 10), std.math.clamp(@as(i32, 15), 5, 10));
    try std.testing.expectEqual(@as(i32, 7), std.math.clamp(@as(i32, 7), 5, 10));
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
    try writer.print("{x:0>4}", .{value});
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
    const hex = std.fmt.bytesToHex(bytes, .lower);
    return allocator.dupe(u8, &hex);
}

/// Generates a random 64-bit Span ID as a hex string (16 chars).
/// Allocator is required to allocate the string.
pub fn generateSpanId(allocator: std.mem.Allocator) ![]u8 {
    var bytes: [8]u8 = undefined;
    io().random(&bytes);
    const hex = std.fmt.bytesToHex(bytes, .lower);
    return allocator.dupe(u8, &hex);
}

/// Parsed W3C traceparent context.
pub const TraceparentContext = struct {
    version: []const u8,
    traceId: []const u8,
    spanId: []const u8,
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
    const traceId = header[3..35];
    const spanId = header[36..52];
    const flags = header[53..55];

    if (!isHexSlice(version) or !isHexSlice(traceId) or !isHexSlice(spanId) or !isHexSlice(flags)) {
        return null;
    }

    if (isAllZerosHex(traceId) or isAllZerosHex(spanId)) {
        return null;
    }

    const flagsByte = std.fmt.parseInt(u8, flags, 16) catch return null;

    return .{
        .version = version,
        .traceId = traceId,
        .spanId = spanId,
        .flags = flags,
        .sampled = (flagsByte & 0x01) == 0x01,
    };
}

/// Formats a W3C `traceparent` header string.
pub fn formatTraceparentHeader(allocator: std.mem.Allocator, traceId: []const u8, spanId: []const u8, sampled: bool) ![]u8 {
    if (traceId.len != 32 or !isHexSlice(traceId) or isAllZerosHex(traceId)) {
        return TraceparentError.InvalidTraceId;
    }

    if (spanId.len != 16 or !isHexSlice(spanId) or isAllZerosHex(spanId)) {
        return TraceparentError.InvalidSpanId;
    }

    const flags = if (sampled) "01" else "00";
    return std.fmt.allocPrint(allocator, "00-{s}-{s}-{s}", .{ traceId, spanId, flags });
}

/// Determines if a trace should be sampled based on the sampling rate.
/// rate: 0.0 to 1.0 (0% to 100%)
pub fn shouldSample(rate: f64) bool {
    if (rate >= 1.0) return true;
    if (rate <= 0.0) return false;
    const rngImpl: std.Random.IoSource = .{ .io = io() };
    const rng = rngImpl.interface();
    return rng.float(f64) < rate;
}

test "generateTraceId" {
    const allocator = std.testing.allocator;
    const traceId = try generateTraceId(allocator);
    defer allocator.free(traceId);
    try std.testing.expectEqual(traceId.len, 32);
}

test "generateSpanId" {
    const allocator = std.testing.allocator;
    const spanId = try generateSpanId(allocator);
    defer allocator.free(spanId);
    try std.testing.expectEqual(spanId.len, 16);
}

test "parseTraceparentHeader valid and sampled" {
    const ctx = parseTraceparentHeader("00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01");
    try std.testing.expect(ctx != null);
    try std.testing.expectEqualStrings("00", ctx.?.version);
    try std.testing.expectEqualStrings("4bf92f3577b34da6a3ce929d0e0e4736", ctx.?.traceId);
    try std.testing.expectEqualStrings("00f067aa0ba902b7", ctx.?.spanId);
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
pub fn calculateErrorRate(errors: u64, total: u64) f64 {
    if (total == 0) return 0.0;
    return @as(f64, @floatFromInt(errors)) / @as(f64, @floatFromInt(total));
}

/// Calculates an average value from a sum and count.
/// Safely handles division by zero.
pub fn calculateAverage(sum: u64, count: u64) f64 {
    if (count == 0) return 0.0;
    return @as(f64, @floatFromInt(sum)) / @as(f64, @floatFromInt(count));
}

/// Safe floating-point division that returns 0.0 for division by zero.
pub fn safeFloatDiv(numerator: f64, denominator: f64) f64 {
    if (denominator == 0.0) return 0.0;
    return numerator / denominator;
}

/// Loads a u64 value from an atomic counter, handling different atomic unsigned types.
/// This is useful for cross-platform compatibility where atomic types vary.
pub fn atomicLoadU64(atomic: anytype) u64 {
    return @as(u64, atomic.load(.monotonic));
}

/// Calculates bytes per second throughput.
pub fn calculateThroughputBytes(bytes: u64, durationMs: i64) f64 {
    return calculateBytesPerSecond(bytes, durationMs);
}

/// Calculates CRC32 checksum of data.
/// Uses standard IEEE polynomial.
pub fn calculateCRC32(data: []const u8) u32 {
    return std.hash.Crc32.hash(data);
}

/// Calculates bytes per second throughput from bytes and elapsed milliseconds.
pub fn calculateBytesPerSecond(bytes: u64, durationMs: i64) f64 {
    if (durationMs <= 0) return 0.0;
    const seconds = @as(f64, @floatFromInt(durationMs)) / @as(f64, @floatFromInt(Constants.TimeConstants.msPerSecond));
    return @as(f64, @floatFromInt(bytes)) / seconds;
}

/// Calculates records per second throughput.
pub fn calculateRecordsPerSecond(records: u64, durationMs: i64) f64 {
    return calculateBytesPerSecond(records, durationMs);
}

/// Creates a nanosecond duration from a start time to now.
pub fn durationSinceNs(startTime: i128) u64 {
    const now = currentNanos();
    if (now < startTime) return 0;
    return @intCast(@max(0, now - startTime));
}

/// Formats a nanosecond duration to a human-readable string.
pub fn writeDurationNs(writer: anytype, ns: u64) !void {
    const nsPerUs = Constants.TimeConstants.nsPerUs;
    const nsPerMs = Constants.TimeConstants.nsPerMs;
    const nsPerSec = Constants.TimeConstants.nsPerSecond;

    if (ns < nsPerUs) {
        try writer.print("{d}ns", .{ns});
    } else if (ns < nsPerMs) {
        try writer.print("{d:.2}µs", .{@as(f64, @floatFromInt(ns)) / @as(f64, @floatFromInt(nsPerUs))});
    } else if (ns < nsPerSec) {
        try writer.print("{d:.2}ms", .{@as(f64, @floatFromInt(ns)) / @as(f64, @floatFromInt(nsPerMs))});
    } else {
        try writer.print("{d:.2}s", .{@as(f64, @floatFromInt(ns)) / @as(f64, @floatFromInt(nsPerSec))});
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
        if (matchInternal(input, pattern, i, 0)) |endIdx| {
            return input[i..endIdx];
        }
    }
    return null;
}

fn matchInternal(input: []const u8, pattern: []const u8, iIdx: usize, pIdx: usize) ?usize {
    if (pIdx == pattern.len) return iIdx;

    // Handle special case: * or + at the very beginning or after another quantifier
    // Treat as matching ANY character (.)
    var pChar: u8 = undefined;
    var isEscaped = false;
    var currentPIdx = pIdx;

    if (pattern[pIdx] == '\\' and pIdx + 1 < pattern.len) {
        isEscaped = true;
        pChar = pattern[pIdx + 1];
        currentPIdx += 2;
    } else {
        pChar = pattern[pIdx];
        currentPIdx += 1;
    }

    // Check for quantifiers after the current token
    if (currentPIdx < pattern.len) {
        const quant = pattern[currentPIdx];
        if (quant == '*' or quant == '+' or quant == '?') {
            const nextPatternIdx = currentPIdx + 1;

            if (quant == '?') {
                // Try matching one
                if (iIdx < input.len and matchesToken(input[iIdx], pChar, isEscaped)) {
                    if (matchInternal(input, pattern, iIdx + 1, nextPatternIdx)) |res| return res;
                }
                // Try matching zero
                return matchInternal(input, pattern, iIdx, nextPatternIdx);
            }

            if (quant == '*') {
                // Greedy match zero or more
                var maxMatches: usize = 0;
                while (iIdx + maxMatches < input.len and matchesToken(input[iIdx + maxMatches], pChar, isEscaped)) {
                    maxMatches += 1;
                }

                while (true) {
                    if (matchInternal(input, pattern, iIdx + maxMatches, nextPatternIdx)) |res| return res;
                    if (maxMatches == 0) break;
                    maxMatches -= 1;
                }
                return null;
            }

            if (quant == '+') {
                // Greedy match one or more
                var count: usize = 0;
                while (iIdx + count < input.len and matchesToken(input[iIdx + count], pChar, isEscaped)) {
                    count += 1;
                }
                if (count == 0) return null;

                while (count > 0) {
                    if (matchInternal(input, pattern, iIdx + count, nextPatternIdx)) |res| return res;
                    count -= 1;
                }
                return null;
            }
        }
    }

    // Single token match
    if (iIdx < input.len and matchesToken(input[iIdx], pChar, isEscaped)) {
        return matchInternal(input, pattern, iIdx + 1, currentPIdx);
    }

    return null;
}

fn matchesToken(c: u8, pChar: u8, isEscaped: bool) bool {
    if (isEscaped) {
        return switch (pChar) {
            'd' => std.ascii.isDigit(c),
            'w' => std.ascii.isAlphanumeric(c) or c == '_',
            's' => std.ascii.isWhitespace(c),
            'D' => !std.ascii.isDigit(c),
            'W' => !(std.ascii.isAlphanumeric(c) or c == '_'),
            'S' => !std.ascii.isWhitespace(c),
            else => c == pChar,
        };
    }
    if (pChar == '.') return true;
    return c == pChar;
}

/// Masks a string for redaction purposes.
/// Supports full masking, partial start/end, and middle masking.
pub fn maskString(
    allocator: std.mem.Allocator,
    value: []const u8,
    maskChar: u8,
    startReveal: usize,
    endReveal: usize,
    mode: enum { full, partialStart, partialEnd, maskMiddle },
) ![]u8 {
    if (mode == .full) {
        // Create a masked string of the same length as the input.
        const result = try allocator.alloc(u8, value.len);
        @memset(result, maskChar);
        return result;
    }

    if (mode == .partialStart) {
        if (value.len <= endReveal) {
            const result = try allocator.alloc(u8, endReveal);
            @memset(result, maskChar);
            return result;
        }
        const result = try allocator.alloc(u8, value.len);
        @memset(result[0 .. value.len - endReveal], maskChar);
        @memcpy(result[value.len - endReveal ..], value[value.len - endReveal ..]);
        return result;
    }

    if (mode == .partialEnd) {
        if (value.len <= startReveal) {
            const result = try allocator.alloc(u8, startReveal);
            @memset(result, maskChar);
            return result;
        }
        const result = try allocator.alloc(u8, value.len);
        @memcpy(result[0..startReveal], value[0..startReveal]);
        @memset(result[startReveal..], maskChar);
        return result;
    }

    if (mode == .maskMiddle) {
        const reveal = @min(startReveal, 3);
        if (value.len <= reveal * 2) {
            const result = try allocator.alloc(u8, 3);
            @memset(result, maskChar);
            return result;
        }
        const result = try allocator.alloc(u8, value.len);
        @memcpy(result[0..reveal], value[0..reveal]);
        @memset(result[reveal .. value.len - reveal], maskChar);
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
    const hexVal = try bytesToHexLowerAlloc(allocator, hash[0..8]);
    defer allocator.free(hexVal);
    return std.fmt.allocPrint(allocator, "[HASH:{s}]", .{hexVal});
}

/// Converts bytes to a lowercase hexadecimal string using the provided allocator.
pub fn bytesToHexLowerAlloc(allocator: std.mem.Allocator, bytes: []const u8) ![]u8 {
    // std.fmt.bytesToHex needs a comptime length; for runtime slices,
    // encode manually (hex digits only, no allocation beyond output).
    const hexDigits = "0123456789abcdef";
    const out = try allocator.alloc(u8, bytes.len * 2);
    for (bytes, 0..) |b, i| {
        out[i * 2] = hexDigits[b >> 4];
        out[i * 2 + 1] = hexDigits[b & 0x0f];
    }
    return out;
}

/// Returns true when a byte is safe in an exported telemetry metric name.
///
/// Uses the portable Prometheus/OpenTelemetry subset: ASCII letters, digits,
/// underscore, and colon. Dots, dashes, spaces, and path separators are not
/// accepted because they can break Prometheus text output.
pub fn isTelemetryMetricNameChar(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_' or c == ':';
}

/// Writes a telemetry metric name with optional prefixing and sanitization.
///
/// When sanitization is enabled, unsupported bytes are replaced with `_` and
/// an initial digit is protected by a leading `_`. This lets JSON, Prometheus,
/// and future OTLP exporters share one consistent name policy.
pub fn writeTelemetryMetricName(
    writer: anytype,
    prefix: []const u8,
    separator: []const u8,
    name: []const u8,
    sanitize: bool,
) !void {
    var wroteAny = false;
    if (prefix.len > 0) {
        try writeTelemetryMetricNamePart(writer, prefix, sanitize, &wroteAny);
        if (separator.len > 0 and name.len > 0) {
            try writeTelemetryMetricNamePart(writer, separator, sanitize, &wroteAny);
        }
    }
    try writeTelemetryMetricNamePart(writer, name, sanitize, &wroteAny);
}

/// Writes a Prometheus label value with the minimal required escaping.
///
/// Escapes backslash, quote, and newline so arbitrary sink names and other
/// user-provided labels remain valid in text exposition output.
pub fn writePrometheusLabelValue(writer: anytype, value: []const u8) !void {
    try writer.writeByte('"');
    for (value) |c| {
        switch (c) {
            '\\' => try writer.writeAll("\\\\"),
            '"' => try writer.writeAll("\\\""),
            '\n' => try writer.writeAll("\\n"),
            else => try writer.writeByte(c),
        }
    }
    try writer.writeByte('"');
}

fn writeTelemetryMetricNamePart(writer: anytype, part: []const u8, sanitize: bool, wroteAny: *bool) !void {
    for (part) |c| {
        if (!sanitize) {
            try writer.writeByte(c);
            wroteAny.* = true;
            continue;
        }

        if (!wroteAny.* and std.ascii.isDigit(c)) {
            try writer.writeByte('_');
            wroteAny.* = true;
        }

        try writer.writeByte(if (isTelemetryMetricNameChar(c)) c else '_');
        wroteAny.* = true;
    }
}

/// Replaces all occurrences of a substring with a replacement string.
/// Allocates a new string for the result.
pub fn replaceString(allocator: std.mem.Allocator, input: []const u8, needle: []const u8, replacement: []const u8) ![]u8 {
    const size = std.mem.replacementSize(u8, input, needle, replacement);
    const result = try allocator.alloc(u8, size);
    _ = std.mem.replace(u8, input, needle, replacement, result);
    return result;
}
/// Returns the file extension for a given compression algorithm.
/// Supports both CompressionConfig.CompressionAlgorithm and other similar enums.
pub fn getCompressionExtension(algo: anytype) []const u8 {
    return switch (algo) {
        .deflate, .zlib, .rawDeflate, .gzip => Constants.CompressionConstants.ArchivingExtensions.gzip,
        .zstd => Constants.CompressionConstants.ArchivingExtensions.zstd,
        .lzma => Constants.CompressionConstants.ArchivingExtensions.lzma,
        .lzma2 => Constants.CompressionConstants.ArchivingExtensions.lzma2,
        .xz => Constants.CompressionConstants.ArchivingExtensions.xz,
        .tarGz => Constants.CompressionConstants.ArchivingExtensions.tarGz,
        .zip => Constants.CompressionConstants.ArchivingExtensions.zip,
        .lz4 => Constants.CompressionConstants.ArchivingExtensions.lz4,
        .brotli => Constants.CompressionConstants.ArchivingExtensions.brotli,
        .none => Constants.CompressionConstants.ArchivingExtensions.none,
    };
}

test "getCompressionExtension" {
    const Algo = enum { none, deflate, zlib, rawDeflate, gzip, zstd, lzma, lzma2, xz, tarGz, zip, lz4, brotli };
    try std.testing.expectEqualStrings(".gz", getCompressionExtension(Algo.gzip));
    try std.testing.expectEqualStrings(".gz", getCompressionExtension(Algo.deflate));
    try std.testing.expectEqualStrings(".zst", getCompressionExtension(Algo.zstd));
    try std.testing.expectEqualStrings(".lzma", getCompressionExtension(Algo.lzma));
    try std.testing.expectEqualStrings(".xz", getCompressionExtension(Algo.xz));
    try std.testing.expectEqualStrings(".tar.gz", getCompressionExtension(Algo.tarGz));
    try std.testing.expectEqualStrings(".zip", getCompressionExtension(Algo.zip));
    try std.testing.expectEqualStrings(".br", getCompressionExtension(Algo.brotli));
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
    try std.testing.expectEqual(@as(f64, 100.0), calculateBytesPerSecond(100, @intCast(Constants.TimeConstants.msPerSecond)));
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
    try std.testing.expect(duration < Constants.TimeConstants.nsPerSecond); // Less than 1 second
}

test "writeTelemetryMetricName sanitizes and prefixes" {
    var buf = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer buf.deinit();

    try writeTelemetryMetricName(&buf.writer, "api.v1", "_", "http.requests-total", true);
    try std.testing.expectEqualStrings("api_v1_http_requests_total", buf.written());
}

test "writeTelemetryMetricName preserves raw names when disabled" {
    var buf = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer buf.deinit();

    try writeTelemetryMetricName(&buf.writer, "", "_", "99.raw.metric", false);
    try std.testing.expectEqualStrings("99.raw.metric", buf.written());
}

test "writeTelemetryMetricName protects leading digits" {
    var buf = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer buf.deinit();

    try writeTelemetryMetricName(&buf.writer, "", "_", "99.requests", true);
    try std.testing.expectEqualStrings("_99_requests", buf.written());
}

test "writePrometheusLabelValue escapes unsafe bytes" {
    var buf = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer buf.deinit();

    try writePrometheusLabelValue(&buf.writer, "file\"sink\\main\nnext");
    try std.testing.expectEqualStrings("\"file\\\"sink\\\\main\\nnext\"", buf.written());
}

/// Truncates a string to at most `max_len` bytes, appending `suffix` if truncated.
/// Returns a newly-allocated slice that the caller must free.
pub fn truncateString(allocator: std.mem.Allocator, s: []const u8, maxLen: usize, suffix: []const u8) ![]u8 {
    if (s.len <= maxLen) return allocator.dupe(u8, s);
    const available = if (maxLen > suffix.len) maxLen - suffix.len else 0;
    const result = try allocator.alloc(u8, available + suffix.len);
    @memcpy(result[0..available], s[0..available]);
    @memcpy(result[available..], suffix);
    return result;
}

/// Truncates a string to at most `max_len` bytes writing to writer, appending `suffix` if truncated.
pub fn writeTruncated(writer: anytype, s: []const u8, maxLen: usize, suffix: []const u8) !void {
    if (s.len <= maxLen) {
        try writer.writeAll(s);
        return;
    }
    const available = if (maxLen > suffix.len) maxLen - suffix.len else 0;
    try writer.writeAll(s[0..available]);
    try writer.writeAll(suffix);
}

/// FNV-1a 32-bit hash of a byte slice. Fast non-cryptographic hash.
/// Suitable for sampling keys, module name hashing, etc.
pub fn hashFnv32a(data: []const u8) u32 {
    return std.hash.Fnv1a_32.hash(data);
}

/// FNV-1a 64-bit hash of a byte slice.
pub fn hashFnv64a(data: []const u8) u64 {
    return std.hash.Fnv1a_64.hash(data);
}

/// Normalizes a path for cross-platform use (replaces backslashes with forward slashes).
pub fn sanitizePath(buf: []u8, path: []const u8) []u8 {
    const len = @min(buf.len, path.len);
    @memcpy(buf[0..len], path[0..len]);
    for (buf[0..len]) |*c| {
        if (c.* == '\\') c.* = '/';
    }
    return buf[0..len];
}

/// Builds a file path from a directory and filename, using the platform path separator.
/// Returns allocated slice (caller must free).
pub fn buildPath(allocator: std.mem.Allocator, dir: []const u8, file: []const u8) ![]u8 {
    const sep = std.fs.path.sep_str;
    return std.fmt.allocPrint(allocator, "{s}{s}{s}", .{ dir, sep, file });
}

/// Converts a string to snake_case by replacing non-alphanumeric chars with underscores.
/// Writes to the provided writer.
pub fn writeSnakeCase(writer: anytype, s: []const u8) !void {
    for (s) |c| {
        if (std.ascii.isAlphanumeric(c)) {
            try writer.writeByte(std.ascii.toLower(c));
        } else {
            try writer.writeByte('_');
        }
    }
}

/// Converts a string to camelCase: first word lowercase, subsequent words capitalized.
/// Writes to the provided writer.
pub fn writeCamelCase(writer: anytype, s: []const u8) !void {
    var capitalizeNext = false;
    var first = true;
    for (s) |c| {
        if (c == '_' or c == '-' or c == ' ') {
            capitalizeNext = true;
        } else if (first) {
            try writer.writeByte(std.ascii.toLower(c));
            first = false;
            capitalizeNext = false;
        } else if (capitalizeNext) {
            try writer.writeByte(std.ascii.toUpper(c));
            capitalizeNext = false;
            first = false;
        } else {
            try writer.writeByte(c);
            first = false;
        }
    }
}

/// Writes a compact JSON object with key-value pairs to the writer.
/// Opens '{', writes each pair as `"key":value`, closes '}'.
/// `pairs` is a slice of [2][]const u8 where [0]=key and [1]=value (value is written as JSON string).
pub fn writeJsonObject(writer: anytype, pairs: []const [2][]const u8) !void {
    try writer.writeByte('{');
    for (pairs, 0..) |pair, i| {
        if (i > 0) try writer.writeByte(',');
        try writer.writeByte('"');
        try escapeJsonString(writer, pair[0]);
        try writer.writeAll("\": \"");
        try escapeJsonString(writer, pair[1]);
        try writer.writeByte('"');
    }
    try writer.writeByte('}');
}

/// Pads a string to `width` characters on the right with `pad_char`.
/// If the string is longer than width, it is written as-is.
pub fn writePaddedRight(writer: anytype, s: []const u8, width: usize, padChar: u8) !void {
    try writer.writeAll(s);
    if (s.len < width) {
        const padLen = width - s.len;
        for (0..padLen) |_| {
            try writer.writeByte(padChar);
        }
    }
}

/// Pads a string to `width` characters on the left with `pad_char`.
/// If the string is longer than width, it is written as-is.
pub fn writePaddedLeft(writer: anytype, s: []const u8, width: usize, padChar: u8) !void {
    if (s.len < width) {
        const padLen = width - s.len;
        for (0..padLen) |_| {
            try writer.writeByte(padChar);
        }
    }
    try writer.writeAll(s);
}

/// Checks if a string looks like a valid email address (basic heuristic).
/// Uses simple structural checks: has @, has dot after @, no spaces.
pub fn isEmailLike(s: []const u8) bool {
    if (s.len < 5) return false;
    const atPos = std.mem.indexOf(u8, s, "@") orelse return false;
    if (atPos == 0 or atPos >= s.len - 2) return false;
    const domain = s[atPos + 1 ..];
    if (std.mem.indexOf(u8, domain, ".") == null) return false;
    for (s) |c| {
        if (std.ascii.isWhitespace(c)) return false;
    }
    return true;
}

/// Checks if a string looks like an IPv4 address (e.g., "192.168.1.1").
pub fn isIpv4Like(s: []const u8) bool {
    var parts: u8 = 0;
    var start: usize = 0;
    for (s, 0..) |c, i| {
        if (c == '.') {
            if (i == start) return false; // empty segment
            const seg = s[start..i];
            if (seg.len > 3) return false;
            const val = std.fmt.parseInt(u16, seg, 10) catch return false;
            if (val > 255) return false;
            parts += 1;
            start = i + 1;
        } else if (!std.ascii.isDigit(c)) {
            return false;
        }
    }
    if (start >= s.len) return false;
    const last = s[start..];
    if (last.len > 3) return false;
    const val = std.fmt.parseInt(u16, last, 10) catch return false;
    if (val > 255) return false;
    parts += 1;
    return parts == 4;
}

/// Checks if a string looks like a JWT token (starts with 'ey', has two '.' separators).
pub fn isJwtLike(s: []const u8) bool {
    if (s.len < 20) return false;
    if (!std.mem.startsWith(u8, s, "ey")) return false;
    var dotCount: u8 = 0;
    for (s) |c| {
        if (c == '.') dotCount += 1;
    }
    return dotCount == 2;
}

/// Validates a credit card number using the Luhn algorithm.
/// Returns true if the number is valid according to Luhn checksum.
pub fn isLuhnValid(digits: []const u8) bool {
    var sum: u32 = 0;
    var alternate = false;
    var i: usize = digits.len;
    while (i > 0) {
        i -= 1;
        const c = digits[i];
        if (!std.ascii.isDigit(c)) continue;
        var d: u32 = c - '0';
        if (alternate) {
            d *= 2;
            if (d > 9) d -= 9;
        }
        sum += d;
        alternate = !alternate;
    }
    return sum % 10 == 0;
}

/// Extracts only digits from a string into the provided buffer.
/// Returns the slice of digits written.
pub fn extractDigits(buf: []u8, s: []const u8) []u8 {
    var len: usize = 0;
    for (s) |c| {
        if (std.ascii.isDigit(c) and len < buf.len) {
            buf[len] = c;
            len += 1;
        }
    }
    return buf[0..len];
}

/// Safe increment of an atomic value, returns the new value.
pub fn atomicIncrementSafe(atomic: anytype) u64 {
    return @as(u64, atomic.fetchAdd(1, .monotonic)) + 1;
}

/// Safe add to an atomic value by delta, returns the new value.
pub fn atomicAddSafe(atomic: anytype, delta: u64) u64 {
    return @as(u64, atomic.fetchAdd(@intCast(delta), .monotonic)) + delta;
}

/// Writes RFC-5424 Syslog priority value: (facility * 8) + severity.
pub fn writeSyslogPriority(writer: anytype, facility: u8, severity: u8) !void {
    const priority: u32 = @as(u32, facility) * 8 + @as(u32, severity);
    try writer.writeByte('<');
    try writer.print("{d}", .{priority});
    try writer.writeByte('>');
}

/// Returns the RFC-5424 severity code (0-7) for a log level priority.
/// Maps: fatal->0 (Emergency), critical->2 (Critical), err->3 (Error),
/// warning->4 (Warning), notice->5 (Notice), info->6 (Informational),
/// debug/trace->7 (Debug)
pub fn syslogSeverityFromPriority(levelPriority: u8) u8 {
    return if (levelPriority >= 55) 0 // Emergency (fatal)
    else if (levelPriority >= 50) 2 // Critical
    else if (levelPriority >= 40) 3 // Error
    else if (levelPriority >= 30) 4 // Warning
    else if (levelPriority >= 22) 5 // Notice
    else if (levelPriority >= 20) 6 // Informational
    else 7; // Debug
}

/// Computes the chained cryptographic hash (SHA-256) of a log record,
/// linking it to the previous record hash.
pub fn computeChainHash(lastHash: ?[32]u8, newlyWritten: []const u8) [32]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    if (lastHash) |lh| {
        hasher.update(&lh);
    } else {
        // Use a default seed/IV for the first hash in the chain
        const iv: [32]u8 = @splat(0);
        hasher.update(&iv);
    }
    hasher.update(newlyWritten);
    var out: [32]u8 = undefined;
    hasher.final(&out);
    return out;
}

test "truncateString" {
    const allocator = std.testing.allocator;
    const s = try truncateString(allocator, "Hello, World!", 5, "...");
    defer allocator.free(s);
    try std.testing.expectEqualStrings("He...", s);
}

test "truncateString no truncation" {
    const allocator = std.testing.allocator;
    const s = try truncateString(allocator, "Hi", 10, "...");
    defer allocator.free(s);
    try std.testing.expectEqualStrings("Hi", s);
}

test "hashFnv32a" {
    const h1 = hashFnv32a("hello");
    const h2 = hashFnv32a("hello");
    const h3 = hashFnv32a("world");
    try std.testing.expectEqual(h1, h2);
    try std.testing.expect(h1 != h3);
}

test "hashFnv32a empty" {
    const h = hashFnv32a("");
    try std.testing.expectEqual(@as(u32, 2166136261), h); // FNV offset basis
}

test "isEmailLike" {
    try std.testing.expect(isEmailLike("user@example.com"));
    try std.testing.expect(!isEmailLike("notanemail"));
    try std.testing.expect(!isEmailLike("@nodomain"));
    try std.testing.expect(!isEmailLike("no@dot"));
}

test "isIpv4Like" {
    try std.testing.expect(isIpv4Like("192.168.1.1"));
    try std.testing.expect(isIpv4Like("0.0.0.0"));
    try std.testing.expect(!isIpv4Like("256.1.1.1"));
    try std.testing.expect(!isIpv4Like("not.an.ip"));
    try std.testing.expect(!isIpv4Like("192.168.1"));
}

test "isJwtLike" {
    try std.testing.expect(isJwtLike("eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U"));
    try std.testing.expect(!isJwtLike("notajwt"));
    try std.testing.expect(!isJwtLike("eyshort"));
}

test "isLuhnValid" {
    // Visa test card
    try std.testing.expect(isLuhnValid("4111111111111111"));
    // Invalid number
    try std.testing.expect(!isLuhnValid("4111111111111112"));
}

test "syslogSeverityFromPriority" {
    try std.testing.expectEqual(@as(u8, 0), syslogSeverityFromPriority(55)); // fatal
    try std.testing.expectEqual(@as(u8, 3), syslogSeverityFromPriority(40)); // error
    try std.testing.expectEqual(@as(u8, 6), syslogSeverityFromPriority(20)); // info
    try std.testing.expectEqual(@as(u8, 7), syslogSeverityFromPriority(5)); // trace
}
