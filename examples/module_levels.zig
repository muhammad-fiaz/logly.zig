const std = @import("std");
const logly = @import("logly");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const logger = try logly.Logger.init(allocator);
    defer logger.deinit();

    // Set global level to INFO
    var config = logly.Config.default();
    config.level = .info;
    config.showModule = true;
    logger.configure(config);

    // Create scoped loggers for different modules
    const netLogger = logger.scoped("network");
    const dbLogger = logger.scoped("database");
    const uiLogger = logger.scoped("ui");

    // Default behavior (INFO and above)
    try logger.info("Application started", @src());
    try netLogger.info("Network initialized", @src()); // Shows [network]
    try netLogger.debug("Network debug message", @src()); // Hidden (global level is INFO)

    // Set specific level for network module (allow DEBUG)
    try logger.setModuleLevel("network", .debug);
    try logger.info("Changed network module level to DEBUG", @src());

    try netLogger.debug("Network debug message (now visible)", @src());
    try dbLogger.debug("Database debug message", @src()); // Still hidden

    // Set specific level for UI module (only ERROR)
    try logger.setModuleLevel("ui", .err);
    try logger.info("Changed UI module level to ERROR", @src());

    try uiLogger.warning("UI warning", @src()); // Hidden
    try uiLogger.err("UI error", @src()); // Visible

    // Verify database still follows global
    try dbLogger.info("Database info", @src()); // Visible
}
