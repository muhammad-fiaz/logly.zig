const std = @import("std");
const logly = @import("logly");
const net = std.net;
const posix = std.posix;

// --- Internal Server Implementation for Self-Contained Example ---

fn tcpServer() !void {
    const address = try std.net.Address.parseIp("127.0.0.1", 9000);
    const tpe: u32 = posix.SOCK.STREAM;
    const protocol = posix.IPPROTO.TCP;
    const listener = try posix.socket(address.any.family, tpe, protocol);
    defer posix.close(listener);

    try posix.setsockopt(listener, posix.SOL.SOCKET, posix.SO.REUSEADDR, &std.mem.toBytes(@as(c_int, 1)));
    try posix.bind(listener, &address.any, address.getOsSockLen());
    try posix.listen(listener, 128);

    std.debug.print("[TCP Server] Listening on 127.0.0.1:9000\n", .{});

    while (true) {
        var client_address: net.Address = undefined;
        var client_address_len: posix.socklen_t = @sizeOf(net.Address);
        const socket = posix.accept(listener, &client_address.any, &client_address_len, 0) catch |err| {
            std.debug.print("[TCP Server] Accept error: {any}\n", .{err});
            continue;
        };
        defer posix.close(socket);

        var buf: [logly.Constants.NetworkConstants.tcp_buffer_size]u8 = undefined;
        while (true) {
            const read = posix.recv(socket, &buf, 0) catch break;
            if (read == 0) break;
            std.debug.print("[TCP Server] Received: {s}", .{buf[0..read]});
        }
    }
}

fn udpServer() !void {
    const address = try std.net.Address.parseIp("127.0.0.1", 9001);
    const socket = try posix.socket(address.any.family, posix.SOCK.DGRAM, posix.IPPROTO.UDP);
    defer posix.close(socket);

    try posix.setsockopt(socket, posix.SOL.SOCKET, posix.SO.REUSEADDR, &std.mem.toBytes(@as(c_int, 1)));
    try posix.bind(socket, &address.any, address.getOsSockLen());

    std.debug.print("[UDP Server] Listening on 127.0.0.1:9001\n", .{});

    var buf: [logly.Constants.NetworkConstants.udp_max_packet]u8 = undefined;
    while (true) {
        var client_address: net.Address = undefined;
        var client_address_len: posix.socklen_t = @sizeOf(net.Address);

        const read = posix.recvfrom(socket, &buf, 0, &client_address.any, &client_address_len) catch |err| {
            std.debug.print("[UDP Server] Recv error: {any}\n", .{err});
            continue;
        };

        if (read == 0) continue;
        std.debug.print("[UDP Server] Received: {s}", .{buf[0..read]});
    }
}

// --- Main Example ---

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 1. Start servers in background threads
    const tcp_thread = try std.Thread.spawn(.{}, tcpServer, .{});
    tcp_thread.detach();

    const udp_thread = try std.Thread.spawn(.{}, udpServer, .{});
    udp_thread.detach();

    // Give servers a moment to start
    logly.Utils.sleepMs(500);

    // 2. Initialize logger
    var config = logly.Config.default();
    config.capture_stack_trace = true;
    config.symbolize_stack_trace = true;
    var logger = try logly.Logger.initWithConfig(allocator, config);
    defer logger.deinit();

    // 3. Configure Sinks

    // Sink 1: TCP Sink with Standard Format
    // This sink sends logs to the TCP server using the default text format.
    var tcp_sink = logly.SinkConfig.network("tcp://127.0.0.1:9000");
    tcp_sink.name = "tcp-standard";
    // Force enable colors so they are transmitted over the network and displayed by the server
    tcp_sink.color = true;
    const tcp_sink_idx = try logger.addSink(tcp_sink);

    // Apply a custom theme to the TCP sink to demonstrate color customization
    var theme = logly.Formatter.Theme{};
    theme.info = "36"; // Cyan
    theme.warning = "33"; // Yellow
    theme.err = "31"; // Red
    theme.success = "32"; // Green
    theme.critical = "35"; // Magenta (Custom color for critical)

    // Access the sink and set the theme
    // Note: In a real app, you might want to do this before adding the sink if possible,
    // or ensure thread safety if the logger is already in use.
    logger.sinks.items[tcp_sink_idx].formatter.setTheme(theme);

    // Sink 2: UDP Sink with JSON Format
    // This sink sends logs to the UDP server in JSON format.
    // Useful for structured logging collectors (e.g., Logstash, Fluentd).
    var udp_json_sink = logly.SinkConfig.network("udp://127.0.0.1:9001");
    udp_json_sink.name = "udp-json";
    udp_json_sink.json = true;
    _ = try logger.addSink(udp_json_sink);

    // 4. Register Custom Levels
    // Add custom levels with specific priorities and colors (ANSI codes)
    try logger.addCustomLevel("AUDIT", 35, "34"); // Blue
    try logger.addCustomLevel("SECURITY", 45, "31"); // Red

    // Sink 3: Syslog Sink (UDP port 514)
    // This sink sends logs in Syslog format (RFC 5424) to a Syslog server.
    // Syslog uses UDP port 514 by default.
    var syslog_sink = try logly.Network.createSyslogSink("127.0.0.1");
    syslog_sink.name = "syslog";
    _ = try logger.addSink(syslog_sink);

    std.debug.print("\n--- Starting Network Logging Tests ---\n", .{});

    // 4. Generate Logs

    // Basic Info Log
    // Goes to: TCP (Standard), UDP (JSON)
    // Filtered out by: TCP (Custom)
    try logger.info("This is a basic info message.", @src());

    // Warning Log
    // Goes to: All sinks
    try logger.warning("This is a warning message!", @src());

    // Error Log with Context
    // Goes to: All sinks
    var ctx = logger.ctx();
    try ctx.str("user_id", "12345")
        .int("attempt", 3)
        .err("Failed to process transaction");

    // Custom Level Log (Success)
    // Goes to: TCP (Standard), UDP (JSON)
    // Filtered out by: TCP (Custom) - assuming success < warning
    try logger.success("Operation completed successfully.", @src());

    // Critical Log
    // Goes to: All sinks
    try logger.critical("System critical failure!", @src());

    // Log with custom levels
    try logger.custom("AUDIT", "User login attempt", null);
    try logger.custom("SECURITY", "Invalid password attempt", null);

    // Flush all sinks to ensure messages are sent
    for (logger.sinks.items) |sink| {
        try sink.flush();
    }

    std.debug.print("\n--- Logs sent. Waiting for servers to print output... ---\n", .{});

    // Wait a bit for messages to be received/printed by servers
    logly.Utils.sleepMs(2000);

    // Demonstrate Syslog formatting with constants
    std.debug.print("\n--- Syslog Formatting Example ---\n", .{});

    // Show Syslog severity and facility constants
    std.debug.print("SyslogFacility.user = {}\n", .{@intFromEnum(logly.Constants.SyslogConstants.Facility.user)});
    std.debug.print("SyslogSeverity.info = {}\n", .{@intFromEnum(logly.Constants.SyslogConstants.Severity.info)});

    // Show how to convert log levels to Syslog severity
    const severity_info = logly.Constants.SyslogConstants.Severity.fromLogLevel(.info);
    const severity_error = logly.Constants.SyslogConstants.Severity.fromLogLevel(.err);
    std.debug.print("Log level .info -> Syslog severity: {}\n", .{@intFromEnum(severity_info)});
    std.debug.print("Log level .err -> Syslog severity: {}\n", .{@intFromEnum(severity_error)});

    // Format a Syslog message manually
    const syslog_msg = try logly.Network.formatSyslog(allocator, .user, // Facility
        .info, // Severity
        "localhost", "network-logging-example", "This is a test Syslog message");
    defer allocator.free(syslog_msg);
    std.debug.print("Formatted Syslog message: {s}\n", .{syslog_msg});

    std.debug.print("\n--- Test Complete ---\n", .{});
}
