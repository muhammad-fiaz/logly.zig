const std = @import("std");
const Level = @import("level.zig").Level;
const Record = @import("record.zig").Record;

/// Filter for conditionally processing log records.
///
/// Filters allow fine-grained control over which log records are processed.
/// They can be combined to create complex filtering logic based on level,
/// message content, module, or custom predicates.
pub const Filter = struct {
    allocator: std.mem.Allocator,
    rules: std.ArrayList(FilterRule),

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
                        const contains = std.mem.indexOf(u8, record.message, substring) != null;
                        if (contains and rule.action == .deny) return false;
                        if (!contains and rule.action == .allow) return false;
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
