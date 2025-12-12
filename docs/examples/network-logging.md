# Network Logging Example

This example demonstrates how to use Logly's network sinks to send logs over TCP and UDP, including support for JSON formatting and compression.

## Overview

Network logging allows you to centralize logs from multiple applications or instances. Logly supports:
- **TCP**: Reliable, connection-oriented logging.
- **UDP**: Fast, fire-and-forget logging.
- **JSON**: Structured logging for easy parsing by aggregators.
- **Compression**: Reduce bandwidth usage.

## Code Example

```zig
const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize logger
    var logger = try logly.Logger.init(allocator);
    defer logger.deinit();

    // 1. TCP Sink with Standard Format & Colors
    // Sends plain text logs to a TCP server.
    // We force enable colors so they show up on the remote viewer.
    var tcp_sink = logly.SinkConfig.network("tcp://127.0.0.1:9000");
    tcp_sink.name = "tcp-standard";
    tcp_sink.color = true; // Force ANSI colors
    const tcp_idx = try logger.addSink(tcp_sink);

    // Apply a custom theme to the TCP sink
    var theme = logly.Formatter.Theme{};
    theme.info = "36"; // Cyan
    theme.warning = "33"; // Yellow
    theme.err = "31"; // Red
    logger.sinks.items[tcp_idx].formatter.setTheme(theme);

    // 2. UDP Sink with JSON Format
    // Sends structured JSON logs to a UDP server.
    // Ideal for log aggregators like Logstash, Fluentd, or Graylog.
    var udp_json_sink = logly.SinkConfig.network("udp://127.0.0.1:9001");
    udp_json_sink.name = "udp-json";
    udp_json_sink.json = true;
    _ = try logger.addSink(udp_json_sink);

    // 3. Register Custom Levels
    try logger.addCustomLevel("AUDIT", 35, "34"); // Blue
    try logger.addCustomLevel("SECURITY", 45, "31"); // Red

    // Log some messages
    try logger.info("Application started", @src());
    try logger.warn("Connection latency high", @src());
    
    // Log with custom levels
    try logger.custom("AUDIT", "User login attempt", null);
    try logger.custom("SECURITY", "Invalid password attempt", null);

    // Ensure all logs are sent before exiting
    for (logger.sinks.items) |sink| {
        try sink.flush();
    }
}
```

## Running a Test Server

To test the network logging, you can use `netcat` (nc) to listen on the ports:

**TCP Listener:**
```bash
nc -l -p 9000
```

**UDP Listener:**
```bash
nc -u -l -p 9001
```

## Best Practices

1.  **Use JSON for Aggregators**: Most log management systems prefer structured data.
2.  **Use UDP for High Volume**: If dropping a few logs is acceptable in exchange for performance, UDP avoids head-of-line blocking.
3.  **Enable Compression for WAN**: If sending logs over the internet, compression can significantly reduce data transfer costs.
4.  **Handle Reconnections**: The TCP sink automatically attempts to reconnect if the connection is lost, but be aware that logs generated during downtime might be lost if the buffer fills up.
