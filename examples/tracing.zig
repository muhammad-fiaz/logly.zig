const std = @import("std");
const logly = @import("logly");
const Config = logly.Config;

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("Distributed Tracing Example\n\n", .{});

    // 1. Configure Distributed Logger
    var config = Config.default();
    config.distributed = .{
        .enabled = true,
        .serviceName = "tracing-example",
        .environment = "demo",
        .region = "local",
    };

    // Create logger
    const logger = try logly.Logger.initWithConfig(allocator, config);
    defer logger.deinit();

    std.debug.print("Distributed Logger Usage (Preferred)\n\n", .{});

    // Simulating a request handling scope
    {
        const traceId = "trace-uuid-v4-123456";
        const spanId = "span-001";

        // Create a lightweight distributed logger for this scope
        const reqLogger = logger.withTrace(traceId, spanId);

        try reqLogger.info("Request received", @src());
        try reqLogger.warning("Simulated latency high", @src());

        // Context is automatically attached:
        // { ... "service": "tracing-example", "trace_id": "trace-uuid-v4-123456" ... }
    }

    std.debug.print("\nGlobal Trace Context (Legacy)\n\n", .{});

    // Set trace context for distributed tracing globally
    try logger.setTraceContext("trace-legacy-global", "span-global");
    try logger.setCorrelationId("corr-req-789");

    std.debug.print("Trace ID: trace-legacy-global\n", .{});
    std.debug.print("Span ID: span-global\n", .{});

    try logger.info("Global context message", @src());

    std.debug.print("\nUsing Child Spans\n\n", .{});

    // Create a child span for nested operations
    {
        var span = try logger.startSpan("database-query"); // Generates new Span ID, parent=previous

        try logger.info("Querying users table", @src());
        try logger.debug("SELECT * FROM users", @src());

        try span.end(null, @src());
    }

    logger.clearTraceContext();
    std.debug.print("\nDone.\n", .{});
}
