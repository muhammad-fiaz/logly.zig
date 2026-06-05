const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    _ = logly.Terminal.enableAnsiColors();

    std.debug.print("=== Logly v0.2.1 Dot-Notation Context Filtering Example ===\\n\\n", .{});

    // Create logger (display-only: no file writes)
    // Disable async writes so messages appear immediately for this demo
    var config = logly.Config.displayOnly();
    config.auto_flush = true;
    const logger = try logly.Logger.initWithConfig(allocator, config);
    defer logger.deinit();

    // Create a filter with dot-notation context path matching
    var filter = logly.Filter.init(allocator);
    defer filter.deinit();

    // Allow records where context["user.id"] == "42"
    try filter.addContextPathMatch("user.id", "42", .allow);

    // Deny records where context["service.name"] == "legacy"
    try filter.addContextPathMatch("service.name", "legacy", .deny);

    // Attach filter to logger
    logger.setFilter(&filter);

    std.debug.print("--- Filter rules configured ---\n", .{});
    std.debug.print("  Rule 1: allow   context['user.id'] == '42'\n", .{});
    std.debug.print("  Rule 2: deny    context['service.name'] == 'legacy'\n\n", .{});

    // Scenario 1: user.id = "42", service.name = "auth" → allowed by rule 1, not denied by rule 2
    try logger.bind("user.id", .{ .string = "42" });
    try logger.bind("service.name", .{ .string = "auth" });
    std.debug.print("[Scenario 1] user.id=42, service.name=auth → ALLOWED:\n", .{});
    try logger.info("User 42 performed an action.", @src());
    try logger.flush();

    // Scenario 2: user.id = "99", service.name = "auth" → doesn't match allow rule 1 → denied
    try logger.bind("user.id", .{ .string = "99" });
    std.debug.print("[Scenario 2] user.id=99, service.name=auth → FILTERED (no allow rule matches):\n", .{});
    try logger.info("User 99 performed an action (should be filtered).", @src());
    try logger.flush();

    // Scenario 3: user.id = "42", service.name = "legacy" → rule 2 deny fires
    try logger.bind("user.id", .{ .string = "42" });
    try logger.bind("service.name", .{ .string = "legacy" });
    std.debug.print("[Scenario 3] user.id=42, service.name=legacy → DENIED by rule 2:\n", .{});
    try logger.info("Legacy service message (should be denied).", @src());
    try logger.flush();

    // Scenario 4: Clear all bindings — no context_path_match rules fire → pass-through
    logger.clearBindings();
    std.debug.print("[Scenario 4] No context bindings → filter falls through:\n", .{});
    try logger.info("No context — filter pass-through.", @src());
    try logger.flush();

    std.debug.print("\n=== Dot-Notation Context Filter Example Complete ===\n", .{});
}
