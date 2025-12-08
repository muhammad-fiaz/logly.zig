# Update Checker

Logly-Zig includes a built-in update checker that runs on startup to notify you of new releases.

## How it Works

When the `Logger` is initialized, it spawns a lightweight background thread that:
1.  Checks the current version of Logly-Zig (embedded from `build.zig.zon`).
2.  Queries the GitHub API for the latest release of `muhammad-fiaz/logly.zig`.
3.  Compares the versions.
4.  If a new version is available, it prints a non-intrusive message to the console.

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
