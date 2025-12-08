const std = @import("std");
const Level = @import("level.zig").Level;

/// Represents a single log event.
///
/// Contains all the metadata associated with a log message, including
/// timestamp, level, message content, source location, and tracing information.
pub const Record = struct {
    /// Unix timestamp in milliseconds.
    timestamp: i64,

    /// Severity level of the log.
    level: Level,

    /// Custom level name (overrides standard level display if set).
    custom_level_name: ?[]const u8 = null,

    /// Custom level color (overrides standard level color if set).
    custom_level_color: ?[]const u8 = null,

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
    thread_id: ?u64 = null,

    /// Distributed trace ID for request tracing across services.
    trace_id: ?[]const u8 = null,

    /// Span ID for distributed tracing within a trace.
    span_id: ?[]const u8 = null,

    /// Parent span ID for nested spans.
    parent_span_id: ?[]const u8 = null,

    /// Correlation ID for grouping related log entries.
    correlation_id: ?[]const u8 = null,

    /// Request ID for HTTP request tracking.
    request_id: ?[]const u8 = null,

    /// Session ID for user session tracking.
    session_id: ?[]const u8 = null,

    /// User ID for audit logging.
    user_id: ?[]const u8 = null,

    /// Tags for categorization and filtering.
    tags: ?[]const []const u8 = null,

    /// Error information if this log represents an error.
    error_info: ?ErrorInfo = null,

    /// Duration in nanoseconds (for timing logs).
    duration_ns: ?u64 = null,

    /// Additional context key-value pairs.
    context: std.StringHashMap(std.json.Value),

    /// Allocator reference for managed memory.
    allocator: std.mem.Allocator,

    /// Owned strings that need to be freed.
    owned_strings: std.ArrayList([]const u8),

    /// Error information structure.
    pub const ErrorInfo = struct {
        name: []const u8,
        message: []const u8,
        stack_trace: ?[]const u8 = null,
        code: ?i32 = null,
    };

    /// Returns the display name for the level (custom or standard).
    pub fn levelName(self: *const Record) []const u8 {
        return self.custom_level_name orelse self.level.asString();
    }

    /// Returns the color code for the level (custom or standard).
    pub fn levelColor(self: *const Record) []const u8 {
        return self.custom_level_color orelse self.level.defaultColor();
    }

    /// Creates a new log record.
    ///
    /// Arguments:
    ///     allocator: Allocator for the context map.
    ///     level: Log severity.
    ///     message: Log message content.
    ///
    /// Returns:
    ///     A new Record instance.
    pub fn init(allocator: std.mem.Allocator, level: Level, message: []const u8) Record {
        return .{
            .timestamp = std.time.milliTimestamp(),
            .level = level,
            .message = message,
            .context = std.StringHashMap(std.json.Value).init(allocator),
            .allocator = allocator,
            .owned_strings = .empty,
        };
    }

    /// Creates a new log record with custom level information.
    ///
    /// Arguments:
    ///     allocator: Allocator for the context map.
    ///     level: Base log severity for filtering.
    ///     custom_name: Custom level name to display.
    ///     custom_color: Custom color code for the level.
    ///     message: Log message content.
    ///
    /// Returns:
    ///     A new Record instance with custom level.
    pub fn initCustom(
        allocator: std.mem.Allocator,
        level: Level,
        custom_name: []const u8,
        custom_color: []const u8,
        message: []const u8,
    ) Record {
        return .{
            .timestamp = std.time.milliTimestamp(),
            .level = level,
            .custom_level_name = custom_name,
            .custom_level_color = custom_color,
            .message = message,
            .context = std.StringHashMap(std.json.Value).init(allocator),
            .allocator = allocator,
            .owned_strings = .empty,
        };
    }

    /// Creates a new log record with source location information.
    ///
    /// Arguments:
    ///     allocator: Allocator for the context map.
    ///     level: Log severity.
    ///     message: Log message content.
    ///     src: Source location information.
    ///
    /// Returns:
    ///     A new Record instance with source information populated.
    pub fn initWithSource(
        allocator: std.mem.Allocator,
        level: Level,
        message: []const u8,
        src: std.builtin.SourceLocation,
    ) Record {
        return .{
            .timestamp = std.time.milliTimestamp(),
            .level = level,
            .message = message,
            .filename = src.file,
            .function = src.fn_name,
            .line = src.line,
            .column = src.column,
            .context = std.StringHashMap(std.json.Value).init(allocator),
            .allocator = allocator,
            .owned_strings = .empty,
        };
    }

    /// Frees resources associated with the record.
    pub fn deinit(self: *Record) void {
        self.context.deinit();
        for (self.owned_strings.items) |s| {
            self.allocator.free(s);
        }
        self.owned_strings.deinit(self.allocator);
    }

    /// Sets the trace ID for distributed tracing.
    ///
    /// Arguments:
    ///     trace_id: The trace ID string.
    pub fn setTraceId(self: *Record, trace_id: []const u8) !void {
        const owned = try self.allocator.dupe(u8, trace_id);
        try self.owned_strings.append(self.allocator, owned);
        self.trace_id = owned;
    }

    /// Sets the span ID for distributed tracing.
    ///
    /// Arguments:
    ///     span_id: The span ID string.
    pub fn setSpanId(self: *Record, span_id: []const u8) !void {
        const owned = try self.allocator.dupe(u8, span_id);
        try self.owned_strings.append(self.allocator, owned);
        self.span_id = owned;
    }

    /// Sets the correlation ID for grouping related logs.
    ///
    /// Arguments:
    ///     correlation_id: The correlation ID string.
    pub fn setCorrelationId(self: *Record, correlation_id: []const u8) !void {
        const owned = try self.allocator.dupe(u8, correlation_id);
        try self.owned_strings.append(self.allocator, owned);
        self.correlation_id = owned;
    }

    /// Adds a context field to the record.
    ///
    /// Arguments:
    ///     key: The field name.
    ///     value: The field value.
    pub fn addField(self: *Record, key: []const u8, value: std.json.Value) !void {
        const owned_key = try self.allocator.dupe(u8, key);
        try self.owned_strings.append(self.allocator, owned_key);
        try self.context.put(owned_key, value);
    }

    /// Sets error information for error-level logs.
    ///
    /// Arguments:
    ///     name: Error name/type.
    ///     message: Error message.
    ///     stack_trace: Optional stack trace.
    ///     code: Optional error code.
    pub fn setError(
        self: *Record,
        name: []const u8,
        message: []const u8,
        stack_trace: ?[]const u8,
        code: ?i32,
    ) !void {
        const owned_name = try self.allocator.dupe(u8, name);
        try self.owned_strings.append(self.allocator, owned_name);

        const owned_message = try self.allocator.dupe(u8, message);
        try self.owned_strings.append(self.allocator, owned_message);

        var owned_stack: ?[]const u8 = null;
        if (stack_trace) |st| {
            owned_stack = try self.allocator.dupe(u8, st);
            try self.owned_strings.append(self.allocator, owned_stack.?);
        }

        self.error_info = .{
            .name = owned_name,
            .message = owned_message,
            .stack_trace = owned_stack,
            .code = code,
        };
    }

    /// Sets the duration for timing logs.
    ///
    /// Arguments:
    ///     duration_ns: Duration in nanoseconds.
    pub fn setDuration(self: *Record, duration_ns: u64) void {
        self.duration_ns = duration_ns;
    }

    /// Sets the duration from a timer start time.
    ///
    /// Arguments:
    ///     start_time: The start timestamp from std.time.Timer or nanoTimestamp.
    pub fn setDurationSince(self: *Record, start_time: i128) void {
        const now = std.time.nanoTimestamp();
        const duration = @as(u64, @intCast(@max(0, now - start_time)));
        self.duration_ns = duration;
    }

    /// Generates a unique trace ID.
    ///
    /// Arguments:
    ///     allocator: Allocator for the generated string.
    ///
    /// Returns:
    ///     A unique trace ID string (caller must free).
    pub fn generateTraceId(allocator: std.mem.Allocator) ![]u8 {
        var bytes: [16]u8 = undefined;
        std.crypto.random.bytes(&bytes);
        return try std.fmt.allocPrint(allocator, "{x}", .{std.fmt.fmtSliceHexLower(&bytes)});
    }

    /// Generates a unique span ID.
    ///
    /// Arguments:
    ///     allocator: Allocator for the generated string.
    ///
    /// Returns:
    ///     A unique span ID string (caller must free).
    pub fn generateSpanId(allocator: std.mem.Allocator) ![]u8 {
        var bytes: [8]u8 = undefined;
        std.crypto.random.bytes(&bytes);
        // Format as lowercase hex string
        var hex: [16]u8 = undefined;
        _ = std.fmt.bufPrint(&hex, "{x:0>16}", .{std.mem.readInt(u64, &bytes, .big)}) catch unreachable;
        return try allocator.dupe(u8, &hex);
    }

    /// Clones the record.
    ///
    /// Arguments:
    ///     allocator: Allocator for the cloned record.
    ///
    /// Returns:
    ///     A new Record that is a copy of this one.
    pub fn clone(self: *const Record, allocator: std.mem.Allocator) !Record {
        // Deep copy the message
        const owned_message = try allocator.dupe(u8, self.message);
        var new_record = Record.init(allocator, self.level, owned_message);
        try new_record.owned_strings.append(allocator, owned_message);

        new_record.timestamp = self.timestamp;
        new_record.line = self.line;
        new_record.column = self.column;
        new_record.thread_id = self.thread_id;
        new_record.duration_ns = self.duration_ns;

        // Deep copy optional strings
        if (self.module) |m| {
            const owned = try allocator.dupe(u8, m);
            try new_record.owned_strings.append(allocator, owned);
            new_record.module = owned;
        }
        if (self.function) |f| {
            const owned = try allocator.dupe(u8, f);
            try new_record.owned_strings.append(allocator, owned);
            new_record.function = owned;
        }
        if (self.filename) |f| {
            const owned = try allocator.dupe(u8, f);
            try new_record.owned_strings.append(allocator, owned);
            new_record.filename = owned;
        }
        if (self.custom_level_name) |n| {
            const owned = try allocator.dupe(u8, n);
            try new_record.owned_strings.append(allocator, owned);
            new_record.custom_level_name = owned;
        }
        if (self.custom_level_color) |c| {
            const owned = try allocator.dupe(u8, c);
            try new_record.owned_strings.append(allocator, owned);
            new_record.custom_level_color = owned;
        }

        if (self.trace_id) |tid| try new_record.setTraceId(tid);
        if (self.span_id) |sid| try new_record.setSpanId(sid);
        if (self.correlation_id) |cid| try new_record.setCorrelationId(cid);

        var it = self.context.iterator();
        while (it.next()) |entry| {
            try new_record.addField(entry.key_ptr.*, entry.value_ptr.*);
        }

        return new_record;
    }
};
