# Security Policy

## Supported Versions

Security updates are provided for currently supported releases.

| Version | Supported          |
| ------- | ------------------ |
| 0.2.2   | :white_check_mark: |
| 0.2.1   | :white_check_mark: |
| < 0.2.1 | :x:                |

Versions below **0.2.1** are end-of-life and will not receive security fixes.

## Zig Compatibility

- **0.2.2 or newer** requires **Zig 0.17.0+**
- **0.2.1** requires **Zig 0.16.x**
- **0.1.7 or earlier** requires **Zig 0.15.0**
- Zig downloads: [ziglang.org](https://ziglang.org/)

---

## Security Model

Logly is a logging library. It writes, formats, transports, and stores
potentially sensitive application data. Understand the following before
logging secrets, PII, or credentials.

### Redaction

Use `Redactor` (fields, patterns, presets) to mask secrets before output.
Redaction runs during record processing, before formatting and sinks.
Verify rules with `wouldRedact`/`previewRedaction` in tests.

Redaction is pattern-based, not a guarantee: review rules against actual
log output. Structured context values are redacted by field name; unknown
field names pass through unmasked.

### Log Injection

Messages containing newlines or control characters are passed through to
text sinks. JSON output escapes per RFC 8259. Log viewers that interpret
ANSI codes or HTML must sanitize independently; Logly does not neutralize
terminal escape sequences inside message content.

### ANSI Codes

Colors come from configuration (`tint.zig` values), not from message text.
Message content is never interpreted as color codes. File sinks default to
no colors; enabling colors in files writes raw escape bytes.

### Network Transport

TCP/UDP/syslog sinks send plaintext with no encryption, authentication,
or delivery acknowledgment. Do not send secrets over untrusted networks
unless tunneled (TLS/VPN). UDP delivery is best-effort by design.

### File Output

Log files inherit default OS permissions. Restrict sensitive log
directories yourself. Rotation renames files in place; archival and
compression preserve permissions of the containing directory.

### Crash Dumps

Panic/signal handlers flush sinks synchronously and print to stderr.
Crash output may include in-flight messages, stack addresses, and module
paths. Treat crash logs as potentially sensitive.

### Dependencies

- `tint.zig` 0.0.2 (colors, no I/O, no allocation)
- `brotli.zig` 0.0.4 (compression)
- `zstd.zig` 0.0.4 (compression)

Review dependency sources before use in sensitive environments.

---

## Reporting a Vulnerability

Report responsibly. Do not include live secrets or exploit details in
public issues for critical findings; use a private advisory instead.

**Where to report:**

- Open an issue: https://github.com/muhammad-fiaz/logly.zig/issues
- Or open a pull request with a fix (omit sensitive details)
- Or create a GitHub Security Advisory for private disclosure

**Include:**

- Affected version(s)
- Clear description
- Steps to reproduce
- Potential impact
- Suggested fix (optional)

**Timeline:**

- Acknowledgement: within 48 hours
- Initial review: within 5–7 days
- Resolution: depending on severity

Reports affecting unsupported versions, documented behavior, or already
fixed releases may be declined.

---

Thank you for helping keep this project secure.
