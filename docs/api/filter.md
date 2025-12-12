# Filter API

The `Filter` struct provides fine-grained control over which log records are processed.

## Overview

Filters evaluate log records against a set of rules. Rules can filter based on log level, module name, message content, or custom logic.

## Types

### Filter

The main filter controller.

```zig
pub const Filter = struct {
    allocator: std.mem.Allocator,
    rules: std.ArrayList(FilterRule),
    stats: FilterStats,
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

### `init(allocator: std.mem.Allocator) Filter`

Initializes a new Filter instance.

### `addRule(rule: FilterRule) !void`

Adds a new rule to the filter chain.

```zig
try filter.addRule(.{
    .rule_type = .module_match,
    .pattern = "network",
    .action = .deny,
});
```

### `shouldLog(record: *const Record) bool`

Evaluates a record against all rules. Returns `true` if the record should be logged, `false` otherwise.

## Presets

`FilterPresets` provides common filter configurations.

### `FilterPresets.production()`

Standard production filter:
- Min Level: INFO
- Deny "debug" modules

### `FilterPresets.debug()`

Debug filter:
- Min Level: DEBUG
- Allow all modules

### `FilterPresets.security()`

Security filter:
- Min Level: WARNING
- Deny sensitive modules
