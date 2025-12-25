const std = @import("std");

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
    if (std.ascii.eqlIgnoreCase(unit, "K") or std.ascii.eqlIgnoreCase(unit, "KB")) return num * 1024;
    if (std.ascii.eqlIgnoreCase(unit, "M") or std.ascii.eqlIgnoreCase(unit, "MB")) return num * 1024 * 1024;
    if (std.ascii.eqlIgnoreCase(unit, "G") or std.ascii.eqlIgnoreCase(unit, "GB")) return num * 1024 * 1024 * 1024;
    if (std.ascii.eqlIgnoreCase(unit, "T") or std.ascii.eqlIgnoreCase(unit, "TB")) return num * 1024 * 1024 * 1024 * 1024;

    return num;
}

/// Formats a byte size into a human-readable string.
/// Uses the most appropriate unit (B, KB, MB, GB, TB).
pub fn formatSize(allocator: std.mem.Allocator, bytes: u64) ![]u8 {
    const units = [_][]const u8{ "B", "KB", "MB", "GB", "TB" };
    var value: f64 = @floatFromInt(bytes);
    var unit_idx: usize = 0;

    while (value >= 1024.0 and unit_idx < units.len - 1) {
        value /= 1024.0;
        unit_idx += 1;
    }

    if (unit_idx == 0) {
        return std.fmt.allocPrint(allocator, "{d} {s}", .{ bytes, units[unit_idx] });
    } else {
        return std.fmt.allocPrint(allocator, "{d:.2} {s}", .{ value, units[unit_idx] });
    }
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
    if (std.ascii.eqlIgnoreCase(unit, "s")) return num * 1000;
    if (std.ascii.eqlIgnoreCase(unit, "m")) return num * 60 * 1000;
    if (std.ascii.eqlIgnoreCase(unit, "h")) return num * 60 * 60 * 1000;
    if (std.ascii.eqlIgnoreCase(unit, "d")) return num * 24 * 60 * 60 * 1000;

    return num;
}

/// Formats a duration in milliseconds into a human-readable string.
pub fn formatDuration(allocator: std.mem.Allocator, ms: i64) ![]u8 {
    if (ms < 1000) {
        return std.fmt.allocPrint(allocator, "{d}ms", .{ms});
    } else if (ms < 60 * 1000) {
        return std.fmt.allocPrint(allocator, "{d:.2}s", .{@as(f64, @floatFromInt(ms)) / 1000.0});
    } else if (ms < 60 * 60 * 1000) {
        return std.fmt.allocPrint(allocator, "{d:.2}m", .{@as(f64, @floatFromInt(ms)) / 60000.0});
    } else if (ms < 24 * 60 * 60 * 1000) {
        return std.fmt.allocPrint(allocator, "{d:.2}h", .{@as(f64, @floatFromInt(ms)) / 3600000.0});
    } else {
        return std.fmt.allocPrint(allocator, "{d:.2}d", .{@as(f64, @floatFromInt(ms)) / 86400000.0});
    }
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
    return fromEpochSeconds(@divFloor(timestamp, 1000));
}

/// Gets current time components.
pub fn nowComponents() TimeComponents {
    return fromMilliTimestamp(std.time.milliTimestamp());
}

/// Returns current Unix timestamp in seconds.
pub fn currentSeconds() i64 {
    return std.time.timestamp();
}

/// Returns current timestamp in milliseconds.
pub fn currentMillis() i64 {
    return std.time.milliTimestamp();
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
    return timestamp - @as(i64, @intCast(tc.hour * 3600 + tc.minute * 60 + tc.second));
}

/// Returns the start of the current hour as epoch seconds.
pub fn startOfHour(timestamp: i64) i64 {
    const tc = fromEpochSeconds(timestamp);
    return timestamp - @as(i64, @intCast(tc.minute * 60 + tc.second));
}

/// Calculates elapsed time in milliseconds since start_time.
pub fn elapsedMs(start_time: i64) u64 {
    const now_time = std.time.milliTimestamp();
    if (now_time < start_time) return 0;
    return @intCast(now_time - start_time);
}

/// Calculates elapsed time in seconds since start_time.
pub fn elapsedSeconds(start_time: i64) u64 {
    return elapsedMs(start_time) / 1000;
}

/// Formats a date/time string based on a format pattern using granular tokens.
/// Supports all ASCII symbols as separators between tokens.
///
/// Supported tokens:
/// YYYY - Year (4 digits)
/// YY   - Year (2 digits)
/// MM   - Month (01-12)
/// DD   - Day (01-31)
/// HH   - Hour (00-23)
/// mm   - Minute (00-59)
/// ss   - Second (00-59)
/// M    - Month (1-12) - single digit
/// D    - Day (1-31) - single digit
/// H    - Hour (0-23) - single digit
pub fn formatDatePattern(writer: anytype, fmt: []const u8, year: i32, month: u8, day: u8, hour: u64, minute: u64, second: u64) !void {
    var i: usize = 0;
    while (i < fmt.len) {
        if (i + 4 <= fmt.len and std.mem.eql(u8, fmt[i .. i + 4], "YYYY")) {
            try writer.print("{d:0>4}", .{year});
            i += 4;
        } else if (i + 2 <= fmt.len and std.mem.eql(u8, fmt[i .. i + 2], "YY")) {
            try writer.print("{d:0>2}", .{@mod(year, 100)});
            i += 2;
        } else if (i + 2 <= fmt.len and std.mem.eql(u8, fmt[i .. i + 2], "MM")) {
            try writer.print("{d:0>2}", .{month});
            i += 2;
        } else if (i + 2 <= fmt.len and std.mem.eql(u8, fmt[i .. i + 2], "DD")) {
            try writer.print("{d:0>2}", .{day});
            i += 2;
        } else if (i + 2 <= fmt.len and std.mem.eql(u8, fmt[i .. i + 2], "HH")) {
            try writer.print("{d:0>2}", .{hour});
            i += 2;
        } else if (i + 2 <= fmt.len and std.mem.eql(u8, fmt[i .. i + 2], "mm")) {
            try writer.print("{d:0>2}", .{minute});
            i += 2;
        } else if (i + 2 <= fmt.len and std.mem.eql(u8, fmt[i .. i + 2], "ss")) {
            try writer.print("{d:0>2}", .{second});
            i += 2;
        } else if (fmt[i] == 'M' and (i + 1 >= fmt.len or fmt[i + 1] != 'M')) {
            try writer.print("{d}", .{month});
            i += 1;
        } else if (fmt[i] == 'D' and (i + 1 >= fmt.len or fmt[i + 1] != 'D')) {
            try writer.print("{d}", .{day});
            i += 1;
        } else if (fmt[i] == 'H' and (i + 1 >= fmt.len or fmt[i + 1] != 'H')) {
            try writer.print("{d}", .{hour});
            i += 1;
        } else {
            try writer.writeByte(fmt[i]);
            i += 1;
        }
    }
}

/// Formats a date/time to a caller-provided buffer using a pattern.
pub fn formatDateToBuf(buf: []u8, fmt: []const u8, year: i32, month: u8, day: u8, hour: u64, minute: u64, second: u64) ![]u8 {
    var fbs = std.io.fixedBufferStream(buf);
    try formatDatePattern(fbs.writer(), fmt, year, month, day, hour, minute, second);
    return fbs.getWritten();
}

/// Formats an ISO 8601 date string (YYYY-MM-DD) to buffer.
pub fn formatIsoDate(buf: []u8, tc: TimeComponents) ![]u8 {
    var fbs = std.io.fixedBufferStream(buf);
    try fbs.writer().print("{d:0>4}-{d:0>2}-{d:0>2}", .{ tc.year, tc.month, tc.day });
    return fbs.getWritten();
}

/// Formats an ISO 8601 time string (HH:MM:SS) to buffer.
pub fn formatIsoTime(buf: []u8, tc: TimeComponents) ![]u8 {
    var fbs = std.io.fixedBufferStream(buf);
    try fbs.writer().print("{d:0>2}:{d:0>2}:{d:0>2}", .{ tc.hour, tc.minute, tc.second });
    return fbs.getWritten();
}

/// Formats an ISO 8601 datetime string (YYYY-MM-DDTHH:MM:SS) to buffer.
pub fn formatIsoDateTime(buf: []u8, tc: TimeComponents) ![]u8 {
    var fbs = std.io.fixedBufferStream(buf);
    try fbs.writer().print("{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}", .{
        tc.year, tc.month, tc.day, tc.hour, tc.minute, tc.second,
    });
    return fbs.getWritten();
}

/// Formats a filename-safe datetime string (YYYY-MM-DD_HH-MM-SS) to buffer.
pub fn formatFilenameSafe(buf: []u8, tc: TimeComponents) ![]u8 {
    var fbs = std.io.fixedBufferStream(buf);
    try fbs.writer().print("{d:0>4}-{d:0>2}-{d:0>2}_{d:0>2}-{d:0>2}-{d:0>2}", .{
        tc.year, tc.month, tc.day, tc.hour, tc.minute, tc.second,
    });
    return fbs.getWritten();
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
    try std.testing.expectEqual(@as(?i64, 86400000), parseDuration("1d"));
}

test "fromEpochSeconds" {
    const tc = fromEpochSeconds(1735689600);
    try std.testing.expectEqual(@as(i32, 2025), tc.year);
    try std.testing.expectEqual(@as(u8, 1), tc.month);
    try std.testing.expectEqual(@as(u8, 1), tc.day);
}

test "isSameDay" {
    try std.testing.expect(isSameDay(1735689600, 1735689600 + 3600));
    try std.testing.expect(!isSameDay(1735689600, 1735689600 + 86400));
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
    const result = try formatDateToBuf(&buf, "YYYY", 2025, 12, 25, 14, 30, 45);
    try std.testing.expect(result.len >= 4);
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
