const std = @import("std");
const Level = @import("level.zig").Level;

/// Configuration options for the Logger.
///
/// This struct controls the global behavior of the logging system, including:
/// *   Log levels and filtering.
/// *   Output formatting (JSON, text, custom patterns).
/// *   Display options (colors, timestamps, file info).
/// *   Feature toggles (callbacks, exception handling).
pub const Config = struct {
    // 🎚️ Log level filtering: Only logs at this level or higher will be processed.
    level: Level = .info,

    // 🌍 Global display controls
    global_color_display: bool = true,
    global_console_display: bool = true,
    global_file_storage: bool = true,

    // 🎨 Color settings: Enable or disable ANSI color codes in output.
    color: bool = true,

    // 📝 Output format settings
    json: bool = false,
    pretty_json: bool = false,
    log_compact: bool = false,
    log_format: ?[]const u8 = null, // Custom format string, e.g. "[{time}] {level}: {message}"
    time_format: []const u8 = "YYYY-MM-DD HH:mm:ss",
    timezone: enum { Local, UTC } = .Local,

    // 👁️ Display options: Control what metadata is shown in the logs.
    console: bool = true,
    show_time: bool = true,
    show_module: bool = true,
    show_function: bool = false,
    show_filename: bool = false,
    show_lineno: bool = false,
    include_hostname: bool = false,
    include_pid: bool = false,

    // 🛁 Sink management
    auto_sink: bool = true,

    // ⚡ Features
    enable_callbacks: bool = true,
    enable_exception_handling: bool = true,
    enable_version_check: bool = false,

    // 🐛 Debug mode
    debug_mode: bool = false,
    debug_log_file: ?[]const u8 = null,

    /// Returns the default configuration.
    ///
    /// The default configuration is:
    /// *   Level: INFO
    /// *   Output: Console with colors
    /// *   Format: Standard text
    /// *   Features: Callbacks and exception handling enabled
    pub fn default() Config {
        return .{};
    }
};
