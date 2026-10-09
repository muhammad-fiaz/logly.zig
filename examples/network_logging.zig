const std = @import("std");
const logly = @import("logly");

// Internal Server Implementation for Self-Contained Example
// Uses logly.Network.LogServer (TCP/UDP log receiver for testing).

fn tcpCallback(message: []const u8) void {
    std.debug.print("[TCP Server] Received: {s}", .{message});
}

fn udpCallback(message: []const u8) void {
    std.debug.print("[UDP Server] Received: {s}", .{message});
}

// Main Example

var threaded = std.Io.Threaded.init_single_threaded;
const io = threaded.io();

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 1. Start servers using Logly's built-in LogServer
    var server = logly.Network.LogServer.init(allocator);
    defer server.deinit();

    try server.startTcp(9000, &tcpCallback);
    try server.startUdp(9001, &udpCallback);
    std.debug.print("[TCP Server] Listening on 127.0.0.1:9000\n", .{});
    std.debug.print("[UDP Server] Listening on 127.0.0.1:9001\n", .{});

    // Give servers a moment to start
    _ = io.sleep(std.Io.Duration.fromMilliseconds(500), .awake) catch {};

    // 2. Initialize logger
    var config = logly.Config.default();
    config.captureStackTrace = true;
    config.symbolizeStackTrace = true;
    var logger = try logly.Logger.initWithConfig(allocator, config);
    defer logger.deinit();

    // 3. Configure Sinks

    // Sink 1: TCP Sink with Standard Format
    // This sink sends logs to the TCP server using the default text format.
    var tcpSink = logly.SinkConfig.network("tcp://127.0.0.1:9000");
    tcpSink.name = "tcp-standard";
    // Force enable colors so they are transmitted over the network and displayed by the server
    tcpSink.color = true;
    const tcpSinkIdx = try logger.addSink(tcpSink);

    // Apply a custom theme to the TCP sink to demonstrate color customization
    var theme = logly.Color.Theme{};
    theme.info = logly.Color.parse("36").?; // Cyan
    theme.warning = logly.Color.parse("33").?; // Yellow
    theme.err = logly.Color.parse("31").?; // Red
    theme.success = logly.Color.parse("32").?; // Green
    theme.critical = logly.Color.parse("35").?; // Magenta (Custom color for critical)

    // Access the sink and set the theme
    // Note: In a real app, you might want to do this before adding the sink if possible,
    // or ensure thread safety if the logger is already in use.
    logger.sinks.items[tcpSinkIdx].formatter.setTheme(theme);

    // Sink 2: UDP Sink with JSON Format
    // This sink sends logs to the UDP server in JSON format.
    // Useful for structured logging collectors (e.g., Logstash, Fluentd).
    var udpJsonSink = logly.SinkConfig.network("udp://127.0.0.1:9001");
    udpJsonSink.name = "udp-json";
    udpJsonSink.format = .json;
    _ = try logger.addSink(udpJsonSink);

    // 4. Register Custom Levels
    // Add custom levels with specific priorities and colors (ANSI codes)
    try logger.addCustomLevel("AUDIT", 35, logly.Color.parse("34").?); // Blue
    try logger.addCustomLevel("SECURITY", 45, logly.Color.parse("31").?); // Red

    // Sink 3: Syslog Sink (UDP port 514)
    // This sink sends logs in Syslog format (RFC 5424) to a Syslog server.
    // Syslog uses UDP port 514 by default.
    // The URI string is caller-owned; free after the logger is done.
    var syslogSink = try logly.Network.createSyslogSink(allocator, "127.0.0.1");
    defer allocator.free(syslogSink.path.?);
    syslogSink.name = "syslog";
    _ = try logger.addSink(syslogSink);

    std.debug.print("\nStarting Network Logging Tests\n", .{});

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
        .err("Failed to process transaction", @src());

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

    std.debug.print("\nLogs sent. Waiting for servers to print output...\n", .{});

    // Wait a bit for messages to be received/printed by servers
    _ = io.sleep(std.Io.Duration.fromMilliseconds(2000), .awake) catch {};

    // Demonstrate Syslog formatting with constants
    std.debug.print("\nSyslog Formatting Example\n", .{});

    // Syslog facility and severity are plain enums on the public Network
    // surface; the PRI value is facility*8 + severity per RFC 5424.
    const Facility = logly.Network.SyslogFacility;
    const Severity = logly.Network.SyslogSeverity;
    std.debug.print("SyslogFacility.user = {}\n", .{@backingInt(Facility.user)});
    std.debug.print("SyslogSeverity.info = {}\n", .{@backingInt(Severity.info)});

    // How a Logly level maps onto a syslog severity.
    std.debug.print("Log level .info -> Syslog severity: {}\n", .{@backingInt(Severity.info)});
    std.debug.print("Log level .err -> Syslog severity: {}\n", .{@backingInt(Severity.err)});

    // Format a Syslog message manually
    const syslogMsg = try logly.Network.formatSyslog(allocator, .user, // Facility
        .info, // Severity
        "localhost", "network-logging-example", "This is a test Syslog message");
    defer allocator.free(syslogMsg);
    std.debug.print("Formatted Syslog message: {s}\n", .{syslogMsg});

    std.debug.print("\nTest Complete\n", .{});
}
