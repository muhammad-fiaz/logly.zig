---
title: Invoke API Reference
description: API reference for Logly.zig Invoke module. Attach extra messages to log records when conditions match — level-based, message content, custom levels, and more.
head:
  - - meta
    - name: keywords
      content: invoke api, log triggers, extra messages, diagnostic messages, level matching, custom levels
  - - meta
    - property: og:title
      content: Invoke API Reference | Logly.zig
---

# Invoke API

The Invoke module attaches extra messages to log records when conditions match. When a log entry matches a trigger's conditions, the trigger's messages are appended to the record.

## Quick Reference

| Method | Description |
|--------|-------------|
| `init(allocator)` | Initialize the invoke engine |
| `deinit()` | Free all resources |
| `enable()` | Enable the engine |
| `disable()` | Disable the engine |
| `isEnabled()` | Check if enabled |
| `add(trigger)` | Add a trigger |
| `addOrUpdate(trigger)` | Add or update a trigger |
| `remove(id)` | Remove a trigger by ID |
| `getById(id)` | Get a trigger by ID |
| `clear()` | Remove all triggers |
| `count()` | Get trigger count |
| `evaluate(record)` | Evaluate triggers against a record |
| `formatMessages(messages, writer, useColor)` | Format messages for output |
| `formatMessagesJson(messages, writer, pretty)` | Format messages as JSON |
| `getStats()` | Get evaluation statistics |
| `resetStats()` | Reset statistics |

## Types

### `Message`

Just `[]const u8`. Write whatever you want — prefix, color codes, emoji, formatting — it all goes through as-is.

```zig
const Message = []const u8;
```

### `LevelMatch`

How to match log levels.

```zig
pub const LevelMatch = union(enum) {
    exact: Level,           // Exact level match
    minPriority: u8,       // Minimum priority threshold
    maxPriority: u8,       // Maximum priority threshold
    priorityRange: struct { min: u8, max: u8 }, // Priority range
    customName: []const u8, // Custom level name
    any: void,              // Matches any level
};
```

### `Trigger`

A trigger definition.

```zig
pub const Trigger = struct {
    id: u32,                              // Unique ID
    name: ?[]const u8 = null,             // Optional name
    enabled: bool = true,                 // Enable/disable
    once: bool = false,                   // Fire only once
    levelMatch: ?LevelMatch = null,      // Level condition
    module: ?[]const u8 = null,           // Module filter
    function: ?[]const u8 = null,         // Function filter
    messageContains: ?[]const u8 = null, // Substring match
    messageRegex: ?[]const u8 = null,    // Regex match
    minDurationNs: ?u64 = null,         // Duration threshold
    messages: []const Message,            // Messages to append
    priority: u8 = 100,                   // Evaluation priority
    cooldownMs: u64 = 0,                // Min interval between fires
};
```

### `Stats`

```zig
pub const Stats = struct {
    pub fn getTriggersEvaluated(self: *const Stats) u64;
    pub fn getTriggersMatched(self: *const Stats) u64;
    pub fn getMessagesEmitted(self: *const Stats) u64;
    pub fn reset(self: *Stats) void;
};
```

## Usage

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var config = logly.Config{};
    config.rules.enabled = true;

    var logger = try logly.Logger.initWithConfig(allocator, config);
    defer logger.deinit();

    var invoke = logly.Invoke.init(allocator);
    defer invoke.deinit();
    invoke.enable();

    // Error trigger
    const err_msgs = []logly.Invoke.Message{
        ">> [ERROR] Database connection pool exhausted",
        ">> [FIX] Increase max_connections in database.yml",
    };

    try invoke.add(.{
        .id = 1,
        .levelMatch = .{ .exact = .err },
        .messageContains = "database",
        .messages = &err_msgs,
    });

    logger.setInvoke(&invoke);

    try logger.err("database connection timeout", @src());
    // Output:
    // [ERROR] database connection timeout
    // >> [ERROR] Database connection pool exhausted
    // >> [FIX] Increase max_connections in database.yml
}
```

## Level Matching

```zig
// Exact level
.levelMatch = .{ .exact = .err }

// Minimum priority (matches err, critical, etc.)
.levelMatch = .{ .minPriority = 40 }

// Priority range (matches warning and err)
.levelMatch = .{ .priorityRange = .{ .min = 30, .max = 40 } }

// Custom level by name
.levelMatch = .{ .customName = "audit" }

// Any level
.levelMatch = .{ .any = {} }
```

## Message Filtering

```zig
// Substring match
.messageContains = "database"

// Regex match
.messageRegex = "out of memory \\d+"

// Duration-based (500ms+)
.minDurationNs = 500_000_000
```

## Once-Fire Triggers

```zig
try invoke.add(.{
    .id = 1,
    .once = true,
    .levelMatch = .{ .exact = .info },
    .messages = &messages,
});
// Fires once, then automatically disabled
```

## Cooldown

```zig
try invoke.add(.{
    .id = 1,
    .cooldownMs = 10000, // Minimum 10 seconds between fires
    .messages = &messages,
});
```
