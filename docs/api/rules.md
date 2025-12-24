# Rules API

The Rules module provides a powerful compiler-style diagnostic system for log messages. It enables attaching contextual guidance, solutions, documentation links, and best practices to log entries based on configurable conditions.

## Overview

The rules system augments logging with intelligent diagnostics:
- **Zero overhead** when disabled
- **Thread-safe** rule evaluation
- **Multiple message categories** with professional styling
- **Custom colors and prefixes**
- **Callbacks** for rule matching and evaluation
- **JSON and text output** support

## Quick Start

```zig
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    // Enable ANSI colors
    _ = logly.Terminal.enableAnsiColors();

    // Configure rules
    var config = logly.Config.default();
    config.rules.enabled = true;

    const logger = try logly.Logger.initWithConfig(allocator, config);
    defer logger.deinit();

    // Create rules engine
    var rules = logly.Rules.init(allocator);
    defer rules.deinit();
    rules.enable();

    // Add a rule
    const messages = [_]logly.Rules.RuleMessage{
        logly.Rules.RuleMessage.cause("Database connection pool exhausted"),
        logly.Rules.RuleMessage.fix("Increase max_connections or implement connection pooling"),
        logly.Rules.RuleMessage.docs("Connection Guide", "https://docs.example.com/db"),
    };

    try rules.add(.{
        .id = 1,
        .level_match = .{ .exact = .err },
        .message_contains = "Database",
        .messages = &messages,
    });

    logger.setRules(&rules);

    // This will trigger the rule
    try logger.err("Database connection timeout", @src());
}
```

**Output:**
```
[2024-12-24 12:00:00.000] [ERROR] Database connection timeout
    ↳ ⦿ cause: Database connection pool exhausted
    ↳ ✦ fix: Increase max_connections or implement connection pooling
    ↳ 📖 docs: Connection Guide: See documentation (https://docs.example.com/db)
```

## Rules Struct

### Initialization

```zig
// Basic initialization
var rules = logly.Rules.init(allocator);
defer rules.deinit();

// With custom configuration
var rules = logly.Rules.initWithConfig(allocator, .{
    .use_unicode = true,
    .enable_colors = true,
    .show_rule_id = true,
});
```

### Methods

| Method | Description |
|--------|-------------|
| `init(allocator)` | Create a new Rules engine |
| `initWithConfig(allocator, config)` | Create with custom configuration |
| `deinit()` | Free all resources |
| `enable()` | Enable the rules engine |
| `disable()` | Disable the rules engine (zero overhead) |
| `isEnabled()` | Check if rules are enabled |
| `configure(config)` | Update configuration |
| `setUnicode(bool)` | Enable/disable Unicode symbols |
| `setColors(bool)` | Enable/disable ANSI colors |

### Rule Management

```zig
// Add a rule (returns error.RuleIdAlreadyExists if ID exists)
try rules.add(.{
    .id = 1,
    .name = "database-error",
    .level_match = .{ .exact = .err },
    .messages = &messages,
});

// Add or update a rule (no error on duplicate ID)
try rules.addOrUpdate(.{
    .id = 1,
    .name = "database-error-updated",
    .level_match = .{ .exact = .warning },
    .messages = &new_messages,
});

// Check if rule exists
if (rules.hasRule(1)) {
    std.debug.print("Rule #1 exists\n", .{});
}

// Remove a rule
const removed = rules.remove(1);

// Enable/disable specific rules
rules.enableRule(1);
rules.disableRule(1);

// Get rule by ID
if (rules.getById(1)) |rule| {
    std.debug.print("Rule enabled: {}\n", .{rule.enabled});
}

// Clear all rules
rules.clear();

// Get rule count
const count = rules.count();
```

| Method | Description |
|--------|-------------|
| `add(rule)` | Add a rule, error if ID exists |
| `addOrUpdate(rule)` | Add or update a rule |
| `hasRule(id)` | Check if rule ID exists |
| `remove(id)` | Remove a rule by ID |
| `enableRule(id)` | Enable a rule |
| `disableRule(id)` | Disable a rule |
| `getById(id)` | Get rule pointer by ID |
| `clear()` | Remove all rules |
| `count()` | Get rule count |


## Rule Struct

A rule defines when and what diagnostic messages to emit.

```zig
const Rule = struct {
    /// Unique rule identifier (required)
    id: u32,

    /// Human-readable name (optional)
    name: ?[]const u8 = null,

    /// Whether this rule is enabled
    enabled: bool = true,

    /// Fire only once per session
    once: bool = false,

    /// Level matching specification
    level_match: ?LevelMatch = null,

    /// Module filter (optional)
    module: ?[]const u8 = null,

    /// Function filter (optional)
    function: ?[]const u8 = null,

    /// Message pattern filter (optional)
    message_contains: ?[]const u8 = null,

    /// Diagnostic messages to emit when matched
    messages: []const RuleMessage,

    /// Priority (higher runs first)
    priority: u8 = 100,
};
```

### Level Matching

```zig
// Match exact level
.level_match = .{ .exact = .err }

// Match minimum priority and above
.level_match = .{ .min_priority = 40 }  // ERROR and above

// Match maximum priority and below
.level_match = .{ .max_priority = 20 }  // INFO and below

// Match priority range
.level_match = .{ .priority_range = .{ .min = 30, .max = 50 } }

// Match custom level by name
.level_match = .{ .custom_name = "AUDIT" }

// Match any level
.level_match = .{ .any = {} }
```

## MessageCategory Enum

Categories determine the styling and semantic meaning of rule messages.

| Category | Prefix (Unicode) | Color | Description |
|----------|------------------|-------|-------------|
| `error_analysis` | `⦿ cause:` | Bright Red | Root cause analysis |
| `solution_suggestion` | `✦ fix:` | Bright Cyan | How to fix the issue |
| `best_practice` | `→ suggest:` | Bright Yellow | Improvement suggestions |
| `action_required` | `▸ action:` | Bold Red | Required actions |
| `documentation_link` | `📖 docs:` | Magenta | Documentation links |
| `bug_report` | `🔗 report:` | Yellow | Issue tracker links |
| `general_information` | `ℹ note:` | White | Additional context |
| `warning_explanation` | `⚠ caution:` | Yellow | Warning details |
| `performance_tip` | `⚡ perf:` | Cyan | Performance advice |
| `security_notice` | `🛡 security:` | Bright Magenta | Security notifications |
| `custom` | `•` | White | User-defined style |

### Category Aliases

For convenience, shorter aliases are available:

```zig
// These are equivalent:
.category = .error_analysis
.category = .cause
.category = .diagnostic

// And these:
.category = .solution_suggestion
.category = .fix
.category = .help
```

## RuleMessage Struct

A message defines what to display when a rule matches.

```zig
const RuleMessage = struct {
    category: MessageCategory,
    title: ?[]const u8 = null,
    message: []const u8,
    url: ?[]const u8 = null,
    custom_color: ?[]const u8 = null,
    custom_prefix: ?[]const u8 = null,
    use_background: bool = false,
    background_color: ?[]const u8 = null,
};
```

### Message Builders

Create messages easily with builder functions:

```zig
const messages = [_]logly.Rules.RuleMessage{
    // Basic builders
    logly.Rules.RuleMessage.cause("Root cause analysis"),
    logly.Rules.RuleMessage.fix("Suggested solution"),
    logly.Rules.RuleMessage.suggest("Best practice tip"),
    logly.Rules.RuleMessage.action("Required action"),
    logly.Rules.RuleMessage.note("Additional information"),
    logly.Rules.RuleMessage.caution("Warning message"),
    logly.Rules.RuleMessage.perf("Performance tip"),
    logly.Rules.RuleMessage.security("Security notice"),

    // With URL
    logly.Rules.RuleMessage.docs("API Reference", "https://api.example.com"),
    logly.Rules.RuleMessage.report("GitHub Issue", "https://github.com/example/issues"),

    // Custom styling
    logly.Rules.RuleMessage.custom("    |-- [CUSTOM]", "Custom message"),

    // Chained modifiers
    logly.Rules.RuleMessage.cause("Error analysis").withColor("91;1"),
    logly.Rules.RuleMessage.fix("Solution").withUrl("https://docs.example.com"),
    logly.Rules.RuleMessage.note("Info").withTitle("Important"),
};
```

## Callbacks

Set callbacks for rule events:

```zig
// Called when a rule matches
rules.setRuleMatchedCallback(fn (rule: *const Rules.Rule, record: *const Record) void {
    std.debug.print("Rule #{d} matched: {s}\n", .{rule.id, rule.name orelse "unnamed"});
});

// Called for each rule evaluation
rules.setRuleEvaluatedCallback(fn (rule: *const Rules.Rule, record: *const Record, matched: bool) void {
    std.debug.print("Rule #{d} evaluated: {}\n", .{rule.id, matched});
});

// Called when messages are attached to a record
rules.setMessagesAttachedCallback(fn (record: *const Record, count: usize) void {
    std.debug.print("{d} messages attached\n", .{count});
});

// Called before evaluation starts
rules.setBeforeEvaluateCallback(fn (record: *const Record) void {
    std.debug.print("Starting evaluation...\n", .{});
});

// Called after evaluation completes
rules.setAfterEvaluateCallback(fn (record: *const Record, matched_count: usize) void {
    std.debug.print("Evaluation complete: {d} rules matched\n", .{matched_count});
});

// Called on evaluation errors
rules.setEvaluationErrorCallback(fn (message: []const u8) void {
    std.debug.print("Error: {s}\n", .{message});
});
```

## Statistics

Monitor rules performance:

```zig
const stats = rules.getStats();

std.debug.print("Rules evaluated: {}\n", .{stats.rules_evaluated.load(.monotonic)});
std.debug.print("Rules matched: {}\n", .{stats.rules_matched.load(.monotonic)});
std.debug.print("Messages emitted: {}\n", .{stats.messages_emitted.load(.monotonic)});
std.debug.print("Evaluations skipped: {}\n", .{stats.evaluations_skipped.load(.monotonic)});
std.debug.print("Match rate: {d:.1}%\n", .{stats.matchRate() * 100});

// Reset statistics
rules.resetStats();
```

## RulesConfig

Configure rules behavior globally:

```zig
const config = logly.Config.RulesConfig{
    .enabled = true,              // Master switch
    .use_unicode = true,          // Use Unicode symbols
    .enable_colors = true,        // ANSI colors
    .show_rule_id = false,        // Show rule IDs
    .indent = "    ",             // Message indent
    .message_prefix = "↳",        // Prefix character
    .include_in_json = true,      // Include in JSON output
    .max_rules = 1000,            // Maximum rules allowed
};
```

### Presets

```zig
// Development (full debugging)
config.rules = logly.Config.RulesConfig.development();

// Production (minimal output)
config.rules = logly.Config.RulesConfig.production();

// ASCII-only terminals
config.rules = logly.Config.RulesConfig.ascii();

// Disabled
config.rules = logly.Config.RulesConfig.disabled();
```

## JSON Output

Format rule messages as JSON:

```zig
var json_buf: std.ArrayList(u8) = .empty;
defer json_buf.deinit(allocator);

try rules.formatMessagesJson(&messages, json_buf.writer(allocator), true); // pretty=true

std.debug.print("{s}\n", .{json_buf.items});
```

**Output:**
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

## Method Aliases

For convenience, several aliases are provided:

| Method | Aliases |
|--------|---------|
| `enable()` | `on()`, `activate()`, `start()` |
| `disable()` | `off()`, `deactivate()`, `stop()` |
| `add()` | `addRule()` |
| `remove()` | `removeRule()`, `deleteRule()`, `delete()` |
| `enableRule()` | `activateRule()` |
| `disableRule()` | `deactivateRule()` |

## Advanced Usage

### Once-Firing Rules

Rules that fire only once per session:

```zig
try rules.add(.{
    .id = 1,
    .once = true,  // Will fire only once
    .level_match = .{ .exact = .info },
    .message_contains = "started",
    .messages = &messages,
});

// Reset once-fired status for all rules
rules.resetOnceFired();
```

### Module and Function Filtering

```zig
try rules.add(.{
    .id = 2,
    .level_match = .{ .exact = .err },
    .module = "database",      // Only match logs from this module
    .function = "connect",     // Only match logs from this function
    .messages = &messages,
});
```

### Priority Range Matching

```zig
// Match warnings and errors (priority 30-50)
try rules.add(.{
    .id = 3,
    .level_match = .{ .priority_range = .{ .min = 30, .max = 50 } },
    .messages = &messages,
});
```

## Complete Example

See [examples/rules.zig](https://github.com/muhammad-fiaz/logly.zig/blob/main/examples/rules.zig) for a comprehensive demonstration of all features.

## See Also

- [Rules Guide](../guide/rules.md) - Usage patterns and best practices
- [Logger API](logger.md) - Logger setRules method
- [Filter API](filter.md) - Log filtering options
- [Configuration Guide](../guide/configuration.md) - RulesConfig options

