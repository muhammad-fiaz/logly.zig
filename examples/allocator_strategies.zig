//! Allocator Strategies Example.
//!
//! Demonstrates using different allocators with Logly.zig:
//! - std.heap.DebugAllocator (development / leak tracking)
//! - std.heap.ArenaAllocator (batch processing / fast cleanup)
//! - std.heap.page_allocator (direct OS page allocation)

const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    std.debug.print("\n=== Allocator Strategies Demo ===\n\n", .{});

    // 1. General Purpose / Debug Allocator (Standard development default)
    std.debug.print("1. Using std.heap.DebugAllocator:\n", .{});
    {
        var gpa = std.heap.DebugAllocator(.{}){};
        defer _ = gpa.deinit();
        const allocator = gpa.allocator();

        var config = logly.Config.default();
        config.color = false;
        const logger = try logly.Logger.initWithConfig(allocator, config);
        defer logger.deinit();

        try logger.info("Running with DebugAllocator", @src());
    }

    // 2. Arena Allocator (Fast bulk deallocation for short-lived scopes)
    std.debug.print("\n2. Using std.heap.ArenaAllocator:\n", .{});
    {
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const arena_allocator = arena.allocator();

        var config = logly.Config.default();
        config.color = false;
        const logger = try logly.Logger.initWithConfig(arena_allocator, config);
        // deinit on logger frees internal structures; arena.deinit frees everything at once
        defer logger.deinit();

        try logger.info("Running within an ArenaAllocator", @src());
        try logger.success("Batch log completed inside arena", null);
    }

    // 3. Direct Page Allocator (System memory allocations for dedicated processes)
    std.debug.print("\n3. Using std.heap.page_allocator:\n", .{});
    {
        const page_allocator = std.heap.page_allocator;

        var config = logly.Config.default();
        config.color = false;
        const logger = try logly.Logger.initWithConfig(page_allocator, config);
        defer logger.deinit();

        try logger.info("Running with page_allocator", null);
    }

    std.debug.print("\nAllocator Strategies Demo completed successfully!\n", .{});
}
