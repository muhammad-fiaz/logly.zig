---
title: Filter API Reference
description: API reference for Logly.zig Filter struct. Create rules to filter logs by level, module, message pattern with allow/deny actions and batch evaluation.
head:
  - - meta
    - name: keywords
      content: filter api, log filtering, rule-based filter, level filter, module filter, pattern matching
  - - meta
    - property: og:title
      content: Filter API Reference | Logly.zig
---

# Filter API

The `Filter` struct provides fine-grained control over which log records are processed.

## Overview

Filters evaluate log records against a set of rules with thread-safe operations. Rules can filter based on log level, module name, message content, or custom logic. Filters support callbacks for allowed/denied records and comprehensive statistics tracking.

## Types

### Filter

The main filter controller with thread-safe rule evaluation.

```zig
pub const Filter = struct {
    allocator: std.mem.Allocator,
    rules: std.ArrayList(FilterRule),
    stats: FilterStats,
    mutex: std.Thread.Mutex,
    
    // Callbacks
    on_record_allowed: ?*const fn (*const Record, u32) void,
    on_record_denied: ?*const fn (*const Record, u32) void,
    on_filter_created: ?*const fn (*const FilterStats) void,
    on_rule_added: ?*const fn (u32, u32) void,
};
```

### FilterStats

Statistics tracking for filter operations.

```zig
pub const FilterStats = struct {
    total_records_evaluated: std.atomic.Value(u64),
    records_allowed: std.atomic.Value(u64),
    records_denied: std.atomic.Value(u64),
    rules_added: std.atomic.Value(u64),
    evaluation_errors: std.atomic.Value(u64),
    
    pub fn allowRate(self: *const FilterStats) f64;
    pub fn errorRate(self: *const FilterStats) f64;
};
```

### FilterRule

A single rule definition.

```zig
pub const FilterRule = struct {
    rule_type: RuleType,
    pattern: ?[]const u8 = null,
    level: ?Level = null,
    action: Action = .allow,

    pub const RuleType = enum {
        level_min,
        level_max,
        level_exact,
        module_match,
        module_prefix,
        message_contains,
        message_regex,
        custom,
    };

    pub const Action = enum {
        allow,
        deny,
    };
};
```

## Methods

### Initialization

#### `init(allocator: std.mem.Allocator) Filter`

Initializes a new Filter instance.

#### `deinit(self: *Filter) void`

Releases all resources associated with the filter.

### Rule Management

#### `addRule(rule: FilterRule) !void`

Adds a new rule to the filter chain.

```zig
try filter.addRule(.{
    .rule_type = .module_match,
    .pattern = "network",
    .action = .deny,
});
```

#### `addMinLevel(level: Level) !void`

Adds a minimum level filter rule.

**Alias**: `minLevel`, `min`

#### `addMaxLevel(level: Level) !void`

Adds a maximum level filter rule.

**Alias**: `maxLevel`, `max`

#### `addModulePrefix(prefix: []const u8, action: Action) !void`

Adds a module prefix filter rule.

**Alias**: `moduleFilter`, `addPrefix`

#### `addMessageFilter(pattern: []const u8, action: Action) !void`

Adds a message content filter rule.

**Alias**: `messageFilter`

#### `addMinPriority(min_priority: u8) !void`

Adds a custom level priority filter (for custom levels).

#### `addPriorityRange(min_priority: u8, max_priority: u8) !void`

Adds a priority range filter for custom levels.

#### `clear() void`

Removes all filter rules.

**Alias**: `reset`, `removeAll`

### Evaluation

#### `shouldLog(record: *const Record) bool`

Evaluates a record against all rules. Returns `true` if the record should be logged.

**Alias**: `check`, `evaluate`

#### `shouldLogBatch(records: []const *const Record, results: []bool) void`

Batch filter evaluation for multiple records at once. More efficient for processing large volumes.

#### `allowsAll() bool`

Fast path check - returns true if filter has no rules (allows all).

### Statistics

#### `getStats() FilterStats`

Returns current filter statistics.

#### `count() usize`

Returns the number of filter rules.

**Alias**: `ruleCount`, `length`

#### `allowedCount() u64`

Returns the count of allowed records.

#### `deniedCount() u64`

Returns the count of denied records.

#### `totalProcessed() u64`

Returns total records evaluated.

#### `resetStats() void`

Resets all statistics to zero.

### State

#### `hasRules() bool`

Returns true if the filter has any rules.

#### `isEmpty() bool`

Returns true if the filter is empty (no rules).

#### `disable() void`

Disables the filter (clears all rules, allowing everything).

### Callbacks

#### `setAllowedCallback(callback: *const fn (*const Record, u32) void) void`

Sets callback for allowed records.

#### `setDeniedCallback(callback: *const fn (*const Record, u32) void) void`

Sets callback for denied records.

#### `setCreatedCallback(callback: *const fn (*const FilterStats) void) void`

Sets callback for filter creation.

#### `setRuleAddedCallback(callback: *const fn (u32, u32) void) void`

Sets callback for rule additions.

### Factory

#### `fromConfig(allocator: Allocator, config: Config) !Filter`

Creates a filter from logger configuration settings.

## Presets

### FilterPresets

```zig
pub const FilterPresets = struct {
    /// Errors only - minimum level: error
    pub fn errorsOnly(allocator: std.mem.Allocator) !Filter;
    
    /// Production - minimum level: info
    pub fn production(allocator: std.mem.Allocator) !Filter;
    
    /// Debug - minimum level: debug
    pub fn debug(allocator: std.mem.Allocator) !Filter;
    
    /// Security - minimum level: warning
    pub fn security(allocator: std.mem.Allocator) !Filter;
};
```

## Example

```zig
const Filter = @import("logly").Filter;
const FilterPresets = @import("logly").FilterPresets;

// Initialize
var filter = Filter.init(allocator);
defer filter.deinit();

// Add rules
try filter.addMinLevel(.warning);
try filter.addModulePrefix("debug.", .deny);
try filter.addMessageFilter("heartbeat", .deny);

// Check if record should be logged
if (filter.shouldLog(&record)) {
    // Process record
}

// Fast path for empty filters
if (filter.allowsAll()) {
    // Skip evaluation, all records pass
}

// Batch processing
var results: [100]bool = undefined;
filter.shouldLogBatch(&records, &results);

// Check statistics
const stats = filter.getStats();
std.debug.print("Allow rate: {d:.2}%\n", .{stats.allowRate() * 100});

// Use presets
var prod_filter = try FilterPresets.production(allocator);
defer prod_filter.deinit();
```

## Performance

- **O(n)** filter evaluation where n = number of rules
- **Early exit** when first deny rule matches
- **Thread-safe** with mutex protection
- **Batch processing** for high-throughput scenarios
- **Fast path** check to skip evaluation when no rules exist
