const std = @import("std");
const builtin = @import("builtin");
const http = std.http;
const SemanticVersion = std.SemanticVersion;
const version_info = @import("version.zig");
const Network = @import("network.zig");

const REPO_OWNER = "muhammad-fiaz";
const REPO_NAME = "logly.zig";
const CURRENT_VERSION: []const u8 = version_info.version;

/// Static flag to ensure update check runs only once per process
var update_check_done = false;
var update_check_mutex = std.Thread.Mutex{};

fn stripVersionPrefix(tag: []const u8) []const u8 {
    if (tag.len == 0) return tag;
    return if (tag[0] == 'v' or tag[0] == 'V') tag[1..] else tag;
}

fn parseSemver(text: []const u8) ?SemanticVersion {
    return SemanticVersion.parse(text) catch null;
}

const VersionRelation = enum { local_newer, equal, remote_newer, unknown };

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
pub fn checkForUpdates(allocator: std.mem.Allocator) ?std.Thread {
    update_check_mutex.lock();
    defer update_check_mutex.unlock();

    // Prevent multiple concurrent update checks
    if (update_check_done) return null;
    update_check_done = true;

    return std.Thread.spawn(.{}, checkWorker, .{allocator}) catch null;
}

fn checkWorker(allocator: std.mem.Allocator) void {
    const latest_tag = fetchLatestTag(allocator) catch return;
    defer allocator.free(latest_tag);

    // Use ASCII-safe indicators instead of emoji for cross-platform compatibility
    switch (compareVersions(latest_tag)) {
        .remote_newer => std.log.info("[UPDATE] A newer release is available: {s} (current {s})", .{ latest_tag, CURRENT_VERSION }),
        .local_newer => std.log.info("[NIGHTLY] Running a dev/nightly build ahead of latest release: current {s}, latest {s}", .{ CURRENT_VERSION, latest_tag }),
        else => {},
    }
}
