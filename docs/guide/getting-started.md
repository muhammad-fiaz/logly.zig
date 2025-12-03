# Getting Started

Get started with Logly-Zig in minutes.

## Prerequisites

- Zig 0.15.0 or higher
- Basic familiarity with Zig

## Installation

### Method 1: Using Zig Fetch (Recommended)

The easiest way to install Logly-Zig is using the `zig fetch` command:

```bash
zig fetch --save https://github.com/muhammad-fiaz/logly.zig/archive/refs/tags/v0.0.3.tar.gz
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
            .url = "https://github.com/muhammad-fiaz/logly.zig/archive/refs/tags/v0.0.3.tar.gz",
            .hash = "1220...", // Run: zig fetch <url> to get this hash
        },
    },
}
```

To get the hash manually, run:
```bash
zig fetch https://github.com/muhammad-fiaz/logly.zig/archive/refs/tags/v0.0.3.tar.gz
```

Copy the output hash (e.g., `1220abcd23f9f0c8...`) into your `build.zig.zon`.

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

## Troubleshooting

### Hash Mismatch Error

If you see a hash mismatch error, run:
```bash
zig fetch --save https://github.com/muhammad-fiaz/logly.zig/archive/refs/tags/v0.0.3.tar.gz
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
