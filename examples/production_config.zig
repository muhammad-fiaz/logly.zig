const std = @import("std");
const logly = @import("logly");
const Config = logly.Config;
const SinkConfig = logly.SinkConfig;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== Production Configuration Example ===\n\n", .{});

    // --- Using Production Preset ---
    std.debug.print("--- 1. Production Preset Configuration ---\n\n", .{});
    {
        const logger = try logly.Logger.init(allocator);
        defer logger.deinit();

        // Apply production preset
        const config = logly.ConfigPresets.production();
        logger.configure(config);

        std.debug.print("Production preset applies:\n", .{});
        std.debug.print("  - Level: warning (fewer logs)\n", .{});
        std.debug.print("  - JSON format for log aggregation\n", .{});
        std.debug.print("  - Sampling enabled (1% of debug logs)\n", .{});
        std.debug.print("  - Async writing for performance\n\n", .{});

        // These debug logs are sampled at 1%
        try logger.debug("Debug: Most of these won't appear");
        try logger.info("Info: Some sampling applied");
        try logger.warning("Warning: Always logged");
        try logger.err("Error: Always logged");
    }

    // --- Using Development Preset ---
    std.debug.print("\n--- 2. Development Preset Configuration ---\n\n", .{});
    {
        const logger = try logly.Logger.init(allocator);
        defer logger.deinit();

        // Apply development preset
        const config = logly.ConfigPresets.development();
        logger.configure(config);

        std.debug.print("Development preset applies:\n", .{});
        std.debug.print("  - Level: debug (verbose logging)\n", .{});
        std.debug.print("  - Colorful console output\n", .{});
        std.debug.print("  - Source location shown\n", .{});
        std.debug.print("  - No sampling (all logs shown)\n\n", .{});

        try logger.trace("Trace: Detailed debugging");
        try logger.debug("Debug: Development info");
        try logger.info("Info: General information");
        try logger.success("Success: Operation completed");
    }

    // --- Using High Throughput Preset ---
    std.debug.print("\n--- 3. High Throughput Configuration ---\n\n", .{});
    {
        const logger = try logly.Logger.init(allocator);
        defer logger.deinit();

        // Apply high throughput preset
        const config = logly.ConfigPresets.highThroughput();
        logger.configure(config);

        std.debug.print("High throughput preset applies:\n", .{});
        std.debug.print("  - Large buffer sizes\n", .{});
        std.debug.print("  - Aggressive sampling\n", .{});
        std.debug.print("  - Rate limiting enabled\n", .{});
        std.debug.print("  - Optimized for high-volume logging\n\n", .{});

        // Simulate high volume logging
        var i: usize = 0;
        while (i < 100) : (i += 1) {
            try logger.info("High volume log message");
        }
        std.debug.print("Logged 100 messages with sampling\n", .{});
    }

    // --- Using Secure Preset ---
    std.debug.print("\n--- 4. Secure Configuration (Compliance) ---\n\n", .{});
    {
        const logger = try logly.Logger.init(allocator);
        defer logger.deinit();

        // Apply secure preset
        const config = logly.ConfigPresets.secure();
        logger.configure(config);

        std.debug.print("Secure preset applies:\n", .{});
        std.debug.print("  - PII redaction enabled\n", .{});
        std.debug.print("  - Sensitive data patterns masked\n", .{});
        std.debug.print("  - Strict error handling\n", .{});
        std.debug.print("  - Audit-ready logging\n\n", .{});

        // Sensitive data will be redacted
        try logger.info("User login: email=test@example.com");
        try logger.info("Payment: card=4111111111111111");
    }

    // --- Custom Production Configuration ---
    std.debug.print("\n--- 5. Custom Production Setup ---\n\n", .{});
    {
        const logger = try logly.Logger.init(allocator);
        defer logger.deinit();

        // Start with production preset and customize
        var config = logly.ConfigPresets.production();

        // Custom modifications
        config.level = .info; // Allow info logs
        config.include_hostname = true; // Include server hostname
        config.include_pid = true; // Include process ID
        config.show_thread_id = true; // Include thread ID
        config.time_format = "ISO8601"; // ISO 8601 timestamps

        logger.configure(config);

        // Add file sink for persistent logging
        _ = try logger.addSink(.{
            .path = "logs/production.log",
            .json = true,
            .rotation = "daily",
            .retention = 30, // Keep 30 days of logs
        });

        std.debug.print("Custom production config with file logging:\n", .{});
        try logger.info("Application started");
        try logger.info("Configuration loaded successfully");
        try logger.warning("Connection pool near capacity");

        try logger.flush();
    }

    // --- Multi-Sink Production Setup ---
    std.debug.print("\n--- 6. Multi-Sink Production Architecture ---\n\n", .{});
    {
        const logger = try logly.Logger.init(allocator);
        defer logger.deinit();

        var config = Config.default();
        config.auto_sink = false;
        config.level = .debug;
        logger.configure(config);

        // Console: Colored output for development/monitoring
        _ = try logger.addSink(.{
            .name = "console",
            .level = .warning, // Only warnings and above
            .color = true,
        });

        // Application log: All levels
        _ = try logger.addSink(.{
            .name = "app-log",
            .path = "logs/app.log",
            .json = true,
            .level = .info,
            .rotation = "daily",
            .retention = 14,
        });

        // Error log: Only errors and critical
        _ = try logger.addSink(.{
            .name = "error-log",
            .path = "logs/error.log",
            .json = true,
            .level = .err,
            .rotation = "daily",
            .retention = 90, // Keep errors longer
        });

        std.debug.print("Multi-sink setup:\n", .{});
        std.debug.print("  - Console: warnings+ only\n", .{});
        std.debug.print("  - app.log: info+ (14 days retention)\n", .{});
        std.debug.print("  - error.log: errors+ (90 days retention)\n\n", .{});

        try logger.debug("Debug: Only in full app log");
        try logger.info("Info: In app.log");
        try logger.warning("Warning: In console and app.log");
        try logger.err("Error: In all three outputs");

        try logger.flush();
    }

    std.debug.print("\n=== Production Configuration Example Complete ===\n", .{});
    std.debug.print("Check logs/ directory for generated log files.\n", .{});
}
