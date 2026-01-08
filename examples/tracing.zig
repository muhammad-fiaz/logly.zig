const std = @import("std");
const logly = @import("logly");
const Config = logly.Config;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== Distributed Tracing Example ===\n\n", .{});

    // 1. Configure Distributed Logger
    // ----------------------------
    var config = Config.default();
    config.distributed = .{
        .enabled = true,
        .service_name = "tracing-example",
        .environment = "demo",
        .region = "local",
    };

    // Create logger
    const logger = try logly.Logger.initWithConfig(allocator, config);
    defer logger.deinit();

    std.debug.print("--- Distributed Logger Usage (Preferred) ---\n\n", .{});

    // Simulating a request handling scope
    {
        const trace_id = "trace-uuid-v4-123456";
        const span_id = "span-001";

        // Create a lightweight distributed logger for this scope
        const req_logger = logger.withTrace(trace_id, span_id);

        try req_logger.info("Request received", @src());
        try req_logger.warn("Simulated latency high", @src());

        // Context is automatically attached:
        // { ... "service": "tracing-example", "trace_id": "trace-uuid-v4-123456" ... }
    }

    std.debug.print("\n--- Global Trace Context (Legacy) ---\n\n", .{});

    // Set trace context for distributed tracing globally
    try logger.setTraceContext("trace-legacy-global", "span-global");
    try logger.setCorrelationId("corr-req-789");

    std.debug.print("Trace ID: trace-legacy-global\n", .{});
    std.debug.print("Span ID: span-global\n", .{});

    try logger.info("Global context message", @src());

    std.debug.print("\n--- Using Child Spans ---\n\n", .{});

    // Create a child span for nested operations
    {
        var span = try logger.startSpan("database-query"); // Generates new Span ID, parent=previous

        try logger.info("Querying users table", @src());
        try logger.debug("SELECT * FROM users", @src());

        try span.end(null);
    }

    logger.clearTraceContext();
    std.debug.print("\nDone.\n", .{});
}
