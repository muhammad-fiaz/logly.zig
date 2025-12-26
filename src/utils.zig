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

/// Writes a human-readable byte size to the writer.
pub fn writeSize(writer: anytype, bytes: u64) !void {
    const units = [_][]const u8{ "B", "KB", "MB", "GB", "TB" };
    var value: f64 = @floatFromInt(bytes);
    var unit_idx: usize = 0;

    while (value >= 1024.0 and unit_idx < units.len - 1) {
        value /= 1024.0;
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
    var list = std.ArrayList(u8).init(allocator);
    errdefer list.deinit();
    try writeSize(list.writer(), bytes);
    return list.toOwnedSlice();
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

/// Writes a human-readable duration to the writer.
pub fn writeDuration(writer: anytype, ms: i64) !void {
    if (ms < 1000) {
        try writer.print("{d}ms", .{ms});
    } else if (ms < 60 * 1000) {
        try writer.print("{d:.2}s", .{@as(f64, @floatFromInt(ms)) / 1000.0});
    } else if (ms < 60 * 60 * 1000) {
        try writer.print("{d:.2}m", .{@as(f64, @floatFromInt(ms)) / 60000.0});
    } else if (ms < 24 * 60 * 60 * 1000) {
        try writer.print("{d:.2}h", .{@as(f64, @floatFromInt(ms)) / 3600000.0});
    } else {
        try writer.print("{d:.2}d", .{@as(f64, @floatFromInt(ms)) / 86400000.0});
    }
}

/// Formats a duration in milliseconds into a human-readable string.
pub fn formatDuration(allocator: std.mem.Allocator, ms: i64) ![]u8 {
    var list = std.ArrayList(u8).init(allocator);
    errdefer list.deinit();
    try writeDuration(list.writer(), ms);
    return list.toOwnedSlice();
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
pub fn formatDatePattern(writer: anytype, fmt: []const u8, year: i32, month: u8, day: u8, hour: u64, minute: u64, second: u64, millis: u64) !void {
    var i: usize = 0;
    while (i < fmt.len) {
        if (i + 4 <= fmt.len and std.mem.eql(u8, fmt[i .. i + 4], "YYYY")) {
            try write4Digits(writer, year);
            i += 4;
        } else if (i + 2 <= fmt.len and std.mem.eql(u8, fmt[i .. i + 2], "YY")) {
            try write2Digits(writer, @mod(year, 100));
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
    var fbs = std.io.fixedBufferStream(buf);
    try formatDatePattern(fbs.writer(), fmt, year, month, day, hour, minute, second, millis);
    return fbs.getWritten();
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
    var fbs = std.io.fixedBufferStream(buf);
    try writeIsoDate(fbs.writer(), tc);
    return fbs.getWritten();
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
    var fbs = std.io.fixedBufferStream(buf);
    try writeIsoTime(fbs.writer(), tc);
    return fbs.getWritten();
}

/// Writes an ISO 8601 datetime (YYYY-MM-DDTHH:MM:SS) to the writer.
pub fn writeIsoDateTime(writer: anytype, tc: TimeComponents) !void {
    try writeIsoDate(writer, tc);
    try writer.writeByte('T');
    try writeIsoTime(writer, tc);
}

/// Formats an ISO 8601 datetime string (YYYY-MM-DDTHH:MM:SS) to buffer.
pub fn formatIsoDateTime(buf: []u8, tc: TimeComponents) ![]u8 {
    var fbs = std.io.fixedBufferStream(buf);
    try writeIsoDateTime(fbs.writer(), tc);
    return fbs.getWritten();
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
    var fbs = std.io.fixedBufferStream(buf);
    try writeFilenameSafe(fbs.writer(), tc);
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

/// Escapes a string for safe inclusion in JSON output.
/// Handles all JSON special characters including control characters.
///
/// Performance: O(n) where n = string length
/// Memory: Zero allocations - writes directly to the provided writer
///
/// Example:
/// ```zig
/// var buf: [256]u8 = undefined;
/// var fbs = std.io.fixedBufferStream(&buf);
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
    var fbs = std.io.fixedBufferStream(buf);
    try escapeJsonString(fbs.writer(), s);
    return fbs.getWritten();
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
    const seconds = @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000_000.0;
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
    const seconds = @as(f64, @floatFromInt(elapsed_ms)) / 1000.0;
    return @as(f64, @floatFromInt(count)) / seconds;
}

test "escapeJsonString" {
    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    try escapeJsonString(fbs.writer(), "Hello\"World");
    try std.testing.expectEqualStrings("Hello\\\"World", fbs.getWritten());

    fbs.reset();
    try escapeJsonString(fbs.writer(), "Line1\nLine2");
    try std.testing.expectEqualStrings("Line1\\nLine2", fbs.getWritten());

    fbs.reset();
    try escapeJsonString(fbs.writer(), "Tab\there");
    try std.testing.expectEqualStrings("Tab\\there", fbs.getWritten());
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
    const result = try formatDateToBuf(&buf, "YYYY-MM-DD | HH:mm:ss.SSS", 2025, 12, 25, 14, 30, 45, 123);
    try std.testing.expectEqualStrings("2025-12-25 | 14:30:45.123", result);
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

pub fn write2Digits(writer: anytype, value: anytype) !void {
    const v: u64 = @intCast(value);
    const v2 = v % 100;
    try writer.writeByte(@intCast('0' + (v2 / 10)));
    try writer.writeByte(@intCast('0' + (v2 % 10)));
}

pub fn write3Digits(writer: anytype, value: anytype) !void {
    const v: u64 = @intCast(value);
    const v3 = v % 1000;
    try writer.writeByte(@intCast('0' + (v3 / 100)));
    try writer.writeByte(@intCast('0' + ((v3 / 10) % 10)));
    try writer.writeByte(@intCast('0' + (v3 % 10)));
}

pub fn write4Digits(writer: anytype, value: anytype) !void {
    const v: u64 = @intCast(value);
    const v4 = v % 10000;
    try writer.writeByte(@intCast('0' + (v4 / 1000)));
    try writer.writeByte(@intCast('0' + ((v4 / 100) % 10)));
    try writer.writeByte(@intCast('0' + ((v4 / 10) % 10)));
    try writer.writeByte(@intCast('0' + (v4 % 10)));
}

pub fn write1Or2Digits(writer: anytype, value: anytype) !void {
    const v: u64 = @intCast(value);
    if (v < 10) {
        try writer.writeByte(@intCast('0' + v));
    } else {
        try write2Digits(writer, v);
    }
}

pub fn write4Hex(writer: anytype, value: u16) !void {
    const hex = "0123456789abcdef";
    try writer.writeByte(hex[(value >> 12) & 0xF]);
    try writer.writeByte(hex[(value >> 8) & 0xF]);
    try writer.writeByte(hex[(value >> 4) & 0xF]);
    try writer.writeByte(hex[value & 0xF]);
}
pub fn writeInt(writer: anytype, value: anytype) !void {
    try writer.print("{d}", .{value});
}
