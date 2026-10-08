---
title: Advanced Network Logging Example
description: Advanced Logly.zig network logging with TCP/UDP helpers, syslog, and JSON fetching.
head:
  - - meta
    - name: keywords
      content: network logging, tcp, udp, syslog, zig logging
  - - meta
    - property: og:title
      content: Advanced Network Logging Example | Logly.zig
---

# Advanced Network Logging

Raw helpers: `connectTcp`/`sendTcp`, UDP sockets, syslog senders, `fetchJson`. Requires reachable hosts.

```zig
const stream = try logly.Network.connectTcp(allocator, "tcp://127.0.0.1:9000");
defer stream.close(logly.Utils.io());
try logly.Network.sendTcp(stream, "raw tcp log\n");

const udp = try logly.Network.createUdpSocket(allocator, "udp://127.0.0.1:514");
defer udp.socket.close(logly.Utils.io());
try logly.Network.sendSyslogUdp(allocator, udp.socket, udp.address, .user, .info, "host", "app", "message");
```

> [!NOTE]
> UDP is datagram-based and does not guarantee delivery.
