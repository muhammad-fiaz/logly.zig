const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== Distributed Tracing Example ===\n\n", .{});

    // Create logger
    const logger = try logly.Logger.init(allocator);
    defer logger.deinit();

    std.debug.print("--- Setting Trace Context ---\n\n", .{});

    // Set trace context for distributed tracing
    // setTraceContext(trace_id, optional_span_id)
    try logger.setTraceContext("trace-abc123-def456", "span-001");
    try logger.setCorrelationId("corr-req-789");

    std.debug.print("Trace ID: trace-abc123-def456\n", .{});
    std.debug.print("Span ID: span-001\n", .{});
    std.debug.print("Correlation ID: corr-req-789\n", .{});

    std.debug.print("\n--- Logging with Trace Context ---\n\n", .{});

    // Log messages - trace context will be included in records
    try logger.info("Request received");
    try logger.debug("Processing request data");
    try logger.info("Calling external service");

    std.debug.print("\n--- Using Child Spans ---\n\n", .{});

    // Create a child span for nested operations
    // startSpan() creates a new span ID and returns a SpanContext
    {
        var span = try logger.startSpan("external-service");

        try logger.info("External service call started");
        try logger.debug("Sending request to API");
        try logger.info("External service responded");

        try span.end(null); // End span, pass optional message
    }
    // Parent span is automatically restored here

    std.debug.print("\n--- Database Span ---\n\n", .{});

    {
        var db_span = try logger.startSpan("database-operation");

        try logger.info("Saving to database");
        try logger.success("Database write successful");

        try db_span.end("database operation completed");
    }

    std.debug.print("\n--- Back to Parent Span ---\n\n", .{});

    try logger.success("Request completed successfully");

    std.debug.print("\n--- Using Context for Service Metadata ---\n\n", .{});

    // You can also add service metadata as context using bind()
    // bind() accepts key and std.json.Value
    try logger.bind("service", .{ .string = "user-service" });
    try logger.bind("version", .{ .string = "1.0.0" });
    try logger.bind("environment", .{ .string = "production" });

    try logger.info("Service metadata added to context");

    std.debug.print("\n--- Clearing Trace Context ---\n\n", .{});

    // Clear trace context when request is done
    logger.clearTraceContext();

    std.debug.print("Trace context cleared\n", .{});

    try logger.info("New request without trace context");

    std.debug.print("\n=== Tracing Example Complete ===\n", .{});
}
