# Compile-Time Configuration

Logly is designed for high performance with carefully tuned default constants. While most configuration happens at runtime via the `Config` struct, Logly exposes its internal compile-time constants and system settings through the `logly.Constants` module.

## Accessing Constants

You can access compile-time constants to align your application's logic with Logly's internal limits and defaults.

```zig
const logly = @import("logly");
const Constants = logly.Constants;

pub fn main() void {
    // Check internal buffer limits
    const max_msg = Constants.BufferSizes.max_message;
    std.debug.print("Logly max message size: {d} bytes\n", .{max_msg});
    
    // Check thread pool defaults
    const threads = Constants.ThreadDefaults.cpuBoundThreadCount();
    std.debug.print("Recommended threads: {d}\n", .{threads});
}
```

## Available Constant Groups

The `Constants` module is organized into several groups:

### Buffer Sizes (`Constants.BufferSizes`)
Defines the static buffer sizes used for various operations to avoid dynamic allocation overhead where possible.
- `message`: Default log message buffer size (Default: 4KB)
- `format`: Buffer size for formatting operations (Default: 8KB)
- `sink`: Buffer size for sink operations (Default: 16KB)
- `async_queue`: Buffer size for async queue (Default: 8KB)
- `max_message`: Maximum allowed log message size (Default: 1MB)

### Thread Defaults (`Constants.ThreadDefaults`)
Helper functions and constants for configuring the thread pool.
- `recommendedThreadCount()`: Returns optimal thread count for the system.
- `ioBoundThreadCount()`: Returns optimal count for I/O heavy logging.
- `cpuBoundThreadCount()`: Returns optimal count for compression/formatting.

### Time Constants (`Constants.TimeConstants`)
Time conversion factors and default intervals.
- `default_flush_interval_ms`: Default flush interval (100ms).
- `rotation_check_interval_ms`: Default file rotation check interval (1 min).

### Rotation Constants (`Constants.RotationConstants`)
Defaults for file rotation policies.
- `default_max_size`: Default max file size before rotation (10MB).
- `default_max_files`: Default number of backup files to keep (5).

## Platform-Specific Atomic Types

Logly automatically selects the optimal atomic integer types for the target architecture (`Constants.AtomicUnsigned`, `Constants.AtomicSigned`). You can use these types in your own code to ensure lock-free compatibility with Logly's internals.

```zig
const AtomicInt = logly.Constants.AtomicUnsigned;
var counter: AtomicInt = 0;
```

## Adding Compile-Time Log Filtering

To strictly remove log calls from your binary at compile-time (stripping distinct log levels), you can wrap Logly calls with a `comptime` check. This is similar to how `std.log` works but gives you explicit control.

```zig
const logly = @import("logly");
const build_config = @import("build_options"); // Your build options

// Wrapper function to strip debug logs at compile time
pub inline fn debug(logger: *logly.Logger, msg: []const u8, src: ?std.builtin.SourceLocation) !void {
    if (comptime build_config.enable_debug_logs) {
        try logger.debug(msg, src);
    }
}
```

This pattern ensures that if `enable_debug_logs` is `false`, the entire branch is eliminated by the Zig compiler, resulting in zero runtime overhead.
