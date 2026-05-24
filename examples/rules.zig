const std = @import("std");
const logly = @import("logly");

/// Logly Rules System Demo
/// Demonstrates compiler-style guided diagnostics for log messages,
/// error analysis, security detection, performance monitoring, and
/// rule chaining with priority ordering.
pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
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
        .once = false,
        .level_match = .{ .exact = .info },
        .message_contains = "started",
        .messages = &init_messages,
    });
    std.debug.print("[OK] Added Rule #4: Startup notice (always fires)\n", .{});

    // Rule 5: Timed operation latency detector
    const slow_op_messages = [_]logly.Rules.RuleMessage{
        logly.Rules.RuleMessage.perf("Operation exceeded latency budget of 500ms"),
        logly.Rules.RuleMessage.suggest("Check system resources, DB index queries, or network load"),
    };

    try rules.add(.{
        .id = 5,
        .name = "slow-operation",
        .min_duration_ns = 500_000_000, // 500ms
        .messages = &slow_op_messages,
    });
    std.debug.print("[OK] Added Rule #5: Latency detector (500ms)\n", .{});

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

    std.debug.print("Test 4: INFO with 'started' (triggers Rule #4):\n", .{});
    try logger.info("Application started successfully", @src());
    std.debug.print("\n", .{});

    std.debug.print("Test 5: INFO again (Rule #4 fires AGAIN):\n", .{});
    try logger.info("Service started on port 8080", @src());
    std.debug.print("\n", .{});

    std.debug.print("Test 6: Timed log operation (triggers Rule #5 if latency > 500ms):\n", .{});
    const query_start = logly.Utils.currentNanos();
    // Simulate a 600ms slow database query
    logly.Utils.sleepMs(600);
    _ = try logger.logTimed(.warning, "Slow DB query: SELECT * FROM users", query_start);
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

    std.debug.print("=== Part 5: Error Analysis Rules ===\n\n", .{});

    var error_rules = logly.Rules.init(allocator);
    defer error_rules.deinit();
    error_rules.enable();

    // Database error pattern
    const db_err_msgs = [_]logly.Rules.RuleMessage{
        logly.Rules.RuleMessage.cause("Database driver reported an error"),
        logly.Rules.RuleMessage.fix("Check DB server reachability and credentials"),
        logly.Rules.RuleMessage.perf("Consider connection pooling to reduce latency"),
    };
    try error_rules.add(.{
        .id = 10,
        .name = "db_error_analysis",
        .level_match = .{ .exact = .err },
        .message_contains = "database",
        .messages = &db_err_msgs,
    });

    // Network timeout pattern
    const timeout_msgs = [_]logly.Rules.RuleMessage{
        logly.Rules.RuleMessage.cause("Network request exceeded timeout threshold"),
        logly.Rules.RuleMessage.fix("Increase timeout or implement retry logic"),
        logly.Rules.RuleMessage.suggest("Use exponential back-off for retries"),
    };
    try error_rules.add(.{
        .id = 11,
        .name = "network_timeout_analysis",
        .level_match = .{ .exact = .err },
        .message_contains = "timeout",
        .messages = &timeout_msgs,
    });

    // OOM pattern
    const oom_msgs = [_]logly.Rules.RuleMessage{
        logly.Rules.RuleMessage.cause("Allocator ran out of available memory"),
        logly.Rules.RuleMessage.action("Reduce allocation sizes or increase system memory"),
        logly.Rules.RuleMessage.fix("Profile heap usage with a memory analyser"),
    };
    try error_rules.add(.{
        .id = 12,
        .name = "oom_analysis",
        .level_match = .{ .exact = .err },
        .message_contains = "out of memory",
        .messages = &oom_msgs,
    });

    std.debug.print("   Error analysis rules configured ({d} rules)\n", .{error_rules.count()});
    std.debug.print("   Rules: db_error_analysis, network_timeout_analysis, oom_analysis\n\n", .{});

    std.debug.print("=== Part 6: Security Alert Rules ===\n\n", .{});

    var security_rules = logly.Rules.init(allocator);
    defer security_rules.deinit();
    security_rules.enable();

    // Unauthorized access detection
    const unauth_msgs = [_]logly.Rules.RuleMessage{
        logly.Rules.RuleMessage.security("Access attempt without valid credentials"),
        logly.Rules.RuleMessage.action("Audit access controls and rotate secrets"),
        logly.Rules.RuleMessage.fix("Verify IAM policy and token expiry"),
    };
    try security_rules.add(.{
        .id = 20,
        .name = "unauthorized_access",
        .level_match = .{ .exact = .warning },
        .message_contains = "unauthorized",
        .priority = 10,
        .messages = &unauth_msgs,
    });

    // Brute force detection
    const brute_msgs = [_]logly.Rules.RuleMessage{
        logly.Rules.RuleMessage.security("Repeated authentication failures from same source"),
        logly.Rules.RuleMessage.action("Block source IP and alert the security team"),
        logly.Rules.RuleMessage.fix("Enforce rate limiting on login endpoints"),
    };
    try security_rules.add(.{
        .id = 21,
        .name = "brute_force_detection",
        .level_match = .{ .exact = .err },
        .message_contains = "authentication failed",
        .priority = 20,
        .messages = &brute_msgs,
    });

    // SQL injection pattern
    const sqli_msgs = [_]logly.Rules.RuleMessage{
        logly.Rules.RuleMessage.security("Possible SQL injection payload detected in input"),
        logly.Rules.RuleMessage.action("Reject request and log attacker IP immediately"),
        logly.Rules.RuleMessage.fix("Use parameterised queries / prepared statements"),
        logly.Rules.RuleMessage.docs("OWASP SQL Injection", "https://owasp.org/www-community/attacks/SQL_Injection"),
    };
    try security_rules.add(.{
        .id = 22,
        .name = "sql_injection_detection",
        .level_match = .{ .exact = .critical },
        .message_contains = "sql injection",
        .priority = 100,
        .messages = &sqli_msgs,
    });

    std.debug.print("   Security rules configured ({d} rules)\n", .{security_rules.count()});
    std.debug.print("   Priorities: unauthorized=10, brute_force=20, sql_injection=100\n\n", .{});

    std.debug.print("=== Part 7: Performance Hint Rules ===\n\n", .{});

    var perf_rules = logly.Rules.init(allocator);
    defer perf_rules.deinit();
    perf_rules.enable();

    // Slow query detection
    const slow_query_msgs = [_]logly.Rules.RuleMessage{
        logly.Rules.RuleMessage.perf("Query execution time exceeded 500ms"),
        logly.Rules.RuleMessage.fix("Add an index on the filtered column(s)"),
        logly.Rules.RuleMessage.suggest("Review EXPLAIN output and avoid full table scans"),
    };
    try perf_rules.add(.{
        .id = 30,
        .name = "slow_query",
        .level_match = .{ .exact = .warning },
        .message_contains = "slow query",
        .messages = &slow_query_msgs,
    });

    // High memory usage
    const high_mem_msgs = [_]logly.Rules.RuleMessage{
        logly.Rules.RuleMessage.perf("Heap usage crossed 80% of allocated limit"),
        logly.Rules.RuleMessage.fix("Free unused allocations and check for leaks"),
        logly.Rules.RuleMessage.suggest("Consider using an arena allocator for short-lived data"),
    };
    try perf_rules.add(.{
        .id = 31,
        .name = "high_memory",
        .level_match = .{ .exact = .warning },
        .message_contains = "memory usage",
        .messages = &high_mem_msgs,
    });

    // CPU spike hint
    const cpu_msgs = [_]logly.Rules.RuleMessage{
        logly.Rules.RuleMessage.perf("CPU utilisation spike detected"),
        logly.Rules.RuleMessage.fix("Profile hot paths with a sampling profiler"),
        logly.Rules.RuleMessage.suggest("Offload CPU-intensive work to a thread pool"),
    };
    try perf_rules.add(.{
        .id = 32,
        .name = "cpu_spike",
        .level_match = .{ .exact = .warning },
        .message_contains = "cpu",
        .messages = &cpu_msgs,
    });

    std.debug.print("   Performance hint rules configured ({d} rules)\n\n", .{perf_rules.count()});

    std.debug.print("=== Part 8: Rule Chaining and Priority Ordering ===\n\n", .{});

    var chained_rules = logly.Rules.init(allocator);
    defer chained_rules.deinit();
    chained_rules.enable();

    // Low-priority informational rule (priority=1 — fires last in severity sort)
    const low_prio_msgs = [_]logly.Rules.RuleMessage{
        logly.Rules.RuleMessage.note("Low-priority informational match"),
    };
    try chained_rules.add(.{
        .id = 40,
        .name = "low_priority_info",
        .level_match = .{ .any = {} },
        .priority = 1,
        .messages = &low_prio_msgs,
    });

    // Medium-priority warning rule (priority=50)
    const mid_prio_msgs = [_]logly.Rules.RuleMessage{
        logly.Rules.RuleMessage.caution("Mid-priority: action may be required"),
        logly.Rules.RuleMessage.fix("Review configuration before proceeding"),
    };
    try chained_rules.add(.{
        .id = 41,
        .name = "mid_priority_warning",
        .level_match = .{ .min_priority = 30 }, // warnings and above
        .priority = 50,
        .messages = &mid_prio_msgs,
    });

    // High-priority critical escalation (priority=99 — fires first in severity sort)
    const high_prio_msgs = [_]logly.Rules.RuleMessage{
        logly.Rules.RuleMessage.security("High-priority: critical escalation triggered"),
        logly.Rules.RuleMessage.action("Page on-call engineer immediately"),
    };
    try chained_rules.add(.{
        .id = 42,
        .name = "high_priority_critical",
        .level_match = .{ .exact = .critical },
        .priority = 99,
        .messages = &high_prio_msgs,
    });

    // Sort rules by priority so higher-priority rules run first
    chained_rules.sortByPriority();

    std.debug.print("   Chained rules ({d} total) — sorted by descending priority:\n", .{chained_rules.count()});
    std.debug.print("     priority=99  high_priority_critical  (critical only)\n", .{});
    std.debug.print("     priority=50  mid_priority_warning    (warnings+)\n", .{});
    std.debug.print("     priority=1   low_priority_info       (any level)\n\n", .{});

    std.debug.print("=== Part 9: Statistics ===\n\n", .{});

    const stats = rules.getStats();
    std.debug.print("   Rules evaluated:     {}\n", .{stats.getRulesEvaluated()});
    std.debug.print("   Rules matched:       {}\n", .{stats.getRulesMatched()});
    std.debug.print("   Messages emitted:    {}\n", .{stats.getMessagesEmitted()});
    std.debug.print("   Evaluations skipped: {}\n", .{stats.getEvaluationsSkipped()});
    std.debug.print("   Match rate:          {d:.1}%\n\n", .{stats.matchRate() * 100});

    std.debug.print("=== Part 10: JSON Output ===\n\n", .{});

    const json_messages = [_]logly.Rules.RuleMessage{
        logly.Rules.RuleMessage.cause("Example error analysis"),
        logly.Rules.RuleMessage.fix("Example solution"),
    };

    var json_buf: std.ArrayList(u8) = .empty;
    defer json_buf.deinit(allocator);

    var json_writer = logly.Utils.ArrayListWriter.init(&json_buf, allocator);
    try rules.formatMessagesJson(&json_messages, &json_writer.writer, true);
    std.debug.print("{s}\n\n", .{json_buf.items});

    std.debug.print("=== Cleanup ===\n\n", .{});
    rules.clear();
    std.debug.print("   All rules cleared. Count: {}\n", .{rules.count()});

    std.debug.print("\n", .{});
    std.debug.print("========================================\n", .{});
    std.debug.print("    Demo Complete!\n", .{});
    std.debug.print("========================================\n\n", .{});
}
