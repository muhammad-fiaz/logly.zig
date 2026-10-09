//! Network log transport.
//!
//! TCP, UDP, and RFC 5424 syslog sinks plus a LogServer for testing.
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
    bytesSent: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
    bytesReceived: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
    messagesSent: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
    connectionsMade: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
    errors: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),

    pub fn reset(self: *NetworkStats) void {
        self.bytesSent.store(0, .monotonic);
        self.bytesReceived.store(0, .monotonic);
        self.messagesSent.store(0, .monotonic);
        self.connectionsMade.store(0, .monotonic);
        self.errors.store(0, .monotonic);
    }

    pub fn totalBytesSent(self: *const NetworkStats) u64 {
        return Utils.atomicLoadU64(&self.bytesSent);
    }

    pub fn totalBytesReceived(self: *const NetworkStats) u64 {
        return Utils.atomicLoadU64(&self.bytesReceived);
    }

    pub fn totalMessagesCount(self: *const NetworkStats) u64 {
        return Utils.atomicLoadU64(&self.messagesSent);
    }

    pub fn totalConnectionsMade(self: *const NetworkStats) u64 {
        return Utils.atomicLoadU64(&self.connectionsMade);
    }

    pub fn totalErrors(self: *const NetworkStats) u64 {
        return Utils.atomicLoadU64(&self.errors);
    }

    /// Checks if any network errors occurred.
    pub fn hasErrors(self: *const NetworkStats) bool {
        return self.errors.load(.monotonic) > 0;
    }

    /// Calculate error rate (0.0 - 1.0) based on messages sent.
    pub fn errorRate(self: *const NetworkStats) f64 {
        const sent = Utils.atomicLoadU64(&self.messagesSent);
        const errs = Utils.atomicLoadU64(&self.errors);
        return Utils.calculateErrorRate(errs, sent);
    }

    /// Calculate average bytes per message.
    pub fn avgBytesPerMessage(self: *const NetworkStats) f64 {
        const bytes = Utils.atomicLoadU64(&self.bytesSent);
        const messages = Utils.atomicLoadU64(&self.messagesSent);
        return Utils.calculateAverage(bytes, messages);
    }

    /// Returns total bytes transferred (sent + received).
    pub fn totalBytesTransferred(self: *const NetworkStats) u64 {
        return Utils.atomicLoadU64(&self.bytesSent) + Utils.atomicLoadU64(&self.bytesReceived);
    }
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
    appName: []const u8,
    message: []const u8,
) ![]u8 {
    const priority = (@as(u8, @backingInt(facility)) * 8) + @as(u8, @backingInt(severity));
    // RFC5424 TIMESTAMP: full-date "T" full-time, UTC with millis.
    const nowMs = Utils.currentMillis();
    const tc = Utils.fromMilliTimestamp(nowMs);
    const millis: u64 = @intCast(@mod(if (nowMs < 0) 0 else nowMs, Constants.TimeConstants.msPerSecond));

    var res = std.Io.Writer.Allocating.init(allocator);
    errdefer res.deinit();
    const w = &res.writer;

    try w.writeByte('<');
    try Utils.writeInt(w, priority);
    try w.writeAll(">1 ");
    try Utils.writeIsoDateTime(w, tc);
    try w.writeByte('.');
    try Utils.write3Digits(w, millis);
    try w.writeByte('Z');
    try w.writeByte(' ');
    try w.writeAll(hostname);
    try w.writeByte(' ');
    try w.writeAll(appName);
    try w.writeAll(" - - - ");
    try w.writeAll(message);
    try w.writeByte('\n');

    return res.toOwnedSlice();
}

/// Connects to a TCP host specified by a URI string with explicit I/O.
pub fn connectTcpWithIo(allocator: std.mem.Allocator, io_handle: std.Io, uri: []const u8) !std.Io.net.Stream {
    if (!std.mem.startsWith(u8, uri, "tcp://")) return NetworkError.InvalidUri;
    const addressPart = uri[6..];

    if (std.mem.indexOfScalar(u8, addressPart, ':')) |colonIdx| {
        const host = addressPart[0..colonIdx];
        const portStr = addressPart[colonIdx + 1 ..];
        const port = std.fmt.parseInt(u16, portStr, 10) catch return NetworkError.InvalidUri;

        _ = allocator;
        const hostName = std.Io.net.HostName.init(host) catch return NetworkError.InvalidUri;
        const stream = hostName.connect(io_handle, port, .{ .mode = .stream, .protocol = .tcp }) catch return NetworkError.ConnectionFailed;
        _ = stats.connectionsMade.fetchAdd(1, .monotonic);
        return stream;
    }
    return NetworkError.InvalidUri;
}

/// Connects to a TCP host specified by a URI string (e.g., "tcp://127.0.0.1:8080").
/// Returns a std.Io.net.Stream.
pub fn connectTcp(allocator: std.mem.Allocator, uri: []const u8) !std.Io.net.Stream {
    return connectTcpWithIo(allocator, Utils.defaultIo(), uri);
}

/// A UDP socket and its target address endpoint.
pub const UdpEndpoint = struct {
    socket: std.Io.net.Socket,
    address: std.Io.net.IpAddress,
};

/// Creates a UDP socket connected to a host specified by a URI string with explicit I/O.
pub fn createUdpSocketWithIo(allocator: std.mem.Allocator, io_handle: std.Io, uri: []const u8) !UdpEndpoint {
    if (!std.mem.startsWith(u8, uri, "udp://")) return NetworkError.InvalidUri;
    const addressPart = uri[6..];

    if (std.mem.indexOfScalar(u8, addressPart, ':')) |colonIdx| {
        const host = addressPart[0..colonIdx];
        const portStr = addressPart[colonIdx + 1 ..];
        const port = std.fmt.parseInt(u16, portStr, 10) catch return NetworkError.InvalidUri;

        _ = allocator;
        const address = std.Io.net.IpAddress.parse(host, port) catch return NetworkError.AddressResolutionError;
        {
            const localAddress = switch (address) {
                .ip4 => std.Io.net.IpAddress.parse("0.0.0.0", 0) catch unreachable,
                .ip6 => std.Io.net.IpAddress.parse("::", 0) catch unreachable,
            };
            const socket = localAddress.bind(io_handle, .{ .mode = .dgram, .protocol = .udp }) catch return NetworkError.SocketCreationError;
            _ = stats.connectionsMade.fetchAdd(1, .monotonic);
            return .{ .socket = socket, .address = address };
        }
    }
    return NetworkError.InvalidUri;
}

/// Creates a UDP socket connected to a host specified by a URI string (e.g., "udp://127.0.0.1:514").
/// Returns a tuple of (socket, address).
pub fn createUdpSocket(allocator: std.mem.Allocator, uri: []const u8) !UdpEndpoint {
    return createUdpSocketWithIo(allocator, Utils.defaultIo(), uri);
}

/// Sends data via UDP socket with explicit I/O.
pub fn sendUdpWithIo(socket: std.Io.net.Socket, io_handle: std.Io, address: std.Io.net.IpAddress, data: []const u8) !void {
    socket.send(io_handle, &address, data) catch {
        _ = stats.errors.fetchAdd(1, .monotonic);
        return NetworkError.SendFailed;
    };
    _ = stats.bytesSent.fetchAdd(@truncate(data.len), .monotonic);
    _ = stats.messagesSent.fetchAdd(1, .monotonic);
}

/// Sends data via UDP socket.
pub fn sendUdp(socket: std.Io.net.Socket, address: std.Io.net.IpAddress, data: []const u8) !void {
    return sendUdpWithIo(socket, Utils.defaultIo(), address, data);
}

/// Sends data via a TCP stream with explicit I/O.
pub fn sendTcpWithIo(stream: std.Io.net.Stream, io_handle: std.Io, data: []const u8) !void {
    var buffer: [Constants.BufferSizes.message]u8 = undefined;
    var writer = stream.writer(io_handle, &buffer);
    writer.interface.writeAll(data) catch {
        _ = stats.errors.fetchAdd(1, .monotonic);
        return NetworkError.SendFailed;
    };
    writer.interface.flush() catch {
        _ = stats.errors.fetchAdd(1, .monotonic);
        return NetworkError.SendFailed;
    };
    _ = stats.bytesSent.fetchAdd(@truncate(data.len), .monotonic);
    _ = stats.messagesSent.fetchAdd(1, .monotonic);
}

/// Sends data via a TCP stream.
pub fn sendTcp(stream: std.Io.net.Stream, data: []const u8) !void {
    return sendTcpWithIo(stream, Utils.defaultIo(), data);
}

/// Formats a syslog message and sends it via UDP with explicit I/O.
pub fn sendSyslogUdpWithIo(
    allocator: std.mem.Allocator,
    io_handle: std.Io,
    socket: std.Io.net.Socket,
    address: std.Io.net.IpAddress,
    facility: SyslogFacility,
    severity: SyslogSeverity,
    hostname: []const u8,
    appName: []const u8,
    message: []const u8,
) !void {
    const formatted = try formatSyslog(allocator, facility, severity, hostname, appName, message);
    defer allocator.free(formatted);
    try sendUdpWithIo(socket, io_handle, address, formatted);
}

/// Formats a syslog message and sends it via UDP.
pub fn sendSyslogUdp(
    allocator: std.mem.Allocator,
    socket: std.Io.net.Socket,
    address: std.Io.net.IpAddress,
    facility: SyslogFacility,
    severity: SyslogSeverity,
    hostname: []const u8,
    appName: []const u8,
    message: []const u8,
) !void {
    return sendSyslogUdpWithIo(allocator, Utils.defaultIo(), socket, address, facility, severity, hostname, appName, message);
}

/// Formats a syslog message and sends it via TCP with explicit I/O.
pub fn sendSyslogTcpWithIo(
    allocator: std.mem.Allocator,
    io_handle: std.Io,
    stream: std.Io.net.Stream,
    facility: SyslogFacility,
    severity: SyslogSeverity,
    hostname: []const u8,
    appName: []const u8,
    message: []const u8,
) !void {
    const formatted = try formatSyslog(allocator, facility, severity, hostname, appName, message);
    defer allocator.free(formatted);
    try sendTcpWithIo(stream, io_handle, formatted);
}

/// Formats a syslog message and sends it via TCP.
pub fn sendSyslogTcp(
    allocator: std.mem.Allocator,
    stream: std.Io.net.Stream,
    facility: SyslogFacility,
    severity: SyslogSeverity,
    hostname: []const u8,
    appName: []const u8,
    message: []const u8,
) !void {
    return sendSyslogTcpWithIo(allocator, Utils.defaultIo(), stream, facility, severity, hostname, appName, message);
}

/// Fetches a JSON response from a URL with explicit I/O.
pub fn fetchJsonWithIo(allocator: std.mem.Allocator, io_handle: std.Io, url: []const u8, headers: []const http.Header) !std.json.Parsed(std.json.Value) {
    var client = http.Client{ .allocator = allocator, .io = io_handle };
    defer client.deinit();

    var req = try client.request(.GET, try std.Uri.parse(url), .{
        .headers = .{ .userAgent = .{ .override = std.fmt.comptimePrint("logly.zig/{s}", .{builtin.zigVersionString}) } },
        .extraHeaders = headers,
    });
    defer req.deinit();

    try req.sendBodiless();

    const redirectBuffer = try allocator.alloc(u8, Constants.NetworkConstants.tcpBufferSize);
    defer allocator.free(redirectBuffer);

    var response = try req.receiveHead(redirectBuffer);
    if (response.head.status != .ok) return NetworkError.RequestFailed;

    const decompressBuffer: []u8 = switch (response.head.contentEncoding) {
        .identity => &.{},
        .zstd => try allocator.alloc(u8, std.compress.zstd.defaultWindowLen),
        .deflate, .gzip => try allocator.alloc(u8, std.compress.flate.maxWindowLen),
        .compress => return NetworkError.UnsupportedEncoding,
    };
    defer if (decompressBuffer.len != 0) allocator.free(decompressBuffer);

    var transferBuffer: [64]u8 = undefined;
    var decompress: http.Decompress = undefined;
    var reader = response.readerDecompressing(&transferBuffer, &decompress, decompressBuffer);

    var body = std.ArrayList(u8).initCapacity(allocator, Constants.BufferSizes.message) catch return NetworkError.ReadError;
    defer body.deinit(allocator);

    var bodyWriter = Utils.ArrayListWriter.init(&body, allocator);
    const writer = &bodyWriter.writer;
    var buf: [Constants.BufferSizes.message]u8 = undefined;
    while (true) {
        const n = reader.readSliceShort(&buf) catch return NetworkError.ReadError;
        if (n == 0) break;
        try writer.writeAll(buf[0..n]);
    }

    _ = stats.bytesReceived.fetchAdd(@truncate(body.items.len), .monotonic);
    return std.json.parseFromSlice(std.json.Value, allocator, body.items, .{});
}

/// Fetches a JSON response from a URL.
/// Returns the parsed JSON value (caller must deinit).
pub fn fetchJson(allocator: std.mem.Allocator, url: []const u8, headers: []const http.Header) !std.json.Parsed(std.json.Value) {
    return fetchJsonWithIo(allocator, Utils.defaultIo(), url, headers);
}

/// A simple log server that can listen on TCP and UDP ports.
/// Useful for testing network logging or building simple log collectors.
pub const LogServer = struct {
    allocator: std.mem.Allocator,
    io: std.Io = Utils.defaultIo(),
    running: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    tcpThread: ?std.Thread = null,
    udpThread: ?std.Thread = null,
    tcpPort: u16 = 0,
    udpPort: u16 = 0,
    messagesReceived: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),

    pub fn init(allocator: std.mem.Allocator) LogServer {
        return initWithIo(allocator, Utils.defaultIo());
    }

    pub fn initWithIo(allocator: std.mem.Allocator, io_handle: std.Io) LogServer {
        return .{
            .allocator = allocator,
            .io = io_handle,
        };
    }

    pub fn deinit(self: *LogServer) void {
        self.stop();
    }

    pub fn stop(self: *LogServer) void {
        self.running.store(false, .monotonic);
        self.wakeTcpWorker();
        self.wakeUdpWorker();
        if (self.tcpThread) |t| t.join();
        if (self.udpThread) |t| t.join();
        self.tcpThread = null;
        self.udpThread = null;
        self.tcpPort = 0;
        self.udpPort = 0;
    }

    pub fn isRunning(self: *const LogServer) bool {
        return self.running.load(.monotonic);
    }

    pub fn messageCount(self: *const LogServer) u64 {
        return @as(u64, self.messagesReceived.load(.monotonic));
    }

    pub fn startTcp(self: *LogServer, port: u16, callback: *const fn ([]const u8) void) !void {
        self.running.store(true, .monotonic);
        self.tcpPort = port;
        self.tcpThread = try std.Thread.spawn(.{}, tcpWorker, .{ self, port, callback });
    }

    pub fn startUdp(self: *LogServer, port: u16, callback: *const fn ([]const u8) void) !void {
        self.running.store(true, .monotonic);
        self.udpPort = port;
        self.udpThread = try std.Thread.spawn(.{}, udpWorker, .{ self, port, callback });
    }

    fn wakeTcpWorker(self: *LogServer) void {
        if (self.tcpThread == null or self.tcpPort == 0) return;
        const hostName = std.Io.net.HostName.init("127.0.0.1") catch return;
        const stream = hostName.connect(self.io, self.tcpPort, .{ .mode = .stream, .protocol = .tcp }) catch return;
        stream.close(self.io);
    }

    fn wakeUdpWorker(self: *LogServer) void {
        if (self.udpThread == null or self.udpPort == 0) return;
        const address = std.Io.net.IpAddress.parse("127.0.0.1", self.udpPort) catch return;
        const localAddress = std.Io.net.IpAddress.parse("0.0.0.0", 0) catch return;
        const socket = localAddress.bind(self.io, .{ .mode = .dgram, .protocol = .udp }) catch return;
        defer socket.close(self.io);
        socket.send(self.io, &address, "") catch {};
    }

    fn tcpWorker(self: *LogServer, port: u16, callback: *const fn ([]const u8) void) void {
        const io_handle = self.io;
        const address = std.Io.net.IpAddress.parse("0.0.0.0", port) catch return;
        var server = address.listen(io_handle, .{ .reuse_address = true }) catch return;
        defer server.deinit(io_handle);

        while (self.running.load(.monotonic)) {
            const stream = server.accept(io_handle) catch continue;

            const thread = std.Thread.spawn(.{}, tcpClientHandler, .{ self, stream, callback }) catch {
                stream.close(io_handle);
                continue;
            };
            thread.detach();
        }
    }

    fn tcpClientHandler(self: *LogServer, stream: std.Io.net.Stream, callback: *const fn ([]const u8) void) void {
        const io_handle = self.io;
        defer stream.close(io_handle);
        var buf: [Constants.NetworkConstants.tcpBufferSize]u8 = undefined;
        var reader = stream.reader(io_handle, &buf);
        while (self.running.load(.monotonic)) {
            const read = reader.interface.readSliceShort(&buf) catch break;
            if (read == 0) break;
            _ = self.messagesReceived.fetchAdd(1, .monotonic);
            callback(buf[0..read]);
        }
    }

    fn udpWorker(self: *LogServer, port: u16, callback: *const fn ([]const u8) void) void {
        const io_handle = self.io;
        const address = std.Io.net.IpAddress.parse("0.0.0.0", port) catch return;
        const socket = address.bind(io_handle, .{ .mode = .dgram, .protocol = .udp }) catch return;
        defer socket.close(io_handle);

        var buf: [Constants.NetworkConstants.udpMaxPacket]u8 = undefined;
        while (self.running.load(.monotonic)) {
            const message = socket.receive(io_handle, &buf) catch continue;
            if (message.data.len == 0) continue;
            _ = self.messagesReceived.fetchAdd(1, .monotonic);
            callback(message.data);
        }
    }
};

/// Creates a TCP network sink configuration.
/// The returned `path` is allocated with `allocator`; free it with
/// `allocator.free(config.path.?)` after the sink is deinited, or transfer
/// ownership to a `Sink` that dupes it. Caller owns the URI memory.
pub fn createTcpSink(allocator: std.mem.Allocator, host: []const u8, port: u16) !SinkConfig {
    const uri = try std.fmt.allocPrint(allocator, "tcp://{s}:{d}", .{ host, port });
    return SinkConfig{
        .path = uri,
        .color = false,
        .asyncWrite = true,
    };
}

/// Creates a UDP network sink configuration.
/// Ownership: same as `createTcpSink`.
pub fn createUdpSink(allocator: std.mem.Allocator, host: []const u8, port: u16) !SinkConfig {
    const uri = try std.fmt.allocPrint(allocator, "udp://{s}:{d}", .{ host, port });
    return SinkConfig{
        .path = uri,
        .color = false,
        .asyncWrite = true,
    };
}

pub fn createSyslogSink(allocator: std.mem.Allocator, host: []const u8) !SinkConfig {
    return createUdpSink(allocator, host, Constants.SyslogConstants.defaultPort);
}

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
    io: std.Io = Utils.defaultIo(),
    uri: []const u8,
    state: ConnectionState = .disconnected,
    stream: ?std.Io.net.Stream = null,
    udpSocket: ?std.Io.net.Socket = null,
    udpAddr: ?std.Io.net.IpAddress = null,
    keepalive: bool = true,
    httpChunked: bool = false,
    syslogFormat: bool = false,
    maxRetries: u32 = Constants.TimeDefaults.maxRetries,
    retryDelayMs: u64 = Constants.TimeDefaults.retryDelayMs,
    consecutiveErrors: u32 = 0,

    pub fn init(allocator: std.mem.Allocator, uri: []const u8) !NetworkSink {
        return initWithIo(allocator, Utils.defaultIo(), uri);
    }

    pub fn initWithIo(allocator: std.mem.Allocator, io_handle: std.Io, uri: []const u8) !NetworkSink {
        return .{
            .allocator = allocator,
            .io = io_handle,
            .uri = try allocator.dupe(u8, uri),
        };
    }

    pub fn deinit(self: *NetworkSink) void {
        self.disconnect();
        self.allocator.free(self.uri);
    }

    pub fn disconnect(self: *NetworkSink) void {
        if (self.stream) |s| {
            s.close(self.io);
            self.stream = null;
        }
        if (self.udpSocket) |s| {
            s.close(self.io);
            self.udpSocket = null;
        }
        self.state = .disconnected;
    }

    pub fn connect(self: *NetworkSink) !void {
        self.state = .connecting;
        self.consecutiveErrors = 0;

        var attempt: u32 = 0;
        var delay = self.retryDelayMs;

        while (attempt < self.maxRetries) : (attempt += 1) {
            if (std.mem.startsWith(u8, self.uri, "tcp://")) {
                if (connectTcpWithIo(self.allocator, self.io, self.uri)) |s| {
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
                    self.consecutiveErrors += 1;
                    if (attempt + 1 == self.maxRetries) {
                        self.state = .failed;
                        return err;
                    }
                }
            } else if (std.mem.startsWith(u8, self.uri, "udp://")) {
                if (createUdpSocketWithIo(self.allocator, self.io, self.uri)) |udp| {
                    self.udpSocket = udp.socket;
                    self.udpAddr = udp.address;
                    self.state = .connected;
                    return;
                } else |err| {
                    self.consecutiveErrors += 1;
                    if (attempt + 1 == self.maxRetries) {
                        self.state = .failed;
                        return err;
                    }
                }
            } else {
                self.state = .failed;
                return NetworkError.InvalidUri;
            }

            // Exponential backoff
            Utils.sleepNs(delay * 1000 * 1000);
            delay *= 2;
        }
        self.state = .failed;
        return NetworkError.ConnectionFailed;
    }

    pub fn write(self: *NetworkSink, data: []const u8) !void {
        if (self.state != .connected) {
            try self.connect();
        }

        var dataToSend = data;
        var allocated: ?[]u8 = null;
        defer if (allocated) |slice| self.allocator.free(slice);

        if (self.syslogFormat) {
            allocated = try formatSyslog(self.allocator, .user, .info, "localhost", "logly", data);
            dataToSend = allocated.?;
        }

        if (self.httpChunked) {
            // chunked format: <size_hex>\r\n<data>\r\n
            var chunkBuf: [32]u8 = undefined;
            const chunkHdr = try std.fmt.bufPrint(&chunkBuf, "{x}\r\n", .{dataToSend.len});

            var chunkedMsg: std.ArrayList(u8) = .empty;
            defer chunkedMsg.deinit(self.allocator);
            try chunkedMsg.appendSlice(self.allocator, chunkHdr);
            try chunkedMsg.appendSlice(self.allocator, dataToSend);
            try chunkedMsg.appendSlice(self.allocator, "\r\n");

            try self.writeRaw(chunkedMsg.items);
        } else {
            try self.writeRaw(dataToSend);
        }
    }

    fn writeRaw(self: *NetworkSink, data: []const u8) !void {
        var attempt: u32 = 0;
        var delay = self.retryDelayMs;

        while (attempt < self.maxRetries) : (attempt += 1) {
            if (self.stream) |s| {
                sendTcpWithIo(s, self.io, data) catch |err| {
                    self.consecutiveErrors += 1;
                    if (attempt + 1 == self.maxRetries) {
                        self.state = .failed;
                        return err;
                    }
                    // Try auto-reconnect, then retry the payload on the
                    // next attempt. Never report success for unsent data.
                    self.disconnect();
                    _ = self.connect() catch {};
                    continue;
                };
                self.consecutiveErrors = 0;
                return;
            } else if (self.udpSocket) |s| {
                if (self.udpAddr) |addr| {
                    sendUdpWithIo(s, self.io, addr, data) catch |err| {
                        self.consecutiveErrors += 1;
                        if (attempt + 1 == self.maxRetries) {
                            self.state = .failed;
                            return err;
                        }
                        continue;
                    };
                    self.consecutiveErrors = 0;
                    return;
                }
            }
            // Exponential backoff
            Utils.sleepNs(delay * 1000 * 1000);
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
    defer udp.socket.close(Utils.defaultIo());

    try sendSyslogUdp(allocator, udp.socket, udp.address, .user, .info, "localhost", "logly", "syslog test");

    const udpStats = getStats();
    try std.testing.expect(udpStats.totalMessagesCount() >= 1);

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
            Utils.defaultIo().sleep(.fromMilliseconds(10), .awake) catch {};
            continue;
        };
    }

    try std.testing.expect(stream != null);
    defer if (stream) |s| s.close(Utils.defaultIo());

    resetStats();
    try sendTcp(stream.?, "tcp test");
    if (stream) |s| {
        s.close(Utils.defaultIo());
        stream = null;
    }
    var waitAttempt: u8 = 0;
    while (waitAttempt < 50 and !TestContext.received.load(.monotonic)) : (waitAttempt += 1) {
        Utils.defaultIo().sleep(.fromMilliseconds(10), .awake) catch {};
    }

    const tcpStats = getStats();
    try std.testing.expect(tcpStats.totalMessagesCount() >= 1);
    try std.testing.expect(TestContext.received.load(.monotonic));
}
