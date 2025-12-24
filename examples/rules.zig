const std = @import("std");
const logly = @import("logly");

/// Logly Rules System Demo
/// Demonstrates compiler-style guided diagnostics for log messages.
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Enable ANSI colors for Windows
    _ = logly.Terminal.enableAnsiColors();

    std.debug.print("\n", .{});
    std.debug.print("========================================\n", .{});
    std.debug.print("    Logly Rules System Demo\n", .{});
    std.debug.print("========================================\n\n", .{});

    // Setup: Create logger with rules enabled
    var config = logly.Config.default();
    config.rules.enabled = true;
    config.color = true;

    const logger = try logly.Logger.initWithConfig(allocator, config);
    defer logger.deinit();

    // Create and configure rules engine
    var rules = logly.Rules.init(allocator);
    defer rules.deinit();
    rules.enable();

    std.debug.print("=== Part 1: Adding Rules ===\n\n", .{});

    // Rule 1: Database error handling
    const db_messages = [_]logly.Rules.RuleMessage{
        logly.Rules.RuleMessage.cause("Database connection pool exhausted"),
        logly.Rules.RuleMessage.fix("Increase max_connections in database.yml"),
        logly.Rules.RuleMessage.docs("Connection Guide", "https://docs.example.com/db-pooling"),
    };

    try rules.add(.{
        .id = 1,
        .name = "database-error",
        .level_match = .{ .exact = .err },
        .message_contains = "Database",
        .messages = &db_messages,
    });
    std.debug.print("[OK] Added Rule #1: Database error handler\n", .{});

    // Rule 2: Performance warnings
    const perf_messages = [_]logly.Rules.RuleMessage{
        logly.Rules.RuleMessage.caution("Operation exceeded performance threshold"),
        logly.Rules.RuleMessage.perf("Consider caching frequently accessed data"),
        logly.Rules.RuleMessage.suggest("Use async operations for I/O bound tasks"),
    };

    try rules.add(.{
        .id = 2,
        .name = "performance-warning",
        .level_match = .{ .exact = .warning },
        .messages = &perf_messages,
    });
    std.debug.print("[OK] Added Rule #2: Performance warning handler\n", .{});

    // Rule 3: Security alerts
    const security_messages = [_]logly.Rules.RuleMessage{
        logly.Rules.RuleMessage.security("Critical security event detected"),
        logly.Rules.RuleMessage.action("Immediately review security logs"),
        logly.Rules.RuleMessage.report("Security Team", "https://internal.example.com/security"),
    };

    try rules.add(.{
        .id = 3,
        .name = "security-alert",
        .level_match = .{ .exact = .critical },
        .messages = &security_messages,
    });
    std.debug.print("[OK] Added Rule #3: Security alert handler\n", .{});

    // Rule 4: One-time startup rule
    const init_messages = [_]logly.Rules.RuleMessage{
        logly.Rules.RuleMessage.note("Application initialized successfully"),
    };

    try rules.add(.{
        .id = 4,
        .name = "startup-notice",
        .once = true,
        .level_match = .{ .exact = .info },
        .message_contains = "started",
        .messages = &init_messages,
    });
    std.debug.print("[OK] Added Rule #4: One-time startup notice\n", .{});

    std.debug.print("\n   Total rules: {}\n\n", .{rules.count()});

    // Attach rules to logger
    logger.setRules(&rules);

    std.debug.print("=== Part 2: Listing Rules ===\n\n", .{});
    try rules.list();
    std.debug.print("\n", .{});

    std.debug.print("=== Part 3: Testing Rules ===\n\n", .{});

    std.debug.print("Test 1: ERROR with 'Database' keyword (triggers Rule #1):\n", .{});
    try logger.err("Database connection timeout after 30s", @src());
    std.debug.print("\n", .{});

    std.debug.print("Test 2: WARNING (triggers Rule #2):\n", .{});
    try logger.warning("Query took 2.5s to execute", @src());
    std.debug.print("\n", .{});

    std.debug.print("Test 3: CRITICAL (triggers Rule #3):\n", .{});
    try logger.critical("Authentication bypass detected", @src());
    std.debug.print("\n", .{});

    std.debug.print("Test 4: INFO with 'started' (triggers Rule #4 ONCE):\n", .{});
    try logger.info("Application started successfully", @src());
    std.debug.print("\n", .{});

    std.debug.print("Test 5: INFO again (Rule #4 should NOT fire - once rule):\n", .{});
    try logger.info("Service started on port 8080", @src());
    std.debug.print("\n", .{});

    std.debug.print("=== Part 4: Rule Management ===\n\n", .{});

    std.debug.print("Disabling Rule #2 (performance)...\n", .{});
    rules.disableRule(2);

    std.debug.print("Test: WARNING after disabling Rule #2 (no guidance expected):\n", .{});
    try logger.warning("Another slow query", @src());
    std.debug.print("\n", .{});

    std.debug.print("Re-enabling Rule #2...\n", .{});
    rules.enableRule(2);

    std.debug.print("Test: WARNING after re-enabling (guidance should appear):\n", .{});
    try logger.warning("Yet another slow query", @src());
    std.debug.print("\n", .{});

    std.debug.print("Removing Rule #3 (security)...\n", .{});
    const removed = rules.remove(3);
    std.debug.print("   Removed: {}\n", .{removed});
    std.debug.print("   Remaining rules: {}\n\n", .{rules.count()});

    std.debug.print("=== Part 5: Statistics ===\n\n", .{});

    const stats = rules.getStats();
    std.debug.print("   Rules evaluated:    {}\n", .{stats.rules_evaluated.load(.monotonic)});
    std.debug.print("   Rules matched:      {}\n", .{stats.rules_matched.load(.monotonic)});
    std.debug.print("   Messages emitted:   {}\n", .{stats.messages_emitted.load(.monotonic)});
    std.debug.print("   Evaluations skipped: {}\n", .{stats.evaluations_skipped.load(.monotonic)});
    std.debug.print("   Match rate:         {d:.1}%\n\n", .{stats.matchRate() * 100});

    std.debug.print("=== Part 6: JSON Output ===\n\n", .{});

    const json_messages = [_]logly.Rules.RuleMessage{
        logly.Rules.RuleMessage.cause("Example error analysis"),
        logly.Rules.RuleMessage.fix("Example solution"),
    };

    var json_buf: std.ArrayList(u8) = .empty;
    defer json_buf.deinit(allocator);

    try rules.formatMessagesJson(&json_messages, json_buf.writer(allocator), true);
    std.debug.print("{s}\n\n", .{json_buf.items});

    std.debug.print("=== Cleanup ===\n\n", .{});
    rules.clear();
    std.debug.print("   All rules cleared. Count: {}\n", .{rules.count()});

    std.debug.print("\n", .{});
    std.debug.print("========================================\n", .{});
    std.debug.print("    Demo Complete!\n", .{});
    std.debug.print("========================================\n\n", .{});
}
