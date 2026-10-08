const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("Log Sampling Example\n\n", .{});

    // Create logger with probability sampling (50%)
    const logger = try logly.Logger.init(allocator);
    defer logger.deinit();

    // Create a sampler with 50% probability
    var sampler = logly.Sampler.init(allocator, .{ .probability = 0.5 });
    defer sampler.deinit();

    logger.setSampler(&sampler);

    std.debug.print("Probability Sampling (50%)\n", .{});
    std.debug.print("Logging 10 messages with 50% sampling:\n\n", .{});

    var i: u32 = 0;
    while (i < 10) : (i += 1) {
        try logger.infof("Message {d} of 10", .{i + 1}, @src());
    }
    try logger.flush();

    std.debug.print("\nRate Limiting\n", .{});

    // Create a new logger with rate limiting
    const rateLogger = try logly.Logger.init(allocator);
    defer rateLogger.deinit();

    // Rate limit to 5 messages per second
    var rateSampler = logly.Sampler.init(allocator, .{ .rateLimit = .{
        .maxRecords = 5,
        .windowMs = 1000,
    } });
    defer rateSampler.deinit();

    rateLogger.setSampler(&rateSampler);

    std.debug.print("Rate limited to 5 messages per second:\n\n", .{});

    i = 0;
    while (i < 10) : (i += 1) {
        try rateLogger.infof("Rate limited message {d}", .{i + 1}, @src());
    }
    try rateLogger.flush();

    std.debug.print("\nEvery N Sampling\n", .{});

    // Sample every 3rd message
    const everyLogger = try logly.Logger.init(allocator);
    defer everyLogger.deinit();

    var everySampler = logly.Sampler.init(allocator, .{ .everyN = 3 });
    defer everySampler.deinit();

    everyLogger.setSampler(&everySampler);

    std.debug.print("Sampling every 3rd message:\n\n", .{});

    i = 0;
    while (i < 9) : (i += 1) {
        try everyLogger.infof("Every-N message {d}", .{i + 1}, @src());
    }
    try everyLogger.flush();

    std.debug.print("\nUsing Sampler Presets\n", .{});

    // Use preset for no sampling (all messages pass)
    var noSampler = logly.SamplerPresets.none(allocator);
    defer noSampler.deinit();

    std.debug.print("No sampling preset - all messages logged\n", .{});

    // Use preset for 10% sampling
    var sample10 = logly.SamplerPresets.sample10Percent(allocator);
    defer sample10.deinit();

    std.debug.print("10%% sampling preset - ~10%% of messages logged\n", .{});

    // Use preset for rate limiting (100/second)
    var rateLimited = logly.SamplerPresets.limit100PerSecond(allocator);
    defer rateLimited.deinit();

    std.debug.print("Rate limited preset - max 100 messages/second\n", .{});

    std.debug.print("\nSampling Example Complete\n", .{});
}
