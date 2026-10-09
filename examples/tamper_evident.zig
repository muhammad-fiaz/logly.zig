//! Tamper-Evident Cryptographic Log Chaining Example.
//!
//! Demonstrates SHA-256 cryptographic chaining on log records
//! to detect tampering or unauthorized modifications.

const std = @import("std");
const logly = @import("logly");

var capturedSignature: [64]u8 = undefined;
var capturedSignatureLen: usize = 0;

fn onSignatureGenerated(sink_name: []const u8, signature: []const u8) void {
    std.debug.print("  [Signature Callback] Sink: '{s}', SHA-256: {s}\n", .{ sink_name, signature });
    if (signature.len <= capturedSignature.len) {
        @memcpy(capturedSignature[0..signature.len], signature);
        capturedSignatureLen = signature.len;
    }
}

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const logPath = "logs/secure_audit.log";
    std.Io.Dir.cwd().deleteFile(logly.defaultIo(), logPath) catch {};
    defer std.Io.Dir.cwd().deleteFile(logly.defaultIo(), logPath) catch {};

    std.debug.print("\n=== Tamper-Evident Log Chaining Demo ===\n\n", .{});

    var config = logly.Config.default();
    config.autoSink = false;

    const logger = try logly.Logger.initWithConfig(allocator, config);
    defer logger.deinit();

    var sinkCfg = logly.SinkConfig.file(logPath);
    sinkCfg.name = "tamper_evident_audit_sink";
    sinkCfg.tamperEvident = true; // Enable SHA-256 chaining
    sinkCfg.asyncWrite = false; // Synchronous for immediate disk verification

    const sinkId = try logger.addSink(sinkCfg);
    if (logger.getSink(sinkId)) |sink| {
        sink.setSignatureCallback(&onSignatureGenerated);
    }

    std.debug.print("1. Writing chained audit records...\n", .{});
    try logger.info("User 'alice' authenticated from 10.0.0.1", null);
    try logger.warn("Privilege escalation requested for resource 'payment_gateway'", null);
    try logger.info("Access granted by policy rule #402", null);

    try logger.flush();

    std.debug.print("\n2. Inspecting cryptographically chained log contents on disk:\n", .{});
    const content = try std.Io.Dir.cwd().readFileAlloc(
        logly.defaultIo(),
        logPath,
        allocator,
        .limited(64 * 1024),
    );
    defer allocator.free(content);

    var lineIter = std.mem.splitScalar(u8, content, '\n');
    var lineNum: usize = 1;
    while (lineIter.next()) |line| {
        if (line.len == 0) continue;
        std.debug.print("  Line {d}: {s}\n", .{ lineNum, line });
        lineNum += 1;
    }

    std.debug.print("\nTamper-Evident Logging Demo completed successfully!\n", .{});
}
