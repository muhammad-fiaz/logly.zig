//! Network Logging Module
//!
//! Provides network-based log transport for distributed logging systems.
//! Supports TCP, UDP, and Syslog protocols for remote log collection.
//!
//! Components:
//! - TCP/UDP Connections: Direct network connections for log streaming
//! - Syslog Support: RFC 5424 compliant syslog message formatting
//! - LogServer: Simple TCP/UDP log receiver for testing
//! - Network Statistics: Throughput and error monitoring
//!
//! Protocols:
//! - tcp://host:port - TCP stream connection
//! - udp://host:port - UDP datagram connection
//! - Syslog (UDP port 514) - Standard syslog protocol
//!
//! Thread Safety:
//! All network operations are thread-safe with atomic statistics.

const std = @import("std");
const builtin = @import("builtin");
const http = std.http;
const SinkConfig = @import("sink.zig").SinkConfig;
const Constants = @import("constants.zig");
const Utils = @import("utils.zig");
const Config = @import("config.zig");

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

/// Network statistics for monitoring.
pub const NetworkStats = struct {
    bytes_sent: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
    bytes_received: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
    messages_sent: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
    connections_made: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
    errors: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),

    pub fn reset(self: *NetworkStats) void {
        self.bytes_sent.store(0, .monotonic);
        self.bytes_received.store(0, .monotonic);
        self.messages_sent.store(0, .monotonic);
        self.connections_made.store(0, .monotonic);
        self.errors.store(0, .monotonic);
    }

    /// Alias for reset
    pub const clear = reset;
    pub const zero = reset;

    pub fn totalBytesSent(self: *const NetworkStats) u64 {
        return Utils.atomicLoadU64(&self.bytes_sent);
    }

    /// Alias for totalBytesSent
    pub const bytesSent = totalBytesSent;
    pub const sentBytes = totalBytesSent;

    pub fn totalBytesReceived(self: *const NetworkStats) u64 {
        return Utils.atomicLoadU64(&self.bytes_received);
    }

    /// Alias for totalBytesReceived
    pub const bytesReceived = totalBytesReceived;
    pub const receivedBytes = totalBytesReceived;

    pub fn totalMessagesCount(self: *const NetworkStats) u64 {
        return Utils.atomicLoadU64(&self.messages_sent);
    }

    /// Alias for totalMessagesCount
    pub const messagesCount = totalMessagesCount;
    pub const messageCount = totalMessagesCount;
    pub const totalMessages = totalMessagesCount;

    pub fn totalConnectionsMade(self: *const NetworkStats) u64 {
        return Utils.atomicLoadU64(&self.connections_made);
    }

    /// Alias for totalConnectionsMade
    pub const connectionsMade = totalConnectionsMade;
    pub const connectionCount = totalConnectionsMade;
    pub const totalConnections = totalConnectionsMade;

    pub fn totalErrors(self: *const NetworkStats) u64 {
        return Utils.atomicLoadU64(&self.errors);
    }

    /// Alias for totalErrors
    pub const errorCount = totalErrors;

    /// Checks if any network errors occurred.
    pub fn hasErrors(self: *const NetworkStats) bool {
        return self.errors.load(.monotonic) > 0;
    }

    /// Alias for hasErrors
    pub const hasFailures = hasErrors;
    pub const isError = hasErrors;

    /// Calculate error rate (0.0 - 1.0) based on messages sent.
    pub fn errorRate(self: *const NetworkStats) f64 {
        const sent = Utils.atomicLoadU64(&self.messages_sent);
        const errs = Utils.atomicLoadU64(&self.errors);
        return Utils.calculateErrorRate(errs, sent);
    }

    /// Alias for errorRate
    pub const failureRate = errorRate;

    /// Calculate average bytes per message.
    pub fn avgBytesPerMessage(self: *const NetworkStats) f64 {
        const bytes = Utils.atomicLoadU64(&self.bytes_sent);
        const messages = Utils.atomicLoadU64(&self.messages_sent);
        return Utils.calculateAverage(bytes, messages);
    }

    /// Alias for avgBytesPerMessage
    pub const avgBytes = avgBytesPerMessage;
    pub const bytesPerMessage = avgBytesPerMessage;

    /// Returns total bytes transferred (sent + received).
    pub fn totalBytesTransferred(self: *const NetworkStats) u64 {
        return Utils.atomicLoadU64(&self.bytes_sent) + Utils.atomicLoadU64(&self.bytes_received);
    }

    /// Alias for totalBytesTransferred
    pub const bytesTransferred = totalBytesTransferred;
    pub const totalTransferred = totalBytesTransferred;
};

/// Global network stats
pub var stats: NetworkStats = .{};

/// Syslog severity levels (RFC 5424)
pub const SyslogSeverity = Constants.SyslogConstants.Severity;

/// Syslog facilities (RFC 5424)
pub const SyslogFacility = Constants.SyslogConstants.Facility;

pub fn formatSyslog(
    allocator: std.mem.Allocator,
    facility: SyslogFacility,
    severity: SyslogSeverity,
    hostname: []const u8,
    app_name: []const u8,
    message: []const u8,
) ![]u8 {
    const priority = (@as(u8, @intFromEnum(facility)) * 8) + @as(u8, @intFromEnum(severity));
    const timestamp = Utils.currentSeconds();

    var res = std.Io.Writer.Allocating.init(allocator);
    errdefer res.deinit();
    const w = &res.writer;

    try w.writeByte('<');
    try Utils.writeInt(w, priority);
    try w.writeAll(">1 ");
    try Utils.writeInt(w, @as(u64, @intCast(timestamp)));
    try w.writeByte(' ');
    try w.writeAll(hostname);
    try w.writeByte(' ');
    try w.writeAll(app_name);
    try w.writeAll(" - - - ");
    try w.writeAll(message);
    try w.writeByte('\n');

    return res.toOwnedSlice();
}

/// Alias for formatSyslog
pub const syslogFormat = formatSyslog;
pub const formatAsSyslog = formatSyslog;

/// Connects to a TCP host specified by a URI string (e.g., "tcp://127.0.0.1:8080").
/// Returns a std.Io.net.Stream.
pub fn connectTcp(allocator: std.mem.Allocator, uri: []const u8) !std.Io.net.Stream {
    if (!std.mem.startsWith(u8, uri, "tcp://")) return NetworkError.InvalidUri;
    const address_part = uri[6..];

    if (std.mem.indexOfScalar(u8, address_part, ':')) |colon_idx| {
        const host = address_part[0..colon_idx];
        const port_str = address_part[colon_idx + 1 ..];
        const port = std.fmt.parseInt(u16, port_str, 10) catch return NetworkError.InvalidUri;

        _ = allocator;
        const host_name = std.Io.net.HostName.init(host) catch return NetworkError.InvalidUri;
        const stream = host_name.connect(Utils.io(), port, .{ .mode = .stream, .protocol = .tcp }) catch return NetworkError.ConnectionFailed;
        _ = stats.connections_made.fetchAdd(1, .monotonic);
        return stream;
    }
    return NetworkError.InvalidUri;
}

/// Alias for connectTcp
pub const tcpConnect = connectTcp;
pub const connect = connectTcp;

/// Creates a UDP socket connected to a host specified by a URI string (e.g., "udp://127.0.0.1:514").
/// Returns a tuple of (socket, address).
pub fn createUdpSocket(allocator: std.mem.Allocator, uri: []const u8) !struct { socket: std.Io.net.Socket, address: std.Io.net.IpAddress } {
    if (!std.mem.startsWith(u8, uri, "udp://")) return NetworkError.InvalidUri;
    const address_part = uri[6..];

    if (std.mem.indexOfScalar(u8, address_part, ':')) |colon_idx| {
        const host = address_part[0..colon_idx];
        const port_str = address_part[colon_idx + 1 ..];
        const port = std.fmt.parseInt(u16, port_str, 10) catch return NetworkError.InvalidUri;

        _ = allocator;
        const address = std.Io.net.IpAddress.parse(host, port) catch return NetworkError.AddressResolutionError;
        {
            const local_address = switch (address) {
                .ip4 => std.Io.net.IpAddress.parse("0.0.0.0", 0) catch unreachable,
                .ip6 => std.Io.net.IpAddress.parse("::", 0) catch unreachable,
            };
            const socket = local_address.bind(Utils.io(), .{ .mode = .dgram, .protocol = .udp }) catch return NetworkError.SocketCreationError;
            _ = stats.connections_made.fetchAdd(1, .monotonic);
            return .{ .socket = socket, .address = address };
        }
    }
    return NetworkError.InvalidUri;
}

/// Alias for createUdpSocket
pub const udpSocket = createUdpSocket;

/// Sends data via UDP socket.
pub fn sendUdp(socket: std.Io.net.Socket, address: std.Io.net.IpAddress, data: []const u8) !void {
    socket.send(Utils.io(), &address, data) catch {
        _ = stats.errors.fetchAdd(1, .monotonic);
        return NetworkError.SendFailed;
    };
    _ = stats.bytes_sent.fetchAdd(@truncate(data.len), .monotonic);
    _ = stats.messages_sent.fetchAdd(1, .monotonic);
}

/// Sends data via a TCP stream.
pub fn sendTcp(stream: std.Io.net.Stream, data: []const u8) !void {
    var buffer: [Constants.BufferSizes.message]u8 = undefined;
    var writer = stream.writer(Utils.io(), &buffer);
    writer.interface.writeAll(data) catch {
        _ = stats.errors.fetchAdd(1, .monotonic);
        return NetworkError.SendFailed;
    };
    writer.interface.flush() catch {
        _ = stats.errors.fetchAdd(1, .monotonic);
        return NetworkError.SendFailed;
    };
    _ = stats.bytes_sent.fetchAdd(@truncate(data.len), .monotonic);
    _ = stats.messages_sent.fetchAdd(1, .monotonic);
}

/// Formats a syslog message and sends it via UDP.
pub fn sendSyslogUdp(
    allocator: std.mem.Allocator,
    socket: std.Io.net.Socket,
    address: std.Io.net.IpAddress,
    facility: SyslogFacility,
    severity: SyslogSeverity,
    hostname: []const u8,
    app_name: []const u8,
    message: []const u8,
) !void {
    const formatted = try formatSyslog(allocator, facility, severity, hostname, app_name, message);
    defer allocator.free(formatted);
    try sendUdp(socket, address, formatted);
}

/// Formats a syslog message and sends it via TCP.
pub fn sendSyslogTcp(
    allocator: std.mem.Allocator,
    stream: std.Io.net.Stream,
    facility: SyslogFacility,
    severity: SyslogSeverity,
    hostname: []const u8,
    app_name: []const u8,
    message: []const u8,
) !void {
    const formatted = try formatSyslog(allocator, facility, severity, hostname, app_name, message);
    defer allocator.free(formatted);
    try sendTcp(stream, formatted);
}

/// Alias for sendUdp
pub const udpSend = sendUdp;
pub const sendToUdp = sendUdp;

/// Alias for sendTcp
pub const tcpSend = sendTcp;
pub const sendToTcp = sendTcp;

/// Alias for sendSyslogUdp
pub const syslogSend = sendSyslogUdp;
pub const sendSyslog = sendSyslogUdp;
pub const sendSyslogTcp_ = sendSyslogTcp;

/// Fetches a JSON response from a URL.
/// Returns the parsed JSON value (caller must deinit).
pub fn fetchJson(allocator: std.mem.Allocator, url: []const u8, headers: []const http.Header) !std.json.Parsed(std.json.Value) {
    var client = http.Client{ .allocator = allocator, .io = Utils.io() };
    defer client.deinit();

    var req = try client.request(.GET, try std.Uri.parse(url), .{
        .headers = .{ .user_agent = .{ .override = std.fmt.comptimePrint("logly.zig/{s}", .{builtin.zig_version_string}) } },
        .extra_headers = headers,
    });
    defer req.deinit();

    try req.sendBodiless();

    const redirect_buffer = try allocator.alloc(u8, Constants.NetworkConstants.tcp_buffer_size);
    defer allocator.free(redirect_buffer);

    var response = try req.receiveHead(redirect_buffer);
    if (response.head.status != .ok) return NetworkError.RequestFailed;

    const decompress_buffer: []u8 = switch (response.head.content_encoding) {
        .identity => &.{},
        .zstd => try allocator.alloc(u8, std.compress.zstd.default_window_len),
        .deflate, .gzip => try allocator.alloc(u8, std.compress.flate.max_window_len),
        .compress => return NetworkError.UnsupportedEncoding,
    };
    defer if (decompress_buffer.len != 0) allocator.free(decompress_buffer);

    var transfer_buffer: [64]u8 = undefined;
    var decompress: http.Decompress = undefined;
    var reader = response.readerDecompressing(&transfer_buffer, &decompress, decompress_buffer);

    var body = std.ArrayList(u8).initCapacity(allocator, Constants.BufferSizes.message) catch return NetworkError.ReadError;
    defer body.deinit(allocator);

    var body_writer = Utils.ArrayListWriter.init(&body, allocator);
    const writer = &body_writer.writer;
    var buf: [Constants.BufferSizes.message]u8 = undefined;
    while (true) {
        const n = reader.readSliceShort(&buf) catch return NetworkError.ReadError;
        if (n == 0) break;
        try writer.writeAll(buf[0..n]);
    }

    _ = stats.bytes_received.fetchAdd(@truncate(body.items.len), .monotonic);
    return std.json.parseFromSlice(std.json.Value, allocator, body.items, .{});
}

/// Alias for fetchJson
pub const getJson = fetchJson;
pub const httpGet = fetchJson;

/// A simple log server that can listen on TCP and UDP ports.
/// Useful for testing network logging or building simple log collectors.
pub const LogServer = struct {
    allocator: std.mem.Allocator,
    running: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    tcp_thread: ?std.Thread = null,
    udp_thread: ?std.Thread = null,
    tcp_port: u16 = 0,
    udp_port: u16 = 0,
    messages_received: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),

    pub fn init(allocator: std.mem.Allocator) LogServer {
        return .{
            .allocator = allocator,
        };
    }

    /// Alias for init().
    pub const create = init;

    pub fn deinit(self: *LogServer) void {
        self.stop();
    }

    /// Alias for deinit().
    pub const destroy = deinit;

    pub fn stop(self: *LogServer) void {
        self.running.store(false, .monotonic);
        self.wakeTcpWorker();
        self.wakeUdpWorker();
        if (self.tcp_thread) |t| t.join();
        if (self.udp_thread) |t| t.join();
        self.tcp_thread = null;
        self.udp_thread = null;
        self.tcp_port = 0;
        self.udp_port = 0;
    }

    /// Alias for stop
    pub const shutdown = stop;
    pub const close = stop;

    pub fn isRunning(self: *const LogServer) bool {
        return self.running.load(.monotonic);
    }

    /// Alias for isRunning
    pub const isActive = isRunning;

    pub fn messageCount(self: *const LogServer) u64 {
        return @as(u64, self.messages_received.load(.monotonic));
    }

    /// Alias for messageCount
    pub const messagesReceived = messageCount;
    pub const receivedCount = messageCount;

    pub fn startTcp(self: *LogServer, port: u16, callback: *const fn ([]const u8) void) !void {
        self.running.store(true, .monotonic);
        self.tcp_port = port;
        self.tcp_thread = try std.Thread.spawn(.{}, tcpWorker, .{ self, port, callback });
    }

    /// Alias for startTcp
    pub const listenTcp = startTcp;

    pub fn startUdp(self: *LogServer, port: u16, callback: *const fn ([]const u8) void) !void {
        self.running.store(true, .monotonic);
        self.udp_port = port;
        self.udp_thread = try std.Thread.spawn(.{}, udpWorker, .{ self, port, callback });
    }

    /// Alias for startUdp
    pub const listenUdp = startUdp;

    fn wakeTcpWorker(self: *LogServer) void {
        if (self.tcp_thread == null or self.tcp_port == 0) return;
        const host_name = std.Io.net.HostName.init("127.0.0.1") catch return;
        const stream = host_name.connect(Utils.io(), self.tcp_port, .{ .mode = .stream, .protocol = .tcp }) catch return;
        stream.close(Utils.io());
    }

    fn wakeUdpWorker(self: *LogServer) void {
        if (self.udp_thread == null or self.udp_port == 0) return;
        const address = std.Io.net.IpAddress.parse("127.0.0.1", self.udp_port) catch return;
        const local_address = std.Io.net.IpAddress.parse("0.0.0.0", 0) catch return;
        const socket = local_address.bind(Utils.io(), .{ .mode = .dgram, .protocol = .udp }) catch return;
        defer socket.close(Utils.io());
        socket.send(Utils.io(), &address, "") catch {};
    }

    fn tcpWorker(self: *LogServer, port: u16, callback: *const fn ([]const u8) void) void {
        const io = Utils.io();
        const address = std.Io.net.IpAddress.parse("0.0.0.0", port) catch return;
        var server = address.listen(io, .{ .reuse_address = true }) catch return;
        defer server.deinit(io);

        while (self.running.load(.monotonic)) {
            const stream = server.accept(io) catch continue;

            const thread = std.Thread.spawn(.{}, tcpClientHandler, .{ self, stream, callback }) catch {
                stream.close(io);
                continue;
            };
            thread.detach();
        }
    }

    fn tcpClientHandler(self: *LogServer, stream: std.Io.net.Stream, callback: *const fn ([]const u8) void) void {
        const io = Utils.io();
        defer stream.close(io);
        var buf: [Constants.NetworkConstants.tcp_buffer_size]u8 = undefined;
        var reader = stream.reader(io, &buf);
        while (self.running.load(.monotonic)) {
            const read = reader.interface.readSliceShort(&buf) catch break;
            if (read == 0) break;
            _ = self.messages_received.fetchAdd(1, .monotonic);
            callback(buf[0..read]);
        }
    }

    fn udpWorker(self: *LogServer, port: u16, callback: *const fn ([]const u8) void) void {
        const io = Utils.io();
        const address = std.Io.net.IpAddress.parse("0.0.0.0", port) catch return;
        const socket = address.bind(io, .{ .mode = .dgram, .protocol = .udp }) catch return;
        defer socket.close(io);

        var buf: [Constants.NetworkConstants.udp_max_packet]u8 = undefined;
        while (self.running.load(.monotonic)) {
            const message = socket.receive(io, &buf) catch continue;
            if (message.data.len == 0) continue;
            _ = self.messages_received.fetchAdd(1, .monotonic);
            callback(message.data);
        }
    }
};

/// Creates a TCP network sink configuration.
pub fn createTcpSink(host: []const u8, port: u16) !SinkConfig {
    const uri = try std.fmt.allocPrint(std.heap.page_allocator, "tcp://{s}:{d}", .{ host, port });
    return SinkConfig{
        .path = uri,
        .color = false,
        .async_write = true,
    };
}

/// Creates a UDP network sink configuration.
pub fn createUdpSink(host: []const u8, port: u16) !SinkConfig {
    const uri = try std.fmt.allocPrint(std.heap.page_allocator, "udp://{s}:{d}", .{ host, port });
    return SinkConfig{
        .path = uri,
        .color = false,
        .async_write = true,
    };
}

pub fn createSyslogSink(host: []const u8) !SinkConfig {
    return createUdpSink(host, Constants.SyslogConstants.default_port);
}

/// Aliases for sink creation
pub const tcpSink = createTcpSink;
pub const udpSink = createUdpSink;
pub const syslogSink = createSyslogSink;

/// Returns global network statistics.
pub fn getStats() NetworkStats {
    return stats;
}

/// Resets global network statistics.
pub fn resetStats() void {
    stats.reset();
}

pub const ConnectionState = enum {
    disconnected,
    connecting,
    connected,
    failed,
};

/// An advanced network-based log sink manager.
/// Manages TCP/UDP connections with automatic reconnect, retry budgets, keepalive, and specialized framing.
pub const NetworkSink = struct {
    allocator: std.mem.Allocator,
    uri: []const u8,
    state: ConnectionState = .disconnected,
    stream: ?std.Io.net.Stream = null,
    udp_socket: ?std.Io.net.Socket = null,
    udp_addr: ?std.Io.net.IpAddress = null,
    keepalive: bool = true,
    http_chunked: bool = false,
    syslog_format: bool = false,
    max_retries: u32 = Constants.TimeDefaults.max_retries,
    retry_delay_ms: u64 = Constants.TimeDefaults.retry_delay_ms,
    consecutive_errors: u32 = 0,

    pub fn init(allocator: std.mem.Allocator, uri: []const u8) !NetworkSink {
        return .{
            .allocator = allocator,
            .uri = try allocator.dupe(u8, uri),
        };
    }

    pub fn deinit(self: *NetworkSink) void {
        self.disconnect();
        self.allocator.free(self.uri);
    }

    pub fn disconnect(self: *NetworkSink) void {
        if (self.stream) |s| {
            s.close(Utils.io());
            self.stream = null;
        }
        if (self.udp_socket) |s| {
            s.close(Utils.io());
            self.udp_socket = null;
        }
        self.state = .disconnected;
    }

    pub fn connect(self: *NetworkSink) !void {
        self.state = .connecting;
        self.consecutive_errors = 0;

        var attempt: u32 = 0;
        var delay = self.retry_delay_ms;

        while (attempt < self.max_retries) : (attempt += 1) {
            if (std.mem.startsWith(u8, self.uri, "tcp://")) {
                if (connectTcp(self.allocator, self.uri)) |s| {
                    self.stream = s;
                    self.state = .connected;
                    if (self.keepalive) {
                        if (builtin.os.tag != .windows) {
                            if (@hasField(std.Io.net.Stream, "socket")) {
                                if (std.posix.setsockopt(s.socket.handle, std.posix.SOL.SOCKET, std.posix.SO.KEEPALIVE, &std.mem.toBytes(@as(c_int, 1)))) |_| {} else |_| {}
                            }
                        }
                    }
                    return;
                } else |err| {
                    self.consecutive_errors += 1;
                    if (attempt + 1 == self.max_retries) {
                        self.state = .failed;
                        return err;
                    }
                }
            } else if (std.mem.startsWith(u8, self.uri, "udp://")) {
                if (createUdpSocket(self.allocator, self.uri)) |udp| {
                    self.udp_socket = udp.socket;
                    self.udp_addr = udp.address;
                    self.state = .connected;
                    return;
                } else |err| {
                    self.consecutive_errors += 1;
                    if (attempt + 1 == self.max_retries) {
                        self.state = .failed;
                        return err;
                    }
                }
            } else {
                self.state = .failed;
                return NetworkError.InvalidUri;
            }

            // Exponential backoff
            Utils.sleepMs(delay);
            delay *= 2;
        }
        self.state = .failed;
        return NetworkError.ConnectionFailed;
    }

    pub fn write(self: *NetworkSink, data: []const u8) !void {
        if (self.state != .connected) {
            try self.connect();
        }

        var data_to_send = data;
        var allocated: ?[]u8 = null;
        defer if (allocated) |slice| self.allocator.free(slice);

        if (self.syslog_format) {
            allocated = try formatSyslog(self.allocator, .user, .info, "localhost", "logly", data);
            data_to_send = allocated.?;
        }

        if (self.http_chunked) {
            // chunked format: <size_hex>\r\n<data>\r\n
            var chunk_buf: [32]u8 = undefined;
            const chunk_hdr = try std.fmt.bufPrint(&chunk_buf, "{x}\r\n", .{data_to_send.len});

            var chunked_msg: std.ArrayList(u8) = .empty;
            defer chunked_msg.deinit(self.allocator);
            try chunked_msg.appendSlice(self.allocator, chunk_hdr);
            try chunked_msg.appendSlice(self.allocator, data_to_send);
            try chunked_msg.appendSlice(self.allocator, "\r\n");

            try self.writeRaw(chunked_msg.items);
        } else {
            try self.writeRaw(data_to_send);
        }
    }

    fn writeRaw(self: *NetworkSink, data: []const u8) !void {
        var attempt: u32 = 0;
        var delay = self.retry_delay_ms;

        while (attempt < self.max_retries) : (attempt += 1) {
            if (self.stream) |s| {
                sendTcp(s, data) catch |err| {
                    self.consecutive_errors += 1;
                    if (attempt + 1 == self.max_retries) {
                        self.state = .failed;
                        return err;
                    }
                    // Try auto-reconnect
                    self.disconnect();
                    _ = self.connect() catch {};
                };
                return;
            } else if (self.udp_socket) |s| {
                if (self.udp_addr) |addr| {
                    sendUdp(s, addr, data) catch |err| {
                        self.consecutive_errors += 1;
                        if (attempt + 1 == self.max_retries) {
                            self.state = .failed;
                            return err;
                        }
                    };
                    return;
                }
            }
            // Exponential backoff
            Utils.sleepMs(delay);
            delay *= 2;
        }
        return NetworkError.SendFailed;
    }

    pub fn health(self: *const NetworkSink) ConnectionState {
        return self.state;
    }
};

test "syslog severity mapping" {
    try std.testing.expectEqual(SyslogSeverity.debug, SyslogSeverity.fromLogLevel(.debug));
    try std.testing.expectEqual(SyslogSeverity.info, SyslogSeverity.fromLogLevel(.info));
    try std.testing.expectEqual(SyslogSeverity.warning, SyslogSeverity.fromLogLevel(.warning));
    try std.testing.expectEqual(SyslogSeverity.err, SyslogSeverity.fromLogLevel(.err));
    try std.testing.expectEqual(SyslogSeverity.critical, SyslogSeverity.fromLogLevel(.critical));
}

test "syslog formatting" {
    const allocator = std.testing.allocator;
    const formatted = try formatSyslog(allocator, .user, .info, "localhost", "test-app", "Hello Syslog");
    defer allocator.free(formatted);

    // <(facility*8 + severity)>1 timestamp hostname app-name - - - message
    // user(1)*8 + info(6) = 14
    try std.testing.expect(std.mem.startsWith(u8, formatted, "<14>1 "));
    try std.testing.expect(std.mem.indexOf(u8, formatted, "localhost test-app - - - Hello Syslog") != null);
}

test "network send helpers" {
    const allocator = std.testing.allocator;

    const TestContext = struct {
        var received: std.atomic.Value(bool) = std.atomic.Value(bool).init(false);

        fn onMessage(message: []const u8) void {
            _ = message;
            received.store(true, .monotonic);
        }
    };

    resetStats();

    const udp = try createUdpSocket(allocator, "udp://127.0.0.1:5514");
    defer udp.socket.close(Utils.io());

    try sendSyslogUdp(allocator, udp.socket, udp.address, .user, .info, "localhost", "logly", "syslog test");

    const udp_stats = getStats();
    try std.testing.expect(udp_stats.totalMessagesCount() >= 1);

    TestContext.received.store(false, .monotonic);
    var server = LogServer.init(allocator);
    defer server.deinit();

    const port: u16 = 39090;
    try server.startTcp(port, TestContext.onMessage);
    defer server.stop();

    var stream: ?std.Io.net.Stream = null;
    var attempt: u8 = 0;
    while (attempt < 10 and stream == null) : (attempt += 1) {
        stream = connectTcp(allocator, "tcp://127.0.0.1:39090") catch {
            Utils.io().sleep(.fromMilliseconds(10), .awake) catch {};
            continue;
        };
    }

    try std.testing.expect(stream != null);
    defer if (stream) |s| s.close(Utils.io());

    resetStats();
    try sendTcp(stream.?, "tcp test");
    if (stream) |s| {
        s.close(Utils.io());
        stream = null;
    }
    var wait_attempt: u8 = 0;
    while (wait_attempt < 50 and !TestContext.received.load(.monotonic)) : (wait_attempt += 1) {
        Utils.io().sleep(.fromMilliseconds(10), .awake) catch {};
    }

    const tcp_stats = getStats();
    try std.testing.expect(tcp_stats.totalMessagesCount() >= 1);
    try std.testing.expect(TestContext.received.load(.monotonic));
}
