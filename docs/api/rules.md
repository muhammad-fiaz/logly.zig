---
title: Rules API Reference
description: API reference for Logly.zig Rules module. Compiler-style diagnostics with cause, fix, hint, and docs messages. Pattern matching, severity levels, and auto-triggering.
head:
  - - meta
    - name: keywords
      content: rules api, diagnostic rules, log guidance, error explanations, fix suggestions, pattern matching rules
  - - meta
    - property: og:title
      content: Rules API Reference | Logly.zig
---

# Rules API

The Rules module provides a powerful compiler-style diagnostic system for log messages. It enables attaching contextual guidance, solutions, documentation links, and best practices to log entries based on configurable conditions.

## Quick Reference: Method Aliases

| Full Method | Alias(es) | Description |
|-------------|-----------|-------------|
| `init()` | `create()` | Initialize rules engine |
| `deinit()` | `destroy()` | Deinitialize rules engine |
| `initWithConfig()` | `createWithConfig()` | Initialize with config |
| `initFromGlobalConfig()` | `createFromGlobalConfig()` | Initialize from global config |
| `syncWithGlobalConfig()` | `syncWithGlobal()` | Sync with global config |
| `enable()` | `on()`, `activate()`, `start()` | Enable rules |
| `disable()` | `off()`, `deactivate()`, `stop()` | Disable rules |
| `isEnabled()` | `active()` | Check if enabled |
| `add()` | `addRule()` | Add rule |
| `remove()` | `removeRule()`, `deleteRule()`, `delete()` | Remove rule |
| `enableRule()` | `activateRule()` | Enable specific rule |
| `disableRule()` | `deactivateRule()` | Disable specific rule |
| `setAllEnabled()` | `setEnabledAll()` | Enable/disable all rules |
| `removeByName()` | `removeNamed()` | Remove rules by name |
| `enabledRuleCount()` | `enabledCount()` | Count enabled rules |
| `disabledRuleCount()` | `disabledCount()` | Count disabled rules |
| `configure()` | `setConfiguration()` | Configure rules |
| `setUnicode()` | `unicode()` | Set unicode mode |
| `setColors()` | `colors()` | Set colors |
| `setConfig()` | `configuration()` | Set config |
| `getConfig()` | `getConfiguration()` | Get config |
| `setRuleMatchedCallback()` | `onRuleMatched()` | Set rule matched callback |
| `setRuleEvaluatedCallback()` | `onRuleEvaluated()` | Set rule evaluated callback |
| `setMessagesAttachedCallback()` | `onMessagesAttached()` | Set messages attached callback |
| `setEvaluationErrorCallback()` | `onEvaluationError()` | Set evaluation error callback |
| `setBeforeEvaluateCallback()` | `onBeforeEvaluate()` | Set before evaluate callback |
| `setAfterEvaluateCallback()` | `onAfterEvaluate()` | Set after evaluate callback |
| `addOrUpdate()` | `upsert()` | Add or update rule |
| `wouldMatchAny()` | `hasMatch()` | Non-mutating match preflight |
| `matchingRuleIds()` | `previewRuleIds()` | Non-mutating matching rule ID preview |
| `matchingRuleIdsWithAllocator()` | `previewRuleIdsWithAllocator()` | Matching ID preview with allocator |
| `sortByPriority()` | `sortRules()` | Sort rules by priority (desc) then ID |
| `hasRule()` | `containsRule()` | Check if has rule |
| `getById()` | `getRule()` | Get rule by ID |
| `clear()` | `clearAll()` | Clear all rules |
| `count()` | `ruleCount()` | Get rule count |
| `resetOnceFired()` | `resetOnce()` | Reset once fired |
| `evaluateWithAllocator()` | `evaluateWithAlloc()` | Evaluate with allocator |
| `formatMessages()` | `format()` | Format messages |
| `formatMessagesJson()` | `formatJson()` | Format messages as JSON |
| `getStats()` | `statistics()` | Get statistics |
| `resetStats()` | `resetStatistics()` | Reset statistics |
| `matches()` | `check()` | Check if rule matches (Rule) |
| `markFired()` | `fire()` | Mark rule as fired (Rule) |
| `resetFired()` | `resetFire()` | Reset fired state (Rule) |
| `getColor()` | `getMessageColor()` | Get message color (RuleMessage) |
| `getPrefix()` | `prefix()` | Get prefix (RuleMessage) |
| `withColor()` | `setColor()` | Set color (RuleMessage) |
| `withUrl()` | `setUrl()` | Set URL (RuleMessage) |
| `withTitle()` | `setTitle()` | Set title (RuleMessage) |
| `level()` | `exactLevel()` | Exact level match (LevelMatch) |
| `errors()` | `errorLevel()` | Error level match (LevelMatch) |
| `warnings()` | `warningLevel()` | Warning level match (LevelMatch) |
| `all()` | `anyLevel()` | Any level match (LevelMatch) |
| `exact()` | `err()`, `info()` | Exact level (LevelMatchBuilder) |
| `warnings()` | `warn()` | Warnings level (LevelMatchBuilder) |
| `getRulesEvaluated()` | `rulesEvaluated()`, `evaluatedCount()` | Get rules evaluated (RulesStats) |
| `getRulesMatched()` | `rulesMatched()`, `matchedCount()` | Get rules matched (RulesStats) |
| `getMessagesEmitted()` | `messagesEmitted()`, `emittedCount()` | Get messages emitted (RulesStats) |
| `getEvaluationsSkipped()` | `evaluationsSkipped()`, `skippedCount()` | Get evaluations skipped (RulesStats) |
| `hasEvaluated()` | `hasEvaluatedRules()` | Check if has evaluated (RulesStats) |
| `hasMatched()` | `matched()` | Check if matched (RulesStats) |
| `hasEmitted()` | `emitted()` | Check if emitted (RulesStats) |
| `hasSkipped()` | `hasSkippedEvaluations()` | Check if skipped (RulesStats) |
| `matchRate()` | `matchPercentage()` | Get match rate (RulesStats) |
| `skipRate()` | `skipPercentage()` | Get skip rate (RulesStats) |
| `avgMessagesPerMatch()` | `avgMessages()` | Get avg messages per match (RulesStats) |
| `efficiencyRate()` | `efficiencyPercentage()` | Get efficiency rate (RulesStats) |
| `reset()` | `clear()`, `zero()` | Reset stats (RulesStats) |
| `MessageCategory.error_analysis` | `cause()`, `diagnostic()`, `analysis()` | Error analysis category |
| `MessageCategory.solution_suggestion` | `fix()`, `solution()`, `help()` | Solution suggestion category |
| `MessageCategory.best_practice` | `suggest()`, `hint()`, `tip()` | Best practice category |
| `MessageCategory.action_required` | `action()`, `todo()` | Action required category |
| `MessageCategory.documentation_link` | `docs()`, `reference()`, `link()` | Documentation link category |
| `MessageCategory.bug_report` | `report()`, `issue()` | Bug report category |
| `MessageCategory.general_information` | `note()`, `info()` | General information category |
| `MessageCategory.warning_explanation` | `caution()`, `warning()`, `warn()` | Warning explanation category |
| `MessageCategory.performance_tip` | `perf()`, `performance()` | Performance tip category |
| `MessageCategory.security_notice` | `security()` | Security notice category |
| `displayName()` | `name()` | Get display name (MessageCategory) |
| `prefix()` | `unicodePrefix()` | Get unicode prefix (MessageCategory) |
| `prefixAscii()` | `asciiPrefix()` | Get ASCII prefix (MessageCategory) |
| `defaultColor()` | `color()` | Get default color (MessageCategory) |

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
    >> [ERROR] Database connection pool exhausted
    >> [FIX] Increase max_connections or implement connection pooling
    >> [DOC] Connection Guide: See documentation (https://docs.example.com/db)
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
| `init(allocator)`Alias: `create` | Create a new Rules engine |
| `initWithConfig(allocator, config)` | Create with custom configuration |
| `deinit()` Alias: `destroy` | Free all resources |
| `enable()` | Enable the rules engine |
| `disable()` | Disable the rules engine (zero overhead) |
| `isEnabled()` | Check if rules are enabled |
| `configure(config)` | Update configuration |
| `setUnicode(bool)` | Enable/disable Unicode symbols |
| `setColors(bool)` | Enable/disable ANSI colors |

### RulesStats

Statistics for the rules engine with atomic counters.

#### Getter Methods

| Method | Return | Description |
|--------|--------|-------------|
| `getRulesEvaluated()` | `u64` | Get total rules evaluated |
| `getRulesMatched()` | `u64` | Get total rules matched |
| `getMessagesEmitted()` | `u64` | Get total messages emitted |
| `getEvaluationsSkipped()` | `u64` | Get evaluations skipped |

#### Boolean Checks

| Method | Return | Description |
|--------|--------|-------------|
| `hasEvaluated()` | `bool` | Check if any rules have been evaluated |
| `hasMatched()` | `bool` | Check if any rules have matched |
| `hasEmitted()` | `bool` | Check if any messages have been emitted |
| `hasSkipped()` | `bool` | Check if any evaluations have been skipped |

#### Rate Calculations

| Method | Return | Description |
|--------|--------|-------------|
| `matchRate()` | `f64` | Calculate match rate (0.0 - 1.0) |
| `skipRate()` | `f64` | Calculate skip rate (0.0 - 1.0) |
| `avgMessagesPerMatch()` | `f64` | Calculate average messages per match |
| `efficiencyRate()` | `f64` | Calculate efficiency rate (1.0 - skipRate) |

#### Reset

| Method | Description |
|--------|-------------|
| `reset()` | Reset all statistics to initial state |

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

// Enable or disable all rules in one call
_ = rules.setAllEnabled(true);

// Remove all rules sharing the same name
_ = rules.removeByName("database-error");

// Optionally force sorting by priority (highest first)
rules.sortByPriority();

// Get rule by ID
if (rules.getById(1)) |rule| {
    std.debug.print("Rule enabled: {}\n", .{rule.enabled});
}

// Clear all rules
rules.clear();

// Get rule count
const count = rules.count();
```

### Evaluation

#### `evaluate(record: *const Record) ?[]const RuleMessage`

Evaluates all enabled rules against a log record. Returns a slice of rule messages if any rules match. Note: Caller must free the returned slice.

#### `evaluateWithAllocator(record: *const Record, scratch_allocator: ?std.mem.Allocator) ?[]const RuleMessage`

Evaluates rules using an optional scratch allocator for the resulting message slice.

Evaluation respects `RulesConfig.max_messages_per_rule`, which caps emitted messages per matching rule during each evaluation pass.

#### `wouldMatchAny(record: *const Record) bool`

Returns `true` if at least one enabled rule would match the record.

- Non-mutating: does not fire `once` rules.
- Useful for preflight checks before full evaluation.

#### `matchingRuleIds(record: *const Record) ?[]u32`

Returns IDs of rules that would match this record.

- Non-mutating: does not fire `once` rules.
- Caller owns returned memory.

#### `matchingRuleIdsWithAllocator(record: *const Record, scratch_allocator: ?std.mem.Allocator) ?[]u32`

Same as `matchingRuleIds(...)`, with explicit allocator control for the returned slice.

**Example:**
```zig
const messages = rules.evaluateWithAllocator(record, logger.scratchAllocator());
// No need to free if using logger's scratch allocator (batch-freed)
```

| Method | Description |
|--------|-------------|
| `add(rule)` | Add a rule, error if ID exists |
| `addOrUpdate(rule)` | Add or update a rule |
| `hasRule(id)` | Check if rule ID exists |
| `remove(id)` | Remove a rule by ID |
| `removeByName(name)` | Remove all rules with matching name |
| `enableRule(id)` | Enable a rule |
| `disableRule(id)` | Disable a rule |
| `setAllEnabled(enabled)` | Bulk enable/disable all rules |
| `enabledRuleCount()` | Count enabled rules |
| `disabledRuleCount()` | Count disabled rules |
| `getById(id)` | Get rule pointer by ID |
| `sortByPriority()` | Sort by priority (desc), then rule ID |
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

std.debug.print("Rules evaluated: {}\\n", .{stats.getRulesEvaluated()});
std.debug.print("Rules matched: {}\\n", .{stats.getRulesMatched()});
std.debug.print("Messages emitted: {}\\n", .{stats.getMessagesEmitted()});
std.debug.print("Evaluations skipped: {}\\n", .{stats.getEvaluationsSkipped()});
std.debug.print("Match rate: {d:.1}%\\n", .{stats.matchRate() * 100});

// Reset statistics
rules.resetStats();
```

## RulesConfig

Configure rules behavior globally. The rules system **respects global configuration settings** such as `global_console_display`, `global_file_storage`, and `global_color_display`.

```zig
const config = logly.Config.RulesConfig{
    // Master switches
    .enabled = true,                    // Master switch for rules system
    .client_rules_enabled = true,       // Enable client-defined rules
    .builtin_rules_enabled = true,      // Enable built-in rules (reserved)

    // Display options
    .use_unicode = false,               // Use Unicode symbols (deprecated, use 'symbols' to configure custom characters)
    .enable_colors = true,              // ANSI colors in output
    .show_rule_id = false,              // Show rule IDs in output
    .include_rule_id_prefix = false,    // Include "R0001:" prefix
    .rule_id_format = "R{d}",           // Custom rule ID format
    .indent = "    ",                   // Message indent
    .message_prefix = "↳",              // Prefix character (deprecated)
    .symbols = .{},                     // Custom symbols (see RuleSymbols)

    // Output control (respects global switches)
    .console_output = true,             // Output to console (AND'd with global_console_display)
    .file_output = true,                // Output to files (AND'd with global_file_storage)
    .include_in_json = true,            // Include in JSON output

    // Advanced options
    .verbose = false,                   // Full context output
    .max_rules = 1000,                  // Maximum rules allowed
    .max_messages_per_rule = 10,        // Cap messages emitted per matching rule
    .sort_by_severity = false,          // Keep rules sorted by descending priority
};
```

When `sort_by_severity` is enabled, the engine keeps rules ordered by `priority` (highest first, then rule ID) during add/update/config-sync flows.

### Global Switch Integration

Rule output is controlled by **both local and global settings**:

```zig
// Console output requires BOTH to be true:
// - RulesConfig.console_output = true
// - Config.global_console_display = true

// File output requires BOTH to be true:
// - RulesConfig.file_output = true
// - Config.global_file_storage = true

// Color output requires BOTH to be true:
// - RulesConfig.enable_colors = true
// - Config.global_color_display = true
```

This ensures rules can be disabled globally without modifying individual rule configurations:

```zig
// Disable ALL console output (including rules)
config.global_console_display = false;

// Or disable ONLY rule console output
config.rules.console_output = false;
```

### Presets

```zig
// Development (full debugging)
config.rules = logly.Config.RulesConfig.development();

// Production (minimal output, no colors, no verbose)
config.rules = logly.Config.RulesConfig.production();

// ASCII-only terminals
config.rules = logly.Config.RulesConfig.ascii();

// Disabled
config.rules = logly.Config.RulesConfig.disabled();

// Silent (rules evaluate but don't output)
config.rules = logly.Config.RulesConfig.silent();

// Console only (no file output)
config.rules = logly.Config.RulesConfig.consoleOnly();

// File only (no console output)
config.rules = logly.Config.RulesConfig.fileOnly();
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
| `setAllEnabled()` | `setEnabledAll()` |
| `removeByName()` | `removeNamed()` |
| `enabledRuleCount()` | `enabledCount()` |
| `disabledRuleCount()` | `disabledCount()` |
| `wouldMatchAny()` | `hasMatch()` |
| `matchingRuleIds()` | `previewRuleIds()` |
| `matchingRuleIdsWithAllocator()` | `previewRuleIdsWithAllocator()` |
| `sortByPriority()` | `sortRules()` |

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

