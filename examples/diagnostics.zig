const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Enable ANSI colors on Windows (no-op elsewhere)
    _ = logly.Terminal.enableAnsiColors();

    // ========== EXAMPLE 1: Auto-emit on init with colors ==========
    std.debug.print("Example 1: Auto-emit Diagnostics at Startup\n", .{});
    std.debug.print("─────────────────────────────────────────────────────────\n", .{});
    {
        var config = logly.Config.default();
        config.emit_system_diagnostics_on_init = true; // Emit during init
        config.include_drive_diagnostics = true; // Include drive info
        config.log_format = "[{level:>5}] {message}";
        config.use_colors = true; // Enable colors

        const logger = try logly.Logger.initWithConfig(allocator, config);
        defer logger.deinit();

        std.debug.print("\n✓ Diagnostics auto-emitted at logger initialization\n", .{});
    }

    // ========== EXAMPLE 2: Manual on-demand diagnostics ==========
    std.debug.print("\n\nExample 2: Manual On-Demand Diagnostics\n", .{});
    std.debug.print("─────────────────────────────────────────────────────────\n", .{});
    {
        var config = logly.Config.default();
        config.use_colors = true;
        config.log_format = "[{timestamp:s}] {level:>5} | {message}";

        const logger = try logly.Logger.initWithConfig(allocator, config);
        defer logger.deinit();

        // Emit diagnostics on demand
        try logger.logSystemDiagnostics(@src());
        std.debug.print("\n✓ Diagnostics emitted on-demand\n", .{});
    }

    // ========== EXAMPLE 3: With drive diagnostics ==========
    std.debug.print("\n\nExample 3: Diagnostics with Drive Information\n", .{});
    std.debug.print("─────────────────────────────────────────────────────────\n", .{});
    {
        var config = logly.Config.default();
        config.include_drive_diagnostics = true; // Include all drives
        config.use_colors = true;
        config.log_format = "[{level:>5}] {message}";

        const logger = try logly.Logger.initWithConfig(allocator, config);
        defer logger.deinit();

        try logger.logSystemDiagnostics(@src());
        std.debug.print("\n✓ Drive information included\n", .{});
    }

    // ========== EXAMPLE 4: Custom formatted diagnostics ==========
    std.debug.print("\n\nExample 4: Custom Format with Diagnostic Fields\n", .{});
    std.debug.print("─────────────────────────────────────────────────────────\n", .{});
    {
        var config = logly.Config.default();
        config.include_drive_diagnostics = false; // No drive info for cleaner output
        config.use_colors = true;
        // Custom format using diagnostic context fields
        config.log_format = "🖥️  {diag.os} | 🏗️  {diag.arch} | 💻 {diag.cpu} | ⚙️  Cores: {diag.cores}";

        const logger = try logly.Logger.initWithConfig(allocator, config);
        defer logger.deinit();

        try logger.logSystemDiagnostics(@src());
        std.debug.print("\n✓ Custom emoji format applied\n", .{});
    }

    // ========== EXAMPLE 5: Memory information format ==========
    std.debug.print("\n\nExample 5: Memory Information Format\n", .{});
    std.debug.print("─────────────────────────────────────────────────────────\n", .{});
    {
        var config = logly.Config.default();
        config.use_colors = true;
        // Format to show memory information
        config.log_format = "🧠 Total RAM: {diag.ram_total_mb} MB | Available: {diag.ram_avail_mb} MB";

        const logger = try logly.Logger.initWithConfig(allocator, config);
        defer logger.deinit();

        try logger.logSystemDiagnostics(@src());
        std.debug.print("\n✓ Memory information displayed\n", .{});
    }

    // ========== EXAMPLE 6: Table-style diagnostics ==========
    std.debug.print("\n\nExample 6: Comprehensive System Info Table\n", .{});
    std.debug.print("─────────────────────────────────────────────────────────\n", .{});
    {
        var config = logly.Config.default();
        config.include_drive_diagnostics = true;
        config.use_colors = true;

        const logger = try logly.Logger.initWithConfig(allocator, config);
        defer logger.deinit();

        // Collect and display diagnostics
        try logger.logSystemDiagnostics(@src());
        std.debug.print("\n✓ Full system diagnostics with drives displayed\n", .{});
    }

    // ========== EXAMPLE 7: Programmatic diagnostics collection ==========
    std.debug.print("\n\nExample 7: Programmatic Diagnostics Collection\n", .{});
    std.debug.print("─────────────────────────────────────────────────────────\n", .{});
    {
        // Collect diagnostics directly (without logger)
        var diagnostics = try logly.Diagnostics.collect(allocator, true);
        defer diagnostics.deinit(allocator);

        // Display collected information
        std.debug.print("\n📊 System Information:\n", .{});
        std.debug.print("  Operating System: {s}\n", .{diagnostics.os_tag});
        std.debug.print("  Architecture: {s}\n", .{diagnostics.arch});
        std.debug.print("  CPU Model: {s}\n", .{diagnostics.cpu_model});
        std.debug.print("  Logical Cores: {d}\n", .{diagnostics.logical_cores});

        if (diagnostics.total_mem) |total| {
            std.debug.print("  Total Memory: {d} MB ({d} GB)\n", .{ total / (1024 * 1024), total / (1024 * 1024 * 1024) });
        }

        if (diagnostics.avail_mem) |avail| {
            std.debug.print("  Available Memory: {d} MB ({d} GB)\n", .{ avail / (1024 * 1024), avail / (1024 * 1024 * 1024) });
        }

        if (diagnostics.drives.len > 0) {
            std.debug.print("\n  💾 Drives:\n", .{});
            for (diagnostics.drives) |drive| {
                const total_gb = @as(f64, @floatFromInt(drive.total_bytes)) / (1024.0 * 1024.0 * 1024.0);
                const free_gb = @as(f64, @floatFromInt(drive.free_bytes)) / (1024.0 * 1024.0 * 1024.0);
                const usage_pct = (1.0 - (@as(f64, @floatFromInt(drive.free_bytes)) / @as(f64, @floatFromInt(drive.total_bytes)))) * 100.0;

                std.debug.print("    {s}: {d:.1} GB / {d:.1} GB ({d:.1}% used)\n", .{ drive.name, free_gb, total_gb, usage_pct });
            }
        }

        std.debug.print("\n✓ Diagnostics collected and displayed\n", .{});
    }

    // ========== EXAMPLE 8: Color schemes ==========
    std.debug.print("\n\nExample 8: Different Color Schemes\n", .{});
    std.debug.print("─────────────────────────────────────────────────────────\n", .{});
    {
        var config = logly.Config.default();
        config.use_colors = true;
        config.log_level = .debug; // Show more detail
        config.log_format = "[{level:>5}] {timestamp:s} → {message}";

        const logger = try logly.Logger.initWithConfig(allocator, config);
        defer logger.deinit();

        try logger.info("System diagnostics with full coloring enabled", .{});
        try logger.logSystemDiagnostics(@src());
        std.debug.print("\n✓ Colors applied to all output\n", .{});
    }

    std.debug.print("Features demonstrated:\n", .{});
    std.debug.print("  ✓ Auto-emit diagnostics at logger init\n", .{});
    std.debug.print("  ✓ On-demand diagnostics collection\n", .{});
    std.debug.print("  ✓ Drive information (Windows/Linux)\n", .{});
    std.debug.print("  ✓ Custom formatting with diagnostic fields\n", .{});
    std.debug.print("  ✓ Memory information display\n", .{});
    std.debug.print("  ✓ Comprehensive system info table\n", .{});
    std.debug.print("  ✓ Programmatic diagnostics collection\n", .{});
    std.debug.print("  ✓ Color-coded output\n", .{});
    std.debug.print("\n", .{});
}
