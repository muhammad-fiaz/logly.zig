---
title: Redactor API Reference
description: API reference for Logly.zig Redactor struct. Mask passwords, API keys, credit cards, and PII with keyword patterns, regex rules, and custom redaction strategies.
head:
  - - meta
    - name: keywords
      content: redactor api, data masking, pii redaction, sensitive data, password masking, security api
  - - meta
    - property: og:title
      content: Redactor API Reference | Logly.zig
---

# Redactor API

The `Redactor` struct handles the masking of sensitive data in log messages and context fields.

## Quick Reference: Method Aliases

| Full Method | Alias(es) | Description |
|-------------|-----------|-------------|
| `init()` | `create()` | Initialize redactor |
| `deinit()` | `destroy()` | Deinitialize redactor |
| `initWithConfig()` | `createWithConfig()` | Initialize with config |
| `addPattern()` | `addRule()` | Add redaction pattern |
| `addField()` | `field()`, `sensitiveField()` | Add sensitive field |
| `addFields()` | `addFieldsBatch()`, `addSensitiveFields()` | Add multiple sensitive fields |
| `addPatterns()` | `addPatternBatch()`, `addRules()` | Add multiple redaction patterns |
| `removeField()` | `deleteField()`, `removeSensitiveField()` | Remove field rule |
| `removePatternByName()` | `removePattern()`, `deletePattern()` | Remove patterns by name |
| `redact()` | `mask()`, `sanitize()`, `process()` | Redact text |
| `previewRedaction()` | `previewMessage()`, `preview()` | Preview full-message redaction without stats mutation |
| `previewRedactionWithAllocator()` | `previewMessageWithAllocator()` | Preview redaction with allocator |
| `redactField()` | `maskField()` | Redact field |
| `previewFieldRedaction()` | `previewField()` | Preview field redaction without stats mutation |
| `redactWithAllocator()` | `maskWithAllocator()`, `sanitizeWithAllocator()` | Redact with allocator |
| `getStats()` | `statistics()` | Get statistics |
| `resetStats()` | `resetStatistics()` | Reset statistics |
| `patternCount()` | `ruleCount()` | Get pattern count |
| `fieldCount()` | `sensitiveFieldCount()` | Get field count |
| `hasRules()` | `hasConfiguration()` | Check if has rules |
| `clearPatterns()` | `clearRules()` | Clear patterns |
| `clearFields()` | `clearSensitiveFields()` | Clear fields |
| `clear()` | `clearAll()` | Clear all |
| `setRedactionAppliedCallback()` | `onRedactionApplied()` | Set redaction applied callback |
| `setPatternMatchedCallback()` | `onPatternMatched()` | Set pattern matched callback |
| `setInitializedCallback()` | `onInitialized()` | Set initialized callback |
| `setErrorCallback()` | `onError()` | Set error callback |
| `getFieldRedaction()` | `getFieldRule()` | Get field redaction |
| `hasFieldRule()` | `hasRuleForField()` | Check whether a field has a rule |
| `wouldRedact()` | `shouldRedact()`, `needsRedaction()` | Check whether a message matches configured patterns |
| `matchingPatternCount()` | `matchingPatterns()`, `matchedPatternCount()` | Count matched patterns for a message |
| `apply()` | `redact()`, `mask()` | Apply pattern (RedactionPattern) |
| `getTotalProcessed()` | `totalProcessed()`, `processedCount()` | Get total processed (RedactorStats) |
| `getValuesRedacted()` | `valuesRedacted()`, `redactedCount()` | Get values redacted (RedactorStats) |
| `getPatternsMatched()` | `patternsMatched()`, `matchedCount()` | Get patterns matched (RedactorStats) |
| `getFieldsRedacted()` | `fieldsRedacted()`, `fieldRedactionCount()` | Get fields redacted (RedactorStats) |
| `getRedactionErrors()` | `redactionErrors()`, `errorCount()` | Get redaction errors (RedactorStats) |
| `hasProcessed()` | `processed()` | Check if processed (RedactorStats) |
| `hasRedacted()` | `redacted()` | Check if redacted (RedactorStats) |
| `hasMatchedPatterns()` | `matchedPatterns()` | Check if matched patterns (RedactorStats) |
| `hasErrors()` | `hasRedactionErrors()` | Check if has errors (RedactorStats) |
| `redactionRate()` | `redactionPercentage()` | Get redaction rate (RedactorStats) |
| `errorRate()` | `errorPercentage()` | Get error rate (RedactorStats) |
| `successRate()` | `successPercentage()` | Get success rate (RedactorStats) |
| `patternMatchRate()` | `patternMatchPercentage()` | Get pattern match rate (RedactorStats) |
| `avgRedactionsPerValue()` | `avgRedactions()` | Get avg redactions per value (RedactorStats) |
| `reset()` | `clear()`, `zero()` | Reset stats (RedactorStats) |

## Overview

Redactors ensure compliance and security by preventing sensitive information (like passwords, API keys, or PII) from being written to logs. Supports pattern-based and field-based redaction with multiple masking types.

## Types

### Redactor

The main redactor controller with thread-safe operations.

```zig
pub const Redactor = struct {
    allocator: std.mem.Allocator,
    patterns: std.ArrayList(RedactionPattern),
    fields: std.StringHashMap(RedactionType),
    stats: RedactorStats,
    mutex: std.Thread.Mutex,
    
    // Callbacks
    on_redaction_applied: ?*const fn ([]const u8, []const u8) void,
    on_field_redacted: ?*const fn ([]const u8, RedactionType) void,
    on_pattern_matched: ?*const fn ([]const u8, []const u8) void,
};
```

### RedactionPattern

Defines a pattern to search for and redact.

```zig
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
    };
};
```

### RedactionType

Defines how the value should be masked.

```zig
pub const RedactionType = enum {
    full,           // Replace with [REDACTED]
    partial_start,  // ****1234
    partial_end,    // 1234****
    hash,           // SHA256 hash
    mask_middle,    // 12****34
    truncate,       // Truncate to N chars
    
    pub fn apply(self: RedactionType, allocator: Allocator, value: []const u8) ![]u8;
};
```

### RedactorStats

Statistics for redaction operations with atomic counters.

```zig
pub const RedactorStats = struct {
    total_values_processed: std.atomic.Value(u64),
    values_redacted: std.atomic.Value(u64),
    patterns_matched: std.atomic.Value(u64),
    fields_redacted: std.atomic.Value(u64),
    redaction_errors: std.atomic.Value(u64),
};
```

#### Getter Methods

| Method | Return | Description |
|--------|--------|-------------|
| `getTotalProcessed()` | `u64` | Get total values processed |
| `getValuesRedacted()` | `u64` | Get total values redacted |
| `getPatternsMatched()` | `u64` | Get total patterns matched |
| `getFieldsRedacted()` | `u64` | Get total fields redacted |
| `getRedactionErrors()` | `u64` | Get total redaction errors |

#### Boolean Checks

| Method | Return | Description |
|--------|--------|-------------|
| `hasProcessed()` | `bool` | Check if any values have been processed |
| `hasRedacted()` | `bool` | Check if any values have been redacted |
| `hasMatchedPatterns()` | `bool` | Check if any patterns have matched |
| `hasErrors()` | `bool` | Check if any errors have occurred |

#### Rate Calculations

| Method | Return | Description |
|--------|--------|-------------|
| `redactionRate()` | `f64` | Calculate redaction rate (0.0 - 1.0) |
| `errorRate()` | `f64` | Calculate error rate (0.0 - 1.0) |
| `successRate()` | `f64` | Calculate success rate (0.0 - 1.0) |
| `patternMatchRate()` | `f64` | Calculate pattern match rate |
| `avgRedactionsPerValue()` | `f64` | Calculate average redactions per processed value |

#### Reset

| Method | Description |
|--------|-------------|
| `reset()` | Reset all statistics to initial state |

### RedactionConfig

Global configuration for redaction, available through `Config.RedactionConfig`:

```zig
pub const RedactionConfig = struct {
    /// Enable redaction system.
    enabled: bool = false,
    /// Fields to redact (by name).
    fields: ?[]const []const u8 = null,
    /// Patterns to redact (string patterns).
    patterns: ?[]const []const u8 = null,
    /// Default replacement text.
    replacement: []const u8 = "[REDACTED]",
    /// Default redaction type for fields.
    default_type: RedactionType = .full,
    /// Enable regex pattern matching.
    enable_regex: bool = false,
    /// Hash algorithm for hash redaction type.
    hash_algorithm: HashAlgorithm = .sha256,
    /// Maximum length before truncation (truncate redaction type).
    truncate_length: usize = 24,
    /// Suffix to append after truncation.
    truncate_suffix: []const u8 = "...",
    /// Characters to reveal at start for partial redaction.
    partial_start_chars: u8 = 4,
    /// Characters to reveal at end for partial redaction.
    partial_end_chars: u8 = 4,
    /// Mask character for redacted content.
    mask_char: u8 = '*',
    /// Enable case-insensitive field matching.
    case_insensitive: bool = true,
    /// Log when redaction is applied (for audit).
    audit_redactions: bool = false,
    /// Compliance preset to use (null for custom).
    compliance_preset: ?CompliancePreset = null,

    // Presets
    pub fn pciDss() RedactionConfig;
    pub fn hipaa() RedactionConfig;
    pub fn gdpr() RedactionConfig;
    pub fn strict() RedactionConfig;
};
```

### CompliancePreset

```zig
pub const CompliancePreset = enum {
    pci_dss,
    hipaa,
    gdpr,
    sox,
    custom,
};
```

### HashAlgorithm

```zig
pub const HashAlgorithm = enum {
    sha256,
    sha512,
    md5,
};
```

## Methods

### Initialization

#### `init(allocator: std.mem.Allocator) Redactor`

Initializes a new Redactor instance with default configuration.

#### `initWithConfig(allocator: std.mem.Allocator, config: RedactionConfig) Redactor`

Initializes a new Redactor instance with custom configuration.

```zig
var redactor = Redactor.initWithConfig(allocator, .{
    .enabled = true,
    .replacement = "[HIDDEN]",
    .mask_char = '#',
    .partial_start_chars = 3,
    .partial_end_chars = 3,
    .case_insensitive = true,
    .audit_redactions = true,
});
```

#### `deinit(self: *Redactor) void`

Releases all resources associated with the redactor.

### Pattern Management

#### `addPattern(name: []const u8, pattern_type: PatternType, pattern: []const u8, replacement: []const u8) !void`

Adds a new pattern-based redaction rule.

**Alias**: `addRule`

#### `addField(field_name: []const u8, redaction_type: RedactionType) !void`

Adds a field-based redaction rule (for structured logging context).

**Alias**: `field`, `sensitiveField`

#### `addFields(field_names: []const []const u8, redaction_type: RedactionType) !usize`

Adds multiple field-based redaction rules and returns the number of fields added.

**Alias**: `addFieldsBatch`, `addSensitiveFields`

#### `addPatterns(patterns: []const RedactionPattern) !usize`

Adds multiple pattern-based redaction rules and returns the number of patterns added.

**Alias**: `addPatternBatch`, `addRules`

#### `removeField(field_name: []const u8) bool`

Removes a field redaction rule by name.

- Honors case-insensitive matching when enabled in config.
- Returns `true` when a rule was removed.

**Alias**: `deleteField`, `removeSensitiveField`

#### `removePatternByName(name: []const u8) usize`

Removes all pattern rules with the provided name and returns number of removed rules.

**Alias**: `removePattern`, `deletePattern`

#### `clearPatterns() void`

Removes all pattern rules.

#### `clearFields() void`

Removes all field rules.

#### `clear() void`

Removes all redaction rules.

### Redaction

#### `redact(value: []const u8) ![]u8`

Applies redaction to a string value using pattern rules. Returns a new allocated string.

**Alias**: `mask`, `sanitize`, `process`

#### `redactWithAllocator(value: []const u8, scratch_allocator: ?std.mem.Allocator) ![]u8`

Applies redaction using an optional scratch allocator. If provided, temporary allocations use the scratch allocator (useful for arena allocators). If null, uses the redactor's main allocator.

```zig
// Use with arena allocator from logger
const result = try redactor.redactWithAllocator(message, logger.scratchAllocator());
```

#### `previewRedaction(value: []const u8) ![]u8`

Previews how full-message pattern redaction would look without mutating stats or callbacks.

**Alias**: `previewMessage`, `preview`

#### `previewRedactionWithAllocator(value: []const u8, scratch_allocator: ?std.mem.Allocator) ![]u8`

Allocator-aware variant of `previewRedaction(...)`.

**Alias**: `previewMessageWithAllocator`

#### `redactField(field_name: []const u8, value: []const u8) ![]u8`

Redacts a field value based on field rules with config settings.

**Alias**: `maskField`

#### `previewFieldRedaction(field_name: []const u8, value: []const u8) ![]u8`

Returns how a field value would be redacted without incrementing runtime counters.

**Alias**: `previewField`

#### `wouldRedact(value: []const u8) bool`

Returns true when at least one configured pattern would match and redact the provided value.

**Alias**: `shouldRedact`, `needsRedaction`

#### `matchingPatternCount(value: []const u8) usize`

Returns count of configured pattern rules that match this value.

**Alias**: `matchingPatterns`, `matchedPatternCount`

### Audit & Logging

#### `auditLog(writer: anytype) !void`

Writes a compliance audit log to the provided writer, detailing the configured fields, patterns, and configuration settings for compliance verification.

### Configuration

#### `getConfig() RedactionConfig`

Returns current redaction configuration.

#### `isEnabled() bool`

Returns true if redaction is enabled in config.

#### `getDefaultReplacement() []const u8`

Returns the default replacement text from config.

### Statistics

#### `getStats() RedactorStats`

Returns current redactor statistics.

**Alias**: `statistics`

#### `resetStats() void`

Resets all statistics to zero.

#### `patternCount() usize`

Returns the number of pattern rules.

#### `fieldCount() usize`

Returns the number of field rules.

#### `hasFieldRule(field_name: []const u8) bool`

Returns true if a field rule exists (including case-insensitive matches when enabled).

### State

#### `hasRules() bool`

Returns true if any redaction rules are configured.

## Presets

### RedactionPresets

```zig
pub const RedactionPresets = struct {
    /// Standard sensitive data redaction.
    /// Includes: password, email (with robust format validation), ssn, api_key fields
    pub fn standard(allocator: std.mem.Allocator) !Redactor;
    
    /// PCI-DSS compliant redaction.
    /// Includes: pan, cvv, pin, card_number, expiry fields. Card numbers are dynamically validated using the Luhn algorithm.
    pub fn pciDss(allocator: std.mem.Allocator) !Redactor;
    
    /// HIPAA compliant redaction.
    /// Includes: patient_id, ssn, dob, address, phone, email, medical_record
    pub fn hipaa(allocator: std.mem.Allocator) !Redactor;
    
    /// GDPR compliant redaction.
    /// Includes: name, email, phone, address, ip, ip_address, user_id. Supports advanced IPv4/IPv6 address masking.
    pub fn gdpr(allocator: std.mem.Allocator) !Redactor;
    
    /// API secrets redaction.
    /// Includes: api_key, secret_key, access_token, refresh_token, bearer_token, jwt (with JWT pattern validation).
    pub fn apiSecrets(allocator: std.mem.Allocator) !Redactor;
    
    /// Financial data redaction.
    /// Includes: account_number, routing_number, balance, amount, iban, swift
    pub fn financial(allocator: std.mem.Allocator) !Redactor;
    
    /// Creates a secure sink configuration with redaction enabled.
    pub fn createSecureSink(file_path: []const u8) SinkConfig;
};
```

## Example

```zig
const Redactor = @import("logly").Redactor;
const RedactionPresets = @import("logly").RedactionPresets;

// Create redactor
var redactor = Redactor.init(allocator);
defer redactor.deinit();

// Add custom rules
try redactor.addField("password", .full);
try redactor.addField("credit_card", .mask_middle);
try redactor.addPattern("api_key_pattern", .contains, "api_key=", "[API_KEY_REDACTED]");

// Or use compliance presets
var pci_redactor = try RedactionPresets.pciDss(allocator);
defer pci_redactor.deinit();

var gdpr_redactor = try RedactionPresets.gdpr(allocator);
defer gdpr_redactor.deinit();

// Apply redaction
const original = "User password=secret123 logged in";
const redacted = try redactor.redact(original);
defer allocator.free(redacted);
// Result: "User password=[REDACTED] logged in"

// Check statistics
const stats = redactor.getStats();
std.debug.print("Redactions: {d}\\n", .{stats.getValuesRedacted()});

// Check rule counts
std.debug.print("Patterns: {d}, Fields: {d}\\n", .{
    redactor.patternCount(),
    redactor.fieldCount(),
});
```

## Compliance Guide

| Preset | Compliance | Key Fields |
|--------|------------|------------|
| `pciDss` | PCI-DSS | Card numbers, CVV, PIN |
| `hipaa` | HIPAA | Patient ID, SSN, medical records |
| `gdpr` | GDPR | Names, emails, IP addresses |
| `financial` | SOX/GLBA | Account numbers, IBAN, amounts |
| `apiSecrets` | Security | API keys, tokens, secrets |

## See Also

- [Redaction Guide](../guide/redaction.md) - Detailed redaction configuration
- [Filtering API](filter.md) - Content-based filtering
