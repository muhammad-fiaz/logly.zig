# UpdateChecker API

The `UpdateChecker` module provides functionality to check for new releases of the library.

## Overview

This module runs a background check against the GitHub API to see if a newer version of Logly is available. It is enabled by default in `Config` but can be disabled.

## Functions

### `checkForUpdates(allocator: std.mem.Allocator) ?std.Thread`

Checks for updates in a background thread. Runs only once per process lifecycle.

- **Returns**: A thread handle if the check was started, `null` otherwise.
- **Behavior**:
    - Fetches the latest release tag from GitHub.
    - Compares it with the current version.
    - Logs an INFO message if a newer version is found.
    - Fails silently on network errors.

## Configuration

Controlled via `Config.check_for_updates`.

```zig
var config = logly.Config.default();
config.check_for_updates = false; // Disable update check
```
