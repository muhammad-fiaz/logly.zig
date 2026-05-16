---
title: Distributed Logging Example
description: A complete example of a simulated microservice using Logly.zig's distributed features. Shows configuration, trace propagation, and structured JSON output.
head:
  - - meta
    - name: keywords
      content: distributed example, microservice logging example, zig microservice, structured logging example
---

# Distributed Logging Example

This example simulates a "User Service" in a distributed environment. It demonstrates service identity, W3C `traceparent` ingestion, scoped request logging, and downstream propagation.

```zig
const std = @import("std");
const logly = @import("logly");
const Config = logly.Config;

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 1. Setup Distributed Configuration
    var config = Config.default();
    config.distributed = .{
        .enabled = true,
        .service_name = "user-service",
        .service_version = "1.0.0",
        .environment = "production",
        .region = "us-east-1",
        .datacenter = "az-1"
    };
    // Enable JSON for structured output
    config.json = true; 

    // Initialize Global Logger
    const logger = try logly.Logger.initWithConfig(allocator, config);
    defer logger.deinit();

    // 2. Simulate Incoming Request Header (e.g., API Gateway)
    const incoming_traceparent = "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01";

    std.debug.print("--- Simulating Request Processing ---\n", .{});

    // 3. Create scoped logger from W3C trace context
    var req_logger = try logger.withTraceparent(incoming_traceparent);
    req_logger = req_logger.inModule("http.request");

    // 4. Log events
    try req_logger.info("Received getUser(id=42)", @src());
    // Output: 
    // {
    //   "timestamp": ...,
    //   "level": "INFO", 
    //   "message": "Received getUser(id=42)",
    //   "service": "user-service",
    //   "trace_id": "4bf92f3577b34da6a3ce929d0e0e4736",
    //   "span_id": "00f067aa0ba902b7",
    //   "env": "production"
    // }

    // 5. Simulate DB Call (Child Operation)
    {
      const db_logger = req_logger.child("7a085853722dc6d2").inModule("database.query");
      try db_logger.debug("Querying database: SELECT * FROM users WHERE id=42", @src());
    }

    // 6. Propagate trace context to downstream service
    if (try logger.getTraceparentHeader(allocator)) |traceparent| {
      defer allocator.free(traceparent);
      std.debug.print("Forward traceparent: {s}\n", .{traceparent});
    }

    try req_logger.success("User found, returning 200 OK", @src());
}
```
