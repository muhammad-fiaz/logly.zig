const std = @import("std");
const builtin = @import("builtin");
const http = std.http;
const SinkConfig = @import("sink.zig").SinkConfig;
const Constants = @import("constants.zig");
const Utils = @import("utils.zig");

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

    pub fn totalBytesSent(self: *const NetworkStats) u64 {
        return @as(u64, self.bytes_sent.load(.monotonic));
    }

    pub fn totalMessagesCount(self: *const NetworkStats) u64 {
        return @as(u64, self.messages_sent.load(.monotonic));
    }
};

/// Global network stats
pub var stats: NetworkStats = .{};

/// Syslog severity levels (RFC 5424)
pub const SyslogSeverity = enum(u3) {
    emergency = 0,
    alert = 1,
    critical = 2,
    err = 3,
    warning = 4,
    notice = 5,
    info = 6,
    debug = 7,

    pub fn fromLogLevel(level: @import("level.zig").Level) SyslogSeverity {
        return switch (level) {
            .trace, .debug => .debug,
            .info => .info,
            .notice => .notice,
            .success => .info,
            .warning => .warning,
            .err => .err,
            .fail => .err,
            .critical => .critical,
            .fatal => .emergency,
        };
    }
};

/// Syslog facilities (RFC 5424)
pub const SyslogFacility = enum(u5) {
    kern = 0,
    user = 1,
    mail = 2,
    daemon = 3,
    auth = 4,
    syslog = 5,
    lpr = 6,
    news = 7,
    uucp = 8,
    cron = 9,
    authpriv = 10,
    ftp = 11,
    local0 = 16,
    local1 = 17,
    local2 = 18,
    local3 = 19,
    local4 = 20,
    local5 = 21,
    local6 = 22,
    local7 = 23,
};

pub fn formatSyslog(
    allocator: std.mem.Allocator,
    facility: SyslogFacility,
    severity: SyslogSeverity,
    hostname: []const u8,
    app_name: []const u8,
    message: []const u8,
) ![]u8 {
    const priority = (@as(u8, @intFromEnum(facility)) * 8) + @as(u8, @intFromEnum(severity));
    const timestamp = std.time.timestamp();

    var res: std.ArrayList(u8) = .{};
    errdefer res.deinit(allocator);
    const w = res.writer(allocator);

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

    return res.toOwnedSlice(allocator);
}

/// Connects to a TCP host specified by a URI string (e.g., "tcp://127.0.0.1:8080").
/// Returns a std.net.Stream.
pub fn connectTcp(allocator: std.mem.Allocator, uri: []const u8) !std.net.Stream {
    if (!std.mem.startsWith(u8, uri, "tcp://")) return NetworkError.InvalidUri;
    const address_part = uri[6..];

    if (std.mem.indexOfScalar(u8, address_part, ':')) |colon_idx| {
        const host = address_part[0..colon_idx];
        const port_str = address_part[colon_idx + 1 ..];
        const port = std.fmt.parseInt(u16, port_str, 10) catch return NetworkError.InvalidUri;

        const stream = std.net.tcpConnectToHost(allocator, host, port) catch return NetworkError.ConnectionFailed;
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
pub fn createUdpSocket(allocator: std.mem.Allocator, uri: []const u8) !struct { socket: std.posix.socket_t, address: std.net.Address } {
    if (!std.mem.startsWith(u8, uri, "udp://")) return NetworkError.InvalidUri;
    const address_part = uri[6..];

    if (std.mem.indexOfScalar(u8, address_part, ':')) |colon_idx| {
        const host = address_part[0..colon_idx];
        const port_str = address_part[colon_idx + 1 ..];
        const port = std.fmt.parseInt(u16, port_str, 10) catch return NetworkError.InvalidUri;

        const list = std.net.getAddressList(allocator, host, port) catch return NetworkError.AddressResolutionError;
        defer list.deinit();

        if (list.addrs.len > 0) {
            const address = list.addrs[0];
            const socket = std.posix.socket(address.any.family, std.posix.SOCK.DGRAM, 0) catch return NetworkError.SocketCreationError;
            _ = stats.connections_made.fetchAdd(1, .monotonic);
            return .{ .socket = socket, .address = address };
        }
    }
    return NetworkError.InvalidUri;
}

/// Alias for createUdpSocket
pub const udpSocket = createUdpSocket;

/// Sends data via UDP socket.
pub fn sendUdp(socket: std.posix.socket_t, address: std.net.Address, data: []const u8) !void {
    const sent = std.posix.sendto(socket, data, 0, &address.any, address.getOsSockLen()) catch {
        _ = stats.errors.fetchAdd(1, .monotonic);
        return NetworkError.SendFailed;
    };
    _ = stats.bytes_sent.fetchAdd(@truncate(sent), .monotonic);
    _ = stats.messages_sent.fetchAdd(1, .monotonic);
}

/// Fetches a JSON response from a URL.
/// Returns the parsed JSON value (caller must deinit).
pub fn fetchJson(allocator: std.mem.Allocator, url: []const u8, headers: []const http.Header) !std.json.Parsed(std.json.Value) {
    var client = http.Client{ .allocator = allocator };
    defer client.deinit();

    var req = try client.request(.GET, try std.Uri.parse(url), .{
        .headers = .{ .user_agent = .{ .override = std.fmt.comptimePrint("logly.zig/{s}", .{builtin.zig_version_string}) } },
        .extra_headers = headers,
    });
    defer req.deinit();

    try req.sendBodiless();

    const redirect_buffer = try allocator.alloc(u8, 8 * 1024);
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

    var body = std.ArrayList(u8).initCapacity(allocator, 4096) catch return NetworkError.ReadError;
    defer body.deinit(allocator);

    const writer = body.writer(allocator);
    var buf: [4096]u8 = undefined;
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
        if (self.tcp_thread) |t| t.join();
        if (self.udp_thread) |t| t.join();
        self.tcp_thread = null;
        self.udp_thread = null;
    }

    /// Alias for stop
    pub const shutdown = stop;
    pub const close = stop;

    pub fn isRunning(self: *const LogServer) bool {
        return self.running.load(.monotonic);
    }

    pub fn messageCount(self: *const LogServer) u64 {
        return @as(u64, self.messages_received.load(.monotonic));
    }

    pub fn startTcp(self: *LogServer, port: u16, callback: *const fn ([]const u8) void) !void {
        self.running.store(true, .monotonic);
        self.tcp_thread = try std.Thread.spawn(.{}, tcpWorker, .{ self, port, callback });
    }

    pub fn startUdp(self: *LogServer, port: u16, callback: *const fn ([]const u8) void) !void {
        self.running.store(true, .monotonic);
        self.udp_thread = try std.Thread.spawn(.{}, udpWorker, .{ self, port, callback });
    }

    /// Aliases
    pub const listenTcp = startTcp;
    pub const listenUdp = startUdp;

    fn tcpWorker(self: *LogServer, port: u16, callback: *const fn ([]const u8) void) void {
        const address = std.net.Address.parseIp("0.0.0.0", port) catch return;
        const tpe: u32 = std.posix.SOCK.STREAM;
        const protocol = std.posix.IPPROTO.TCP;

        const listener = std.posix.socket(address.any.family, tpe, protocol) catch return;
        defer std.posix.close(listener);

        std.posix.setsockopt(listener, std.posix.SOL.SOCKET, std.posix.SO.REUSEADDR, &std.mem.toBytes(@as(c_int, 1))) catch {};
        std.posix.bind(listener, &address.any, address.getOsSockLen()) catch return;
        std.posix.listen(listener, 128) catch return;

        while (self.running.load(.monotonic)) {
            var client_address: std.net.Address = undefined;
            var client_address_len: std.posix.socklen_t = @sizeOf(std.net.Address);

            const socket = std.posix.accept(listener, &client_address.any, &client_address_len, 0) catch continue;

            const thread = std.Thread.spawn(.{}, tcpClientHandler, .{ self, socket, callback }) catch {
                std.posix.close(socket);
                continue;
            };
            thread.detach();
        }
    }

    fn tcpClientHandler(self: *LogServer, socket: std.posix.socket_t, callback: *const fn ([]const u8) void) void {
        defer std.posix.close(socket);
        var buf: [4096]u8 = undefined;
        while (self.running.load(.monotonic)) {
            const read = std.posix.recv(socket, &buf, 0) catch break;
            if (read == 0) break;
            _ = self.messages_received.fetchAdd(1, .monotonic);
            callback(buf[0..read]);
        }
    }

    fn udpWorker(self: *LogServer, port: u16, callback: *const fn ([]const u8) void) void {
        const address = std.net.Address.parseIp("0.0.0.0", port) catch return;
        const socket = std.posix.socket(address.any.family, std.posix.SOCK.DGRAM, std.posix.IPPROTO.UDP) catch return;
        defer std.posix.close(socket);

        std.posix.setsockopt(socket, std.posix.SOL.SOCKET, std.posix.SO.REUSEADDR, &std.mem.toBytes(@as(c_int, 1))) catch {};
        std.posix.bind(socket, &address.any, address.getOsSockLen()) catch return;

        var buf: [4096]u8 = undefined;
        while (self.running.load(.monotonic)) {
            var client_address: std.net.Address = undefined;
            var client_address_len: std.posix.socklen_t = @sizeOf(std.net.Address);

            const read = std.posix.recvfrom(socket, &buf, 0, &client_address.any, &client_address_len) catch continue;
            if (read == 0) continue;
            _ = self.messages_received.fetchAdd(1, .monotonic);
            callback(buf[0..read]);
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

/// Creates a Syslog sink configuration (UDP port 514).
pub fn createSyslogSink(host: []const u8) !SinkConfig {
    return createUdpSink(host, 514);
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
