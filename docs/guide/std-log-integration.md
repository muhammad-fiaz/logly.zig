---
title: Native std.log Integration
description: Route every std.log.* call (and any third-party scoped variant) into your active logly logger through logly.stdLogFn.
head:
  - - meta
    - name: keywords
      content: logly, zig, std.log, logFn, std_options, native integration
---

# Native `std.log` Integration

Logly ships a `logFn` callback that you can plug straight into `std_options` in your root Zig file. Every `std.log.{err, warn, info, debug}` call (and any third-party `std.log.scoped(...)` variant) is then routed into your active logly logger — including internal logly warnings such as "thread count exceeds host cores".

> [!TIP]
> Add the following to your project root file:
> ```zig
> pub const std_options: std.Options = .{
>     .log_level = .info,
>     .logFn = logly.stdLogFn,
> };
> ```
> The `std.log.scoped(...)` macro and the `default` scope are both supported.

## Wiring an Active Logger

`logly.stdLogFn` forwards messages to the active logger registered through `logly.crash.registerLogger`. If no logger is registered, the call is silently dropped (which is the safe default for tests that do not need a logger).

```zig
const logly = @import("logly");
const std = @import("std");

pub const std_options: std.Options = .{
    .log_level = .info,
    .logFn = logly.stdLogFn,
};

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();

    const logger = try logly.Logger.init(.default());
    defer logger.deinit();
    logly.crash.registerLogger(logger);

    std.log.info("user logged in id={d}", .{42});
    std.log.warn("high latency on /checkout: {d}ms", .{530});
    std.log.err("database connection failed", .{});
    std.log.debug("cache miss for key={s}", .{"order:42"});
}
```

## Level Mapping

`std.log.Level` is mapped to `logly.Level` as follows:

| `std.log.Level` | `logly.Level` |
| --------------- | ------------- |
| `.err`          | `.err`        |
| `.warn`         | `.warning`    |
| `.info`         | `.info`       |
| `.debug`        | `.debug`      |

## Scopes

`std.log.scoped` is preserved. The scope name is forwarded into logly's `module` field. The default scope is recorded with `module = null`.

## Internal Log Capture

When the bridge is wired, logly's own `std.log.warn` calls (for example "thread pool requested 45 exceeds host cores 22") are also captured by the active logger.

> [!IMPORTANT]
> If no logger is registered, those internal warnings are dropped on the floor. This is intentional — logly never silently swallows messages in production code that has a logger attached.

## Long Messages

The bridge formats into a 4 KiB stack scratch buffer. If the formatted message exceeds 4 KiB, the call falls back to a tail-format path that still does not perform a heap allocation.
