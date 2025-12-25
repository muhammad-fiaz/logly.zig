---
title: UpdateChecker API Reference
description: API reference for Logly.zig UpdateChecker module. Check for new library versions, manage version info, and receive update notifications automatically.
head:
  - - meta
    - name: keywords
      content: update checker, version check, library updates, version management, auto update, version notification
  - - meta
    - property: og:title
      content: UpdateChecker API Reference | Logly.zig
---

# UpdateChecker API

The `UpdateChecker` module provides functionality to check for new releases of the library and manage version information.

## Overview

This module runs a background check against the GitHub API to see if a newer version of Logly is available. It is enabled by default in `Config` but can be disabled.

## Types

### Version

Version information structure.

```zig
pub const Version = struct {
    major: u8,
    minor: u8,
    patch: u8,
    pre_release: ?[]const u8,
    build_metadata: ?[]const u8,
    
    pub fn toString(self: Version, allocator: Allocator) ![]u8;
    pub fn compare(self: Version, other: Version) i8;
    pub fn isNewerThan(self: Version, other: Version) bool;
};
```

### UpdateInfo

Information about an available update.

```zig
pub const UpdateInfo = struct {
    current_version: Version,
    latest_version: Version,
    release_url: []const u8,
    release_notes: ?[]const u8,
    published_at: ?i64,
    is_prerelease: bool,
};
```

### UpdateCheckerStats

Statistics for update checker operations.

```zig
pub const UpdateCheckerStats = struct {
    checks_performed: std.atomic.Value(u64),
    updates_found: std.atomic.Value(u64),
    check_errors: std.atomic.Value(u64),
    last_check_timestamp: std.atomic.Value(i64),
};
```

## Functions

### `checkForUpdates(allocator: std.mem.Allocator) ?std.Thread`

Checks for updates in a background thread. Runs only once per process lifecycle.

- **Returns**: A thread handle if the check was started, `null` otherwise.
- **Behavior**:
    - Fetches the latest release tag from GitHub.
    - Compares it with the current version.
    - Logs an INFO message if a newer version is found.
    - Fails silently on network errors.

### `getCurrentVersion() Version`

Returns the current version of the library.

### `getLatestVersion(allocator: std.mem.Allocator) !Version`

Fetches the latest version from GitHub API synchronously.

### `isUpdateAvailable(allocator: std.mem.Allocator) !bool`

Returns true if a newer version is available.

### `getUpdateInfo(allocator: std.mem.Allocator) !?UpdateInfo`

Returns detailed information about available update, or null if up-to-date.

## Configuration

Controlled via `Config.check_for_updates`.

```zig
var config = logly.Config.default();
config.check_for_updates = false; // Disable update check
```

## Aliases

| Alias | Method |
|-------|--------|
| `check` | `checkForUpdates` |
| `version` | `getCurrentVersion` |
| `latest` | `getLatestVersion` |
| `hasUpdate` | `isUpdateAvailable` |

## Example

```zig
const logly = @import("logly");
const UpdateChecker = logly.UpdateChecker;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; 
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Check current version
    const current = UpdateChecker.getCurrentVersion();
    std.debug.print("Current version: {d}.{d}.{d}\n", .{
        current.major, current.minor, current.patch
    });

    // Check for updates
    if (try UpdateChecker.isUpdateAvailable(allocator)) {
        if (try UpdateChecker.getUpdateInfo(allocator)) |info| {
            defer allocator.free(info.release_url);
            std.debug.print("New version available: {d}.{d}.{d}\n", .{
                info.latest_version.major,
                info.latest_version.minor,
                info.latest_version.patch,
            });
            std.debug.print("Download: {s}\n", .{info.release_url});
        }
    }

    // Or use background check (default behavior)
    if (UpdateChecker.checkForUpdates(allocator)) |thread| {
        thread.detach(); // Let it run in background
    }
}
```

## Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `check_for_updates` | `bool` | `true` | Enable automatic update checking |
| `update_check_interval_hours` | `u64` | `24` | Hours between checks |
| `show_update_notification` | `bool` | `true` | Show notification when update available |

## See Also

- [Update Checker Guide](../guide/update-checker.md) - Usage patterns
- [Version API](#version) - Version information
- [Configuration Guide](../guide/configuration.md) - Full configuration options
