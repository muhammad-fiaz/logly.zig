const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== Log Sampling Example ===\n\n", .{});

    // Create logger with probability sampling (50%)
    const logger = try logly.Logger.init(allocator);
    defer logger.deinit();

    // Create a sampler with 50% probability
    var sampler = logly.Sampler.init(allocator, .{ .probability = 0.5 });
    defer sampler.deinit();

    logger.setSampler(&sampler);

    std.debug.print("--- Probability Sampling (50%) ---\n", .{});
    std.debug.print("Logging 10 messages with 50% sampling:\n\n", .{});

    var i: u32 = 0;
    while (i < 10) : (i += 1) {
        try logger.infof("Message {d} of 10", .{i + 1});
    }

    std.debug.print("\n--- Rate Limiting ---\n", .{});

    // Create a new logger with rate limiting
    const rate_logger = try logly.Logger.init(allocator);
    defer rate_logger.deinit();

    // Rate limit to 5 messages per second
    var rate_sampler = logly.Sampler.init(allocator, .{ .rate_limit = .{
        .max_records = 5,
        .window_ms = 1000,
    } });
    defer rate_sampler.deinit();

    rate_logger.setSampler(&rate_sampler);

    std.debug.print("Rate limited to 5 messages per second:\n\n", .{});

    i = 0;
    while (i < 10) : (i += 1) {
        try rate_logger.infof("Rate limited message {d}", .{i + 1});
    }

    std.debug.print("\n--- Every N Sampling ---\n", .{});

    // Sample every 3rd message
    const every_logger = try logly.Logger.init(allocator);
    defer every_logger.deinit();

    var every_sampler = logly.Sampler.init(allocator, .{ .every_n = 3 });
    defer every_sampler.deinit();

    every_logger.setSampler(&every_sampler);

    std.debug.print("Sampling every 3rd message:\n\n", .{});

    i = 0;
    while (i < 9) : (i += 1) {
        try every_logger.infof("Every-N message {d}", .{i + 1});
    }

    std.debug.print("\n--- Using Sampler Presets ---\n", .{});

    // Use preset for no sampling (all messages pass)
    var no_sampler = logly.SamplerPresets.none(allocator);
    defer no_sampler.deinit();

    std.debug.print("No sampling preset - all messages logged\n", .{});

    // Use preset for 10% sampling
    var sample10 = logly.SamplerPresets.sample10Percent(allocator);
    defer sample10.deinit();

    std.debug.print("10%% sampling preset - ~10%% of messages logged\n", .{});

    // Use preset for rate limiting (100/second)
    var rate_limited = logly.SamplerPresets.limit100PerSecond(allocator);
    defer rate_limited.deinit();

    std.debug.print("Rate limited preset - max 100 messages/second\n", .{});

    std.debug.print("\n=== Sampling Example Complete ===\n", .{});
}
