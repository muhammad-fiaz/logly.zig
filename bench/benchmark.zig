const std = @import("std");
const logly = @import("logly");
const Logger = logly.Logger;
const Config = logly.Config;
const ThreadPool = logly.ThreadPool;
const Constants = logly.Constants;
const builtin = @import("builtin");

/// Benchmark results structure
const BenchmarkResult = struct {
    name: []const u8,
    iterations: u64,
    totalTimeNs: u64,
    opsPerSec: f64,
    avgLatencyNs: f64,
    minLatencyNs: u64,
    maxLatencyNs: u64,
    notes: []const u8,
    category: []const u8,

    // Static categories for grouping
    const categories = [_][]const u8{
        "Basic Logging",
        "JSON Logging",
        "Log Levels",
        "Custom Features",
        "Configuration Presets",
        "Allocator Comparison",
        "Enterprise Features",
        "Sampling & Rate Limiting",
        "Filtering",
        "Rules Engine",
        "Redaction",
        "Metrics",
        "Rotation",
        "Multi-Threading",
        "Performance Comparison",
    };
};

/// Number of warmup iterations
const WARMUP_ITERATIONS: u64 = 100;

/// Number of benchmark iterations
const BENCHMARK_ITERATIONS: u64 = 10_000;

/// Number of iterations for multi-thread benchmarks
const MT_BENCHMARK_ITERATIONS: u64 = 5_000;

/// Null device path for discarding output
const NULL_PATH = if (builtin.os.tag == .windows) "NUL" else "/dev/null";

/// Print benchmark results in a formatted table by category (Console only)
fn printResults(results: []const BenchmarkResult) void {
    std.debug.print("\n", .{});
    std.debug.print("----------------------------------------------------------------------------------------------------", .{});
    std.debug.print("\n", .{});
    std.debug.print("                                 LOGLY.ZIG BENCHMARK RESULTS\n", .{});
    std.debug.print("----------------------------------------------------------------------------------------------------", .{});
    std.debug.print("\n", .{});

    for (BenchmarkResult.categories) |cat| {
        var hasCategory = false;
        for (results) |r| {
            if (std.mem.eql(u8, r.category, cat)) {
                hasCategory = true;
                break;
            }
        }
        if (!hasCategory) continue;

        std.debug.print("\n[{s}]\n", .{cat});
        std.debug.print("----------------------------------------------------------------------------------------------------", .{});
        std.debug.print("\n", .{});
        std.debug.print("{s:<40} {s:>25} {s:>25} {s:>10}\n", .{ "Benchmark", "Ops/sec", "Avg Latency (ns)", "Notes" });
        std.debug.print("----------------------------------------------------------------------------------------------------", .{});
        std.debug.print("\n", .{});

        for (results) |r| {
            if (std.mem.eql(u8, r.category, cat)) {
                std.debug.print("{s:<50} {d:>25.0} {d:>30.0} {s:>20}\n", .{
                    r.name,
                    r.opsPerSec,
                    r.avgLatencyNs,
                    r.notes,
                });
            }
        }
    }

    std.debug.print("\n", .{});
    std.debug.print("==================================================================================================================================", .{});
    std.debug.print("\n", .{});
}

/// Run a benchmark with the given function
fn runBenchmark(
    name: []const u8,
    comptime benchFn: anytype,
    context: anytype,
    notes: []const u8,
    category: []const u8,
) BenchmarkResult {
    const io = logly.Utils.io();
    var minLatency: u64 = std.math.maxInt(u64);
    var maxLatency: u64 = 0;

    // Warmup
    for (0..WARMUP_ITERATIONS) |_| {
        benchFn(context) catch {};
    }

    const timerStart = std.Io.Clock.awake.now(io);
    for (0..BENCHMARK_ITERATIONS) |_| {
        const iterStart = std.Io.Clock.awake.now(io);
        benchFn(context) catch {};
        const iterEnd = std.Io.Clock.awake.now(io);

        const latency = @as(u64, @intCast(iterEnd.nanoseconds - iterStart.nanoseconds));
        if (latency < minLatency) minLatency = latency;
        if (latency > maxLatency) maxLatency = latency;
    }

    const totalTimeNs = @as(u64, @intCast(std.Io.Clock.awake.now(io).nanoseconds - timerStart.nanoseconds));
    const opsPerSec = @as(f64, @floatFromInt(BENCHMARK_ITERATIONS)) / (@as(f64, @floatFromInt(totalTimeNs)) / 1_000_000_000.0);
    const avgLatencyNs = @as(f64, @floatFromInt(totalTimeNs)) / @as(f64, @floatFromInt(BENCHMARK_ITERATIONS));

    return .{
        .name = name,
        .iterations = BENCHMARK_ITERATIONS,
        .totalTimeNs = totalTimeNs,
        .opsPerSec = opsPerSec,
        .avgLatencyNs = avgLatencyNs,
        .minLatencyNs = minLatency,
        .maxLatencyNs = maxLatency,
        .notes = notes,
        .category = category,
    };
}

/// Benchmark context structure
const BenchContext = struct {
    logger: *Logger,
    allocator: std.mem.Allocator,
};

/// Returns a silent config for benchmarking (no console output).
/// File storage stays enabled so NUL file sinks still format and write,
/// measuring real formatting work without console pollution.
/// Use with Logger.initWithConfig() to prevent log pollution.
fn benchmarkConfig() Config {
    var config = Config.default();
    config.autoSink = false;
    config.autoFlush = false;
    config.globalConsoleDisplay = false;
    config.globalFileStorage = true;
    return config;
}

// Basic Benchmark Functions
fn benchSimpleLog(ctx: *const BenchContext) !void {
    try ctx.logger.info("Simple log message", null);
}

// A record below the configured minimum level. The cost of *rejecting* a log
// call is what most applications actually feel, so it is measured separately
// from accepted calls.
fn benchDisabledLog(ctx: *const BenchContext) !void {
    try ctx.logger.trace("Trace below the configured minimum level", null);
}

fn benchFormattedLog(ctx: *const BenchContext) !void {
    try ctx.logger.infof("User {s} logged in from {s}", .{ "john_doe", "192.168.1.1" }, null);
}

fn benchDebugLog(ctx: *const BenchContext) !void {
    try ctx.logger.debug("Debug level message with some details", null);
}

fn benchWarningLog(ctx: *const BenchContext) !void {
    try ctx.logger.warning("Warning: resource usage at 85%", null);
}

fn benchErrorLog(ctx: *const BenchContext) !void {
    try ctx.logger.err("Error: connection timeout after 30s", null);
}

fn benchCriticalLog(ctx: *const BenchContext) !void {
    try ctx.logger.critical("Critical: system failure detected", null);
}

fn benchSuccessLog(ctx: *const BenchContext) !void {
    try ctx.logger.success("Operation completed successfully", null);
}

fn benchTraceLog(ctx: *const BenchContext) !void {
    try ctx.logger.trace("Detailed trace information for debugging", null);
}

fn benchFailLog(ctx: *const BenchContext) !void {
    try ctx.logger.fail("Operation failed unexpectedly", null);
}

fn benchCustomLevel(ctx: *const BenchContext) !void {
    try ctx.logger.custom("AUDIT", "User action logged for audit", null);
}

//
// Filtering Benchmark Functions
//
fn benchFilterAllowed(ctx: *const BenchContext) !void {
    try ctx.logger.info("This message passes the filter", null);
}

fn benchFilterRejected(ctx: *const BenchContext) !void {
    try ctx.logger.debug("This message is rejected by filter", null);
}

fn benchFilterComplex(ctx: *const BenchContext) !void {
    try ctx.logger.info("Checking complex filter rules", null);
}

//
// Multi-thread worker function
//
fn multiThreadWorker(ctx: *const BenchContext) void {
    for (0..MT_BENCHMARK_ITERATIONS) |_| {
        ctx.logger.info("Multi-threaded log message", null) catch {};
    }
}

fn multiThreadWorkerJson(ctx: *const BenchContext) void {
    for (0..MT_BENCHMARK_ITERATIONS) |_| {
        ctx.logger.info("JSON multi-threaded message", null) catch {};
    }
}

fn multiThreadWorkerFormatted(ctx: *const BenchContext) void {
    for (0..MT_BENCHMARK_ITERATIONS) |_| {
        ctx.logger.infof("Thread message: iteration {d}", .{@as(u32, 42)}, null) catch {};
    }
}

/// Run multi-threaded benchmark
fn runMultiThreadBenchmark(
    name: []const u8,
    logger: *Logger,
    threadCount: usize,
    notes: []const u8,
    category: []const u8,
    allocator: std.mem.Allocator,
    comptime workerFn: fn (*const BenchContext) void,
) BenchmarkResult {
    const io = logly.Utils.io();
    const ctx = BenchContext{ .logger = logger, .allocator = allocator };

    // Warmup
    for (0..WARMUP_ITERATIONS) |_| {
        logger.info("Warmup message", null) catch {};
    }

    const timerStart = std.Io.Clock.awake.now(io);

    // Spawn threads
    var threads: [16]?std.Thread = @splat(null);
    const actualThreads = @min(threadCount, 16);

    for (0..actualThreads) |i| {
        threads[i] = std.Thread.spawn(.{}, workerFn, .{&ctx}) catch null;
    }

    // Wait for all threads
    for (0..actualThreads) |i| {
        if (threads[i]) |t| {
            t.join();
        }
    }

    const totalTimeNs = @as(u64, @intCast(std.Io.Clock.awake.now(io).nanoseconds - timerStart.nanoseconds));
    const totalOps = MT_BENCHMARK_ITERATIONS * actualThreads;
    const opsPerSec = @as(f64, @floatFromInt(totalOps)) / (@as(f64, @floatFromInt(totalTimeNs)) / 1_000_000_000.0);
    const avgLatencyNs = @as(f64, @floatFromInt(totalTimeNs)) / @as(f64, @floatFromInt(totalOps));

    return .{
        .name = name,
        .iterations = totalOps,
        .totalTimeNs = totalTimeNs,
        .opsPerSec = opsPerSec,
        .avgLatencyNs = avgLatencyNs,
        .minLatencyNs = 0,
        .maxLatencyNs = 0,
        .notes = notes,
        .category = category,
    };
}

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var results: std.ArrayList(BenchmarkResult) = .empty;
    defer results.deinit(allocator);

    //
    // Basic Logging
    //
    {
        std.debug.print("Running: Basic logging benchmarks...\n", .{});
        var config = benchmarkConfig();
        config.color = false;
        const logger = try Logger.initWithConfig(allocator, config);
        defer logger.deinit();

        _ = try logger.addSink(.{ .path = NULL_PATH });

        const ctx = BenchContext{ .logger = logger, .allocator = allocator };
        try results.append(allocator, runBenchmark("Simple log (no color)", benchSimpleLog, &ctx, "Plain text output", "Basic Logging"));
        try results.append(allocator, runBenchmark("Formatted log (no color)", benchFormattedLog, &ctx, "Printf-style formatting", "Basic Logging"));
    }

    // Rejection cost: level gate runs before any clock read, lock, or format.
    {
        var config = benchmarkConfig();
        config.level = .info;
        const logger = try logly.Logger.initWithConfig(allocator, config);
        defer logger.deinit();
        _ = try logger.addSink(.{ .path = NULL_PATH });

        const ctx = BenchContext{ .logger = logger, .allocator = allocator };
        try results.append(allocator, runBenchmark("Disabled log call (TRACE vs INFO min)", benchDisabledLog, &ctx, "Rejected before formatting", "Basic Logging"));
    }

    {
        var config = benchmarkConfig();
        config.color = true;
        const logger = try Logger.initWithConfig(allocator, config);
        defer logger.deinit();

        _ = try logger.addSink(.{ .path = NULL_PATH, .color = true });

        const ctx = BenchContext{ .logger = logger, .allocator = allocator };
        try results.append(allocator, runBenchmark("Simple log (with color)", benchSimpleLog, &ctx, "ANSI color codes", "Basic Logging"));
        try results.append(allocator, runBenchmark("Formatted log (with color)", benchFormattedLog, &ctx, "Colored + formatting", "Basic Logging"));
    }

    {
        // Color modes: horizontal vs vertical vs none.
        var hConfig = benchmarkConfig();
        hConfig.color = true;
        hConfig.colorMode = .horizontal;
        const hLogger = try Logger.initWithConfig(allocator, hConfig);
        defer hLogger.deinit();
        _ = try hLogger.addSink(.{ .path = NULL_PATH, .color = true });
        const hCtx = BenchContext{ .logger = hLogger, .allocator = allocator };
        try results.append(allocator, runBenchmark("Horizontal color", benchSimpleLog, &hCtx, "Whole-line level color", "Basic Logging"));

        var vConfig = benchmarkConfig();
        vConfig.color = true;
        vConfig.colorMode = .vertical;
        vConfig.columnColors.timestamp = logly.Color.Tint.color.ansi4.blue;
        vConfig.columnColors.message = logly.Color.Tint.color.ansi4.yellow;
        const vLogger = try Logger.initWithConfig(allocator, vConfig);
        defer vLogger.deinit();
        _ = try vLogger.addSink(.{ .path = NULL_PATH, .color = true });
        const vCtx = BenchContext{ .logger = vLogger, .allocator = allocator };
        try results.append(allocator, runBenchmark("Vertical color", benchSimpleLog, &vCtx, "Per-column colors", "Basic Logging"));

        var nConfig = benchmarkConfig();
        nConfig.colorMode = .none;
        const nLogger = try Logger.initWithConfig(allocator, nConfig);
        defer nLogger.deinit();
        _ = try nLogger.addSink(.{ .path = NULL_PATH });
        const nCtx = BenchContext{ .logger = nLogger, .allocator = allocator };
        try results.append(allocator, runBenchmark("No color mode", benchSimpleLog, &nCtx, "colorMode.none", "Basic Logging"));
    }

    //
    // JSON Logging
    //
    {
        std.debug.print("Running: JSON logging benchmarks...\n", .{});
        var config = benchmarkConfig();
        config.format = .json;
        config.color = false;
        const logger = try Logger.initWithConfig(allocator, config);
        defer logger.deinit();

        _ = try logger.addSink(.{ .path = NULL_PATH, .format = .json, .color = false });

        const ctx = BenchContext{ .logger = logger, .allocator = allocator };
        try results.append(allocator, runBenchmark("JSON compact", benchSimpleLog, &ctx, "Compact JSON output", "JSON Logging"));
        try results.append(allocator, runBenchmark("JSON formatted", benchFormattedLog, &ctx, "JSON with formatting", "JSON Logging"));
    }

    {
        const logger = try Logger.init(allocator);
        defer logger.deinit();

        var config = Config.default();
        config.format = .json;
        config.prettyJson = true;
        config.autoSink = false;
        config.autoFlush = false;
        logger.configure(config);

        _ = try logger.addSink(.{ .path = NULL_PATH, .format = .json, .prettyJson = true });

        const ctx = BenchContext{ .logger = logger, .allocator = allocator };
        try results.append(allocator, runBenchmark("JSON pretty", benchSimpleLog, &ctx, "Indented JSON output", "JSON Logging"));
    }

    {
        const logger = try Logger.init(allocator);
        defer logger.deinit();

        var config = Config.default();
        config.format = .json;
        config.color = true;
        config.autoSink = false;
        config.autoFlush = false;
        logger.configure(config);

        _ = try logger.addSink(.{ .path = NULL_PATH, .format = .json, .color = true });

        const ctx = BenchContext{ .logger = logger, .allocator = allocator };
        try results.append(allocator, runBenchmark("JSON with color", benchSimpleLog, &ctx, "JSON with ANSI colors", "JSON Logging"));
    }

    //
    // Log Levels
    //
    {
        std.debug.print("Running: Log levels benchmarks...\n", .{});
        const logger = try Logger.init(allocator);
        defer logger.deinit();

        var config = Config.default();
        config.level = .trace;
        config.color = false;
        config.autoSink = false;
        config.autoFlush = false;
        logger.configure(config);

        _ = try logger.addSink(.{ .path = NULL_PATH });

        const ctx = BenchContext{ .logger = logger, .allocator = allocator };
        try results.append(allocator, runBenchmark("TRACE level", benchTraceLog, &ctx, "Lowest priority level", "Log Levels"));
        try results.append(allocator, runBenchmark("DEBUG level", benchDebugLog, &ctx, "Debug information", "Log Levels"));
        try results.append(allocator, runBenchmark("INFO level", benchSimpleLog, &ctx, "General information", "Log Levels"));
        try results.append(allocator, runBenchmark("SUCCESS level", benchSuccessLog, &ctx, "Success messages", "Log Levels"));
        try results.append(allocator, runBenchmark("WARNING level", benchWarningLog, &ctx, "Warning messages", "Log Levels"));
        try results.append(allocator, runBenchmark("ERROR level", benchErrorLog, &ctx, "Error messages", "Log Levels"));
        try results.append(allocator, runBenchmark("FAIL level", benchFailLog, &ctx, "Failure messages", "Log Levels"));
        try results.append(allocator, runBenchmark("CRITICAL level", benchCriticalLog, &ctx, "Critical messages", "Log Levels"));
    }

    //
    // Custom Features
    //
    {
        std.debug.print("Running: Custom features benchmarks...\n", .{});
        const logger = try Logger.init(allocator);
        defer logger.deinit();

        var config = Config.default();
        config.level = .trace;
        config.color = false;
        config.autoSink = false;
        config.autoFlush = false;
        logger.configure(config);

        try logger.addCustomLevel("AUDIT", 35, logly.Color.parse("96").?);

        _ = try logger.addSink(.{ .path = NULL_PATH });

        const ctx = BenchContext{ .logger = logger, .allocator = allocator };
        try results.append(allocator, runBenchmark("Custom level (AUDIT)", benchCustomLevel, &ctx, "User-defined log level", "Custom Features"));
    }

    {
        const logger = try Logger.init(allocator);
        defer logger.deinit();

        var config = Config.default();
        config.logFormat = "{time} | {level} | {message}";
        config.autoSink = false;
        config.autoFlush = false;
        logger.configure(config);

        _ = try logger.addSink(.{ .path = NULL_PATH });

        const ctx = BenchContext{ .logger = logger, .allocator = allocator };
        try results.append(allocator, runBenchmark("Custom log format", benchSimpleLog, &ctx, "{time} | {level} | {message}", "Custom Features"));
    }

    {
        const logger = try Logger.init(allocator);
        defer logger.deinit();

        var config = Config.default();
        config.timeFormat = "DD/MM/YYYY HH:mm:ss";
        config.autoSink = false;
        config.autoFlush = false;
        logger.configure(config);

        _ = try logger.addSink(.{ .path = NULL_PATH });

        const ctx = BenchContext{ .logger = logger, .allocator = allocator };
        try results.append(allocator, runBenchmark("Custom time format", benchSimpleLog, &ctx, "DD/MM/YYYY HH:mm:ss", "Custom Features"));
    }

    {
        const logger = try Logger.init(allocator);
        defer logger.deinit();

        var config = Config.default();
        config.timeFormat = "ISO8601";
        config.autoSink = false;
        config.autoFlush = false;
        logger.configure(config);

        _ = try logger.addSink(.{ .path = NULL_PATH });

        const ctx = BenchContext{ .logger = logger, .allocator = allocator };
        try results.append(allocator, runBenchmark("ISO8601 time format", benchSimpleLog, &ctx, "ISO 8601 standard format", "Custom Features"));
    }

    {
        const logger = try Logger.init(allocator);
        defer logger.deinit();

        var config = Config.default();
        config.timeFormat = "unix_ms";
        config.autoSink = false;
        config.autoFlush = false;
        logger.configure(config);

        _ = try logger.addSink(.{ .path = NULL_PATH });

        const ctx = BenchContext{ .logger = logger, .allocator = allocator };
        try results.append(allocator, runBenchmark("Unix timestamp (ms)", benchSimpleLog, &ctx, "Millisecond Unix timestamp", "Custom Features"));
    }

    //
    // Configuration Presets
    //
    {
        std.debug.print("Running: Configuration presets benchmarks...\n", .{});

        // Full metadata
        const logger = try Logger.init(allocator);
        defer logger.deinit();

        var config = Config.default();
        config.showTime = true;
        config.showModule = true;
        config.showFunction = true;
        config.showFilename = true;
        config.showLineno = true;
        config.color = false;
        config.autoSink = false;
        config.autoFlush = false;
        logger.configure(config);

        _ = try logger.addSink(.{ .path = NULL_PATH });

        const ctx = BenchContext{ .logger = logger, .allocator = allocator };
        try results.append(allocator, runBenchmark("Full metadata config", benchSimpleLog, &ctx, "Time + module + file + line", "Configuration Presets"));
    }

    {
        const logger = try Logger.init(allocator);
        defer logger.deinit();

        var config = Config.default();
        config.showTime = false;
        config.showModule = false;
        config.color = false;
        config.autoSink = false;
        config.autoFlush = false;
        logger.configure(config);

        _ = try logger.addSink(.{ .path = NULL_PATH });

        const ctx = BenchContext{ .logger = logger, .allocator = allocator };
        try results.append(allocator, runBenchmark("Minimal config", benchSimpleLog, &ctx, "No timestamp or module", "Configuration Presets"));
    }

    {
        const logger = try Logger.init(allocator);
        defer logger.deinit();

        var config = Config.production();
        config.autoSink = false;
        config.autoFlush = false;
        logger.configure(config);

        _ = try logger.addSink(.{ .path = NULL_PATH, .format = .json });

        const ctx = BenchContext{ .logger = logger, .allocator = allocator };
        try results.append(allocator, runBenchmark("Production preset", benchSimpleLog, &ctx, "JSON + sampling + metrics", "Configuration Presets"));
    }

    {
        const logger = try Logger.init(allocator);
        defer logger.deinit();

        var config = Config.development();
        config.autoSink = false;
        config.autoFlush = false;
        logger.configure(config);

        _ = try logger.addSink(.{ .path = NULL_PATH });

        const ctx = BenchContext{ .logger = logger, .allocator = allocator };
        try results.append(allocator, runBenchmark("Development preset", benchSimpleLog, &ctx, "Debug + source location", "Configuration Presets"));
    }

    {
        const logger = try Logger.init(allocator);
        defer logger.deinit();

        var config = Config.highThroughput();
        config.autoSink = false;
        config.autoFlush = false;
        logger.configure(config);

        _ = try logger.addSink(.{ .path = NULL_PATH });

        const ctx = BenchContext{ .logger = logger, .allocator = allocator };
        try results.append(allocator, runBenchmark("High throughput preset", benchSimpleLog, &ctx, "Async + thread pool + sampling", "Configuration Presets"));
    }

    {
        const logger = try Logger.init(allocator);
        defer logger.deinit();

        var config = Config.secure();
        config.autoSink = false;
        config.autoFlush = false;
        logger.configure(config);

        _ = try logger.addSink(.{ .path = NULL_PATH });

        const ctx = BenchContext{ .logger = logger, .allocator = allocator };
        try results.append(allocator, runBenchmark("Secure preset", benchSimpleLog, &ctx, "Redaction enabled", "Configuration Presets"));
    }

    {
        const logger = try Logger.init(allocator);
        defer logger.deinit();

        var config = Config.default();
        config.color = false;
        config.autoSink = false;
        config.autoFlush = false;
        logger.configure(config);

        _ = try logger.addSink(.{ .path = NULL_PATH });
        _ = try logger.addSink(.{ .path = NULL_PATH, .format = .json });
        _ = try logger.addSink(.{ .path = NULL_PATH, .format = .json, .prettyJson = true });

        const ctx = BenchContext{ .logger = logger, .allocator = allocator };
        try results.append(allocator, runBenchmark("Multiple sinks (3)", benchSimpleLog, &ctx, "Text + JSON + Pretty", "Configuration Presets"));
    }

    //
    // Allocator Comparison
    //
    {
        std.debug.print("Running: Allocator comparison benchmarks...\n", .{});

        // Standard allocator (GPA)
        const loggerStd = try Logger.init(allocator);
        defer loggerStd.deinit();

        var configStd = Config.default();
        configStd.autoSink = false;
        configStd.autoFlush = false;
        loggerStd.configure(configStd);
        _ = loggerStd.removeAllSinks();

        _ = try loggerStd.addSink(.{ .path = NULL_PATH });

        const ctxStd = BenchContext{ .logger = loggerStd, .allocator = allocator };
        try results.append(allocator, runBenchmark("Standard allocator (GPA)", benchSimpleLog, &ctxStd, "Default allocation", "Allocator Comparison"));
        try results.append(allocator, runBenchmark("Standard allocator (formatted)", benchFormattedLog, &ctxStd, "GPA with formatting", "Allocator Comparison"));
    }

    {
        // Page allocator comparison
        const pageAlloc = std.heap.page_allocator;
        const loggerPage = try Logger.init(pageAlloc);
        defer loggerPage.deinit();

        var configPage = Config.default();
        configPage.autoSink = false;
        configPage.autoFlush = false;
        loggerPage.configure(configPage);
        _ = loggerPage.removeAllSinks();

        _ = try loggerPage.addSink(.{ .path = NULL_PATH });

        const ctxPage = BenchContext{ .logger = loggerPage, .allocator = pageAlloc };
        try results.append(allocator, runBenchmark("Page allocator", benchSimpleLog, &ctxPage, "System page allocator", "Allocator Comparison"));
    }

    //
    // Enterprise Features
    //
    {
        std.debug.print("Running: Enterprise features benchmarks...\n", .{});

        // Context binding benchmark
        const logger = try Logger.init(allocator);
        defer logger.deinit();

        var config = Config.default();
        config.autoSink = false;
        config.autoFlush = false;
        logger.configure(config);

        _ = try logger.addSink(.{ .path = NULL_PATH });

        try logger.bind("app", .{ .string = "benchmark" });
        try logger.bind("version", .{ .string = "0.0.4" });
        try logger.bind("environment", .{ .string = "test" });

        const ctx = BenchContext{ .logger = logger, .allocator = allocator };
        try results.append(allocator, runBenchmark("With context (3 fields)", benchSimpleLog, &ctx, "Bound context data", "Enterprise Features"));
    }

    {
        // Trace context benchmark
        const logger = try Logger.init(allocator);
        defer logger.deinit();

        var config = Config.default();
        config.enableTracing = true;
        config.autoSink = false;
        config.autoFlush = false;
        logger.configure(config);

        _ = try logger.addSink(.{ .path = NULL_PATH });

        try logger.setTraceContext("trace-abc-123456", "span-001");
        try logger.setCorrelationId("correlation-xyz-789");

        const ctx = BenchContext{ .logger = logger, .allocator = allocator };
        try results.append(allocator, runBenchmark("With trace context", benchSimpleLog, &ctx, "Trace ID + Span ID", "Enterprise Features"));
    }

    {
        // Metrics enabled benchmark
        const logger = try Logger.init(allocator);
        defer logger.deinit();

        var config = Config.default();
        config.enableMetrics = true;
        config.autoSink = false;
        config.autoFlush = false;
        logger.configure(config);

        _ = try logger.addSink(.{ .path = NULL_PATH });

        const ctx = BenchContext{ .logger = logger, .allocator = allocator };
        try results.append(allocator, runBenchmark("With metrics enabled", benchSimpleLog, &ctx, "Performance monitoring", "Enterprise Features"));
    }

    {
        // Structured logging
        const logger = try Logger.init(allocator);
        defer logger.deinit();

        var config = Config.default();
        config.structured = true;
        config.format = .json;
        config.autoSink = false;
        config.autoFlush = false;
        logger.configure(config);

        _ = try logger.addSink(.{ .path = NULL_PATH, .format = .json });

        const ctx = BenchContext{ .logger = logger, .allocator = allocator };
        try results.append(allocator, runBenchmark("Structured logging", benchSimpleLog, &ctx, "JSON structured output", "Enterprise Features"));
    }

    //
    // Sampling & Rate Limiting
    //
    {
        std.debug.print("Running: Sampling & rate limiting benchmarks...\n", .{});

        // Probability sampling
        const loggerProb = try Logger.init(allocator);
        defer loggerProb.deinit();

        var configProb = Config.default();
        configProb.sampling = .{ .enabled = true, .strategy = .{ .probability = 0.5 } };
        configProb.autoSink = false;
        configProb.autoFlush = false;
        loggerProb.configure(configProb);
        _ = loggerProb.removeAllSinks();

        _ = try loggerProb.addSink(.{ .path = NULL_PATH });

        const ctxProb = BenchContext{ .logger = loggerProb, .allocator = allocator };
        try results.append(allocator, runBenchmark("Sampling (50% probability)", benchSimpleLog, &ctxProb, "Probability sampling", "Sampling & Rate Limiting"));
    }

    {
        // Rate limit sampling
        const loggerRate = try Logger.init(allocator);
        defer loggerRate.deinit();

        var configRate = Config.default();
        configRate.sampling = .{ .enabled = true, .strategy = .{ .rateLimit = .{ .maxRecords = 100, .windowMs = 1000 } } };
        configRate.autoSink = false;
        configRate.autoFlush = false;
        loggerRate.configure(configRate);
        _ = loggerRate.removeAllSinks();

        _ = try loggerRate.addSink(.{ .path = NULL_PATH });

        const ctxRate = BenchContext{ .logger = loggerRate, .allocator = allocator };
        try results.append(allocator, runBenchmark("Sampling (rate limit)", benchSimpleLog, &ctxRate, "Rate-based sampling", "Sampling & Rate Limiting"));
    }

    {
        // Adaptive sampling
        const loggerAdapt = try Logger.init(allocator);
        defer loggerAdapt.deinit();

        var configAdapt = Config.default();
        configAdapt.sampling = .{ .enabled = true, .strategy = .{ .adaptive = .{ .targetRate = 1000 } } };
        configAdapt.autoSink = false;
        configAdapt.autoFlush = false;
        loggerAdapt.configure(configAdapt);
        _ = loggerAdapt.removeAllSinks();

        _ = try loggerAdapt.addSink(.{ .path = NULL_PATH });

        const ctxAdapt = BenchContext{ .logger = loggerAdapt, .allocator = allocator };
        try results.append(allocator, runBenchmark("Sampling (adaptive)", benchSimpleLog, &ctxAdapt, "Adaptive sampling", "Sampling & Rate Limiting"));
    }

    {
        // Every-N sampling
        const loggerN = try Logger.init(allocator);
        defer loggerN.deinit();

        var configN = Config.default();
        configN.sampling = .{ .enabled = true, .strategy = .{ .everyN = 100 } };
        configN.autoSink = false;
        configN.autoFlush = false;
        loggerN.configure(configN);
        _ = loggerN.removeAllSinks();

        _ = try loggerN.addSink(.{ .path = NULL_PATH });

        const ctxN = BenchContext{ .logger = loggerN, .allocator = allocator };
        try results.append(allocator, runBenchmark("Sampling (every-N)", benchSimpleLog, &ctxN, "Every-N message sampling", "Sampling & Rate Limiting"));
    }

    {
        // Rate limiting
        const loggerRL = try Logger.init(allocator);
        defer loggerRL.deinit();

        var configRL = Config.default();
        configRL.rateLimit = .{ .enabled = true, .maxPerSecond = 10000, .burstSize = 100 };
        configRL.autoSink = false;
        configRL.autoFlush = false;
        loggerRL.configure(configRL);
        _ = loggerRL.removeAllSinks();

        _ = try loggerRL.addSink(.{ .path = NULL_PATH });

        const ctxRL = BenchContext{ .logger = loggerRL, .allocator = allocator };
        try results.append(allocator, runBenchmark("Rate limiting (10K/sec)", benchSimpleLog, &ctxRL, "Max 10K logs per second", "Sampling & Rate Limiting"));
    }

    {
        // Redaction
        const loggerRedact = try Logger.init(allocator);
        defer loggerRedact.deinit();

        var configRedact = Config.default();
        configRedact.redaction = .{ .enabled = true, .replacement = "[REDACTED]" };
        configRedact.autoSink = false;
        configRedact.autoFlush = false;
        loggerRedact.configure(configRedact);
        _ = loggerRedact.removeAllSinks();

        _ = try loggerRedact.addSink(.{ .path = NULL_PATH });

        const ctxRedact = BenchContext{ .logger = loggerRedact, .allocator = allocator };
        try results.append(allocator, runBenchmark("With redaction enabled", benchSimpleLog, &ctxRedact, "Sensitive data masking", "Sampling & Rate Limiting"));
    }

    //
    // Filtering
    //
    {
        std.debug.print("Running: Filtering benchmarks...\n", .{});

        const loggerFilter = try Logger.init(allocator);
        defer loggerFilter.deinit();

        var configFilter = Config.default();
        configFilter.autoSink = false;
        configFilter.autoFlush = false;
        loggerFilter.configure(configFilter);
        _ = loggerFilter.removeAllSinks();

        // Setup filter
        var filter = logly.Filter.init(allocator);
        defer filter.deinit();
        try filter.addMinLevel(.info); // Allow INFO and above
        loggerFilter.setFilter(&filter);

        _ = try loggerFilter.addSink(.{ .path = NULL_PATH });

        const ctxFilter = BenchContext{ .logger = loggerFilter, .allocator = allocator };
        try results.append(allocator, runBenchmark("Filter (allowed)", benchFilterAllowed, &ctxFilter, "Message passes filter", "Filtering"));
        try results.append(allocator, runBenchmark("Filter (rejected)", benchFilterRejected, &ctxFilter, "Message blocked by filter", "Filtering"));
    }

    //
    // Rules Engine
    //
    {
        std.debug.print("Running: Rules Engine benchmarks...\n", .{});

        // Rules with conditions
        const RulesContext = struct {
            logger: *Logger,
            fn benchRulesLog(self: *const @This()) !void {
                try self.logger.info("Processing order #12345", null);
            }
        };

        const loggerRules = try Logger.init(allocator);
        defer loggerRules.deinit();

        var configRules = Config.default();
        configRules.autoSink = false;
        configRules.autoFlush = false;
        configRules.rules = .{
            .enabled = true,
        };
        loggerRules.configure(configRules);
        _ = loggerRules.removeAllSinks();

        _ = try loggerRules.addSink(.{ .path = NULL_PATH });

        const rulesCtx = RulesContext{ .logger = loggerRules };
        try results.append(allocator, runBenchmark("Rules engine (enabled)", struct {
            fn bench(ctx: *const RulesContext) !void {
                try ctx.benchRulesLog();
            }
        }.bench, &rulesCtx, "Rule evaluation", "Rules Engine"));
    }

    {
        // Rules disabled baseline
        const loggerNoRules = try Logger.init(allocator);
        defer loggerNoRules.deinit();

        var configNoRules = Config.default();
        configNoRules.autoSink = false;
        configNoRules.autoFlush = false;
        configNoRules.rules = .{ .enabled = false };
        loggerNoRules.configure(configNoRules);
        _ = loggerNoRules.removeAllSinks();

        _ = try loggerNoRules.addSink(.{ .path = NULL_PATH });

        const ctx = BenchContext{ .logger = loggerNoRules, .allocator = allocator };
        try results.append(allocator, runBenchmark("Rules engine (disabled)", benchSimpleLog, &ctx, "No rule evaluation", "Rules Engine"));
    }

    //
    // Redaction
    //
    {
        std.debug.print("Running: Redaction benchmarks...\n", .{});

        const Redactor = logly.Redactor;

        // Redactor pattern matching
        const RedactorContext = struct {
            redactor: *Redactor,
            allocator: std.mem.Allocator,

            fn benchRedact(self: *const @This()) !void {
                const msg = "User password=secret123 logged in from api_key=abc123";
                const result = try self.redactor.redact(msg);
                self.allocator.free(result);
            }

            fn benchNoRedact(self: *const @This()) !void {
                const msg = "Normal message without sensitive data";
                const result = try self.redactor.redact(msg);
                self.allocator.free(result);
            }
        };

        var redactor = Redactor.init(allocator);
        defer redactor.deinit();

        try redactor.addPattern("password", .contains, "password=", "[REDACTED]");
        try redactor.addPattern("api_key", .contains, "api_key=", "[HIDDEN]");

        const redactCtx = RedactorContext{ .redactor = &redactor, .allocator = allocator };
        try results.append(allocator, runBenchmark("Redaction (pattern match)", struct {
            fn bench(ctx: *const RedactorContext) !void {
                try ctx.benchRedact();
            }
        }.bench, &redactCtx, "2 patterns matched", "Redaction"));

        try results.append(allocator, runBenchmark("Redaction (no match)", struct {
            fn bench(ctx: *const RedactorContext) !void {
                try ctx.benchNoRedact();
            }
        }.bench, &redactCtx, "No patterns matched", "Redaction"));
    }

    {
        // Field redaction
        const Redactor = logly.Redactor;

        const FieldRedactContext = struct {
            redactor: *Redactor,
            allocator: std.mem.Allocator,

            fn benchFieldRedact(self: *const @This()) !void {
                const result = try self.redactor.redactField("password", "supersecret123");
                self.allocator.free(result);
            }
        };

        var fieldRedactor = Redactor.init(allocator);
        defer fieldRedactor.deinit();

        try fieldRedactor.addField("password", .full);
        try fieldRedactor.addField("email", .partialEnd);
        try fieldRedactor.addField("credit_card", .maskMiddle);

        const fieldCtx = FieldRedactContext{ .redactor = &fieldRedactor, .allocator = allocator };
        try results.append(allocator, runBenchmark("Field redaction (full)", struct {
            fn bench(ctx: *const FieldRedactContext) !void {
                try ctx.benchFieldRedact();
            }
        }.bench, &fieldCtx, "Full field masking", "Redaction"));
    }

    //
    // Metrics
    //
    {
        std.debug.print("Running: Metrics benchmarks...\n", .{});

        const Metrics = logly.Metrics;

        const MetricsContext = struct {
            metrics: *Metrics,

            fn benchRecordLog(self: *const @This()) !void {
                self.metrics.recordLog(.info, 100);
            }

            fn benchRecordLogWithLatency(self: *const @This()) !void {
                self.metrics.recordLogWithLatency(.info, 100, 1000);
            }

            fn benchSnapshot(self: *const @This()) !void {
                _ = self.metrics.getSnapshot();
            }
        };

        var metrics = Metrics.init(allocator);
        defer metrics.deinit();

        const metricsCtx = MetricsContext{ .metrics = &metrics };
        try results.append(allocator, runBenchmark("Metrics recordLog", struct {
            fn bench(ctx: *const MetricsContext) !void {
                try ctx.benchRecordLog();
            }
        }.bench, &metricsCtx, "Atomic counter update", "Metrics"));

        try results.append(allocator, runBenchmark("Metrics with latency", struct {
            fn bench(ctx: *const MetricsContext) !void {
                try ctx.benchRecordLogWithLatency();
            }
        }.bench, &metricsCtx, "With latency tracking", "Metrics"));

        try results.append(allocator, runBenchmark("Metrics snapshot", struct {
            fn bench(ctx: *const MetricsContext) !void {
                try ctx.benchSnapshot();
            }
        }.bench, &metricsCtx, "Get current snapshot", "Metrics"));
    }

    {
        // Metrics with config
        const Metrics = logly.Metrics;

        var metricsWithConfig = Metrics.initWithConfig(allocator, .{
            .enabled = true,
            .trackLevels = true,
            .trackLatency = true,
            .enableHistogram = true,
        });
        defer metricsWithConfig.deinit();

        const MetricsConfigContext = struct {
            metrics: *Metrics,

            fn benchRecordWithConfig(self: *const @This()) !void {
                self.metrics.recordLogWithLatency(.warning, 150, 2500);
            }
        };

        const configCtx = MetricsConfigContext{ .metrics = &metricsWithConfig };
        try results.append(allocator, runBenchmark("Metrics (full config)", struct {
            fn bench(ctx: *const MetricsConfigContext) !void {
                try ctx.benchRecordWithConfig();
            }
        }.bench, &configCtx, "All tracking enabled", "Metrics"));
    }

    //
    // Rotation
    //
    {
        std.debug.print("Running: Rotation benchmarks...\n", .{});

        const loggerRotation = try Logger.init(allocator);
        defer loggerRotation.deinit();

        var configRot = Config.default();
        configRot.autoSink = false;
        configRot.autoFlush = false;
        loggerRotation.configure(configRot);
        _ = loggerRotation.removeAllSinks();

        // Add a sink with rotation
        _ = try loggerRotation.addSink(.{
            .path = NULL_PATH,
            .rotation = "daily",
            .sizeLimit = 1024 * 1024, // 1MB
            .retention = 5,
        });

        const ctxRot = BenchContext{ .logger = loggerRotation, .allocator = allocator };
        try results.append(allocator, runBenchmark("Rotation (size check)", benchSimpleLog, &ctxRot, "Size-based check", "Rotation"));
    }

    //
    // Multi-Threading
    //
    {
        std.debug.print("Running: Multi-threading benchmarks...\n", .{});

        // Single-threaded baseline
        const logger1 = try Logger.init(allocator);
        defer logger1.deinit();

        var config1 = Config.default();
        config1.autoSink = false;
        config1.autoFlush = false;
        logger1.configure(config1);
        _ = logger1.removeAllSinks();

        _ = try logger1.addSink(.{ .path = NULL_PATH });

        try results.append(allocator, runMultiThreadBenchmark(
            "Single thread baseline",
            logger1,
            1,
            "1 thread sequential",
            "Multi-Threading",
            allocator,
            multiThreadWorker,
        ));
    }

    {
        // 2 threads
        const logger2 = try Logger.init(allocator);
        defer logger2.deinit();

        var config2 = Config.default();
        config2.autoSink = false;
        config2.autoFlush = false;
        logger2.configure(config2);
        _ = logger2.removeAllSinks();

        _ = try logger2.addSink(.{ .path = NULL_PATH });

        try results.append(allocator, runMultiThreadBenchmark(
            "2 threads concurrent",
            logger2,
            2,
            "2 threads parallel",
            "Multi-Threading",
            allocator,
            multiThreadWorker,
        ));
    }

    {
        // 4 threads
        const logger4 = try Logger.init(allocator);
        defer logger4.deinit();

        var config4 = Config.default();
        config4.autoSink = false;
        config4.autoFlush = false;
        logger4.configure(config4);
        _ = logger4.removeAllSinks();

        _ = try logger4.addSink(.{ .path = NULL_PATH });

        try results.append(allocator, runMultiThreadBenchmark(
            "4 threads concurrent",
            logger4,
            4,
            "4 threads parallel",
            "Multi-Threading",
            allocator,
            multiThreadWorker,
        ));
    }

    {
        // 8 threads
        const logger8 = try Logger.init(allocator);
        defer logger8.deinit();

        var config8 = Config.default();
        config8.autoSink = false;
        config8.autoFlush = false;
        logger8.configure(config8);
        _ = logger8.removeAllSinks();

        _ = try logger8.addSink(.{ .path = NULL_PATH });

        try results.append(allocator, runMultiThreadBenchmark(
            "8 threads concurrent",
            logger8,
            8,
            "8 threads parallel",
            "Multi-Threading",
            allocator,
            multiThreadWorker,
        ));
    }

    {
        // 16 threads
        const logger16 = try Logger.init(allocator);
        defer logger16.deinit();

        var config16 = Config.default();
        config16.autoSink = false;
        config16.autoFlush = false;
        logger16.configure(config16);
        _ = logger16.removeAllSinks();

        _ = try logger16.addSink(.{ .path = NULL_PATH });

        try results.append(allocator, runMultiThreadBenchmark(
            "16 threads concurrent",
            logger16,
            16,
            "16 threads parallel",
            "Multi-Threading",
            allocator,
            multiThreadWorker,
        ));
    }

    {
        // Multi-thread with JSON
        const loggerJson = try Logger.init(allocator);
        defer loggerJson.deinit();

        var configJson = Config.default();
        configJson.format = .json;
        configJson.autoSink = false;
        configJson.autoFlush = false;
        loggerJson.configure(configJson);
        _ = loggerJson.removeAllSinks();

        _ = try loggerJson.addSink(.{ .path = NULL_PATH, .format = .json });

        try results.append(allocator, runMultiThreadBenchmark(
            "4 threads JSON",
            loggerJson,
            4,
            "Parallel JSON logging",
            "Multi-Threading",
            allocator,
            multiThreadWorkerJson,
        ));
    }

    {
        // Multi-thread with colors
        const loggerColor = try Logger.init(allocator);
        defer loggerColor.deinit();

        var configColor = Config.default();
        configColor.color = true;
        configColor.autoSink = false;
        configColor.autoFlush = false;
        loggerColor.configure(configColor);
        _ = loggerColor.removeAllSinks();

        _ = try loggerColor.addSink(.{ .path = NULL_PATH, .color = true });

        try results.append(allocator, runMultiThreadBenchmark(
            "4 threads colored",
            loggerColor,
            4,
            "Parallel colored logging",
            "Multi-Threading",
            allocator,
            multiThreadWorker,
        ));
    }

    {
        // Multi-thread with formatting
        const loggerFmt = try Logger.init(allocator);
        defer loggerFmt.deinit();

        var configFmt = Config.default();
        configFmt.autoSink = false;
        configFmt.autoFlush = false;
        loggerFmt.configure(configFmt);
        _ = loggerFmt.removeAllSinks();

        _ = try loggerFmt.addSink(.{ .path = NULL_PATH });

        try results.append(allocator, runMultiThreadBenchmark(
            "4 threads formatted",
            loggerFmt,
            4,
            "Parallel formatted logging",
            "Multi-Threading",
            allocator,
            multiThreadWorkerFormatted,
        ));
    }

    //
    // Performance Comparison
    //
    {
        std.debug.print("Running: Performance comparison benchmarks...\n", .{});

        // File output
        const loggerFile = try Logger.init(allocator);
        defer loggerFile.deinit();

        var configFile = Config.default();
        configFile.color = false;
        configFile.autoSink = false;
        configFile.autoFlush = false;
        loggerFile.configure(configFile);
        _ = loggerFile.removeAllSinks();

        _ = try loggerFile.addSink(.{ .path = NULL_PATH });

        const ctxFile = BenchContext{ .logger = loggerFile, .allocator = allocator };
        try results.append(allocator, runBenchmark("File output (plain)", benchSimpleLog, &ctxFile, "Null device output", "Performance Comparison"));
        try results.append(allocator, runBenchmark("File output (error)", benchErrorLog, &ctxFile, "Error to file", "Performance Comparison"));
    }

    {
        // No sampling vs sampling comparison
        const loggerNoSample = try Logger.init(allocator);
        defer loggerNoSample.deinit();

        var configNoSample = Config.default();
        configNoSample.sampling = .{ .enabled = false };
        configNoSample.autoSink = false;
        configNoSample.autoFlush = false;
        loggerNoSample.configure(configNoSample);
        _ = loggerNoSample.removeAllSinks();

        _ = try loggerNoSample.addSink(.{ .path = NULL_PATH });

        const ctxNoSample = BenchContext{ .logger = loggerNoSample, .allocator = allocator };
        try results.append(allocator, runBenchmark("No sampling (baseline)", benchSimpleLog, &ctxNoSample, "Sampling disabled", "Performance Comparison"));
    }

    {
        // Compression enabled
        const loggerComp = try Logger.init(allocator);
        defer loggerComp.deinit();

        var configComp = Config.default();
        configComp.compression = .{ .enabled = true, .algorithm = .deflate, .level = .fast };
        configComp.autoSink = false;
        configComp.autoFlush = false;
        loggerComp.configure(configComp);
        _ = loggerComp.removeAllSinks();

        _ = try loggerComp.addSink(.{ .path = NULL_PATH });

        const ctxComp = BenchContext{ .logger = loggerComp, .allocator = allocator };
        try results.append(allocator, runBenchmark("Compression enabled (fast)", benchSimpleLog, &ctxComp, "Deflate compression", "Performance Comparison"));
    }

    // Print all results to console
    printResults(results.items);

    // Summary Statistics
    std.debug.print("\n[BENCHMARK SUMMARY]\n", .{});
    std.debug.print("============================================================", .{});
    std.debug.print("\n", .{});

    var totalOps: f64 = 0;
    var maxOps: f64 = 0;
    var minOps: f64 = std.math.floatMax(f64);
    var count: usize = 0;
    var maxName: []const u8 = "";
    var minName: []const u8 = "";

    for (results.items) |r| {
        totalOps += r.opsPerSec;
        count += 1;
        if (r.opsPerSec > maxOps) {
            maxOps = r.opsPerSec;
            maxName = r.name;
        }
        if (r.opsPerSec < minOps) {
            minOps = r.opsPerSec;
            minName = r.name;
        }
    }

    const avgOps = if (count > 0) totalOps / @as(f64, @floatFromInt(count)) else 0;
    const avgLatency = if (avgOps > 0) 1_000_000_000.0 / avgOps else 0;

    if (count > 0) {
        std.debug.print("\nTotal benchmarks run:     {d}\n", .{count});
        std.debug.print("Average throughput:       {d:.0} ops/sec\n", .{avgOps});
        std.debug.print("Maximum throughput:       {d:.0} ops/sec ({s})\n", .{ maxOps, maxName });
        std.debug.print("Minimum throughput:       {d:.0} ops/sec ({s})\n", .{ minOps, minName });
        std.debug.print("Average latency:          {d:.0} ns\n", .{avgLatency});
    }

    std.debug.print("\n", .{});
    std.debug.print("============================================================", .{});
    std.debug.print("\n", .{});
    std.debug.print("[OK] Benchmarks completed successfully!\n\n", .{});

    // Write final Markdown report
    const io = logly.Utils.io();
    const mdFile = std.Io.Dir.cwd().createFile(io, "benchmark-results.md", .{}) catch |err| {
        std.debug.print("Warning: Could not create benchmark-results.md: {}\n", .{err});
        return;
    };
    defer mdFile.close(io);

    const mdHeader =
        \\#### 📊 LOGLY.ZIG BENCHMARK RESULTS
        \\
        \\**Environment Details:**
        \\- **Platform:** {s}
        \\- **Architecture:** {s}
        \\- **Warmup Iterations:** {d}
        \\- **Benchmark Iterations:** {d}
        \\- **Multi-thread Iterations:** {d} per thread
        \\
        \\
    ;

    var headerBuf: [1024]u8 = undefined;
    const header = std.fmt.bufPrint(&headerBuf, mdHeader, .{
        @tagName(builtin.os.tag),
        @tagName(builtin.cpu.arch),
        WARMUP_ITERATIONS,
        BENCHMARK_ITERATIONS,
        MT_BENCHMARK_ITERATIONS,
    }) catch "";
    try mdFile.writeStreamingAll(io, header);

    // Write categorized tables
    for (BenchmarkResult.categories) |cat| {
        var hasCategory = false;
        for (results.items) |r| {
            if (std.mem.eql(u8, r.category, cat)) {
                hasCategory = true;
                break;
            }
        }
        if (!hasCategory) continue;

        const catMd = std.fmt.allocPrint(allocator,
            \\
            \\<details>
            \\<summary><strong>{s}</strong></summary>
            \\
            \\| Benchmark | Ops/sec (higher is better) | Avg Latency (ns) (lower is better) | Notes |
            \\| :--- | :--- | :--- | :--- |
            \\
        , .{cat}) catch continue;
        defer allocator.free(catMd);
        try mdFile.writeStreamingAll(io, catMd);

        for (results.items) |r| {
            if (std.mem.eql(u8, r.category, cat)) {
                var lineBuf: [1024]u8 = undefined;
                const line = std.fmt.bufPrint(&lineBuf, "| {s} | {d:.0} | {d:.0} | {s} |\n", .{
                    r.name,
                    r.opsPerSec,
                    r.avgLatencyNs,
                    r.notes,
                }) catch continue;
                try mdFile.writeStreamingAll(io, line);
            }
        }
        try mdFile.writeStreamingAll(io, "</details>\n");
    }

    // Write summary to Markdown
    if (count > 0) {
        try mdFile.writeStreamingAll(io, "\n### 📈 Benchmark Summary\n\n");
        var summaryBuf: [1024]u8 = undefined;
        const summary = std.fmt.bufPrint(&summaryBuf,
            \\- **Total benchmarks run:** {d}
            \\- **Average throughput:** {d:.0} ops/sec
            \\- **Maximum throughput:** {d:.0} ops/sec ({s})
            \\- **Minimum throughput:** {d:.0} ops/sec ({s})
            \\- **Average latency:** {d:.0} ns
            \\
        , .{ count, avgOps, maxOps, maxName, minOps, minName, avgLatency }) catch "";
        try mdFile.writeStreamingAll(io, summary);
    }

    try mdFile.writeStreamingAll(io, "\n---\n");
}
