---
title: Distributed Logging Example
description: A complete example of a simulated microservice using Logly.zig's distributed features. Shows configuration, trace propagation, and structured JSON output.
head:
  - - meta
    - name: keywords
      content: distributed example, microservice logging example, zig microservice, structured logging example
---

# Distributed Logging Example

This example simulates a "User Service" in a distributed environment. It demonstrates how to configure service identity and handle traces.

```zig
const std = @import("std");
const logly = @import("logly");
const Config = logly.Config;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
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

    // 2. Simulate Incoming Request (e.g., from an API Gateway)
    // In a real app, these come from HTTP headers
    const incoming_trace = "trace-8899aabb-ccdd";
    const incoming_span = "span-gateway-01";

    std.debug.print("--- Simulating Request Processing ---\n", .{});

    // 3. Create Scoped Logger for this Request
    const req_logger = logger.withTrace(incoming_trace, incoming_span);

    // 4. Log events
    try req_logger.info("Received getUser(id=42)");
    // Output: 
    // {
    //   "timestamp": ...,
    //   "level": "INFO", 
    //   "message": "Received getUser(id=42)",
    //   "service": "user-service",
    //   "trace_id": "trace-8899aabb-ccdd",
    //   "span_id": "span-gateway-01",
    //   "env": "production"
    // }

    // 5. Simulate DB Call (Child Operation)
    {
        // manually creating a sub-span logic or just logging with same context
        try req_logger.debug("Querying database: SELECT * FROM users WHERE id=42");
    }

    try req_logger.success("User found, returning 200 OK");
}
```
