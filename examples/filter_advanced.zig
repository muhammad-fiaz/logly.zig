const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Enable ANSI colors on Windows (no-op on Linux/macOS)
    _ = logly.Terminal.enableAnsiColors();

    std.debug.print("\n", .{});
    std.debug.print("  Advanced Filtering Demo\n", .{});
    std.debug.print("\n\n", .{});

    const logger = try logly.Logger.init(allocator);
    defer logger.deinit();

    // 1. Setup an Advanced Filter with Composite Modes
    std.debug.print("1. Glob matching and Rate Limiting\n", .{});

    var advancedFilter = logly.Filter.init(allocator);
    defer advancedFilter.deinit();

    // Set logical mode to .any (logical OR: passes if any rule matches)
    advancedFilter.setMode(.any);

    // Glob pattern rule: allow any modules matching "auth.*"
    try advancedFilter.addGlobModule("auth.*", .allow);

    // Rate-limiting rule: limit logs to 5 messages per second
    try advancedFilter.addRateRule(5, .allow);

    logger.setFilter(&advancedFilter);

    // Simulated logs from different modules
    var rec1 = logly.Record.init(allocator, .info, "User login success");
    rec1.module = "auth.login";
    try logger.dispatchRecord(&rec1);
    rec1.deinit();

    var rec2 = logly.Record.init(allocator, .info, "Database query execution");
    rec2.module = "db.query";
    try logger.dispatchRecord(&rec2);
    rec2.deinit();

    // 2. Time-Window Filtering Rules
    std.debug.print("\n2. Time-Window Rules\n", .{});
    var timeFilter = logly.Filter.init(allocator);
    defer timeFilter.deinit();

    // Define a rule allowing logs only between 09:00 (9 AM) and 17:00 (5 PM)
    try timeFilter.addTimeWindowRule(9, 17, .allow);
    logger.setFilter(&timeFilter);

    var rec3 = logly.Record.init(allocator, .info, "Standard business hours activity");
    try logger.dispatchRecord(&rec3);
    rec3.deinit();

    // 3. Batch Filtering of Records
    std.debug.print("\n3. Batch Filtering API\n", .{});

    var batch: std.ArrayList(logly.Record) = .empty;
    defer {
        for (batch.items) |*r| r.deinit();
        batch.deinit(allocator);
    }

    try batch.append(allocator, logly.Record.init(allocator, .debug, "Low priority debug log"));
    try batch.append(allocator, logly.Record.init(allocator, .err, "Critical database corruption"));
    try batch.append(allocator, logly.Record.init(allocator, .info, "User logoff event"));

    var minLevelFilter = logly.Filter.init(allocator);
    defer minLevelFilter.deinit();
    try minLevelFilter.addMinLevel(.info);

    std.debug.print("Evaluating batch of {d} records...\n", .{batch.items.len});

    // Evaluate rules on whole batch
    const results = try allocator.alloc(logly.Filter.FilterResult, batch.items.len);
    defer allocator.free(results);

    const recordPtrs = try allocator.alloc(*const logly.Record, batch.items.len);
    defer allocator.free(recordPtrs);
    for (batch.items, 0..) |*r, i| {
        recordPtrs[i] = r;
    }

    minLevelFilter.filterBatch(recordPtrs, results);

    std.debug.print("Batch filtering completed.\n", .{});
    for (results, 0..) |res, i| {
        std.debug.print("  - Record {d} Level {s}: Passed: {s}, Reason: {s}\n", .{
            i,
            recordPtrs[i].level.asString(),
            if (res.allowed) "Yes" else "No",
            res.reason,
        });
    }

    std.debug.print("\nAdvanced Filtering Example completed successfully!\n", .{});
}
