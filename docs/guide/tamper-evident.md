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

To enable cryptographic chaining on a file sink, set `tamperEvident = true` in your sink configuration:

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
    secure_sink.tamperEvident = true; // [!code hl] // Enable cryptographic signature chaining!

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

Logly writes the chain values but does not ship a verifier; verification is
the responsibility of the audit tool consuming the file. The chain is:

1. Start with 32 zero bytes as the previous hash.
2. Read one record and remove its appended signature (` [SIG:<hex>]` for text,
   or the `"sig"` field for JSON).
3. Compute `SHA-256(previous_hash || record_bytes)`.
4. Compare the result with the signature stored in the record, then use it as
   the previous hash for the next record.
5. A mismatch identifies the first modified, inserted, or removed record.

---

## Best Practices & Compliance

> [!CAUTION]
> Cryptographic chaining detects tampering, but it cannot prevent deletion of the entire file. For complete compliance, combine `tamperEvident` logging with remote syslog forwarding so logs exist in multiple secure locations simultaneously.

* **Audit Regularly**: Verify the chain with an automated task so modifications are detected promptly.
* **Record Boundaries**: Verification must hash the exact record bytes before the signature was appended. Preserve line endings and serialization settings.
* **Compliance Standards**: Cryptographic chaining can support log-integrity controls, but compliance also depends on retention, access control, and monitoring.
