# Network API

The `Network` module provides utilities for network-based logging, including TCP and UDP connections and HTTP requests.

## Overview

This module is primarily used by network sinks but can be used directly for custom network operations.

## Functions

### `connectTcp(allocator: std.mem.Allocator, uri: []const u8) !std.net.Stream`

Connects to a TCP host specified by a URI string (e.g., "tcp://127.0.0.1:8080").

### `createUdpSocket(allocator: std.mem.Allocator, uri: []const u8) !struct { socket: std.posix.socket_t, address: std.net.Address }`

Creates a UDP socket connected to a host specified by a URI string (e.g., "udp://127.0.0.1:514").

### `fetchJson(allocator: std.mem.Allocator, url: []const u8, headers: []const http.Header) !std.json.Parsed(std.json.Value)`

Fetches and parses a JSON response from a URL. Useful for retrieving configuration or updates.

## Types

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
