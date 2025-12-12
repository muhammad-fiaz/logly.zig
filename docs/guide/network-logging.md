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
    var tcp_sink = logly.SinkConfig.network("tcp://127.0.0.1:9000");
    _ = try logger.addSink(tcp_sink);

    // UDP Sink
    var udp_sink = logly.SinkConfig.network("udp://127.0.0.1:9001");
    _ = try logger.addSink(udp_sink);

    try logger.info("This message goes to network sinks!", .{});
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
sink.json = true; // Send logs as JSON objects
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
try logger.info("Hello from client!", .{});
```

## Reliability

*   **Async Logging**: It is highly recommended to use `async_write = true` (default) for network sinks to avoid blocking your application if the network is slow or the server is unreachable.
*   **Buffering**: The async writer buffers logs and sends them in batches, improving network efficiency.
*   **Reconnection**: TCP sinks handle reconnection logic automatically.

## Security

Currently, Logly supports plain TCP and UDP. For secure logging over public networks, consider using:
*   SSH tunneling
*   VPNs
*   Stunnel
*   A local log collector agent (e.g., Vector, Fluent Bit) that handles TLS encryption.
