//! Invoke triggers.
//!
//! Attaches extra messages when records match level, content, or timing rules.
const std = @import("std");
const Level = @import("level.zig").Level;
const Record = @import("record.zig").Record;
const Constants = @import("constants.zig");
const Utils = @import("utils.zig");

/// Rule set that attaches extra messages when matching records are logged.
pub const Invoke = struct {
    allocator: std.mem.Allocator,
    triggers: std.ArrayList(Trigger),
    enabled: bool = false,
    mutex: std.Io.Mutex = std.Io.Mutex.init,
    stats: Stats = .{},

    /// Text emitted by a matching invoke rule.
    pub const Message = []const u8;

    /// Counters describing how often invoke rules fired.
    pub const Stats = struct {
        triggersEvaluated: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        triggersMatched: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        messagesEmitted: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),

        /// Number of records whose rules were evaluated.
        pub fn getTriggersEvaluated(self: *const Stats) u64 {
            return Utils.atomicLoadU64(&self.triggersEvaluated);
        }

        /// Number of records that matched at least one rule.
        pub fn getTriggersMatched(self: *const Stats) u64 {
            return Utils.atomicLoadU64(&self.triggersMatched);
        }

        /// Number of messages emitted by rules.
        pub fn getMessagesEmitted(self: *const Stats) u64 {
            return Utils.atomicLoadU64(&self.messagesEmitted);
        }

        /// Zeroes every counter.
        pub fn reset(self: *Stats) void {
            self.triggersEvaluated.store(0, .monotonic);
            self.triggersMatched.store(0, .monotonic);
            self.messagesEmitted.store(0, .monotonic);
        }
    };

    /// How to match log levels.
    pub const LevelMatch = union(enum) {
        exact: Level,
        minPriority: u8,
        maxPriority: u8,
        priorityRange: struct { min: u8, max: u8 },
        customName: []const u8,
        any: void,
    };

    /// A trigger definition.
    pub const Trigger = struct {
        id: u32,
        name: ?[]const u8 = null,
        enabled: bool = true,
        once: bool = false,
        fired: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
        levelMatch: ?LevelMatch = null,
        module: ?[]const u8 = null,
        function: ?[]const u8 = null,
        messageContains: ?[]const u8 = null,
        messageRegex: ?[]const u8 = null,
        minDurationNs: ?u64 = null,
        messages: []const Message,
        priority: u8 = 100,
        cooldownMs: u64 = 0,
        lastFiredMs: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),

        pub fn matches(self: *const Trigger, record: *const Record) bool {
            if (!self.enabled) return false;
            if (self.once and self.fired.load(.monotonic)) return false;

            if (self.minDurationNs) |threshold| {
                if (record.durationNs) |dur| {
                    if (dur < threshold) return false;
                } else {
                    return false;
                }
            }

            if (self.levelMatch) |lm| {
                const matched = switch (lm) {
                    .exact => |lev| record.level == lev,
                    .minPriority => |min| record.level.priority() >= min,
                    .maxPriority => |max| record.level.priority() <= max,
                    .priorityRange => |range| record.level.priority() >= range.min and record.level.priority() <= range.max,
                    .customName => |name| blk: {
                        if (record.customLevelName) |cname| {
                            break :blk std.mem.eql(u8, cname, name);
                        }
                        break :blk false;
                    },
                    .any => true,
                };
                if (!matched) return false;
            }

            if (self.module) |mod| {
                if (record.module) |recMod| {
                    if (!std.mem.eql(u8, recMod, mod)) return false;
                } else {
                    return false;
                }
            }

            if (self.function) |func| {
                if (record.function) |recFunc| {
                    if (!std.mem.eql(u8, recFunc, func)) return false;
                } else {
                    return false;
                }
            }

            if (self.messageContains) |pattern| {
                if (std.mem.indexOf(u8, record.message, pattern) == null) {
                    return false;
                }
            }

            if (self.messageRegex) |regex| {
                if (Utils.findRegexPattern(record.message, regex) == null) {
                    return false;
                }
            }

            if (self.cooldownMs > 0) {
                const now: Constants.AtomicUnsigned = @truncate(@as(u64, @intCast(Utils.currentMillis())));
                const last = self.lastFiredMs.load(.monotonic);
                if (now - last < self.cooldownMs) return false;
            }

            return true;
        }
    };

    pub fn init(allocator: std.mem.Allocator) Invoke {
        return .{
            .allocator = allocator,
            .triggers = .empty,
        };
    }

    pub fn deinit(self: *Invoke) void {
        self.triggers.deinit(self.allocator);
    }

    pub fn enable(self: *Invoke) void {
        self.enabled = true;
    }

    pub fn disable(self: *Invoke) void {
        self.enabled = false;
    }

    pub fn isEnabled(self: *const Invoke) bool {
        return self.enabled;
    }

    pub fn count(self: *const Invoke) usize {
        return self.triggers.items.len;
    }

    pub fn add(self: *Invoke, trigger: Trigger) !void {
        for (self.triggers.items) |existing| {
            if (existing.id == trigger.id) return error.TriggerIdAlreadyExists;
        }
        try self.triggers.append(self.allocator, trigger);
    }

    pub fn addOrUpdate(self: *Invoke, trigger: Trigger) !void {
        for (self.triggers.items, 0..) |existing, i| {
            if (existing.id == trigger.id) {
                self.triggers.items[i] = trigger;
                return;
            }
        }
        try self.triggers.append(self.allocator, trigger);
    }

    pub fn remove(self: *Invoke, id: u32) bool {
        for (self.triggers.items, 0..) |trigger, i| {
            if (trigger.id == id) {
                _ = self.triggers.orderedRemove(i);
                return true;
            }
        }
        return false;
    }

    pub fn getById(self: *const Invoke, id: u32) ?Trigger {
        for (self.triggers.items) |trigger| {
            if (trigger.id == id) return trigger;
        }
        return null;
    }

    pub fn clear(self: *Invoke) void {
        self.triggers.clearRetainingCapacity();
    }

    pub fn evaluate(self: *Invoke, record: *const Record) ?[]const Message {
        if (!self.enabled) return null;

        self.stats.triggersEvaluated.store(
            self.stats.triggersEvaluated.load(.monotonic) + 1,
            .monotonic,
        );

        var matchedMessages: std.ArrayList(Message) = .empty;
        var anyMatched = false;

        for (self.triggers.items) |*trigger| {
            if (trigger.matches(record)) {
                anyMatched = true;
                self.stats.triggersMatched.store(
                    self.stats.triggersMatched.load(.monotonic) + 1,
                    .monotonic,
                );

                for (trigger.messages) |msg| {
                    matchedMessages.append(self.allocator, msg) catch continue;
                }

                if (trigger.once) {
                    trigger.fired.store(true, .monotonic);
                }

                const now: Constants.AtomicUnsigned = @truncate(@as(u64, @intCast(Utils.currentMillis())));
                trigger.lastFiredMs.store(now, .monotonic);
            }
        }

        if (!anyMatched) return null;

        const total = matchedMessages.items.len;
        self.stats.messagesEmitted.store(
            self.stats.messagesEmitted.load(.monotonic) + total,
            .monotonic,
        );

        return matchedMessages.toOwnedSlice(self.allocator) catch null;
    }

    pub fn formatMessages(self: *Invoke, messages: []const Message, writer: anytype, useColor: bool) !void {
        _ = useColor;
        _ = self;

        for (messages) |msg| {
            try writer.writeAll("\n");
            try writer.writeAll(msg);
        }
    }

    pub fn formatMessagesJson(self: *Invoke, messages: []const Message, writer: anytype, pretty: bool) !void {
        _ = self;
        const indent = if (pretty) "    " else "";
        const newline = if (pretty) "\n" else "";

        try writer.writeAll("[");
        try writer.writeAll(newline);

        for (messages, 0..) |msg, i| {
            try writer.writeAll(indent);
            try writer.writeByte('"');
            try Utils.escapeJsonString(writer, msg);
            try writer.writeByte('"');

            if (i + 1 < messages.len) {
                try writer.writeAll(",");
            }
            try writer.writeAll(newline);
        }

        try writer.writeAll("]");
    }

    pub fn getStats(self: *const Invoke) Stats {
        return self.stats;
    }

    pub fn resetStats(self: *Invoke) void {
        self.stats.reset();
    }
};

// Tests
test "invoke basic" {
    var invoke = Invoke.init(std.testing.allocator);
    defer invoke.deinit();

    try std.testing.expect(!invoke.enabled);
    try std.testing.expectEqual(@as(usize, 0), invoke.count());
}

test "invoke add and evaluate" {
    var invoke = Invoke.init(std.testing.allocator);
    defer invoke.deinit();
    invoke.enable();

    const messages = [_]Invoke.Message{
        ">> [ERROR] Test diagnostic",
        ">> [FIX] Test help",
    };

    try invoke.add(.{
        .id = 0,
        .levelMatch = .{ .exact = .err },
        .messages = &messages,
    });

    var record = Record.init(std.testing.allocator, .err, "Test error");
    defer record.deinit();

    const result = invoke.evaluate(&record);
    try std.testing.expect(result != null);
    if (result) |msgs| {
        defer std.testing.allocator.free(msgs);
        try std.testing.expectEqual(@as(usize, 2), msgs.len);
    }
}

test "invoke once firing" {
    var invoke = Invoke.init(std.testing.allocator);
    defer invoke.deinit();
    invoke.enable();

    const messages = [_]Invoke.Message{
        ">> [INFO] This should fire once",
    };

    try invoke.add(.{
        .id = 0,
        .once = true,
        .levelMatch = .{ .exact = .info },
        .messages = &messages,
    });

    var record = Record.init(std.testing.allocator, .info, "Test");
    defer record.deinit();

    const result1 = invoke.evaluate(&record);
    try std.testing.expect(result1 != null);
    if (result1) |msgs| {
        defer std.testing.allocator.free(msgs);
    }

    const result2 = invoke.evaluate(&record);
    try std.testing.expect(result2 == null);
}

test "invoke custom level" {
    var invoke = Invoke.init(std.testing.allocator);
    defer invoke.deinit();
    invoke.enable();

    const messages = [_]Invoke.Message{
        "Custom level triggered",
    };

    try invoke.add(.{
        .id = 1,
        .levelMatch = .{ .customName = "audit" },
        .messages = &messages,
    });

    var record = Record.init(std.testing.allocator, .info, "audited action");
    defer record.deinit();
    record.customLevelName = "audit";

    const result = invoke.evaluate(&record);
    try std.testing.expect(result != null);
    if (result) |msgs| {
        defer std.testing.allocator.free(msgs);
        try std.testing.expectEqual(@as(usize, 1), msgs.len);
        try std.testing.expectEqualStrings("Custom level triggered", msgs[0]);
    }
}

test "invoke min priority matches multiple levels" {
    var invoke = Invoke.init(std.testing.allocator);
    defer invoke.deinit();
    invoke.enable();

    const messages = [_]Invoke.Message{
        "High priority warning",
    };

    try invoke.add(.{
        .id = 1,
        .levelMatch = .{ .minPriority = 40 },
        .messages = &messages,
    });

    var errRecord = Record.init(std.testing.allocator, .err, "error");
    defer errRecord.deinit();
    const errResult = invoke.evaluate(&errRecord);
    try std.testing.expect(errResult != null);
    if (errResult) |msgs| std.testing.allocator.free(msgs);

    var infoRecord = Record.init(std.testing.allocator, .info, "info");
    defer infoRecord.deinit();
    try std.testing.expect(invoke.evaluate(&infoRecord) == null);
}

test "invoke priority range" {
    var invoke = Invoke.init(std.testing.allocator);
    defer invoke.deinit();
    invoke.enable();

    const messages = [_]Invoke.Message{
        "Mid priority",
    };

    try invoke.add(.{
        .id = 1,
        .levelMatch = .{ .priorityRange = .{ .min = 30, .max = 40 } },
        .messages = &messages,
    });

    var warnRecord = Record.init(std.testing.allocator, .warning, "warn");
    defer warnRecord.deinit();
    const warnResult = invoke.evaluate(&warnRecord);
    try std.testing.expect(warnResult != null);
    if (warnResult) |msgs| std.testing.allocator.free(msgs);

    var debugRecord = Record.init(std.testing.allocator, .debug, "debug");
    defer debugRecord.deinit();
    try std.testing.expect(invoke.evaluate(&debugRecord) == null);
}

test "invoke message_contains filter" {
    var invoke = Invoke.init(std.testing.allocator);
    defer invoke.deinit();
    invoke.enable();

    const messages = [_]Invoke.Message{
        "Database timeout detected",
    };

    try invoke.add(.{
        .id = 1,
        .levelMatch = .{ .any = {} },
        .messageContains = "database",
        .messages = &messages,
    });

    var matchRecord = Record.init(std.testing.allocator, .err, "database connection failed");
    defer matchRecord.deinit();
    const matchResult = invoke.evaluate(&matchRecord);
    try std.testing.expect(matchResult != null);
    if (matchResult) |msgs| std.testing.allocator.free(msgs);

    var noMatchRecord = Record.init(std.testing.allocator, .err, "network timeout");
    defer noMatchRecord.deinit();
    try std.testing.expect(invoke.evaluate(&noMatchRecord) == null);
}

test "invoke remove" {
    var invoke = Invoke.init(std.testing.allocator);
    defer invoke.deinit();

    const messages = [_]Invoke.Message{"msg"};
    try invoke.add(.{ .id = 1, .messages = &messages });
    try invoke.add(.{ .id = 2, .messages = &messages });
    try invoke.add(.{ .id = 3, .messages = &messages });

    try std.testing.expectEqual(@as(usize, 3), invoke.count());

    const removed = invoke.remove(2);
    try std.testing.expect(removed);
    try std.testing.expectEqual(@as(usize, 2), invoke.count());

    const notRemoved = invoke.remove(999);
    try std.testing.expect(!notRemoved);
}

test "invoke format messages" {
    var invoke = Invoke.init(std.testing.allocator);
    defer invoke.deinit();

    const messages = [_]Invoke.Message{
        ">> [ERROR] Test message",
    };

    var buf = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer buf.deinit();

    try invoke.formatMessages(&messages, &buf.writer, false);

    try std.testing.expect(buf.written().len > 0);
    try std.testing.expect(std.mem.indexOf(u8, buf.written(), "Test message") != null);
}

test "invoke statistics" {
    var invoke = Invoke.init(std.testing.allocator);
    defer invoke.deinit();
    invoke.enable();

    const messages = [_]Invoke.Message{"msg"};
    try invoke.add(.{
        .id = 1,
        .levelMatch = .{ .exact = .err },
        .messages = &messages,
    });

    var record = Record.init(std.testing.allocator, .err, "Test");
    defer record.deinit();

    const result = invoke.evaluate(&record);
    if (result) |msgs| {
        defer std.testing.allocator.free(msgs);
    }

    const stats = invoke.getStats();
    try std.testing.expect(stats.getTriggersEvaluated() > 0);
    try std.testing.expect(stats.getTriggersMatched() > 0);
}

test "invoke json format" {
    var invoke = Invoke.init(std.testing.allocator);
    defer invoke.deinit();

    const messages = [_]Invoke.Message{
        "Test error",
        "Fix it",
    };

    var buf = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer buf.deinit();

    try invoke.formatMessagesJson(&messages, &buf.writer, false);

    try std.testing.expect(buf.written().len > 0);
    try std.testing.expect(std.mem.indexOf(u8, buf.written(), "Test error") != null);
}

test "invoke addOrUpdate" {
    var invoke = Invoke.init(std.testing.allocator);
    defer invoke.deinit();

    const messages1 = [_]Invoke.Message{"Original"};
    const messages2 = [_]Invoke.Message{"Updated"};

    try invoke.addOrUpdate(.{ .id = 1, .messages = &messages1 });
    try std.testing.expectEqual(@as(usize, 1), invoke.count());

    try invoke.addOrUpdate(.{ .id = 1, .messages = &messages2 });
    try std.testing.expectEqual(@as(usize, 1), invoke.count());

    if (invoke.getById(1)) |trigger| {
        try std.testing.expectEqualStrings("Updated", trigger.messages[0]);
    }
}

test "invoke cooldown" {
    var invoke = Invoke.init(std.testing.allocator);
    defer invoke.deinit();
    invoke.enable();

    const messages = [_]Invoke.Message{"cooled"};
    try invoke.add(.{
        .id = 1,
        .levelMatch = .{ .any = {} },
        .cooldownMs = 10000,
        .messages = &messages,
    });

    var record = Record.init(std.testing.allocator, .info, "test");
    defer record.deinit();

    const result1 = invoke.evaluate(&record);
    try std.testing.expect(result1 != null);
    if (result1) |msgs| std.testing.allocator.free(msgs);

    const result2 = invoke.evaluate(&record);
    try std.testing.expect(result2 == null);
}

test "invoke reset once-fired" {
    var invoke = Invoke.init(std.testing.allocator);
    defer invoke.deinit();
    invoke.enable();

    const messages = [_]Invoke.Message{"once"};
    try invoke.add(.{
        .id = 1,
        .once = true,
        .levelMatch = .{ .any = {} },
        .messages = &messages,
    });

    var record = Record.init(std.testing.allocator, .info, "test");
    defer record.deinit();

    const r1 = invoke.evaluate(&record);
    try std.testing.expect(r1 != null);
    if (r1) |msgs| std.testing.allocator.free(msgs);

    const r2 = invoke.evaluate(&record);
    try std.testing.expect(r2 == null);

    for (invoke.triggers.items) |*t| t.fired.store(false, .monotonic);

    const r3 = invoke.evaluate(&record);
    try std.testing.expect(r3 != null);
    if (r3) |msgs| std.testing.allocator.free(msgs);
}
