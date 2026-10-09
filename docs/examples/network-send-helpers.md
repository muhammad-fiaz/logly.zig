---
title: Network Send Helpers Example
description: Send raw TCP logs and syslog UDP messages with Logly.zig network helpers.
head:
  - - meta
    - name: keywords
      content: network send helpers, tcp log, syslog udp, zig logging
  - - meta
    - property: og:title
      content: Network Send Helpers Example | Logly.zig
---

# Network Send Helpers

Minimal TCP + syslog UDP delivery. Requires reachable test hosts.

```zig
const stream = try logly.Network.connectTcp(allocator, "tcp://127.0.0.1:9000");
defer stream.close(logly.Utils.io());
try logly.Network.sendTcp(stream, "hello over tcp\n");
```
