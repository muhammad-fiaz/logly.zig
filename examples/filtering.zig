const std = @import("std");
const logly = @import("logly");
// this will help u understand filtering in logly.zig :)
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Enable ANSI colors on Windows
    _ = logly.Terminal.enableAnsiColors();

    std.debug.print("\n", .{});
    printSeparator("COMPREHENSIVE FILTERING EXAMPLE");

    // =========================================
    // 1. BASIC LEVEL FILTERING
    // =========================================
    printSection("1. Basic Level Filtering (Min Level: WARNING)");
    {
        const logger = try logly.Logger.init(allocator);
        defer logger.deinit();

        var filter = logly.Filter.init(allocator);
        defer filter.deinit();
        try filter.addMinLevel(.warning);
        logger.setFilter(&filter);

        // These are filtered out (below WARNING)
        try logger.trace("FILTERED: trace message", @src());
        try logger.debug("FILTERED: debug message", @src());
        try logger.info("FILTERED: info message", @src());

        // These pass through (WARNING and above)
        try logger.warn("PASS: warning message", @src());
        try logger.err("PASS: error message", @src());
        try logger.crit("PASS: critical message", @src());
    }

    // =========================================
    // 2. LEVEL RANGE FILTERING (Min + Max)
    // =========================================
    printSection("2. Level Range Filtering (INFO to WARNING only)");
    {
        const logger = try logly.Logger.init(allocator);
        defer logger.deinit();

        var filter = logly.Filter.init(allocator);
        defer filter.deinit();
        try filter.addMinLevel(.info);
        try filter.addMaxLevel(.warning);
        logger.setFilter(&filter);

        try logger.debug("FILTERED: debug (below min)", @src());
        try logger.info("PASS: info message", @src());
        try logger.success("PASS: success message", @src());
        try logger.warn("PASS: warning message", @src());
        try logger.err("FILTERED: error (above max)", @src());
        try logger.crit("FILTERED: critical (above max)", @src());
    }

    // =========================================
    // 3. MESSAGE CONTENT FILTERING
    // =========================================
    printSection("3. Message Content Filtering");
    {
        const logger = try logly.Logger.init(allocator);
        defer logger.deinit();

        var filter = logly.Filter.init(allocator);
        defer filter.deinit();
        // Deny messages containing "heartbeat" or "ping"
        try filter.addMessageFilter("heartbeat", .deny);
        try filter.addMessageFilter("ping", .deny);
        logger.setFilter(&filter);

        try logger.info("PASS: User logged in successfully", @src());
        try logger.info("FILTERED: heartbeat check passed", @src());
        try logger.info("FILTERED: ping response received", @src());
        try logger.info("PASS: Database query completed", @src());
    }

    // =========================================
    // 4. FILTER PRESETS
    // =========================================
    printSection("4. Filter Presets");
    {
        std.debug.print("4a. Errors Only Preset:\n", .{});
        const logger1 = try logly.Logger.init(allocator);
        defer logger1.deinit();

        var errors_filter = try logly.FilterPresets.errorsOnly(allocator);
        defer errors_filter.deinit();
        logger1.setFilter(&errors_filter);

        try logger1.info("FILTERED: info message", @src());
        try logger1.warn("FILTERED: warning message", @src());
        try logger1.err("PASS: error message", @src());
        try logger1.crit("PASS: critical message", @src());

        std.debug.print("\n4b. Production Preset (INFO+):\n", .{});
        const logger2 = try logly.Logger.init(allocator);
        defer logger2.deinit();

        var prod_filter = try logly.FilterPresets.production(allocator);
        defer prod_filter.deinit();
        logger2.setFilter(&prod_filter);

        try logger2.trace("FILTERED: trace message", @src());
        try logger2.debug("FILTERED: debug message", @src());
        try logger2.info("PASS: info message", @src());
        try logger2.warn("PASS: warning message", @src());
    }

    // =========================================
    // 5. JSON OUTPUT WITH FILTERING
    // =========================================
    printSection("5. JSON Output with Filtering");
    {
        const logger = try logly.Logger.init(allocator);
        defer logger.deinit();

        // Clear auto-sink and add JSON sink
        _ = logger.removeAllSinks();
        _ = try logger.add(.{ .json = true });

        var filter = logly.Filter.init(allocator);
        defer filter.deinit();
        try filter.addMinLevel(.warning);
        logger.setFilter(&filter);

        try logger.info("FILTERED: info in JSON", @src());
        try logger.warn("PASS: warning in JSON format", @src());
        try logger.err("PASS: error in JSON format", @src());
    }

    // =========================================
    // 6. PRETTY JSON WITH FILTERING
    // =========================================
    printSection("6. Pretty JSON with Filtering");
    {
        const logger = try logly.Logger.init(allocator);
        defer logger.deinit();

        // Clear auto-sink and add pretty JSON sink
        _ = logger.removeAllSinks();
        _ = try logger.add(.{ .json = true, .pretty_json = true });

        var filter = logly.Filter.init(allocator);
        defer filter.deinit();
        try filter.addMinLevel(.err);
        logger.setFilter(&filter);

        try logger.warn("FILTERED: warning in pretty JSON", @src());
        try logger.err("PASS: error in pretty JSON", @src());
    }

    // =========================================
    // 7. CUSTOM LOG FORMAT WITH FILTERING
    // =========================================
    printSection("7. Custom Format with Filtering");
    {
        const logger = try logly.Logger.init(allocator);
        defer logger.deinit();

        // Clear auto-sink and configure custom format
        _ = logger.removeAllSinks();

        var config = logly.Config.default();
        config.log_format = "[{level}] {time} | {message}";
        config.time_format = "HH:mm:ss";
        logger.configure(config);

        _ = try logger.add(.{});

        var filter = logly.Filter.init(allocator);
        defer filter.deinit();
        try filter.addMinLevel(.info);
        logger.setFilter(&filter);

        try logger.debug("FILTERED: debug with custom format", @src());
        try logger.info("PASS: info with custom format", @src());
        try logger.warn("PASS: warning with custom format", @src());
    }

    // =========================================
    // 8. CUSTOM LOG LEVELS WITH FILTERING
    // =========================================
    printSection("8. Custom Log Levels with Filtering");
    {
        const logger = try logly.Logger.init(allocator);
        defer logger.deinit();

        // Add custom levels
        try logger.addCustomLevel("AUDIT", 35, "35;1"); // Between WARNING(30) and ERROR(40)
        try logger.addCustomLevel("SECURITY", 45, "91"); // Between ERROR(40) and CRITICAL(50)
        try logger.addCustomLevel("NOTICE", 22, "96"); // Between INFO(20) and SUCCESS(25)

        var filter = logly.Filter.init(allocator);
        defer filter.deinit();
        try filter.addMinLevel(.warning); // Priority 30
        logger.setFilter(&filter);

        // NOTICE (22) < WARNING (30), should be filtered
        try logger.custom("NOTICE", "FILTERED: notice message", @src());

        // AUDIT (35) >= WARNING (30), should pass
        try logger.custom("AUDIT", "PASS: audit event logged", @src());

        // SECURITY (45) >= WARNING (30), should pass
        try logger.custom("SECURITY", "PASS: security alert", @src());

        // Standard levels
        try logger.info("FILTERED: info message", @src());
        try logger.warn("PASS: warning message", @src());
    }

    // =========================================
    // 9. PER-SINK FILTERING
    // =========================================
    printSection("9. Per-Sink Level Filtering");
    {
        const logger = try logly.Logger.init(allocator);
        defer logger.deinit();

        // Clear the auto-created sink and add custom ones
        _ = logger.removeAllSinks();

        // Console sink - INFO and above
        _ = try logger.add(.{
            .level = .info,
        });

        // Errors-only sink (simulated with level filter)
        _ = try logger.add(.{
            .level = .err,
            .max_level = .critical,
        });

        std.debug.print("(First sink: INFO+, Second sink: ERROR to CRITICAL only)\n", .{});
        try logger.debug("FILTERED on both: debug", @src());
        try logger.info("Sink 1 only: info", @src());
        try logger.warn("Sink 1 only: warning", @src());
        try logger.err("Both sinks: error", @src());
        try logger.crit("Both sinks: critical", @src());
    }

    // =========================================
    // 10. PER-SINK MESSAGE FILTERING
    // =========================================
    printSection("10. Per-Sink Message Filtering");
    {
        const logger = try logly.Logger.init(allocator);
        defer logger.deinit();

        // Clear the auto-created sink and add a filtered one
        _ = logger.removeAllSinks();

        // Console sink that excludes heartbeat messages
        _ = try logger.add(.{
            .filter = .{
                .exclude_messages = &.{ "heartbeat", "ping", "health" },
            },
        });

        try logger.info("PASS: User authentication successful", @src());
        try logger.info("FILTERED: heartbeat check", @src());
        try logger.info("FILTERED: ping response", @src());
        try logger.info("FILTERED: health check passed", @src());
        try logger.info("PASS: Database connected", @src());
    }

    // =========================================
    // 11. MULTIPLE SINKS WITH DIFFERENT FILTERS
    // =========================================
    printSection("11. Multiple Sinks with Different Configs");
    {
        const logger = try logly.Logger.init(allocator);
        defer logger.deinit();

        // Clear the auto-created sink
        _ = logger.removeAllSinks();

        std.debug.print("Sink 1: Plain text, all levels\n", .{});
        std.debug.print("Sink 2: JSON format, WARNING+ only\n", .{});
        std.debug.print("(Output interleaved below)\n\n", .{});

        // Sink 1: Plain text console
        _ = try logger.add(.{});

        // Sink 2: JSON, warnings only
        _ = try logger.add(.{
            .json = true,
            .level = .warning,
        });

        try logger.info("Info: appears in plain text only", @src());
        try logger.warn("Warning: appears in both formats", @src());
        try logger.err("Error: appears in both formats", @src());
    }

    // =========================================
    // 12. FILTERING WITH CONTEXT BINDING
    // =========================================
    printSection("12. Filtering with Context Binding");
    {
        const logger = try logly.Logger.init(allocator);
        defer logger.deinit();

        // Clear auto-sink and add JSON sink
        _ = logger.removeAllSinks();
        _ = try logger.add(.{ .json = true });

        // Bind context
        try logger.bind("service", .{ .string = "api-gateway" });
        try logger.bind("version", .{ .string = "2.0.0" });

        var filter = logly.Filter.init(allocator);
        defer filter.deinit();
        try filter.addMinLevel(.info);
        logger.setFilter(&filter);

        try logger.debug("FILTERED: debug with context", @src());
        try logger.info("PASS: info with bound context", @src());
        try logger.warn("PASS: warning with bound context", @src());

        logger.unbind("service");
        logger.unbind("version");
    }

    // =========================================
    // 13. FILTERING WITH DISTRIBUTED TRACING
    // =========================================
    printSection("13. Filtering with Distributed Tracing");
    {
        const logger = try logly.Logger.init(allocator);
        defer logger.deinit();

        // Clear auto-sink and add JSON sink with trace ID
        _ = logger.removeAllSinks();
        _ = try logger.add(.{ .json = true, .include_trace_id = true });

        // Set trace context
        try logger.setTraceContext("trace-abc-123", "span-xyz-789");
        try logger.setCorrelationId("corr-request-001");

        var filter = logly.Filter.init(allocator);
        defer filter.deinit();
        try filter.addMinLevel(.warning);
        logger.setFilter(&filter);

        try logger.info("FILTERED: info with trace context", @src());
        try logger.warn("PASS: warning with trace context", @src());
        try logger.err("PASS: error with trace context", @src());

        logger.clearTraceContext();
    }

    // =========================================
    // 14. FILTERING WITH SAMPLING
    // =========================================
    printSection("14. Filtering Combined with Sampling");
    {
        const logger = try logly.Logger.init(allocator);
        defer logger.deinit();

        // Set up sampling (50% probability)
        var sampler = logly.Sampler.init(allocator, .{ .probability = 0.5 });
        defer sampler.deinit();
        logger.setSampler(&sampler);

        // Set up filter
        var filter = logly.Filter.init(allocator);
        defer filter.deinit();
        try filter.addMinLevel(.info);
        logger.setFilter(&filter);

        std.debug.print("(Sampling at 50% + Filter INFO+, results vary)\n", .{});

        var i: usize = 0;
        while (i < 10) : (i += 1) {
            try logger.debug("FILTERED: debug message", @src());
            try logger.infof("SAMPLED: info message {d}", .{i}, @src());
        }
    }

    // =========================================
    // 15. FILTERING WITH REDACTION
    // =========================================
    printSection("15. Filtering with Sensitive Data Redaction");
    {
        const logger = try logly.Logger.init(allocator);
        defer logger.deinit();

        // Set up redactor
        var redactor = logly.Redactor.init(allocator);
        defer redactor.deinit();
        try redactor.addPattern("password", .contains, "password=", "[REDACTED]");
        logger.setRedactor(&redactor);

        // Set up filter
        var filter = logly.Filter.init(allocator);
        defer filter.deinit();
        try filter.addMinLevel(.info);
        logger.setFilter(&filter);

        try logger.debug("FILTERED: debug with password=secret123", @src());
        try logger.info("PASS: User login with password=secret123", @src());
        try logger.warn("PASS: Auth failed with password=wrongpass", @src());
    }

    // =========================================
    // 16. FILTERING WITH METRICS
    // =========================================
    printSection("16. Filtering with Metrics Collection");
    {
        const logger = try logly.Logger.init(allocator);
        defer logger.deinit();

        logger.enableMetrics();

        var filter = logly.Filter.init(allocator);
        defer filter.deinit();
        try filter.addMinLevel(.warning);
        logger.setFilter(&filter);

        // Log some messages
        try logger.debug("FILTERED: debug", @src());
        try logger.info("FILTERED: info", @src());
        try logger.warn("PASS: warning 1", @src());
        try logger.warn("PASS: warning 2", @src());
        try logger.err("PASS: error", @src());

        // Get metrics
        if (logger.getMetrics()) |metrics| {
            std.debug.print("\nMetrics (only passed messages counted):\n", .{});
            std.debug.print("  Total records: {d}\n", .{metrics.total_records});
        }
    }

    // =========================================
    // 17. ALL STANDARD LOG LEVELS
    // =========================================
    printSection("17. All Standard Log Levels (No Filter)");
    {
        const logger = try logly.Logger.init(allocator);
        defer logger.deinit();

        // Set minimum level to trace to show all levels
        var config = logly.Config.default();
        config.level = .trace;
        logger.configure(config);

        // No filter - show all levels
        try logger.trace("Level 1 - TRACE (priority 5)", @src());
        try logger.debug("Level 2 - DEBUG (priority 10)", @src());
        try logger.info("Level 3 - INFO (priority 20)", @src());
        try logger.success("Level 4 - SUCCESS (priority 25)", @src());
        try logger.warn("Level 5 - WARNING (priority 30)", @src());
        try logger.err("Level 6 - ERROR (priority 40)", @src());
        try logger.fail("Level 7 - FAIL (priority 45)", @src());
        try logger.crit("Level 8 - CRITICAL (priority 50)", @src());
    }

    // =========================================
    // 18. SOURCE LOCATION DISPLAY
    // =========================================
    printSection("18. Source Location with Filtering");
    {
        const logger = try logly.Logger.init(allocator);
        defer logger.deinit();

        // Clear auto-sink and configure source location display
        _ = logger.removeAllSinks();

        var config = logly.Config.default();
        config.show_filename = true;
        config.show_lineno = true;
        logger.configure(config);

        _ = try logger.add(.{});

        var filter = logly.Filter.init(allocator);
        defer filter.deinit();
        try filter.addMinLevel(.info);
        logger.setFilter(&filter);

        try logger.debug("FILTERED: debug with source location", @src());
        try logger.info("PASS: info with file:line displayed", @src());
        try logger.warn("PASS: warning with source location", @src());
    }

    // =========================================
    // COMPLETE
    // =========================================
    std.debug.print("\n", .{});
    printSeparator("FILTERING EXAMPLE COMPLETE");
    std.debug.print("\n", .{});
}

fn printSeparator(title: []const u8) void {
    std.debug.print("============================================================\n", .{});
    std.debug.print("  {s}\n", .{title});
    std.debug.print("============================================================\n", .{});
}

fn printSection(title: []const u8) void {
    std.debug.print("\n--- {s} ---\n\n", .{title});
}
