//! Log record filtering.
//!
//! Decides whether a record is logged based on level, content, module,
//! and custom rules. Combine rules with AND/OR/NOT logic.

const std = @import("std");
const Config = @import("config.zig").Config;
const Level = @import("level.zig").Level;
const Record = @import("record.zig").Record;
const SinkConfig = @import("sink.zig").SinkConfig;
const Constants = @import("constants.zig");
const Utils = @import("utils.zig");
const Color = @import("color.zig");

/// Rate bucket for tracking message rates per module.
pub const RateBucket = struct {
    tokens: f64,
    lastRefillMs: i64,
};

/// Filter for conditionally processing log records.
pub const Filter = struct {
    /// Filter statistics for monitoring and diagnostics.
    pub const FilterStats = struct {
        totalRecordsEvaluated: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        recordsAllowed: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        recordsDenied: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        rulesAdded: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        evaluationErrors: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),

        /// Calculate allow rate (0.0 - 1.0)
        pub fn allowRate(self: *const FilterStats) f64 {
            return Utils.calculateRate(
                Utils.atomicLoadU64(&self.recordsAllowed),
                Utils.atomicLoadU64(&self.totalRecordsEvaluated),
            );
        }

        /// Calculate deny rate (0.0 - 1.0)
        pub fn denyRate(self: *const FilterStats) f64 {
            return Utils.calculateRate(
                Utils.atomicLoadU64(&self.recordsDenied),
                Utils.atomicLoadU64(&self.totalRecordsEvaluated),
            );
        }

        /// Calculate error rate (0.0 - 1.0)
        pub fn errorRate(self: *const FilterStats) f64 {
            return Utils.calculateErrorRate(
                Utils.atomicLoadU64(&self.evaluationErrors),
                Utils.atomicLoadU64(&self.totalRecordsEvaluated),
            );
        }

        /// Returns true if any records have been denied.
        pub fn hasDenied(self: *const FilterStats) bool {
            return self.recordsDenied.load(.monotonic) > 0;
        }

        /// Returns true if any evaluation errors occurred.
        pub fn hasEvaluationErrors(self: *const FilterStats) bool {
            return self.evaluationErrors.load(.monotonic) > 0;
        }

        /// Returns total records evaluated as u64.
        pub fn getTotal(self: *const FilterStats) u64 {
            return Utils.atomicLoadU64(&self.totalRecordsEvaluated);
        }

        /// Returns allowed records count as u64.
        pub fn getAllowed(self: *const FilterStats) u64 {
            return Utils.atomicLoadU64(&self.recordsAllowed);
        }

        /// Returns denied records count as u64.
        pub fn getDenied(self: *const FilterStats) u64 {
            return Utils.atomicLoadU64(&self.recordsDenied);
        }

        /// Returns rules added count as u64.
        pub fn getRulesAdded(self: *const FilterStats) u64 {
            return Utils.atomicLoadU64(&self.rulesAdded);
        }

        /// Calculate throughput records per second.
        pub fn throughput(self: *const FilterStats, elapsedMs: i64) f64 {
            return Utils.calculateRecordsPerSecond(self.getTotal(), elapsedMs);
        }

        /// Reset all statistics to zero.
        pub fn reset(self: *FilterStats) void {
            self.totalRecordsEvaluated.store(0, .monotonic);
            self.recordsAllowed.store(0, .monotonic);
            self.recordsDenied.store(0, .monotonic);
            self.rulesAdded.store(0, .monotonic);
            self.evaluationErrors.store(0, .monotonic);
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
        notAll,
    };

    allocator: std.mem.Allocator,
    rules: std.ArrayList(FilterRule),
    stats: FilterStats = .{},
    mutex: std.Io.Mutex = std.Io.Mutex.init,
    mode: Mode = .all,
    enabled: bool = true,
    rateBuckets: std.StringHashMap(RateBucket) = undefined,
    rng: ?std.Random.DefaultPrng = null,
    everyNCounter: u64 = 0,

    /// Callback invoked when a record passes filtering.
    onRecordAllowed: ?*const fn (*const Record, u32) void = null,

    /// Callback invoked when a record is denied by filter.
    onRecordDenied: ?*const fn (*const Record, u32) void = null,

    /// Callback invoked when filter is created.
    onFilterCreated: ?*const fn (*const FilterStats) void = null,

    /// Callback invoked when a rule is added.
    onRuleAdded: ?*const fn (u32, u32) void = null,

    /// A single filter rule that determines whether a record should pass.
    ///
    /// Filter rules are evaluated in order and can allow or deny records
    /// based on level, module, message content, or custom criteria.
    pub const FilterRule = struct {
        /// The type of rule to apply (level, module, message, etc.).
        ruleType: RuleType,
        /// Pattern to match against (for module/message rules).
        pattern: ?[]const u8 = null,
        /// Log level for level-based rules.
        level: ?Level = null,
        /// Action to take when rule matches (allow or deny).
        action: Action = .allow,
        /// Specific key for context-based filtering.
        contextKey: ?[]const u8 = null,
        /// User-defined predicate function for complex filtering.
        predicate: ?*const fn (*const Record) bool = null,
        /// Time-window start hour (0-23).
        timeStart: ?u8 = null,
        /// Time-window end hour (0-23).
        timeEnd: ?u8 = null,
        /// Rate limit (messages per second).
        rateLimit: ?u32 = null,
        /// Sampling probability.
        probability: ?f64 = null,
        /// Sampling every N.
        everyN: ?u32 = null,

        /// Types of filter rules available.
        pub const RuleType = enum {
            /// Only allow records at or above minimum level.
            levelMin,
            /// Only allow records at or below maximum level.
            levelMax,
            /// Only allow records at exact level.
            levelExact,
            /// Match records from specific module name.
            moduleMatch,
            /// Match records from modules starting with prefix.
            modulePrefix,
            /// Match records using regex for module name.
            moduleRegex,
            /// Match records containing specified text.
            messageContains,
            /// Match records using regex pattern.
            messageRegex,
            /// Match records by source file name.
            sourceFileMatch,
            /// Match records by source file regex.
            sourceFileRegex,
            /// Match records by function name.
            functionMatch,
            /// Match records by function regex.
            functionRegex,
            /// Match records by trace ID.
            traceIdMatch,
            /// Match records by span ID.
            spanIdMatch,
            /// Match records having specific context key.
            contextHasKey,
            /// Match records with specific context value.
            contextValueMatch,
            /// Match records with nested context path (e.g. "user.id").
            contextPathMatch,

            /// Match records by thread ID.
            threadIdMatch,
            /// Match records that contain error information.
            hasError,
            /// Custom predicate-based filtering.
            custom,
            /// Time-window filter.
            timeWindow,
            /// Rate-based filter (token bucket).
            rateLimit,
            /// Glob pattern match for module names.
            globMatch,
            /// Sampling probability.
            samplingProbability,
            /// Sampling every N.
            samplingEveryN,
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
    pub fn init(allocator: std.mem.Allocator) Filter {
        return .{
            .allocator = allocator,
            .rules = .empty,
            .rateBuckets = std.StringHashMap(RateBucket).init(allocator),
        };
    }

    /// Sets the logical mode used when combining filter rules.
    pub fn setMode(self: *Filter, mode: Mode) void {
        self.mode = mode;
    }

    /// Returns true when the filter is currently using the requested mode.
    pub fn isMode(self: *const Filter, mode: Mode) bool {
        return self.mode == mode;
    }

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
            if (rule.contextKey) |k| {
                self.allocator.free(k);
            }
        }
        self.rules.deinit(self.allocator);

        var it = self.rateBuckets.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.rateBuckets.deinit();
    }

    /// Adds a new filter rule.
    pub fn addRule(self: *Filter, rule: FilterRule) !void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());

        // Deep copy patterns and keys if present
        var newRule = rule;
        if (rule.pattern) |p| {
            newRule.pattern = try self.allocator.dupe(u8, p);
        }
        if (rule.contextKey) |k| {
            newRule.contextKey = try self.allocator.dupe(u8, k);
        }

        try self.rules.append(self.allocator, newRule);
        _ = self.stats.rulesAdded.fetchAdd(1, .monotonic);

        if (self.onRuleAdded) |cb| {
            cb(@backingInt(rule.ruleType), @intCast(self.rules.items.len));
        }
    }

    /// Sets the callback for record allowed events.
    pub fn setAllowedCallback(self: *Filter, callback: *const fn (*const Record, u32) void) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        self.onRecordAllowed = callback;
    }

    /// Sets the callback for record denied events.
    pub fn setDeniedCallback(self: *Filter, callback: *const fn (*const Record, u32) void) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        self.onRecordDenied = callback;
    }

    /// Sets the callback for filter creation.
    pub fn setCreatedCallback(self: *Filter, callback: *const fn (*const FilterStats) void) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        self.onFilterCreated = callback;
    }

    /// Sets the callback for rule addition.
    pub fn setRuleAddedCallback(self: *Filter, callback: *const fn (u32, u32) void) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        self.onRuleAdded = callback;
    }

    /// Returns filter statistics.
    pub fn getStats(self: *Filter) FilterStats {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());

        return self.stats;
    }

    /// Adds a minimum level filter rule.
    ///
    /// Records with a level below the minimum will be filtered out.
    ///
    /// Complexity: O(1) (Amortized append)
    pub fn addMinLevel(self: *Filter, level: Level) !void {
        try self.rules.append(self.allocator, .{
            .ruleType = .levelMin,
            .level = level,
            .action = .allow,
        });
    }

    /// Adds a maximum level filter rule.
    ///
    /// Records with a level above the maximum will be filtered out.
    ///
    /// Complexity: O(1) (Amortized append)
    pub fn addMaxLevel(self: *Filter, level: Level) !void {
        try self.rules.append(self.allocator, .{
            .ruleType = .levelMax,
            .level = level,
            .action = .allow,
        });
    }

    /// Adds a module prefix filter rule.
    ///
    /// Only records from modules matching the prefix will be allowed.
    ///
    /// Complexity: O(M) where M is prefix length.
    pub fn addModulePrefix(self: *Filter, prefix: []const u8) !void {
        const ownedPrefix = try self.allocator.dupe(u8, prefix);
        try self.rules.append(self.allocator, .{
            .ruleType = .modulePrefix,
            .pattern = ownedPrefix,
            .action = .allow,
        });
    }

    /// Adds a message content filter rule.
    ///
    /// Records containing the specified substring will be filtered according to `action`.
    ///
    /// Complexity: O(S) where S is substring length.
    pub fn addMessageFilter(self: *Filter, substring: []const u8, action: FilterRule.Action) !void {
        const ownedSubstring = try self.allocator.dupe(u8, substring);
        try self.rules.append(self.allocator, .{
            .ruleType = .messageContains,
            .pattern = ownedSubstring,
            .action = action,
        });
    }

    /// Evaluates whether a record should be processed based on configured rules.
    ///
    /// Complexity: O(N * M) where N is rules and M is message/module length.
    pub fn shouldLog(self: *const Filter, record: *const Record) bool {
        if (!self.enabled) return true;
        if (self.rules.items.len == 0) return true;

        _ = @constCast(&self.stats.totalRecordsEvaluated).fetchAdd(1, .monotonic);

        const result = switch (self.mode) {
            .all => self.evaluateAll(record),
            .any => self.evaluateAny(record),
            .none => !self.evaluateAny(record),
            .notAll => !self.evaluateAll(record),
        };

        if (result) {
            _ = @constCast(&self.stats.recordsAllowed).fetchAdd(1, .monotonic);
        } else {
            _ = @constCast(&self.stats.recordsDenied).fetchAdd(1, .monotonic);
        }

        return result;
    }

    /// Cheap pre-filter evaluated before redaction and record allocation.
    ///
    /// Returns true only when the full evaluation is certain to deny the
    /// record. Only applies in `.all` mode to rules that need nothing more
    /// than level, module, and message. Any other mode or rule type
    /// abstains (returns false) and the full filter still runs later.
    /// Lock-free like the rest of the data plane: configure rules before
    /// logging, do not mutate them concurrently with logging.
    pub fn preFilterRejects(
        self: *const Filter,
        level: Level,
        module: ?[]const u8,
        message: []const u8,
    ) bool {
        if (!self.enabled) return false;
        if (self.rules.items.len == 0) return false;
        if (self.mode != .all) return false;

        for (self.rules.items) |rule| {
            const matches: ?bool = switch (rule.ruleType) {
                .levelMin => if (rule.level) |l| level.priority() >= l.priority() else null,
                .levelMax => if (rule.level) |l| level.priority() <= l.priority() else null,
                .levelExact => if (rule.level) |l| level == l else null,
                .moduleMatch => if (rule.pattern) |p| if (module) |m| std.mem.eql(u8, m, p) else false else null,
                .modulePrefix => if (rule.pattern) |p| if (module) |m| std.mem.startsWith(u8, m, p) else false else null,
                .messageContains => if (rule.pattern) |p| std.mem.indexOf(u8, message, p) != null else null,
                else => null,
            };
            const m = matches orelse continue;
            const passed = if (rule.action == .allow) m else !m;
            if (!passed) return true;
        }
        return false;
    }

    fn evaluateAll(self: *const Filter, record: *const Record) bool {
        for (self.rules.items, 0..) |rule, i| {
            const matches = self.checkRule(rule, record);
            const passed = if (rule.action == .allow) matches else !matches;

            if (!passed) {
                if (self.onRecordDenied) |cb| cb(record, @intCast(i));
                return false;
            }
        }
        if (self.onRecordAllowed) |cb| cb(record, @intCast(self.rules.items.len));
        return true;
    }

    fn evaluateAny(self: *const Filter, record: *const Record) bool {
        for (self.rules.items, 0..) |rule, i| {
            const matches = self.checkRule(rule, record);
            const passed = if (rule.action == .allow) matches else !matches;

            if (passed) {
                if (self.onRecordAllowed) |cb| cb(record, @intCast(i + 1));
                return true;
            }
        }
        if (self.onRecordDenied) |cb| cb(record, 0);
        return false;
    }

    fn checkRule(self: *const Filter, rule: FilterRule, record: *const Record) bool {
        return switch (rule.ruleType) {
            .levelMin => if (rule.level) |l| record.level.priority() >= l.priority() else true,
            .levelMax => if (rule.level) |l| record.level.priority() <= l.priority() else true,
            .levelExact => if (rule.level) |l| record.level == l else true,

            .moduleMatch => if (rule.pattern) |p| if (record.module) |m| std.mem.eql(u8, m, p) else false else true,
            .modulePrefix => if (rule.pattern) |p| if (record.module) |m| std.mem.startsWith(u8, m, p) else false else true,
            .moduleRegex => if (rule.pattern) |p| (if (record.module) |m| Utils.findRegexPattern(m, p) != null else false) else true,

            .messageContains => if (rule.pattern) |p| std.mem.indexOf(u8, record.message, p) != null else true,
            .messageRegex => if (rule.pattern) |p| Utils.findRegexPattern(record.message, p) != null else true,

            .sourceFileMatch => if (rule.pattern) |p| if (record.filename) |f| std.mem.eql(u8, f, p) else false else true,
            .sourceFileRegex => if (rule.pattern) |p| (if (record.filename) |f| Utils.findRegexPattern(f, p) != null else false) else true,

            .functionMatch => if (rule.pattern) |p| if (record.function) |f| std.mem.eql(u8, f, p) else false else true,
            .functionRegex => if (rule.pattern) |p| (if (record.function) |f| Utils.findRegexPattern(f, p) != null else false) else true,

            .traceIdMatch => if (rule.pattern) |p| if (record.traceId) |tid| std.mem.eql(u8, tid, p) else false else true,
            .spanIdMatch => if (rule.pattern) |p| if (record.spanId) |sid| std.mem.eql(u8, sid, p) else false else true,

            .threadIdMatch => if (rule.pattern) |p| if (record.threadId) |tid| blk: {
                var buf: [Constants.BufferSizes.tiny]u8 = undefined;
                const tidStr = std.fmt.bufPrint(&buf, "{d}", .{tid}) catch "";
                break :blk std.mem.eql(u8, tidStr, p);
            } else false else true,

            .contextHasKey => if (rule.contextKey) |k| record.context.contains(k) else false,
            .contextValueMatch => if (rule.contextKey) |k| if (rule.pattern) |p| if (record.context.get(k)) |v| blk: {
                var buf: [Constants.BufferSizes.small]u8 = undefined;
                const vStr = switch (v) {
                    .string => |s| s,
                    .integer => |i| std.fmt.bufPrint(&buf, "{d}", .{i}) catch "",
                    .float => |f| std.fmt.bufPrint(&buf, "{d}", .{f}) catch "",
                    .bool => |b| if (b) "true" else "false",
                    else => "",
                };
                if (Utils.findRegexPattern(vStr, p) != null) break :blk true;
                break :blk false;
            } else false else false else false,

            .contextPathMatch => if (rule.contextKey) |k| if (rule.pattern) |p| if (getNestedContextValue(&record.context, k)) |v| blk: {
                var buf: [Constants.BufferSizes.small]u8 = undefined;
                const vStr = switch (v) {
                    .string => |s| s,
                    .integer => |i| std.fmt.bufPrint(&buf, "{d}", .{i}) catch "",
                    .float => |f| std.fmt.bufPrint(&buf, "{d}", .{f}) catch "",
                    .bool => |b| if (b) "true" else "false",
                    else => "",
                };
                if (Utils.findRegexPattern(vStr, p) != null) break :blk true;
                break :blk false;
            } else false else false else false,

            .hasError => record.errorInfo != null,

            .custom => if (rule.predicate) |pred| pred(record) else true,

            .timeWindow => if (rule.timeStart) |start| if (rule.timeEnd) |end| blk: {
                const localTime = Utils.fromMilliTimestampLocal(record.timestamp);
                const hour = @as(u8, @intCast(localTime.hour));
                if (start <= end) {
                    break :blk (hour >= start and hour < end);
                } else {
                    break :blk (hour >= start or hour < end);
                }
            } else false else false,

            .rateLimit => if (rule.rateLimit) |limit| blk: {
                const mutableSelf = @constCast(self);
                mutableSelf.mutex.lockUncancelable(Utils.io());
                defer mutableSelf.mutex.unlock(Utils.io());

                const moduleName = record.module orelse "unknown";
                const now = Utils.currentMillis();

                const gpr = mutableSelf.rateBuckets.getOrPut(moduleName) catch {
                    break :blk false;
                };
                if (!gpr.found_existing) {
                    const ownedKey = mutableSelf.allocator.dupe(u8, moduleName) catch {
                        break :blk false;
                    };
                    gpr.key_ptr.* = ownedKey;
                    gpr.value_ptr.* = .{
                        .tokens = @floatFromInt(limit),
                        .lastRefillMs = now,
                    };
                }

                const bucket = gpr.value_ptr;
                const elapsed = now - bucket.lastRefillMs;
                const refillInterval = @as(f64, @floatFromInt(elapsed)) / 1000.0;
                bucket.tokens = @min(@as(f64, @floatFromInt(limit)), bucket.tokens + refillInterval * @as(f64, @floatFromInt(limit)));
                bucket.lastRefillMs = now;

                if (bucket.tokens >= 1.0) {
                    bucket.tokens -= 1.0;
                    break :blk true;
                } else {
                    break :blk false;
                }
            } else false,

            .globMatch => if (rule.pattern) |p| if (record.module) |m| matchGlob(m, p) else false else true,

            .samplingProbability => if (rule.probability) |prob| blk: {
                const mutableSelf = @constCast(self);
                mutableSelf.mutex.lockUncancelable(Utils.io());
                defer mutableSelf.mutex.unlock(Utils.io());

                if (mutableSelf.rng == null) {
                    mutableSelf.rng = std.Random.DefaultPrng.init(@as(u64, @intCast(Utils.currentMillis())));
                }
                break :blk mutableSelf.rng.?.random().float(f64) < prob;
            } else true,

            .samplingEveryN => if (rule.everyN) |n| blk: {
                if (n == 0) break :blk true;
                const mutableSelf = @constCast(self);
                mutableSelf.mutex.lockUncancelable(Utils.io());
                defer mutableSelf.mutex.unlock(Utils.io());

                mutableSelf.everyNCounter += 1;
                break :blk (mutableSelf.everyNCounter % n) == 0;
            } else true,
        };
    }

    /// Clears all filter rules.
    ///
    /// Takes the filter lock: rules must not be mutated concurrently with
    /// evaluation. Frees both pattern and context-key allocations (deinit
    /// parity — previously context keys leaked here).
    pub fn clear(self: *Filter) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        for (self.rules.items) |rule| {
            if (rule.pattern) |p| {
                self.allocator.free(p);
            }
            if (rule.contextKey) |k| {
                self.allocator.free(k);
            }
        }
        self.rules.clearRetainingCapacity();
    }

    /// Adds a filter for custom levels by priority.
    /// Only records with custom level priority >= min_priority will pass.
    pub fn addMinPriority(self: *Filter, minPriority: u8) !void {
        try self.rules.append(self.allocator, .{
            .ruleType = .levelMin,
            .level = Level.fromPriority(minPriority) orelse .info,
            .action = .allow,
        });
    }

    /// Adds a filter for custom levels by priority range.
    pub fn addPriorityRange(self: *Filter, minPriority: u8, maxPriority: u8) !void {
        try self.addMinPriority(minPriority);
        try self.rules.append(self.allocator, .{
            .ruleType = .levelMax,
            .level = Level.fromPriority(maxPriority) orelse .critical,
            .action = .allow,
        });
    }

    /// Explicitly allow a module.
    pub fn allowModule(self: *Filter, module: []const u8) !void {
        try self.addRule(.{
            .ruleType = .moduleMatch,
            .pattern = module,
            .action = .allow,
        });
    }

    /// Explicitly deny a module.
    pub fn denyModule(self: *Filter, module: []const u8) !void {
        try self.addRule(.{
            .ruleType = .moduleMatch,
            .pattern = module,
            .action = .deny,
        });
    }

    /// Allow modules starting with prefix.
    pub fn allowPrefix(self: *Filter, prefix: []const u8) !void {
        try self.addRule(.{
            .ruleType = .modulePrefix,
            .pattern = prefix,
            .action = .allow,
        });
    }

    /// Deny modules starting with prefix.
    pub fn denyPrefix(self: *Filter, prefix: []const u8) !void {
        try self.addRule(.{
            .ruleType = .modulePrefix,
            .pattern = prefix,
            .action = .deny,
        });
    }

    /// Allow messages matching regex.
    pub fn allowRegex(self: *Filter, regex: []const u8) !void {
        try self.addRule(.{
            .ruleType = .messageRegex,
            .pattern = regex,
            .action = .allow,
        });
    }

    /// Deny messages matching regex.
    pub fn denyRegex(self: *Filter, regex: []const u8) !void {
        try self.addRule(.{
            .ruleType = .messageRegex,
            .pattern = regex,
            .action = .deny,
        });
    }

    /// Add a custom predicate rule.
    pub fn addCustom(self: *Filter, predicate: *const fn (*const Record) bool, action: FilterRule.Action) !void {
        try self.addRule(.{
            .ruleType = .custom,
            .predicate = predicate,
            .action = action,
        });
    }

    /// Add a context value match rule.
    pub fn addContextMatch(self: *Filter, key: []const u8, pattern: []const u8, action: FilterRule.Action) !void {
        try self.addRule(.{
            .ruleType = .contextValueMatch,
            .contextKey = key,
            .pattern = pattern,
            .action = action,
        });
    }

    /// Add a nested context path match rule.
    pub fn addContextPathMatch(self: *Filter, key: []const u8, pattern: []const u8, action: FilterRule.Action) !void {
        try self.addRule(.{
            .ruleType = .contextPathMatch,
            .contextKey = key,
            .pattern = pattern,
            .action = action,
        });
    }

    /// Only allow records with errors.
    pub fn addErrorOnly(self: *Filter) !void {
        try self.addRule(.{
            .ruleType = .hasError,
            .action = .allow,
        });
    }

    /// Returns the number of filter rules.
    pub fn count(self: *const Filter) usize {
        return self.rules.items.len;
    }

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

        if (config.sampling.enabled) {
            switch (config.sampling.strategy) {
                .none => {},
                .probability => |prob| {
                    try filter.addRule(.{
                        .ruleType = .samplingProbability,
                        .probability = prob,
                        .action = .allow,
                    });
                },
                .rateLimit => |rl| {
                    try filter.addRule(.{
                        .ruleType = .rateLimit,
                        .rateLimit = rl.maxRecords,
                        .action = .allow,
                    });
                },
                .everyN => |n| {
                    try filter.addRule(.{
                        .ruleType = .samplingEveryN,
                        .everyN = n,
                        .action = .allow,
                    });
                },
                .adaptive => |ad| {
                    try filter.addRule(.{
                        .ruleType = .rateLimit,
                        .rateLimit = ad.targetRate,
                        .action = .allow,
                    });
                },
            }
        }

        if (config.redaction.enabled) {
            if (config.redaction.patterns) |patterns| {
                for (patterns) |pattern| {
                    try filter.addRule(.{
                        .ruleType = .messageRegex,
                        .pattern = pattern,
                        .action = .deny,
                    });
                }
            }
        }

        return filter;
    }

    /// Applies `action` only between `startHour` and `endHour` (0-23).
    pub fn addTimeWindowRule(self: *Filter, startHour: u8, endHour: u8, action: FilterRule.Action) !void {
        try self.addRule(.{
            .ruleType = .timeWindow,
            .timeStart = startHour,
            .timeEnd = endHour,
            .action = action,
        });
    }

    /// Limits the logger to `ratePerSecond` records per second.
    pub fn addRateRule(self: *Filter, ratePerSecond: u32, action: FilterRule.Action) !void {
        try self.addRule(.{
            .ruleType = .rateLimit,
            .rateLimit = ratePerSecond,
            .action = action,
        });
    }

    /// Matches module names against a glob `pattern`.
    pub fn addGlobModule(self: *Filter, pattern: []const u8, action: FilterRule.Action) !void {
        try self.addRule(.{
            .ruleType = .globMatch,
            .pattern = pattern,
            .action = action,
        });
    }

    /// Outcome of a filter evaluation, with a reason on rejection.
    pub const FilterResult = struct {
        allowed: bool,
        reason: []const u8,
    };

    /// Static denial reason for a rule type (shared by batch and hot paths).
    fn denyReasonFor(ruleType: FilterRule.RuleType) []const u8 {
        return switch (ruleType) {
            .levelMin => "denied: below minimum level",
            .levelMax => "denied: above maximum level",
            .levelExact => "denied: level mismatch",
            .moduleMatch => "denied: module match",
            .modulePrefix => "denied: module prefix",
            .moduleRegex => "denied: module regex",
            .messageContains => "denied: message contains",
            .messageRegex => "denied: message regex",
            .sourceFileMatch => "denied: source file match",
            .sourceFileRegex => "denied: source file regex",
            .functionMatch => "denied: function match",
            .functionRegex => "denied: function regex",
            .traceIdMatch => "denied: trace id mismatch",
            .spanIdMatch => "denied: span id mismatch",
            .threadIdMatch => "denied: thread id mismatch",
            .contextHasKey => "denied: context has key",
            .contextValueMatch => "denied: context value mismatch",
            .contextPathMatch => "denied: context path mismatch",
            .hasError => "denied: does not have error",
            .custom => "denied: custom rule",
            .timeWindow => "denied: outside time window",
            .rateLimit => "denied: rate limit exceeded",
            .globMatch => "denied: glob mismatch",
            .samplingProbability => "denied: sampling probability drop",
            .samplingEveryN => "denied: sampling every_n drop",
        };
    }

    /// Evaluates a record, returning the decision plus a static reason string.
    ///
    /// The hot-path equivalent of filterBatch for a single record, without
    /// allocation. Reasons are static literals valid for the program lifetime.
    /// Fires onRecordAllowed/onRecordDenied exactly as evaluateAll and
    /// evaluateAny do, so switching callers over changes no observable stats.
    pub fn shouldLogWithReason(self: *const Filter, record: *const Record) FilterResult {
        if (!self.enabled) return .{ .allowed = true, .reason = "allowed: filter disabled" };
        if (self.rules.items.len == 0) return .{ .allowed = true, .reason = "allowed by default" };

        _ = @constCast(&self.stats.totalRecordsEvaluated).fetchAdd(1, .monotonic);

        const result: FilterResult = switch (self.mode) {
            .all => blk: {
                for (self.rules.items, 0..) |rule, i| {
                    const matches = self.checkRule(rule, record);
                    const passed = if (rule.action == .allow) matches else !matches;
                    if (!passed) {
                        if (self.onRecordDenied) |cb| cb(record, @intCast(i));
                        break :blk .{ .allowed = false, .reason = denyReasonFor(rule.ruleType) };
                    }
                }
                if (self.onRecordAllowed) |cb| cb(record, @intCast(self.rules.items.len));
                break :blk .{ .allowed = true, .reason = "allowed by all rules" };
            },
            .any => blk: {
                for (self.rules.items, 0..) |rule, i| {
                    const matches = self.checkRule(rule, record);
                    const passed = if (rule.action == .allow) matches else !matches;
                    if (passed) {
                        if (self.onRecordAllowed) |cb| cb(record, @intCast(i + 1));
                        break :blk .{ .allowed = true, .reason = "allowed: rule matched" };
                    }
                }
                if (self.onRecordDenied) |cb| cb(record, 0);
                break :blk .{ .allowed = false, .reason = "denied: no rules matched" };
            },
            .none => blk: {
                // Matches shouldLog(.none) = !evaluateAny: inner any-style
                // callbacks fire, then the decision is negated.
                var innerPassed = false;
                for (self.rules.items, 0..) |rule, i| {
                    const matches = self.checkRule(rule, record);
                    const passed = if (rule.action == .allow) matches else !matches;
                    if (passed) {
                        if (self.onRecordAllowed) |cb| cb(record, @intCast(i + 1));
                        innerPassed = true;
                        break;
                    }
                }
                if (!innerPassed) {
                    if (self.onRecordDenied) |cb| cb(record, 0);
                    break :blk .{ .allowed = true, .reason = "allowed: no rules matched" };
                }
                break :blk .{ .allowed = false, .reason = "denied: rule matched in none mode" };
            },
            .notAll => blk: {
                // Matches shouldLog(.notAll) = !evaluateAll: inner all-style
                // callbacks fire, then the decision is negated.
                var failed = false;
                for (self.rules.items, 0..) |rule, i| {
                    const matches = self.checkRule(rule, record);
                    const passed = if (rule.action == .allow) matches else !matches;
                    if (!passed) {
                        if (self.onRecordDenied) |cb| cb(record, @intCast(i));
                        failed = true;
                        break;
                    }
                }
                if (!failed) {
                    if (self.onRecordAllowed) |cb| cb(record, @intCast(self.rules.items.len));
                    break :blk .{ .allowed = false, .reason = "denied: all rules matched in not_all mode" };
                }
                break :blk .{ .allowed = true, .reason = "allowed: rule failed in not_all mode" };
            },
        };

        if (result.allowed) {
            _ = @constCast(&self.stats.recordsAllowed).fetchAdd(1, .monotonic);
        } else {
            _ = @constCast(&self.stats.recordsDenied).fetchAdd(1, .monotonic);
        }

        return result;
    }

    /// Evaluates many records, writing one boolean per record into `results`.
    pub fn filterBatch(self: *const Filter, records: []const *const Record, results: []FilterResult) void {
        // Hard guard, not just an assert: asserts vanish in ReleaseFast,
        // where a length mismatch would become an out-of-bounds access.
        if (records.len != results.len) return;
        for (records, 0..) |record, i| {
            var allowed = true;
            var reason: []const u8 = "allowed by default";

            if (self.enabled and self.rules.items.len > 0) {
                switch (self.mode) {
                    .all => {
                        for (self.rules.items, 0..) |rule, ruleIdx| {
                            const matches = self.checkRule(rule, record);
                            const passed = if (rule.action == .allow) matches else !matches;
                            if (!passed) {
                                allowed = false;
                                reason = switch (rule.ruleType) {
                                    .levelMin => "denied: below minimum level",
                                    .levelMax => "denied: above maximum level",
                                    .levelExact => "denied: level mismatch",
                                    .moduleMatch => "denied: module match",
                                    .modulePrefix => "denied: module prefix",
                                    .moduleRegex => "denied: module regex",
                                    .messageContains => "denied: message contains",
                                    .messageRegex => "denied: message regex",
                                    .sourceFileMatch => "denied: source file match",
                                    .sourceFileRegex => "denied: source file regex",
                                    .functionMatch => "denied: function match",
                                    .functionRegex => "denied: function regex",
                                    .traceIdMatch => "denied: trace id mismatch",
                                    .spanIdMatch => "denied: span id mismatch",
                                    .threadIdMatch => "denied: thread id mismatch",
                                    .contextHasKey => "denied: context has key",
                                    .contextValueMatch => "denied: context value mismatch",
                                    .contextPathMatch => "denied: context path mismatch",
                                    .hasError => "denied: does not have error",
                                    .custom => "denied: custom rule",
                                    .timeWindow => "denied: outside time window",
                                    .rateLimit => "denied: rate limit exceeded",
                                    .globMatch => "denied: glob mismatch",
                                    .samplingProbability => "denied: sampling probability drop",
                                    .samplingEveryN => "denied: sampling every_n drop",
                                };
                                _ = ruleIdx;
                                break;
                            }
                        }
                        if (allowed) {
                            reason = "allowed by all rules";
                        }
                    },
                    .any => {
                        allowed = false;
                        reason = "denied: no rules matched";
                        for (self.rules.items) |rule| {
                            const matches = self.checkRule(rule, record);
                            const passed = if (rule.action == .allow) matches else !matches;
                            if (passed) {
                                allowed = true;
                                reason = "allowed: rule matched";
                                break;
                            }
                        }
                    },
                    .none => {
                        allowed = true;
                        reason = "allowed: no rules matched";
                        for (self.rules.items) |rule| {
                            const matches = self.checkRule(rule, record);
                            const passed = if (rule.action == .allow) matches else !matches;
                            if (passed) {
                                allowed = false;
                                reason = "denied: rule matched in none mode";
                                break;
                            }
                        }
                    },
                    .notAll => {
                        allowed = false;
                        reason = "denied: all rules matched in not_all mode";
                        for (self.rules.items) |rule| {
                            const matches = self.checkRule(rule, record);
                            const passed = if (rule.action == .allow) matches else !matches;
                            if (!passed) {
                                allowed = true;
                                reason = "allowed: rule failed in not_all mode";
                                break;
                            }
                        }
                    },
                }
            }
            results[i] = .{ .allowed = allowed, .reason = reason };
        }
    }

    /// Batch filter evaluation - returns array of booleans for each record.
    /// More efficient for processing multiple records at once.
    pub fn shouldLogBatch(self: *Filter, records: []const *const Record, results: []bool) void {
        if (records.len != results.len) return;
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
    pub fn createFilteredSink(filePath: []const u8, minLevel: Level) SinkConfig {
        return SinkConfig{
            .path = filePath,
            .level = minLevel,
            .color = false,
        };
    }
};

/// Composite filter for chaining multiple filters with AND/OR/none/not_all semantics.
pub const CompositeFilter = struct {
    allocator: std.mem.Allocator,
    filters: std.ArrayList(*const Filter),
    mode: Filter.Mode = .all,

    /// Creates an empty composite filter.
    pub fn init(allocator: std.mem.Allocator) CompositeFilter {
        return .{
            .allocator = allocator,
            .filters = .empty,
        };
    }

    /// Releases the composite filter and its rules.
    pub fn deinit(self: *CompositeFilter) void {
        self.filters.deinit(self.allocator);
    }

    pub fn addFilter(self: *CompositeFilter, filter: *const Filter) !void {
        try self.filters.append(self.allocator, filter);
    }

    pub fn shouldLog(self: *const CompositeFilter, record: *const Record) bool {
        if (self.filters.items.len == 0) return true;
        return switch (self.mode) {
            .all => {
                for (self.filters.items) |filter| {
                    if (!filter.shouldLog(record)) return false;
                }
                return true;
            },
            .any => {
                for (self.filters.items) |filter| {
                    if (filter.shouldLog(record)) return true;
                }
                return false;
            },
            .none => {
                for (self.filters.items) |filter| {
                    if (filter.shouldLog(record)) return false;
                }
                return true;
            },
            .notAll => {
                for (self.filters.items) |filter| {
                    if (!filter.shouldLog(record)) return true;
                }
                return false;
            },
        };
    }
};

pub fn matchGlob(str: []const u8, pattern: []const u8) bool {
    if (pattern.len == 0) return str.len == 0;
    if (std.mem.eql(u8, pattern, "*")) return true;

    var sIdx: usize = 0;
    var pIdx: usize = 0;
    var starIdx: ?usize = null;
    var matchIdx: usize = 0;

    while (sIdx < str.len) {
        if (pIdx < pattern.len and (pattern[pIdx] == '?' or pattern[pIdx] == str[sIdx])) {
            sIdx += 1;
            pIdx += 1;
        } else if (pIdx < pattern.len and pattern[pIdx] == '*') {
            starIdx = pIdx;
            matchIdx = sIdx;
            pIdx += 1;
        } else if (starIdx) |star| {
            pIdx = star + 1;
            matchIdx += 1;
            sIdx = matchIdx;
        } else {
            return false;
        }
    }

    while (pIdx < pattern.len and pattern[pIdx] == '*') {
        pIdx += 1;
    }

    return pIdx == pattern.len;
}

test "filter basic" {
    var filter = Filter.init(std.testing.allocator);
    defer filter.deinit();

    try filter.addMinLevel(.warning);

    var recordInfo = Record.init(std.testing.allocator, .info, "test");
    defer recordInfo.deinit();

    var recordErr = Record.init(std.testing.allocator, .err, "test");
    defer recordErr.deinit();

    try std.testing.expect(!filter.shouldLog(&recordInfo));
    try std.testing.expect(filter.shouldLog(&recordErr));
}

test "filter max level" {
    var filter = Filter.init(std.testing.allocator);
    defer filter.deinit();

    try filter.addMinLevel(.info);
    try filter.addMaxLevel(.warning);

    var recordDebug = Record.init(std.testing.allocator, .debug, "test");
    defer recordDebug.deinit();

    var recordInfo = Record.init(std.testing.allocator, .info, "test");
    defer recordInfo.deinit();

    var recordWarning = Record.init(std.testing.allocator, .warning, "test");
    defer recordWarning.deinit();

    var recordErr = Record.init(std.testing.allocator, .err, "test");
    defer recordErr.deinit();

    // debug < info (min), should not pass
    try std.testing.expect(!filter.shouldLog(&recordDebug));
    // info == info (min), should pass
    try std.testing.expect(filter.shouldLog(&recordInfo));
    // warning == warning (max), should pass
    try std.testing.expect(filter.shouldLog(&recordWarning));
    // err > warning (max), should not pass
    try std.testing.expect(!filter.shouldLog(&recordErr));
}

test "filter module prefix" {
    var filter = Filter.init(std.testing.allocator);
    defer filter.deinit();

    try filter.addModulePrefix("database");

    var recordNoModule = Record.init(std.testing.allocator, .info, "test");
    defer recordNoModule.deinit();

    var recordDb = Record.init(std.testing.allocator, .info, "test");
    defer recordDb.deinit();
    recordDb.module = "database.query";

    var recordHttp = Record.init(std.testing.allocator, .info, "test");
    defer recordHttp.deinit();
    recordHttp.module = "http.server";

    // No module should fail
    try std.testing.expect(!filter.shouldLog(&recordNoModule));
    // database.query starts with "database", should pass
    try std.testing.expect(filter.shouldLog(&recordDb));
    // http.server does not start with "database", should fail
    try std.testing.expect(!filter.shouldLog(&recordHttp));
}

test "filter modes any" {
    var filter = Filter.init(std.testing.allocator);
    defer filter.deinit();
    filter.mode = .any;

    try filter.allowModule("auth");
    try filter.addMinLevel(.err);

    var recordAuthInfo = Record.init(std.testing.allocator, .info, "login");
    defer recordAuthInfo.deinit();
    recordAuthInfo.module = "auth";

    var recordDbErr = Record.init(std.testing.allocator, .err, "db error");
    defer recordDbErr.deinit();
    recordDbErr.module = "database";

    var recordDbInfo = Record.init(std.testing.allocator, .info, "db info");
    defer recordDbInfo.deinit();
    recordDbInfo.module = "database";

    // auth info matches module allow rule
    try std.testing.expect(filter.shouldLog(&recordAuthInfo));
    // db err matches min level rule
    try std.testing.expect(filter.shouldLog(&recordDbErr));
    // db info matches neither
    try std.testing.expect(!filter.shouldLog(&recordDbInfo));
}

test "filter regex" {
    var filter = Filter.init(std.testing.allocator);
    defer filter.deinit();

    try filter.allowRegex("user_\\d+");

    var recordMatch = Record.init(std.testing.allocator, .info, "Hello user_123");
    defer recordMatch.deinit();

    var recordNoMatch = Record.init(std.testing.allocator, .info, "Hello user_abc");
    defer recordNoMatch.deinit();

    try std.testing.expect(filter.shouldLog(&recordMatch));
    try std.testing.expect(!filter.shouldLog(&recordNoMatch));
}

test "filter context" {
    var filter = Filter.init(std.testing.allocator);
    defer filter.deinit();

    try filter.addContextMatch("request_id", "req-*", .allow);

    var recordMatch = Record.init(std.testing.allocator, .info, "msg");
    defer recordMatch.deinit();
    try recordMatch.context.put("request_id", .{ .string = "req-123" });

    var recordNoMatch = Record.init(std.testing.allocator, .info, "msg");
    defer recordNoMatch.deinit();
    try recordNoMatch.context.put("request_id", .{ .string = "other-123" });

    try std.testing.expect(filter.shouldLog(&recordMatch));
    try std.testing.expect(!filter.shouldLog(&recordNoMatch));
}

test "filter message contains" {
    var filter = Filter.init(std.testing.allocator);
    defer filter.deinit();

    try filter.addMessageFilter("heartbeat", .deny);

    var recordNormal = Record.init(std.testing.allocator, .info, "User logged in");
    defer recordNormal.deinit();

    var recordHeartbeat = Record.init(std.testing.allocator, .info, "heartbeat check");
    defer recordHeartbeat.deinit();

    // Normal message should pass
    try std.testing.expect(filter.shouldLog(&recordNormal));
    // Message containing "heartbeat" should be denied
    try std.testing.expect(!filter.shouldLog(&recordHeartbeat));
}

test "filter with custom level" {
    var filter = Filter.init(std.testing.allocator);
    defer filter.deinit();

    // Set minimum level to warning (priority 30)
    try filter.addMinLevel(.warning);

    // Custom level with priority 35 (between warning 30 and err 40)
    var recordCustom = Record.initCustom(std.testing.allocator, .warning, "AUDIT", Color.Tint.color.ansi4.magenta, "Audit event");
    defer recordCustom.deinit();

    // Custom level uses the base level for filtering, which is .warning (30)
    // Since warning (30) >= warning (30), it should pass
    try std.testing.expect(filter.shouldLog(&recordCustom));

    // Custom level with lower priority (mapped to info which is 20)
    var recordCustomLow = Record.initCustom(std.testing.allocator, .info, "NOTICE", Color.Tint.color.ansi4.brightCyan, "Notice event");
    defer recordCustomLow.deinit();

    // info (20) < warning (30), should not pass
    try std.testing.expect(!filter.shouldLog(&recordCustomLow));
}

test "filter mode helpers" {
    var filter = Filter.init(std.testing.allocator);
    defer filter.deinit();

    try std.testing.expect(filter.isMode(.all));
    filter.setMode(.any);
    try std.testing.expect(filter.isMode(.any));
    try std.testing.expect(!filter.isMode(.none));
}

test "glob matching" {
    try std.testing.expect(matchGlob("database.query", "database.*"));
    try std.testing.expect(matchGlob("database.query", "*query"));
    try std.testing.expect(!matchGlob("database.query", "database"));
    try std.testing.expect(matchGlob("database", "database"));
}

test "time window filter" {
    var filter = Filter.init(std.testing.allocator);
    defer filter.deinit();

    // Quiet hours: 22:00 to 06:00
    try filter.addTimeWindowRule(22, 6, .deny);

    var recDay = Record.init(std.testing.allocator, .info, "day message");
    defer recDay.deinit();
    // 12:00 UTC (noon)
    recDay.timestamp = 12 * 60 * 60 * 1000;

    var recNight = Record.init(std.testing.allocator, .info, "night message");
    defer recNight.deinit();
    // 23:00 UTC (night)
    recNight.timestamp = 23 * 60 * 60 * 1000;

    // Inside quiet hours (23:00) should be denied
    try std.testing.expect(!filter.shouldLog(&recNight));
    // Outside quiet hours (12:00) should be allowed
    try std.testing.expect(filter.shouldLog(&recDay));
}

test "rate limit filter" {
    var filter = Filter.init(std.testing.allocator);
    defer filter.deinit();

    // Limit to 2 messages per second
    try filter.addRateRule(2, .allow);

    var rec = Record.init(std.testing.allocator, .info, "msg");
    defer rec.deinit();
    rec.module = "test_rate";

    // 1st request -> allowed
    try std.testing.expect(filter.shouldLog(&rec));
    // 2nd request -> allowed
    try std.testing.expect(filter.shouldLog(&rec));
    // 3rd request -> denied (exceeds 2)
    try std.testing.expect(!filter.shouldLog(&rec));
}

test "composite filter" {
    var f1 = Filter.init(std.testing.allocator);
    defer f1.deinit();
    try f1.addMinLevel(.warning);

    var f2 = Filter.init(std.testing.allocator);
    defer f2.deinit();
    try f2.allowModule("auth");

    var composite = CompositeFilter.init(std.testing.allocator);
    defer composite.deinit();
    composite.mode = .all;
    try composite.addFilter(&f1);
    try composite.addFilter(&f2);

    var recAuthWarn = Record.init(std.testing.allocator, .warning, "warn");
    defer recAuthWarn.deinit();
    recAuthWarn.module = "auth";

    var recAuthInfo = Record.init(std.testing.allocator, .info, "info");
    defer recAuthInfo.deinit();
    recAuthInfo.module = "auth";

    try std.testing.expect(composite.shouldLog(&recAuthWarn));
    try std.testing.expect(!composite.shouldLog(&recAuthInfo));
}

pub fn getNestedContextValue(context: *const std.StringHashMap(std.json.Value), path: []const u8) ?std.json.Value {
    if (context.get(path)) |v| return v;

    var it = std.mem.splitScalar(u8, path, '.');
    const firstKey = it.next() orelse return null;

    var currentVal = context.get(firstKey) orelse return null;

    while (it.next()) |key| {
        switch (currentVal) {
            .object => |obj| {
                currentVal = obj.get(key) orelse return null;
            },
            else => return null,
        }
    }

    return currentVal;
}

test "nested context path filter" {
    var filter = Filter.init(std.testing.allocator);
    defer filter.deinit();

    try filter.addContextPathMatch("user.id", "42", .allow);

    var rec = Record.init(std.testing.allocator, .info, "msg");
    defer rec.deinit();

    // Context does not match -> denied
    try std.testing.expect(!filter.shouldLog(&rec));

    // Nested object: user: { id: 42 }
    var userObj: std.json.ObjectMap = .empty;
    defer userObj.deinit(std.testing.allocator);
    try userObj.put(std.testing.allocator, "id", .{ .integer = 42 });

    try rec.context.put("user", .{ .object = userObj });

    // Context path matches -> allowed
    try std.testing.expect(filter.shouldLog(&rec));
}
