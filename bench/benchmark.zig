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
};

/// Number of warmup iterations
const WARMUP_ITERATIONS: u64 = 100;

/// Number of benchmark iterations
const BENCHMARK_ITERATIONS: u64 = 10_000;

/// Number of iterations for multi-thread benchmarks
const MT_BENCHMARK_ITERATIONS: u64 = 5_000;

/// Null device path for discarding output
const NULL_PATH = if (builtin.os.tag == .windows) "NUL" else "/dev/null";

/// Print benchmark results in a formatted table by category
fn printResults(results: []const BenchmarkResult) void {
    std.debug.print("\n", .{});
    std.debug.print("=" ** 130, .{});
    std.debug.print("\n", .{});
    std.debug.print("                                      LOGLY-ZIG BENCHMARK RESULTS (v0.0.4)\n", .{});
    std.debug.print("=" ** 130, .{});
    std.debug.print("\n", .{});

    // Group by category - using ASCII instead of Unicode emojis
    const categories = [_][]const u8{
        "Basic Logging",
        "JSON Logging",
        "Log Levels",
        "Custom Features",
        "Configuration Presets",
        "Allocator Comparison",
        "Enterprise Features",
        "Sampling & Rate Limiting",
        "Multi-Threading",
        "Performance Comparison",
    };

    for (categories) |cat| {
        var has_category = false;
        for (results) |r| {
            if (std.mem.eql(u8, r.category, cat)) {
                has_category = true;
                break;
            }
        }
        if (!has_category) continue;

        std.debug.print("\n[{s}]\n", .{cat});
        std.debug.print("-" ** 130, .{});
        std.debug.print("\n", .{});
        std.debug.print("{s:<50} {s:>12} {s:>18} {s:>45}\n", .{ "Benchmark", "Ops/sec", "Avg Latency (ns)", "Notes" });
        std.debug.print("-" ** 130, .{});
        std.debug.print("\n", .{});

        for (results) |r| {
            if (std.mem.eql(u8, r.category, cat)) {
                std.debug.print("{s:<50} {d:>12.0} {d:>18.0} {s:>45}\n", .{
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

    // Enable ANSI colors for Windows console
    _ = logly.Terminal.enableAnsiColors();

    std.debug.print("\n", .{});
    std.debug.print("================================================================================\n", .{});
    std.debug.print("                  LOGLY-ZIG COMPREHENSIVE BENCHMARKS (v0.0.4)\n", .{});
    std.debug.print("================================================================================\n", .{});
    std.debug.print("   Platform: {s}\n", .{@tagName(builtin.os.tag)});
    std.debug.print("   Architecture: {s}\n", .{@tagName(builtin.cpu.arch)});
    std.debug.print("   Warmup iterations: {d}\n", .{WARMUP_ITERATIONS});
    std.debug.print("   Benchmark iterations: {d}\n", .{BENCHMARK_ITERATIONS});
    std.debug.print("   Multi-thread iterations: {d} per thread\n", .{MT_BENCHMARK_ITERATIONS});
    std.debug.print("================================================================================\n\n", .{});

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
        configProb.sampling = .{ .enabled = true, .rate = 0.5, .strategy = .probability };
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
        configRate.sampling = .{ .enabled = true, .strategy = .rate_limit };
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
        configAdapt.sampling = .{ .enabled = true, .strategy = .adaptive, .rate = 0.8 };
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
        configN.sampling = .{ .enabled = true, .strategy = .every_n };
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

    // Print all results
    printResults(results.items);

    // Print summary statistics
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

    if (count > 0) {
        const avg_ops = total_ops / @as(f64, @floatFromInt(count));
        std.debug.print("\nTotal benchmarks run:     {d}\n", .{count});
        std.debug.print("Average throughput:       {d:.0} ops/sec\n", .{avg_ops});
        std.debug.print("Maximum throughput:       {d:.0} ops/sec ({s})\n", .{ max_ops, max_name });
        std.debug.print("Minimum throughput:       {d:.0} ops/sec ({s})\n", .{ min_ops, min_name });
        std.debug.print("Average latency:          {d:.0} ns\n", .{1_000_000_000.0 / avg_ops});
    }

    std.debug.print("\n", .{});
    std.debug.print("=" ** 60, .{});
    std.debug.print("\n", .{});
    std.debug.print("[OK] Benchmarks completed successfully!\n\n", .{});

    // Print markdown table for README
    std.debug.print("\n[MARKDOWN TABLE FOR README.md]\n", .{});
    std.debug.print("=" ** 60, .{});
    std.debug.print("\n\n", .{});
    std.debug.print("| Benchmark | Ops/sec | Avg Latency (ns) | Notes |\n", .{});
    std.debug.print("|-----------|---------|------------------|-------|\n", .{});
    for (results.items) |r| {
        std.debug.print("| {s} | {d:.0} | {d:.0} | {s} |\n", .{
            r.name,
            r.ops_per_sec,
            r.avg_latency_ns,
            r.notes,
        });
    }
    std.debug.print("\n", .{});
}
