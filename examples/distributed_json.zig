const std = @import("std");
const logly = @import("logly");
const Config = logly.Config;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var config = Config.default();
    config.json = true;
    config.distributed = .{
        .enabled = true,
        .service_name = "test-service",
        .environment = "staging",
        .region = "us-west-2",
        .datacenter = "dc1",
    };

    const logger = try logly.Logger.initWithConfig(allocator, config);
    defer logger.deinit();

    const request_logger = logger.withTrace("trace-123", "span-456");

    try request_logger.info("Test distributed log", @src());
}
