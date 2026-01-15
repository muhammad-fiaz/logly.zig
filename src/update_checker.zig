//! Automatic Update Checker Module
//!
//! Provides background version checking against GitHub releases.
//! Runs asynchronously to avoid blocking application startup.
//!
//! Features:
//! - Semantic version comparison (MAJOR.MINOR.PATCH)
//! - Background thread execution (non-blocking)
//! - Single execution per process (prevents duplicate checks)
//! - Silent failure handling (graceful degradation)
//! - Console notifications for available updates
//!
//! The update checker queries the GitHub API for the latest release
//! and compares it against the current version to notify users of
//! available updates or warn about running development builds.

const std = @import("std");
const builtin = @import("builtin");
const http = std.http;
const SemanticVersion = std.SemanticVersion;
const version_info = @import("version.zig");
const Network = @import("network.zig");

/// GitHub repository owner for update checks.
const REPO_OWNER = "muhammad-fiaz";

/// GitHub repository name for update checks.
const REPO_NAME = "logly.zig";

/// Current version string from version.zig.
const CURRENT_VERSION: []const u8 = version_info.version;

/// Flag to ensure update check runs only once per process lifetime.
var update_check_done = false;

/// Flag to enable/disable update checking project-wide.
/// When set to false, update checks are disabled for the entire application.
/// This can be set at any point before the first logger initialization.
var update_check_enabled = true;

/// Mutex protecting the update check flag.
var update_check_mutex = std.Thread.Mutex{};

/// Enables or disables update checking project-wide.
/// Call this function before initializing any loggers to ensure it takes effect.
///
/// Example:
/// ```zig
/// const logly = @import("logly");
///
/// // Disable update checking for the entire application
/// logly.UpdateChecker.setEnabled(false);
///
/// // Now create loggers - they won't perform update checks
/// const logger = logly.Logger.init(.{});
/// ```
pub fn setEnabled(enabled: bool) void {
    update_check_mutex.lock();
    defer update_check_mutex.unlock();
    update_check_enabled = enabled;
}

/// Returns whether update checking is enabled.
pub fn isEnabled() bool {
    update_check_mutex.lock();
    defer update_check_mutex.unlock();
    return update_check_enabled;
}

/// Resets the update check state (useful for testing).
/// This should only be called in test scenarios.
pub fn resetState() void {
    update_check_mutex.lock();
    defer update_check_mutex.unlock();
    update_check_done = false;
    update_check_enabled = true;
}

/// Strips leading 'v' or 'V' prefix from version tags.
/// GitHub releases often use "v1.0.0" format.
fn stripVersionPrefix(tag: []const u8) []const u8 {
    if (tag.len == 0) return tag;
    return if (tag[0] == 'v' or tag[0] == 'V') tag[1..] else tag;
}

/// Parses a version string into SemanticVersion.
/// Returns null if parsing fails.
fn parseSemver(text: []const u8) ?SemanticVersion {
    return SemanticVersion.parse(text) catch null;
}

/// Version comparison result indicating relative version ordering.
const VersionRelation = enum {
    /// Local version is newer than remote (dev/nightly build).
    local_newer,
    /// Versions are equal (up to date).
    equal,
    /// Remote version is newer (update available).
    remote_newer,
    /// Version comparison failed (unknown format).
    unknown,
};

fn compareVersions(latest_raw: []const u8) VersionRelation {
    const latest = stripVersionPrefix(latest_raw);
    const current = stripVersionPrefix(CURRENT_VERSION);

    if (parseSemver(current)) |cur| {
        if (parseSemver(latest)) |lat| {
            if (lat.major != cur.major) return if (lat.major > cur.major) .remote_newer else .local_newer;
            if (lat.minor != cur.minor) return if (lat.minor > cur.minor) .remote_newer else .local_newer;
            if (lat.patch != cur.patch) return if (lat.patch > cur.patch) .remote_newer else .local_newer;
            return .equal;
        }
    }

    if (std.mem.eql(u8, current, latest)) return .equal;
    return .unknown;
}

fn fetchLatestTag(allocator: std.mem.Allocator) ![]const u8 {
    const url = std.fmt.comptimePrint("https://api.github.com/repos/{s}/{s}/releases/latest", .{ REPO_OWNER, REPO_NAME });
    const extra_headers = [_]http.Header{
        .{ .name = "Accept", .value = "application/vnd.github+json" },
    };

    const parsed = Network.fetchJson(allocator, url, &extra_headers) catch return error.TagMissing;
    defer parsed.deinit();

    return switch (parsed.value) {
        .object => |obj| blk: {
            if (obj.get("tag_name")) |tag_value| {
                switch (tag_value) {
                    .string => |s| break :blk try allocator.dupe(u8, s),
                    else => break :blk error.TagMissing,
                }
            }
            break :blk error.TagMissing;
        },
        else => error.TagMissing,
    };
}

/// Checks for updates in a background thread (runs only once per process).
/// Returns a thread handle so callers can optionally join during shutdown.
/// Fails silently on errors (no internet, api limits, etc).
/// Respects the project-wide update_check_enabled flag.
pub fn checkForUpdates(allocator: std.mem.Allocator, global_console_display: bool) ?std.Thread {
    update_check_mutex.lock();
    defer update_check_mutex.unlock();

    // Prevent concurrent checks, running during tests, or when disabled project-wide
    if (update_check_done or builtin.is_test or !update_check_enabled) return null;
    update_check_done = true;

    return std.Thread.spawn(.{}, checkWorker, .{ allocator, global_console_display }) catch null;
}

fn checkWorker(allocator: std.mem.Allocator, global_console_display: bool) void {
    const latest_tag = fetchLatestTag(allocator) catch return;
    defer allocator.free(latest_tag);

    // Errors are silenced as requested for production use
    // If you need to debug, you can uncomment these line comments:
    // const reset = "\x1b[0m";
    // const bold_white = "\x1b[1;37m";
    // const red_bg = "\x1b[41m";
    // std.log.info("{s}{s} [UPDATE ERROR] ❌ Failed to check for updates {s}", .{ bold_white, red_bg, reset });

    const reset = "\x1b[0m";
    const bold_white = "\x1b[1;37m";
    const bold_black = "\x1b[1;30m";
    const green_bg = "\x1b[42m"; // Professional Green
    const cyan_bg = "\x1b[46m"; // Professional Cyan

    if (!global_console_display) return;

    switch (compareVersions(latest_tag)) {
        .remote_newer => {
            std.debug.print("\n{s}{s} [UPDATE] >> A newer release is available: {s} (current {s}) {s}\n", .{
                bold_white,
                green_bg,
                latest_tag,
                CURRENT_VERSION,
                reset,
            });
            std.debug.print("{s}{s}          To update, run: zig fetch --save https://github.com/muhammad-fiaz/logly.zig/releases       {s}\n\n", .{
                bold_white,
                green_bg,
                reset,
            });
        },
        .local_newer => {
            std.debug.print("\n{s}{s} [NIGHTLY] * Running a dev/nightly build ahead of latest release: current {s}, latest {s} {s}\n", .{
                bold_black,
                cyan_bg,
                CURRENT_VERSION,
                latest_tag,
                reset,
            });
            std.debug.print("{s}{s}           This version may contain experimental features and is not for production use.      {s}\n\n", .{
                bold_black,
                cyan_bg,
                reset,
            });
        },
        else => {},
    }
}

// Tests
test "setEnabled and isEnabled" {
    // Initial state should be enabled
    resetState();
    try std.testing.expect(isEnabled());

    // Disable
    setEnabled(false);
    try std.testing.expect(!isEnabled());

    // Re-enable
    setEnabled(true);
    try std.testing.expect(isEnabled());

    // Reset for other tests
    resetState();
}

test "resetState" {
    setEnabled(false);
    try std.testing.expect(!isEnabled());

    resetState();
    try std.testing.expect(isEnabled());
}

test "stripVersionPrefix" {
    try std.testing.expectEqualStrings("1.0.0", stripVersionPrefix("v1.0.0"));
    try std.testing.expectEqualStrings("1.0.0", stripVersionPrefix("V1.0.0"));
    try std.testing.expectEqualStrings("1.0.0", stripVersionPrefix("1.0.0"));
    try std.testing.expectEqualStrings("", stripVersionPrefix(""));
}

test "compareVersions" {
    // Test equal versions
    try std.testing.expectEqual(VersionRelation.equal, compareVersions(CURRENT_VERSION));

    // Test that comparison handles prefixes
    const current_with_v = std.fmt.comptimePrint("v{s}", .{CURRENT_VERSION});
    try std.testing.expectEqual(VersionRelation.equal, compareVersions(current_with_v));
}
