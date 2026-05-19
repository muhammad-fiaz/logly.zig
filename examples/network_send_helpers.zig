const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stream = try logly.Network.connectTcp(allocator, "tcp://127.0.0.1:9000");
    defer stream.close(logly.Utils.io());
    try logly.Network.sendTcp(stream, "raw tcp log\n");

    const udp = try logly.Network.createUdpSocket(allocator, "udp://127.0.0.1:514");
    defer udp.socket.close(logly.Utils.io());
    try logly.Network.sendSyslogUdp(
        allocator,
        udp.socket,
        udp.address,
        .user,
        .info,
        "localhost",
        "logly-demo",
        "syslog helper message",
    );
}
