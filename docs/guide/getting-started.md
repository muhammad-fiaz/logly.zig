# Getting Started

Get started with Logly-Zig in minutes.

## Prerequisites

- Zig 0.15.0 or higher
- Basic familiarity with Zig

## Installation

### Method 1: Using Zig Fetch (Recommended)

The easiest way to install Logly-Zig is using the `zig fetch` command:

```bash
zig fetch --save https://github.com/muhammad-fiaz/logly.zig/archive/refs/tags/v0.0.6.tar.gz
```

This command automatically:
1. Downloads the package
2. Calculates the hash
3. Adds it to your `build.zig.zon`

### Method 2: Manual Installation

If you prefer manual installation, add to your `build.zig.zon`:

```zig
.{
    .name = "my-project",
    .version = "0.1.0",
    .dependencies = .{
        .logly = .{
            .url = "https://github.com/muhammad-fiaz/logly.zig/archive/refs/tags/v0.0.6.tar.gz",
            .hash = "1220...", // Run: zig fetch <url> to get this hash
        },
    },
}
```

To get the hash manually, run:
```bash
zig fetch https://github.com/muhammad-fiaz/logly.zig/archive/refs/tags/v0.0.6.tar.gz
```

Copy the output hash (e.g., `1220abcd23f9f0c8...`) into your `build.zig.zon`.

### Method 3: Prebuilt Libraries

While we recommend using the Zig Package Manager, we also provide prebuilt static libraries for each release on the [Releases](https://github.com/muhammad-fiaz/logly.zig/releases) page. These can be useful for integration with other build systems or languages.

**Available Prebuilt Libraries:**

| Platform | Architecture | File |
|----------|-------------|------|
| **Windows** | x86_64 | `logly-x86_64-windows.lib` |
| **Windows** | x86 | `logly-x86-windows.lib` |
| **Linux** | x86_64 | `liblogly-x86_64-linux.a` |
| **Linux** | x86 | `liblogly-x86-linux.a` |
| **Linux** | ARM64 | `liblogly-aarch64-linux.a` |
| **macOS** | x86_64 | `liblogly-x86_64-macos.a` |
| **macOS** | ARM64 (Apple Silicon) | `liblogly-aarch64-macos.a` |
| **Bare Metal** | x86_64 | `liblogly-x86_64-freestanding.a` |
| **Bare Metal** | ARM64 | `liblogly-aarch64-freestanding.a` |
| **Bare Metal** | RISC-V 64 | `liblogly-riscv64-freestanding.a` |
| **Bare Metal** | ARM | `liblogly-arm-freestanding.a` |

**Using Prebuilt Libraries:**

1. Download the appropriate library from the [Releases](https://github.com/muhammad-fiaz/logly.zig/releases) page
2. Place it in your project (e.g., `libs/` folder)
3. Update your `build.zig`:

```zig
// Assuming you downloaded the library to `libs/`
exe.addLibraryPath(b.path("libs"));
exe.linkSystemLibrary("logly");
```

### Update build.zig

Add the dependency to your `build.zig`:

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "my-app",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add logly dependency
    const logly_dep = b.dependency("logly", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("logly", logly_dep.module("logly"));

    b.installArtifact(exe);

    // Add run step
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    const run_step = b.step("run", "Run the application");
    run_step.dependOn(&run_cmd.step);
}
```

### Build & Run

```bash
# Build the project
zig build

# Run the application
zig build run
```

## Verify Installation

Create a simple test file `src/main.zig`:

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Enable ANSI colors on Windows (no-op on Linux/macOS)
    _ = logly.Terminal.enableAnsiColors();

    const logger = try logly.Logger.init(allocator);
    defer logger.deinit();

    // Entire log lines are colored by level!
    try logger.info("Logly-Zig is working!");      // White line
    try logger.success("Installation complete!");  // Green line
    try logger.warning("Ready for production!");   // Yellow line
}
```

Build and run:

```bash
zig build run
```

You should see colored output:

```
[2024-01-15 10:30:45] [INFO] Logly-Zig is working!
[2024-01-15 10:30:45] [SUCCESS] Installation complete!
[2024-01-15 10:30:45] [WARNING] Ready for production!
```

## Color Support

Logly-Zig provides **whole-line coloring** where the entire log line (timestamp, level, message) is colored based on the log level.

### Built-in Level Colors

| Level | Color | ANSI Code |
|-------|-------|-----------|
| TRACE | Cyan | 36 |
| DEBUG | Blue | 34 |
| INFO | White | 37 |
| SUCCESS | Green | 32 |
| WARNING | Yellow | 33 |
| ERROR | Red | 31 |
| FAIL | Magenta | 35 |
| CRITICAL | Bright Red | 91 |

### Custom Colors

You can create custom log levels with any ANSI color code:

```zig
// Add custom level with cyan bold color
try logger.addCustomLevel("NOTICE", 35, "36;1");

// Use the custom level
try logger.custom("NOTICE", "Custom notice message");
```

**Common ANSI color codes:**
- `30` - Black
- `31` - Red
- `32` - Green
- `33` - Yellow
- `34` - Blue
- `35` - Magenta
- `36` - Cyan
- `37` - White
- `90-97` - Bright variants
- Add `;1` for bold (e.g., `36;1` for cyan bold)
- Add `;4` for underline (e.g., `31;4` for red underline)

### Disabling Colors

```zig
// Global color disable
var config = logly.Config.default();
config.global_color_display = false;
logger.configure(config);

// Per-sink color disable
_ = try logger.addSink(.{
    .path = "logs/app.log",
    .color = false,  // No colors in file
});
```

## Troubleshooting

### Hash Mismatch Error

If you see a hash mismatch error, run:
```bash
zig fetch --save https://github.com/muhammad-fiaz/logly.zig/archive/refs/tags/v0.0.4.tar.gz
```

### Colors Not Displaying on Windows

Make sure to call `Terminal.enableAnsiColors()` before logging:
```zig
_ = logly.Terminal.enableAnsiColors();
```

### Module Not Found

Ensure your `build.zig` includes:
```zig
exe.root_module.addImport("logly", logly_dep.module("logly"));
```

## Next Steps

- [Quick Start](/guide/quick-start) - Learn the basics
- [Configuration](/guide/configuration) - Configure your logger
- [Custom Levels](/guide/custom-levels) - Create custom log levels with colors
- [Formatting](/guide/formatting) - Customize log output format
- [Examples](/examples/basic) - See more examples
