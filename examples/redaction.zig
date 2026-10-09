const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("Sensitive Data Redaction Example\n\n", .{});

    // Create a redactor with common sensitive patterns
    var redactor = logly.Redactor.init(allocator);
    defer redactor.deinit();

    // Add field-based redaction rules
    try redactor.addField("password", .full);
    try redactor.addField("api_key", .partialEnd);
    try redactor.addField("credit_card", .maskMiddle);
    try redactor.addField("ssn", .maskMiddle);
    try redactor.addField("email", .partialStart);

    // Add pattern-based redaction
    // NOTE: `.contains` replaces the matched token only, so include a
    // trailing value in the pattern when the secret itself must disappear.
    try redactor.addPattern("password_pattern", .contains, "password=secret123", "password=[REDACTED]");
    try redactor.addPattern("secret_pattern", .contains, "secret: mysupersecret", "secret: [HIDDEN]");
    try redactor.addPattern("email_pattern", .email, "", "[EMAIL REDACTED]");

    // Create logger
    const logger = try logly.Logger.init(allocator);
    defer logger.deinit();

    // Set redactor on logger
    logger.setRedactor(&redactor);

    std.debug.print("Field-based Redaction Examples\n\n", .{});

    // Demonstrate field redaction types
    std.debug.print("RedactionType.full: ", .{});
    const full = try logly.Redactor.RedactionType.full.apply(allocator, "mysecretpassword123");
    defer allocator.free(full);
    std.debug.print("{s}\n", .{full});

    std.debug.print("RedactionType.partial_end: ", .{});
    const partialEnd = try logly.Redactor.RedactionType.partialEnd.apply(allocator, "sk_live_abc123xyz");
    defer allocator.free(partialEnd);
    std.debug.print("{s}\n", .{partialEnd});

    std.debug.print("RedactionType.partial_start: ", .{});
    const partialStart = try logly.Redactor.RedactionType.partialStart.apply(allocator, "user@example.com");
    defer allocator.free(partialStart);
    std.debug.print("{s}\n", .{partialStart});

    std.debug.print("RedactionType.mask_middle: ", .{});
    const maskMiddle = try logly.Redactor.RedactionType.maskMiddle.apply(allocator, "4111111111111111");
    defer allocator.free(maskMiddle);
    std.debug.print("{s}\n", .{maskMiddle});

    std.debug.print("RedactionType.hash: ", .{});
    const hashed = try logly.Redactor.RedactionType.hash.apply(allocator, "sensitivedata");
    defer allocator.free(hashed);
    std.debug.print("{s}\n", .{hashed});

    std.debug.print("\nPattern-based Redaction in Logs\n\n", .{});

    // Log messages with sensitive data - redactor will mask them
    try logger.info("User login attempt with password=secret123", @src());
    try logger.info("API call with secret: mysupersecret", @src());
    try logger.info("Processing order for user@example.com", @src());
    // Flush so redacted lines appear under the header above,
    // not after the "Example Complete" footer (stdout vs stderr).
    try logger.flush();

    std.debug.print("\nUsing Redaction Presets\n\n", .{});

    // Use common preset
    var commonRedactor = try logly.RedactionPresets.common(allocator);
    defer commonRedactor.deinit();

    std.debug.print("Common redactor includes rules for:\n", .{});
    std.debug.print("  - password (full)\n", .{});
    std.debug.print("  - secret (full)\n", .{});
    std.debug.print("  - api_key (partial_end)\n", .{});
    std.debug.print("  - token (partial_end)\n", .{});
    std.debug.print("  - credit_card (mask_middle)\n", .{});
    std.debug.print("  - ssn (mask_middle)\n", .{});
    std.debug.print("  - email (partial_start)\n", .{});

    std.debug.print("\nRedaction Example Complete\n", .{});
}
