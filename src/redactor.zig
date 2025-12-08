const std = @import("std");
const Config = @import("config.zig").Config;

/// Redaction utilities for masking sensitive data in logs.
///
/// Provides pattern-based and field-based redaction to prevent
/// sensitive information from appearing in log output.
///
/// Callbacks:
/// - `on_redaction_applied`: Called when redaction is applied to a value
/// - `on_pattern_matched`: Called when a redaction pattern matches
/// - `on_redactor_initialized`: Called when redactor is created
/// - `on_redaction_error`: Called when redaction processing fails
///
/// Performance:
/// - O(n) pattern evaluation where n = number of patterns
/// - Early exit on first matching pattern
/// - Minimal memory overhead for pattern storage
pub const Redactor = struct {
    /// Redactor statistics for monitoring and diagnostics.
    pub const RedactorStats = struct {
        total_values_processed: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
        values_redacted: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
        patterns_matched: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
        fields_redacted: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
        redaction_errors: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),

        /// Calculate redaction rate (0.0 - 1.0)
        pub fn redactionRate(self: *const RedactorStats) f64 {
            const total = self.total_values_processed.load(.monotonic);
            if (total == 0) return 0;
            const redacted = self.values_redacted.load(.monotonic);
            return @as(f64, @floatFromInt(redacted)) / @as(f64, @floatFromInt(total));
        }

        /// Calculate error rate (0.0 - 1.0)
        pub fn errorRate(self: *const RedactorStats) f64 {
            const total = self.total_values_processed.load(.monotonic);
            if (total == 0) return 0;
            const errors = self.redaction_errors.load(.monotonic);
            return @as(f64, @floatFromInt(errors)) / @as(f64, @floatFromInt(total));
        }
    };

    allocator: std.mem.Allocator,
    patterns: std.ArrayList(RedactionPattern),
    fields: std.StringHashMap(RedactionType),
    stats: RedactorStats = .{},
    mutex: std.Thread.Mutex = .{},

    /// Callback invoked when redaction is applied.
    /// Parameters: (original_length: u64, redacted_length: u64, redaction_type: u32)
    on_redaction_applied: ?*const fn (u64, u64, u32) void = null,

    /// Callback invoked when a pattern matches.
    /// Parameters: (pattern_name: []const u8, matched_value: []const u8)
    on_pattern_matched: ?*const fn ([]const u8, []const u8) void = null,

    /// Callback invoked when redactor is initialized.
    /// Parameters: (stats: *const RedactorStats)
    on_redactor_initialized: ?*const fn (*const RedactorStats) void = null,

    /// Callback invoked on redaction error.
    /// Parameters: (error_msg: []const u8)
    on_redaction_error: ?*const fn ([]const u8) void = null,

    /// Pattern-based redaction configuration.
    pub const RedactionPattern = struct {
        name: []const u8,
        pattern_type: PatternType,
        pattern: []const u8,
        replacement: []const u8,

        pub const PatternType = enum {
            exact,
            prefix,
            suffix,
            contains,
            regex,
        };
    };

    /// Type of redaction to apply.
    pub const RedactionType = enum {
        full,
        partial_start,
        partial_end,
        hash,
        mask_middle,

        pub fn apply(self: RedactionType, allocator: std.mem.Allocator, value: []const u8) ![]u8 {
            return switch (self) {
                .full => try allocator.dupe(u8, "[REDACTED]"),
                .partial_start => blk: {
                    if (value.len <= 4) {
                        break :blk try allocator.dupe(u8, "****");
                    }
                    const result = try allocator.alloc(u8, value.len);
                    @memset(result[0 .. value.len - 4], '*');
                    @memcpy(result[value.len - 4 ..], value[value.len - 4 ..]);
                    break :blk result;
                },
                .partial_end => blk: {
                    if (value.len <= 4) {
                        break :blk try allocator.dupe(u8, "****");
                    }
                    const result = try allocator.alloc(u8, value.len);
                    @memcpy(result[0..4], value[0..4]);
                    @memset(result[4..], '*');
                    break :blk result;
                },
                .hash => blk: {
                    var hash: [32]u8 = undefined;
                    std.crypto.hash.sha2.Sha256.hash(value, &hash, .{});
                    const hex = try std.fmt.allocPrint(allocator, "[HASH:{s}]", .{&std.fmt.bytesToHex(hash[0..8], .lower)});
                    break :blk hex;
                },
                .mask_middle => blk: {
                    if (value.len <= 6) {
                        break :blk try allocator.dupe(u8, "***");
                    }
                    const result = try allocator.alloc(u8, value.len);
                    @memcpy(result[0..3], value[0..3]);
                    @memset(result[3 .. value.len - 3], '*');
                    @memcpy(result[value.len - 3 ..], value[value.len - 3 ..]);
                    break :blk result;
                },
            };
        }
    };

    /// Initializes a new Redactor instance.
    ///
    /// Arguments:
    ///     allocator: Memory allocator for internal storage.
    ///
    /// Returns:
    ///     A new Redactor instance.
    pub fn init(allocator: std.mem.Allocator) Redactor {
        return .{
            .allocator = allocator,
            .patterns = .empty,
            .fields = std.StringHashMap(RedactionType).init(allocator),
        };
    }

    /// Releases all resources associated with the redactor.
    pub fn deinit(self: *Redactor) void {
        for (self.patterns.items) |pattern| {
            self.allocator.free(pattern.name);
            self.allocator.free(pattern.pattern);
            self.allocator.free(pattern.replacement);
        }
        self.patterns.deinit(self.allocator);

        var it = self.fields.keyIterator();
        while (it.next()) |key| {
            self.allocator.free(key.*);
        }
        self.fields.deinit();
    }

    /// Sets the callback for redaction applied events.
    pub fn setRedactionAppliedCallback(self: *Redactor, callback: *const fn (u64, u64, u32) void) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.on_redaction_applied = callback;
    }

    /// Sets the callback for pattern matched events.
    pub fn setPatternMatchedCallback(self: *Redactor, callback: *const fn ([]const u8, []const u8) void) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.on_pattern_matched = callback;
    }

    /// Sets the callback for redactor initialization.
    pub fn setInitializedCallback(self: *Redactor, callback: *const fn (*const RedactorStats) void) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.on_redactor_initialized = callback;
    }

    /// Sets the callback for redaction errors.
    pub fn setErrorCallback(self: *Redactor, callback: *const fn ([]const u8) void) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.on_redaction_error = callback;
    }

    /// Returns redactor statistics.
    pub fn getStats(self: *Redactor) RedactorStats {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.stats;
    }

    /// Adds a sensitive field for redaction.
    ///
    /// Arguments:
    ///     field_name: The name of the field to redact.
    ///     redaction_type: The type of redaction to apply.
    pub fn addField(self: *Redactor, field_name: []const u8, redaction_type: RedactionType) !void {
        const owned_name = try self.allocator.dupe(u8, field_name);
        try self.fields.put(owned_name, redaction_type);
    }

    /// Adds a pattern-based redaction rule.
    ///
    /// Arguments:
    ///     name: A descriptive name for the pattern.
    ///     pattern_type: The type of pattern matching to use.
    ///     pattern: The pattern to match.
    ///     replacement: The replacement text.
    pub fn addPattern(
        self: *Redactor,
        name: []const u8,
        pattern_type: RedactionPattern.PatternType,
        pattern: []const u8,
        replacement: []const u8,
    ) !void {
        try self.patterns.append(self.allocator, .{
            .name = try self.allocator.dupe(u8, name),
            .pattern_type = pattern_type,
            .pattern = try self.allocator.dupe(u8, pattern),
            .replacement = try self.allocator.dupe(u8, replacement),
        });
    }

    /// Redacts sensitive data from a message.
    ///
    /// Arguments:
    ///     message: The message to redact.
    ///
    /// Returns:
    ///     The redacted message (caller must free).
    pub fn redact(self: *Redactor, message: []const u8) ![]u8 {
        var result = try self.allocator.dupe(u8, message);
        errdefer self.allocator.free(result);

        for (self.patterns.items) |pattern| {
            result = try self.applyPattern(result, pattern);
        }

        return result;
    }

    fn applyPattern(self: *Redactor, input: []u8, pattern: RedactionPattern) ![]u8 {
        switch (pattern.pattern_type) {
            .contains => {
                var result: std.ArrayList(u8) = .empty;
                defer result.deinit(self.allocator);

                var i: usize = 0;
                while (i < input.len) {
                    if (std.mem.indexOf(u8, input[i..], pattern.pattern)) |pos| {
                        try result.appendSlice(self.allocator, input[i .. i + pos]);
                        try result.appendSlice(self.allocator, pattern.replacement);
                        i = i + pos + pattern.pattern.len;
                    } else {
                        try result.appendSlice(self.allocator, input[i..]);
                        break;
                    }
                }

                self.allocator.free(input);
                return try result.toOwnedSlice(self.allocator);
            },
            .prefix => {
                if (std.mem.startsWith(u8, input, pattern.pattern)) {
                    const new_result = try self.allocator.alloc(
                        u8,
                        pattern.replacement.len + input.len - pattern.pattern.len,
                    );
                    @memcpy(new_result[0..pattern.replacement.len], pattern.replacement);
                    @memcpy(new_result[pattern.replacement.len..], input[pattern.pattern.len..]);
                    self.allocator.free(input);
                    return new_result;
                }
                return input;
            },
            .suffix => {
                if (std.mem.endsWith(u8, input, pattern.pattern)) {
                    const new_result = try self.allocator.alloc(
                        u8,
                        input.len - pattern.pattern.len + pattern.replacement.len,
                    );
                    @memcpy(new_result[0 .. input.len - pattern.pattern.len], input[0 .. input.len - pattern.pattern.len]);
                    @memcpy(new_result[input.len - pattern.pattern.len ..], pattern.replacement);
                    self.allocator.free(input);
                    return new_result;
                }
                return input;
            },
            .exact => {
                if (std.mem.eql(u8, input, pattern.pattern)) {
                    self.allocator.free(input);
                    return try self.allocator.dupe(u8, pattern.replacement);
                }
                return input;
            },
            .regex => {
                // Simple regex-like pattern matching for common cases
                // Supports: * (any chars), ? (single char), \d (digit), \w (word char), \s (whitespace)
                var result: std.ArrayList(u8) = .empty;
                defer result.deinit(self.allocator);

                var i: usize = 0;
                while (i < input.len) {
                    if (matchRegexPattern(input[i..], pattern.pattern)) |match_len| {
                        try result.appendSlice(self.allocator, pattern.replacement);
                        i += match_len;
                    } else {
                        try result.append(self.allocator, input[i]);
                        i += 1;
                    }
                }

                self.allocator.free(input);
                return try result.toOwnedSlice(self.allocator);
            },
        }
    }

    /// Checks if a field should be redacted.
    ///
    /// Arguments:
    ///     field_name: The name of the field to check.
    ///
    /// Returns:
    ///     The redaction type if the field should be redacted, null otherwise.
    pub fn getFieldRedaction(self: *const Redactor, field_name: []const u8) ?RedactionType {
        return self.fields.get(field_name);
    }
};

/// Simple regex-like pattern matching.
/// Supports: * (any chars), + (one or more), ? (optional), \d (digit), \w (word), \s (space)
fn matchRegexPattern(input: []const u8, pattern: []const u8) ?usize {
    var input_idx: usize = 0;
    var pattern_idx: usize = 0;

    while (pattern_idx < pattern.len) {
        // Handle escape sequences
        if (pattern[pattern_idx] == '\\' and pattern_idx + 1 < pattern.len) {
            const next = pattern[pattern_idx + 1];
            if (input_idx >= input.len) return null;

            const matches = switch (next) {
                'd' => std.ascii.isDigit(input[input_idx]),
                'w' => std.ascii.isAlphanumeric(input[input_idx]) or input[input_idx] == '_',
                's' => std.ascii.isWhitespace(input[input_idx]),
                'D' => !std.ascii.isDigit(input[input_idx]),
                'W' => !(std.ascii.isAlphanumeric(input[input_idx]) or input[input_idx] == '_'),
                'S' => !std.ascii.isWhitespace(input[input_idx]),
                else => input[input_idx] == next,
            };

            if (!matches) return null;
            input_idx += 1;
            pattern_idx += 2;
            continue;
        }

        // Handle wildcards
        if (pattern[pattern_idx] == '*') {
            // Match zero or more of any character
            if (pattern_idx + 1 >= pattern.len) {
                // * at end matches everything
                return input.len;
            }
            // Try to match rest of pattern starting at each position
            var try_idx = input_idx;
            while (try_idx <= input.len) {
                if (matchRegexPattern(input[try_idx..], pattern[pattern_idx + 1 ..])) |rest_len| {
                    return try_idx + rest_len;
                }
                try_idx += 1;
            }
            return null;
        }

        if (pattern[pattern_idx] == '+') {
            // Match one or more of previous pattern (simplified: any char)
            if (input_idx >= input.len) return null;
            input_idx += 1;
            while (input_idx < input.len and pattern_idx + 1 < pattern.len) {
                if (matchRegexPattern(input[input_idx..], pattern[pattern_idx + 1 ..])) |rest_len| {
                    return input_idx + rest_len;
                }
                input_idx += 1;
            }
            pattern_idx += 1;
            continue;
        }

        if (pattern[pattern_idx] == '.') {
            // Match any single character
            if (input_idx >= input.len) return null;
            input_idx += 1;
            pattern_idx += 1;
            continue;
        }

        // Literal match
        if (input_idx >= input.len) return null;
        if (input[input_idx] != pattern[pattern_idx]) return null;
        input_idx += 1;
        pattern_idx += 1;
    }

    return input_idx;
}

/// Pre-built redaction patterns for common sensitive data.
pub const RedactionPresets = struct {
    /// Creates a redactor with common sensitive data patterns.
    pub fn common(allocator: std.mem.Allocator) !Redactor {
        var redactor = Redactor.init(allocator);
        errdefer redactor.deinit();

        try redactor.addField("password", .full);
        try redactor.addField("secret", .full);
        try redactor.addField("api_key", .partial_end);
        try redactor.addField("token", .partial_end);
        try redactor.addField("credit_card", .mask_middle);
        try redactor.addField("ssn", .mask_middle);
        try redactor.addField("email", .partial_start);

        return redactor;
    }

    /// Creates a redactor for PCI-DSS compliance.
    pub fn pciDss(allocator: std.mem.Allocator) !Redactor {
        var redactor = Redactor.init(allocator);
        errdefer redactor.deinit();

        try redactor.addField("pan", .mask_middle);
        try redactor.addField("cvv", .full);
        try redactor.addField("pin", .full);
        try redactor.addField("card_number", .mask_middle);
        try redactor.addField("expiry", .full);

        return redactor;
    }

    /// Creates a redactor for HIPAA compliance.
    pub fn hipaa(allocator: std.mem.Allocator) !Redactor {
        var redactor = Redactor.init(allocator);
        errdefer redactor.deinit();

        try redactor.addField("patient_id", .hash);
        try redactor.addField("ssn", .full);
        try redactor.addField("dob", .full);
        try redactor.addField("address", .partial_end);
        try redactor.addField("phone", .partial_start);
        try redactor.addField("email", .partial_start);
        try redactor.addField("medical_record", .hash);

        return redactor;
    }
};

test "redactor field" {
    const result = try Redactor.RedactionType.partial_end.apply(std.testing.allocator, "secret123456");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("secr********", result);
}

test "redactor pattern" {
    var redactor = Redactor.init(std.testing.allocator);
    defer redactor.deinit();

    try redactor.addPattern("password_value", .contains, "password=secret123", "[REDACTED]");

    const result = try redactor.redact("user login password=secret123 success");
    defer std.testing.allocator.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, "secret") == null);
    try std.testing.expect(std.mem.indexOf(u8, result, "[REDACTED]") != null);
}
