const std = @import("std");
const builtin = @import("builtin");
const http = std.http;
const SemanticVersion = std.SemanticVersion;
const version_info = @import("version.zig");

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
    var client = http.Client{ .allocator = allocator };
    defer client.deinit();

    const url = std.fmt.comptimePrint("https://api.github.com/repos/{s}/{s}/releases/latest", .{ REPO_OWNER, REPO_NAME });
    const extra_headers = [_]http.Header{
        .{ .name = "Accept", .value = "application/vnd.github+json" },
    };

    var req = try client.request(.GET, try std.Uri.parse(url), .{
        .headers = .{ .user_agent = .{ .override = std.fmt.comptimePrint("logly.zig/{s}", .{builtin.zig_version_string}) } },
        .extra_headers = &extra_headers,
    });
    defer req.deinit();

    try req.sendBodiless();

    const redirect_buffer = try allocator.alloc(u8, 8 * 1024);
    defer allocator.free(redirect_buffer);

    var response = try req.receiveHead(redirect_buffer);
    if (response.head.status != .ok) return error.TagMissing;

    const decompress_buffer: []u8 = switch (response.head.content_encoding) {
        .identity => &.{},
        .zstd => try allocator.alloc(u8, std.compress.zstd.default_window_len),
        .deflate, .gzip => try allocator.alloc(u8, std.compress.flate.max_window_len),
        .compress => return error.TagMissing,
    };
    defer if (decompress_buffer.len != 0) allocator.free(decompress_buffer);

    var transfer_buffer: [64]u8 = undefined;
    var decompress: http.Decompress = undefined;
    const reader = response.readerDecompressing(&transfer_buffer, &decompress, decompress_buffer);

    var accumulator: std.Io.Writer.Allocating = .init(allocator);
    defer accumulator.deinit();

    _ = reader.streamRemaining(&accumulator.writer) catch return error.TagMissing;

    const body_slice = accumulator.writer.buffer[0..accumulator.writer.end];
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, body_slice, .{});
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
