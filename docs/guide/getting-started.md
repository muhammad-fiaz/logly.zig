# Getting Started

Get started with Logly-Zig in minutes.

## Prerequisites

- Zig 0.15.0 or higher
- Basic familiarity with Zig

## Installation

### Using Zig Package Manager

Add Logly-Zig to your `build.zig.zon`:

```zig
.{
    .name = "my-project",
    .version = "0.1.0",
    .dependencies = .{
        .logly = .{
            .url = "https://github.com/muhammad-fiaz/logly.zig/archive/refs/tags/v0.0.1.tar.gz",
            .hash = "1220...", // Run zig build to get the hash
        },
    },
}
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
    const logly = b.dependency("logly", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("logly", logly.module("logly"));

    b.installArtifact(exe);
}
```

### Fetch Dependencies

```bash
zig build
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

    const logger = try logly.Logger.init(allocator);
    defer logger.deinit();

    try logger.info("Logly-Zig is working!");
}
```

Build and run:

```bash
zig build run
```

You should see:

```
[INFO] Logly-Zig is working!
```

## Next Steps

- [Quick Start](/guide/quick-start) - Learn the basics
- [Configuration](/guide/configuration) - Configure your logger
- [Examples](/examples/basic) - See more examples
