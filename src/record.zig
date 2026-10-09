//! Log record.
//!
//! A single log event: timestamp, level, message, context, and trace data.
const std = @import("std");
const Level = @import("level.zig").Level;
const Utils = @import("utils.zig");
const Color = @import("color.zig");

/// Represents a single log event.
pub const Record = struct {
    /// Unix timestamp in milliseconds.
    timestamp: i64,

    /// Severity level of the log.
    level: Level,

    /// Custom level name (overrides standard level display if set).
    customLevelName: ?[]const u8 = null,

    /// Custom level color (overrides standard level color if set).
    /// A tint `Color` value; no allocation or lifetime management needed.
    customLevelColor: ?Color.Color = null,

    /// The actual log message.
    message: []const u8,

    /// Name of the module where the log originated (optional).
    module: ?[]const u8 = null,

    /// Name of the function where the log originated (optional).
    function: ?[]const u8 = null,

    /// Source filename (optional).
    filename: ?[]const u8 = null,

    /// Source line number (optional).
    line: ?u32 = null,

    /// Column number in source (optional).
    column: ?u32 = null,

    /// Thread ID for concurrent logging identification.
    threadId: ?u64 = null,

    /// Distributed trace ID for request tracing across services.
    traceId: ?[]const u8 = null,

    /// Span ID for distributed tracing within a trace.
    spanId: ?[]const u8 = null,

    /// Parent span ID for nested spans.
    parentSpanId: ?[]const u8 = null,
    /// Stack trace (optional).
    stackTrace: ?*std.builtin.StackTrace = null,
    /// Correlation ID for grouping related log entries.
    correlationId: ?[]const u8 = null,

    /// Request ID for HTTP request tracking.
    requestId: ?[]const u8 = null,

    /// Session ID for user session tracking.
    sessionId: ?[]const u8 = null,

    /// User ID for audit logging.
    userId: ?[]const u8 = null,

    /// Tags for categorization and filtering.
    tags: ?[]const []const u8 = null,

    /// Error information if this log represents an error.
    errorInfo: ?ErrorInfo = null,

    /// Duration in nanoseconds (for timing logs).
    durationNs: ?u64 = null,

    /// Additional context key-value pairs.
    context: std.StringHashMap(std.json.Value),

    /// Invoke messages attached to this record (if any triggers matched).
    invokeMessages: ?[]const InvokeMessage = null,

    /// Allocator reference for managed memory.
    allocator: std.mem.Allocator,

    /// Owned strings that need to be freed.
    ownedStrings: std.ArrayList([]const u8),

    /// Owned stack trace that needs to be freed.
    ownedStackTrace: ?*std.builtin.StackTrace = null,

    pub const ErrorCategory = enum {
        io,
        network,
        logic,
        oom,
        unknown,

        pub fn asString(self: ErrorCategory) []const u8 {
            return switch (self) {
                .io => "io",
                .network => "network",
                .logic => "logic",
                .oom => "oom",
                .unknown => "unknown",
            };
        }
    };

    /// Error information structure.
    pub const ErrorInfo = struct {
        name: []const u8,
        message: []const u8,
        stackTrace: ?[]const u8 = null,
        code: ?i32 = null,
        errorCategory: ?ErrorCategory = null,
    };

    /// Message type (re-exported from invoke.zig).
    pub const InvokeMessage = @import("invoke.zig").Invoke.Message;

    /// Returns the display name for the level (custom or standard).
    pub fn levelName(self: *const Record) []const u8 {
        return self.customLevelName orelse self.level.asString();
    }

    /// Returns the color for the level (custom or standard).
    ///
    /// Returns a tint `Color` value. Render with `color.sequence()`.
    pub fn levelColor(self: *const Record) Color.Color {
        return self.customLevelColor orelse self.level.defaultColor();
    }

    /// Creates a new log record.
    pub fn init(allocator: std.mem.Allocator, level: Level, message: []const u8) Record {
        return .{
            .timestamp = Utils.currentMillis(),
            .level = level,
            .message = message,
            .context = std.StringHashMap(std.json.Value).init(allocator),
            .allocator = allocator,
            .ownedStrings = .empty,
        };
    }

    /// Creates a new log record with custom level information.
    pub fn initCustom(
        allocator: std.mem.Allocator,
        level: Level,
        customName: []const u8,
        customColor: Color.Color,
        message: []const u8,
    ) Record {
        return .{
            .timestamp = Utils.currentMillis(),
            .level = level,
            .customLevelName = customName,
            .customLevelColor = customColor,
            .message = message,
            .context = std.StringHashMap(std.json.Value).init(allocator),
            .allocator = allocator,
            .ownedStrings = .empty,
        };
    }

    /// Creates a new log record with source location information.
    pub fn initWithSource(
        allocator: std.mem.Allocator,
        level: Level,
        message: []const u8,
        src: std.builtin.SourceLocation,
    ) Record {
        return .{
            .timestamp = Utils.currentMillis(),
            .level = level,
            .message = message,
            .filename = src.file,
            .function = src.fnName,
            .line = src.line,
            .column = src.column,
            .context = std.StringHashMap(std.json.Value).init(allocator),
            .allocator = allocator,
            .ownedStrings = .empty,
        };
    }

    /// Frees resources associated with the record.
    pub fn deinit(self: *Record) void {
        self.context.deinit();
        for (self.ownedStrings.items) |s| {
            self.allocator.free(s);
        }
        self.ownedStrings.deinit(self.allocator);

        if (self.ownedStackTrace) |st| {
            self.allocator.free(st.instruction_addresses);
            self.allocator.destroy(st);
        }

        if (self.invokeMessages) |messages| {
            self.allocator.free(messages);
        }

        if (self.tags) |t| {
            self.allocator.free(t);
        }
    }

    /// Sets the trace ID for distributed tracing.
    pub fn setTraceId(self: *Record, traceId: []const u8) !void {
        const owned = try self.allocator.dupe(u8, traceId);
        try self.ownedStrings.append(self.allocator, owned);
        self.traceId = owned;
    }

    /// Sets the span ID for distributed tracing.
    pub fn setSpanId(self: *Record, spanId: []const u8) !void {
        const owned = try self.allocator.dupe(u8, spanId);
        try self.ownedStrings.append(self.allocator, owned);
        self.spanId = owned;
    }

    /// Sets the correlation ID for grouping related logs.
    pub fn setCorrelationId(self: *Record, correlationId: []const u8) !void {
        const owned = try self.allocator.dupe(u8, correlationId);
        try self.ownedStrings.append(self.allocator, owned);
        self.correlationId = owned;
    }

    /// Adds a context field to the record.
    pub fn addField(self: *Record, key: []const u8, value: std.json.Value) !void {
        const ownedKey = try self.allocator.dupe(u8, key);
        try self.ownedStrings.append(self.allocator, ownedKey);
        try self.context.put(ownedKey, value);
    }

    /// Sets error information for error-level logs.
    pub fn setError(
        self: *Record,
        name: []const u8,
        message: []const u8,
        stackTrace: ?[]const u8,
        code: ?i32,
    ) !void {
        try self.setErrorWithCategory(name, message, stackTrace, code, null);
    }

    /// Sets error information with a specific category.
    pub fn setErrorWithCategory(
        self: *Record,
        name: []const u8,
        message: []const u8,
        stackTrace: ?[]const u8,
        code: ?i32,
        category: ?ErrorCategory,
    ) !void {
        const ownedName = try self.allocator.dupe(u8, name);
        try self.ownedStrings.append(self.allocator, ownedName);

        const ownedMessage = try self.allocator.dupe(u8, message);
        try self.ownedStrings.append(self.allocator, ownedMessage);

        var ownedStack: ?[]const u8 = null;
        if (stackTrace) |st| {
            ownedStack = try self.allocator.dupe(u8, st);
            try self.ownedStrings.append(self.allocator, ownedStack.?);
        }

        self.errorInfo = .{
            .name = ownedName,
            .message = ownedMessage,
            .stackTrace = ownedStack,
            .code = code,
            .errorCategory = category,
        };
    }

    /// Adds a category tag to the record.
    pub fn addTag(self: *Record, tag: []const u8) !void {
        const owned = try self.allocator.dupe(u8, tag);
        errdefer self.allocator.free(owned);

        var list: std.ArrayList([]const u8) = .empty;
        defer list.deinit(self.allocator);

        if (self.tags) |existing| {
            try list.appendSlice(self.allocator, existing);
        }
        try list.append(self.allocator, owned);

        const oldTags = self.tags;
        self.tags = try list.toOwnedSlice(self.allocator);
        if (oldTags) |ot| {
            self.allocator.free(ot);
        }
        try self.ownedStrings.append(self.allocator, owned);
    }

    /// Returns a numeric severity (0-100) derived from level priority.
    pub fn severity(self: *const Record) u8 {
        return switch (self.level) {
            .trace => 10,
            .debug => 20,
            .info => 40,
            .notice => 45,
            .success => 50,
            .warning => 60,
            .err => 80,
            .fail => 85,
            .critical => 90,
            .fatal => 100,
        };
    }

    /// Helper to check if severity is at or above a threshold.
    pub fn isHighSeverity(self: *const Record, threshold: Level) bool {
        return @backingInt(self.level) >= @backingInt(threshold);
    }

    fn writeLogfmtString(writer: anytype, value: []const u8) !void {
        var needsQuoting = false;
        if (value.len == 0) {
            needsQuoting = true;
        } else {
            for (value) |c| {
                if (c == ' ' or c == '=' or c == '"' or c == '\\' or c == '\n' or c == '\r' or c == '\t') {
                    needsQuoting = true;
                    break;
                }
            }
        }

        if (needsQuoting) {
            try writer.writeByte('"');
            for (value) |c| {
                switch (c) {
                    '\\' => try writer.writeAll("\\\\"),
                    '"' => try writer.writeAll("\\\""),
                    '\n' => try writer.writeAll("\\n"),
                    '\r' => try writer.writeAll("\\r"),
                    '\t' => try writer.writeAll("\\t"),
                    else => try writer.writeByte(c),
                }
            }
            try writer.writeByte('"');
        } else {
            try writer.writeAll(value);
        }
    }

    /// Serializes the record as a logfmt string.
    pub fn toLogfmt(self: *const Record, writer: anytype) !void {
        try writer.writeAll("ts=");
        try writer.print("{d}", .{self.timestamp});
        try writer.writeAll(" level=");
        try writer.writeAll(self.levelName());
        try writer.writeAll(" msg=");
        try writeLogfmtString(writer, self.message);

        if (self.module) |m| {
            try writer.writeAll(" module=");
            try writeLogfmtString(writer, m);
        }
        if (self.function) |f| {
            try writer.writeAll(" function=");
            try writeLogfmtString(writer, f);
        }
        if (self.filename) |f| {
            try writer.writeAll(" file=");
            try writeLogfmtString(writer, f);
        }
        if (self.line) |l| {
            try writer.print(" line={d}", .{l});
        }
        if (self.traceId) |tid| {
            try writer.writeAll(" traceId=");
            try writeLogfmtString(writer, tid);
        }
        if (self.spanId) |sid| {
            try writer.writeAll(" spanId=");
            try writeLogfmtString(writer, sid);
        }

        var it = self.context.iterator();
        while (it.next()) |entry| {
            try writer.print(" {s}=", .{entry.key_ptr.*});
            var valBuf: std.ArrayList(u8) = .empty;
            defer valBuf.deinit(self.allocator);
            var listWriter = Utils.ArrayListWriter.init(&valBuf, self.allocator);
            try std.json.stringify(entry.value_ptr.*, .{}, &listWriter.writer);
            try writeLogfmtString(writer, valBuf.items);
        }
    }

    /// Sets the duration for timing logs.
    pub fn setDuration(self: *Record, durationNs: u64) void {
        self.durationNs = durationNs;
    }

    /// Sets the duration from a timer start time.
    pub fn setDurationSince(self: *Record, startTime: i128) void {
        const now = Utils.currentNanos();
        const duration = @as(u64, @intCast(@max(0, now - startTime)));
        self.durationNs = duration;
    }

    /// Generates a unique trace ID.
    pub fn generateTraceId(allocator: std.mem.Allocator) ![]u8 {
        return Utils.generateTraceId(allocator);
    }

    /// Generates a unique span ID.
    pub fn generateSpanId(allocator: std.mem.Allocator) ![]u8 {
        return Utils.generateSpanId(allocator);
    }

    /// Clones the record.
    pub fn clone(self: *const Record, allocator: std.mem.Allocator) !Record {
        // Deep copy the message
        const ownedMessage = try allocator.dupe(u8, self.message);
        var newRecord = Record.init(allocator, self.level, ownedMessage);
        try newRecord.ownedStrings.append(allocator, ownedMessage);

        newRecord.timestamp = self.timestamp;
        newRecord.line = self.line;
        newRecord.column = self.column;
        newRecord.threadId = self.threadId;
        newRecord.durationNs = self.durationNs;

        // Deep copy optional strings
        if (self.module) |m| {
            const owned = try allocator.dupe(u8, m);
            try newRecord.ownedStrings.append(allocator, owned);
            newRecord.module = owned;
        }
        if (self.function) |f| {
            const owned = try allocator.dupe(u8, f);
            try newRecord.ownedStrings.append(allocator, owned);
            newRecord.function = owned;
        }
        if (self.filename) |f| {
            const owned = try allocator.dupe(u8, f);
            try newRecord.ownedStrings.append(allocator, owned);
            newRecord.filename = owned;
        }
        if (self.customLevelName) |n| {
            const owned = try allocator.dupe(u8, n);
            try newRecord.ownedStrings.append(allocator, owned);
            newRecord.customLevelName = owned;
        }
        if (self.customLevelColor) |c| {
            newRecord.customLevelColor = c;
        }

        if (self.traceId) |tid| try newRecord.setTraceId(tid);
        if (self.spanId) |sid| try newRecord.setSpanId(sid);
        if (self.correlationId) |cid| try newRecord.setCorrelationId(cid);
        if (self.parentSpanId) |psid| try newRecord.setParentSpanId(psid);
        if (self.requestId) |rid| try newRecord.setRequestId(rid);
        if (self.sessionId) |sid| try newRecord.setSessionId(sid);
        if (self.userId) |uid| try newRecord.setUserId(uid);

        if (self.tags) |tgs| {
            var list: std.ArrayList([]const u8) = .empty;
            errdefer list.deinit(allocator);
            for (tgs) |tag| {
                const owned = try allocator.dupe(u8, tag);
                try list.append(allocator, owned);
                try newRecord.ownedStrings.append(allocator, owned);
            }
            newRecord.tags = try list.toOwnedSlice(allocator);
        }

        if (self.errorInfo) |errI| {
            const ownedName = try allocator.dupe(u8, errI.name);
            try newRecord.ownedStrings.append(allocator, ownedName);
            const ownedMsg = try allocator.dupe(u8, errI.message);
            try newRecord.ownedStrings.append(allocator, ownedMsg);
            var ownedStack: ?[]const u8 = null;
            if (errI.stackTrace) |st| {
                ownedStack = try allocator.dupe(u8, st);
                try newRecord.ownedStrings.append(allocator, ownedStack.?);
            }
            newRecord.errorInfo = .{
                .name = ownedName,
                .message = ownedMsg,
                .stackTrace = ownedStack,
                .code = errI.code,
                .errorCategory = errI.errorCategory,
            };
        }

        if (self.stackTrace) |st| {
            const newSt = try allocator.create(std.builtin.StackTrace);
            const newAddresses = try allocator.dupe(usize, st.instruction_addresses);
            newSt.* = .{
                .index = st.index,
                .instruction_addresses = newAddresses,
            };
            newRecord.ownedStackTrace = newSt;
            newRecord.stackTrace = newSt;
        }

        var it = self.context.iterator();
        while (it.next()) |entry| {
            try newRecord.addField(entry.key_ptr.*, entry.value_ptr.*);
        }

        return newRecord;
    }

    /// Returns true if this record has a custom level.
    pub fn hasCustomLevel(self: *const Record) bool {
        return self.customLevelName != null;
    }

    /// Returns true if this record has context fields.
    pub fn hasContext(self: *const Record) bool {
        return self.context.count() > 0;
    }

    /// Returns the number of context fields.
    pub fn contextCount(self: *const Record) usize {
        return self.context.count();
    }

    /// Returns true if this record has a stack trace.
    pub fn hasStackTrace(self: *const Record) bool {
        return self.stackTrace != null;
    }

    /// Returns true if this record has error info.
    pub fn hasError(self: *const Record) bool {
        return self.errorInfo != null;
    }

    /// Returns true if this record has tracing info.
    pub fn hasTracing(self: *const Record) bool {
        return self.traceId != null or self.spanId != null;
    }

    /// Sets the parent span ID for hierarchical tracing.
    pub fn setParentSpanId(self: *Record, parentId: []const u8) !void {
        const owned = try self.allocator.dupe(u8, parentId);
        try self.ownedStrings.append(self.allocator, owned);
        self.parentSpanId = owned;
    }

    /// Sets the request ID for HTTP request tracking.
    pub fn setRequestId(self: *Record, reqId: []const u8) !void {
        const owned = try self.allocator.dupe(u8, reqId);
        try self.ownedStrings.append(self.allocator, owned);
        self.requestId = owned;
    }

    /// Sets the session ID for user session tracking.
    pub fn setSessionId(self: *Record, sessId: []const u8) !void {
        const owned = try self.allocator.dupe(u8, sessId);
        try self.ownedStrings.append(self.allocator, owned);
        self.sessionId = owned;
    }

    /// Sets the user ID for audit logging.
    pub fn setUserId(self: *Record, uid: []const u8) !void {
        const owned = try self.allocator.dupe(u8, uid);
        try self.ownedStrings.append(self.allocator, owned);
        self.userId = owned;
    }

    /// Returns true if this record has a request ID.
    pub fn hasRequestId(self: *const Record) bool {
        return self.requestId != null;
    }

    /// Returns true if this record has a session ID.
    pub fn hasSessionId(self: *const Record) bool {
        return self.sessionId != null;
    }

    /// Returns true if this record has a user ID.
    pub fn hasUserId(self: *const Record) bool {
        return self.userId != null;
    }

    /// Returns true if this record has a parent span ID.
    pub fn hasParentSpan(self: *const Record) bool {
        return self.parentSpanId != null;
    }
};

test "record init sets level and message" {
    var record = Record.init(std.testing.allocator, .info, "hello");
    defer record.deinit();
    try std.testing.expectEqual(Level.info, record.level);
    try std.testing.expectEqualStrings("hello", record.message);
}

test "record levelColor uses default and custom" {
    var record = Record.init(std.testing.allocator, .err, "oops");
    defer record.deinit();
    try std.testing.expectEqual(Level.err.defaultColor(), record.levelColor());
    record.customLevelColor = Color.Tint.color.ansi4.magenta;
    try std.testing.expectEqual(Color.Tint.color.ansi4.magenta, record.levelColor());
}

test "record initCustom stores color" {
    var record = Record.initCustom(std.testing.allocator, .warning, "AUDIT", Color.Tint.color.cyan, "audit");
    defer record.deinit();
    try std.testing.expectEqualStrings("AUDIT", record.customLevelName.?);
    try std.testing.expectEqual(Color.Tint.color.cyan, record.customLevelColor.?);
}
