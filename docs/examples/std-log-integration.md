---
title: Native std.log Integration Example
description: Example of routing std.log.* calls into a logly logger through logly.stdLogFn, including scoped variants.
head:
  - - meta
    - name: keywords
    - content: std.log, logFn, std_options, native integration, logly
---

# Native `std.log` Integration Example

This example shows how to plug `logly.stdLogFn` into the `std_options` struct in your root file. Every `std.log.{err, warn, info, debug}` call (including third-party `std.log.scoped(...)` variants) is then routed into the active logly logger.

> [!NOTE]
> Run with: `zig build run-std_log_integration`

## Code Example

```zig
const std = @import("std");
const logly = @import("logly");

pub const std_options: std.Options = .{
    .log_level = .info,
    .logFn = logly.stdLogFn,
};

const my_lib = struct {
    pub fn compile(time_ms: u32) void {
        std.log.info("compiled in {d}ms", .{time_ms});
    }

    pub fn cache(key: []const u8) void {
        std.log.debug("cache miss for key={s}", .{key});
    }
};

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();

    const logger = try logly.Logger.initWithConfig(gpa.allocator(), .default());
    defer logger.deinit();
    logly.crash.registerLogger(logger);

    std.log.info("user logged in id={d}", .{42});
    std.log.warn("high latency on /checkout: {d}ms", .{530});
    std.log.err("database connection failed", .{});
    my_lib.compile(12);
    my_lib.cache("order:42");
}
```

> [!TIP]
> `std.log.scoped("my_lib")` style is supported: the scope name is forwarded into logly's `module` field and the active logger's output is tagged with it.
