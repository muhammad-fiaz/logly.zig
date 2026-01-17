//! Log Filter Module
//!
//! Provides conditional processing of log records based on configurable rules.
//! Filters can be combined to create complex filtering logic.
//!
//! Filter Types:
//! - Level-based: Minimum/maximum level, level ranges
//! - Content-based: Message contains/matches patterns
//! - Module-based: Allow/deny specific modules
//! - Custom: User-defined predicate functions
//!
//! Combinators:
//! - AND: All rules must match
//! - OR: Any rule must match
//! - NOT: Invert rule result
//!
//! Use Cases:
//! - Development: Show all logs
//! - Production: Errors and warnings only
//! - Debugging: Focus on specific modules
//! - Security: Filter sensitive information
//!
//! Performance:
//! - O(n) where n is number of rules
//! - Short-circuit evaluation for OR/AND
//! - Cached regex patterns

const std = @import("std");
const Config = @import("config.zig").Config;
const Level = @import("level.zig").Level;
const Record = @import("record.zig").Record;
const SinkConfig = @import("sink.zig").SinkConfig;
const Constants = @import("constants.zig");
const Utils = @import("utils.zig");

/// Filter for conditionally processing log records.
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
            return Utils.calculateRate(
                Utils.atomicLoadU64(&self.records_allowed),
                Utils.atomicLoadU64(&self.total_records_evaluated),
            );
        }

        /// Calculate deny rate (0.0 - 1.0)
        pub fn denyRate(self: *const FilterStats) f64 {
            return Utils.calculateRate(
                Utils.atomicLoadU64(&self.records_denied),
                Utils.atomicLoadU64(&self.total_records_evaluated),
            );
        }

        /// Calculate error rate (0.0 - 1.0)
        pub fn errorRate(self: *const FilterStats) f64 {
            return Utils.calculateErrorRate(
                Utils.atomicLoadU64(&self.evaluation_errors),
                Utils.atomicLoadU64(&self.total_records_evaluated),
            );
        }

        /// Returns true if any records have been denied.
        pub fn hasDenied(self: *const FilterStats) bool {
            return self.records_denied.load(.monotonic) > 0;
        }

        /// Returns true if any evaluation errors occurred.
        pub fn hasEvaluationErrors(self: *const FilterStats) bool {
            return self.evaluation_errors.load(.monotonic) > 0;
        }

        /// Returns total records evaluated as u64.
        pub fn getTotal(self: *const FilterStats) u64 {
            return Utils.atomicLoadU64(&self.total_records_evaluated);
        }

        /// Returns allowed records count as u64.
        pub fn getAllowed(self: *const FilterStats) u64 {
            return Utils.atomicLoadU64(&self.records_allowed);
        }

        /// Returns denied records count as u64.
        pub fn getDenied(self: *const FilterStats) u64 {
            return Utils.atomicLoadU64(&self.records_denied);
        }

        /// Returns rules added count as u64.
        pub fn getRulesAdded(self: *const FilterStats) u64 {
            return Utils.atomicLoadU64(&self.rules_added);
        }

        /// Calculate throughput records per second.
        pub fn throughput(self: *const FilterStats, elapsed_ms: i64) f64 {
            return Utils.calculateRecordsPerSecond(self.getTotal(), elapsed_ms);
        }

        /// Reset all statistics to zero.
        pub fn reset(self: *FilterStats) void {
            self.total_records_evaluated.store(0, .monotonic);
            self.records_allowed.store(0, .monotonic);
            self.records_denied.store(0, .monotonic);
            self.rules_added.store(0, .monotonic);
            self.evaluation_errors.store(0, .monotonic);
        }
    };

    /// Logical mode for combining multiple filter rules.
    pub const Mode = enum {
        /// All rules must pass for record to be allowed (Implicit AND).
        all,
        /// At least one rule must pass for record to be allowed (Implicit OR).
        any,
        /// Record is allowed only if NO rules match (NOR).
        none,
        /// Invert the result of 'all' (NAND).
        not_all,
    };

    allocator: std.mem.Allocator,
    rules: std.ArrayList(FilterRule),
    stats: FilterStats = .{},
    mutex: std.Thread.Mutex = .{},
    mode: Mode = .all,
    enabled: bool = true,

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
    ///
    /// Filter rules are evaluated in order and can allow or deny records
    /// based on level, module, message content, or custom criteria.
    pub const FilterRule = struct {
        /// The type of rule to apply (level, module, message, etc.).
        rule_type: RuleType,
        /// Pattern to match against (for module/message rules).
        pattern: ?[]const u8 = null,
        /// Log level for level-based rules.
        level: ?Level = null,
        /// Action to take when rule matches (allow or deny).
        action: Action = .allow,
        /// Specific key for context-based filtering.
        context_key: ?[]const u8 = null,
        /// User-defined predicate function for complex filtering.
        predicate: ?*const fn (*const Record) bool = null,

        /// Types of filter rules available.
        pub const RuleType = enum {
            /// Only allow records at or above minimum level.
            level_min,
            /// Only allow records at or below maximum level.
            level_max,
            /// Only allow records at exact level.
            level_exact,
            /// Match records from specific module name.
            module_match,
            /// Match records from modules starting with prefix.
            module_prefix,
            /// Match records using regex for module name.
            module_regex,
            /// Match records containing specified text.
            message_contains,
            /// Match records using regex pattern.
            message_regex,
            /// Match records by source file name.
            source_file_match,
            /// Match records by source file regex.
            source_file_regex,
            /// Match records by function name.
            function_match,
            /// Match records by function regex.
            function_regex,
            /// Match records by trace ID.
            trace_id_match,
            /// Match records by span ID.
            span_id_match,
            /// Match records having specific context key.
            context_has_key,
            /// Match records with specific context value.
            context_value_match,
            /// Match records by thread ID.
            thread_id_match,
            /// Match records that contain error information.
            has_error,
            /// Custom predicate-based filtering.
            custom,
        };

        /// Action to take when a filter rule matches.
        pub const Action = enum {
            /// Allow the record to pass through.
            allow,
            /// Deny/block the record.
            deny,
        };
    };

    /// Initializes a new Filter instance.
    ///
    /// Arguments:
    ///   - `allocator`: Memory allocator for internal storage.
    ///
    /// Return Value:
    ///   - A new `Filter` instance.
    ///
    /// Complexity: O(1)
    pub fn init(allocator: std.mem.Allocator) Filter {
        return .{
            .allocator = allocator,
            .rules = .empty,
        };
    }

    pub const create = init;

    /// Releases all resources associated with the filter.
    ///
    /// Frees all rules and character patterns.
    ///
    /// Complexity: O(N) where N is the number of rules.
    pub fn deinit(self: *Filter) void {
        for (self.rules.items) |rule| {
            if (rule.pattern) |p| {
                self.allocator.free(p);
            }
            if (rule.context_key) |k| {
                self.allocator.free(k);
            }
        }
        self.rules.deinit(self.allocator);
    }

    pub const destroy = deinit;

    /// Adds a new filter rule.
    pub fn addRule(self: *Filter, rule: FilterRule) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Deep copy patterns and keys if present
        var new_rule = rule;
        if (rule.pattern) |p| {
            new_rule.pattern = try self.allocator.dupe(u8, p);
        }
        if (rule.context_key) |k| {
            new_rule.context_key = try self.allocator.dupe(u8, k);
        }

        try self.rules.append(self.allocator, new_rule);
        _ = self.stats.rules_added.fetchAdd(1, .monotonic);

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
    ///   - `level`: The minimum level to allow.
    ///
    /// Complexity: O(1) (Amortized append)
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
    ///   - `level`: The maximum level to allow.
    ///
    /// Complexity: O(1) (Amortized append)
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
    ///   - `prefix`: The module prefix to match (copied internally).
    ///
    /// Complexity: O(M) where M is prefix length.
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
    /// Records containing the specified substring will be filtered according to `action`.
    ///
    /// Arguments:
    ///   - `substring`: The substring to search for (copied internally).
    ///   - `action`: Whether to allow or deny matching records.
    ///
    /// Complexity: O(S) where S is substring length.
    pub fn addMessageFilter(self: *Filter, substring: []const u8, action: FilterRule.Action) !void {
        const owned_substring = try self.allocator.dupe(u8, substring);
        try self.rules.append(self.allocator, .{
            .rule_type = .message_contains,
            .pattern = owned_substring,
            .action = action,
        });
    }

    /// Evaluates whether a record should be processed based on configured rules.
    ///
    /// Algorithm:
    ///   - Iterates through all rules.
    ///   - If any rule blocks the record, returns false immediately.
    ///   - For `allow` rules, condition must match to proceed (implicit AND logic for some types).
    ///   - Note: Logic here implements a mix of "allow-list" and "block-list" behavior depending on rule types.
    ///
    /// Arguments:
    ///   - `record`: The log record to evaluate.
    ///
    /// Return Value:
    ///   - `true` if the record should be processed, `false` otherwise.
    ///
    /// Complexity: O(N * M) where N is rules and M is message/module length.
    pub fn shouldLog(self: *const Filter, record: *const Record) bool {
        if (!self.enabled) return true;
        if (self.rules.items.len == 0) return true;

        _ = @constCast(&self.stats.total_records_evaluated).fetchAdd(1, .monotonic);

        const result = switch (self.mode) {
            .all => self.evaluateAll(record),
            .any => self.evaluateAny(record),
            .none => !self.evaluateAny(record),
            .not_all => !self.evaluateAll(record),
        };

        if (result) {
            _ = @constCast(&self.stats.records_allowed).fetchAdd(1, .monotonic);
        } else {
            _ = @constCast(&self.stats.records_denied).fetchAdd(1, .monotonic);
        }

        return result;
    }

    fn evaluateAll(self: *const Filter, record: *const Record) bool {
        for (self.rules.items, 0..) |rule, i| {
            const matches = self.checkRule(rule, record);
            const passed = if (rule.action == .allow) matches else !matches;

            if (!passed) {
                if (self.on_record_denied) |cb| cb(record, @intCast(i));
                return false;
            }
        }
        if (self.on_record_allowed) |cb| cb(record, @intCast(self.rules.items.len));
        return true;
    }

    fn evaluateAny(self: *const Filter, record: *const Record) bool {
        for (self.rules.items, 0..) |rule, i| {
            const matches = self.checkRule(rule, record);
            const passed = if (rule.action == .allow) matches else !matches;

            if (passed) {
                if (self.on_record_allowed) |cb| cb(record, @intCast(i + 1));
                return true;
            }
        }
        if (self.on_record_denied) |cb| cb(record, 0);
        return false;
    }

    fn checkRule(self: *const Filter, rule: FilterRule, record: *const Record) bool {
        _ = self;
        return switch (rule.rule_type) {
            .level_min => if (rule.level) |l| record.level.priority() >= l.priority() else true,
            .level_max => if (rule.level) |l| record.level.priority() <= l.priority() else true,
            .level_exact => if (rule.level) |l| record.level == l else true,

            .module_match => if (rule.pattern) |p| if (record.module) |m| std.mem.eql(u8, m, p) else false else true,
            .module_prefix => if (rule.pattern) |p| if (record.module) |m| std.mem.startsWith(u8, m, p) else false else true,
            .module_regex => if (rule.pattern) |p| (if (record.module) |m| Utils.findRegexPattern(m, p) != null else false) else true,

            .message_contains => if (rule.pattern) |p| std.mem.indexOf(u8, record.message, p) != null else true,
            .message_regex => if (rule.pattern) |p| Utils.findRegexPattern(record.message, p) != null else true,

            .source_file_match => if (rule.pattern) |p| if (record.filename) |f| std.mem.eql(u8, f, p) else false else true,
            .source_file_regex => if (rule.pattern) |p| (if (record.filename) |f| Utils.findRegexPattern(f, p) != null else false) else true,

            .function_match => if (rule.pattern) |p| if (record.function) |f| std.mem.eql(u8, f, p) else false else true,
            .function_regex => if (rule.pattern) |p| (if (record.function) |f| Utils.findRegexPattern(f, p) != null else false) else true,

            .trace_id_match => if (rule.pattern) |p| if (record.trace_id) |tid| std.mem.eql(u8, tid, p) else false else true,
            .span_id_match => if (rule.pattern) |p| if (record.span_id) |sid| std.mem.eql(u8, sid, p) else false else true,

            .thread_id_match => if (rule.pattern) |p| if (record.thread_id) |tid| blk: {
                var buf: [32]u8 = undefined;
                const tid_str = std.fmt.bufPrint(&buf, "{d}", .{tid}) catch "";
                break :blk std.mem.eql(u8, tid_str, p);
            } else false else true,

            .context_has_key => if (rule.context_key) |k| record.context.contains(k) else false,
            .context_value_match => if (rule.context_key) |k| if (rule.pattern) |p| if (record.context.get(k)) |v| blk: {
                var buf: [256]u8 = undefined;
                const v_str = switch (v) {
                    .string => |s| s,
                    .integer => |i| std.fmt.bufPrint(&buf, "{d}", .{i}) catch "",
                    .float => |f| std.fmt.bufPrint(&buf, "{d}", .{f}) catch "",
                    .bool => |b| if (b) "true" else "false",
                    else => "",
                };
                if (Utils.findRegexPattern(v_str, p) != null) break :blk true;
                break :blk false;
            } else false else false else false,

            .has_error => record.error_info != null,

            .custom => if (rule.predicate) |pred| pred(record) else true,
        };
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

    /// Explicitly allow a module.
    pub fn allowModule(self: *Filter, module: []const u8) !void {
        try self.addRule(.{
            .rule_type = .module_match,
            .pattern = module,
            .action = .allow,
        });
    }

    /// Explicitly deny a module.
    pub fn denyModule(self: *Filter, module: []const u8) !void {
        try self.addRule(.{
            .rule_type = .module_match,
            .pattern = module,
            .action = .deny,
        });
    }

    /// Allow modules starting with prefix.
    pub fn allowPrefix(self: *Filter, prefix: []const u8) !void {
        try self.addRule(.{
            .rule_type = .module_prefix,
            .pattern = prefix,
            .action = .allow,
        });
    }

    /// Deny modules starting with prefix.
    pub fn denyPrefix(self: *Filter, prefix: []const u8) !void {
        try self.addRule(.{
            .rule_type = .module_prefix,
            .pattern = prefix,
            .action = .deny,
        });
    }

    /// Allow messages matching regex.
    pub fn allowRegex(self: *Filter, regex: []const u8) !void {
        try self.addRule(.{
            .rule_type = .message_regex,
            .pattern = regex,
            .action = .allow,
        });
    }

    /// Deny messages matching regex.
    pub fn denyRegex(self: *Filter, regex: []const u8) !void {
        try self.addRule(.{
            .rule_type = .message_regex,
            .pattern = regex,
            .action = .deny,
        });
    }

    /// Add a custom predicate rule.
    pub fn addCustom(self: *Filter, predicate: *const fn (*const Record) bool, action: FilterRule.Action) !void {
        try self.addRule(.{
            .rule_type = .custom,
            .predicate = predicate,
            .action = action,
        });
    }

    /// Add a context value match rule.
    pub fn addContextMatch(self: *Filter, key: []const u8, pattern: []const u8, action: FilterRule.Action) !void {
        try self.addRule(.{
            .rule_type = .context_value_match,
            .context_key = key,
            .pattern = pattern,
            .action = action,
        });
    }

    /// Only allow records with errors.
    pub fn addErrorOnly(self: *Filter) !void {
        try self.addRule(.{
            .rule_type = .has_error,
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

    /// Aliases for convenience
    pub const allow = allowModule;
    pub const deny = denyModule;
    pub const keep = allowModule;
    pub const drop = denyModule;
    pub const include = allowModule;
    pub const exclude = denyModule;

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
        return self.stats.getAllowed();
    }

    /// Returns the denied records count from stats.
    pub fn deniedCount(self: *const Filter) u64 {
        return self.stats.getDenied();
    }

    /// Returns the total processed records count.
    pub fn totalProcessed(self: *const Filter) u64 {
        return self.allowedCount() + self.deniedCount();
    }

    /// Resets all statistics.
    pub fn resetStats(self: *Filter) void {
        self.stats.reset();
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
        try filter.allowModule(module);
        return filter;
    }

    /// Filter for development - allow all.
    pub fn development(allocator: std.mem.Allocator) !Filter {
        return Filter.init(allocator);
    }

    /// Filter for verbose mode - include trace logs.
    pub fn verbose(allocator: std.mem.Allocator) !Filter {
        var filter = Filter.init(allocator);
        try filter.addMinLevel(.trace);
        return filter;
    }

    /// Only allow warnings and errors.
    pub fn warningsAndErrors(allocator: std.mem.Allocator) !Filter {
        var filter = Filter.init(allocator);
        try filter.addMinLevel(.warning);
        return filter;
    }

    /// Filter out network-related logs.
    pub fn noNetwork(allocator: std.mem.Allocator) !Filter {
        var filter = Filter.init(allocator);
        try filter.denyPrefix("network");
        try filter.denyPrefix("http");
        try filter.denyPrefix("socket");
        return filter;
    }

    /// Filter only specific module.
    pub fn only(allocator: std.mem.Allocator, module: []const u8) !Filter {
        var filter = Filter.init(allocator);
        try filter.allowModule(module);
        filter.mode = .all; // Ensuring it's the only one if multiple applied? No, init is fresh.
        return filter;
    }

    /// Exclude specific module.
    pub fn exclude(allocator: std.mem.Allocator, module: []const u8) !Filter {
        var filter = Filter.init(allocator);
        try filter.denyModule(module);
        return filter;
    }

    /// Filter for audit logs.
    pub fn audit(allocator: std.mem.Allocator) !Filter {
        var filter = Filter.init(allocator);
        try filter.addMessageFilter("audit", .allow);
        return filter;
    }

    /// Filter for security events.
    pub fn security(allocator: std.mem.Allocator) !Filter {
        var filter = Filter.init(allocator);
        try filter.addMessageFilter("security", .allow);
        try filter.addMessageFilter("auth", .allow);
        filter.mode = .any;
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

test "filter modes any" {
    var filter = Filter.init(std.testing.allocator);
    defer filter.deinit();
    filter.mode = .any;

    try filter.allowModule("auth");
    try filter.addMinLevel(.err);

    var record_auth_info = Record.init(std.testing.allocator, .info, "login");
    defer record_auth_info.deinit();
    record_auth_info.module = "auth";

    var record_db_err = Record.init(std.testing.allocator, .err, "db error");
    defer record_db_err.deinit();
    record_db_err.module = "database";

    var record_db_info = Record.init(std.testing.allocator, .info, "db info");
    defer record_db_info.deinit();
    record_db_info.module = "database";

    // auth info matches module allow rule
    try std.testing.expect(filter.shouldLog(&record_auth_info));
    // db err matches min level rule
    try std.testing.expect(filter.shouldLog(&record_db_err));
    // db info matches neither
    try std.testing.expect(!filter.shouldLog(&record_db_info));
}

test "filter regex" {
    var filter = Filter.init(std.testing.allocator);
    defer filter.deinit();

    try filter.allowRegex("user_\\d+");

    var record_match = Record.init(std.testing.allocator, .info, "Hello user_123");
    defer record_match.deinit();

    var record_no_match = Record.init(std.testing.allocator, .info, "Hello user_abc");
    defer record_no_match.deinit();

    try std.testing.expect(filter.shouldLog(&record_match));
    try std.testing.expect(!filter.shouldLog(&record_no_match));
}

test "filter context" {
    var filter = Filter.init(std.testing.allocator);
    defer filter.deinit();

    try filter.addContextMatch("request_id", "req-*", .allow);

    var record_match = Record.init(std.testing.allocator, .info, "msg");
    defer record_match.deinit();
    try record_match.context.put("request_id", .{ .string = "req-123" });

    var record_no_match = Record.init(std.testing.allocator, .info, "msg");
    defer record_no_match.deinit();
    try record_no_match.context.put("request_id", .{ .string = "other-123" });

    try std.testing.expect(filter.shouldLog(&record_match));
    try std.testing.expect(!filter.shouldLog(&record_no_match));
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
