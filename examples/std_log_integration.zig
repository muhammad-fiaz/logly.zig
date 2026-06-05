const std = @import("std");
const logly = @import("logly");

// Routes `std.log.*` calls into a logly Logger via the
// `logly.stdLogFn` bridge. Use this when you want to keep
// `pub const std_options = .{ .logFn = logly.stdLogFn }` in
// your root file and have every third-party `std.log` call
// funnelled through your configured logger.

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var config = logly.Config.default();
    config.auto_sink = false;
    config.check_for_updates = false;
    config.global_console_display = true;

    var logger = try logly.Logger.initWithConfig(allocator, config);
    defer logger.deinit();
    logly.crash.registerLogger(logger);
    defer logly.crash.unregisterLogger();

    // These calls flow through `logly.stdLogFn` even though
    // they look like plain `std.log.*` calls.
    std.log.info("user logged in id={d}", .{42});
    std.log.warn("high latency on /checkout: {d}ms", .{530});
    std.log.err("database connection failed", .{});

    const my_lib = std.log.scoped(.my_lib);
    my_lib.debug("cache miss for key {s}", .{"order:42"});
    my_lib.info("compiled in {d}ms", .{12});
}
