const std = @import("std");
const logly = @import("logly");
const Config = logly.Config;

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var config = Config.default();
    config.format = .json;
    config.distributed = .{
        .enabled = true,
        .serviceName = "test-service",
        .environment = "staging",
        .region = "us-west-2",
        .datacenter = "dc1",
    };

    const logger = try logly.Logger.initWithConfig(allocator, config);
    defer logger.deinit();

    const requestLogger = logger.withTrace("trace-123", "span-456");

    try requestLogger.info("Test distributed log", @src());
}
