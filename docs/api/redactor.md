# Redactor API

The `Redactor` struct handles the masking of sensitive data in log messages and context fields.

## Overview

Redactors are used to ensure compliance and security by preventing sensitive information (like passwords, API keys, or PII) from being written to logs.

## Types

### Redactor

The main redactor controller.

```zig
pub const Redactor = struct {
    allocator: std.mem.Allocator,
    patterns: std.ArrayList(RedactionPattern),
    fields: std.StringHashMap(RedactionType),
    stats: RedactorStats,
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
};
```

## Methods

### `init(allocator: std.mem.Allocator) Redactor`

Initializes a new Redactor instance.

### `addPattern(pattern: RedactionPattern) !void`

Adds a new pattern-based redaction rule.

### `addField(field_name: []const u8, redaction_type: RedactionType) !void`

Adds a field-based redaction rule (for structured logging context).

### `redact(value: []const u8) ![]u8`

Applies redaction to a string value. Returns a new allocated string if redaction occurred, or a copy of the original.

## Presets

`RedactionPresets` provides common redaction rules.

### `RedactionPresets.standard()`

Includes common patterns for:
- Credit Card Numbers
- Email Addresses
- SSN / ID Numbers
- API Keys (generic patterns)

### `RedactionPresets.pci()`

PCI-DSS compliant redaction rules.

### `RedactionPresets.gdpr()`

GDPR compliant redaction rules (PII focus).
