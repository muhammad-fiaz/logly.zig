---
title: Network Logging
description: Send logs over TCP and UDP with Logly.zig. Suited to centralized logging, shipping to collectors like Logstash, and remote application monitoring.
head:
  - - meta
    - name: keywords
      content: network logging, tcp logging, udp logging, centralized logging, logstash, fluentd, remote monitoring
  - - meta
    - property: og:title
      content: Network Logging | Logly.zig
  - - meta
    - property: og:image
      content: https://muhammad-fiaz.github.io/logly.zig/cover.png
---

# Network Logging

Logly supports sending logs over the network using TCP and UDP protocols. This is useful for centralized logging, shipping logs to log collectors (like Logstash, Fluentd, or Splunk), or monitoring applications remotely.

## Basic Usage

To enable network logging, add a network sink to your logger configuration.

```zig
const logly = @import("logly");

pub fn main() !void {
    var logger = try logly.Logger.init(allocator);
    defer logger.deinit();

    // TCP Sink
    var tcpSink = logly.SinkConfig.network("tcp://127.0.0.1:9000");
     _ = try logger.addSink(tcpSink);

    // UDP Sink
    var udpSink = logly.SinkConfig.network("udp://127.0.0.1:9001");
     _ = try logger.addSink(udpSink);

    try logger.info("This message goes to network sinks!", @src());
}
```

## Configuration Options

Network sinks support standard sink configuration options, plus protocol-specific behaviors.

### TCP vs UDP

*   **TCP**: Reliable delivery. The logger will establish a connection and keep it open. If the connection drops, it will attempt to reconnect. Good for critical logs where delivery is guaranteed.
*   **UDP**: Fire-and-forget. Faster and less overhead, but delivery is not guaranteed. Good for high-volume metrics or non-critical logs where occasional packet loss is acceptable.

### JSON Formatting

Network sinks are often used with log collectors that expect structured data. You can enable JSON formatting for the sink:

```zig
var sink = logly.SinkConfig.network("tcp://logs.example.com:5000");
sink.format = .json; // Send logs as JSON objects
 _ = try logger.addSink(sink);
```

### Colors

By default, network sinks do not send ANSI color codes. If you are streaming logs to a remote terminal or a viewer that supports ANSI colors, you can force enable them:

```zig
var sink = logly.SinkConfig.network("tcp://viewer.example.com:9000");
sink.color = true; // Force enable ANSI colors
 _ = try logger.addSink(sink);
```

## Example: Centralized Logging

You can set up a simple centralized logging server using `netcat` for testing:

**Server (Terminal 1):**
```bash
nc -l -k 9000
```

**Client (Zig Application):**
```zig
var sink = logly.SinkConfig.network("tcp://localhost:9000");
 _ = try logger.addSink(sink);
try logger.info("Hello from client!", @src());
```

## Network Helper APIs

Use the `Network` helpers directly when you need one-off sends outside of sinks:

```zig
const Network = logly.Network;

const stream = try Network.connectTcp(allocator, "tcp://127.0.0.1:9000");
defer stream.close(logly.Utils.io());
try Network.sendTcp(stream, "raw tcp log\n");

const udp = try Network.createUdpSocket(allocator, "udp://127.0.0.1:514");
defer udp.socket.close(logly.Utils.io());
try Network.sendSyslogUdp(
  allocator,
  udp.socket,
  udp.address,
  .user,
  .info,
  "localhost",
  "my-app",
  "syslog helper message",
);
```

## Reliability

*   **Async Logging**: It is highly recommended to use `asyncWrite = true` (default) for network sinks to avoid blocking your application if the network is slow or the server is unreachable.
*   **Buffering**: The async writer buffers logs and sends them in batches, improving network efficiency.
*   **Reconnection**: TCP sinks handle reconnection logic automatically.

## Syslog over TCP

Syslog over TCP is exposed through the `Network` helpers rather than a dedicated sink type. Connect a TCP stream and send an RFC 5424 message with an explicit facility and severity:

```zig
const Network = logly.Network;

const stream = try Network.connectTcp(allocator, "tcp://syslog-collector:514");
defer stream.close(logly.Utils.io());

try Network.sendSyslogTcp(
    allocator,
    stream,
    .local0,
    .info,
    "logly-host",
    "logly",
    "application started",
);
```

For UDP delivery, use `Network.sendSyslogUdp` with a socket from `Network.createUdpSocket`. To route logger records through a network sink, use `SinkConfig.network(uri)` and set `format` to `.syslog` or `.syslog3164`; the network sink reconnects on transport failure but does not add RFC 6587 octet-counting framing.

## Security

Currently, Logly supports plain TCP and UDP. For secure logging over public networks, consider using:
*   SSH tunneling
*   VPNs
*   Stunnel
*   A local log collector agent (e.g., Vector, Fluent Bit) that handles TLS encryption.

## See Also
- [Network API](/api/network) - Network reference API
- [Network Logging Example](/examples/network-logging) - High performance network logs example
