const std = @import("std");
const Level = @import("level.zig").Level;

pub const Config = struct {
    // Log level filtering
    level: Level = .info,

    // Global display controls
    global_color_display: bool = true,
    global_console_display: bool = true,
    global_file_storage: bool = true,

    // Color settings
    color: bool = true,

    // Output format
    json: bool = false,
    pretty_json: bool = false,
    log_compact: bool = false,

    // Display options
    console: bool = true,
    show_time: bool = true,
    show_module: bool = true,
    show_function: bool = false,
    show_filename: bool = false,
    show_lineno: bool = false,

    // Sink management
    auto_sink: bool = true,

    // Features
    enable_callbacks: bool = true,
    enable_exception_handling: bool = true,
    enable_version_check: bool = false,

    // Debug mode
    debug_mode: bool = false,
    debug_log_file: ?[]const u8 = null,

    pub fn default() Config {
        return .{};
    }
};
