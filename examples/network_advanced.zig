const std = @import("std");
const logly = @import("logly");

fn printMessage(msg: []const u8) void {
    // Print the received message with a clean server header
    std.debug.print("  [Server Received] => {s}", .{msg});
    // Add newline if the message does not end with one
    if (msg.len > 0 and msg[msg.len - 1] != '\n') {
        std.debug.print("\n", .{});
    }
}

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    _ = logly.Terminal.enableAnsiColors();

    std.debug.print("\n", .{});
    std.debug.print("  Advanced Network Sink and Compliance Demo\n", .{});
    std.debug.print("\n\n", .{});

    // 1. Initialize LogServer for TCP and UDP listening
    std.debug.print("1. Initializing LogServer\n", .{});
    var server = logly.Network.LogServer.init(allocator);
    defer server.deinit();

    const tcpPort: u16 = 39190;
    const udpPort: u16 = 39191;

    try server.startTcp(tcpPort, printMessage);
    std.debug.print("  TCP Server listening on 127.0.0.1:{d}\n", .{tcpPort});

    try server.startUdp(udpPort, printMessage);
    std.debug.print("  UDP Server listening on 127.0.0.1:{d}\n", .{udpPort});

    // Give servers a brief moment to spin up their threads
    logly.Utils.sleepMs(100);

    // 2. TCP Sink Setup with health checking
    std.debug.print("\n2. TCP NetworkSink with Health Monitoring\n", .{});
    const tcpUri = try std.fmt.allocPrint(allocator, "tcp://127.0.0.1:{d}", .{tcpPort});
    defer allocator.free(tcpUri);

    var tcpSink = try logly.Network.NetworkSink.init(allocator, tcpUri);
    defer tcpSink.deinit();

    std.debug.print("  Initial Connection State: {any}\n", .{tcpSink.health()});
    std.debug.print("  Connecting to server...\n", .{});
    try tcpSink.connect();
    std.debug.print("  Connected State: {any}\n", .{tcpSink.health()});

    std.debug.print("  Sending logs over TCP...\n", .{});
    try tcpSink.write("INFO: [TCP] Application initialized successfully.\n");
    try tcpSink.write("WARN: [TCP] Disk usage approaching 85% on /dev/sda1.\n");

    // Wait a brief moment to ensure logs are processed and printed
    logly.Utils.sleepMs(200);

    // 3. UDP Sink Setup
    std.debug.print("\n3. UDP NetworkSink\n", .{});
    const udpUri = try std.fmt.allocPrint(allocator, "udp://127.0.0.1:{d}", .{udpPort});
    defer allocator.free(udpUri);

    var udpSink = try logly.Network.NetworkSink.init(allocator, udpUri);
    defer udpSink.deinit();

    std.debug.print("  Connecting UDP sink...\n", .{});
    try udpSink.connect();
    std.debug.print("  UDP Connection State: {any}\n", .{udpSink.health()});

    std.debug.print("  Sending logs over UDP...\n", .{});
    try udpSink.write("DEBUG: [UDP] Routing service registered.\n");
    try udpSink.write("SUCCESS: [UDP] Healthcheck ping acknowledged.\n");

    logly.Utils.sleepMs(200);

    // 4. Syslog RFC-5424 Formatting
    std.debug.print("\n4. UDP NetworkSink with Syslog RFC-5424 Formatting\n", .{});
    var syslogSink = try logly.Network.NetworkSink.init(allocator, udpUri);
    defer syslogSink.deinit();
    syslogSink.syslogFormat = true;

    try syslogSink.connect();
    std.debug.print("  Sending Syslog-formatted event...\n", .{});
    try syslogSink.write("SEC-AUDIT: User 'admin' successfully escalated privileges via sudo.");

    logly.Utils.sleepMs(200);

    // 5. HTTP Chunked Streaming Mode
    std.debug.print("\n5. TCP NetworkSink with HTTP Chunked Streaming Framing\n", .{});
    var httpSink = try logly.Network.NetworkSink.init(allocator, tcpUri);
    defer httpSink.deinit();
    httpSink.httpChunked = true;

    try httpSink.connect();
    std.debug.print("  Sending HTTP chunked log data...\n", .{});
    try httpSink.write("Chunk 1: Transaction started.");
    try httpSink.write("Chunk 2: Payment processed successfully.");
    try httpSink.write("Chunk 3: Receipt emailed to customer.");

    logly.Utils.sleepMs(200);

    // 6. Resilience, Reconnection, and Retry Budgets
    std.debug.print("\n6. Reconnection and Backoff Resilience\n", .{});
    std.debug.print("  Stopping LogServer temporarily to simulate network drop...\n", .{});
    server.stop();
    logly.Utils.sleepMs(100);

    std.debug.print("  Attempting to write to TCP sink during outage...\n", .{});
    // Reconfigure retry budget to be fast for demo purposes
    tcpSink.maxRetries = 3;
    tcpSink.retryDelayMs = 50;

    // This should fail to write or trigger reconnect attempts and mark state as failed
    tcpSink.write("ERROR: [TCP] Outage occurs!") catch |err| {
        std.debug.print("  Caught expected write failure during outage: {any}\n", .{err});
    };

    std.debug.print("  Sink State during outage: {any}\n", .{tcpSink.health()});

    std.debug.print("  Restarting LogServer to restore network...\n", .{});
    try server.startTcp(tcpPort, printMessage);
    logly.Utils.sleepMs(100);

    std.debug.print("  Writing to TCP sink again (should auto-reconnect)...\n", .{});
    try tcpSink.write("INFO: [TCP] Network connection recovered. Flushing backlog.\n");

    logly.Utils.sleepMs(200);

    // 7. Network Statistics
    std.debug.print("\n7. Network Statistics Summary\n", .{});
    const stats = logly.Network.getStats();
    std.debug.print("  Total Messages Sent: {d}\n", .{stats.totalMessagesCount()});
    std.debug.print("  Total Bytes Transferred: {d} bytes\n", .{stats.totalBytesTransferred()});
    std.debug.print("  Total Connections Established: {d}\n", .{stats.totalConnectionsMade()});
    std.debug.print("  Total Connection/Send Errors: {d}\n", .{stats.totalErrors()});
    std.debug.print("  Calculated Error Rate: {d:.2}%\n", .{stats.errorRate() * 100.0});

    std.debug.print("\n\n", .{});
    std.debug.print("  Advanced Network Example Completed Successfully!\n", .{});
    std.debug.print("\n", .{});
}
