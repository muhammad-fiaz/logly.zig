const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== Advanced Sensitive Data Redaction & Compliance Audit Example ===\n\n", .{});

    // 1. Initialize an advanced redactor
    var redactor = logly.Redactor.init(allocator);
    defer redactor.deinit();

    // 2. Add advanced pattern-based rules:
    // - Email pattern redaction
    try redactor.addPattern("gdpr_email", .email, "", "[EMAIL REDACTED]");

    // - IPv4/IPv6 pattern redaction
    try redactor.addPattern("pci_ip", .ip, "", "[IP REDACTED]");

    // - JWT Token pattern redaction
    try redactor.addPattern("auth_jwt", .jwt, "", "[JWT REDACTED]");

    // - Luhn (Credit Card) pattern redaction (with high accuracy & validation)
    try redactor.addPattern("pci_card", .luhn, "", "[CREDIT CARD REDACTED]");

    // 3. Create logger and register the redactor
    const logger = try logly.Logger.init(allocator);
    defer logger.deinit();
    logger.setRedactor(&redactor);

    std.debug.print("--- Testing Redaction on Various Data Formats ---\n\n", .{});

    // Email test
    std.debug.print("[Test 1] Email Pattern:\n", .{});
    const msg1 = "Customer query received from support.agent_42@subdomain.company.co.uk regarding order.";
    const red1 = try redactor.redact(msg1);
    defer allocator.free(red1);
    std.debug.print("  Original: {s}\n", .{msg1});
    std.debug.print("  Redacted: {s}\n\n", .{red1});

    // IP address test (both IPv4 and IPv6)
    std.debug.print("[Test 2] IP Addresses (IPv4 and IPv6):\n", .{});
    const msg2 = "Connection accepted from 192.168.1.105 with IPv6 route 2001:0db8:85a3:0000:0000:8a2e:0370:7334 or local ::1.";
    const red2 = try redactor.redact(msg2);
    defer allocator.free(red2);
    std.debug.print("  Original: {s}\n", .{msg2});
    std.debug.print("  Redacted: {s}\n\n", .{red2});

    // JWT token test
    std.debug.print("[Test 3] JWT Access Token:\n", .{});
    const msg3 = "Authorization header bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c passed verification.";
    const red3 = try redactor.redact(msg3);
    defer allocator.free(red3);
    std.debug.print("  Original: {s}\n", .{msg3});
    std.debug.print("  Redacted: {s}\n\n", .{red3});

    // Credit Card (Luhn) test
    std.debug.print("[Test 4] Credit Cards (Luhn Validation):\n", .{});
    const msg4 = "Customer paid using 4111 1111 1111 1111 (Visa test card, valid Luhn) but entered 4111-1111-1111-1112 (invalid Luhn).";
    const red4 = try redactor.redact(msg4);
    defer allocator.free(red4);
    std.debug.print("  Original: {s}\n", .{msg4});
    std.debug.print("  Redacted: {s}\n\n", .{red4});

    std.debug.print("--- Using Redaction Presets ---\n\n", .{});

    var gdpr_redactor = try logly.RedactionPresets.gdprEmail(allocator);
    defer gdpr_redactor.deinit();
    const preset_msg = "GDPR sensitive data: admin@domain.org was processed.";
    const preset_red = try gdpr_redactor.redact(preset_msg);
    defer allocator.free(preset_red);
    std.debug.print("GDPR Preset:\n", .{});
    std.debug.print("  Original: {s}\n", .{preset_msg});
    std.debug.print("  Redacted: {s}\n\n", .{preset_red});

    std.debug.print("--- Compliance Audit Log Output ---\n\n", .{});

    // Print compliance audit logs to standard debug print by buffering
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(allocator);
    var writer_adapter = logly.Utils.ArrayListWriter.init(&buf, allocator);
    try redactor.auditLog(&writer_adapter.writer);
    std.debug.print("{s}", .{buf.items});

    std.debug.print("\n=== Advanced Redaction Example Complete ===\n", .{});
}
