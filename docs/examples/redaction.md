---
title: Log Redaction Example
description: Example of automatic sensitive data masking with Logly.zig. Redact passwords, API keys, credit cards, and PII for security and GDPR compliance.
head:
  - - meta
    - name: keywords
      content: redaction example, data masking, pii protection, password masking, gdpr compliance, security logging
  - - meta
    - property: og:title
      content: Log Redaction Example | Logly.zig
---

# Redaction Example

Automatically mask sensitive data in log messages for compliance and security.

## Basic Redaction

```zig
const std = @import("std");
const logly = @import("logly");
const Redactor = logly.Redactor;

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create redactor
    var redactor = Redactor.init(allocator);
    defer redactor.deinit();

    // Add patterns to redact (name, pattern_type, pattern, replacement)
    try redactor.addPattern(
        "password",
        .contains,
        "password=secret123",
        "[REDACTED]",
    );

    // Redact sensitive data in a message
    const message = "User login password=secret123 success";
    const redacted = try redactor.redact(message);
    defer allocator.free(redacted);
    
    std.debug.print("Redacted: {s}\n", .{redacted});
    // Output: "User login [REDACTED] success"
}
```

## Pattern Types

```zig
// Exact match - entire string must match
try redactor.addPattern("exact_api_key", .exact, "api_key_12345", "[API_KEY_REDACTED]");

// Prefix match - matches if string starts with pattern
try redactor.addPattern("bearer_token", .prefix, "Bearer ", "[TOKEN] ");

// Suffix match - matches if string ends with pattern
try redactor.addPattern("company_email", .suffix, "@company.com", "@[REDACTED]");

// Contains - matches if pattern appears anywhere in string
try redactor.addPattern("ssn_mention", .contains, "SSN:", "SSN:[REDACTED]");

// Regex-like patterns
// Supports: * (any chars), + (one or more), . (single char), \d (digit), \w (word char), \s (whitespace)
try redactor.addPattern("ssn_format", .regex, "\\d\\d\\d-\\d\\d-\\d\\d\\d\\d", "***-**-****");
```

## Field-Based Redaction

```zig
// Add fields for redaction with different types
try redactor.addField("password", .full);         // -> "[REDACTED]"
try redactor.addField("secret", .full);           // -> "[REDACTED]"
try redactor.addField("api_key", .partialEnd);   // -> "api_********"
try redactor.addField("token", .partialEnd);     // -> "tok_********"
try redactor.addField("credit_card", .maskMiddle); // -> "411*****1234"
try redactor.addField("ssn", .maskMiddle);       // -> "123***6789"
try redactor.addField("email", .partialStart);   // -> "******@example.com"

// Check if a field should be redacted
if (redactor.getFieldRedaction("password")) |redactionType| {
    const redacted_value = try redactionType.apply(allocator, "mysecretpassword");
    defer allocator.free(redacted_value);
    // redacted_value is "[REDACTED]"
}
```

## Redaction Types

```zig
const RedactionType = Redactor.RedactionType;

// Full redaction - replaces entire value with "[REDACTED]"
const full = try RedactionType.full.apply(allocator, "secret");
// Result: "[REDACTED]"

// Partial start - masks all but last 4 characters
const partialStart = try RedactionType.partialStart.apply(allocator, "1234567890");
// Result: "******7890"

// Partial end - shows only first 4 characters
const partialEnd = try RedactionType.partialEnd.apply(allocator, "1234567890");
// Result: "1234******"

// Hash - replaces with SHA256 hash prefix
const hashed = try RedactionType.hash.apply(allocator, "sensitive");
// Result: "[HASH:a1b2c3d4...]"

// Mask middle - shows first 3 and last 3 characters
const masked = try RedactionType.maskMiddle.apply(allocator, "1234567890");
// Result: "123****890"
```

## Truncate and Hash Selection

```zig
var redactor = Redactor.init(allocator);
defer redactor.deinit();

redactor.config.truncateLength = 8;
redactor.config.truncateSuffix = "...";
redactor.config.hashAlgorithm = .sha512;

try redactor.addField("token", .truncate);
try redactor.addField("user_id", .hash);

const truncated = try redactor.redactField("token", "supersecretvalue");
defer allocator.free(truncated);
// truncated = "supersec..."
```

## Redaction Presets

```zig
const RedactionPresets = logly.RedactionPresets;

// Common sensitive data preset: password, secret, api_key, token, credit_card, ssn, email
var commonRedactor = try RedactionPresets.common(allocator);
defer commonRedactor.deinit();

// PCI-DSS compliance preset: pan, cvv, pin, card_number, expiry
var pci_redactor = try RedactionPresets.pciDss(allocator);
defer pci_redactor.deinit();

// HIPAA compliance preset: patient_id, ssn, dob, address, phone, email, medical_record
var hipaa_redactor = try RedactionPresets.hipaa(allocator);
defer hipaa_redactor.deinit();
```

## Credit Card Masking

```zig
try redactor.addPattern(
    "credit_card",
    .regex,
    "\\d\\d\\d\\d-\\d\\d\\d\\d-\\d\\d\\d\\d-\\d\\d\\d\\d",
    "****-****-****-****",
);

const message = try redactor.redact("Payment with card: 4111-1111-1111-1234");
defer allocator.free(message);
// Output: "Payment with card: ****-****-****-****"
```

## Compliance Use Cases

| Regulation | Data to Redact |
|------------|----------------|
| GDPR | Names, emails, IPs |
| HIPAA | Medical IDs, patient info |
| PCI-DSS | Credit cards, CVVs |
| SOX | Financial account numbers |

## Best Practices

1. **Redact at the source** - Apply redaction before logs leave the app
2. **Test patterns** - Verify patterns catch all sensitive data
3. **Audit regularly** - Review logs for missed PII
4. **Layer defenses** - Use redaction with encryption and access controls
5. **Document patterns** - Maintain list of redaction rules for compliance

## New Features (v0.1.8)
 
 ### Improved Regex Engine
 
 Redaction now supports a production-ready regex-like engine for pattern matching (see [Redaction Guide](/guide/redaction) for details).
 
## New Compliance Presets (v0.1.8)

```zig
const RedactionPresets = logly.RedactionPresets;

// GDPR compliance preset
var gdprRedactor = try RedactionPresets.gdpr(allocator);
defer gdprRedactor.deinit();

// API secrets preset (API keys, tokens, secrets)
var api_redactor = try RedactionPresets.apiSecrets(allocator);
defer api_redactor.deinit();

// Financial data preset (accounts, routing numbers)
var fin_redactor = try RedactionPresets.financial(allocator);
defer fin_redactor.deinit();
```

## Aliases

| Alias | Method |
|-------|--------|
| `addRule` | `addPattern` |
| `field` | `addField` |
| `sensitiveField` | `addField` |
| `mask` | `redact` |
| `sanitize` | `redact` |
| `statistics` | `getStats` |

## See Also

- [Redaction Guide](/guide/redaction) - Detailed redaction documentation
- [Redactor API](/api/redactor) - Full API reference

