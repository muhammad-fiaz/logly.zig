const std = @import("std");
const Level = @import("level.zig").Level;
const Record = @import("record.zig").Record;
const Config = @import("config.zig").Config;
const Constants = @import("constants.zig");

/// Unified Rules System for compiler-style guided diagnostics.
///
/// The Rules engine attaches contextual diagnostic messages to log entries
/// based on configurable conditions. This enables IDE-style guidance including:
/// - Error analysis and root cause identification
/// - Solution suggestions and best practices
/// - Documentation links and bug report URLs
/// - Performance tips and security notices
pub const Rules = struct {
    allocator: std.mem.Allocator,
    rules: std.ArrayList(Rule),
    enabled: bool = false,
    mutex: std.Thread.Mutex = .{},
    stats: RulesStats = .{},
    config: InternalRulesConfig = .{},

    // Callbacks
    on_rule_matched: ?*const fn (*const Rule, *const Record) void = null,
    on_rule_evaluated: ?*const fn (*const Rule, *const Record, bool) void = null,
    on_messages_attached: ?*const fn (*const Record, usize) void = null,
    on_evaluation_error: ?*const fn ([]const u8) void = null,
    on_before_evaluate: ?*const fn (*const Record) void = null,
    on_after_evaluate: ?*const fn (*const Record, usize) void = null,

    /// Rules engine statistics for monitoring and diagnostics.
    pub const RulesStats = struct {
        rules_evaluated: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        rules_matched: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        messages_emitted: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        evaluations_skipped: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),

        pub fn matchRate(self: *const RulesStats) f64 {
            const evaluated = @as(u64, self.rules_evaluated.load(.monotonic));
            if (evaluated == 0) return 0;
            const matched = @as(u64, self.rules_matched.load(.monotonic));
            return @as(f64, @floatFromInt(matched)) / @as(f64, @floatFromInt(evaluated));
        }

        pub fn reset(self: *RulesStats) void {
            self.rules_evaluated.store(0, .monotonic);
            self.rules_matched.store(0, .monotonic);
            self.messages_emitted.store(0, .monotonic);
            self.evaluations_skipped.store(0, .monotonic);
        }
    };

    /// Message category with professional styling for different diagnostic types.
    pub const MessageCategory = enum {
        error_analysis,
        solution_suggestion,
        best_practice,
        action_required,
        documentation_link,
        bug_report,
        general_information,
        warning_explanation,
        performance_tip,
        security_notice,
        custom,

        pub fn displayName(self: MessageCategory) []const u8 {
            return switch (self) {
                .error_analysis => "Error Analysis",
                .solution_suggestion => "Solution",
                .best_practice => "Best Practice",
                .action_required => "Action Required",
                .documentation_link => "Documentation",
                .bug_report => "Report Issue",
                .general_information => "Information",
                .warning_explanation => "Warning Details",
                .performance_tip => "Performance",
                .security_notice => "Security",
                .custom => "Note",
            };
        }

        /// Returns the default prefix with symbol for this category (Unicode).
        pub fn prefix(self: MessageCategory) []const u8 {
            return switch (self) {
                .error_analysis => "    -> [cause]",
                .solution_suggestion => "    -> [fix]",
                .best_practice => "    -> [suggest]",
                .action_required => "    -> [action]",
                .documentation_link => "    -> [docs]",
                .bug_report => "    -> [report]",
                .general_information => "    -> [note]",
                .warning_explanation => "    -> [caution]",
                .performance_tip => "    -> [perf]",
                .security_notice => "    -> [security]",
                .custom => "    -> [custom]",
            };
        }

        /// Returns the ASCII-only prefix (for non-UTF8 terminals).
        pub fn prefixAscii(self: MessageCategory) []const u8 {
            return switch (self) {
                .error_analysis => "    |-- [cause]",
                .solution_suggestion => "    |-- [fix]",
                .best_practice => "    |-- [suggest]",
                .action_required => "    |-- [action]",
                .documentation_link => "    |-- [docs]",
                .bug_report => "    |-- [report]",
                .general_information => "    |-- [note]",
                .warning_explanation => "    |-- [caution]",
                .performance_tip => "    |-- [perf]",
                .security_notice => "    |-- [security]",
                .custom => "    |-- [custom]",
            };
        }

        /// Returns the default ANSI color code for this category.
        pub fn defaultColor(self: MessageCategory) []const u8 {
            return switch (self) {
                .error_analysis => "91",
                .solution_suggestion => "96",
                .best_practice => "93",
                .action_required => "91;1",
                .documentation_link => "35",
                .bug_report => "33",
                .general_information => "37",
                .warning_explanation => "33",
                .performance_tip => "36",
                .security_notice => "95",
                .custom => "37",
            };
        }

        // Aliases for convenience
        pub const cause = MessageCategory.error_analysis;
        pub const diagnostic = MessageCategory.error_analysis;
        pub const analysis = MessageCategory.error_analysis;
        pub const fix = MessageCategory.solution_suggestion;
        pub const solution = MessageCategory.solution_suggestion;
        pub const help = MessageCategory.solution_suggestion;
        pub const suggest = MessageCategory.best_practice;
        pub const hint = MessageCategory.best_practice;
        pub const tip = MessageCategory.best_practice;
        pub const action = MessageCategory.action_required;
        pub const todo = MessageCategory.action_required;
        pub const docs = MessageCategory.documentation_link;
        pub const reference = MessageCategory.documentation_link;
        pub const link = MessageCategory.documentation_link;
        pub const report = MessageCategory.bug_report;
        pub const issue = MessageCategory.bug_report;
        pub const note = MessageCategory.general_information;
        pub const info = MessageCategory.general_information;
        pub const caution = MessageCategory.warning_explanation;
        pub const warning = MessageCategory.warning_explanation;
        pub const warn = MessageCategory.warning_explanation;
        pub const perf = MessageCategory.performance_tip;
        pub const performance = MessageCategory.performance_tip;
        pub const security = MessageCategory.security_notice;
    };

    /// A single diagnostic message attached to a rule.
    pub const RuleMessage = struct {
        category: MessageCategory,
        title: ?[]const u8 = null,
        message: []const u8,
        url: ?[]const u8 = null,
        custom_color: ?[]const u8 = null,
        custom_prefix: ?[]const u8 = null,
        use_background: bool = false,
        background_color: ?[]const u8 = null,

        pub fn getColor(self: *const RuleMessage) []const u8 {
            return self.custom_color orelse self.category.defaultColor();
        }

        pub fn getPrefix(self: *const RuleMessage, use_unicode: bool) []const u8 {
            if (self.custom_prefix) |cp| return cp;
            return if (use_unicode) self.category.prefix() else self.category.prefixAscii();
        }

        // Convenience constructors
        pub fn cause(msg: []const u8) RuleMessage {
            return .{ .category = .error_analysis, .message = msg };
        }

        pub fn fix(msg: []const u8) RuleMessage {
            return .{ .category = .solution_suggestion, .message = msg };
        }

        pub fn suggest(msg: []const u8) RuleMessage {
            return .{ .category = .best_practice, .message = msg };
        }

        pub fn action(msg: []const u8) RuleMessage {
            return .{ .category = .action_required, .message = msg };
        }

        pub fn docs(title: []const u8, url: []const u8) RuleMessage {
            return .{ .category = .documentation_link, .title = title, .message = "See documentation", .url = url };
        }

        pub fn report(title: []const u8, url: []const u8) RuleMessage {
            return .{ .category = .bug_report, .title = title, .message = "Report issue", .url = url };
        }

        pub fn note(msg: []const u8) RuleMessage {
            return .{ .category = .general_information, .message = msg };
        }

        pub fn caution(msg: []const u8) RuleMessage {
            return .{ .category = .warning_explanation, .message = msg };
        }

        pub fn perf(msg: []const u8) RuleMessage {
            return .{ .category = .performance_tip, .message = msg };
        }

        pub fn security(msg: []const u8) RuleMessage {
            return .{ .category = .security_notice, .message = msg };
        }

        pub fn custom(custom_prefix: []const u8, msg: []const u8) RuleMessage {
            return .{ .category = .custom, .custom_prefix = custom_prefix, .message = msg };
        }

        pub fn withColor(msg: RuleMessage, color: []const u8) RuleMessage {
            var m = msg;
            m.custom_color = color;
            return m;
        }

        pub fn withUrl(msg: RuleMessage, url: []const u8) RuleMessage {
            var m = msg;
            m.url = url;
            return m;
        }

        pub fn withTitle(msg: RuleMessage, title: []const u8) RuleMessage {
            var m = msg;
            m.title = title;
            return m;
        }
    };

    /// Level matching specification for rules.
    pub const LevelMatch = union(enum) {
        exact: Level,
        min_priority: u8,
        max_priority: u8,
        priority_range: struct { min: u8, max: u8 },
        custom_name: []const u8,
        any: void,

        pub fn level(lvl: Level) LevelMatch {
            return .{ .exact = lvl };
        }

        pub fn errors() LevelMatch {
            return .{ .min_priority = 40 };
        }

        pub fn warnings() LevelMatch {
            return .{ .min_priority = 30 };
        }

        pub fn all() LevelMatch {
            return .{ .any = {} };
        }
    };

    /// A complete rule definition.
    pub const Rule = struct {
        id: u32,
        name: ?[]const u8 = null,
        enabled: bool = true,
        once: bool = false,
        fired: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
        level_match: ?LevelMatch = null,
        module: ?[]const u8 = null,
        function: ?[]const u8 = null,
        message_contains: ?[]const u8 = null,
        messages: []const RuleMessage,
        priority: u8 = 100,

        pub fn matches(self: *const Rule, record: *const Record) bool {
            if (!self.enabled) return false;
            if (self.once and self.fired.load(.monotonic)) return false;

            if (self.level_match) |lm| {
                const matched = switch (lm) {
                    .exact => |lev| record.level == lev,
                    .min_priority => |min| record.level.priority() >= min,
                    .max_priority => |max| record.level.priority() <= max,
                    .priority_range => |range| record.level.priority() >= range.min and record.level.priority() <= range.max,
                    .custom_name => |name| blk: {
                        if (record.custom_level_name) |cname| {
                            break :blk std.mem.eql(u8, cname, name);
                        }
                        break :blk false;
                    },
                    .any => true,
                };
                if (!matched) return false;
            }

            if (self.module) |mod| {
                if (record.module) |rec_mod| {
                    if (!std.mem.eql(u8, rec_mod, mod)) return false;
                } else {
                    return false;
                }
            }

            if (self.function) |func| {
                if (record.function) |rec_func| {
                    if (!std.mem.eql(u8, rec_func, func)) return false;
                } else {
                    return false;
                }
            }

            if (self.message_contains) |pattern| {
                if (std.mem.indexOf(u8, record.message, pattern) == null) {
                    return false;
                }
            }

            return true;
        }

        pub fn markFired(self: *Rule) void {
            if (self.once) {
                self.fired.store(true, .monotonic);
            }
        }

        pub fn resetFired(self: *Rule) void {
            self.fired.store(false, .monotonic);
        }
    };

    /// Rules configuration - re-exported from global config for consistency.
    pub const RulesConfig = Config.RulesConfig;

    /// Initialize from global Config's RulesConfig.
    pub fn initFromGlobalConfig(allocator: std.mem.Allocator, global_config: Config) Rules {
        const rules_cfg = global_config.rules;
        return .{
            .allocator = allocator,
            .rules = .empty,
            .enabled = rules_cfg.enabled,
            .config = .{
                .use_unicode = rules_cfg.use_unicode,
                .enable_colors = rules_cfg.enable_colors,
                .show_rule_id = rules_cfg.show_rule_id,
                .indent = rules_cfg.indent,
                .message_prefix = rules_cfg.message_prefix,
                .include_in_json = rules_cfg.include_in_json,
                .max_rules = rules_cfg.max_rules,
            },
        };
    }

    /// Sync configuration from global Config.
    pub fn syncWithGlobalConfig(self: *Rules, global_config: Config) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const rules_cfg = global_config.rules;
        self.enabled = rules_cfg.enabled;
        self.config.use_unicode = rules_cfg.use_unicode;
        self.config.enable_colors = rules_cfg.enable_colors;
        self.config.show_rule_id = rules_cfg.show_rule_id;
        self.config.indent = rules_cfg.indent;
        self.config.message_prefix = rules_cfg.message_prefix;
        self.config.include_in_json = rules_cfg.include_in_json;
        self.config.max_rules = rules_cfg.max_rules;
    }

    /// Internal RulesConfig struct (local copy of settings).
    pub const InternalRulesConfig = struct {
        use_unicode: bool = true,
        enable_colors: bool = true,
        show_rule_id: bool = false,
        indent: []const u8 = "    ",
        message_prefix: []const u8 = "->",
        include_in_json: bool = true,
        max_rules: usize = 1000,

        pub fn minimal() InternalRulesConfig {
            return .{ .use_unicode = true, .enable_colors = true };
        }

        pub fn production() InternalRulesConfig {
            return .{ .use_unicode = false, .enable_colors = false, .show_rule_id = false };
        }

        pub fn development() InternalRulesConfig {
            return .{ .use_unicode = true, .enable_colors = true, .show_rule_id = true };
        }

        pub fn ascii() InternalRulesConfig {
            return .{ .use_unicode = false, .enable_colors = true };
        }
    };

    // Initialization
    pub fn init(allocator: std.mem.Allocator) Rules {
        return .{
            .allocator = allocator,
            .rules = .empty,
        };
    }

    pub fn initWithConfig(allocator: std.mem.Allocator, config: RulesConfig) Rules {
        return .{
            .allocator = allocator,
            .rules = .empty,
            .config = config,
        };
    }

    pub fn deinit(self: *Rules) void {
        self.rules.deinit(self.allocator);
    }

    // Configuration methods
    pub fn enable(self: *Rules) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.enabled = true;
    }

    pub fn disable(self: *Rules) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.enabled = false;
    }

    pub fn isEnabled(self: *const Rules) bool {
        return self.enabled;
    }

    pub fn configure(self: *Rules, config: RulesConfig) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.config = config;
    }

    pub fn setUnicode(self: *Rules, use_unicode: bool) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.config.use_unicode = use_unicode;
    }

    pub fn setColors(self: *Rules, enable_colors: bool) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.config.enable_colors = enable_colors;
    }

    // Callback setters
    pub fn setRuleMatchedCallback(self: *Rules, callback: *const fn (*const Rule, *const Record) void) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.on_rule_matched = callback;
    }

    pub fn setRuleEvaluatedCallback(self: *Rules, callback: *const fn (*const Rule, *const Record, bool) void) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.on_rule_evaluated = callback;
    }

    pub fn setMessagesAttachedCallback(self: *Rules, callback: *const fn (*const Record, usize) void) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.on_messages_attached = callback;
    }

    pub fn setEvaluationErrorCallback(self: *Rules, callback: *const fn ([]const u8) void) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.on_evaluation_error = callback;
    }

    pub fn setBeforeEvaluateCallback(self: *Rules, callback: *const fn (*const Record) void) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.on_before_evaluate = callback;
    }

    pub fn setAfterEvaluateCallback(self: *Rules, callback: *const fn (*const Record, usize) void) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.on_after_evaluate = callback;
    }

    // Rule management

    /// Adds a new rule to the engine. Returns error if rule ID already exists.
    ///
    /// Arguments:
    ///     rule: The rule to add.
    ///
    /// Returns:
    ///     error.RuleIdAlreadyExists if a rule with the same ID exists.
    ///     error.TooManyRules if the max rules limit is reached.
    pub fn add(self: *Rules, rule: Rule) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.rules.items.len >= self.config.max_rules) {
            return error.TooManyRules;
        }

        // Check for duplicate ID
        for (self.rules.items) |existing| {
            if (existing.id == rule.id) {
                return error.RuleIdAlreadyExists;
            }
        }

        try self.rules.append(self.allocator, rule);
    }

    /// Adds a rule, updating it if a rule with the same ID already exists.
    /// Use this when you want to allow updates.
    pub fn addOrUpdate(self: *Rules, rule: Rule) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.rules.items.len >= self.config.max_rules) {
            return error.TooManyRules;
        }

        // Check for existing rule with same ID and update
        for (self.rules.items, 0..) |existing, i| {
            if (existing.id == rule.id) {
                self.rules.items[i] = rule;
                return;
            }
        }

        try self.rules.append(self.allocator, rule);
    }

    /// Checks if a rule with the given ID exists.
    pub fn hasRule(self: *Rules, id: u32) bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.rules.items) |rule| {
            if (rule.id == id) {
                return true;
            }
        }
        return false;
    }

    pub fn remove(self: *Rules, id: u32) bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.rules.items, 0..) |rule, i| {
            if (rule.id == id) {
                _ = self.rules.orderedRemove(i);
                return true;
            }
        }
        return false;
    }

    pub fn getById(self: *Rules, id: u32) ?*Rule {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.rules.items) |*rule| {
            if (rule.id == id) {
                return rule;
            }
        }
        return null;
    }

    pub fn enableRule(self: *Rules, id: u32) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.rules.items) |*rule| {
            if (rule.id == id) {
                rule.enabled = true;
                return;
            }
        }
    }

    pub fn disableRule(self: *Rules, id: u32) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.rules.items) |*rule| {
            if (rule.id == id) {
                rule.enabled = false;
                return;
            }
        }
    }

    pub fn clear(self: *Rules) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.rules.clearRetainingCapacity();
    }

    pub fn count(self: *const Rules) usize {
        return self.rules.items.len;
    }

    pub fn list(self: *const Rules) !void {
        const stdout = std.debug;

        if (self.rules.items.len == 0) {
            stdout.print("   No rules defined\n", .{});
            return;
        }

        for (self.rules.items) |rule| {
            stdout.print("   Rule ID: {}", .{rule.id});

            if (rule.name) |name| {
                stdout.print(" ({s})", .{name});
            }

            stdout.print(", enabled: {}", .{rule.enabled});

            if (rule.level_match) |lm| {
                stdout.print(", level: ", .{});
                switch (lm) {
                    .exact => |lev| stdout.print("{s}", .{lev.asString()}),
                    .min_priority => |min| stdout.print(">={}", .{min}),
                    .max_priority => |max| stdout.print("<={}", .{max}),
                    .priority_range => |range| stdout.print("{}-{}", .{ range.min, range.max }),
                    .custom_name => |name| stdout.print("custom:{s}", .{name}),
                    .any => stdout.print("any", .{}),
                }
            }

            stdout.print(", messages: {}\n", .{rule.messages.len});
        }
    }

    pub fn resetOnceFired(self: *Rules) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.rules.items) |*rule| {
            rule.resetFired();
        }
    }

    // Evaluation
    pub fn evaluate(self: *Rules, record: *const Record) ?[]const RuleMessage {
        if (!self.enabled) {
            _ = self.stats.evaluations_skipped.fetchAdd(1, .monotonic);
            return null;
        }

        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.rules.items.len == 0) return null;

        if (self.on_before_evaluate) |cb| {
            cb(record);
        }

        _ = self.stats.rules_evaluated.fetchAdd(1, .monotonic);

        var matched_messages: std.ArrayList(RuleMessage) = .empty;
        errdefer matched_messages.deinit(self.allocator);

        var matched_count: usize = 0;

        for (self.rules.items) |*rule| {
            const matched = rule.matches(record);

            if (self.on_rule_evaluated) |cb| {
                cb(rule, record, matched);
            }

            if (matched) {
                _ = self.stats.rules_matched.fetchAdd(1, .monotonic);
                matched_count += 1;

                if (self.on_rule_matched) |cb| {
                    cb(rule, record);
                }

                for (rule.messages) |msg| {
                    matched_messages.append(self.allocator, msg) catch continue;
                    _ = self.stats.messages_emitted.fetchAdd(1, .monotonic);
                }

                rule.markFired();
            }
        }

        if (self.on_after_evaluate) |cb| {
            cb(record, matched_count);
        }

        if (matched_messages.items.len == 0) {
            matched_messages.deinit(self.allocator);
            return null;
        }

        const result = matched_messages.toOwnedSlice(self.allocator) catch null;
        if (result) |msgs| {
            if (self.on_messages_attached) |cb| {
                cb(record, msgs.len);
            }
        }
        return result;
    }

    // Formatting
    pub fn formatMessages(self: *Rules, messages: []const RuleMessage, writer: anytype, use_color: bool) !void {
        const use_unicode = self.config.use_unicode;
        const enable_colors = use_color and self.config.enable_colors;

        for (messages) |msg| {
            try writer.writeAll("\n");

            if (enable_colors) {
                if (msg.use_background and msg.background_color != null) {
                    try writer.print("\x1b[{s};{s}m", .{ msg.getColor(), msg.background_color.? });
                } else {
                    try writer.print("\x1b[{s}m", .{msg.getColor()});
                }
            }

            try writer.writeAll(msg.getPrefix(use_unicode));
            try writer.writeAll(" ");

            if (msg.title) |title| {
                if (enable_colors) try writer.writeAll("\x1b[1m");
                try writer.writeAll(title);
                try writer.writeAll(": ");
                if (enable_colors) try writer.print("\x1b[0m\x1b[{s}m", .{msg.getColor()});
            }

            try writer.writeAll(msg.message);

            if (msg.url) |url| {
                try writer.writeAll(" (");
                if (enable_colors) try writer.writeAll("\x1b[4m");
                try writer.writeAll(url);
                if (enable_colors) try writer.print("\x1b[0m\x1b[{s}m", .{msg.getColor()});
                try writer.writeAll(")");
            }

            if (enable_colors) {
                try writer.writeAll("\x1b[0m");
            }
        }
    }

    pub fn formatMessagesJson(self: *Rules, messages: []const RuleMessage, writer: anytype, pretty: bool) !void {
        _ = self;
        const indent = if (pretty) "    " else "";
        const newline = if (pretty) "\n" else "";
        const sep = if (pretty) ": " else ":";

        try writer.writeAll("[");
        try writer.writeAll(newline);

        for (messages, 0..) |msg, i| {
            try writer.print("{s}{{", .{indent});
            try writer.writeAll(newline);

            try writer.print("{s}{s}\"category\"{s}\"", .{ indent, indent, sep });
            try writer.writeAll(@tagName(msg.category));
            try writer.writeAll("\"");

            if (msg.title) |title| {
                try writer.writeAll(",");
                try writer.writeAll(newline);
                try writer.print("{s}{s}\"title\"{s}\"", .{ indent, indent, sep });
                try escapeJsonString(writer, title);
                try writer.writeAll("\"");
            }

            try writer.writeAll(",");
            try writer.writeAll(newline);
            try writer.print("{s}{s}\"message\"{s}\"", .{ indent, indent, sep });
            try escapeJsonString(writer, msg.message);
            try writer.writeAll("\"");

            if (msg.url) |url| {
                try writer.writeAll(",");
                try writer.writeAll(newline);
                try writer.print("{s}{s}\"url\"{s}\"", .{ indent, indent, sep });
                try escapeJsonString(writer, url);
                try writer.writeAll("\"");
            }

            try writer.writeAll(newline);
            try writer.print("{s}}}", .{indent});

            if (i + 1 < messages.len) {
                try writer.writeAll(",");
            }
            try writer.writeAll(newline);
        }

        try writer.writeAll("]");
    }

    fn escapeJsonString(writer: anytype, s: []const u8) !void {
        for (s) |c| {
            switch (c) {
                '"' => try writer.writeAll("\\\""),
                '\\' => try writer.writeAll("\\\\"),
                '\n' => try writer.writeAll("\\n"),
                '\r' => try writer.writeAll("\\r"),
                '\t' => try writer.writeAll("\\t"),
                else => {
                    if (c < 0x20) {
                        try writer.print("\\u{x:0>4}", .{c});
                    } else {
                        try writer.writeByte(c);
                    }
                },
            }
        }
    }

    // Statistics
    pub fn getStats(self: *const Rules) RulesStats {
        return self.stats;
    }

    pub fn resetStats(self: *Rules) void {
        self.stats.reset();
    }

    // Aliases
    pub const on = enable;
    pub const off = disable;
    pub const activate = enable;
    pub const deactivate = disable;
    pub const start = enable;
    pub const stop = disable;
    pub const addRule = add;
    pub const removeRule = remove;
    pub const deleteRule = remove;
    pub const delete = remove;
    pub const activateRule = enableRule;
    pub const deactivateRule = disableRule;

    pub const Error = error{
        TooManyRules,
        OutOfMemory,
    };
};

/// Convenience builders for creating rule messages.
pub const RuleMessageBuilder = struct {
    pub fn cause(msg: []const u8) Rules.RuleMessage {
        return Rules.RuleMessage.cause(msg);
    }

    pub fn fix(msg: []const u8) Rules.RuleMessage {
        return Rules.RuleMessage.fix(msg);
    }

    pub fn suggest(msg: []const u8) Rules.RuleMessage {
        return Rules.RuleMessage.suggest(msg);
    }

    pub fn action(msg: []const u8) Rules.RuleMessage {
        return Rules.RuleMessage.action(msg);
    }

    pub fn docs(title: []const u8, url: []const u8) Rules.RuleMessage {
        return Rules.RuleMessage.docs(title, url);
    }

    pub fn report(title: []const u8, url: []const u8) Rules.RuleMessage {
        return Rules.RuleMessage.report(title, url);
    }

    pub fn note(msg: []const u8) Rules.RuleMessage {
        return Rules.RuleMessage.note(msg);
    }

    pub fn caution(msg: []const u8) Rules.RuleMessage {
        return Rules.RuleMessage.caution(msg);
    }

    pub fn perf(msg: []const u8) Rules.RuleMessage {
        return Rules.RuleMessage.perf(msg);
    }

    pub fn security(msg: []const u8) Rules.RuleMessage {
        return Rules.RuleMessage.security(msg);
    }

    pub fn custom(prefix_str: []const u8, msg: []const u8) Rules.RuleMessage {
        return Rules.RuleMessage.custom(prefix_str, msg);
    }
};

/// Convenience builders for level matching.
pub const LevelMatchBuilder = struct {
    pub fn exact(lev: Level) Rules.LevelMatch {
        return .{ .exact = lev };
    }

    pub fn errors() Rules.LevelMatch {
        return Rules.LevelMatch.errors();
    }

    pub fn warnings() Rules.LevelMatch {
        return Rules.LevelMatch.warnings();
    }

    pub fn all() Rules.LevelMatch {
        return Rules.LevelMatch.all();
    }

    pub fn minPriority(min: u8) Rules.LevelMatch {
        return .{ .min_priority = min };
    }

    pub fn maxPriority(max: u8) Rules.LevelMatch {
        return .{ .max_priority = max };
    }

    pub fn range(min: u8, max: u8) Rules.LevelMatch {
        return .{ .priority_range = .{ .min = min, .max = max } };
    }

    pub fn customLevel(name: []const u8) Rules.LevelMatch {
        return .{ .custom_name = name };
    }

    pub const err = exact;
    pub const warn = warnings;
    pub const info = exact;
};

// Tests
test "rules basic" {
    var rules = Rules.init(std.testing.allocator);
    defer rules.deinit();

    try std.testing.expect(!rules.enabled);
    try std.testing.expectEqual(@as(usize, 0), rules.count());
}

test "rules add and evaluate" {
    var rules = Rules.init(std.testing.allocator);
    defer rules.deinit();

    rules.enable();

    const messages = [_]Rules.RuleMessage{
        .{ .category = .error_analysis, .message = "Test diagnostic" },
        .{ .category = .solution_suggestion, .message = "Test help" },
    };

    try rules.add(.{
        .id = 0,
        .level_match = .{ .exact = .err },
        .messages = &messages,
    });

    var record = Record.init(std.testing.allocator, .err, "Test error");
    defer record.deinit();

    const result = rules.evaluate(&record);
    try std.testing.expect(result != null);
    if (result) |msgs| {
        defer std.testing.allocator.free(msgs);
        try std.testing.expectEqual(@as(usize, 2), msgs.len);
    }
}

test "rules once firing" {
    var rules = Rules.init(std.testing.allocator);
    defer rules.deinit();

    rules.enable();

    const messages = [_]Rules.RuleMessage{
        .{ .category = .general_information, .message = "This should fire once" },
    };

    try rules.add(.{
        .id = 0,
        .once = true,
        .level_match = .{ .exact = .info },
        .messages = &messages,
    });

    var record = Record.init(std.testing.allocator, .info, "Test");
    defer record.deinit();

    const result1 = rules.evaluate(&record);
    try std.testing.expect(result1 != null);
    if (result1) |msgs| {
        defer std.testing.allocator.free(msgs);
    }

    const result2 = rules.evaluate(&record);
    try std.testing.expect(result2 == null);
}

test "rules remove" {
    var rules = Rules.init(std.testing.allocator);
    defer rules.deinit();

    const messages = [_]Rules.RuleMessage{
        .{ .category = .error_analysis, .message = "Test" },
    };

    try rules.add(.{ .id = 1, .messages = &messages });
    try rules.add(.{ .id = 2, .messages = &messages });
    try rules.add(.{ .id = 3, .messages = &messages });

    try std.testing.expectEqual(@as(usize, 3), rules.count());

    const removed = rules.remove(2);
    try std.testing.expect(removed);
    try std.testing.expectEqual(@as(usize, 2), rules.count());

    const not_removed = rules.remove(999);
    try std.testing.expect(!not_removed);
}

test "rules enable disable" {
    var rules = Rules.init(std.testing.allocator);
    defer rules.deinit();

    rules.enable();
    try std.testing.expect(rules.isEnabled());

    rules.disable();
    try std.testing.expect(!rules.isEnabled());
}

test "rules clear" {
    var rules = Rules.init(std.testing.allocator);
    defer rules.deinit();

    const messages = [_]Rules.RuleMessage{
        .{ .category = .error_analysis, .message = "Test" },
    };

    try rules.add(.{ .id = 1, .messages = &messages });
    try rules.add(.{ .id = 2, .messages = &messages });

    try std.testing.expectEqual(@as(usize, 2), rules.count());

    rules.clear();
    try std.testing.expectEqual(@as(usize, 0), rules.count());
}

test "rules format messages" {
    var rules = Rules.init(std.testing.allocator);
    defer rules.deinit();

    const messages = [_]Rules.RuleMessage{
        .{ .category = .error_analysis, .message = "Test message" },
    };

    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(std.testing.allocator);

    try rules.formatMessages(&messages, buf.writer(std.testing.allocator), false);

    try std.testing.expect(buf.items.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "Test message") != null);
}

test "rules message builders" {
    const msg1 = Rules.RuleMessage.cause("Error occurred");
    try std.testing.expectEqual(Rules.MessageCategory.error_analysis, msg1.category);

    const msg2 = Rules.RuleMessage.fix("Apply this fix");
    try std.testing.expectEqual(Rules.MessageCategory.solution_suggestion, msg2.category);

    const msg3 = Rules.RuleMessage.docs("API Docs", "https://example.com");
    try std.testing.expect(msg3.url != null);
}

test "rules statistics" {
    var rules = Rules.init(std.testing.allocator);
    defer rules.deinit();

    rules.enable();

    const messages = [_]Rules.RuleMessage{
        .{ .category = .error_analysis, .message = "Test" },
    };

    try rules.add(.{
        .id = 1,
        .level_match = .{ .exact = .err },
        .messages = &messages,
    });

    var record = Record.init(std.testing.allocator, .err, "Test");
    defer record.deinit();

    const result = rules.evaluate(&record);
    if (result) |msgs| {
        defer std.testing.allocator.free(msgs);
    }

    const stats = rules.getStats();
    try std.testing.expect(stats.rules_evaluated.load(.monotonic) > 0);
    try std.testing.expect(stats.rules_matched.load(.monotonic) > 0);
}

test "rules json format" {
    var rules = Rules.init(std.testing.allocator);
    defer rules.deinit();

    const messages = [_]Rules.RuleMessage{
        .{ .category = .error_analysis, .message = "Test error" },
        .{ .category = .solution_suggestion, .message = "Fix it", .url = "https://example.com" },
    };

    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(std.testing.allocator);

    try rules.formatMessagesJson(&messages, buf.writer(std.testing.allocator), false);

    try std.testing.expect(buf.items.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "error_analysis") != null);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "solution_suggestion") != null);
}

test "rules duplicate id detection" {
    var rules = Rules.init(std.testing.allocator);
    defer rules.deinit();

    const messages = [_]Rules.RuleMessage{
        .{ .category = .error_analysis, .message = "Test" },
    };

    // Add first rule
    try rules.add(.{ .id = 1, .messages = &messages });
    try std.testing.expectEqual(@as(usize, 1), rules.count());

    // Try to add duplicate - should fail
    const result = rules.add(.{ .id = 1, .messages = &messages });
    try std.testing.expectError(error.RuleIdAlreadyExists, result);
    try std.testing.expectEqual(@as(usize, 1), rules.count());

    // Add different ID - should work
    try rules.add(.{ .id = 2, .messages = &messages });
    try std.testing.expectEqual(@as(usize, 2), rules.count());

    // Check hasRule
    try std.testing.expect(rules.hasRule(1));
    try std.testing.expect(rules.hasRule(2));
    try std.testing.expect(!rules.hasRule(3));
}

test "rules addOrUpdate" {
    var rules = Rules.init(std.testing.allocator);
    defer rules.deinit();

    const messages1 = [_]Rules.RuleMessage{
        .{ .category = .error_analysis, .message = "Original" },
    };

    const messages2 = [_]Rules.RuleMessage{
        .{ .category = .solution_suggestion, .message = "Updated" },
    };

    // Add first rule
    try rules.addOrUpdate(.{ .id = 1, .messages = &messages1 });
    try std.testing.expectEqual(@as(usize, 1), rules.count());

    // Update same ID - should update, not add
    try rules.addOrUpdate(.{ .id = 1, .messages = &messages2 });
    try std.testing.expectEqual(@as(usize, 1), rules.count());

    // Verify the rule was updated
    if (rules.getById(1)) |rule| {
        try std.testing.expectEqual(Rules.MessageCategory.solution_suggestion, rule.messages[0].category);
    }
}
