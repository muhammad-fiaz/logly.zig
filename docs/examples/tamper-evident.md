---
title: Tamper-Evident Chaining Example
description: Cryptographic SHA-256 log record chaining in Logly.zig to guarantee audit log integrity.
head:
  - - meta
    - name: keywords
      content: tamper evident logging, sha256 log chaining, audit integrity, cryptographic logging
  - - meta
    - property: og:title
      content: Tamper-Evident Chaining Example | Logly.zig
---

# Tamper-Evident Chaining Example

Demonstrates SHA-256 cryptographic chaining on log records to detect tampering, line deletions, or unauthorized modifications.

## Code Example

```zig
const std = @import("std");
const logly = @import("logly");

fn onSignatureGenerated(sink_name: []const u8, signature: []const u8) void {
    std.debug.print("  [Signature Callback] Sink: '{s}', SHA-256: {s}\n", .{ sink_name, signature });
}

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const logPath = "logs/secure_audit.log";

    var config = logly.Config.default();
    config.autoSink = false;

    const logger = try logly.Logger.initWithConfig(allocator, config);
    defer logger.deinit();

    var sinkCfg = logly.SinkConfig.file(logPath);
    sinkCfg.name = "tamper_evident_audit_sink";
    sinkCfg.tamperEvident = true; // Enable SHA-256 chaining
    sinkCfg.asyncWrite = false;

    const sinkId = try logger.addSink(sinkCfg);
    if (logger.getSink(sinkId)) |sink| {
        sink.setSignatureCallback(&onSignatureGenerated);
    }

    try logger.info("User 'alice' authenticated from 10.0.0.1", null);
    try logger.warn("Privilege escalation requested for resource 'payment_gateway'", null);
    try logger.info("Access granted by policy rule #402", null);

    try logger.flush();
}
```

## How It Works

1. Each log record is hashed using SHA-256 alongside the previous record's signature.
2. The resulting digest is appended to the written log line in `[SIG:<hash>]` format.
3. If an attacker deletes or alters any line, all subsequent signatures fail verification.
