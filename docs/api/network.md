---
title: Network API Reference
description: API reference for Logly.zig Network module. TCP, UDP logging, HTTP endpoints, Syslog support, and network compression for centralized log aggregation.
head:
  - - meta
    - name: keywords
      content: network api, tcp logging, udp logging, syslog, remote logging, log aggregation, network sink
  - - meta
    - property: og:title
      content: Network API Reference | Logly.zig
---

# Network API

The `Network` module provides utilities for network-based logging, including TCP, UDP connections, HTTP requests, and Syslog support.

## Quick Reference: Method Aliases

| Full Method | Alias(es) | Description |
|-------------|-----------|-------------|
| `reset()` | `clear()`, `zero()` | Reset network statistics |
| `totalBytesSent()` | `bytesSent()`, `sentBytes()` | Get total bytes sent |
| `totalBytesReceived()` | `bytesReceived()`, `receivedBytes()` | Get total bytes received |
| `totalMessagesCount()` | `messagesCount()`, `messageCount()`, `totalMessages()` | Get total messages count |
| `totalConnectionsMade()` | `connectionsMade()`, `connectionCount()`, `totalConnections()` | Get total connections made |
| `totalErrors()` | `errorCount()` | Get total errors |
| `hasErrors()` | `hasFailures()`, `isError()` | Check if there are errors |
| `errorRate()` | `failureRate()` | Get error rate |
| `avgBytesPerMessage()` | `avgBytes()`, `bytesPerMessage()` | Get average bytes per message |
| `totalBytesTransferred()` | `bytesTransferred()`, `totalTransferred()` | Get total bytes transferred |
| `formatSyslog()` | `syslogFormat()`, `formatAsSyslog()` | Format message as syslog |
| `connectTcp()` | `tcpConnect()`, `connect()` | Connect to TCP endpoint |
| `createUdpSocket()` | `udpSocket()` | Create UDP socket |
| `sendUdp()` | `udpSend()`, `sendToUdp()` | Send UDP message |
| `sendTcp()` | `tcpSend()`, `sendToTcp()` | Send TCP message |
| `sendSyslogUdp()` | `syslogSend()`, `sendSyslog()` | Send syslog message over UDP |
| `fetchJson()` | `getJson()`, `httpGet()` | Fetch JSON from HTTP endpoint |
| `init()` | `create()` | Initialize log server |
| `deinit()` | `destroy()` | Deinitialize log server |
| `stop()` | `shutdown()`, `close()` | Stop log server |
| `isRunning()` | `isActive()` | Check if server is running |
| `messageCount()` | `messagesReceived()`, `receivedCount()` | Get message count |
| `startTcp()` | `listenTcp()` | Start TCP listener |
| `startUdp()` | `listenUdp()` | Start UDP listener |
| `createTcpSink()` | `tcpSink()` | Create TCP sink config |
| `createUdpSink()` | `udpSink()` | Create UDP sink config |
| `createSyslogSink()` | `syslogSink()` | Create syslog sink config |
| `getStats()` | `networkStats()`, `getNetworkStats()` | Get network statistics |
| `resetStats()` | `clearStats()`, `resetNetworkStats()` | Reset network statistics |

## Overview

This module is primarily used by network sinks but can be used directly for custom network operations. It includes statistics tracking and callback support for monitoring network operations.

## Types

### NetworkStats

Statistics for network operations.

```zig
pub const NetworkStats = struct {
    bytes_sent: std.atomic.Value(Constants.AtomicUnsigned),
    bytes_received: std.atomic.Value(Constants.AtomicUnsigned),
    messages_sent: std.atomic.Value(Constants.AtomicUnsigned),
    connections_made: std.atomic.Value(Constants.AtomicUnsigned),
    errors: std.atomic.Value(Constants.AtomicUnsigned),
};
```

#### Getter Methods

| Method | Return | Description |
|--------|--------|-------------|
| `totalBytesSent()` | `u64` | Get total bytes sent |
| `totalBytesReceived()` | `u64` | Get total bytes received |
| `totalMessagesCount()` | `u64` | Get total messages sent |
| `totalConnectionsMade()` | `u64` | Get total connections made |
| `totalErrors()` | `u64` | Get total error count |
| `totalBytesTransferred()` | `u64` | Get total bytes (sent + received) |

#### Boolean Checks

| Method | Return | Description |
|--------|--------|-------------|
| `hasErrors()` | `bool` | Check if any errors have occurred |

#### Rate Calculations

| Method | Return | Description |
|--------|--------|-------------|
| `errorRate()` | `f64` | Calculate error rate (0.0 - 1.0) |
| `avgBytesPerMessage()` | `f64` | Calculate average bytes per message |

#### Reset

| Method | Description |
|--------|-------------|
| `reset()` | Reset all statistics to initial state |

### LogServer

A simple log server for receiving logs over TCP/UDP.

```zig
pub const LogServer = struct {
    allocator: std.mem.Allocator,
    running: std.atomic.Value(bool),
    tcp_thread: ?std.Thread,
    udp_thread: ?std.Thread,
    messages_received: std.atomic.Value(Constants.AtomicUnsigned),
    
    pub fn init(allocator: std.mem.Allocator) LogServer;
    /// Alias for init()
    pub const create = init;

    pub fn deinit(self: *LogServer) void;
    /// Alias for deinit()
    pub const destroy = deinit;

    pub fn stop(self: *LogServer) void;
    /// Alias for stop()
    pub const shutdown = stop;
    pub const close = stop;

    pub fn isRunning(self: *const LogServer) bool;
    /// Alias for isRunning()
    pub const isActive = isRunning;

    pub fn messageCount(self: *const LogServer) u64;
    /// Alias for messageCount()
    pub const messagesReceived = messageCount;
    pub const receivedCount = messageCount;

    pub fn startTcp(self: *LogServer, port: u16, callback: *const fn ([]const u8) void) !void;
    /// Alias for startTcp()
    pub const listenTcp = startTcp;

    pub fn startUdp(self: *LogServer, port: u16, callback: *const fn ([]const u8) void) !void;
    /// Alias for startUdp()
    pub const listenUdp = startUdp;
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
    SendFailed,
    Timeout,
};
```

## Functions

### `connectTcp(allocator: std.mem.Allocator, uri: []const u8) !std.Io.net.Stream`

Connects to a TCP host specified by a URI string (e.g., "tcp://127.0.0.1:8080").

### `createUdpSocket(allocator: std.mem.Allocator, uri: []const u8) !struct { socket: std.Io.net.Socket, address: std.Io.net.IpAddress }`

Creates a UDP socket connected to a host specified by a URI string (e.g., "udp://127.0.0.1:514").

### `sendUdp(socket: std.Io.net.Socket, address: std.Io.net.IpAddress, data: []const u8) !void`

Sends data via UDP socket.

### `sendTcp(stream: std.Io.net.Stream, data: []const u8) !void`

Sends data via TCP stream and updates network stats.

### `sendSyslogUdp(allocator: std.mem.Allocator, socket: std.Io.net.Socket, address: std.Io.net.IpAddress, facility: SyslogFacility, severity: SyslogSeverity, hostname: []const u8, app_name: []const u8, message: []const u8) !void`

Formats a syslog message and sends it over UDP.

### `fetchJson(allocator: std.mem.Allocator, url: []const u8, headers: []const http.Header) !std.json.Parsed(std.json.Value)`

Fetches and parses a JSON response from a URL.

### `formatSyslog(allocator: std.mem.Allocator, facility: SyslogFacility, severity: SyslogSeverity, hostname: []const u8, app_name: []const u8, message: []const u8) ![]u8`

Formats a log message as a Syslog message (RFC 5424). Uses `Constants.SyslogConstants.Severity` and `Constants.SyslogConstants.Facility` for the enums.

## Aliases

The Network module provides convenience aliases:

| Alias | Method |
|-------|--------|
| `tcpConnect` | `connectTcp` |
| `connect` | `connectTcp` |
| `udpSocket` | `createUdpSocket` |
| `udpSend` | `sendUdp` |
| `sendToUdp` | `sendUdp` |
| `tcpSend` | `sendTcp` |
| `sendToTcp` | `sendTcp` |
| `syslogSend` | `sendSyslogUdp` |
| `sendSyslog` | `sendSyslogUdp` |
| `getJson` | `fetchJson` |
| `httpGet` | `fetchJson` |
| `syslogFormat` | `formatSyslog` |
| `formatAsSyslog` | `formatSyslog` |
| `networkStats` | `getStats` |
| `getNetworkStats` | `getStats` |
| `clearStats` | `resetStats` |
| `resetNetworkStats` | `resetStats` |
| `tcpSink` | `createTcpSink` |
| `udpSink` | `createUdpSink` |
| `syslogSink` | `createSyslogSink` |

## Additional Methods

- `getStats() NetworkStats` - Returns current network statistics
- `resetStats() void` - Resets all network statistics

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
const io = logly.Utils.io();

// Connect to TCP server
const stream = try Network.connectTcp(allocator, "tcp://localhost:8080");
defer stream.close(io);

// Create UDP socket for Syslog
const udp = try Network.createUdpSocket(allocator, "udp://localhost:514");
defer udp.socket.close(io);

// Send UDP data
try Network.sendUdp(udp.socket, udp.address, "Hello Syslog");

// Fetch JSON from URL
const json = try Network.fetchJson(allocator, "https://api.example.com/config", &.{});
defer json.deinit();

// Format Syslog message
const syslog_msg = try Network.formatSyslog(allocator, .user, .info, "localhost", "myapp", "Log message");
defer allocator.free(syslog_msg);

// Get network statistics
const stats = Network.getStats();
std.debug.print("Bytes sent: {}\n", .{stats.totalBytesSent()});
```

## See Also

- [Network Logging Guide](../guide/network-logging.md) - Network logging configuration
- [Sink API](sink.md) - Sink configuration
- [Logger API](logger.md) - Logger methods
