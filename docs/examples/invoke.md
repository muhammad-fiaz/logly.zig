---
title: Invoke System Example
description: Example of the Logly.zig Invoke system. Attach extra messages to log records when conditions match.
head:
  - - meta
    - name: keywords
      content: invoke example, log triggers, extra messages, guided diagnostics, pattern matching
  - - meta
    - property: og:title
      content: Invoke System Example | Logly.zig
---

# Invoke System Example

This example demonstrates the Invoke system for attaching extra messages to log records.

## Overview

The Invoke system watches log records and, when a trigger's conditions match, appends the trigger's messages to the record. Supports all built-in log levels plus custom levels.

## Features Demonstrated

- Level-based triggers
- Message content filtering
- Custom level triggers
- Duration-based triggers
- Once-fire triggers
- Statistics tracking

## Complete Example

::: code-group
```zig [examples/invoke.zig]
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    _ = logly.Terminal.enableAnsiColors();

    // Enable invoke in config
    var config = logly.Config{};
    config.rules.enabled = true;

    var logger = try logly.Logger.initWithConfig(allocator, config);
    defer logger.deinit();

    var invoke = logly.Invoke.init(allocator);
    defer invoke.deinit();
    invoke.enable();

    // 1. Database error trigger
    const err_msgs = [_]logly.Invoke.Message{
        ">> [ERROR] Database connection pool exhausted",
        ">> [FIX] Increase max_connections in database.yml",
        ">> [DOC] https://docs.example.com/db-pooling",
    };

    try invoke.add(.{
        .id = 1,
        .name = "db_pool_detector",
        .level_match = .{ .exact = .err },
        .message_contains = "database",
        .messages = &err_msgs,
    });

    // 2. Performance warning trigger
    const perf_msgs = [_]logly.Invoke.Message{
        ">> [WARN] Operation exceeded performance threshold",
        ">> [TIP] Consider caching frequently accessed data",
    };

    try invoke.add(.{
        .id = 2,
        .name = "perf_hint",
        .level_match = .{ .exact = .warning },
        .messages = &perf_msgs,
    });

    // 3. SQL injection detector (any level)
    const security_msgs = [_]logly.Invoke.Message{
        ">> [SECURITY] Possible SQL injection detected",
        ">> [ACTION] Reject request and log attacker IP",
    };

    try invoke.add(.{
        .id = 3,
        .name = "sqli_detector",
        .level_match = .{ .any = {} },
        .message_contains = "SELECT * FROM",
        .messages = &security_msgs,
    });

    // 4. Custom level trigger
    const audit_msgs = [_]logly.Invoke.Message{
        ">> [AUDIT] Sensitive data accessed",
    };

    try invoke.add(.{
        .id = 4,
        .name = "audit_detector",
        .level_match = .{ .custom_name = "audit" },
        .messages = &audit_msgs,
    });

    // 5. Slow operation detector (duration-based)
    const slow_msgs = [_]logly.Invoke.Message{
        ">> [SLOW] Operation exceeded 500ms latency budget",
    };

    try invoke.add(.{
        .id = 5,
        .name = "slow_op_detector",
        .level_match = .{ .any = {} },
        .min_duration_ns = 500_000_000,
        .messages = &slow_msgs,
    });

    logger.setInvoke(&invoke);

    // Test triggers
    try logger.err("database connection timeout after 30s", @src());
    try logger.warn("request processing slow", @src());
    try logger.info("SELECT * FROM users WHERE id = 1", @src());
    try logger.debug("entering function handle_request", @src());
    try logger.err("file not found: config.yaml", @src());

    // Statistics
    const stats = invoke.getStats();
    std.debug.print("\nEvaluated: {}\n", .{stats.getTriggersEvaluated()});
    std.debug.print("Matched:   {}\n", .{stats.getTriggersMatched()});
    std.debug.print("Emitted:   {}\n", .{stats.getMessagesEmitted()});
}
```
:::

## Expected Output

```text
[ERROR] database connection timeout after 30s
>> [ERROR] Database connection pool exhausted
>> [FIX] Increase max_connections in database.yml
>> [DOC] https://docs.example.com/db-pooling
[WARNING] request processing slow
>> [WARN] Operation exceeded performance threshold
>> [TIP] Consider caching frequently accessed data
[INFO] SELECT * FROM users WHERE id = 1
>> [SECURITY] Possible SQL injection detected
>> [ACTION] Reject request and log attacker IP
[ERROR] file not found: config.yaml

Evaluated: 4
Matched:   3
Emitted:   7
```

Notice:
- The database error triggered 3 extra messages
- The warning triggered 2 extra messages
- The SQL pattern triggered 2 extra messages
- The file-not-found error had no trigger (no "database" pattern)
- The debug message had no trigger (no matching conditions)
