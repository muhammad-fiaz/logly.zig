# Filtering

Logly-Zig v0.0.3+ provides a powerful filtering system for rule-based log filtering. Filter logs by level, message patterns, modules, and more. Filters work with all sink types: console, file, and JSON.

## Overview

The `Filter` module allows you to:
- Filter by minimum/maximum log level
- Filter by message content patterns
- Filter by module name prefix
- Apply filters globally or per-sink
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

    // Enable colors on Windows
    _ = logly.Terminal.enableAnsiColors();

    const logger = try logly.Logger.init(allocator);
    defer logger.deinit();

    // Create a filter
    var filter = Filter.init(allocator);
    defer filter.deinit();

    // Only allow warning and above
    try filter.addMinLevel(.warning);

    // Apply filter to logger (applies to ALL sinks)
    logger.setFilter(&filter);

    // These will be filtered out (below warning level)
    try logger.debug(@src(), "Debug message - filtered", .{});
    try logger.info(@src(), "Info message - filtered", .{});

    // These will pass through
    try logger.warn(@src(), "Warning message - passes", .{});
    try logger.err(@src(), "Error message - passes", .{});
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

Logly supports filtering at both the logger level and per-sink level. Per-sink filtering uses the `FilterConfig` struct within `SinkConfig`, which provides fine-grained control over which messages each sink receives.

### FilterConfig Options

```zig
pub const FilterConfig = struct {
    include_modules: ?[]const []const u8 = null,   // Only log these modules
    exclude_modules: ?[]const []const u8 = null,   // Exclude these modules
    include_messages: ?[]const []const u8 = null,  // Only log messages containing these
    exclude_messages: ?[]const []const u8 = null,  // Exclude messages containing these
};
```

### Console Sink with Filtering

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    _ = logly.Terminal.enableAnsiColors();

    const logger = try logly.Logger.init(allocator);
    defer logger.deinit();

    // Console sink that only logs auth and database modules
    _ = try logger.add(.{
        .level = .debug,
        .filter = .{
            .include_modules = &.{ "auth", "database" },
            .exclude_messages = &.{ "heartbeat", "ping" },
        },
    });

    // Logs from auth module - passes
    try logger.info(@src(), "[auth] User logged in", .{});

    // Logs from database module - passes
    try logger.debug(@src(), "[database] Query executed", .{});

    // Filtered out - wrong module
    try logger.info(@src(), "[http] Request received", .{});

    // Filtered out - contains excluded message
    try logger.debug(@src(), "[auth] heartbeat check", .{});
}
```

### File Sink with Filtering

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const logger = try logly.Logger.init(allocator);
    defer logger.deinit();

    // Error log file - only errors and critical
    _ = try logger.add(.{
        .path = "logs/errors.log",
        .level = .err,
        .max_level = .critical,
        .filter = .{
            .exclude_messages = &.{ "health_check", "monitoring" },
        },
    });

    // Audit log file - only specific modules
    _ = try logger.add(.{
        .path = "logs/audit.log",
        .level = .info,
        .filter = .{
            .include_modules = &.{ "auth", "security", "admin" },
        },
    });

    // Debug log file - everything except noisy modules
    _ = try logger.add(.{
        .path = "logs/debug.log",
        .level = .debug,
        .filter = .{
            .exclude_modules = &.{ "metrics", "heartbeat" },
        },
    });

    // Goes to audit.log only
    try logger.info(@src(), "[auth] User login successful", .{});

    // Goes to errors.log
    try logger.err(@src(), "Database connection failed", .{});

    // Goes to debug.log only (filtered from others)
    try logger.debug(@src(), "Processing request", .{});
}
```

### JSON Sink with Filtering

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const logger = try logly.Logger.init(allocator);
    defer logger.deinit();

    // JSON logs for production - structured data
    _ = try logger.add(.{
        .path = "logs/app.json",
        .format = .json,
        .level = .info,
        .filter = .{
            .include_modules = &.{ "api", "service", "handler" },
            .exclude_messages = &.{ "DEBUG", "TRACE" },
        },
    });

    // JSON error logs for alerting systems
    _ = try logger.add(.{
        .path = "logs/alerts.json",
        .format = .json,
        .level = .err,
        .filter = .{
            .include_messages = &.{ "CRITICAL", "ALERT", "FATAL" },
        },
    });

    // API logs - goes to app.json
    try logger.info(@src(), "[api] Request processed", .{});

    // Critical error - goes to both files
    try logger.crit(@src(), "CRITICAL: System failure", .{});

    // Regular error - only app.json
    try logger.err(@src(), "[service] Connection timeout", .{});
}
```

### Multiple Sinks with Different Filters

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    _ = logly.Terminal.enableAnsiColors();

    const logger = try logly.Logger.init(allocator);
    defer logger.deinit();

    // Console - development view (all debug+)
    _ = try logger.add(.{
        .level = .debug,
    });

    // File - production logs (info+, no debug noise)
    _ = try logger.add(.{
        .path = "logs/production.log",
        .level = .info,
        .filter = .{
            .exclude_modules = &.{ "debug", "test", "mock" },
        },
    });

    // JSON - structured logs for log aggregation
    _ = try logger.add(.{
        .path = "logs/structured.json",
        .format = .json,
        .level = .info,
        .filter = .{
            .include_modules = &.{ "api", "database", "auth", "service" },
        },
    });

    // Errors file - critical errors only
    _ = try logger.add(.{
        .path = "logs/critical.log",
        .level = .err,
        .filter = .{
            .exclude_messages = &.{ "warning", "notice" },
        },
    });

    // Log some messages
    try logger.debug(@src(), "[debug] Variable value: 42", .{});  // Console only
    try logger.info(@src(), "[api] Request received", .{});       // Console, production.log, structured.json
    try logger.warn(@src(), "[database] Slow query", .{});        // Console, production.log
    try logger.err(@src(), "Critical database error", .{});       // All sinks
}
```

### Combining Logger and Sink Filters

You can use both logger-level filters and per-sink filters together:

```zig
const std = @import("std");
const logly = @import("logly");
const Filter = logly.Filter;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const logger = try logly.Logger.init(allocator);
    defer logger.deinit();

    // Global filter - minimum info level
    var global_filter = Filter.init(allocator);
    defer global_filter.deinit();
    try global_filter.addMinLevel(.info);
    logger.setFilter(&global_filter);

    // Console sink - additional module filter
    _ = try logger.add(.{
        .level = .info,
        .filter = .{
            .include_modules = &.{ "app", "core" },
        },
    });

    // File sink - different module focus
    _ = try logger.add(.{
        .path = "logs/database.log",
        .level = .info,
        .filter = .{
            .include_modules = &.{ "database", "query" },
        },
    });

    // Filtered by global filter (below info)
    try logger.debug(@src(), "[app] Debug info", .{});

    // Passes global, goes to console (matches include_modules)
    try logger.info(@src(), "[app] Starting application", .{});

    // Passes global, goes to file (matches include_modules)
    try logger.info(@src(), "[database] Connection established", .{});

    // Passes global but filtered by both sinks (wrong module)
    try logger.info(@src(), "[http] Server started", .{});
}
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
