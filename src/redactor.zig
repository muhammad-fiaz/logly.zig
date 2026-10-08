//! Sensitive data redaction.
//!
//! Masks fields and patterns (emails, IPs, tokens) before output.
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
        totalValuesProcessed: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        valuesRedacted: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        patternsMatched: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        fieldsRedacted: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        redactionErrors: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),

        /// Get total values processed.
        pub fn getTotalProcessed(self: *const RedactorStats) u64 {
            return Utils.atomicLoadU64(&self.totalValuesProcessed);
        }

        /// Get total values redacted.
        pub fn getValuesRedacted(self: *const RedactorStats) u64 {
            return Utils.atomicLoadU64(&self.valuesRedacted);
        }

        /// Get total patterns matched.
        pub fn getPatternsMatched(self: *const RedactorStats) u64 {
            return Utils.atomicLoadU64(&self.patternsMatched);
        }

        /// Get total fields redacted.
        pub fn getFieldsRedacted(self: *const RedactorStats) u64 {
            return Utils.atomicLoadU64(&self.fieldsRedacted);
        }

        /// Get total redaction errors.
        pub fn getRedactionErrors(self: *const RedactorStats) u64 {
            return Utils.atomicLoadU64(&self.redactionErrors);
        }

        /// Check if any values have been processed.
        pub fn hasProcessed(self: *const RedactorStats) bool {
            return Utils.atomicLoadU64(&self.totalValuesProcessed) > 0;
        }

        /// Check if any values have been redacted.
        pub fn hasRedacted(self: *const RedactorStats) bool {
            return Utils.atomicLoadU64(&self.valuesRedacted) > 0;
        }

        /// Check if any patterns have matched.
        pub fn hasMatchedPatterns(self: *const RedactorStats) bool {
            return Utils.atomicLoadU64(&self.patternsMatched) > 0;
        }

        /// Check if any errors have occurred.
        pub fn hasErrors(self: *const RedactorStats) bool {
            return Utils.atomicLoadU64(&self.redactionErrors) > 0;
        }

        /// Calculate redaction rate (0.0 - 1.0)
        pub fn redactionRate(self: *const RedactorStats) f64 {
            return Utils.calculateRate(
                Utils.atomicLoadU64(&self.valuesRedacted),
                Utils.atomicLoadU64(&self.totalValuesProcessed),
            );
        }

        /// Calculate error rate (0.0 - 1.0)
        pub fn errorRate(self: *const RedactorStats) f64 {
            return Utils.calculateErrorRate(
                Utils.atomicLoadU64(&self.redactionErrors),
                Utils.atomicLoadU64(&self.totalValuesProcessed),
            );
        }

        /// Calculate success rate (0.0 - 1.0).
        pub fn successRate(self: *const RedactorStats) f64 {
            return 1.0 - self.errorRate();
        }

        /// Calculate pattern match rate (patterns matched / values redacted).
        pub fn patternMatchRate(self: *const RedactorStats) f64 {
            return Utils.calculateRate(
                Utils.atomicLoadU64(&self.patternsMatched),
                Utils.atomicLoadU64(&self.valuesRedacted),
            );
        }

        /// Calculate average redactions per processed value.
        pub fn avgRedactionsPerValue(self: *const RedactorStats) f64 {
            return Utils.calculateAverage(
                Utils.atomicLoadU64(&self.valuesRedacted),
                Utils.atomicLoadU64(&self.totalValuesProcessed),
            );
        }

        /// Reset all statistics to initial state.
        pub fn reset(self: *RedactorStats) void {
            self.totalValuesProcessed.store(0, .monotonic);
            self.valuesRedacted.store(0, .monotonic);
            self.patternsMatched.store(0, .monotonic);
            self.fieldsRedacted.store(0, .monotonic);
            self.redactionErrors.store(0, .monotonic);
        }
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
    onRedactionApplied: ?*const fn (u64, u64, u32) void = null,

    /// Callback invoked when a pattern matches.
    onPatternMatched: ?*const fn ([]const u8, []const u8) void = null,

    /// Callback invoked with redaction details showing original and redacted values.
    onRedactionDetail: ?*const fn ([]const u8, []const u8, []const u8) void = null,

    /// Callback invoked when redactor is initialized.
    onRedactorInitialized: ?*const fn (*const RedactorStats) void = null,

    /// Callback invoked on redaction error.
    onRedactionError: ?*const fn ([]const u8) void = null,

    /// Pattern-based redaction configuration.
    pub const RedactionPattern = struct {
        name: []const u8,
        patternType: PatternType,
        pattern: []const u8,
        replacement: []const u8,

        pub const PatternType = enum {
            exact,
            prefix,
            suffix,
            contains,
            regex,
            regexReplace,
            email,
            ip,
            jwt,
            luhn,
        };
    };

    /// Type of redaction to apply.
    pub const RedactionType = enum {
        full,
        partialStart,
        partialEnd,
        hash,
        maskMiddle,
        truncate,

        pub fn apply(self: RedactionType, allocator: std.mem.Allocator, value: []const u8) ![]u8 {
            return switch (self) {
                .full => try allocator.dupe(u8, Constants.RedactionDefaults.replacement),
                .partialStart => blk: {
                    if (value.len <= 4) {
                        break :blk try allocator.dupe(u8, "****");
                    }
                    const result = try allocator.alloc(u8, value.len);
                    @memset(result[0 .. value.len - 4], '*');
                    @memcpy(result[value.len - 4 ..], value[value.len - 4 ..]);
                    break :blk result;
                },
                .partialEnd => blk: {
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
                    const hexVal = try Utils.bytesToHexLowerAlloc(allocator, hash[0..8]);
                    defer allocator.free(hexVal);
                    break :blk try std.fmt.allocPrint(allocator, "[HASH:{s}]", .{hexVal});
                },
                .maskMiddle => blk: {
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
                    const maxLen: usize = Constants.RedactionDefaults.truncateLength;
                    const suffix = Constants.RedactionDefaults.truncateSuffix;
                    if (value.len <= maxLen) {
                        break :blk try allocator.dupe(u8, value);
                    }
                    const result = try allocator.alloc(u8, maxLen + suffix.len);
                    @memcpy(result[0..maxLen], value[0..maxLen]);
                    @memcpy(result[maxLen..], suffix);
                    break :blk result;
                },
            };
        }
    };

    /// Initializes a new Redactor instance with default configuration.
    pub fn init(allocator: std.mem.Allocator) Redactor {
        return initWithConfig(allocator, .{});
    }

    /// Initializes a new Redactor instance with custom configuration.
    pub fn initWithConfig(allocator: std.mem.Allocator, config: RedactionConfig) Redactor {
        var redactor = Redactor{
            .allocator = allocator,
            .config = config,
            .patterns = .empty,
            .fields = std.StringHashMap(RedactionType).init(allocator),
        };

        // Invoke initialized callback if set
        if (redactor.onRedactorInitialized) |callback| {
            callback(&redactor.stats);
        }

        return redactor;
    }

    /// Applies field/pattern rules defined in the redaction config.
    ///
    /// This does not mutate existing rules; it only adds new ones from config.
    pub fn applyConfigRules(self: *Redactor) !void {
        if (self.config.fields) |fields| {
            const mapped = mapConfigRedactionType(self.config.defaultType);
            for (fields) |fieldName| {
                try self.addField(fieldName, mapped);
            }
        }

        if (self.config.patterns) |patterns| {
            const patternType: RedactionPattern.PatternType = if (self.config.enableRegex) .regex else .contains;
            for (patterns, 0..) |pattern, i| {
                const name = try std.fmt.allocPrint(self.allocator, "config_pattern_{d}", .{i});
                defer self.allocator.free(name);
                try self.addPattern(name, patternType, pattern, self.config.replacement);
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

    /// Sets the callback for redaction applied events.
    pub fn setCallback(self: *Redactor, callback: *const fn (u64, u64, u32) void) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        self.onRedactionApplied = callback;
    }

    /// Sets the callback for redaction applied events.
    pub fn setRedactionAppliedCallback(self: *Redactor, callback: *const fn (u64, u64, u32) void) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        self.onRedactionApplied = callback;
    }

    /// Sets the callback for pattern matched events.
    pub fn setPatternMatchedCallback(self: *Redactor, callback: *const fn ([]const u8, []const u8) void) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        self.onPatternMatched = callback;
    }

    /// Sets the callback for redaction detail events (shows original and redacted values).
    pub fn setRedactionDetailCallback(self: *Redactor, callback: *const fn ([]const u8, []const u8, []const u8) void) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        self.onRedactionDetail = callback;
    }

    /// Sets the callback for redactor initialization.
    pub fn setInitializedCallback(self: *Redactor, callback: *const fn (*const RedactorStats) void) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        self.onRedactorInitialized = callback;
    }

    /// Sets the callback for redaction errors.
    pub fn setErrorCallback(self: *Redactor, callback: *const fn ([]const u8) void) void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());
        self.onRedactionError = callback;
    }

    /// Returns redactor statistics.
    pub fn getStats(self: *Redactor) RedactorStats {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());

        return self.stats;
    }

    /// Adds a sensitive field for redaction.
    pub fn addField(self: *Redactor, fieldName: []const u8, redactionType: RedactionType) !void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());

        if (self.fields.getPtr(fieldName)) |existing| {
            existing.* = redactionType;
            return;
        }

        const ownedName = try self.allocator.dupe(u8, fieldName);
        try self.fields.put(ownedName, redactionType);
    }

    /// Adds multiple sensitive fields using the same redaction type.
    ///
    /// Returns the number of fields added.
    pub fn addFields(self: *Redactor, fieldNames: []const []const u8, redactionType: RedactionType) !usize {
        var added: usize = 0;
        for (fieldNames) |name| {
            try self.addField(name, redactionType);
            added += 1;
        }
        return added;
    }

    /// Adds a pattern-based redaction rule.
    pub fn addPattern(
        self: *Redactor,
        name: []const u8,
        patternType: RedactionPattern.PatternType,
        pattern: []const u8,
        replacement: []const u8,
    ) !void {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());

        try self.patterns.append(self.allocator, .{
            .name = try self.allocator.dupe(u8, name),
            .patternType = patternType,
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
            try self.addPattern(pattern.name, pattern.patternType, pattern.pattern, pattern.replacement);
            added += 1;
        }
        return added;
    }

    /// Removes a field rule by name.
    ///
    /// Returns true when a matching field was removed.
    pub fn removeField(self: *Redactor, fieldName: []const u8) bool {
        self.mutex.lockUncancelable(Utils.io());
        defer self.mutex.unlock(Utils.io());

        if (self.fields.fetchRemove(fieldName)) |entry| {
            self.allocator.free(entry.key);
            return true;
        }

        if (self.config.caseInsensitive) {
            var keyToRemove: ?[]const u8 = null;
            var it = self.fields.iterator();
            while (it.next()) |entry| {
                if (std.ascii.eqlIgnoreCase(entry.key_ptr.*, fieldName)) {
                    keyToRemove = entry.key_ptr.*;
                    break;
                }
            }

            if (keyToRemove) |key| {
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
    pub fn redactWithAllocator(self: *Redactor, message: []const u8, scratchAllocator: ?std.mem.Allocator) ![]u8 {
        return self.redactInternal(message, scratchAllocator, .track);
    }

    /// Redacts sensitive data from a message without mutating stats.
    pub fn previewRedaction(self: *Redactor, message: []const u8) ![]u8 {
        return self.previewRedactionWithAllocator(message, null);
    }

    /// Redacts sensitive data from a message without mutating stats using an optional allocator.
    pub fn previewRedactionWithAllocator(self: *Redactor, message: []const u8, scratchAllocator: ?std.mem.Allocator) ![]u8 {
        return self.redactInternal(message, scratchAllocator, .preview);
    }

    fn redactInternal(self: *Redactor, message: []const u8, scratchAllocator: ?std.mem.Allocator, mode: RedactionApplyMode) ![]u8 {
        return self.redactInner(message, scratchAllocator, mode) catch |err| {
            // Count the failure and report it; the error still propagates
            // so the caller drops the record fail-closed (never forwards
            // unredacted text). Preview mode stays side-effect free.
            if (mode == .track) {
                _ = self.stats.redactionErrors.fetchAdd(1, .monotonic);
                if (self.onRedactionError) |callback| {
                    callback(@errorName(err));
                }
            }
            return err;
        };
    }

    fn redactInner(self: *Redactor, message: []const u8, scratchAllocator: ?std.mem.Allocator, mode: RedactionApplyMode) ![]u8 {
        const alloc = scratchAllocator orelse self.allocator;

        if (mode == .track) {
            _ = self.stats.totalValuesProcessed.fetchAdd(1, .monotonic);
        }

        var result = try alloc.dupe(u8, message);
        errdefer alloc.free(result);

        var wasRedacted = false;
        for (self.patterns.items) |pattern| {
            if (!patternMatchesMessage(pattern, result)) continue;

            const originalValue = result;
            result = try self.applyPatternWithAllocator(result, pattern, alloc);

            wasRedacted = true;
            if (mode == .track) {
                _ = self.stats.patternsMatched.fetchAdd(1, .monotonic);

                // Invoke pattern matched callback
                if (self.onPatternMatched) |callback| {
                    callback(pattern.name, originalValue);
                }

                // Invoke redaction detail callback (shows original and redacted values)
                if (self.onRedactionDetail) |callback| {
                    callback(pattern.name, originalValue, result);
                }
            }
        }

        if (mode == .track and wasRedacted) {
            _ = self.stats.valuesRedacted.fetchAdd(1, .monotonic);

            // Invoke redaction applied callback
            if (self.onRedactionApplied) |callback| {
                callback(@intCast(message.len), @intCast(result.len), 0);
            }

            // Audit logging if enabled
            if (self.config.auditRedactions) {
                // The callback handles audit logging
            }
        }

        return result;
    }

    /// Redacts a field value based on field rules.
    pub fn redactField(self: *Redactor, fieldName: []const u8, value: []const u8) ![]u8 {
        _ = self.stats.totalValuesProcessed.fetchAdd(1, .monotonic);

        // Check if field should be redacted
        const redactionType = self.getFieldRedactionWithConfig(fieldName);
        if (redactionType) |rtype| {
            _ = self.stats.fieldsRedacted.fetchAdd(1, .monotonic);
            _ = self.stats.valuesRedacted.fetchAdd(1, .monotonic);

            // Apply the redaction with config settings
            return self.applyRedactionType(rtype, value) catch |err| {
                _ = self.stats.redactionErrors.fetchAdd(1, .monotonic);
                if (self.onRedactionError) |callback| {
                    callback(@errorName(err));
                }
                return err;
            };
        }

        return self.allocator.dupe(u8, value) catch |err| {
            _ = self.stats.redactionErrors.fetchAdd(1, .monotonic);
            return err;
        };
    }

    /// Previews how a field would be redacted without changing counters.
    pub fn previewFieldRedaction(self: *Redactor, fieldName: []const u8, value: []const u8) ![]u8 {
        const redactionType = self.getFieldRedactionWithConfig(fieldName);
        if (redactionType) |rtype| {
            return self.applyRedactionType(rtype, value);
        }
        return self.allocator.dupe(u8, value);
    }

    /// Get field redaction type considering config settings.
    fn getFieldRedactionWithConfig(self: *const Redactor, fieldName: []const u8) ?RedactionType {
        // Check explicit field rules first
        if (self.fields.get(fieldName)) |rtype| {
            return rtype;
        }

        // Case-insensitive matching if enabled
        if (self.config.caseInsensitive) {
            var it = self.fields.iterator();
            while (it.next()) |entry| {
                if (std.ascii.eqlIgnoreCase(entry.key_ptr.*, fieldName)) {
                    return entry.value_ptr.*;
                }
            }
        }

        return null;
    }

    /// Apply redaction type with config settings.
    fn applyRedactionType(self: *Redactor, rtype: RedactionType, value: []const u8) ![]u8 {
        const maskChar = self.config.maskChar;
        const startChars = self.config.partialStartChars;
        const endChars = self.config.partialEndChars;

        return switch (rtype) {
            .full => try self.allocator.dupe(u8, self.config.replacement),
            .partialStart => Utils.maskString(self.allocator, value, maskChar, startChars, endChars, .partialStart),
            .partialEnd => Utils.maskString(self.allocator, value, maskChar, startChars, endChars, .partialEnd),
            .hash => self.computeRedactionHash(value),
            .maskMiddle => Utils.maskString(self.allocator, value, maskChar, startChars, endChars, .maskMiddle),
            .truncate => self.applyTruncate(value),
        };
    }

    fn applyTruncate(self: *Redactor, value: []const u8) ![]u8 {
        const maxLen = self.config.truncateLength;
        const suffix = self.config.truncateSuffix;
        if (maxLen == 0) return self.allocator.dupe(u8, suffix);
        if (value.len <= maxLen) return self.allocator.dupe(u8, value);
        const result = try self.allocator.alloc(u8, maxLen + suffix.len);
        @memcpy(result[0..maxLen], value[0..maxLen]);
        @memcpy(result[maxLen..], suffix);
        return result;
    }

    fn computeRedactionHash(self: *Redactor, value: []const u8) ![]u8 {
        return switch (self.config.hashAlgorithm) {
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

    fn formatHashTag(allocator: std.mem.Allocator, hashBytes: []const u8) ![]u8 {
        const hexVal = try Utils.bytesToHexLowerAlloc(allocator, hashBytes);
        defer allocator.free(hexVal);
        return std.fmt.allocPrint(allocator, "[HASH:{s}]", .{hexVal});
    }

    fn mapConfigRedactionType(rtype: RedactionConfig.RedactionType) RedactionType {
        return switch (rtype) {
            .full => .full,
            .partialStart => .partialStart,
            .partialEnd => .partialEnd,
            .hash => .hash,
            .maskMiddle => .maskMiddle,
            .truncate => .truncate,
        };
    }

    fn matchIpv6(input: []const u8) ?usize {
        if (input.len < 3) return null;
        var colons: usize = 0;
        var hexSegments: usize = 0;
        var i: usize = 0;
        var lastWasColon = false;

        // An IPv6 address can start with ::
        if (std.mem.startsWith(u8, input, "::")) {
            colons += 2;
            i += 2;
            lastWasColon = true;
        }

        while (i < input.len) {
            const c = input[i];
            if (std.ascii.isHex(c)) {
                // Read hex segment (max 4 chars)
                var segLen: usize = 0;
                while (i < input.len and std.ascii.isHex(input[i])) : (i += 1) {
                    segLen += 1;
                }
                if (segLen > 4) return null; // Invalid segment length
                hexSegments += 1;
                lastWasColon = false;
            } else if (c == ':') {
                if (lastWasColon) {
                    // Double colon `::`
                    if (colons > 0 and i > 0 and input[i - 1] == ':') {
                        // Allowed at most one double colon
                        colons += 1;
                        i += 1;
                        lastWasColon = true;
                    } else {
                        return null;
                    }
                } else {
                    colons += 1;
                    i += 1;
                    lastWasColon = true;
                }
            } else {
                break;
            }
        }

        // Valid IPv6 should have at least 2 colons and some hex segments/colons, and not end with a single colon (unless ::)
        if (colons >= 2 and (hexSegments >= 1 or colons >= 2)) {
            if (lastWasColon and !std.mem.endsWith(u8, input[0..i], "::")) {
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
        const payloadStart = i;
        while (i < input.len and (std.ascii.isAlphanumeric(input[i]) or input[i] == '_' or input[i] == '-')) : (i += 1) {}
        if (i == payloadStart or i >= input.len or input[i] != '.') return null;
        i += 1; // skip '.'

        // Part 3: Signature
        const sigStart = i;
        while (i < input.len and (std.ascii.isAlphanumeric(input[i]) or input[i] == '_' or input[i] == '-')) : (i += 1) {}
        if (i == sigStart) return null;

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

        var digitBuf: [32]u8 = undefined;
        var digitCount: usize = 0;
        var i: usize = 0;
        var lastDigitIdx: usize = 0;

        while (i < input.len) : (i += 1) {
            const c = input[i];
            if (std.ascii.isDigit(c)) {
                if (digitCount < 32) {
                    digitBuf[digitCount] = c;
                    digitCount += 1;
                }
                lastDigitIdx = i;
            } else if (c == ' ' or c == '-') {
                // separator allowed
            } else {
                break;
            }

            if (digitCount > 19) {
                break;
            }
        }

        if (digitCount >= 13 and digitCount <= 19) {
            if (Utils.isLuhnValid(digitBuf[0..digitCount])) {
                return lastDigitIdx + 1;
            }
        }

        return null;
    }

    fn applyPattern(self: *Redactor, input: []u8, pattern: RedactionPattern) ![]u8 {
        return self.applyPatternWithAllocator(input, pattern, self.allocator);
    }

    fn applyPatternWithAllocator(self: *Redactor, input: []u8, pattern: RedactionPattern, alloc: std.mem.Allocator) ![]u8 {
        _ = self; // self only needed for stats/callbacks in caller
        switch (pattern.patternType) {
            .contains => {
                const result = try Utils.replaceString(alloc, input, pattern.pattern, pattern.replacement);
                alloc.free(input);
                return result;
            },
            .prefix => {
                if (std.mem.startsWith(u8, input, pattern.pattern)) {
                    const newResult = try alloc.alloc(
                        u8,
                        pattern.replacement.len + input.len - pattern.pattern.len,
                    );
                    @memcpy(newResult[0..pattern.replacement.len], pattern.replacement);
                    @memcpy(newResult[pattern.replacement.len..], input[pattern.pattern.len..]);
                    alloc.free(input);
                    return newResult;
                }
                return input;
            },
            .suffix => {
                if (std.mem.endsWith(u8, input, pattern.pattern)) {
                    const newResult = try alloc.alloc(
                        u8,
                        input.len - pattern.pattern.len + pattern.replacement.len,
                    );
                    @memcpy(newResult[0 .. input.len - pattern.pattern.len], input[0 .. input.len - pattern.pattern.len]);
                    @memcpy(newResult[input.len - pattern.pattern.len ..], pattern.replacement);
                    alloc.free(input);
                    return newResult;
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
            .regex, .regexReplace => {
                // Simple regex-like pattern matching for common cases
                // Supports: * (any chars), ? (single char), \d (digit), \w (word char), \s (whitespace)
                var result: std.ArrayList(u8) = .empty;
                defer result.deinit(alloc);

                var i: usize = 0;
                while (i < input.len) {
                    if (matchRegexPattern(input[i..], pattern.pattern)) |matchLen| {
                        try result.appendSlice(alloc, pattern.replacement);
                        i += matchLen;
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
                    if (Utils.matchRegexPattern(input[i..], "\\w+@\\w+\\.\\w+")) |matchLen| {
                        if (matchLen > 0) {
                            try result.appendSlice(alloc, pattern.replacement);
                            i += matchLen;
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
                    if (Utils.matchRegexPattern(input[i..], "\\d+\\.\\d+\\.\\d+\\.\\d+")) |matchLen| {
                        if (matchLen > 0) {
                            try result.appendSlice(alloc, pattern.replacement);
                            i += matchLen;
                            continue;
                        }
                    }
                    if (matchIpv6(input[i..])) |matchLen| {
                        if (matchLen > 0) {
                            try result.appendSlice(alloc, pattern.replacement);
                            i += matchLen;
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
                    if (matchJwt(input[i..])) |matchLen| {
                        try result.appendSlice(alloc, pattern.replacement);
                        i += matchLen;
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
                        if (matchLuhn(input[i..])) |matchLen| {
                            try result.appendSlice(alloc, pattern.replacement);
                            i += matchLen;
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
        return switch (pattern.patternType) {
            .contains => std.mem.indexOf(u8, message, pattern.pattern) != null,
            .prefix => std.mem.startsWith(u8, message, pattern.pattern),
            .suffix => std.mem.endsWith(u8, message, pattern.pattern),
            .exact => std.mem.eql(u8, message, pattern.pattern),
            .regex, .regexReplace => Utils.findRegexPattern(message, pattern.pattern) != null,
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
    pub fn getFieldRedaction(self: *const Redactor, fieldName: []const u8) ?RedactionType {
        return self.fields.get(fieldName);
    }

    /// Returns true when the provided field has a redaction rule.
    pub fn hasFieldRule(self: *const Redactor, fieldName: []const u8) bool {
        return self.getFieldRedactionWithConfig(fieldName) != null;
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

    /// Alias for setCallback
    // pub const callback = setCallback; // shadows parameters

    /// Alias for addPattern
    // pub const addRule = addPattern; // already exists

    /// Alias for addField
    // pub const field = addField; // already exists
    // pub const sensitiveField = addField; // already exists

    /// Alias for redact
    // pub const mask = redact; // already exists
    // pub const sanitize = redact; // already exists
    // pub const process = redact; // already exists

    /// Alias for redactField
    // pub const maskField = redactField; // already exists

    /// Formats and dumps redaction statistics for compliance.
    pub fn auditLog(self: *const Redactor, writer: anytype) !void {
        try writer.print("Redaction compliance audit log\n", .{});
        try writer.print("Total values processed: {d}\n", .{self.stats.getTotalProcessed()});
        try writer.print("Values redacted: {d}\n", .{self.stats.getValuesRedacted()});
        try writer.print("Patterns matched: {d}\n", .{self.stats.getPatternsMatched()});
        try writer.print("Fields redacted: {d}\n", .{self.stats.getFieldsRedacted()});
        try writer.print("Redaction errors: {d}\n", .{self.stats.getRedactionErrors()});
        try writer.print("Redaction rate: {d:.2}%\n", .{self.stats.redactionRate() * 100.0});
        try writer.print("Success rate: {d:.2}%\n", .{self.stats.successRate() * 100.0});
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
        try redactor.addField("api_key", .partialEnd);
        try redactor.addField("token", .partialEnd);
        try redactor.addField("credit_card", .maskMiddle);
        try redactor.addField("ssn", .maskMiddle);
        try redactor.addField("email", .partialStart);

        return redactor;
    }

    /// Creates a redactor for PCI-DSS compliance.
    pub fn pciDss(allocator: std.mem.Allocator) !Redactor {
        var redactor = Redactor.init(allocator);
        errdefer redactor.deinit();

        try redactor.addField("pan", .maskMiddle);
        try redactor.addField("cvv", .full);
        try redactor.addField("pin", .full);
        try redactor.addField("card_number", .maskMiddle);
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
        try redactor.addField("address", .partialEnd);
        try redactor.addField("phone", .partialStart);
        try redactor.addField("email", .partialStart);
        try redactor.addField("medical_record", .hash);

        return redactor;
    }

    /// Creates a redactor for GDPR compliance.
    pub fn gdpr(allocator: std.mem.Allocator) !Redactor {
        var redactor = Redactor.init(allocator);
        errdefer redactor.deinit();

        try redactor.addField("name", .partialEnd);
        try redactor.addField("email", .partialStart);
        try redactor.addField("phone", .partialStart);
        try redactor.addField("address", .full);
        try redactor.addField("ip", .partialEnd);
        try redactor.addField("ip_address", .partialEnd);
        try redactor.addField("user_id", .hash);

        return redactor;
    }

    /// Creates a redactor for API keys and secrets.
    pub fn apiSecrets(allocator: std.mem.Allocator) !Redactor {
        var redactor = Redactor.init(allocator);
        errdefer redactor.deinit();

        try redactor.addField("api_key", .maskMiddle);
        try redactor.addField("secret_key", .full);
        try redactor.addField("access_token", .maskMiddle);
        try redactor.addField("refresh_token", .full);
        try redactor.addField("bearer_token", .maskMiddle);
        try redactor.addField("authorization", .partialEnd);

        return redactor;
    }

    /// Creates a redactor for financial data.
    pub fn financial(allocator: std.mem.Allocator) !Redactor {
        var redactor = Redactor.init(allocator);
        errdefer redactor.deinit();

        try redactor.addField("account_number", .maskMiddle);
        try redactor.addField("routing_number", .full);
        try redactor.addField("balance", .full);
        try redactor.addField("amount", .full);
        try redactor.addField("iban", .maskMiddle);
        try redactor.addField("swift", .partialEnd);

        return redactor;
    }

    /// Creates a secure sink configuration with redaction enabled.
    pub fn createSecureSink(filePath: []const u8) SinkConfig {
        return SinkConfig{
            .path = filePath,
            .format = .json,
            .color = false,
        };
    }
};

test "redactor field" {
    const result = try Redactor.RedactionType.partialEnd.apply(std.testing.allocator, "secret123456");
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
        .{ .name = "token_pattern", .patternType = .contains, .pattern = "token=", .replacement = "token=" ++ Constants.RedactionDefaults.replacement },
        .{ .name = "password_pattern", .patternType = .contains, .pattern = "password=", .replacement = "password=" ++ Constants.RedactionDefaults.replacement },
    };

    const added = try redactor.addPatterns(patterns[0..]);
    try std.testing.expectEqual(@as(usize, 2), added);
    try std.testing.expectEqual(@as(usize, 2), redactor.patternCount());

    try redactor.addField("api_key", .maskMiddle);
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

    const beforeProcessed = redactor.getStats().getTotalProcessed();
    const beforeRedacted = redactor.getStats().getValuesRedacted();

    const preview = try redactor.previewRedaction("token=abc");
    defer std.testing.allocator.free(preview);
    try std.testing.expect(std.mem.indexOf(u8, preview, Constants.RedactionDefaults.replacement) != null);

    const afterProcessed = redactor.getStats().getTotalProcessed();
    const afterRedacted = redactor.getStats().getValuesRedacted();
    try std.testing.expectEqual(beforeProcessed, afterProcessed);
    try std.testing.expectEqual(beforeRedacted, afterRedacted);

    const actual = try redactor.redact("token=abc");
    defer std.testing.allocator.free(actual);
    try std.testing.expect(std.mem.indexOf(u8, actual, Constants.RedactionDefaults.replacement) != null);
    try std.testing.expect(redactor.getStats().getTotalProcessed() > afterProcessed);
}

test "redactor truncate redaction" {
    var redactor = Redactor.init(std.testing.allocator);
    defer redactor.deinit();

    redactor.config.truncateLength = 4;
    redactor.config.truncateSuffix = "...";
    try redactor.addField("token", .truncate);

    const redacted = try redactor.redactField("token", "abcdef");
    defer std.testing.allocator.free(redacted);

    try std.testing.expectEqualStrings("abcd...", redacted);
}

test "redactor hash algorithm selection" {
    var redactor = Redactor.init(std.testing.allocator);
    defer redactor.deinit();

    redactor.config.hashAlgorithm = .md5;
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
    const emailRes = try redactor.redact("Contact me at john_doe@example.com for info");
    defer std.testing.allocator.free(emailRes);
    try std.testing.expectEqualStrings("Contact me at [EMAIL] for info", emailRes);

    // 2. IP address redaction
    try redactor.addPattern("ip_pat", .ip, "", "[IP]");
    const ipRes = try redactor.redact("IPs: 192.168.1.100 and 2001:0db8:85a3:0000:0000:8a2e:0370:7334 or ::1");
    defer std.testing.allocator.free(ipRes);
    try std.testing.expectEqualStrings("IPs: [IP] and [IP] or [IP]", ipRes);

    // 3. JWT redaction
    try redactor.addPattern("jwt_pat", .jwt, "", "[JWT]");
    const jwtRes = try redactor.redact("Token: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c here");
    defer std.testing.allocator.free(jwtRes);
    try std.testing.expectEqualStrings("Token: [JWT] here", jwtRes);

    // 4. Luhn (credit card) redaction
    try redactor.addPattern("luhn_pat", .luhn, "", "[CARD]");
    // 4111-1111-1111-1111 is a valid Luhn (Visa test card)
    const luhnRes = try redactor.redact("Pay using 4111 1111 1111 1111 (valid) or 4111-1111-1111-1112 (invalid)");
    defer std.testing.allocator.free(luhnRes);
    try std.testing.expectEqualStrings("Pay using [CARD] (valid) or 4111-1111-1111-1112 (invalid)", luhnRes);

    // 5. Presets
    var gdprEmailRed = try RedactionPresets.gdprEmail(std.testing.allocator);
    defer gdprEmailRed.deinit();
    const gr = try gdprEmailRed.redact("email is test@domain.org");
    defer std.testing.allocator.free(gr);
    try std.testing.expectEqualStrings("email is [EMAIL REDACTED]", gr);

    var pciCardRed = try RedactionPresets.pciCard(std.testing.allocator);
    defer pciCardRed.deinit();
    const pr = try pciCardRed.redact("card 4111-1111-1111-1111");
    defer std.testing.allocator.free(pr);
    try std.testing.expectEqualStrings("card [CARD REDACTED]", pr);

    // 6. Audit Log
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(std.testing.allocator);
    var writerAdapter = Utils.ArrayListWriter.init(&buf, std.testing.allocator);
    try gdprEmailRed.auditLog(&writerAdapter.writer);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "Redaction compliance audit log") != null);
}
