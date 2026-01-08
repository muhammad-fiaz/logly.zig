---
title: Distributed Config API Reference
description: API reference for Logly.zig DistributedConfig struct. Configure service identification, tracing headers, and environment context for microservices.
head:
  - - meta
    - name: keywords
      content: distributed config, distributed logging api, microservices config, trace headers, service name, region
  - - meta
    - property: og:title
      content: Distributed Config API Reference | Logly.zig
---

# Distributed Config API

The `DistributedConfig` struct controls how the logger behaves in a distributed system, defining service identity and trace propagation rules.

## Fields

### `enabled: bool`

Enable distributed context features. When true, distributed fields (like service name, region) are automatically attached to logs. 
**Default**: `false`

### Service Identity

#### `service_name: ?[]const u8`

Name of the service or application (e.g., "auth-service", "payment-api").
**Default**: `null`

#### `service_version: ?[]const u8`

Semantic version of the running artifact (e.g., "1.0.2", "v2.0.0-rc1").
**Default**: `null`

#### `environment: ?[]const u8`

Deployment environment (e.g., "production", "staging", "development").
**Default**: `null`

#### `datacenter: ?[]const u8`

Datacenter or Availability Zone identifier (e.g., "us-east-1a", "eu-west-2").
**Default**: `null`

#### `region: ?[]const u8`

Cloud region identifier (e.g., "us-east-1").
**Default**: `null`

#### `instance_id: ?[]const u8`

Unique identifier for the specific instance (e.g., Kubernetes Pod ID, EC2 Instance ID, container ID).
**Default**: `null`

### Trace Propagation

#### `trace_header: []const u8`

HTTP header name used for propagating Trace IDs.
**Default**: `"X-Trace-ID"`

#### `span_header: []const u8`

HTTP header name used for propagating Span IDs.
**Default**: `"X-Span-ID"`

#### `parent_header: []const u8`

HTTP header name used for propagating Parent Span IDs.
**Default**: `"X-Parent-ID"`

#### `baggage_header: []const u8`

HTTP header name for Baggage/Correlation Context.
**Default**: `"Correlation-Context"`

#### `trace_sampling_rate: f64`

Sampling probablity for distributed traces (0.0 to 1.0).
**Default**: `1.0` (100% sampling)

### Callbacks

#### `on_trace_created: ?*const fn (trace_id: []const u8) void`

Optional callback invoked whenever `logger.setTraceContext` is called.
**Default**: `null`

#### `on_span_created: ?*const fn (span_id: []const u8, name: []const u8) void`

Optional callback invoked whenever `logger.startSpan` is called.
**Default**: `null`

## Usage

```zig
var config = logly.Config.default();
config.distributed = .{
    .enabled = true,
    .service_name = "payment-service",
    .environment = "production",
    .region = "us-east-1",
    .trace_header = "b3-traceid", // Support B3 propagation headers
    .span_header = "b3-spanid",
};
```
