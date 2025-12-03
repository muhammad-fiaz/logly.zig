# Filtering

Logly-Zig v0.0.3+ provides a powerful filtering system for rule-based log filtering. Filter logs by level, message patterns, modules, and more.

## Overview

The `Filter` module allows you to:
- Filter by minimum/maximum log level
- Filter by message content patterns
- Filter by module name prefix
- Use pre-built filter presets for common scenarios

## Basic Usage

```zig
const std = @import("std");
const logly = @import("logly");
const Filter = logly.Filter;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create a filter
    var filter = Filter.init(allocator);
    defer filter.deinit();

    // Only allow warning and above
    try filter.addMinLevel(.warning);

    // Check if a record should pass the filter
    const should_log = filter.shouldLog(.info, null, "Test message");
    // Returns false since info < warning
}
```

## Filter Rules

### Level Filtering

Filter by minimum and/or maximum level:

```zig
var filter = Filter.init(allocator);
defer filter.deinit();

// Only warning and above
try filter.addMinLevel(.warning);

// Also add maximum level (info through warning only)
try filter.addMaxLevel(.warning);
```

### Module Prefix Filtering

Filter by module name prefix:

```zig
var filter = Filter.init(allocator);
defer filter.deinit();

// Only logs from modules starting with "database"
try filter.addModulePrefix("database");

// Add another module prefix
try filter.addModulePrefix("auth");
```

### Message Content Filtering

Filter by message content with allow/drop actions:

```zig
var filter = Filter.init(allocator);
defer filter.deinit();

// Drop logs containing "heartbeat"
try filter.addMessageFilter("heartbeat", .drop);

// Allow logs containing "error"
try filter.addMessageFilter("error", .allow);
```

## Filter Presets

Logly provides pre-built filter configurations for common scenarios:

```zig
const FilterPresets = logly.FilterPresets;

// Errors only - filter for error level and above
var errors_only = try FilterPresets.errorsOnly(allocator);
defer errors_only.deinit();

// Production - info level and above, excludes debug noise
var production = try FilterPresets.production(allocator);
defer production.deinit();

// Module-specific - only logs from a specific module
var module_only = try FilterPresets.moduleOnly(allocator, "database");
defer module_only.deinit();
```

## Using Filters

The `shouldLog` method checks if a log record should pass through:

```zig
var filter = Filter.init(allocator);
defer filter.deinit();

try filter.addMinLevel(.info);

// Check various levels
const debug_passes = filter.shouldLog(.debug, null, "Debug message");    // false
const info_passes = filter.shouldLog(.info, null, "Info message");       // true
const warning_passes = filter.shouldLog(.warning, null, "Warning");      // true

// Check with module
const db_log = filter.shouldLog(.info, "database", "Query executed");    // true
```

## Per-Sink Filtering

You can also configure filtering per-sink using SinkConfig:

```zig
_ = try logger.addSink(.{
    .path = "logs/errors.log",
    .level = .err,           // Only error and above
    .max_level = .critical,  // Up to critical
    .filter = .{
        .include_modules = &.{"error", "critical"},
        .exclude_messages = &.{"health_check"},
    },
});
```

## Best Practices

1. **Use presets**: Start with `FilterPresets` for common scenarios
2. **Combine with sampling**: Use `Sampler` for volume control in addition to filtering
3. **Test your filters**: Verify filtering works at different levels
4. **Document filter rules**: Add comments explaining why each rule exists

## See Also

- [Sampling](/guide/sampling) - Rate limiting and probability-based filtering
- [Redaction](/guide/redaction) - Sensitive data masking
- [Configuration](/guide/configuration) - Global configuration options
