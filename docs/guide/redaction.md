# Redaction

Logly-Zig v0.0.3+ provides automatic sensitive data masking to help maintain security and compliance. Redact passwords, API keys, credit card numbers, and other PII from log messages.

## Overview

The `Redactor` module enables you to:
- Automatically mask sensitive data in log messages
- Define custom patterns for different data types
- Use pattern matching: exact, prefix, suffix, contains, regex
- Apply different redaction types: full, partial, hashed
- Use pre-built presets for common compliance scenarios

## Basic Usage

```zig
const std = @import("std");
const logly = @import("logly");
const Redactor = logly.Redactor;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create a redactor
    var redactor = Redactor.init(allocator);
    defer redactor.deinit();

    // Add pattern for sensitive data
    // Parameters: name, pattern_type, pattern, replacement
    try redactor.addPattern(
        "password",
        .contains,
        "password=secret",
        "[REDACTED]",
    );

    // Redact a message
    const message = "User login password=secret success";
    const redacted = try redactor.redact(message);
    defer allocator.free(redacted);
    
    std.debug.print("{s}\n", .{redacted});
    // Output: User login [REDACTED] success
}
```

## Pattern Types

### Contains Match

Match any message containing a substring:

```zig
try redactor.addPattern("api_key", .contains, "api_key=", "[API_KEY_HIDDEN]");
```

### Prefix Match

Match patterns starting with a specific string:

```zig
try redactor.addPattern("bearer_token", .prefix, "Bearer ", "[TOKEN] ");
```

### Suffix Match

Match patterns ending with a specific string:

```zig
try redactor.addPattern("company_email", .suffix, "@company.com", "@[REDACTED]");
```

### Exact Match

Match exact strings:

```zig
try redactor.addPattern("secret_key", .exact, "supersecretkey123", "[HIDDEN]");
```

### Regex Match

Use regex-like patterns for complex matching:
Supports: `*` (any chars), `+` (one or more), `.` (single char), `\d` (digit), `\w` (word char), `\s` (whitespace)

```zig
// Credit card numbers
try redactor.addPattern("credit_card", .regex, 
    "\\d\\d\\d\\d-\\d\\d\\d\\d-\\d\\d\\d\\d-\\d\\d\\d\\d", 
    "****-****-****-****");

// Social Security Numbers
try redactor.addPattern("ssn", .regex, 
    "\\d\\d\\d-\\d\\d-\\d\\d\\d\\d", 
    "***-**-****");
```

## Field-Based Redaction

Add sensitive fields with different redaction types:

```zig
var redactor = Redactor.init(allocator);
defer redactor.deinit();

// Full redaction - replaces with "[REDACTED]"
try redactor.addField("password", .full);
try redactor.addField("secret", .full);

// Partial end - shows first 4 chars only
try redactor.addField("api_key", .partial_end);

// Partial start - shows last 4 chars only
try redactor.addField("email", .partial_start);

// Mask middle - shows first 3 and last 3 chars
try redactor.addField("credit_card", .mask_middle);

// Hash - replaces with SHA256 hash prefix
try redactor.addField("patient_id", .hash);
```

## Redaction Types

| Type | Input | Output |
|------|-------|--------|
| `.full` | `secret123` | `[REDACTED]` |
| `.partial_start` | `1234567890` | `******7890` |
| `.partial_end` | `1234567890` | `1234******` |
| `.mask_middle` | `1234567890` | `123****890` |
| `.hash` | `sensitive` | `[HASH:a1b2c3d4...]` |

## Redaction Presets

Logly provides pre-built redactor configurations for compliance scenarios:

```zig
const RedactionPresets = logly.RedactionPresets;

// Common sensitive data: password, secret, api_key, token, credit_card, ssn, email
var common = try RedactionPresets.common(allocator);
defer common.deinit();

// PCI-DSS compliance: pan, cvv, pin, card_number, expiry
var pci = try RedactionPresets.pciDss(allocator);
defer pci.deinit();

// HIPAA compliance: patient_id, ssn, dob, address, phone, email, medical_record
var hipaa = try RedactionPresets.hipaa(allocator);
defer hipaa.deinit();
```

## Production Example

```zig
const std = @import("std");
const logly = @import("logly");
const Redactor = logly.Redactor;
const RedactionPresets = logly.RedactionPresets;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Use common preset as a base
    var redactor = try RedactionPresets.common(allocator);
    defer redactor.deinit();

    // Add custom patterns
    try redactor.addPattern("bearer_token", .prefix, "Bearer ", "[TOKEN] ");
    try redactor.addPattern("credit_card", .regex, 
        "\\d\\d\\d\\d-\\d\\d\\d\\d-\\d\\d\\d\\d-\\d\\d\\d\\d",
        "****-****-****-****");

    // Redact messages before logging
    const message = "Processing payment for card 4532-1234-5678-9012";
    const redacted = try redactor.redact(message);
    defer allocator.free(redacted);
    
    std.debug.print("{s}\n", .{redacted});
    // Output: Processing payment for card ****-****-****-****
}
```

## Checking Field Redaction

```zig
var redactor = Redactor.init(allocator);
defer redactor.deinit();

try redactor.addField("password", .full);
try redactor.addField("api_key", .partial_end);

// Check if a field should be redacted
if (redactor.getFieldRedaction("password")) |redaction_type| {
    const value = "mysecretpassword";
    const redacted_value = try redaction_type.apply(allocator, value);
    defer allocator.free(redacted_value);
    // redacted_value is "[REDACTED]"
}
```

## Compliance Considerations

Redaction helps with compliance requirements like:

- **GDPR**: Mask personal data in logs
- **PCI-DSS**: Redact credit card numbers (use `RedactionPresets.pciDss`)
- **HIPAA**: Mask health information (use `RedactionPresets.hipaa`)
- **SOC 2**: Protect sensitive data in audit logs

## Best Practices

1. **Redact before logging**: Process messages before they reach sinks
2. **Test your patterns**: Verify patterns match what you expect
3. **Don't over-redact**: Avoid patterns that mask useful debugging info
4. **Use presets**: Start with `RedactionPresets` for compliance scenarios
5. **Document patterns**: Keep a list of what data types are being redacted
6. **Performance**: Complex regex patterns may impact performance

## See Also

- [Filtering](/guide/filtering) - Rule-based log filtering
- [Configuration](/guide/configuration) - Global configuration options
- [JSON Logging](/guide/json) - Structured JSON output
