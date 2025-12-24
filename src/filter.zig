const std = @import("std");
const Config = @import("config.zig").Config;
const Level = @import("level.zig").Level;
const Record = @import("record.zig").Record;
const SinkConfig = @import("sink.zig").SinkConfig;
const Constants = @import("constants.zig");

/// Filter for conditionally processing log records.
///
/// Filters allow fine-grained control over which log records are processed.
/// They can be combined to create complex filtering logic based on level,
/// message content, module, or custom predicates.
///
/// Callbacks:
/// - `on_record_allowed`: Called when a record passes filtering
/// - `on_record_denied`: Called when a record is blocked by filter
/// - `on_filter_created`: Called when filter is created/initialized
/// - `on_rule_added`: Called when a new filter rule is added
///
/// Performance:
/// - O(n) filter evaluation where n = number of rules
/// - Early exit optimization when first deny rule matches
/// - Minimal memory overhead per rule
pub const Filter = struct {
    /// Filter statistics for monitoring and diagnostics.
    pub const FilterStats = struct {
        total_records_evaluated: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        records_allowed: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        records_denied: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        rules_added: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        evaluation_errors: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),

        /// Calculate allow rate (0.0 - 1.0)
        pub fn allowRate(self: *const FilterStats) f64 {
            const total = @as(u64, self.total_records_evaluated.load(.monotonic));
            if (total == 0) return 0;
            const allowed = @as(u64, self.records_allowed.load(.monotonic));
            return @as(f64, @floatFromInt(allowed)) / @as(f64, @floatFromInt(total));
        }

        /// Calculate error rate (0.0 - 1.0)
        pub fn errorRate(self: *const FilterStats) f64 {
            const total = @as(u64, self.total_records_evaluated.load(.monotonic));
            if (total == 0) return 0;
            const errors = @as(u64, self.evaluation_errors.load(.monotonic));
            return @as(f64, @floatFromInt(errors)) / @as(f64, @floatFromInt(total));
        }
    };

    allocator: std.mem.Allocator,
    rules: std.ArrayList(FilterRule),
    stats: FilterStats = .{},
    mutex: std.Thread.Mutex = .{},

    /// Callback invoked when a record passes filtering.
    /// Parameters: (record: *const Record, rules_checked: u32)
    on_record_allowed: ?*const fn (*const Record, u32) void = null,

    /// Callback invoked when a record is denied by filter.
    /// Parameters: (record: *const Record, blocking_rule_index: u32)
    on_record_denied: ?*const fn (*const Record, u32) void = null,

    /// Callback invoked when filter is created.
    /// Parameters: (stats: *const FilterStats)
    on_filter_created: ?*const fn (*const FilterStats) void = null,

    /// Callback invoked when a rule is added.
    /// Parameters: (rule_type: u32, total_rules: u32)
    on_rule_added: ?*const fn (u32, u32) void = null,

    /// A single filter rule that determines whether a record should pass.
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

    /// Initializes a new Filter instance.
    ///
    /// Arguments:
    ///     allocator: Memory allocator for internal storage.
    ///
    /// Returns:
    ///     A new Filter instance.
    pub fn init(allocator: std.mem.Allocator) Filter {
        return .{
            .allocator = allocator,
            .rules = .empty,
        };
    }

    /// Releases all resources associated with the filter.
    pub fn deinit(self: *Filter) void {
        for (self.rules.items) |rule| {
            if (rule.pattern) |p| {
                self.allocator.free(p);
            }
        }
        self.rules.deinit(self.allocator);
    }

    /// Adds a new filter rule.
    pub fn addRule(self: *Filter, rule: FilterRule) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Deep copy pattern if present
        var new_rule = rule;
        if (rule.pattern) |p| {
            new_rule.pattern = try self.allocator.dupe(u8, p);
        }

        try self.rules.append(new_rule);

        if (self.on_rule_added) |cb| {
            cb(@intFromEnum(rule.rule_type), @intCast(self.rules.items.len));
        }
    }

    /// Sets the callback for record allowed events.
    pub fn setAllowedCallback(self: *Filter, callback: *const fn (*const Record, u32) void) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.on_record_allowed = callback;
    }

    /// Sets the callback for record denied events.
    pub fn setDeniedCallback(self: *Filter, callback: *const fn (*const Record, u32) void) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.on_record_denied = callback;
    }

    /// Sets the callback for filter creation.
    pub fn setCreatedCallback(self: *Filter, callback: *const fn (*const FilterStats) void) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.on_filter_created = callback;
    }

    /// Sets the callback for rule addition.
    pub fn setRuleAddedCallback(self: *Filter, callback: *const fn (u32, u32) void) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.on_rule_added = callback;
    }

    /// Returns filter statistics.
    pub fn getStats(self: *Filter) FilterStats {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.stats;
    }

    /// Adds a minimum level filter rule.
    ///
    /// Records with a level below the minimum will be filtered out.
    ///
    /// Arguments:
    ///     level: The minimum level to allow.
    pub fn addMinLevel(self: *Filter, level: Level) !void {
        try self.rules.append(self.allocator, .{
            .rule_type = .level_min,
            .level = level,
            .action = .allow,
        });
    }

    /// Adds a maximum level filter rule.
    ///
    /// Records with a level above the maximum will be filtered out.
    ///
    /// Arguments:
    ///     level: The maximum level to allow.
    pub fn addMaxLevel(self: *Filter, level: Level) !void {
        try self.rules.append(self.allocator, .{
            .rule_type = .level_max,
            .level = level,
            .action = .allow,
        });
    }

    /// Adds a module prefix filter rule.
    ///
    /// Only records from modules matching the prefix will be allowed.
    ///
    /// Arguments:
    ///     prefix: The module prefix to match.
    pub fn addModulePrefix(self: *Filter, prefix: []const u8) !void {
        const owned_prefix = try self.allocator.dupe(u8, prefix);
        try self.rules.append(self.allocator, .{
            .rule_type = .module_prefix,
            .pattern = owned_prefix,
            .action = .allow,
        });
    }

    /// Adds a message content filter rule.
    ///
    /// Records containing the specified substring will be filtered.
    ///
    /// Arguments:
    ///     substring: The substring to search for.
    ///     action: Whether to allow or deny matching records.
    pub fn addMessageFilter(self: *Filter, substring: []const u8, action: FilterRule.Action) !void {
        const owned_substring = try self.allocator.dupe(u8, substring);
        try self.rules.append(self.allocator, .{
            .rule_type = .message_contains,
            .pattern = owned_substring,
            .action = action,
        });
    }

    /// Evaluates whether a record should be processed.
    ///
    /// Arguments:
    ///     record: The log record to evaluate.
    ///
    /// Returns:
    ///     true if the record should be processed, false otherwise.
    pub fn shouldLog(self: *const Filter, record: *const Record) bool {
        if (self.rules.items.len == 0) return true;

        for (self.rules.items) |rule| {
            switch (rule.rule_type) {
                .level_min => {
                    if (rule.level) |min_level| {
                        if (record.level.priority() < min_level.priority()) {
                            return false;
                        }
                    }
                },
                .level_max => {
                    if (rule.level) |max_level| {
                        if (record.level.priority() > max_level.priority()) {
                            return false;
                        }
                    }
                },
                .level_exact => {
                    if (rule.level) |exact_level| {
                        if (record.level != exact_level) {
                            return false;
                        }
                    }
                },
                .module_prefix => {
                    if (rule.pattern) |prefix| {
                        if (record.module) |module| {
                            if (!std.mem.startsWith(u8, module, prefix)) {
                                if (rule.action == .allow) return false;
                            }
                        } else {
                            if (rule.action == .allow) return false;
                        }
                    }
                },
                .module_match => {
                    if (rule.pattern) |pattern| {
                        if (record.module) |module| {
                            if (!std.mem.eql(u8, module, pattern)) {
                                if (rule.action == .allow) return false;
                            }
                        } else {
                            if (rule.action == .allow) return false;
                        }
                    }
                },
                .message_contains => {
                    if (rule.pattern) |substring| {
                        const has_match = std.mem.indexOf(u8, record.message, substring) != null;
                        if (has_match and rule.action == .deny) return false;
                        if (!has_match and rule.action == .allow) return false;
                    }
                },

                .message_regex, .custom => {},
            }
        }

        return true;
    }

    /// Clears all filter rules.
    pub fn clear(self: *Filter) void {
        for (self.rules.items) |rule| {
            if (rule.pattern) |p| {
                self.allocator.free(p);
            }
        }
        self.rules.clearRetainingCapacity();
    }

    /// Adds a filter for custom levels by priority.
    /// Only records with custom level priority >= min_priority will pass.
    pub fn addMinPriority(self: *Filter, min_priority: u8) !void {
        try self.rules.append(self.allocator, .{
            .rule_type = .level_min,
            .level = Level.fromPriority(min_priority) orelse .info,
            .action = .allow,
        });
    }

    /// Adds a filter for custom levels by priority range.
    pub fn addPriorityRange(self: *Filter, min_priority: u8, max_priority: u8) !void {
        try self.addMinPriority(min_priority);
        try self.rules.append(self.allocator, .{
            .rule_type = .level_max,
            .level = Level.fromPriority(max_priority) orelse .critical,
            .action = .allow,
        });
    }

    /// Alias for addRule
    pub const add = addRule;

    /// Alias for shouldLog
    pub const check = shouldLog;
    pub const test_ = shouldLog;
    pub const evaluate = shouldLog;

    /// Alias for clear
    pub const reset = clear;
    pub const removeAll = clear;

    /// Alias for addMinLevel
    pub const minLevel = addMinLevel;
    pub const min = addMinLevel;

    /// Alias for addMaxLevel
    pub const maxLevel = addMaxLevel;
    pub const max = addMaxLevel;

    /// Alias for addModulePrefix
    pub const moduleFilter = addModulePrefix;
    pub const addPrefix = addModulePrefix;

    /// Alias for addMessageFilter
    pub const messageFilter = addMessageFilter;

    /// Returns the number of filter rules.
    pub fn count(self: *const Filter) usize {
        return self.rules.items.len;
    }

    /// Alias for count
    pub const ruleCount = count;
    pub const length = count;

    /// Returns true if the filter has any rules.
    pub fn hasRules(self: *const Filter) bool {
        return self.rules.items.len > 0;
    }

    /// Returns true if the filter is empty (no rules).
    pub fn isEmpty(self: *const Filter) bool {
        return self.rules.items.len == 0;
    }

    /// Disable the filter (allow all).
    pub fn disable(self: *Filter) void {
        self.clear();
    }

    /// Create a filter from config settings.
    pub fn fromConfig(allocator: std.mem.Allocator, config: Config) !Filter {
        var filter = Filter.init(allocator);
        errdefer filter.deinit();

        // Apply minimum level from config
        try filter.addMinLevel(config.level);

        return filter;
    }

    /// Batch filter evaluation - returns array of booleans for each record.
    /// More efficient for processing multiple records at once.
    /// Performance: O(n * m) where n = records, m = rules.
    pub fn shouldLogBatch(self: *Filter, records: []const *const Record, results: []bool) void {
        std.debug.assert(records.len == results.len);
        for (records, 0..) |record, i| {
            results[i] = self.shouldLog(record);
        }
    }

    /// Fast path check - returns true if filter is empty (allow all).
    /// Use before shouldLog() to skip evaluation when possible.
    pub inline fn allowsAll(self: *const Filter) bool {
        return self.rules.items.len == 0;
    }

    /// Returns the allowed records count from stats.
    pub fn allowedCount(self: *const Filter) u64 {
        return @as(u64, self.stats.records_allowed.load(.monotonic));
    }

    /// Returns the denied records count from stats.
    pub fn deniedCount(self: *const Filter) u64 {
        return @as(u64, self.stats.records_denied.load(.monotonic));
    }

    /// Returns the total processed records count.
    pub fn totalProcessed(self: *const Filter) u64 {
        return self.allowedCount() + self.deniedCount();
    }

    /// Resets all statistics.
    pub fn resetStats(self: *Filter) void {
        self.stats = .{};
    }
};

/// Pre-built filter configurations for common use cases.
pub const FilterPresets = struct {
    /// Creates a filter that only allows error-level and above logs.
    pub fn errorsOnly(allocator: std.mem.Allocator) !Filter {
        var filter = Filter.init(allocator);
        try filter.addMinLevel(.err);
        return filter;
    }

    /// Creates a filter that excludes trace and debug logs.
    pub fn production(allocator: std.mem.Allocator) !Filter {
        var filter = Filter.init(allocator);
        try filter.addMinLevel(.info);
        return filter;
    }

    /// Creates a filter for a specific module.
    pub fn moduleOnly(allocator: std.mem.Allocator, module: []const u8) !Filter {
        var filter = Filter.init(allocator);
        try filter.addModulePrefix(module);
        return filter;
    }

    /// Creates a filtered sink configuration.
    pub fn createFilteredSink(file_path: []const u8, min_level: Level) SinkConfig {
        return SinkConfig{
            .path = file_path,
            .level = min_level,
            .color = false,
        };
    }
};

test "filter basic" {
    var filter = Filter.init(std.testing.allocator);
    defer filter.deinit();

    try filter.addMinLevel(.warning);

    var record_info = Record.init(std.testing.allocator, .info, "test");
    defer record_info.deinit();

    var record_err = Record.init(std.testing.allocator, .err, "test");
    defer record_err.deinit();

    try std.testing.expect(!filter.shouldLog(&record_info));
    try std.testing.expect(filter.shouldLog(&record_err));
}

test "filter max level" {
    var filter = Filter.init(std.testing.allocator);
    defer filter.deinit();

    try filter.addMinLevel(.info);
    try filter.addMaxLevel(.warning);

    var record_debug = Record.init(std.testing.allocator, .debug, "test");
    defer record_debug.deinit();

    var record_info = Record.init(std.testing.allocator, .info, "test");
    defer record_info.deinit();

    var record_warning = Record.init(std.testing.allocator, .warning, "test");
    defer record_warning.deinit();

    var record_err = Record.init(std.testing.allocator, .err, "test");
    defer record_err.deinit();

    // debug < info (min), should not pass
    try std.testing.expect(!filter.shouldLog(&record_debug));
    // info == info (min), should pass
    try std.testing.expect(filter.shouldLog(&record_info));
    // warning == warning (max), should pass
    try std.testing.expect(filter.shouldLog(&record_warning));
    // err > warning (max), should not pass
    try std.testing.expect(!filter.shouldLog(&record_err));
}

test "filter module prefix" {
    var filter = Filter.init(std.testing.allocator);
    defer filter.deinit();

    try filter.addModulePrefix("database");

    var record_no_module = Record.init(std.testing.allocator, .info, "test");
    defer record_no_module.deinit();

    var record_db = Record.init(std.testing.allocator, .info, "test");
    defer record_db.deinit();
    record_db.module = "database.query";

    var record_http = Record.init(std.testing.allocator, .info, "test");
    defer record_http.deinit();
    record_http.module = "http.server";

    // No module should fail
    try std.testing.expect(!filter.shouldLog(&record_no_module));
    // database.query starts with "database", should pass
    try std.testing.expect(filter.shouldLog(&record_db));
    // http.server does not start with "database", should fail
    try std.testing.expect(!filter.shouldLog(&record_http));
}

test "filter message contains" {
    var filter = Filter.init(std.testing.allocator);
    defer filter.deinit();

    try filter.addMessageFilter("heartbeat", .deny);

    var record_normal = Record.init(std.testing.allocator, .info, "User logged in");
    defer record_normal.deinit();

    var record_heartbeat = Record.init(std.testing.allocator, .info, "heartbeat check");
    defer record_heartbeat.deinit();

    // Normal message should pass
    try std.testing.expect(filter.shouldLog(&record_normal));
    // Message containing "heartbeat" should be denied
    try std.testing.expect(!filter.shouldLog(&record_heartbeat));
}

test "filter with custom level" {
    var filter = Filter.init(std.testing.allocator);
    defer filter.deinit();

    // Set minimum level to warning (priority 30)
    try filter.addMinLevel(.warning);

    // Custom level with priority 35 (between warning 30 and err 40)
    var record_custom = Record.initCustom(std.testing.allocator, .warning, "AUDIT", "35", "Audit event");
    defer record_custom.deinit();

    // Custom level uses the base level for filtering, which is .warning (30)
    // Since warning (30) >= warning (30), it should pass
    try std.testing.expect(filter.shouldLog(&record_custom));

    // Custom level with lower priority (mapped to info which is 20)
    var record_custom_low = Record.initCustom(std.testing.allocator, .info, "NOTICE", "96", "Notice event");
    defer record_custom_low.deinit();

    // info (20) < warning (30), should not pass
    try std.testing.expect(!filter.shouldLog(&record_custom_low));
}
