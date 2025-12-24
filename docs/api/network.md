# Network API

The `Network` module provides utilities for network-based logging, including TCP, UDP connections, HTTP requests, and Syslog support.

## Overview

This module is primarily used by network sinks but can be used directly for custom network operations. It includes statistics tracking and callback support for monitoring network operations.

## Types

### NetworkStats

Statistics for network operations.

```zig
pub const NetworkStats = struct {
    bytes_sent: std.atomic.Value(u64),
    bytes_received: std.atomic.Value(u64),
    connections_opened: std.atomic.Value(u64),
    connections_closed: std.atomic.Value(u64),
    connection_errors: std.atomic.Value(u64),
    send_errors: std.atomic.Value(u64),
    receive_errors: std.atomic.Value(u64),
    
    pub fn reset(self: *NetworkStats) void;
    pub fn errorRate(self: *const NetworkStats) f64;
};
```

### LogServer

A simple log server for receiving logs over TCP/UDP.

```zig
pub const LogServer = struct {
    allocator: std.mem.Allocator,
    protocol: Protocol,
    port: u16,
    running: std.atomic.Value(bool),
    stats: NetworkStats,
    
    pub const Protocol = enum { tcp, udp };
    
    pub fn init(allocator: std.mem.Allocator, protocol: Protocol, port: u16) !*LogServer;
    pub fn deinit(self: *LogServer) void;
    pub fn start(self: *LogServer) !void;
    pub fn stop(self: *LogServer) void;
};
```

### NetworkError

Common network errors.

```zig
pub const NetworkError = error{
    InvalidUri,
    ConnectionFailed,
    SocketCreationError,
    AddressResolutionError,
    RequestFailed,
    UnsupportedEncoding,
    ReadError,
};
```

## Functions

### `connectTcp(allocator: std.mem.Allocator, uri: []const u8) !std.net.Stream`

Connects to a TCP host specified by a URI string (e.g., "tcp://127.0.0.1:8080").

### `createUdpSocket(allocator: std.mem.Allocator, uri: []const u8) !struct { socket, address }`

Creates a UDP socket connected to a host specified by a URI string (e.g., "udp://127.0.0.1:514").

### `fetchJson(allocator: std.mem.Allocator, url: []const u8, headers: []const http.Header) !std.json.Parsed(std.json.Value)`

Fetches and parses a JSON response from a URL.

### `formatSyslog(allocator: std.mem.Allocator, record: *const Record, facility: u8) ![]u8`

Formats a log record as a Syslog message (RFC 5424).

## Aliases

The Network module provides convenience aliases:

| Alias | Method |
|-------|--------|
| `tcp` | `connectTcp` |
| `udp` | `createUdpSocket` |
| `http` | `fetchJson` |
| `syslog` | `formatSyslog` |
| `statistics` | `getStats` |

## Additional Methods

- `getStats() NetworkStats` - Returns current network statistics
- `resetStats() void` - Resets all network statistics
- `isConnected() bool` - Returns true if connected
- `reconnect() !void` - Reconnects to the server

## Network Sink Configuration

```zig
// TCP sink
const tcp_sink = logly.SinkConfig{
    .network = "tcp://logserver.example.com:8080",
    .json = true,
    .color = false,
};

// UDP sink (Syslog)
const udp_sink = logly.SinkConfig{
    .network = "udp://localhost:514",
    .syslog = true,
};
```

## Example

```zig
const logly = @import("logly");
const Network = logly.Network;

// Connect to TCP server
const stream = try Network.connectTcp(allocator, "tcp://localhost:8080");
defer stream.close();

// Create UDP socket for Syslog
const udp = try Network.createUdpSocket(allocator, "udp://localhost:514");
defer std.posix.close(udp.socket);

// Fetch JSON from URL
const json = try Network.fetchJson(allocator, "https://api.example.com/config", &.{});
defer json.deinit();
```

## See Also

- [Network Logging Guide](../guide/network-logging.md) - Network logging configuration
- [Sink API](sink.md) - Sink configuration
- [Logger API](logger.md) - Logger methods
