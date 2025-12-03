const std = @import("std");
const logly = @import("logly");
const Logger = logly.Logger;
const Config = logly.Config;
const builtin = @import("builtin");

/// Benchmark results structure
const BenchmarkResult = struct {
    name: []const u8,
    iterations: u64,
    total_time_ns: u64,
    ops_per_sec: f64,
    avg_latency_ns: f64,
    min_latency_ns: u64,
    max_latency_ns: u64,
    notes: []const u8,
};

/// Number of warmup iterations
const WARMUP_ITERATIONS: u64 = 100;

/// Number of benchmark iterations
const BENCHMARK_ITERATIONS: u64 = 10_000;

/// Null device path for discarding output
const NULL_PATH = if (builtin.os.tag == .windows) "NUL" else "/dev/null";

/// Print benchmark results in a formatted table
fn printResults(results: []const BenchmarkResult) void {
    std.debug.print("\n", .{});
    std.debug.print("=" ** 120, .{});
    std.debug.print("\n", .{});
    std.debug.print("                                    LOGLY-ZIG BENCHMARK RESULTS\n", .{});
    std.debug.print("=" ** 120, .{});
    std.debug.print("\n\n", .{});

    std.debug.print("{s:<42} {s:>12} {s:>18} {s:>40}\n", .{ "Benchmark", "Ops/sec", "Avg Latency (ns)", "Notes" });
    std.debug.print("-" ** 120, .{});
    std.debug.print("\n", .{});

    for (results) |r| {
        std.debug.print("{s:<42} {d:>12.0} {d:>18.0} {s:>40}\n", .{
            r.name,
            r.ops_per_sec,
            r.avg_latency_ns,
            r.notes,
        });
    }

    std.debug.print("\n", .{});
    std.debug.print("=" ** 120, .{});
    std.debug.print("\n", .{});
}

/// Run a benchmark with the given function
fn runBenchmark(
    name: []const u8,
    comptime benchFn: anytype,
    context: anytype,
    notes: []const u8,
) BenchmarkResult {
    var min_latency: u64 = std.math.maxInt(u64);
    var max_latency: u64 = 0;

    // Warmup
    for (0..WARMUP_ITERATIONS) |_| {
        benchFn(context) catch {};
    }

    // Actual benchmark
    var timer = std.time.Timer.start() catch return BenchmarkResult{
        .name = name,
        .iterations = 0,
        .total_time_ns = 0,
        .ops_per_sec = 0,
        .avg_latency_ns = 0,
        .min_latency_ns = 0,
        .max_latency_ns = 0,
        .notes = notes,
    };

    for (0..BENCHMARK_ITERATIONS) |_| {
        const iter_start = timer.read();
        benchFn(context) catch {};
        const iter_end = timer.read();

        const latency = iter_end - iter_start;
        if (latency < min_latency) min_latency = latency;
        if (latency > max_latency) max_latency = latency;
    }

    const total_time_ns = timer.read();
    const ops_per_sec = @as(f64, @floatFromInt(BENCHMARK_ITERATIONS)) / (@as(f64, @floatFromInt(total_time_ns)) / 1_000_000_000.0);
    const avg_latency_ns = @as(f64, @floatFromInt(total_time_ns)) / @as(f64, @floatFromInt(BENCHMARK_ITERATIONS));

    return .{
        .name = name,
        .iterations = BENCHMARK_ITERATIONS,
        .total_time_ns = total_time_ns,
        .ops_per_sec = ops_per_sec,
        .avg_latency_ns = avg_latency_ns,
        .min_latency_ns = min_latency,
        .max_latency_ns = max_latency,
        .notes = notes,
    };
}

/// Benchmark context structure
const BenchContext = struct {
    logger: *Logger,
    allocator: std.mem.Allocator,
};

// Benchmark functions
fn benchSimpleLog(ctx: *const BenchContext) !void {
    try ctx.logger.info("Simple log message");
}

fn benchFormattedLog(ctx: *const BenchContext) !void {
    try ctx.logger.infof("User {s} logged in from {s}", .{ "john_doe", "192.168.1.1" });
}

fn benchDebugLog(ctx: *const BenchContext) !void {
    try ctx.logger.debug("Debug level message with some details");
}

fn benchWarningLog(ctx: *const BenchContext) !void {
    try ctx.logger.warning("Warning: resource usage at 85%");
}

fn benchErrorLog(ctx: *const BenchContext) !void {
    try ctx.logger.err("Error: connection timeout after 30s");
}

fn benchCriticalLog(ctx: *const BenchContext) !void {
    try ctx.logger.critical("Critical: system failure detected");
}

fn benchSuccessLog(ctx: *const BenchContext) !void {
    try ctx.logger.success("Operation completed successfully");
}

fn benchTraceLog(ctx: *const BenchContext) !void {
    try ctx.logger.trace("Detailed trace information for debugging");
}

fn benchFailLog(ctx: *const BenchContext) !void {
    try ctx.logger.fail("Operation failed unexpectedly");
}

fn benchCustomLevel(ctx: *const BenchContext) !void {
    try ctx.logger.custom("AUDIT", "User action logged for audit");
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n🚀 Starting Logly.Zig Benchmarks...\n", .{});
    std.debug.print("   Warmup iterations: {d}\n", .{WARMUP_ITERATIONS});
    std.debug.print("   Benchmark iterations: {d}\n\n", .{BENCHMARK_ITERATIONS});

    var results: std.ArrayList(BenchmarkResult) = .empty;
    defer results.deinit(allocator);

    // ============================================
    // BENCHMARK 1: Console Logging (No Color)
    // ============================================
    {
        std.debug.print("Running: Console logging (no color)...\n", .{});
        const logger = try Logger.init(allocator);
        defer logger.deinit();

        var config = Config.default();
        config.color = false;
        config.global_color_display = false;
        config.auto_sink = false;
        logger.configure(config);

        _ = try logger.addSink(.{ .path = NULL_PATH });

        const ctx = BenchContext{ .logger = logger, .allocator = allocator };
        try results.append(allocator, runBenchmark("Console (no color) - info", benchSimpleLog, &ctx, "Plain text, no ANSI codes"));
        try results.append(allocator, runBenchmark("Console (no color) - formatted", benchFormattedLog, &ctx, "Printf-style formatting"));
    }

    // ============================================
    // BENCHMARK 2: Console Logging (With Color)
    // ============================================
    {
        std.debug.print("Running: Console logging (with color)...\n", .{});
        const logger = try Logger.init(allocator);
        defer logger.deinit();

        var config = Config.default();
        config.color = true;
        config.global_color_display = true;
        config.auto_sink = false;
        logger.configure(config);

        _ = try logger.addSink(.{ .path = NULL_PATH, .color = true });

        const ctx = BenchContext{ .logger = logger, .allocator = allocator };
        try results.append(allocator, runBenchmark("Console (with color) - info", benchSimpleLog, &ctx, "ANSI color wrapping"));
        try results.append(allocator, runBenchmark("Console (with color) - formatted", benchFormattedLog, &ctx, "Colored + formatting"));
    }

    // ============================================
    // BENCHMARK 3: JSON Logging (No Color)
    // ============================================
    {
        std.debug.print("Running: JSON logging (no color)...\n", .{});
        const logger = try Logger.init(allocator);
        defer logger.deinit();

        var config = Config.default();
        config.json = true;
        config.color = false;
        config.auto_sink = false;
        logger.configure(config);

        _ = try logger.addSink(.{ .path = NULL_PATH, .json = true, .color = false });

        const ctx = BenchContext{ .logger = logger, .allocator = allocator };
        try results.append(allocator, runBenchmark("JSON (no color) - info", benchSimpleLog, &ctx, "Compact JSON output"));
        try results.append(allocator, runBenchmark("JSON (no color) - formatted", benchFormattedLog, &ctx, "JSON with formatting"));
    }

    // ============================================
    // BENCHMARK 4: JSON Logging (With Color)
    // ============================================
    {
        std.debug.print("Running: JSON logging (with color)...\n", .{});
        const logger = try Logger.init(allocator);
        defer logger.deinit();

        var config = Config.default();
        config.json = true;
        config.color = true;
        config.global_color_display = true;
        config.auto_sink = false;
        logger.configure(config);

        _ = try logger.addSink(.{ .path = NULL_PATH, .json = true, .color = true });

        const ctx = BenchContext{ .logger = logger, .allocator = allocator };
        try results.append(allocator, runBenchmark("JSON (with color) - info", benchSimpleLog, &ctx, "JSON with ANSI colors"));
        try results.append(allocator, runBenchmark("JSON (with color) - error", benchErrorLog, &ctx, "JSON colored error"));
    }

    // ============================================
    // BENCHMARK 5: Pretty JSON Logging
    // ============================================
    {
        std.debug.print("Running: Pretty JSON logging...\n", .{});
        const logger = try Logger.init(allocator);
        defer logger.deinit();

        var config = Config.default();
        config.json = true;
        config.pretty_json = true;
        config.auto_sink = false;
        logger.configure(config);

        _ = try logger.addSink(.{ .path = NULL_PATH, .json = true, .pretty_json = true });

        const ctx = BenchContext{ .logger = logger, .allocator = allocator };
        try results.append(allocator, runBenchmark("Pretty JSON - info", benchSimpleLog, &ctx, "Indented JSON output"));
    }

    // ============================================
    // BENCHMARK 6: Custom Format
    // ============================================
    {
        std.debug.print("Running: Custom format logging...\n", .{});
        const logger = try Logger.init(allocator);
        defer logger.deinit();

        var config = Config.default();
        config.log_format = "{time} | {level} | {message}";
        config.auto_sink = false;
        logger.configure(config);

        _ = try logger.addSink(.{ .path = NULL_PATH });

        const ctx = BenchContext{ .logger = logger, .allocator = allocator };
        try results.append(allocator, runBenchmark("Custom format - info", benchSimpleLog, &ctx, "{time} | {level} | {message}"));
    }

    // ============================================
    // BENCHMARK 7: All Log Levels (No Color)
    // ============================================
    {
        std.debug.print("Running: All 8 log levels (no color)...\n", .{});
        const logger = try Logger.init(allocator);
        defer logger.deinit();

        var config = Config.default();
        config.level = .trace;
        config.color = false;
        config.auto_sink = false;
        logger.configure(config);

        _ = try logger.addSink(.{ .path = NULL_PATH });

        const ctx = BenchContext{ .logger = logger, .allocator = allocator };
        try results.append(allocator, runBenchmark("Level: TRACE", benchTraceLog, &ctx, "Trace level messages"));
        try results.append(allocator, runBenchmark("Level: DEBUG", benchDebugLog, &ctx, "Debug level messages"));
        try results.append(allocator, runBenchmark("Level: INFO", benchSimpleLog, &ctx, "Info level messages"));
        try results.append(allocator, runBenchmark("Level: SUCCESS", benchSuccessLog, &ctx, "Success level messages"));
        try results.append(allocator, runBenchmark("Level: WARNING", benchWarningLog, &ctx, "Warning level messages"));
        try results.append(allocator, runBenchmark("Level: ERROR", benchErrorLog, &ctx, "Error level messages"));
        try results.append(allocator, runBenchmark("Level: FAIL", benchFailLog, &ctx, "Fail level messages"));
        try results.append(allocator, runBenchmark("Level: CRITICAL", benchCriticalLog, &ctx, "Critical level messages"));
    }

    // ============================================
    // BENCHMARK 8: All Log Levels (With Color)
    // ============================================
    {
        std.debug.print("Running: All 8 log levels (with color)...\n", .{});
        const logger = try Logger.init(allocator);
        defer logger.deinit();

        var config = Config.default();
        config.level = .trace;
        config.color = true;
        config.global_color_display = true;
        config.auto_sink = false;
        logger.configure(config);

        _ = try logger.addSink(.{ .path = NULL_PATH, .color = true });

        const ctx = BenchContext{ .logger = logger, .allocator = allocator };
        try results.append(allocator, runBenchmark("Level (color): TRACE", benchTraceLog, &ctx, "Colored trace messages"));
        try results.append(allocator, runBenchmark("Level (color): DEBUG", benchDebugLog, &ctx, "Colored debug messages"));
        try results.append(allocator, runBenchmark("Level (color): INFO", benchSimpleLog, &ctx, "Colored info messages"));
        try results.append(allocator, runBenchmark("Level (color): SUCCESS", benchSuccessLog, &ctx, "Colored success messages"));
        try results.append(allocator, runBenchmark("Level (color): WARNING", benchWarningLog, &ctx, "Colored warning messages"));
        try results.append(allocator, runBenchmark("Level (color): ERROR", benchErrorLog, &ctx, "Colored error messages"));
        try results.append(allocator, runBenchmark("Level (color): FAIL", benchFailLog, &ctx, "Colored fail messages"));
        try results.append(allocator, runBenchmark("Level (color): CRITICAL", benchCriticalLog, &ctx, "Colored critical messages"));
    }

    // ============================================
    // BENCHMARK 9: Custom Log Levels (No Color)
    // ============================================
    {
        std.debug.print("Running: Custom log levels...\n", .{});
        const logger = try Logger.init(allocator);
        defer logger.deinit();

        var config = Config.default();
        config.level = .trace;
        config.color = false;
        config.auto_sink = false;
        logger.configure(config);

        try logger.addCustomLevel("AUDIT", 35, "96");

        _ = try logger.addSink(.{ .path = NULL_PATH });

        const ctx = BenchContext{ .logger = logger, .allocator = allocator };
        try results.append(allocator, runBenchmark("Custom Level: AUDIT", benchCustomLevel, &ctx, "User-defined log level"));
    }

    // ============================================
    // BENCHMARK 10: Custom Log Levels (With Color)
    // ============================================
    {
        std.debug.print("Running: Custom log levels (with color)...\n", .{});
        const logger = try Logger.init(allocator);
        defer logger.deinit();

        var config = Config.default();
        config.level = .trace;
        config.color = true;
        config.global_color_display = true;
        config.auto_sink = false;
        logger.configure(config);

        try logger.addCustomLevel("AUDIT", 35, "96");

        _ = try logger.addSink(.{ .path = NULL_PATH, .color = true });

        const ctx = BenchContext{ .logger = logger, .allocator = allocator };
        try results.append(allocator, runBenchmark("Custom Level (color): AUDIT", benchCustomLevel, &ctx, "Colored custom level"));
    }

    // ============================================
    // BENCHMARK 11: File Output (No Color)
    // ============================================
    {
        std.debug.print("Running: File output (no color)...\n", .{});
        const logger = try Logger.init(allocator);
        defer logger.deinit();

        var config = Config.default();
        config.color = false;
        config.global_color_display = false;
        config.auto_sink = false;
        logger.configure(config);

        _ = try logger.addSink(.{ .path = NULL_PATH, .color = false });

        const ctx = BenchContext{ .logger = logger, .allocator = allocator };
        try results.append(allocator, runBenchmark("File (no color) - info", benchSimpleLog, &ctx, "Plain file output"));
        try results.append(allocator, runBenchmark("File (no color) - error", benchErrorLog, &ctx, "Plain file error output"));
    }

    // ============================================
    // BENCHMARK 12: File Output (With Color)
    // ============================================
    {
        std.debug.print("Running: File output (with color)...\n", .{});
        const logger = try Logger.init(allocator);
        defer logger.deinit();

        var config = Config.default();
        config.color = true;
        config.global_color_display = true;
        config.auto_sink = false;
        logger.configure(config);

        _ = try logger.addSink(.{ .path = NULL_PATH, .color = true });

        const ctx = BenchContext{ .logger = logger, .allocator = allocator };
        try results.append(allocator, runBenchmark("File (with color) - info", benchSimpleLog, &ctx, "File with ANSI codes"));
        try results.append(allocator, runBenchmark("File (with color) - error", benchErrorLog, &ctx, "File colored error"));
    }

    // ============================================
    // BENCHMARK 13: With Full Metadata
    // ============================================
    {
        std.debug.print("Running: With full metadata...\n", .{});
        const logger = try Logger.init(allocator);
        defer logger.deinit();

        var config = Config.default();
        config.show_time = true;
        config.show_module = true;
        config.show_function = true;
        config.show_filename = true;
        config.show_lineno = true;
        config.color = false;
        config.auto_sink = false;
        logger.configure(config);

        _ = try logger.addSink(.{ .path = NULL_PATH });

        const ctx = BenchContext{ .logger = logger, .allocator = allocator };
        try results.append(allocator, runBenchmark("Full metadata - info", benchSimpleLog, &ctx, "Time + module + file + line"));
    }

    // ============================================
    // BENCHMARK 14: Minimal Config
    // ============================================
    {
        std.debug.print("Running: Minimal config...\n", .{});
        const logger = try Logger.init(allocator);
        defer logger.deinit();

        var config = Config.default();
        config.show_time = false;
        config.show_module = false;
        config.color = false;
        config.auto_sink = false;
        logger.configure(config);

        _ = try logger.addSink(.{ .path = NULL_PATH });

        const ctx = BenchContext{ .logger = logger, .allocator = allocator };
        try results.append(allocator, runBenchmark("Minimal config - info", benchSimpleLog, &ctx, "No timestamp or module"));
    }

    // ============================================
    // BENCHMARK 15: Production Config
    // ============================================
    {
        std.debug.print("Running: Production config...\n", .{});
        const logger = try Logger.init(allocator);
        defer logger.deinit();

        var config = Config.production();
        config.auto_sink = false;
        logger.configure(config);

        _ = try logger.addSink(.{ .path = NULL_PATH, .json = true });

        const ctx = BenchContext{ .logger = logger, .allocator = allocator };
        try results.append(allocator, runBenchmark("Production config - info", benchSimpleLog, &ctx, "JSON with optimizations"));
    }

    // ============================================
    // BENCHMARK 16: Multiple Sinks
    // ============================================
    {
        std.debug.print("Running: Multiple sinks...\n", .{});
        const logger = try Logger.init(allocator);
        defer logger.deinit();

        var config = Config.default();
        config.color = false;
        config.auto_sink = false;
        logger.configure(config);

        _ = try logger.addSink(.{ .path = NULL_PATH });
        _ = try logger.addSink(.{ .path = NULL_PATH, .json = true });
        _ = try logger.addSink(.{ .path = NULL_PATH, .json = true, .pretty_json = true });

        const ctx = BenchContext{ .logger = logger, .allocator = allocator };
        try results.append(allocator, runBenchmark("Multiple sinks (3) - info", benchSimpleLog, &ctx, "Console + JSON + Pretty"));
    }

    // Print all results
    printResults(results.items);

    // Print summary
    std.debug.print("\n📊 SUMMARY\n", .{});
    std.debug.print("-" ** 50, .{});
    std.debug.print("\n", .{});

    var total_ops: f64 = 0;
    var count: usize = 0;
    for (results.items) |r| {
        total_ops += r.ops_per_sec;
        count += 1;
    }

    if (count > 0) {
        const avg_ops = total_ops / @as(f64, @floatFromInt(count));
        std.debug.print("Average throughput: {d:.0} ops/sec\n", .{avg_ops});
    }

    std.debug.print("\n✅ Benchmarks completed!\n\n", .{});
}
