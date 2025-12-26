---
title: Installation Guide
description: Install Logly.zig in your Zig project using zig fetch, manual configuration, or prebuilt libraries. Supports Windows, Linux, macOS, and bare-metal targets with step-by-step instructions.
head:
  - - meta
    - name: keywords
      content: install logly, zig package manager, zig fetch, build.zig.zon, zig library installation, prebuilt zig libraries
---

# Installation

This guide covers all available methods to install Logly.zig in your project.

## Prerequisites

- **Zig 0.15.0** or higher
- Basic familiarity with Zig

## Method 1: Using Zig Fetch (Recommended)

The easiest way to install Logly-Zig is using the `zig fetch` command:

```bash
zig fetch --save https://github.com/muhammad-fiaz/logly.zig/archive/refs/tags/0.1.0.tar.gz
```

**Or for Nightly/PreRelease:**

```bash
zig fetch --save git+https://github.com/muhammad-fiaz/logly.zig.git
```

This command automatically:
1. Downloads the package
2. Calculates the hash
3. Adds it to your `build.zig.zon`

## Method 2: Manual Installation

If you prefer manual installation, add to your `build.zig.zon`:

```zig
.{
    .name = "my-project",
    .version = "0.1.0",
    .dependencies = .{
        .logly = .{
            .url = "https://github.com/muhammad-fiaz/logly.zig/archive/refs/tags/0.1.0.tar.gz",
            .hash = "1220...", // Run: zig fetch <url> to get this hash
        },
    },
}
```

To get the hash manually, run:

```bash
zig fetch https://github.com/muhammad-fiaz/logly.zig/archive/refs/tags/0.1.0.tar.gz
```

Copy the output hash (e.g., `1220abcd23f9f0c8...`) into your `build.zig.zon`.

## Method 3: Prebuilt Libraries

While we recommend using the Zig Package Manager, we also provide prebuilt static libraries for each release on the [Releases](https://github.com/muhammad-fiaz/logly.zig/releases) page. These can be useful for integration with other build systems or languages.

### Available Prebuilt Libraries

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

### Using Prebuilt Libraries

1. Download the appropriate library from the [Releases](https://github.com/muhammad-fiaz/logly.zig/releases) page
2. Place it in your project (e.g., `libs/` folder)
3. Update your `build.zig`:

```zig
// Assuming you downloaded the library to `libs/`
exe.addLibraryPath(b.path("libs"));
exe.linkSystemLibrary("logly");
```

## Configuring build.zig

After adding the dependency, update your `build.zig` to use Logly:

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

## Verifying Installation

Create a simple test file `src/main.zig`:

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const logger = try logly.Logger.init(allocator);
    defer logger.deinit();

    try logger.info("Logly installed successfully!", @src());
}
```

Build and run:

```bash
zig build run
```

You should see colored output:

```
2024-12-24 12:00:00.000 | INFO  | Logly installed successfully!
```

## Build Options

Logly supports several build options that can be passed to the dependency:

```zig
const logly_dep = b.dependency("logly", .{
    .target = target,
    .optimize = optimize,
    // Optional build options can be added here
});
```

### Available Build Modes

| Mode | Description | Use Case |
|------|-------------|----------|
| `Debug` | Full debug info, no optimization | Development |
| `ReleaseSafe` | Optimized with safety checks | Testing |
| `ReleaseFast` | Maximum optimization | Production |
| `ReleaseSmall` | Size optimization | Embedded |

## Troubleshooting

### Hash Mismatch Error

If you get a hash mismatch error:

```bash
error: hash mismatch
```

Update the hash in your `build.zig.zon` by running:

```bash
zig fetch https://github.com/muhammad-fiaz/logly.zig/archive/refs/tags/0.1.0.tar.gz
```

### Module Not Found

If you get "module 'logly' not found":

1. Ensure the dependency is correctly added to `build.zig.zon`
2. Verify `build.zig` has the correct import line:
   ```zig
   exe.root_module.addImport("logly", logly_dep.module("logly"));
   ```

### Network Issues

If you're behind a firewall or have network issues:

1. Download the tarball manually from GitHub
2. Use local path in `build.zig.zon`:
   ```zig
   .logly = .{
       .path = "../logly.zig",
   },
   ```

## Updating Logly

To update to a newer version:

1. Update the URL in `build.zig.zon` to the new version tag
2. Run `zig fetch` to get the new hash
3. Update the hash in `build.zig.zon`
4. Rebuild your project

Or simply run:

```bash
zig fetch --save https://github.com/muhammad-fiaz/logly.zig/archive/refs/tags/NEW_VERSION.tar.gz
```

## Next Steps

- [Quick Start Guide](quick-start.md) - Get logging in 5 minutes
- [Configuration Guide](configuration.md) - Customize your logger
- [API Reference](../api/logger.md) - Full API documentation

## See Also

- [GitHub Repository](https://github.com/muhammad-fiaz/logly.zig)
- [Releases Page](https://github.com/muhammad-fiaz/logly.zig/releases)
- [Zig Package Manager Documentation](https://ziglang.org/documentation/master/#Package-Management)
