---
title: Update Checker
description: Stay up to date with the built-in update checker in Logly.zig. Automatically notify of new releases in a non-intrusive background thread.
head:
  - - meta
    - name: keywords
      content: update checker, version check, github api, background thread, release notification, non-blocking update, zig logging
  - - meta
    - property: og:title
      content: Update Checker | Logly.zig
  - - meta
    - property: og:image
      content: https://muhammad-fiaz.github.io/logly.zig/cover.png
---

# Update Checker

Logly-Zig includes a built-in update checker that runs on startup to notify you of new releases.

When the `Logger` is initialized, it performs a non-blocking check for updates:
1.  **Thread Pool Integration**: If a `ThreadPool` is configured, it submits the check as a background task.
2.  **Fallback Threading**: If no thread pool is available, it spawns a dedicated lightweight background thread.
3.  **Version Comparison**: It compares the current version (from `build.zig.zon`) with the latest release from the GitHub API.
4.  **Silent Results**: If an update is available (or if running a nightly build), it prints a non-intrusive notification.
5.  **Failure Tolerance**: It fails silently on network errors or API rate limits.

## Configuration

The update checker is enabled by default. You can disable it in the configuration:

```zig
var config = logly.Config.default();
config.check_for_updates = false; // Disable update check

const logger = try logly.Logger.initWithConfig(allocator, config);
```

## Behavior

-   **Non-blocking**: The check runs in a background thread, so it never slows down your application startup.
-   **Silent Failure**: If there is no internet connection or the GitHub API is unreachable, the checker fails silently without printing errors or affecting your application.
-   **Cross-Platform**: Uses ASCII-safe message formatting compatible with all terminals (PowerShell, cmd, Linux, macOS).

## Example Output

Newer version available:
```text
info: [UPDATE] A newer release is available: v0.0.5 (current 0.0.4)
```

Running a dev/nightly build:
```text
info: [NIGHTLY] Running a dev/nightly build ahead of latest release: current 0.0.5, latest 0.0.4
```

## Platform Support

Works correctly on:
- **Windows**: PowerShell, Windows Terminal, cmd.exe
- **Linux**: All standard terminals
- **macOS**: Terminal, iTerm, and other terminal emulators
- **VSCode**: Integrated terminal
