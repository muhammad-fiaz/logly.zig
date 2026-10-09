---
title: Advanced Redaction Example
description: Email, IP, JWT, and Luhn redaction with presets and compliance audit logging in Logly.zig.
head:
  - - meta
    - name: keywords
      content: advanced redaction, email, ip, jwt, luhn, compliance audit, zig logging
  - - meta
    - property: og:title
      content: Advanced Redaction Example | Logly.zig
---

# Advanced Redaction

Pattern redaction for emails, IPv4/IPv6, JWTs, and Luhn-validated cards, plus GDPR/PCI presets and an audit log.

```zig
try redactor.addPattern("email", .email, "", "[EMAIL]");
try redactor.addPattern("ip", .ip, "", "[IP]");
try redactor.addPattern("jwt", .jwt, "", "[JWT]");
try redactor.addPattern("card", .luhn, "", "[CARD]");

var gdpr = try logly.RedactionPresets.gdprEmail(allocator);
defer gdpr.deinit();
```

Output:

```text
Original: Customer paid using 4111 1111 1111 1111 (Visa test card, valid Luhn)
Redacted: Customer paid using [CREDIT CARD REDACTED] (Visa test card, valid Luhn)

=== REDACTION COMPLIANCE AUDIT LOG ===
Total values processed: 4
Values redacted: 4
Redaction rate: 100.00%
```
