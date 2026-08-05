const std = @import("std");
const logly = @import("logly");

/// Logly Invoke Demo
/// Demonstrates attaching extra messages to log records when
/// conditions match — level-based, message content, and custom levels.
pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    _ = logly.Terminal.enableAnsiColors();

    std.debug.print("\n", .{});
    std.debug.print("========================================\n", .{});
    std.debug.print("    Logly Invoke Demo\n", .{});
    std.debug.print("========================================\n\n", .{});

    // Setup logger with invoke enabled
    var config = logly.Config{};
    config.rules.enabled = true;

    var logger = try logly.Logger.initWithConfig(allocator, config);
    defer logger.deinit();

    // Create invoke engine
    var invoke = logly.Invoke.init(allocator);
    defer invoke.deinit();
    invoke.enable();

    // 1. Level-based trigger: errors get extra context
    const err_messages = [_]logly.Invoke.Message{
        ">> [ERROR] Database connection pool exhausted",
        ">> [FIX] Increase max_connections in database.yml",
        ">> [DOC] https://docs.example.com/db-pooling",
    };

    try invoke.add(.{
        .id = 1,
        .name = "db_pool_detector",
        .level_match = .{ .exact = .err },
        .message_contains = "database",
        .messages = &err_messages,
    });

    // 2. Warning trigger: performance hint
    const perf_messages = [_]logly.Invoke.Message{
        ">> [WARN] Operation exceeded performance threshold",
        ">> [TIP] Consider caching frequently accessed data",
    };

    try invoke.add(.{
        .id = 2,
        .name = "perf_hint",
        .level_match = .{ .exact = .warning },
        .messages = &perf_messages,
    });

    // 3. Any-level trigger with message pattern
    const security_messages = [_]logly.Invoke.Message{
        ">> [SECURITY] Possible SQL injection detected",
        ">> [ACTION] Reject request and log attacker IP",
    };

    try invoke.add(.{
        .id = 3,
        .name = "sqli_detector",
        .level_match = .{ .any = {} },
        .message_contains = "SELECT * FROM",
        .messages = &security_messages,
    });

    // 4. Custom level trigger
    const audit_messages = [_]logly.Invoke.Message{
        ">> [AUDIT] Sensitive data accessed",
    };

    try invoke.add(.{
        .id = 4,
        .name = "audit_detector",
        .level_match = .{ .custom_name = "audit" },
        .messages = &audit_messages,
    });

    // 5. Slow operation detector (duration-based)
    const slow_messages = [_]logly.Invoke.Message{
        ">> [SLOW] Operation exceeded 500ms latency budget",
    };

    try invoke.add(.{
        .id = 5,
        .name = "slow_op_detector",
        .level_match = .{ .any = {} },
        .min_duration_ns = 500_000_000,
        .messages = &slow_messages,
    });

    // Attach to logger
    logger.setInvoke(&invoke);

    std.debug.print("=== Testing Triggers ===\n\n", .{});

    // Test: error with database message → should trigger #1
    try logger.err("database connection timeout after 30s", @src());

    // Test: warning → should trigger #2
    try logger.warn("request processing slow", @src());

    // Test: info with SQL pattern → should trigger #3
    try logger.info("SELECT * FROM users WHERE id = 1", @src());

    // Test: debug → no triggers should fire
    try logger.debug("entering function handle_request", @src());

    // Test: error without database pattern → no trigger
    try logger.err("file not found: config.yaml", @src());

    std.debug.print("\n=== Statistics ===\n\n", .{});

    const stats = invoke.getStats();
    std.debug.print("   Triggers evaluated: {}\n", .{stats.getTriggersEvaluated()});
    std.debug.print("   Triggers matched:   {}\n", .{stats.getTriggersMatched()});
    std.debug.print("   Messages emitted:   {}\n", .{stats.getMessagesEmitted()});

    std.debug.print("\n=== Once-Fire Trigger ===\n\n", .{});

    // Once-fire trigger
    const once_messages = [_]logly.Invoke.Message{
        ">> [ONCE] This message fires only once",
    };

    try invoke.add(.{
        .id = 6,
        .name = "once_detector",
        .once = true,
        .level_match = .{ .exact = .info },
        .messages = &once_messages,
    });

    try logger.info("first info message", @src());
    try logger.info("second info message — no trigger", @src());

    std.debug.print("\nDone.\n", .{});
}
