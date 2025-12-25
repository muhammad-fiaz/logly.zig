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
        "System Diagnostics",
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
    std.debug.print("-" ** 100, .{});
    std.debug.print("\n", .{});
    std.debug.print("                                 LOGLY.ZIG BENCHMARK RESULTS\n", .{});
    std.debug.print("-" ** 100, .{});
    std.debug.print("\n", .{});

    for (BenchmarkResult.categories) |cat| {
        var has_category = false;
        for (results) |r| {
            if (std.mem.eql(u8, r.category, cat)) {
                has_category = true;
                break;
            }
        }
        if (!has_category) continue;

        std.debug.print("\n[{s}]\n", .{cat});
        std.debug.print("-" ** 100, .{});
        std.debug.print("\n", .{});
        std.debug.print("{s:<40} {s:>25} {s:>25} {s:>10}\n", .{ "Benchmark", "Ops/sec", "Avg Latency (ns)", "Notes" });
        std.debug.print("-" ** 100, .{});
        std.debug.print("\n", .{});

        for (results) |r| {
            if (std.mem.eql(u8, r.category, cat)) {
                std.debug.print("{s:<50} {d:>25.0} {d:>30.0} {s:>20}\n", .{
                    r.name,
                    r.ops_per_sec,
                    r.avg_latency_ns,
                    r.notes,
                });
            }
        }
    }

    std.debug.print("\n", .{});
    std.debug.print("=" ** 130, .{});
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
        .category = category,
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
        .category = category,
    };
}

/// Benchmark context structure
const BenchContext = struct {
    logger: *Logger,
    allocator: std.mem.Allocator,
};

// ============================================
// Basic Benchmark Functions
// ============================================
fn benchSimpleLog(ctx: *const BenchContext) !void {
    try ctx.logger.info("Simple log message", null);
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

// ============================================
// Filtering Benchmark Functions
// ============================================
fn benchFilterAllowed(ctx: *const BenchContext) !void {
    try ctx.logger.info("This message passes the filter", null);
}

fn benchFilterRejected(ctx: *const BenchContext) !void {
    try ctx.logger.debug("This message is rejected by filter", null);
}

fn benchFilterComplex(ctx: *const BenchContext) !void {
    try ctx.logger.info("Checking complex filter rules", null);
}

// ============================================
// Diagnostics Benchmark Functions
// ============================================
fn benchDiagnostics(ctx: *const BenchContext) !void {
    try ctx.logger.logSystemDiagnostics(null);
}

// ============================================
// Multi-thread worker function
// ============================================
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
    thread_count: usize,
    notes: []const u8,
    category: []const u8,
    allocator: std.mem.Allocator,
    comptime workerFn: fn (*const BenchContext) void,
) BenchmarkResult {
    const ctx = BenchContext{ .logger = logger, .allocator = allocator };

    // Warmup
    for (0..WARMUP_ITERATIONS) |_| {
        logger.info("Warmup message", null) catch {};
    }

    var timer = std.time.Timer.start() catch return BenchmarkResult{
        .name = name,
        .iterations = 0,
        .total_time_ns = 0,
        .ops_per_sec = 0,
        .avg_latency_ns = 0,
        .min_latency_ns = 0,
        .max_latency_ns = 0,
        .notes = notes,
        .category = category,
    };

    // Spawn threads
    var threads: [16]?std.Thread = [_]?std.Thread{null} ** 16;
    const actual_threads = @min(thread_count, 16);

    for (0..actual_threads) |i| {
        threads[i] = std.Thread.spawn(.{}, workerFn, .{&ctx}) catch null;
    }

    // Wait for all threads
    for (0..actual_threads) |i| {
        if (threads[i]) |t| {
            t.join();
        }
    }

    const total_time_ns = timer.read();
    const total_ops = MT_BENCHMARK_ITERATIONS * actual_threads;
    const ops_per_sec = @as(f64, @floatFromInt(total_ops)) / (@as(f64, @floatFromInt(total_time_ns)) / 1_000_000_000.0);
    const avg_latency_ns = @as(f64, @floatFromInt(total_time_ns)) / @as(f64, @floatFromInt(total_ops));

    return .{
        .name = name,
        .iterations = total_ops,
        .total_time_ns = total_time_ns,
        .ops_per_sec = ops_per_sec,
        .avg_latency_ns = avg_latency_ns,
        .min_latency_ns = 0,
        .max_latency_ns = 0,
        .notes = notes,
        .category = category,
    };
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var results: std.ArrayList(BenchmarkResult) = .empty;
    defer results.deinit(allocator);

    // ============================================
    // CATEGORY: Basic Logging
    // ============================================
    {
        std.debug.print("Running: Basic logging benchmarks...\n", .{});
        const logger = try Logger.init(allocator);
        defer logger.deinit();

        var config = Config.default();
        config.color = false;
        config.global_color_display = false;
        config.auto_sink = false;
        logger.configure(config);

        _ = try logger.addSink(.{ .path = NULL_PATH });

        const ctx = BenchContext{ .logger = logger, .allocator = allocator };
        try results.append(allocator, runBenchmark("Simple log (no color)", benchSimpleLog, &ctx, "Plain text output", "Basic Logging"));
        try results.append(allocator, runBenchmark("Formatted log (no color)", benchFormattedLog, &ctx, "Printf-style formatting", "Basic Logging"));
    }

    {
        const logger = try Logger.init(allocator);
        defer logger.deinit();

        var config = Config.default();
        config.color = true;
        config.global_color_display = true;
        config.auto_sink = false;
        logger.configure(config);

        _ = try logger.addSink(.{ .path = NULL_PATH, .color = true });

        const ctx = BenchContext{ .logger = logger, .allocator = allocator };
        try results.append(allocator, runBenchmark("Simple log (with color)", benchSimpleLog, &ctx, "ANSI color codes", "Basic Logging"));
        try results.append(allocator, runBenchmark("Formatted log (with color)", benchFormattedLog, &ctx, "Colored + formatting", "Basic Logging"));
    }

    // ============================================
    // CATEGORY: JSON Logging
    // ============================================
    {
        std.debug.print("Running: JSON logging benchmarks...\n", .{});
        const logger = try Logger.init(allocator);
        defer logger.deinit();

        var config = Config.default();
        config.json = true;
        config.color = false;
        config.auto_sink = false;
        logger.configure(config);

        _ = try logger.addSink(.{ .path = NULL_PATH, .json = true, .color = false });

        const ctx = BenchContext{ .logger = logger, .allocator = allocator };
        try results.append(allocator, runBenchmark("JSON compact", benchSimpleLog, &ctx, "Compact JSON output", "JSON Logging"));
        try results.append(allocator, runBenchmark("JSON formatted", benchFormattedLog, &ctx, "JSON with formatting", "JSON Logging"));
    }

    {
        const logger = try Logger.init(allocator);
        defer logger.deinit();

        var config = Config.default();
        config.json = true;
        config.pretty_json = true;
        config.auto_sink = false;
        logger.configure(config);

        _ = try logger.addSink(.{ .path = NULL_PATH, .json = true, .pretty_json = true });

        const ctx = BenchContext{ .logger = logger, .allocator = allocator };
        try results.append(allocator, runBenchmark("JSON pretty", benchSimpleLog, &ctx, "Indented JSON output", "JSON Logging"));
    }

    {
        const logger = try Logger.init(allocator);
        defer logger.deinit();

        var config = Config.default();
        config.json = true;
        config.color = true;
        config.auto_sink = false;
        logger.configure(config);

        _ = try logger.addSink(.{ .path = NULL_PATH, .json = true, .color = true });

        const ctx = BenchContext{ .logger = logger, .allocator = allocator };
        try results.append(allocator, runBenchmark("JSON with color", benchSimpleLog, &ctx, "JSON with ANSI colors", "JSON Logging"));
    }

    // ============================================
    // CATEGORY: Log Levels
    // ============================================
    {
        std.debug.print("Running: Log levels benchmarks...\n", .{});
        const logger = try Logger.init(allocator);
        defer logger.deinit();

        var config = Config.default();
        config.level = .trace;
        config.color = false;
        config.auto_sink = false;
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

    // ============================================
    // CATEGORY: Custom Features
    // ============================================
    {
        std.debug.print("Running: Custom features benchmarks...\n", .{});
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
        try results.append(allocator, runBenchmark("Custom level (AUDIT)", benchCustomLevel, &ctx, "User-defined log level", "Custom Features"));
    }

    {
        const logger = try Logger.init(allocator);
        defer logger.deinit();

        var config = Config.default();
        config.log_format = "{time} | {level} | {message}";
        config.auto_sink = false;
        logger.configure(config);

        _ = try logger.addSink(.{ .path = NULL_PATH });

        const ctx = BenchContext{ .logger = logger, .allocator = allocator };
        try results.append(allocator, runBenchmark("Custom log format", benchSimpleLog, &ctx, "{time} | {level} | {message}", "Custom Features"));
    }

    {
        const logger = try Logger.init(allocator);
        defer logger.deinit();

        var config = Config.default();
        config.time_format = "DD/MM/YYYY HH:mm:ss";
        config.auto_sink = false;
        logger.configure(config);

        _ = try logger.addSink(.{ .path = NULL_PATH });

        const ctx = BenchContext{ .logger = logger, .allocator = allocator };
        try results.append(allocator, runBenchmark("Custom time format", benchSimpleLog, &ctx, "DD/MM/YYYY HH:mm:ss", "Custom Features"));
    }

    {
        const logger = try Logger.init(allocator);
        defer logger.deinit();

        var config = Config.default();
        config.time_format = "ISO8601";
        config.auto_sink = false;
        logger.configure(config);

        _ = try logger.addSink(.{ .path = NULL_PATH });

        const ctx = BenchContext{ .logger = logger, .allocator = allocator };
        try results.append(allocator, runBenchmark("ISO8601 time format", benchSimpleLog, &ctx, "ISO 8601 standard format", "Custom Features"));
    }

    {
        const logger = try Logger.init(allocator);
        defer logger.deinit();

        var config = Config.default();
        config.time_format = "unix_ms";
        config.auto_sink = false;
        logger.configure(config);

        _ = try logger.addSink(.{ .path = NULL_PATH });

        const ctx = BenchContext{ .logger = logger, .allocator = allocator };
        try results.append(allocator, runBenchmark("Unix timestamp (ms)", benchSimpleLog, &ctx, "Millisecond Unix timestamp", "Custom Features"));
    }

    // ============================================
    // CATEGORY: Configuration Presets
    // ============================================
    {
        std.debug.print("Running: Configuration presets benchmarks...\n", .{});

        // Full metadata
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
        try results.append(allocator, runBenchmark("Full metadata config", benchSimpleLog, &ctx, "Time + module + file + line", "Configuration Presets"));
    }

    {
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
        try results.append(allocator, runBenchmark("Minimal config", benchSimpleLog, &ctx, "No timestamp or module", "Configuration Presets"));
    }

    {
        const logger = try Logger.init(allocator);
        defer logger.deinit();

        var config = Config.production();
        config.auto_sink = false;
        logger.configure(config);

        _ = try logger.addSink(.{ .path = NULL_PATH, .json = true });

        const ctx = BenchContext{ .logger = logger, .allocator = allocator };
        try results.append(allocator, runBenchmark("Production preset", benchSimpleLog, &ctx, "JSON + sampling + metrics", "Configuration Presets"));
    }

    {
        const logger = try Logger.init(allocator);
        defer logger.deinit();

        var config = Config.development();
        config.auto_sink = false;
        logger.configure(config);

        _ = try logger.addSink(.{ .path = NULL_PATH });

        const ctx = BenchContext{ .logger = logger, .allocator = allocator };
        try results.append(allocator, runBenchmark("Development preset", benchSimpleLog, &ctx, "Debug + source location", "Configuration Presets"));
    }

    {
        const logger = try Logger.init(allocator);
        defer logger.deinit();

        var config = Config.highThroughput();
        config.auto_sink = false;
        logger.configure(config);

        _ = try logger.addSink(.{ .path = NULL_PATH });

        const ctx = BenchContext{ .logger = logger, .allocator = allocator };
        try results.append(allocator, runBenchmark("High throughput preset", benchSimpleLog, &ctx, "Async + thread pool + sampling", "Configuration Presets"));
    }

    {
        const logger = try Logger.init(allocator);
        defer logger.deinit();

        var config = Config.secure();
        config.auto_sink = false;
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
        config.auto_sink = false;
        logger.configure(config);

        _ = try logger.addSink(.{ .path = NULL_PATH });
        _ = try logger.addSink(.{ .path = NULL_PATH, .json = true });
        _ = try logger.addSink(.{ .path = NULL_PATH, .json = true, .pretty_json = true });

        const ctx = BenchContext{ .logger = logger, .allocator = allocator };
        try results.append(allocator, runBenchmark("Multiple sinks (3)", benchSimpleLog, &ctx, "Text + JSON + Pretty", "Configuration Presets"));
    }

    // ============================================
    // CATEGORY: Allocator Comparison
    // ============================================
    {
        std.debug.print("Running: Allocator comparison benchmarks...\n", .{});

        // Standard allocator (GPA)
        const loggerStd = try Logger.init(allocator);
        defer loggerStd.deinit();

        var configStd = Config.default();
        configStd.use_arena_allocator = false;
        configStd.auto_sink = false;
        loggerStd.configure(configStd);

        _ = try loggerStd.addSink(.{ .path = NULL_PATH });

        const ctxStd = BenchContext{ .logger = loggerStd, .allocator = allocator };
        try results.append(allocator, runBenchmark("Standard allocator (GPA)", benchSimpleLog, &ctxStd, "Default allocation", "Allocator Comparison"));
        try results.append(allocator, runBenchmark("Standard allocator (formatted)", benchFormattedLog, &ctxStd, "GPA with formatting", "Allocator Comparison"));
    }

    {
        // Arena allocator
        const loggerArena = try Logger.initWithConfig(allocator, Config.default().withArenaAllocation());
        defer loggerArena.deinit();

        var configArena = loggerArena.config;
        configArena.auto_sink = false;
        loggerArena.configure(configArena);

        _ = try loggerArena.addSink(.{ .path = NULL_PATH });

        const ctxArena = BenchContext{ .logger = loggerArena, .allocator = allocator };
        try results.append(allocator, runBenchmark("Arena allocator", benchSimpleLog, &ctxArena, "Reduced alloc overhead", "Allocator Comparison"));
        try results.append(allocator, runBenchmark("Arena allocator (formatted)", benchFormattedLog, &ctxArena, "Arena with formatting", "Allocator Comparison"));
    }

    {
        // Page allocator comparison
        const page_alloc = std.heap.page_allocator;
        const loggerPage = try Logger.init(page_alloc);
        defer loggerPage.deinit();

        var configPage = Config.default();
        configPage.auto_sink = false;
        loggerPage.configure(configPage);

        _ = try loggerPage.addSink(.{ .path = NULL_PATH });

        const ctxPage = BenchContext{ .logger = loggerPage, .allocator = page_alloc };
        try results.append(allocator, runBenchmark("Page allocator", benchSimpleLog, &ctxPage, "System page allocator", "Allocator Comparison"));
    }

    // ============================================
    // CATEGORY: Enterprise Features
    // ============================================
    {
        std.debug.print("Running: Enterprise features benchmarks...\n", .{});

        // Context binding benchmark
        const logger = try Logger.init(allocator);
        defer logger.deinit();

        var config = Config.default();
        config.auto_sink = false;
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
        config.enable_tracing = true;
        config.auto_sink = false;
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
        config.enable_metrics = true;
        config.auto_sink = false;
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
        config.json = true;
        config.auto_sink = false;
        logger.configure(config);

        _ = try logger.addSink(.{ .path = NULL_PATH, .json = true });

        const ctx = BenchContext{ .logger = logger, .allocator = allocator };
        try results.append(allocator, runBenchmark("Structured logging", benchSimpleLog, &ctx, "JSON structured output", "Enterprise Features"));
    }

    // ============================================
    // CATEGORY: Sampling & Rate Limiting
    // ============================================
    {
        std.debug.print("Running: Sampling & rate limiting benchmarks...\n", .{});

        // Probability sampling
        const loggerProb = try Logger.init(allocator);
        defer loggerProb.deinit();

        var configProb = Config.default();
        configProb.sampling = .{ .enabled = true, .strategy = .{ .probability = 0.5 } };
        configProb.auto_sink = false;
        loggerProb.configure(configProb);

        _ = try loggerProb.addSink(.{ .path = NULL_PATH });

        const ctxProb = BenchContext{ .logger = loggerProb, .allocator = allocator };
        try results.append(allocator, runBenchmark("Sampling (50% probability)", benchSimpleLog, &ctxProb, "Probability sampling", "Sampling & Rate Limiting"));
    }

    {
        // Rate limit sampling
        const loggerRate = try Logger.init(allocator);
        defer loggerRate.deinit();

        var configRate = Config.default();
        configRate.sampling = .{ .enabled = true, .strategy = .{ .rate_limit = .{ .max_records = 100, .window_ms = 1000 } } };
        configRate.auto_sink = false;
        loggerRate.configure(configRate);

        _ = try loggerRate.addSink(.{ .path = NULL_PATH });

        const ctxRate = BenchContext{ .logger = loggerRate, .allocator = allocator };
        try results.append(allocator, runBenchmark("Sampling (rate limit)", benchSimpleLog, &ctxRate, "Rate-based sampling", "Sampling & Rate Limiting"));
    }

    {
        // Adaptive sampling
        const loggerAdapt = try Logger.init(allocator);
        defer loggerAdapt.deinit();

        var configAdapt = Config.default();
        configAdapt.sampling = .{ .enabled = true, .strategy = .{ .adaptive = .{ .target_rate = 1000 } } };
        configAdapt.auto_sink = false;
        loggerAdapt.configure(configAdapt);

        _ = try loggerAdapt.addSink(.{ .path = NULL_PATH });

        const ctxAdapt = BenchContext{ .logger = loggerAdapt, .allocator = allocator };
        try results.append(allocator, runBenchmark("Sampling (adaptive)", benchSimpleLog, &ctxAdapt, "Adaptive sampling", "Sampling & Rate Limiting"));
    }

    {
        // Every-N sampling
        const loggerN = try Logger.init(allocator);
        defer loggerN.deinit();

        var configN = Config.default();
        configN.sampling = .{ .enabled = true, .strategy = .{ .every_n = 100 } };
        configN.auto_sink = false;
        loggerN.configure(configN);

        _ = try loggerN.addSink(.{ .path = NULL_PATH });

        const ctxN = BenchContext{ .logger = loggerN, .allocator = allocator };
        try results.append(allocator, runBenchmark("Sampling (every-N)", benchSimpleLog, &ctxN, "Every-N message sampling", "Sampling & Rate Limiting"));
    }

    {
        // Rate limiting
        const loggerRL = try Logger.init(allocator);
        defer loggerRL.deinit();

        var configRL = Config.default();
        configRL.rate_limit = .{ .enabled = true, .max_per_second = 10000, .burst_size = 100 };
        configRL.auto_sink = false;
        loggerRL.configure(configRL);

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
        configRedact.auto_sink = false;
        loggerRedact.configure(configRedact);

        _ = try loggerRedact.addSink(.{ .path = NULL_PATH });

        const ctxRedact = BenchContext{ .logger = loggerRedact, .allocator = allocator };
        try results.append(allocator, runBenchmark("With redaction enabled", benchSimpleLog, &ctxRedact, "Sensitive data masking", "Sampling & Rate Limiting"));
    }

    // ============================================
    // CATEGORY: Filtering
    // ============================================
    {
        std.debug.print("Running: Filtering benchmarks...\n", .{});

        const loggerFilter = try Logger.init(allocator);
        defer loggerFilter.deinit();

        var configFilter = Config.default();
        configFilter.auto_sink = false;
        loggerFilter.configure(configFilter);

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

    // ============================================
    // CATEGORY: Rules Engine
    // ============================================
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
        configRules.auto_sink = false;
        configRules.rules = .{
            .enabled = true,
        };
        loggerRules.configure(configRules);

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
        configNoRules.auto_sink = false;
        configNoRules.rules = .{ .enabled = false };
        loggerNoRules.configure(configNoRules);

        _ = try loggerNoRules.addSink(.{ .path = NULL_PATH });

        const ctx = BenchContext{ .logger = loggerNoRules, .allocator = allocator };
        try results.append(allocator, runBenchmark("Rules engine (disabled)", benchSimpleLog, &ctx, "No rule evaluation", "Rules Engine"));
    }

    // ============================================
    // CATEGORY: Redaction
    // ============================================
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
        try fieldRedactor.addField("email", .partial_end);
        try fieldRedactor.addField("credit_card", .mask_middle);

        const fieldCtx = FieldRedactContext{ .redactor = &fieldRedactor, .allocator = allocator };
        try results.append(allocator, runBenchmark("Field redaction (full)", struct {
            fn bench(ctx: *const FieldRedactContext) !void {
                try ctx.benchFieldRedact();
            }
        }.bench, &fieldCtx, "Full field masking", "Redaction"));
    }

    // ============================================
    // CATEGORY: Metrics
    // ============================================
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
            .track_levels = true,
            .track_latency = true,
            .enable_histogram = true,
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

    // ============================================
    // CATEGORY: Rotation
    // ============================================
    {
        std.debug.print("Running: Rotation benchmarks...\n", .{});

        const loggerRotation = try Logger.init(allocator);
        defer loggerRotation.deinit();

        var configRot = Config.default();
        configRot.auto_sink = false;
        loggerRotation.configure(configRot);

        // Add a sink with rotation
        _ = try loggerRotation.addSink(.{
            .path = NULL_PATH,
            .rotation = "daily",
            .size_limit = 1024 * 1024, // 1MB
            .retention = 5,
        });

        const ctxRot = BenchContext{ .logger = loggerRotation, .allocator = allocator };
        try results.append(allocator, runBenchmark("Rotation (size check)", benchSimpleLog, &ctxRot, "Size-based check", "Rotation"));
    }

    // ============================================
    // CATEGORY: System Diagnostics
    // ============================================
    {
        std.debug.print("Running: System Diagnostics benchmarks...\n", .{});

        const loggerDiag = try Logger.init(allocator);
        defer loggerDiag.deinit();

        var configDiag = Config.default();
        configDiag.auto_sink = false;
        configDiag.include_drive_diagnostics = false; // Keep it faster
        loggerDiag.configure(configDiag);

        _ = try loggerDiag.addSink(.{ .path = NULL_PATH });

        const ctxDiag = BenchContext{ .logger = loggerDiag, .allocator = allocator };
        try results.append(allocator, runBenchmark("System Diagnostics (basic)", benchDiagnostics, &ctxDiag, "OS/CPU/Mem info", "System Diagnostics"));
    }

    // ============================================
    // CATEGORY: Multi-Threading
    // ============================================
    {
        std.debug.print("Running: Multi-threading benchmarks...\n", .{});

        // Single-threaded baseline
        const logger1 = try Logger.init(allocator);
        defer logger1.deinit();

        var config1 = Config.default();
        config1.auto_sink = false;
        logger1.configure(config1);

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
        config2.auto_sink = false;
        logger2.configure(config2);

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
        config4.auto_sink = false;
        logger4.configure(config4);

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
        config8.auto_sink = false;
        logger8.configure(config8);

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
        config16.auto_sink = false;
        logger16.configure(config16);

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
        configJson.json = true;
        configJson.auto_sink = false;
        loggerJson.configure(configJson);

        _ = try loggerJson.addSink(.{ .path = NULL_PATH, .json = true });

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
        configColor.auto_sink = false;
        loggerColor.configure(configColor);

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
        configFmt.auto_sink = false;
        loggerFmt.configure(configFmt);

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

    {
        // Multi-thread with arena allocator
        const loggerArena = try Logger.initWithConfig(allocator, Config.default().withArenaAllocation());
        defer loggerArena.deinit();

        var configArena = loggerArena.config;
        configArena.auto_sink = false;
        loggerArena.configure(configArena);

        _ = try loggerArena.addSink(.{ .path = NULL_PATH });

        try results.append(allocator, runMultiThreadBenchmark(
            "4 threads arena allocator",
            loggerArena,
            4,
            "Parallel with arena alloc",
            "Multi-Threading",
            allocator,
            multiThreadWorker,
        ));
    }

    // ============================================
    // CATEGORY: Performance Comparison
    // ============================================
    {
        std.debug.print("Running: Performance comparison benchmarks...\n", .{});

        // File output
        const loggerFile = try Logger.init(allocator);
        defer loggerFile.deinit();

        var configFile = Config.default();
        configFile.color = false;
        configFile.auto_sink = false;
        loggerFile.configure(configFile);

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
        configNoSample.auto_sink = false;
        loggerNoSample.configure(configNoSample);

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
        configComp.auto_sink = false;
        loggerComp.configure(configComp);

        _ = try loggerComp.addSink(.{ .path = NULL_PATH });

        const ctxComp = BenchContext{ .logger = loggerComp, .allocator = allocator };
        try results.append(allocator, runBenchmark("Compression enabled (fast)", benchSimpleLog, &ctxComp, "Deflate compression", "Performance Comparison"));
    }

    // Print all results to console
    printResults(results.items);

    // Summary Statistics
    std.debug.print("\n[BENCHMARK SUMMARY]\n", .{});
    std.debug.print("=" ** 60, .{});
    std.debug.print("\n", .{});

    var total_ops: f64 = 0;
    var max_ops: f64 = 0;
    var min_ops: f64 = std.math.floatMax(f64);
    var count: usize = 0;
    var max_name: []const u8 = "";
    var min_name: []const u8 = "";

    for (results.items) |r| {
        total_ops += r.ops_per_sec;
        count += 1;
        if (r.ops_per_sec > max_ops) {
            max_ops = r.ops_per_sec;
            max_name = r.name;
        }
        if (r.ops_per_sec < min_ops) {
            min_ops = r.ops_per_sec;
            min_name = r.name;
        }
    }

    const avg_ops = if (count > 0) total_ops / @as(f64, @floatFromInt(count)) else 0;
    const avg_latency = if (avg_ops > 0) 1_000_000_000.0 / avg_ops else 0;

    if (count > 0) {
        std.debug.print("\nTotal benchmarks run:     {d}\n", .{count});
        std.debug.print("Average throughput:       {d:.0} ops/sec\n", .{avg_ops});
        std.debug.print("Maximum throughput:       {d:.0} ops/sec ({s})\n", .{ max_ops, max_name });
        std.debug.print("Minimum throughput:       {d:.0} ops/sec ({s})\n", .{ min_ops, min_name });
        std.debug.print("Average latency:          {d:.0} ns\n", .{avg_latency});
    }

    std.debug.print("\n", .{});
    std.debug.print("=" ** 60, .{});
    std.debug.print("\n", .{});
    std.debug.print("[OK] Benchmarks completed successfully!\n\n", .{});

    // Write final Markdown report
    const md_file = std.fs.cwd().createFile("benchmark-results.md", .{}) catch |err| {
        std.debug.print("Warning: Could not create benchmark-results.md: {}\n", .{err});
        return;
    };
    defer md_file.close();

    const md_header =
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

    var header_buf: [1024]u8 = undefined;
    const header = std.fmt.bufPrint(&header_buf, md_header, .{
        @tagName(builtin.os.tag),
        @tagName(builtin.cpu.arch),
        WARMUP_ITERATIONS,
        BENCHMARK_ITERATIONS,
        MT_BENCHMARK_ITERATIONS,
    }) catch "";
    try md_file.writeAll(header);

    // Write categorized tables
    for (BenchmarkResult.categories) |cat| {
        var has_category = false;
        for (results.items) |r| {
            if (std.mem.eql(u8, r.category, cat)) {
                has_category = true;
                break;
            }
        }
        if (!has_category) continue;

        const cat_md = std.fmt.allocPrint(allocator,
            \\
            \\<details>
            \\<summary><strong>{s}</strong></summary>
            \\
            \\| Benchmark | Ops/sec (higher is better) | Avg Latency (ns) (lower is better) | Notes |
            \\| :--- | :--- | :--- | :--- |
            \\
        , .{cat}) catch continue;
        defer allocator.free(cat_md);
        try md_file.writeAll(cat_md);

        for (results.items) |r| {
            if (std.mem.eql(u8, r.category, cat)) {
                var line_buf: [1024]u8 = undefined;
                const line = std.fmt.bufPrint(&line_buf, "| {s} | {d:.0} | {d:.0} | {s} |\n", .{
                    r.name,
                    r.ops_per_sec,
                    r.avg_latency_ns,
                    r.notes,
                }) catch continue;
                try md_file.writeAll(line);
            }
        }
        try md_file.writeAll("</details>\n");
    }

    // Write summary to Markdown
    if (count > 0) {
        try md_file.writeAll("\n### 📈 Benchmark Summary\n\n");
        var summary_buf: [1024]u8 = undefined;
        const summary = std.fmt.bufPrint(&summary_buf,
            \\- **Total benchmarks run:** {d}
            \\- **Average throughput:** {d:.0} ops/sec
            \\- **Maximum throughput:** {d:.0} ops/sec ({s})
            \\- **Minimum throughput:** {d:.0} ops/sec ({s})
            \\- **Average latency:** {d:.0} ns
            \\
        , .{ count, avg_ops, max_ops, max_name, min_ops, min_name, avg_latency }) catch "";
        try md_file.writeAll(summary);
    }

    try md_file.writeAll("\n---\n");
}
