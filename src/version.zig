//! Logly version. Single source of truth; mirrors build.zig.zon.

/// Current release version.
pub const version = "0.2.2";

const std = @import("std");

test "version parses as semantic version" {
    const parsed = try std.SemanticVersion.parse(version);
    try std.testing.expectEqual(@as(usize, 0), parsed.major);
    try std.testing.expectEqual(@as(usize, 2), parsed.minor);
    try std.testing.expectEqual(@as(usize, 2), parsed.patch);
}
