const std = @import("std");

/// Formats a date/time string based on a format pattern using granular tokens.
/// Supported tokens:
/// YYYY - Year (4 digits)
/// YY   - Year (2 digits)
/// MM   - Month (01-12)
/// M    - Month (1-12)
/// DD   - Day (01-31)
/// D    - Day (1-31)
/// HH   - Hour (00-23)
/// H    - Hour (0-23)
/// mm   - Minute (00-59)
/// m    - Minute (0-59)
/// ss   - Second (00-59)
/// s    - Second (0-59)
pub fn format(writer: anytype, fmt: []const u8, year: i32, month: u8, day: u8, hour: u64, minute: u64, second: u64) !void {
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
        } else if (i + 1 <= fmt.len and std.mem.eql(u8, fmt[i .. i + 1], "M")) {
            try writer.print("{d}", .{month});
            i += 1;
        } else if (i + 2 <= fmt.len and std.mem.eql(u8, fmt[i .. i + 2], "DD")) {
            try writer.print("{d:0>2}", .{day});
            i += 2;
        } else if (i + 1 <= fmt.len and std.mem.eql(u8, fmt[i .. i + 1], "D")) {
            try writer.print("{d}", .{day});
            i += 1;
        } else if (i + 2 <= fmt.len and std.mem.eql(u8, fmt[i .. i + 2], "HH")) {
            try writer.print("{d:0>2}", .{hour});
            i += 2;
        } else if (i + 1 <= fmt.len and std.mem.eql(u8, fmt[i .. i + 1], "H")) {
            try writer.print("{d}", .{hour});
            i += 1;
        } else if (i + 2 <= fmt.len and std.mem.eql(u8, fmt[i .. i + 2], "mm")) {
            try writer.print("{d:0>2}", .{minute});
            i += 2;
        } else if (i + 1 <= fmt.len and std.mem.eql(u8, fmt[i .. i + 1], "m")) {
            try writer.print("{d}", .{minute});
            i += 1;
        } else if (i + 2 <= fmt.len and std.mem.eql(u8, fmt[i .. i + 2], "ss")) {
            try writer.print("{d:0>2}", .{second});
            i += 2;
        } else if (i + 1 <= fmt.len and std.mem.eql(u8, fmt[i .. i + 1], "s")) {
            try writer.print("{d}", .{second});
            i += 1;
        } else {
            try writer.writeByte(fmt[i]);
            i += 1;
        }
    }
}
