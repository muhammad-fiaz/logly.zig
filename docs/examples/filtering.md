# Filtering Example

Learn how to filter log messages based on level, module, or content.

## Basic Filtering

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const logger = try logly.Logger.init(allocator);
    defer logger.deinit();

    // Create a filter
    var filter = logly.Filter.init(allocator);
    defer filter.deinit();

    // Add minimum level filter - only warning and above
    try filter.addMinLevel(.warning);

    // Apply filter to logger
    logger.setFilter(&filter);

    // Only warning and above will pass
    try logger.debug("This won't appear");  // Filtered out
    try logger.info("This won't appear");   // Filtered out
    try logger.warning("This will appear"); // Passes filter
    try logger.err("This will appear");     // Passes filter
}
```

## Module-Based Filtering

```zig
// Filter by module prefix
var filter = logly.Filter.init(allocator);
defer filter.deinit();

try filter.addModulePrefix("database");  // Only from "database" module

logger.setFilter(&filter);

// Create scoped logger
const db_logger = logger.scoped("database");
try db_logger.info("This will appear");     // Module matches

try logger.info("This won't appear");       // No module, filtered
```

## Message Content Filtering

```zig
var filter = logly.Filter.init(allocator);
defer filter.deinit();

// Deny logs containing sensitive keywords
try filter.addMessageFilter("password", .deny);
try filter.addMessageFilter("secret", .deny);

logger.setFilter(&filter);

try logger.info("Normal message");           // Passes
try logger.info("User password changed");    // Filtered (contains "password")
```

## Filter Presets

```zig
const FilterPresets = logly.FilterPresets;

// Production: info and above (excludes trace/debug)
var prod_filter = try FilterPresets.production(allocator);
defer prod_filter.deinit();

// Errors only: err and above
var error_filter = try FilterPresets.errorsOnly(allocator);
defer error_filter.deinit();

// Module-specific filter
var db_filter = try FilterPresets.moduleOnly(allocator, "database");
defer db_filter.deinit();
```

## Filter Rule Types

| Rule Type | Method | Description |
|-----------|--------|-------------|
| Min Level | `addMinLevel(level)` | Allow logs at or above level |
| Max Level | `addMaxLevel(level)` | Allow logs at or below level |
| Module Prefix | `addModulePrefix(prefix)` | Allow logs from matching modules |
| Message Contains | `addMessageFilter(str, action)` | Allow/deny based on content |

## Filter Actions

- **`.allow`** - Allow logs matching this rule
- **`.deny`** - Block logs matching this rule

## Combined Filtering

```zig
var filter = logly.Filter.init(allocator);
defer filter.deinit();

// Multiple rules: info level minimum, exclude password-related
try filter.addMinLevel(.info);
try filter.addMessageFilter("password", .deny);

logger.setFilter(&filter);
```

## Use Cases

- **Development**: No filter (show all logs)
- **Production**: Filter to warnings and above
- **Debugging**: Enable debug for specific modules only
- **Security**: Filter out PII-containing messages
