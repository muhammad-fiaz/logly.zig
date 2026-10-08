---
title: Advanced Formatting Example
description: NDJSON, logfmt, syslog, and template formatting with Logly.zig.
head:
  - - meta
    - name: keywords
      content: advanced formatting, ndjson, logfmt, syslog, templates, zig logging
  - - meta
    - property: og:title
      content: Advanced Formatting Example | Logly.zig
---

# Advanced Formatting

NDJSON, logfmt, syslog, and aligned template output for the same record.

```zig
// NDJSON (one JSON object per line)
try formatter.formatJsonToWriter(&writer, &record, config);

// logfmt (key=value pairs)
try formatter.formatLogfmtToWriter(&writer, &record, config);

// Syslog (RFC5424)
try formatter.formatSyslogToWriter(&writer, &record, config);

// Template with alignment
config.logFormat = "[{level}] {time} | {message}";
```

Output:

```text
{"timestamp":"2026-10-07 05:57:20.148","level":"WARNING","message":"Database connection latency detected","module":"db.client","traceId":"trace-1234567890abcdef","spanId":"span-12345"}
```

```text
ts="2026-10-07 05:57:20.148" level=WARNING msg="Database connection latency detected" module=db.client traceId=trace-1234567890abcdef spanId=span-12345
```

```text
<12>1 2026-10-07T05:57:20.148Z UNKNOWN logly 1234 - - Database connection latency detected
```

```text
[WARNING ] 2026-10-07 05:57:20.148 | Database connection latency detected (module=db.client)
```
