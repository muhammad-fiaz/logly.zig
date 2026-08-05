---
title: Invoke System Guide
description: Learn how to use Logly.zig's Invoke system to attach extra messages to log records when conditions match.
head:
  - - meta
    - name: keywords
      content: logly invoke, log triggers, extra messages, guided diagnostics, error analysis, pattern matching
  - - meta
    - property: og:title
      content: Invoke System Guide | Logly.zig
---

# Invoke System Guide

The Invoke system attaches extra messages to log records when conditions match. When a log entry matches a trigger's conditions, the trigger's messages are automatically appended.

## Why Use Invoke?

Traditional logging tells you *what* happened. Invoke tells you *why* it happened and *how* to fix it:

```
[ERROR] Database connection timeout
>> [ERROR] Connection pool exhausted
>> [FIX] Increase max_connections in database.yml
>> [DOC] See https://docs.example.com/db-pooling
```

This transforms logs from passive records into active developer assistance.

## Getting Started

### 1. Enable Invoke in Configuration

```zig
var config = logly.Config{};
config.rules.enabled = true;

const logger = try logly.Logger.initWithConfig(allocator, config);
```

### 2. Create an Invoke Engine

```zig
var invoke = logly.Invoke.init(allocator);
defer invoke.deinit();
invoke.enable();
```

### 3. Define Triggers

```zig
const messages = [_]logly.Invoke.Message{
    ">> [ERROR] Database connection pool exhausted",
    ">> [FIX] Increase max_connections in database.yml",
    ">> [DOC] https://docs.example.com/db-pooling",
};

try invoke.add(.{
    .id = 1,
    .level_match = .{ .exact = .err },
    .message_contains = "database",
    .messages = &messages,
});
```

### 4. Attach to Logger

```zig
logger.setInvoke(&invoke);
```

### 5. Log Normally

```zig
try logger.err("database connection timeout", @src());
// Output:
// [ERROR] database connection timeout
// >> [ERROR] Database connection pool exhausted
// >> [FIX] Increase max_connections in database.yml
// >> [DOC] https://docs.example.com/db-pooling
```

## Level Matching

Triggers can match by exact level, priority range, or custom level name:

```zig
// Match errors only
.level_match = .{ .exact = .err }

// Match warnings and above
.level_match = .{ .min_priority = 30 }

// Match a custom level
.level_match = .{ .custom_name = "audit" }

// Match any level
.level_match = .{ .any = {} }
```

## Message Filtering

Triggers can filter by message content:

```zig
// Substring match
.message_contains = "database"

// Regex match
.message_regex = "out of memory \\d+"

// Duration-based (500ms+ operations)
.min_duration_ns = 500_000_000
```

## Once-Fire Triggers

Triggers can fire only once:

```zig
try invoke.add(.{
    .id = 1,
    .once = true,
    .level_match = .{ .exact = .info },
    .messages = &messages,
});
```

## Cooldown

Prevent trigger storms with cooldown:

```zig
try invoke.add(.{
    .id = 1,
    .cooldown_ms = 10000, // Minimum 10 seconds between fires
    .messages = &messages,
});
```

## Statistics

```zig
const stats = invoke.getStats();
std.debug.print("Evaluated: {}\n", .{stats.getTriggersEvaluated()});
std.debug.print("Matched:   {}\n", .{stats.getTriggersMatched()});
std.debug.print("Emitted:   {}\n", .{stats.getMessagesEmitted()});
```
