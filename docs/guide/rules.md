---
title: Rules System Guide
description: Learn how to use Logly.zig's Rules System for compiler-style guided diagnostics. Add contextual cause, fix, hint, and documentation messages to your logs automatically based on pattern matching.
head:
  - - meta
    - name: keywords
      content: logly rules, guided diagnostics, log analysis, error messages, debugging tips, log patterns, contextual logging
---

# Rules System Guide

The Rules system provides compiler-style guided diagnostics for your log messages. When a log entry matches a rule's conditions, contextual messages are automatically appended to help developers understand issues, find solutions, and access documentation.

## Why Use Rules?

Traditional logging tells you *what* happened. Rules tell you *why* it happened and *how* to fix it:

```
[ERROR] Database connection timeout
    ↳ ⦿ cause: Connection pool exhausted
    ↳ ✦ fix: Increase max_connections in database.yml
    ↳ 📖 docs: See https://docs.example.com/db-pooling
```

This transforms logs from passive records into active developer assistance.

## Getting Started

### 1. Enable Rules in Configuration

```zig
var config = logly.Config.default();
config.rules.enabled = true;  // Enable the rules system

const logger = try logly.Logger.initWithConfig(allocator, config);
```

### 2. Create a Rules Engine

```zig
var rules = logly.Rules.init(allocator);
defer rules.deinit();
rules.enable();  // Activate the engine
```

### 3. Define Rules

```zig
const messages = [_]logly.Rules.RuleMessage{
    logly.Rules.RuleMessage.cause("Database connection pool exhausted"),
    logly.Rules.RuleMessage.fix("Increase max_connections in database.yml"),
    logly.Rules.RuleMessage.docs("Connection Guide", "https://docs.example.com/db"),
};

try rules.add(.{
    .id = 1,
    .level_match = .{ .exact = .err },
    .message_contains = "Database",
    .messages = &messages,
});
```

### 4. Attach to Logger

```zig
logger.setRules(&rules);
```

Now when you log an error containing "Database", the rule messages will appear:

```zig
try logger.err("Database connection timeout", @src());
```

## Message Categories

Rules support multiple message categories, each with distinct styling:

| Category | Symbol | Purpose |
|----------|--------|---------|
| `error_analysis` (cause) | ⦿ | Root cause analysis |
| `solution_suggestion` (fix) | ✦ | How to fix the issue |
| `best_practice` (suggest) | → | Improvement suggestions |
| `action_required` (action) | ▸ | Required immediate actions |
| `documentation_link` (docs) | 📖 | Links to documentation |
| `bug_report` (report) | 🔗 | Issue tracker links |
| `general_information` (note) | ℹ | Additional context |
| `warning_explanation` (caution) | ⚠ | Warning details |
| `performance_tip` (perf) | ⚡ | Performance advice |
| `security_notice` (security) | 🛡 | Security notifications |
| `custom` | • | User-defined style |

### Creating Messages

Use the convenient builder methods:

```zig
// Simple messages
logly.Rules.RuleMessage.cause("Root cause explanation")
logly.Rules.RuleMessage.fix("How to fix this")
logly.Rules.RuleMessage.suggest("Best practice tip")
logly.Rules.RuleMessage.action("Required action")
logly.Rules.RuleMessage.note("Additional information")
logly.Rules.RuleMessage.caution("Warning details")
logly.Rules.RuleMessage.perf("Performance tip")
logly.Rules.RuleMessage.security("Security notice")

// With documentation URL
logly.Rules.RuleMessage.docs("API Reference", "https://api.example.com/docs")

// With issue tracker URL
logly.Rules.RuleMessage.report("GitHub Issue", "https://github.com/example/issues/123")

// Custom prefix and color
logly.Rules.RuleMessage.custom("    |-- [CUSTOM]", "Custom message")

// Chained modifiers
logly.Rules.RuleMessage.cause("Error").withColor("91;1")
logly.Rules.RuleMessage.fix("Solution").withUrl("https://docs.example.com")
```

## Level Matching

Rules can match logs based on various criteria:

### Exact Level

```zig
.level_match = .{ .exact = .err }  // Only ERROR level
.level_match = .{ .exact = .warning }  // Only WARNING level
```

### Priority Range

```zig
// Match warnings and above (WARNING, ERROR, FAIL, CRITICAL)
.level_match = .{ .min_priority = 30 }

// Match info and below (TRACE, DEBUG, INFO, SUCCESS)
.level_match = .{ .max_priority = 20 }

// Match specific range (WARNING through ERROR)
.level_match = .{ .priority_range = .{ .min = 30, .max = 40 } }
```

### Custom Levels

```zig
// Match custom level by name
.level_match = .{ .custom_name = "AUDIT" }
```

### Any Level

```zig
.level_match = .{ .any = {} }  // Match all levels
```

## Additional Filters

Rules can also filter by:

### Module

```zig
try rules.add(.{
    .id = 1,
    .module = "database",  // Only logs from this module
    .level_match = .{ .exact = .err },
    .messages = &messages,
});
```

### Function

```zig
try rules.add(.{
    .id = 2,
    .function = "connect",  // Only logs from this function
    .level_match = .{ .exact = .err },
    .messages = &messages,
});
```

### Message Content

```zig
try rules.add(.{
    .id = 3,
    .message_contains = "timeout",  // Only logs containing this text
    .level_match = .{ .exact = .err },
    .messages = &messages,
});
```

## Rule Management

### Adding Rules

```zig
// Add a new rule - returns error if ID already exists
try rules.add(.{
    .id = 1,
    .level_match = .{ .exact = .err },
    .messages = &messages,
});

// Add or update a rule (no error on duplicate ID)
try rules.addOrUpdate(.{
    .id = 1,
    .level_match = .{ .exact = .warning },
    .messages = &updated_messages,
});

// Check if rule exists
if (rules.hasRule(1)) {
    std.debug.print("Rule #1 exists\n", .{});
}

// Get rule count
const count = rules.count();
```

### Enable/Disable Rules

```zig
rules.disableRule(1);  // Disable rule #1
rules.enableRule(1);   // Re-enable rule #1
```

### Remove Rules

```zig
const removed = rules.remove(1);  // Returns true if found and removed
```

### Clear All Rules

```zig
rules.clear();
```

### Get Rule By ID

```zig
if (rules.getById(1)) |rule| {
    std.debug.print("Rule name: {s}\n", .{rule.name orelse "unnamed"});
}
```

### List Rules

```zig

try rules.list();  // Prints all rules to debug output
```

## One-Time Rules

Rules that should fire only once per session:

```zig
try rules.add(.{
    .id = 10,
    .once = true,  // Will fire only the first time
    .level_match = .{ .exact = .info },
    .message_contains = "started",
    .messages = &startup_messages,
});
```

Reset one-time rules:

```zig
rules.resetOnceFired();  // All once-rules can fire again
```

## Configuration Options

### Global Configuration

The rules system **respects global configuration switches** for console and file output:

```zig
var config = logly.Config.default();
config.rules = .{
    // Master switches
    .enabled = true,                    // Master switch for rules system
    .client_rules_enabled = true,       // Enable client-defined rules
    .builtin_rules_enabled = true,      // Enable built-in rules (reserved)

    // Display options
    .use_unicode = true,                // Use Unicode symbols (vs ASCII)
    .enable_colors = true,              // ANSI colors in output
    .show_rule_id = false,              // Show rule IDs for debugging
    .include_rule_id_prefix = false,    // Include "R0001:" prefix
    .rule_id_format = "R{d}",           // Custom rule ID format
    .indent = "    ",                   // Indentation for messages
    .message_prefix = "↳",              // Prefix character

    // Output control (respects global switches)
    .console_output = true,             // Output to console (AND'd with global_console_display)
    .file_output = true,                // Output to files (AND'd with global_file_storage)
    .include_in_json = true,            // Include in JSON output

    // Advanced options
    .verbose = false,                   // Full context output
    .max_rules = 1000,                  // Maximum rules allowed
    .max_messages_per_rule = 10,        // Max messages to show per match
    .sort_by_severity = false,          // Order by severity
};
```

### Global Switch Integration

Rule output is controlled by **both local and global settings**:

```zig
// Console output is shown ONLY when BOTH are true:
// - RulesConfig.console_output = true
// - Config.global_console_display = true

// File output is written ONLY when BOTH are true:
// - RulesConfig.file_output = true
// - Config.global_file_storage = true

// Color output is enabled ONLY when BOTH are true:
// - RulesConfig.enable_colors = true
// - Config.global_color_display = true
```

This allows you to:
- Disable ALL console output globally without changing rule settings
- Disable ONLY rule output while keeping other console output

```zig
// Disable ALL console output (including rules)
config.global_console_display = false;

// Or disable ONLY rule console output
config.rules.console_output = false;
```

### Configuration Presets

```zig
// Development: colors, Unicode, show rule IDs, verbose
config.rules = logly.Config.RulesConfig.development();

// Production: no colors, no verbose, minimal output
config.rules = logly.Config.RulesConfig.production();

// ASCII: for terminals without Unicode support
config.rules = logly.Config.RulesConfig.ascii();

// Disabled: zero overhead
config.rules = logly.Config.RulesConfig.disabled();

// Silent: rules evaluate but don't output
config.rules = logly.Config.RulesConfig.silent();

// Console only: no file output
config.rules = logly.Config.RulesConfig.consoleOnly();

// File only: no console output
config.rules = logly.Config.RulesConfig.fileOnly();
```

### Runtime Configuration

```zig
rules.setUnicode(false);          // Switch to ASCII mode
rules.setColors(true);            // Enable/disable colors
rules.setConfig(.{ .verbose = true });        // Update config
rules.enableConsoleOutput();      // Enable console output
rules.disableConsoleOutput();     // Disable console output
rules.enableFileOutput();         // Enable file output
rules.disableFileOutput();        // Disable file output
rules.setVerbose(true);           // Enable verbose mode
```

## Callbacks

Monitor rule activity with callbacks:

```zig
// Called when any rule matches
rules.setRuleMatchedCallback(fn (rule: *const Rules.Rule, record: *const Record) void {
    std.debug.print("Rule #{d} matched!\n", .{rule.id});
});

// Called for each rule evaluation
rules.setRuleEvaluatedCallback(fn (rule: *const Rules.Rule, record: *const Record, matched: bool) void {
    std.debug.print("Rule #{d}: {}\n", .{rule.id, matched});
});

// Called when messages are attached
rules.setMessagesAttachedCallback(fn (record: *const Record, count: usize) void {
    std.debug.print("{d} messages attached\n", .{count});
});

// Called before evaluation
rules.setBeforeEvaluateCallback(fn (record: *const Record) void {
    std.debug.print("Starting evaluation...\n", .{});
});

// Called after evaluation
rules.setAfterEvaluateCallback(fn (record: *const Record, matched_count: usize) void {
    std.debug.print("Matched {d} rules\n", .{matched_count});
});
```

## Statistics

Track rules performance:

```zig
const stats = rules.getStats();

std.debug.print("Rules evaluated: {}\n", .{stats.rules_evaluated.load(.monotonic)});
std.debug.print("Rules matched: {}\n", .{stats.rules_matched.load(.monotonic)});
std.debug.print("Messages emitted: {}\n", .{stats.messages_emitted.load(.monotonic)});
std.debug.print("Skipped (disabled): {}\n", .{stats.evaluations_skipped.load(.monotonic)});
std.debug.print("Match rate: {d:.1}%\n", .{stats.matchRate() * 100});

// Reset statistics
rules.resetStats();
```

## JSON Output

Export rule messages as JSON:

```zig
var buf: std.ArrayList(u8) = .empty;
defer buf.deinit(allocator);

try rules.formatMessagesJson(&messages, buf.writer(allocator), true);  // pretty=true
std.debug.print("{s}\n", .{buf.items});
```

Output:
```json
[
    {
        "category": "error_analysis",
        "message": "Database connection pool exhausted"
    },
    {
        "category": "solution_suggestion",
        "message": "Increase max_connections"
    },
    {
        "category": "documentation_link",
        "title": "Docs",
        "message": "See documentation",
        "url": "https://docs.example.com/db"
    }
]
```

## Best Practices

1. **Use descriptive rule IDs**: Group related rules with sequential IDs
2. **Keep messages actionable**: Provide specific guidance, not just descriptions
3. **Include documentation links**: Help developers find more information
4. **Use appropriate categories**: Choose semantically correct message types
5. **Filter precisely**: Use `message_contains` to avoid false positives
6. **Monitor statistics**: Track match rates to ensure rules are effective
7. **Disable in production** if performance is critical: Rules add ~microseconds per log

## Complete Example

See [examples/rules.zig](https://github.com/muhammad-fiaz/logly.zig/blob/main/examples/rules.zig) for a comprehensive demonstration.

## See Also

- [Rules API Reference](/api/rules)
- [Custom Levels Guide](/guide/custom-levels)
- [Configuration Guide](/guide/configuration)
