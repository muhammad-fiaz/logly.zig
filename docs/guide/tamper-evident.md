---
title: Cryptographic Tamper-Evident Logs
description: Protect your structured log files using Logly's native SHA-256 cryptographic chaining to prevent unauthorized modifications.
---

# Cryptographic Tamper-Evident Logs

In highly secure or compliant environments (such as financial transaction processors, healthcare services, and security auditing tools), log files are high-value targets. An attacker who gains unauthorized access to a system will frequently edit or delete log files to cover their tracks.

Logly addresses this security vector by introducing native **Cryptographic Tamper-Evident Logging**. Inspired by blockchain-style validation, Logly can cryptographically chain log records together. By embedding a SHA-256 hash of the current log record combined with the signature of the preceding record, Logly makes any unauthorized log insertion, modification, or deletion immediately detectable.

---

## Technical Architecture

In a standard file, each line is completely independent. In a tamper-evident file, each log record includes a cryptographic signature `SIG:<hash>` that binds it permanently to the history of the file:

```
[Record 1] Message: "User logged in"  --> Hash1 = SHA-256("User logged in" + Seed)       --> SIG:Hash1
[Record 2] Message: "Transfer complete" -> Hash2 = SHA-256("Transfer complete" + Hash1) --> SIG:Hash2
[Record 3] Message: "User logged out" --> Hash3 = SHA-256("User logged out" + Hash2)   --> SIG:Hash3
```

If an attacker attempts to modify `Record 2` (e.g., editing the transaction amount), the hash of `Record 2` changes. Consequently, the signature chain breaks, and `Record 3`'s signature immediately fails validation. Even if the attacker attempts to recalculate all subsequent hashes, they cannot reproduce valid signatures without the private startup initialization seed.

---

## Enabling Tamper-Evident Sinks

To enable cryptographic chaining on a file sink, set `tamper_evident = true` in your sink configuration:

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const logger = try logly.Logger.init(allocator);
    defer logger.deinit();

    // Create a secure file sink configuration
    var secure_sink = logly.SinkConfig.file("logs/secure_audit.log");
    secure_sink.name = "tamper_evident_sink";
    secure_sink.tamper_evident = true; // [!code hl] // Enable cryptographic signature chaining!

    // Add the sink
    _ = try logger.addSink(secure_sink);

    try logger.info("Securing this financial event with SHA-256 chaining.", @src());
    try logger.flush();
}
```

---

## How It Appears in Logs

When tamper-evident logging is active, every log record written to the file ends with a trailing `SIG:<hex>` signature:

```json
{"timestamp":1701234567890,"level":"INFO","message":"Securing this financial event with SHA-256 chaining.","sig":"8f3c7b2a...e90"}
```

If using a flat format, the signature is appended to the end of the line:

```
2026-05-24 10:50:33.123 [INFO] Securing this financial event with SHA-256 chaining. SIG:8f3c7b2a...e90
```

---

## Verifying Integrity

To verify a log file's integrity:
1. Initialize a SHA-256 context with the configured initialization seed.
2. Read the file line by line.
3. Extract the signature, compute the hash of the current content combined with the *previous* line's signature, and verify that it matches.
4. If a single line's signature does not match, a warning is raised and the exact index of the tampered line is identified.

---

## Best Practices & Compliance

> [!CAUTION]
> Cryptographic chaining detects tampering, but it cannot prevent deletion of the entire file. For complete compliance, combine `tamper_evident` logging with remote syslog forwarding so logs exist in multiple secure locations simultaneously.

* **Audit Regularly**: Integrate an automated cron task that checks log files using a validation script to catch discrepancies immediately.
* **Keep Seeds Secret**: The initialization seed used to start the hash chain should be loaded from a secure environment variable or key vault, never hardcoded in the source code.
* **Compliance Standards**: Enabling cryptographic chaining helps satisfy rigorous log integrity requirements for compliance standards such as **PCI-DSS (Req 10.5)**, **HIPAA**, and **GDPR**.
