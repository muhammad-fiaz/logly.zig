const std = @import("std");

/// Parses a size string (e.g., "10MB", "5GB") into bytes.
/// Supports B, KB, MB, GB, TB (case insensitive).
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
