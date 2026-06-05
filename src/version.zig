//! Logly Version Information

/// Logly V0.2.1 | Author: Muhammad Fiaz | License: MIT
pub const version = "0.2.1";

/// Current version parsed as a SemanticVersion for ordered comparison.
///
/// Parsed at compile time so that version comparison helpers do not pay any
/// runtime parsing cost on the hot logging path.
pub const parsed: std.SemanticVersion = std.SemanticVersion.parse(version) catch @panic("invalid logly version string");

const std = @import("std");
