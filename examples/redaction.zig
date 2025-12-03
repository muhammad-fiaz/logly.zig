const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== Sensitive Data Redaction Example ===\n\n", .{});

    // Create a redactor with common sensitive patterns
    var redactor = logly.Redactor.init(allocator);
    defer redactor.deinit();

    // Add field-based redaction rules
    try redactor.addField("password", .full);
    try redactor.addField("api_key", .partial_end);
    try redactor.addField("credit_card", .mask_middle);
    try redactor.addField("ssn", .mask_middle);
    try redactor.addField("email", .partial_start);

    // Add pattern-based redaction
    try redactor.addPattern("password_pattern", .contains, "password=", "[REDACTED_PASSWORD]");
    try redactor.addPattern("secret_pattern", .contains, "secret:", "[HIDDEN]");

    // Create logger
    const logger = try logly.Logger.init(allocator);
    defer logger.deinit();

    // Set redactor on logger
    logger.setRedactor(&redactor);

    std.debug.print("--- Field-based Redaction Examples ---\n\n", .{});

    // Demonstrate field redaction types
    std.debug.print("RedactionType.full: ", .{});
    const full = try logly.Redactor.RedactionType.full.apply(allocator, "mysecretpassword123");
    defer allocator.free(full);
    std.debug.print("{s}\n", .{full});

    std.debug.print("RedactionType.partial_end: ", .{});
    const partial_end = try logly.Redactor.RedactionType.partial_end.apply(allocator, "sk_live_abc123xyz");
    defer allocator.free(partial_end);
    std.debug.print("{s}\n", .{partial_end});

    std.debug.print("RedactionType.partial_start: ", .{});
    const partial_start = try logly.Redactor.RedactionType.partial_start.apply(allocator, "user@example.com");
    defer allocator.free(partial_start);
    std.debug.print("{s}\n", .{partial_start});

    std.debug.print("RedactionType.mask_middle: ", .{});
    const mask_middle = try logly.Redactor.RedactionType.mask_middle.apply(allocator, "4111111111111111");
    defer allocator.free(mask_middle);
    std.debug.print("{s}\n", .{mask_middle});

    std.debug.print("RedactionType.hash: ", .{});
    const hashed = try logly.Redactor.RedactionType.hash.apply(allocator, "sensitivedata");
    defer allocator.free(hashed);
    std.debug.print("{s}\n", .{hashed});

    std.debug.print("\n--- Pattern-based Redaction in Logs ---\n\n", .{});

    // Log messages with sensitive data - redactor will mask them
    try logger.info("User login attempt with password=secret123");
    try logger.info("API call with secret: mysupersecret");
    try logger.info("Processing order for user@example.com");

    std.debug.print("\n--- Using Redaction Presets ---\n\n", .{});

    // Use common preset
    var common_redactor = try logly.RedactionPresets.common(allocator);
    defer common_redactor.deinit();

    std.debug.print("Common redactor includes rules for:\n", .{});
    std.debug.print("  - password (full)\n", .{});
    std.debug.print("  - secret (full)\n", .{});
    std.debug.print("  - api_key (partial_end)\n", .{});
    std.debug.print("  - token (partial_end)\n", .{});
    std.debug.print("  - credit_card (mask_middle)\n", .{});
    std.debug.print("  - ssn (mask_middle)\n", .{});
    std.debug.print("  - email (partial_start)\n", .{});

    std.debug.print("\n=== Redaction Example Complete ===\n", .{});
}
