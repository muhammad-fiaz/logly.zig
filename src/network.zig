const std = @import("std");
const builtin = @import("builtin");
const http = std.http;

pub const NetworkError = error{
    InvalidUri,
    ConnectionFailed,
    SocketCreationError,
    AddressResolutionError,
    RequestFailed,
    UnsupportedEncoding,
    ReadError,
};

/// Connects to a TCP host specified by a URI string (e.g., "tcp://127.0.0.1:8080").
/// Returns a std.net.Stream.
pub fn connectTcp(allocator: std.mem.Allocator, uri: []const u8) !std.net.Stream {
    if (!std.mem.startsWith(u8, uri, "tcp://")) return NetworkError.InvalidUri;
    const address_part = uri[6..];

    if (std.mem.indexOfScalar(u8, address_part, ':')) |colon_idx| {
        const host = address_part[0..colon_idx];
        const port_str = address_part[colon_idx + 1 ..];
        const port = std.fmt.parseInt(u16, port_str, 10) catch return NetworkError.InvalidUri;

        return std.net.tcpConnectToHost(allocator, host, port) catch return NetworkError.ConnectionFailed;
    }
    return NetworkError.InvalidUri;
}

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
            return .{ .socket = socket, .address = address };
        }
    }
    return NetworkError.InvalidUri;
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

    return std.json.parseFromSlice(std.json.Value, allocator, body.items, .{});
}

/// A simple log server that can listen on TCP and UDP ports.
/// Useful for testing network logging or building simple log collectors.
pub const LogServer = struct {
    allocator: std.mem.Allocator,
    running: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    tcp_thread: ?std.Thread = null,
    udp_thread: ?std.Thread = null,

    pub fn init(allocator: std.mem.Allocator) LogServer {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *LogServer) void {
        self.stop();
    }

    pub fn stop(self: *LogServer) void {
        self.running.store(false, .monotonic);
        if (self.tcp_thread) |t| t.join();
        if (self.udp_thread) |t| t.join();
        self.tcp_thread = null;
        self.udp_thread = null;
    }

    pub fn startTcp(self: *LogServer, port: u16, callback: *const fn ([]const u8) void) !void {
        self.running.store(true, .monotonic);
        self.tcp_thread = try std.Thread.spawn(.{}, tcpWorker, .{ self, port, callback });
    }

    pub fn startUdp(self: *LogServer, port: u16, callback: *const fn ([]const u8) void) !void {
        self.running.store(true, .monotonic);
        self.udp_thread = try std.Thread.spawn(.{}, udpWorker, .{ self, port, callback });
    }

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
            callback(buf[0..read]);
        }
    }
};
