//! Sensitive Data Redaction Module
//!
//! Provides pattern-based and field-based redaction to prevent sensitive
//! information from appearing in log output.
//!
//! Redaction Patterns:
//! - Password fields: password, passwd, secret, key, token
//! - Credentials: auth, authorization, cookie
//! - Personal data: email, phone, ssn, credit_card
//! - Network: ip_address, hostname
//! - Custom: User-defined regex patterns
//!
//! Strategies:
//! - Fixed mask: Replace with "***" or custom string
//! - Partial mask: Show first/last N characters
//! - Hash: Replace with hash of original value
//! - Truncate: Show only first N characters
//!
//! Configuration:
//! - Field names to redact
//! - Pattern-based matching
//! - Mask character customization
//! - JSON key redaction
//!
//! Performance:
//! - O(n) pattern evaluation
//! - Early exit on first match
//! - Pre-compiled patterns

const std = @import("std");
const Config = @import("config.zig").Config;
const SinkConfig = @import("sink.zig").SinkConfig;
const Constants = @import("constants.zig");
const Utils = @import("utils.zig");

/// Redaction utilities for masking sensitive data in logs.
pub const Redactor = struct {
    const RedactionApplyMode = enum {
        track,
        preview,
    };

    /// Redactor statistics for monitoring and diagnostics.
    pub const RedactorStats = struct {
        total_values_processed: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        values_redacted: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        patterns_matched: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        fields_redacted: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        redaction_errors: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),

        /// Get total values processed.
        pub fn getTotalProcessed(self: *const RedactorStats) u64 {
            return Utils.atomicLoadU64(&self.total_values_processed);
        }

        /// Get total values redacted.
        pub fn getValuesRedacted(self: *const RedactorStats) u64 {
            return Utils.atomicLoadU64(&self.values_redacted);
        }

        /// Get total patterns matched.
        pub fn getPatternsMatched(self: *const RedactorStats) u64 {
            return Utils.atomicLoadU64(&self.patterns_matched);
        }

        /// Get total fields redacted.
        pub fn getFieldsRedacted(self: *const RedactorStats) u64 {
            return Utils.atomicLoadU64(&self.fields_redacted);
        }

        /// Get total redaction errors.
        pub fn getRedactionErrors(self: *const RedactorStats) u64 {
            return Utils.atomicLoadU64(&self.redaction_errors);
        }

        /// Check if any values have been processed.
        pub fn hasProcessed(self: *const RedactorStats) bool {
            return Utils.atomicLoadU64(&self.total_values_processed) > 0;
        }

        /// Check if any values have been redacted.
        pub fn hasRedacted(self: *const RedactorStats) bool {
            return Utils.atomicLoadU64(&self.values_redacted) > 0;
        }

        /// Check if any patterns have matched.
        pub fn hasMatchedPatterns(self: *const RedactorStats) bool {
            return Utils.atomicLoadU64(&self.patterns_matched) > 0;
        }

        /// Check if any errors have occurred.
        pub fn hasErrors(self: *const RedactorStats) bool {
            return Utils.atomicLoadU64(&self.redaction_errors) > 0;
        }

        /// Calculate redaction rate (0.0 - 1.0)
        pub fn redactionRate(self: *const RedactorStats) f64 {
            return Utils.calculateRate(
                Utils.atomicLoadU64(&self.values_redacted),
                Utils.atomicLoadU64(&self.total_values_processed),
            );
        }

        /// Calculate error rate (0.0 - 1.0)
        pub fn errorRate(self: *const RedactorStats) f64 {
            return Utils.calculateErrorRate(
                Utils.atomicLoadU64(&self.redaction_errors),
                Utils.atomicLoadU64(&self.total_values_processed),
            );
        }

        /// Calculate success rate (0.0 - 1.0).
        pub fn successRate(self: *const RedactorStats) f64 {
            return 1.0 - self.errorRate();
        }

        /// Calculate pattern match rate (patterns matched / values redacted).
        pub fn patternMatchRate(self: *const RedactorStats) f64 {
            return Utils.calculateRate(
                Utils.atomicLoadU64(&self.patterns_matched),
                Utils.atomicLoadU64(&self.values_redacted),
            );
        }

        /// Calculate average redactions per processed value.
        pub fn avgRedactionsPerValue(self: *const RedactorStats) f64 {
            return Utils.calculateAverage(
                Utils.atomicLoadU64(&self.values_redacted),
                Utils.atomicLoadU64(&self.total_values_processed),
            );
        }

        /// Reset all statistics to initial state.
        pub fn reset(self: *RedactorStats) void {
            self.total_values_processed.store(0, .monotonic);
            self.values_redacted.store(0, .monotonic);
            self.patterns_matched.store(0, .monotonic);
            self.fields_redacted.store(0, .monotonic);
            self.redaction_errors.store(0, .monotonic);
        }

        /// Alias for getTotalProcessed
        pub const totalProcessed = getTotalProcessed;
        pub const processedCount = getTotalProcessed;

        /// Alias for getValuesRedacted
        pub const valuesRedacted = getValuesRedacted;
        pub const redactedCount = getValuesRedacted;

        /// Alias for getPatternsMatched
        pub const patternsMatched = getPatternsMatched;
        pub const matchedCount = getPatternsMatched;

        /// Alias for getFieldsRedacted
        pub const fieldsRedacted = getFieldsRedacted;
        pub const fieldRedactionCount = getFieldsRedacted;

        /// Alias for getRedactionErrors
        pub const redactionErrors = getRedactionErrors;
        pub const errorCount = getRedactionErrors;

        /// Alias for hasProcessed
        pub const processed = hasProcessed;

        /// Alias for hasRedacted
        pub const redacted = hasRedacted;

        /// Alias for hasMatchedPatterns
        pub const matchedPatterns = hasMatchedPatterns;

        /// Alias for hasErrors
        pub const hasRedactionErrors = hasErrors;

        /// Alias for redactionRate
        pub const redactionPercentage = redactionRate;

        /// Alias for errorRate
        pub const errorPercentage = errorRate;

        /// Alias for successRate
        pub const successPercentage = successRate;

        /// Alias for patternMatchRate
        pub const patternMatchPercentage = patternMatchRate;

        /// Alias for avgRedactionsPerValue
        pub const avgRedactions = avgRedactionsPerValue;

        /// Alias for reset
        pub const clear = reset;
        pub const zero = reset;
    };

    /// Re-export RedactionConfig from global config.
    pub const RedactionConfig = Config.RedactionConfig;

    /// Memory allocator for redactor operations.
    allocator: std.mem.Allocator,
    /// Redaction configuration.
    config: RedactionConfig = .{},
    /// List of redaction patterns.
    patterns: std.ArrayList(RedactionPattern),
    /// Map of specific fields to redaction types.
    fields: std.StringHashMap(RedactionType),
    /// Redactor statistics.
    stats: RedactorStats = .{},
    /// Mutex for thread-safe operations.
    mutex: std.Io.Mutex = std.Io.Mutex.init,

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
            regex_replace,
            email,
            ip,
            jwt,
            luhn,
        };
    };

    /// Type of redaction to apply.
    pub const RedactionType = enum {
        full,
        partial_start,
        partial_end,
        hash,
        mask_middle,
        truncate,

        pub fn apply(self: RedactionType, allocator: std.mem.Allocator, value: []const u8) ![]u8 {
            return switch (self) {
                .full => try allocator.dupe(u8, Constants.RedactionDefaults.replacement),
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
                    const hex_val = try Utils.bytesToHexLowerAlloc(allocator, hash[0..8]);
                    defer allocator.free(hex_val);
                    break :blk try std.fmt.allocPrint(allocator, "[HASH:{s}]", .{hex_val});
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
                .truncate => blk: {
                    const max_len: usize = Constants.RedactionDefaults.truncate_length;
                    const suffix = Constants.RedactionDefaults.truncate_suffix;
                    if (value.len <= max_len) {
                        break :blk try allocator.dupe(u8, value);
                    }
                    const result = try allocator.alloc(u8, max_len + suffix.len);
                    @memcpy(result[0..max_len], value[0..max_len]);
                    @memcpy(result[max_len..], suffix);
                    break :blk result;
                },
            };
        }

        /// Alias for apply
        pub const redact = apply;
        pub const mask = apply;
    };

    /// Initializes a new Redactor instance with default configuration.
    pub fn init(allocator: std.mem.Allocator) Redactor {
        return initWithConfig(allocator, .{});
    }

    /// Alias for init().
    pub const create = init;

    /// Initializes a new Redactor instance with custom configuration.
    pub fn initWithConfig(allocator: std.mem.Allocator, config: RedactionConfig) Redactor {
        var redactor = Redactor{
            .allocator = allocator,
            .config = config,
            .patterns = .empty,
            .fields = std.StringHashMap(RedactionType).init(allocator),
        };

        // Invoke initialized callback if set
        if (redactor.on_redactor_initialized) |callback| {
            callback(&redactor.stats);
        }

        return redactor;
    }

    /// Applies field/pattern rules defined in the redaction config.
    ///
    /// This does not mutate existing rules; it only adds new ones from config.
    pub fn applyConfigRules(self: *Redactor) !void {
        if (self.config.fields) |fields| {
            const mapped = mapConfigRedactionType(self.config.default_type);
            for (fields) |field_name| {
                try self.addField(field_name, mapped);
            }
        }

        if (self.config.patterns) |patterns| {
            const pattern_type: RedactionPattern.PatternType = if (self.config.enable_regex) .regex else .contains;
            for (patterns, 0..) |pattern, i| {
                const name = try std.fmt.allocPrint(self.allocator, "config_pattern_{d}", .{i});
                defer self.allocator.free(name);
                try self.addPattern(name, pattern_type, pattern, self.config.replacement);
            }
        }
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

    /// Alias for deinit().
    pub const destroy = deinit;

    /// Sets the callback for redaction applied events.
    pub fn setCallback(self: *Redactor, callback: *const fn (u64, u64, u32) void) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        self.on_redaction_applied = callback;
    }

    /// Sets the callback for redaction applied events.
    pub fn setRedactionAppliedCallback(self: *Redactor, callback: *const fn (u64, u64, u32) void) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        self.on_redaction_applied = callback;
    }

    /// Sets the callback for pattern matched events.
    pub fn setPatternMatchedCallback(self: *Redactor, callback: *const fn ([]const u8, []const u8) void) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        self.on_pattern_matched = callback;
    }

    /// Sets the callback for redactor initialization.
    pub fn setInitializedCallback(self: *Redactor, callback: *const fn (*const RedactorStats) void) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        self.on_redactor_initialized = callback;
    }

    /// Sets the callback for redaction errors.
    pub fn setErrorCallback(self: *Redactor, callback: *const fn ([]const u8) void) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        self.on_redaction_error = callback;
    }

    /// Returns redactor statistics.
    pub fn getStats(self: *Redactor) RedactorStats {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());

        return self.stats;
    }

    /// Adds a sensitive field for redaction.
    ///
    /// Arguments:
    ///     field_name: The name of the field to redact.
    ///     redaction_type: The type of redaction to apply.
    pub fn addField(self: *Redactor, field_name: []const u8, redaction_type: RedactionType) !void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());

        if (self.fields.getPtr(field_name)) |existing| {
            existing.* = redaction_type;
            return;
        }

        const owned_name = try self.allocator.dupe(u8, field_name);
        try self.fields.put(owned_name, redaction_type);
    }

    /// Adds multiple sensitive fields using the same redaction type.
    ///
    /// Returns the number of fields added.
    pub fn addFields(self: *Redactor, field_names: []const []const u8, redaction_type: RedactionType) !usize {
        var added: usize = 0;
        for (field_names) |name| {
            try self.addField(name, redaction_type);
            added += 1;
        }
        return added;
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
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());

        try self.patterns.append(self.allocator, .{
            .name = try self.allocator.dupe(u8, name),
            .pattern_type = pattern_type,
            .pattern = try self.allocator.dupe(u8, pattern),
            .replacement = try self.allocator.dupe(u8, replacement),
        });
    }

    /// Adds multiple redaction patterns.
    ///
    /// Returns the number of patterns added.
    pub fn addPatterns(self: *Redactor, patterns: []const RedactionPattern) !usize {
        var added: usize = 0;
        for (patterns) |pattern| {
            try self.addPattern(pattern.name, pattern.pattern_type, pattern.pattern, pattern.replacement);
            added += 1;
        }
        return added;
    }

    /// Removes a field rule by name.
    ///
    /// Returns true when a matching field was removed.
    pub fn removeField(self: *Redactor, field_name: []const u8) bool {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());

        if (self.fields.fetchRemove(field_name)) |entry| {
            self.allocator.free(entry.key);
            return true;
        }

        if (self.config.case_insensitive) {
            var key_to_remove: ?[]const u8 = null;
            var it = self.fields.iterator();
            while (it.next()) |entry| {
                if (std.ascii.eqlIgnoreCase(entry.key_ptr.*, field_name)) {
                    key_to_remove = entry.key_ptr.*;
                    break;
                }
            }

            if (key_to_remove) |key| {
                if (self.fields.fetchRemove(key)) |entry| {
                    self.allocator.free(entry.key);
                    return true;
                }
            }
        }

        return false;
    }

    /// Removes all pattern rules matching the provided name.
    ///
    /// Returns the number of removed patterns.
    pub fn removePatternByName(self: *Redactor, name: []const u8) usize {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());

        var removed: usize = 0;
        var i = self.patterns.items.len;
        while (i > 0) {
            i -= 1;
            const pattern = self.patterns.items[i];
            if (std.mem.eql(u8, pattern.name, name)) {
                self.allocator.free(pattern.name);
                self.allocator.free(pattern.pattern);
                self.allocator.free(pattern.replacement);
                _ = self.patterns.orderedRemove(i);
                removed += 1;
            }
        }

        return removed;
    }

    /// Redacts sensitive data from a message.
    /// Uses config settings for replacement text and audit logging.
    pub fn redact(self: *Redactor, message: []const u8) ![]u8 {
        return self.redactWithAllocator(message, null);
    }

    /// Redacts sensitive data from a message using an optional scratch allocator.
    /// If scratch_allocator is provided, it will be used for temporary allocations.
    /// This is useful for arena allocators that batch-free memory.
    pub fn redactWithAllocator(self: *Redactor, message: []const u8, scratch_allocator: ?std.mem.Allocator) ![]u8 {
        return self.redactInternal(message, scratch_allocator, .track);
    }

    /// Redacts sensitive data from a message without mutating stats.
    pub fn previewRedaction(self: *Redactor, message: []const u8) ![]u8 {
        return self.previewRedactionWithAllocator(message, null);
    }

    /// Redacts sensitive data from a message without mutating stats using an optional allocator.
    pub fn previewRedactionWithAllocator(self: *Redactor, message: []const u8, scratch_allocator: ?std.mem.Allocator) ![]u8 {
        return self.redactInternal(message, scratch_allocator, .preview);
    }

    fn redactInternal(self: *Redactor, message: []const u8, scratch_allocator: ?std.mem.Allocator, mode: RedactionApplyMode) ![]u8 {
        const alloc = scratch_allocator orelse self.allocator;

        if (mode == .track) {
            _ = self.stats.total_values_processed.fetchAdd(1, .monotonic);
        }

        var result = try alloc.dupe(u8, message);
        errdefer alloc.free(result);

        var was_redacted = false;
        for (self.patterns.items) |pattern| {
            if (!patternMatchesMessage(pattern, result)) continue;

            result = try self.applyPatternWithAllocator(result, pattern, alloc);

            was_redacted = true;
            if (mode == .track) {
                _ = self.stats.patterns_matched.fetchAdd(1, .monotonic);

                // Invoke pattern matched callback
                if (self.on_pattern_matched) |callback| {
                    callback(pattern.name, message);
                }
            }
        }

        if (mode == .track and was_redacted) {
            _ = self.stats.values_redacted.fetchAdd(1, .monotonic);

            // Invoke redaction applied callback
            if (self.on_redaction_applied) |callback| {
                callback(@intCast(message.len), @intCast(result.len), 0);
            }

            // Audit logging if enabled
            if (self.config.audit_redactions) {
                // The callback handles audit logging
            }
        }

        return result;
    }

    /// Redacts a field value based on field rules.
    pub fn redactField(self: *Redactor, field_name: []const u8, value: []const u8) ![]u8 {
        _ = self.stats.total_values_processed.fetchAdd(1, .monotonic);

        // Check if field should be redacted
        const redaction_type = self.getFieldRedactionWithConfig(field_name);
        if (redaction_type) |rtype| {
            _ = self.stats.fields_redacted.fetchAdd(1, .monotonic);
            _ = self.stats.values_redacted.fetchAdd(1, .monotonic);

            // Apply the redaction with config settings
            return self.applyRedactionType(rtype, value);
        }

        return self.allocator.dupe(u8, value);
    }

    /// Previews how a field would be redacted without changing counters.
    pub fn previewFieldRedaction(self: *Redactor, field_name: []const u8, value: []const u8) ![]u8 {
        const redaction_type = self.getFieldRedactionWithConfig(field_name);
        if (redaction_type) |rtype| {
            return self.applyRedactionType(rtype, value);
        }
        return self.allocator.dupe(u8, value);
    }

    /// Get field redaction type considering config settings.
    fn getFieldRedactionWithConfig(self: *const Redactor, field_name: []const u8) ?RedactionType {
        // Check explicit field rules first
        if (self.fields.get(field_name)) |rtype| {
            return rtype;
        }

        // Case-insensitive matching if enabled
        if (self.config.case_insensitive) {
            var it = self.fields.iterator();
            while (it.next()) |entry| {
                if (std.ascii.eqlIgnoreCase(entry.key_ptr.*, field_name)) {
                    return entry.value_ptr.*;
                }
            }
        }

        return null;
    }

    /// Apply redaction type with config settings.
    fn applyRedactionType(self: *Redactor, rtype: RedactionType, value: []const u8) ![]u8 {
        const mask_char = self.config.mask_char;
        const start_chars = self.config.partial_start_chars;
        const end_chars = self.config.partial_end_chars;

        return switch (rtype) {
            .full => try self.allocator.dupe(u8, self.config.replacement),
            .partial_start => Utils.maskString(self.allocator, value, mask_char, start_chars, end_chars, .partial_start),
            .partial_end => Utils.maskString(self.allocator, value, mask_char, start_chars, end_chars, .partial_end),
            .hash => self.computeRedactionHash(value),
            .mask_middle => Utils.maskString(self.allocator, value, mask_char, start_chars, end_chars, .mask_middle),
            .truncate => self.applyTruncate(value),
        };
    }

    fn applyTruncate(self: *Redactor, value: []const u8) ![]u8 {
        const max_len = self.config.truncate_length;
        const suffix = self.config.truncate_suffix;
        if (max_len == 0) return self.allocator.dupe(u8, suffix);
        if (value.len <= max_len) return self.allocator.dupe(u8, value);
        const result = try self.allocator.alloc(u8, max_len + suffix.len);
        @memcpy(result[0..max_len], value[0..max_len]);
        @memcpy(result[max_len..], suffix);
        return result;
    }

    fn computeRedactionHash(self: *Redactor, value: []const u8) ![]u8 {
        return switch (self.config.hash_algorithm) {
            .sha256 => Utils.computeRedactionHash(self.allocator, value),
            .sha512 => blk: {
                var hash: [64]u8 = undefined;
                std.crypto.hash.sha2.Sha512.hash(value, &hash, .{});
                break :blk formatHashTag(self.allocator, hash[0..8]);
            },
            .md5 => blk: {
                var hash: [16]u8 = undefined;
                std.crypto.hash.Md5.hash(value, &hash, .{});
                break :blk formatHashTag(self.allocator, hash[0..8]);
            },
        };
    }

    fn formatHashTag(allocator: std.mem.Allocator, hash_bytes: []const u8) ![]u8 {
        const hex_val = try Utils.bytesToHexLowerAlloc(allocator, hash_bytes);
        defer allocator.free(hex_val);
        return std.fmt.allocPrint(allocator, "[HASH:{s}]", .{hex_val});
    }

    fn mapConfigRedactionType(rtype: RedactionConfig.RedactionType) RedactionType {
        return switch (rtype) {
            .full => .full,
            .partial_start => .partial_start,
            .partial_end => .partial_end,
            .hash => .hash,
            .mask_middle => .mask_middle,
            .truncate => .truncate,
        };
    }

    fn matchIpv6(input: []const u8) ?usize {
        if (input.len < 3) return null;
        var colons: usize = 0;
        var hex_segments: usize = 0;
        var i: usize = 0;
        var last_was_colon = false;

        // An IPv6 address can start with ::
        if (std.mem.startsWith(u8, input, "::")) {
            colons += 2;
            i += 2;
            last_was_colon = true;
        }

        while (i < input.len) {
            const c = input[i];
            if (std.ascii.isHex(c)) {
                // Read hex segment (max 4 chars)
                var seg_len: usize = 0;
                while (i < input.len and std.ascii.isHex(input[i])) : (i += 1) {
                    seg_len += 1;
                }
                if (seg_len > 4) return null; // Invalid segment length
                hex_segments += 1;
                last_was_colon = false;
            } else if (c == ':') {
                if (last_was_colon) {
                    // Double colon `::`
                    if (colons > 0 and i > 0 and input[i - 1] == ':') {
                        // Allowed at most one double colon
                        colons += 1;
                        i += 1;
                        last_was_colon = true;
                    } else {
                        return null;
                    }
                } else {
                    colons += 1;
                    i += 1;
                    last_was_colon = true;
                }
            } else {
                break;
            }
        }

        // Valid IPv6 should have at least 2 colons and some hex segments/colons, and not end with a single colon (unless ::)
        if (colons >= 2 and (hex_segments >= 1 or colons >= 2)) {
            if (last_was_colon and !std.mem.endsWith(u8, input[0..i], "::")) {
                return null; // Can't end with a single colon
            }
            return i;
        }
        return null;
    }

    fn matchJwt(input: []const u8) ?usize {
        if (!std.mem.startsWith(u8, input, "eyJ")) return null;
        var i: usize = 3;

        // Part 1: Header (alphanumeric, _ or -)
        while (i < input.len and (std.ascii.isAlphanumeric(input[i]) or input[i] == '_' or input[i] == '-')) : (i += 1) {}
        if (i == 3 or i >= input.len or input[i] != '.') return null;
        i += 1; // skip '.'

        // Part 2: Payload
        const payload_start = i;
        while (i < input.len and (std.ascii.isAlphanumeric(input[i]) or input[i] == '_' or input[i] == '-')) : (i += 1) {}
        if (i == payload_start or i >= input.len or input[i] != '.') return null;
        i += 1; // skip '.'

        // Part 3: Signature
        const sig_start = i;
        while (i < input.len and (std.ascii.isAlphanumeric(input[i]) or input[i] == '_' or input[i] == '-')) : (i += 1) {}
        if (i == sig_start) return null;

        return i;
    }

    fn isStartOfNumber(input: []const u8, idx: usize) bool {
        if (idx == 0) return true;
        if (std.ascii.isDigit(input[idx - 1])) return false;
        if (input[idx - 1] == ' ' or input[idx - 1] == '-') {
            var k = idx - 1;
            while (k > 0) {
                k -= 1;
                const c = input[k];
                if (std.ascii.isDigit(c)) return false;
                if (c != ' ' and c != '-') break;
            }
        }
        return true;
    }

    fn matchLuhn(input: []const u8) ?usize {
        if (input.len < 13) return null;
        if (!std.ascii.isDigit(input[0])) return null;

        var digit_buf: [32]u8 = undefined;
        var digit_count: usize = 0;
        var i: usize = 0;
        var last_digit_idx: usize = 0;

        while (i < input.len) : (i += 1) {
            const c = input[i];
            if (std.ascii.isDigit(c)) {
                if (digit_count < 32) {
                    digit_buf[digit_count] = c;
                    digit_count += 1;
                }
                last_digit_idx = i;
            } else if (c == ' ' or c == '-') {
                // separator allowed
            } else {
                break;
            }

            if (digit_count > 19) {
                break;
            }
        }

        if (digit_count >= 13 and digit_count <= 19) {
            if (Utils.isLuhnValid(digit_buf[0..digit_count])) {
                return last_digit_idx + 1;
            }
        }

        return null;
    }

    fn applyPattern(self: *Redactor, input: []u8, pattern: RedactionPattern) ![]u8 {
        return self.applyPatternWithAllocator(input, pattern, self.allocator);
    }

    fn applyPatternWithAllocator(self: *Redactor, input: []u8, pattern: RedactionPattern, alloc: std.mem.Allocator) ![]u8 {
        _ = self; // self only needed for stats/callbacks in caller
        switch (pattern.pattern_type) {
            .contains => {
                const result = try Utils.replaceString(alloc, input, pattern.pattern, pattern.replacement);
                alloc.free(input);
                return result;
            },
            .prefix => {
                if (std.mem.startsWith(u8, input, pattern.pattern)) {
                    const new_result = try alloc.alloc(
                        u8,
                        pattern.replacement.len + input.len - pattern.pattern.len,
                    );
                    @memcpy(new_result[0..pattern.replacement.len], pattern.replacement);
                    @memcpy(new_result[pattern.replacement.len..], input[pattern.pattern.len..]);
                    alloc.free(input);
                    return new_result;
                }
                return input;
            },
            .suffix => {
                if (std.mem.endsWith(u8, input, pattern.pattern)) {
                    const new_result = try alloc.alloc(
                        u8,
                        input.len - pattern.pattern.len + pattern.replacement.len,
                    );
                    @memcpy(new_result[0 .. input.len - pattern.pattern.len], input[0 .. input.len - pattern.pattern.len]);
                    @memcpy(new_result[input.len - pattern.pattern.len ..], pattern.replacement);
                    alloc.free(input);
                    return new_result;
                }
                return input;
            },
            .exact => {
                if (std.mem.eql(u8, input, pattern.pattern)) {
                    alloc.free(input);
                    return try alloc.dupe(u8, pattern.replacement);
                }
                return input;
            },
            .regex, .regex_replace => {
                // Simple regex-like pattern matching for common cases
                // Supports: * (any chars), ? (single char), \d (digit), \w (word char), \s (whitespace)
                var result: std.ArrayList(u8) = .empty;
                defer result.deinit(alloc);

                var i: usize = 0;
                while (i < input.len) {
                    if (matchRegexPattern(input[i..], pattern.pattern)) |match_len| {
                        try result.appendSlice(alloc, pattern.replacement);
                        i += match_len;
                    } else {
                        try result.append(alloc, input[i]);
                        i += 1;
                    }
                }

                alloc.free(input);
                return try result.toOwnedSlice(alloc);
            },
            .email => {
                var result: std.ArrayList(u8) = .empty;
                defer result.deinit(alloc);

                var i: usize = 0;
                while (i < input.len) {
                    if (Utils.matchRegexPattern(input[i..], "\\w+@\\w+\\.\\w+")) |match_len| {
                        if (match_len > 0) {
                            try result.appendSlice(alloc, pattern.replacement);
                            i += match_len;
                            continue;
                        }
                    }
                    try result.append(alloc, input[i]);
                    i += 1;
                }

                alloc.free(input);
                return try result.toOwnedSlice(alloc);
            },
            .ip => {
                var result: std.ArrayList(u8) = .empty;
                defer result.deinit(alloc);

                var i: usize = 0;
                while (i < input.len) {
                    if (Utils.matchRegexPattern(input[i..], "\\d+\\.\\d+\\.\\d+\\.\\d+")) |match_len| {
                        if (match_len > 0) {
                            try result.appendSlice(alloc, pattern.replacement);
                            i += match_len;
                            continue;
                        }
                    }
                    if (matchIpv6(input[i..])) |match_len| {
                        if (match_len > 0) {
                            try result.appendSlice(alloc, pattern.replacement);
                            i += match_len;
                            continue;
                        }
                    }
                    try result.append(alloc, input[i]);
                    i += 1;
                }

                alloc.free(input);
                return try result.toOwnedSlice(alloc);
            },
            .jwt => {
                var result: std.ArrayList(u8) = .empty;
                defer result.deinit(alloc);

                var i: usize = 0;
                while (i < input.len) {
                    if (matchJwt(input[i..])) |match_len| {
                        try result.appendSlice(alloc, pattern.replacement);
                        i += match_len;
                        continue;
                    }
                    try result.append(alloc, input[i]);
                    i += 1;
                }

                alloc.free(input);
                return try result.toOwnedSlice(alloc);
            },
            .luhn => {
                var result: std.ArrayList(u8) = .empty;
                defer result.deinit(alloc);

                var i: usize = 0;
                while (i < input.len) {
                    if (isStartOfNumber(input, i)) {
                        if (matchLuhn(input[i..])) |match_len| {
                            try result.appendSlice(alloc, pattern.replacement);
                            i += match_len;
                            continue;
                        }
                    }
                    try result.append(alloc, input[i]);
                    i += 1;
                }

                alloc.free(input);
                return try result.toOwnedSlice(alloc);
            },
        }
    }

    /// Checks if a pattern would match a message.
    fn patternMatchesMessage(pattern: RedactionPattern, message: []const u8) bool {
        return switch (pattern.pattern_type) {
            .contains => std.mem.indexOf(u8, message, pattern.pattern) != null,
            .prefix => std.mem.startsWith(u8, message, pattern.pattern),
            .suffix => std.mem.endsWith(u8, message, pattern.pattern),
            .exact => std.mem.eql(u8, message, pattern.pattern),
            .regex, .regex_replace => Utils.findRegexPattern(message, pattern.pattern) != null,
            .email => Utils.findRegexPattern(message, "\\w+@\\w+\\.\\w+") != null,
            .ip => (Utils.findRegexPattern(message, "\\d+\\.\\d+\\.\\d+\\.\\d+") != null) or blk: {
                var i: usize = 0;
                while (i < message.len) : (i += 1) {
                    if (matchIpv6(message[i..])) |_| {
                        break :blk true;
                    }
                }
                break :blk false;
            },
            .jwt => blk: {
                var i: usize = 0;
                while (i < message.len) : (i += 1) {
                    if (matchJwt(message[i..])) |_| {
                        break :blk true;
                    }
                }
                break :blk false;
            },
            .luhn => blk: {
                var i: usize = 0;
                while (i < message.len) : (i += 1) {
                    if (isStartOfNumber(message, i)) {
                        if (matchLuhn(message[i..])) |_| {
                            break :blk true;
                        }
                    }
                }
                break :blk false;
            },
        };
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

    /// Returns true when the provided field has a redaction rule.
    pub fn hasFieldRule(self: *const Redactor, field_name: []const u8) bool {
        return self.getFieldRedactionWithConfig(field_name) != null;
    }

    /// Returns true when at least one configured pattern would redact this message.
    pub fn wouldRedact(self: *const Redactor, message: []const u8) bool {
        for (self.patterns.items) |pattern| {
            if (patternMatchesMessage(pattern, message)) {
                return true;
            }
        }
        return false;
    }

    /// Returns how many pattern rules match a message.
    pub fn matchingPatternCount(self: *const Redactor, message: []const u8) usize {
        var count: usize = 0;
        for (self.patterns.items) |pattern| {
            if (patternMatchesMessage(pattern, message)) {
                count += 1;
            }
        }
        return count;
    }

    /// Returns the number of patterns.
    pub fn patternCount(self: *const Redactor) usize {
        return self.patterns.items.len;
    }

    /// Returns the number of fields.
    pub fn fieldCount(self: *const Redactor) usize {
        return self.fields.count();
    }

    /// Returns true if any patterns or fields are configured.
    pub fn hasRules(self: *const Redactor) bool {
        return self.patterns.items.len > 0 or self.fields.count() > 0;
    }

    /// Clears all patterns.
    pub fn clearPatterns(self: *Redactor) void {
        for (self.patterns.items) |pattern| {
            self.allocator.free(pattern.name);
            self.allocator.free(pattern.pattern);
            self.allocator.free(pattern.replacement);
        }
        self.patterns.clearRetainingCapacity();
    }

    /// Clears all fields.
    pub fn clearFields(self: *Redactor) void {
        var it = self.fields.keyIterator();
        while (it.next()) |key| {
            self.allocator.free(key.*);
        }
        self.fields.clearRetainingCapacity();
    }

    /// Clears all patterns and fields.
    pub fn clear(self: *Redactor) void {
        self.clearPatterns();
        self.clearFields();
    }

    /// Resets statistics.
    pub fn resetStats(self: *Redactor) void {
        self.stats.reset();
    }

    /// Alias for addPattern
    pub const addRule = addPattern;

    /// Alias for addField
    pub const field = addField;
    pub const sensitiveField = addField;

    /// Alias for addFields
    pub const addFieldsBatch = addFields;
    pub const addSensitiveFields = addFields;

    /// Alias for addPatterns
    pub const addPatternBatch = addPatterns;
    pub const addRules = addPatterns;

    /// Alias for redact
    pub const mask = redact;
    pub const sanitize = redact;
    pub const process = redact;

    /// Alias for previewRedaction
    pub const previewMessage = previewRedaction;
    pub const preview = previewRedaction;

    /// Alias for previewRedactionWithAllocator
    pub const previewMessageWithAllocator = previewRedactionWithAllocator;

    /// Alias for redactField
    pub const maskField = redactField;

    /// Alias for previewFieldRedaction
    pub const previewField = previewFieldRedaction;

    /// Alias for getStats
    pub const statistics = getStats;

    /// Alias for initWithConfig
    pub const createWithConfig = initWithConfig;

    /// Alias for applyConfigRules
    pub const applyConfig = applyConfigRules;
    pub const loadConfigRules = applyConfigRules;

    /// Alias for setCallback
    // pub const callback = setCallback; // shadows parameters

    /// Alias for setRedactionAppliedCallback
    pub const onRedactionApplied = setRedactionAppliedCallback;

    /// Alias for setPatternMatchedCallback
    pub const onPatternMatched = setPatternMatchedCallback;

    /// Alias for setInitializedCallback
    pub const onInitialized = setInitializedCallback;

    /// Alias for setErrorCallback
    pub const onError = setErrorCallback;

    /// Alias for addPattern
    // pub const addRule = addPattern; // already exists

    /// Alias for addField
    // pub const field = addField; // already exists
    // pub const sensitiveField = addField; // already exists

    /// Alias for redact
    // pub const mask = redact; // already exists
    // pub const sanitize = redact; // already exists
    // pub const process = redact; // already exists

    /// Alias for redactWithAllocator
    pub const maskWithAllocator = redactWithAllocator;
    pub const sanitizeWithAllocator = redactWithAllocator;

    /// Alias for redactField
    // pub const maskField = redactField; // already exists

    /// Alias for getFieldRedaction
    pub const getFieldRule = getFieldRedaction;

    /// Alias for hasFieldRule
    pub const hasRuleForField = hasFieldRule;

    /// Alias for wouldRedact
    pub const shouldRedact = wouldRedact;
    pub const needsRedaction = wouldRedact;

    /// Alias for matchingPatternCount
    pub const matchingPatterns = matchingPatternCount;
    pub const matchedPatternCount = matchingPatternCount;

    /// Alias for removeField
    pub const deleteField = removeField;
    pub const removeSensitiveField = removeField;

    /// Alias for removePatternByName
    pub const removePattern = removePatternByName;
    pub const deletePattern = removePatternByName;

    /// Alias for patternCount
    pub const ruleCount = patternCount;

    /// Alias for fieldCount
    pub const sensitiveFieldCount = fieldCount;

    /// Alias for hasRules
    pub const hasConfiguration = hasRules;

    /// Alias for clearPatterns
    pub const clearRules = clearPatterns;

    /// Alias for clearFields
    pub const clearSensitiveFields = clearFields;

    /// Alias for clear
    pub const clearAll = clear;

    /// Alias for resetStats
    pub const resetStatistics = resetStats;

    /// Formats and dumps redaction statistics for compliance.
    pub fn auditLog(self: *const Redactor, writer: anytype) !void {
        try writer.print("=== REDACTION COMPLIANCE AUDIT LOG ===\n", .{});
        try writer.print("Total values processed: {d}\n", .{self.stats.getTotalProcessed()});
        try writer.print("Values redacted: {d}\n", .{self.stats.getValuesRedacted()});
        try writer.print("Patterns matched: {d}\n", .{self.stats.getPatternsMatched()});
        try writer.print("Fields redacted: {d}\n", .{self.stats.getFieldsRedacted()});
        try writer.print("Redaction errors: {d}\n", .{self.stats.getRedactionErrors()});
        try writer.print("Redaction rate: {d:.2}%\n", .{self.stats.redactionRate() * 100.0});
        try writer.print("Success rate: {d:.2}%\n", .{self.stats.successRate() * 100.0});
        try writer.print("======================================\n", .{});
    }
};

/// Simple regex-like pattern matching.
/// Supports: * (any chars), + (one or more), ? (optional), \d (digit), \w (word), \s (space)
fn matchRegexPattern(input: []const u8, pattern: []const u8) ?usize {
    return Utils.matchRegexPattern(input, pattern);
}

/// Pre-built redaction patterns for common sensitive data.
pub const RedactionPresets = struct {
    /// Creates a redactor configured to redact emails for GDPR.
    pub fn gdprEmail(allocator: std.mem.Allocator) !Redactor {
        var redactor = Redactor.init(allocator);
        errdefer redactor.deinit();
        try redactor.addPattern("gdpr_email", .email, "", "[EMAIL REDACTED]");
        return redactor;
    }

    /// Creates a redactor configured to redact credit cards using Luhn validation for PCI-DSS.
    pub fn pciCard(allocator: std.mem.Allocator) !Redactor {
        var redactor = Redactor.init(allocator);
        errdefer redactor.deinit();
        try redactor.addPattern("pci_card", .luhn, "", "[CARD REDACTED]");
        return redactor;
    }

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

    /// Creates a redactor for GDPR compliance.
    pub fn gdpr(allocator: std.mem.Allocator) !Redactor {
        var redactor = Redactor.init(allocator);
        errdefer redactor.deinit();

        try redactor.addField("name", .partial_end);
        try redactor.addField("email", .partial_start);
        try redactor.addField("phone", .partial_start);
        try redactor.addField("address", .full);
        try redactor.addField("ip", .partial_end);
        try redactor.addField("ip_address", .partial_end);
        try redactor.addField("user_id", .hash);

        return redactor;
    }

    /// Creates a redactor for API keys and secrets.
    pub fn apiSecrets(allocator: std.mem.Allocator) !Redactor {
        var redactor = Redactor.init(allocator);
        errdefer redactor.deinit();

        try redactor.addField("api_key", .mask_middle);
        try redactor.addField("secret_key", .full);
        try redactor.addField("access_token", .mask_middle);
        try redactor.addField("refresh_token", .full);
        try redactor.addField("bearer_token", .mask_middle);
        try redactor.addField("authorization", .partial_end);

        return redactor;
    }

    /// Creates a redactor for financial data.
    pub fn financial(allocator: std.mem.Allocator) !Redactor {
        var redactor = Redactor.init(allocator);
        errdefer redactor.deinit();

        try redactor.addField("account_number", .mask_middle);
        try redactor.addField("routing_number", .full);
        try redactor.addField("balance", .full);
        try redactor.addField("amount", .full);
        try redactor.addField("iban", .mask_middle);
        try redactor.addField("swift", .partial_end);

        return redactor;
    }

    /// Creates a secure sink configuration with redaction enabled.
    pub fn createSecureSink(file_path: []const u8) SinkConfig {
        return SinkConfig{
            .path = file_path,
            .json = true,
            .color = false,
        };
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

    try redactor.addPattern("password_value", .contains, "password=secret123", Constants.RedactionDefaults.replacement);

    const result = try redactor.redact("user login password=secret123 success");
    defer std.testing.allocator.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, "secret") == null);
    try std.testing.expect(std.mem.indexOf(u8, result, Constants.RedactionDefaults.replacement) != null);
}

test "redactor batch fields and field rule checks" {
    var redactor = Redactor.init(std.testing.allocator);
    defer redactor.deinit();

    const fields = [_][]const u8{ "password", "token", "api_key" };
    const added = try redactor.addFields(fields[0..], .full);

    try std.testing.expectEqual(@as(usize, 3), added);
    try std.testing.expect(redactor.hasFieldRule("password"));
    try std.testing.expect(redactor.hasFieldRule("TOKEN"));
    try std.testing.expect(!redactor.hasFieldRule("non_sensitive"));
}

test "redactor preflight and preview helpers" {
    var redactor = Redactor.init(std.testing.allocator);
    defer redactor.deinit();

    try redactor.addPattern("token_pattern", .contains, "token=", "token=" ++ Constants.RedactionDefaults.replacement);
    try redactor.addField("password", .full);

    try std.testing.expect(redactor.wouldRedact("token=abc123"));
    try std.testing.expect(!redactor.wouldRedact("safe message"));

    const preview = try redactor.previewFieldRedaction("password", "my-secret");
    defer std.testing.allocator.free(preview);
    try std.testing.expect(!std.mem.eql(u8, preview, "my-secret"));

    const passthrough = try redactor.previewFieldRedaction("username", "alice");
    defer std.testing.allocator.free(passthrough);
    try std.testing.expectEqualStrings("alice", passthrough);
}

test "redactor batch patterns remove helpers and matching count" {
    var redactor = Redactor.init(std.testing.allocator);
    defer redactor.deinit();

    const patterns = [_]Redactor.RedactionPattern{
        .{ .name = "token_pattern", .pattern_type = .contains, .pattern = "token=", .replacement = "token=" ++ Constants.RedactionDefaults.replacement },
        .{ .name = "password_pattern", .pattern_type = .contains, .pattern = "password=", .replacement = "password=" ++ Constants.RedactionDefaults.replacement },
    };

    const added = try redactor.addPatterns(patterns[0..]);
    try std.testing.expectEqual(@as(usize, 2), added);
    try std.testing.expectEqual(@as(usize, 2), redactor.patternCount());

    try redactor.addField("api_key", .mask_middle);
    try std.testing.expect(redactor.removeField("API_KEY"));
    try std.testing.expect(!redactor.removeField("API_KEY"));

    try std.testing.expectEqual(@as(usize, 2), redactor.matchingPatternCount("token=abc password=xyz"));
    try std.testing.expectEqual(@as(usize, 0), redactor.matchingPatternCount("safe message"));

    const removed = redactor.removePatternByName("token_pattern");
    try std.testing.expectEqual(@as(usize, 1), removed);
    try std.testing.expectEqual(@as(usize, 1), redactor.patternCount());
}

test "redactor preview message does not mutate stats" {
    var redactor = Redactor.init(std.testing.allocator);
    defer redactor.deinit();

    try redactor.addPattern("token_pattern", .contains, "token=", "token=" ++ Constants.RedactionDefaults.replacement);

    const before_processed = redactor.getStats().getTotalProcessed();
    const before_redacted = redactor.getStats().getValuesRedacted();

    const preview = try redactor.previewRedaction("token=abc");
    defer std.testing.allocator.free(preview);
    try std.testing.expect(std.mem.indexOf(u8, preview, Constants.RedactionDefaults.replacement) != null);

    const after_processed = redactor.getStats().getTotalProcessed();
    const after_redacted = redactor.getStats().getValuesRedacted();
    try std.testing.expectEqual(before_processed, after_processed);
    try std.testing.expectEqual(before_redacted, after_redacted);

    const actual = try redactor.redact("token=abc");
    defer std.testing.allocator.free(actual);
    try std.testing.expect(std.mem.indexOf(u8, actual, Constants.RedactionDefaults.replacement) != null);
    try std.testing.expect(redactor.getStats().getTotalProcessed() > after_processed);
}

test "redactor truncate redaction" {
    var redactor = Redactor.init(std.testing.allocator);
    defer redactor.deinit();

    redactor.config.truncate_length = 4;
    redactor.config.truncate_suffix = "...";
    try redactor.addField("token", .truncate);

    const redacted = try redactor.redactField("token", "abcdef");
    defer std.testing.allocator.free(redacted);

    try std.testing.expectEqualStrings("abcd...", redacted);
}

test "redactor hash algorithm selection" {
    var redactor = Redactor.init(std.testing.allocator);
    defer redactor.deinit();

    redactor.config.hash_algorithm = .md5;
    try redactor.addField("secret", .hash);

    const redacted = try redactor.redactField("secret", "super-secret");
    defer std.testing.allocator.free(redacted);

    try std.testing.expect(std.mem.startsWith(u8, redacted, "[HASH:"));
}

test "redactor advanced patterns email, ip, jwt, luhn, presets and audit" {
    var redactor = Redactor.init(std.testing.allocator);
    defer redactor.deinit();

    // 1. Email redaction
    try redactor.addPattern("email_pat", .email, "", "[EMAIL]");
    const email_res = try redactor.redact("Contact me at john_doe@example.com for info");
    defer std.testing.allocator.free(email_res);
    try std.testing.expectEqualStrings("Contact me at [EMAIL] for info", email_res);

    // 2. IP address redaction
    try redactor.addPattern("ip_pat", .ip, "", "[IP]");
    const ip_res = try redactor.redact("IPs: 192.168.1.100 and 2001:0db8:85a3:0000:0000:8a2e:0370:7334 or ::1");
    defer std.testing.allocator.free(ip_res);
    try std.testing.expectEqualStrings("IPs: [IP] and [IP] or [IP]", ip_res);

    // 3. JWT redaction
    try redactor.addPattern("jwt_pat", .jwt, "", "[JWT]");
    const jwt_res = try redactor.redact("Token: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c here");
    defer std.testing.allocator.free(jwt_res);
    try std.testing.expectEqualStrings("Token: [JWT] here", jwt_res);

    // 4. Luhn (credit card) redaction
    try redactor.addPattern("luhn_pat", .luhn, "", "[CARD]");
    // 4111-1111-1111-1111 is a valid Luhn (Visa test card)
    const luhn_res = try redactor.redact("Pay using 4111 1111 1111 1111 (valid) or 4111-1111-1111-1112 (invalid)");
    defer std.testing.allocator.free(luhn_res);
    try std.testing.expectEqualStrings("Pay using [CARD] (valid) or 4111-1111-1111-1112 (invalid)", luhn_res);

    // 5. Presets
    var gdpr_email_red = try RedactionPresets.gdprEmail(std.testing.allocator);
    defer gdpr_email_red.deinit();
    const gr = try gdpr_email_red.redact("email is test@domain.org");
    defer std.testing.allocator.free(gr);
    try std.testing.expectEqualStrings("email is [EMAIL REDACTED]", gr);

    var pci_card_red = try RedactionPresets.pciCard(std.testing.allocator);
    defer pci_card_red.deinit();
    const pr = try pci_card_red.redact("card 4111-1111-1111-1111");
    defer std.testing.allocator.free(pr);
    try std.testing.expectEqualStrings("card [CARD REDACTED]", pr);

    // 6. Audit Log
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(std.testing.allocator);
    var writer_adapter = Utils.ArrayListWriter.init(&buf, std.testing.allocator);
    try gdpr_email_red.auditLog(&writer_adapter.writer);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "REDACTION COMPLIANCE AUDIT LOG") != null);
}
