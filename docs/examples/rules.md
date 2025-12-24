# Rules System Example

This example demonstrates the comprehensive rules system for compiler-style guided diagnostics.

## Overview

The Rules system attaches contextual diagnostic messages to log entries based on configurable conditions. This provides IDE-style guidance including error analysis, solutions, documentation links, and best practices.

## Features Demonstrated

- Adding rules with level matching
- Multiple message categories (cause, fix, docs, perf, security)
- Unicode and ASCII output modes
- Rule management (enable, disable, remove)
- Statistics tracking
- JSON output formatting
- Callbacks for rule events

## Complete Example

::: code-group
```zig [examples/rules.zig]
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Enable ANSI colors for Windows
    _ = logly.Terminal.enableAnsiColors();

    std.debug.print("\n", .{});
    std.debug.print("╔══════════════════════════════════════════════════════════════╗\n", .{});
    std.debug.print("║           Logly Rules System - Complete Demo                 ║\n", .{});
    std.debug.print("╚══════════════════════════════════════════════════════════════╝\n\n", .{});

    // Setup: Create logger with rules enabled
    var config = logly.Config.default();
    config.rules = logly.Config.RulesConfig.development();
    config.color = true;

    const logger = try logly.Logger.initWithConfig(allocator, config);
    defer logger.deinit();

    // Create and configure rules engine
    var rules = logly.Rules.init(allocator);
    defer rules.deinit();
    rules.enable();

    // Rule 1: Database error handling
    const db_messages = [_]logly.Rules.RuleMessage{
        logly.Rules.RuleMessage.cause("Database connection pool exhausted"),
        logly.Rules.RuleMessage.fix("Increase max_connections in database.yml or implement connection pooling"),
        logly.Rules.RuleMessage.docs("Connection Guide", "https://docs.example.com/db-pooling"),
    };

    try rules.add(.{
        .id = 1,
        .name = "database-error",
        .level_match = .{ .exact = .err },
        .message_contains = "Database",
        .messages = &db_messages,
    });

    // Rule 2: Performance warnings
    const perf_messages = [_]logly.Rules.RuleMessage{
        logly.Rules.RuleMessage.caution("Operation exceeded performance threshold"),
        logly.Rules.RuleMessage.perf("Consider caching frequently accessed data"),
        logly.Rules.RuleMessage.suggest("Use async operations for I/O bound tasks"),
    };

    try rules.add(.{
        .id = 2,
        .name = "performance-warning",
        .level_match = .{ .exact = .warning },
        .messages = &perf_messages,
    });

    // Rule 3: Security alerts
    const security_messages = [_]logly.Rules.RuleMessage{
        logly.Rules.RuleMessage.security("Critical security event detected"),
        logly.Rules.RuleMessage.action("Immediately review security logs and audit trail"),
        logly.Rules.RuleMessage.report("Security Team", "https://internal.example.com/security/report"),
    };

    try rules.add(.{
        .id = 3,
        .name = "security-alert",
        .level_match = .{ .exact = .critical },
        .messages = &security_messages,
    });

    // Attach rules to logger
    logger.setRules(&rules);

    // Test rules with logging
    try logger.err("Database connection timeout after 30s", @src());
    try logger.warning("Query took 2.5s to execute", @src());
    try logger.critical("Authentication bypass detected", @src());

    // Statistics
    const stats = rules.getStats();
    std.debug.print("\n=== Rules Statistics ===\n", .{});
    std.debug.print("Rules evaluated: {}\n", .{stats.rules_evaluated.load(.monotonic)});
    std.debug.print("Rules matched: {}\n", .{stats.rules_matched.load(.monotonic)});
    std.debug.print("Messages emitted: {}\n", .{stats.messages_emitted.load(.monotonic)});
    std.debug.print("Match rate: {d:.1}%\n", .{stats.matchRate() * 100});
}
```
:::

## Running the Example

```bash
zig build run-rules
```

## Expected Output

```
╔══════════════════════════════════════════════════════════════╗
║           Logly Rules System - Complete Demo                 ║
╚══════════════════════════════════════════════════════════════╝

[2024-12-24 12:00:00.000] [ERROR] Database connection timeout after 30s
    ↳ ⦿ cause: Database connection pool exhausted
    ↳ ✦ fix: Increase max_connections in database.yml or implement connection pooling
    ↳ 📖 docs: Connection Guide: See documentation (https://docs.example.com/db-pooling)

[2024-12-24 12:00:00.001] [WARNING] Query took 2.5s to execute
    ↳ ⚠ caution: Operation exceeded performance threshold
    ↳ ⚡ perf: Consider caching frequently accessed data
    ↳ → suggest: Use async operations for I/O bound tasks

[2024-12-24 12:00:00.002] [CRITICAL] Authentication bypass detected
    ↳ 🛡 security: Critical security event detected
    ↳ ▸ action: Immediately review security logs and audit trail
    ↳ 🔗 report: Security Team: Report issue (https://internal.example.com/security/report)

=== Rules Statistics ===
Rules evaluated: 3
Rules matched: 3
Messages emitted: 9
Match rate: 100.0%
```

## Message Categories

| Category | Symbol | Use Case |
|----------|--------|----------|
| `cause` | ⦿ | Root cause analysis |
| `fix` | ✦ | Solution suggestions |
| `suggest` | → | Best practices |
| `action` | ▸ | Required actions |
| `docs` | 📖 | Documentation links |
| `report` | 🔗 | Issue tracker links |
| `note` | ℹ | Additional information |
| `caution` | ⚠ | Warning details |
| `perf` | ⚡ | Performance tips |
| `security` | 🛡 | Security notices |

## Level Matching Options

```zig
// Exact level match
.level_match = .{ .exact = .err }

// Minimum priority (error and above)
.level_match = .{ .min_priority = 40 }

// Priority range (warning through critical)
.level_match = .{ .priority_range = .{ .min = 30, .max = 50 } }

// Custom level by name
.level_match = .{ .custom_name = "AUDIT" }

// Match any level
.level_match = .{ .any = {} }
```

## Configuration Presets

```zig
// Development (with rule IDs)
config.rules = logly.Config.RulesConfig.development();

// Production (no colors, minimal)
config.rules = logly.Config.RulesConfig.production();

// ASCII-only (for non-Unicode terminals)
config.rules = logly.Config.RulesConfig.ascii();

// Custom configuration
config.rules = .{
    .enabled = true,
    .use_unicode = true,
    .enable_colors = true,
    .show_rule_id = false,
    .include_in_json = true,
};
```

## JSON Output

```zig
var json_buf: std.ArrayList(u8) = .empty;
defer json_buf.deinit(allocator);

try rules.formatMessagesJson(&messages, json_buf.writer(allocator), true);
```

```json
[
    {
        "category": "error_analysis",
        "message": "Database connection pool exhausted"
    },
    {
        "category": "solution_suggestion",
        "message": "Increase max_connections"
    }
]
```

## See Also

- [Rules API Reference](/api/rules)
- [Configuration Guide](/guide/configuration)
- [Custom Levels](/guide/custom-levels)
