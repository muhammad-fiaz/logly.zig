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

    std.debug.print("============================================================\n", .{});
    std.debug.print("  ADVANCED NETWORK SINK & COMPLIANCE DEMO (v0.2.1)\n", .{});
    std.debug.print("============================================================\n\n", .{});

    // 1. Initialize LogServer for TCP and UDP listening
    std.debug.print("--- 1. Initializing LogServer ---\n", .{});
    var server = logly.Network.LogServer.init(allocator);
    defer server.deinit();

    const tcp_port: u16 = 39190;
    const udp_port: u16 = 39191;

    try server.startTcp(tcp_port, printMessage);
    std.debug.print("  TCP Server listening on 127.0.0.1:{d}\n", .{tcp_port});

    try server.startUdp(udp_port, printMessage);
    std.debug.print("  UDP Server listening on 127.0.0.1:{d}\n", .{udp_port});

    // Give servers a brief moment to spin up their threads
    logly.Utils.sleepMs(100);

    // 2. TCP Sink Setup with health checking
    std.debug.print("\n--- 2. TCP NetworkSink with Health Monitoring ---\n", .{});
    const tcp_uri = try std.fmt.allocPrint(allocator, "tcp://127.0.0.1:{d}", .{tcp_port});
    defer allocator.free(tcp_uri);

    var tcp_sink = try logly.Network.NetworkSink.init(allocator, tcp_uri);
    defer tcp_sink.deinit();

    std.debug.print("  Initial Connection State: {any}\n", .{tcp_sink.health()});
    std.debug.print("  Connecting to server...\n", .{});
    try tcp_sink.connect();
    std.debug.print("  Connected State: {any}\n", .{tcp_sink.health()});

    std.debug.print("  Sending logs over TCP...\n", .{});
    try tcp_sink.write("INFO: [TCP] Application initialized successfully.\n");
    try tcp_sink.write("WARN: [TCP] Disk usage approaching 85% on /dev/sda1.\n");

    // Wait a brief moment to ensure logs are processed and printed
    logly.Utils.sleepMs(200);

    // 3. UDP Sink Setup
    std.debug.print("\n--- 3. UDP NetworkSink ---\n", .{});
    const udp_uri = try std.fmt.allocPrint(allocator, "udp://127.0.0.1:{d}", .{udp_port});
    defer allocator.free(udp_uri);

    var udp_sink = try logly.Network.NetworkSink.init(allocator, udp_uri);
    defer udp_sink.deinit();

    std.debug.print("  Connecting UDP sink...\n", .{});
    try udp_sink.connect();
    std.debug.print("  UDP Connection State: {any}\n", .{udp_sink.health()});

    std.debug.print("  Sending logs over UDP...\n", .{});
    try udp_sink.write("DEBUG: [UDP] Routing service registered.\n");
    try udp_sink.write("SUCCESS: [UDP] Healthcheck ping acknowledged.\n");

    logly.Utils.sleepMs(200);

    // 4. Syslog RFC-5424 Formatting
    std.debug.print("\n--- 4. UDP NetworkSink with Syslog RFC-5424 Formatting ---\n", .{});
    var syslog_sink = try logly.Network.NetworkSink.init(allocator, udp_uri);
    defer syslog_sink.deinit();
    syslog_sink.syslog_format = true;

    try syslog_sink.connect();
    std.debug.print("  Sending Syslog-formatted event...\n", .{});
    try syslog_sink.write("SEC-AUDIT: User 'admin' successfully escalated privileges via sudo.");

    logly.Utils.sleepMs(200);

    // 5. HTTP Chunked Streaming Mode
    std.debug.print("\n--- 5. TCP NetworkSink with HTTP Chunked Streaming Framing ---\n", .{});
    var http_sink = try logly.Network.NetworkSink.init(allocator, tcp_uri);
    defer http_sink.deinit();
    http_sink.http_chunked = true;

    try http_sink.connect();
    std.debug.print("  Sending HTTP chunked log data...\n", .{});
    try http_sink.write("Chunk 1: Transaction started.");
    try http_sink.write("Chunk 2: Payment processed successfully.");
    try http_sink.write("Chunk 3: Receipt emailed to customer.");

    logly.Utils.sleepMs(200);

    // 6. Resilience, Reconnection, and Retry Budgets
    std.debug.print("\n--- 6. Reconnection and Backoff Resilience ---\n", .{});
    std.debug.print("  Stopping LogServer temporarily to simulate network drop...\n", .{});
    server.stop();
    logly.Utils.sleepMs(100);

    std.debug.print("  Attempting to write to TCP sink during outage...\n", .{});
    // Reconfigure retry budget to be fast for demo purposes
    tcp_sink.max_retries = 3;
    tcp_sink.retry_delay_ms = 50;

    // This should fail to write or trigger reconnect attempts and mark state as failed
    tcp_sink.write("ERROR: [TCP] Outage occurs!") catch |err| {
        std.debug.print("  Caught expected write failure during outage: {any}\n", .{err});
    };

    std.debug.print("  Sink State during outage: {any}\n", .{tcp_sink.health()});

    std.debug.print("  Restarting LogServer to restore network...\n", .{});
    try server.startTcp(tcp_port, printMessage);
    logly.Utils.sleepMs(100);

    std.debug.print("  Writing to TCP sink again (should auto-reconnect)...\n", .{});
    try tcp_sink.write("INFO: [TCP] Network connection recovered. Flushing backlog.\n");

    logly.Utils.sleepMs(200);

    // 7. Network Statistics
    std.debug.print("\n--- 7. Network Statistics Summary ---\n", .{});
    const stats = logly.Network.getStats();
    std.debug.print("  Total Messages Sent: {d}\n", .{stats.totalMessagesCount()});
    std.debug.print("  Total Bytes Transferred: {d} bytes\n", .{stats.totalBytesTransferred()});
    std.debug.print("  Total Connections Established: {d}\n", .{stats.totalConnectionsMade()});
    std.debug.print("  Total Connection/Send Errors: {d}\n", .{stats.totalErrors()});
    std.debug.print("  Calculated Error Rate: {d:.2}%\n", .{stats.errorRate() * 100.0});

    std.debug.print("\n============================================================\n", .{});
    std.debug.print("  Advanced Network Example Completed Successfully!\n", .{});
    std.debug.print("============================================================\n", .{});
}
