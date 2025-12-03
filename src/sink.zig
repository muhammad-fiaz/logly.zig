const std = @import("std");
const Level = @import("level.zig").Level;
const Record = @import("record.zig").Record;
const Formatter = @import("formatter.zig").Formatter;
const Rotation = @import("rotation.zig").Rotation;

/// Configuration for a specific log sink.
///
/// Sinks are destinations where logs are written (e.g., console, file).
/// Each sink can have its own configuration, overriding global settings.
pub const SinkConfig = struct {
    /// File path for the sink. If null, defaults to console output.
    path: ?[]const u8 = null,

    /// Sink identifier name for metrics and debugging.
    name: ?[]const u8 = null,

    /// Rotation settings: "minutely", "hourly", "daily", "weekly", "monthly", "yearly".
    rotation: ?[]const u8 = null,

    /// Size limit for rotation (in bytes).
    size_limit: ?u64 = null,

    /// Size limit as a string (e.g., "10MB", "1GB").
    size_limit_str: ?[]const u8 = null,

    /// Number of rotated files to keep.
    retention: ?usize = null,

    /// Sink-specific log level. Overrides the global level if set.
    level: ?Level = null,

    /// Maximum log level for this sink (create level range filters).
    max_level: ?Level = null,

    /// Enable async writing with background buffering.
    async_write: bool = true,

    /// Buffer size for async writing in bytes.
    buffer_size: usize = 8192,

    /// Force JSON output for this sink.
    json: bool = false,

    /// Pretty print JSON output with indentation.
    pretty_json: bool = false,

    /// Enable/disable colors for this sink.
    /// If null, auto-detect (enabled for console, disabled for files).
    color: ?bool = null,

    /// Enable/disable this sink initially.
    enabled: bool = true,

    /// Include timestamp in output.
    include_timestamp: bool = true,

    /// Include log level in output.
    include_level: bool = true,

    /// Include source location in output.
    include_source: bool = false,

    /// Include trace IDs in output (for distributed tracing).
    include_trace_id: bool = false,

    /// Custom log format string for this sink.
    /// Overrides global format if set.
    log_format: ?[]const u8 = null,

    /// Time format for this sink.
    time_format: ?[]const u8 = null,

    /// Compression settings for file sinks.
    compression: CompressionConfig = .{},

    /// Filter configuration for this sink.
    filter: FilterConfig = .{},

    /// Error handling for this sink.
    on_error: ErrorBehavior = .log_stderr,

    /// Maximum records to buffer before forcing a flush.
    max_buffer_records: usize = 1000,

    /// Flush interval in milliseconds.
    flush_interval_ms: u64 = 1000,

    /// File permissions for created log files (Unix only).
    file_mode: ?u32 = null,

    /// Compression configuration.
    pub const CompressionConfig = struct {
        enabled: bool = false,
        algorithm: Algorithm = .gzip,
        level: u4 = 6,

        pub const Algorithm = enum {
            none,
            gzip,
            zstd,
        };
    };

    /// Filter configuration for sink-level filtering.
    pub const FilterConfig = struct {
        /// Include only logs from these modules.
        include_modules: ?[]const []const u8 = null,

        /// Exclude logs from these modules.
        exclude_modules: ?[]const []const u8 = null,

        /// Include only logs containing these substrings.
        include_messages: ?[]const []const u8 = null,

        /// Exclude logs containing these substrings.
        exclude_messages: ?[]const []const u8 = null,
    };

    /// Error behavior for sink write failures.
    pub const ErrorBehavior = enum {
        /// Silently ignore errors.
        silent,

        /// Log errors to stderr.
        log_stderr,

        /// Disable the sink on error.
        disable_sink,

        /// Propagate the error to the caller.
        propagate,
    };

    /// Returns the default sink configuration (Console, async, standard format).
    pub fn default() SinkConfig {
        return .{};
    }

    /// Returns a file sink configuration.
    ///
    /// Arguments:
    ///     file_path: Path to the log file.
    ///
    /// Returns:
    ///     A SinkConfig configured for file output.
    pub fn file(file_path: []const u8) SinkConfig {
        return .{
            .path = file_path,
            .color = false,
        };
    }

    /// Returns a JSON file sink configuration.
    ///
    /// Arguments:
    ///     file_path: Path to the log file.
    ///
    /// Returns:
    ///     A SinkConfig configured for JSON file output.
    pub fn jsonFile(file_path: []const u8) SinkConfig {
        return .{
            .path = file_path,
            .json = true,
            .color = false,
        };
    }

    /// Returns a rotating file sink configuration.
    ///
    /// Arguments:
    ///     file_path: Path to the log file.
    ///     rotation_interval: Rotation interval string.
    ///     retention_count: Number of files to retain.
    ///
    /// Returns:
    ///     A SinkConfig configured for rotating file output.
    pub fn rotating(file_path: []const u8, rotation_interval: []const u8, retention_count: usize) SinkConfig {
        return .{
            .path = file_path,
            .rotation = rotation_interval,
            .retention = retention_count,
            .color = false,
        };
    }

    /// Returns an error-only sink configuration.
    ///
    /// Arguments:
    ///     file_path: Path to the error log file.
    ///
    /// Returns:
    ///     A SinkConfig configured to only capture error-level and above.
    pub fn errorOnly(file_path: []const u8) SinkConfig {
        return .{
            .path = file_path,
            .level = .err,
            .color = false,
        };
    }
};

fn parseSize(s: []const u8) ?u64 {
    var end: usize = 0;
    while (end < s.len and std.ascii.isDigit(s[end])) : (end += 1) {}

    if (end == 0) return null;

    const num = std.fmt.parseInt(u64, s[0..end], 10) catch return null;

    // Skip whitespace
    var unit_start = end;
    while (unit_start < s.len and std.ascii.isWhitespace(s[unit_start])) : (unit_start += 1) {}

    if (unit_start >= s.len) return num; // Default to bytes if no unit

    const unit = s[unit_start..];

    if (std.ascii.eqlIgnoreCase(unit, "B")) return num;
    if (std.ascii.eqlIgnoreCase(unit, "KB") or std.ascii.eqlIgnoreCase(unit, "K")) return num * 1024;
    if (std.ascii.eqlIgnoreCase(unit, "MB") or std.ascii.eqlIgnoreCase(unit, "M")) return num * 1024 * 1024;
    if (std.ascii.eqlIgnoreCase(unit, "GB") or std.ascii.eqlIgnoreCase(unit, "G")) return num * 1024 * 1024 * 1024;
    if (std.ascii.eqlIgnoreCase(unit, "TB") or std.ascii.eqlIgnoreCase(unit, "T")) return num * 1024 * 1024 * 1024 * 1024;

    return num;
}

pub const Sink = struct {
    allocator: std.mem.Allocator,
    config: SinkConfig,
    file: ?std.fs.File = null,
    formatter: Formatter,
    rotation: ?Rotation = null,
    buffer: std.ArrayList(u8),
    mutex: std.Thread.Mutex = .{},
    enabled: bool = true,
    json_first_entry: bool = true, // Track if this is the first JSON entry for file output

    pub fn init(allocator: std.mem.Allocator, config: SinkConfig) !*Sink {
        const sink = try allocator.create(Sink);
        sink.* = .{
            .allocator = allocator,
            .config = config,
            .formatter = Formatter.init(allocator),
            .buffer = .empty,
            .enabled = config.enabled,
            .json_first_entry = true,
        };
        errdefer sink.deinit();

        if (config.path) |path| {
            const dir = std.fs.path.dirname(path);
            if (dir) |d| {
                try std.fs.cwd().makePath(d);
            }

            sink.file = try std.fs.cwd().createFile(path, .{
                .read = true,
                .truncate = false,
            });

            // Write opening bracket for JSON array files
            if (config.json) {
                if (sink.file) |file| {
                    try file.writeAll("[\n");
                }
            }

            var size_limit = config.size_limit;
            if (size_limit == null and config.size_limit_str != null) {
                size_limit = parseSize(config.size_limit_str.?);
            }

            if (config.rotation != null or size_limit != null) {
                sink.rotation = try Rotation.init(
                    allocator,
                    path,
                    config.rotation,
                    size_limit,
                    config.retention,
                );
            }
        }

        return sink;
    }

    pub fn deinit(self: *Sink) void {
        self.flush() catch {};
        // Write closing bracket for JSON array files
        if (self.config.json and self.file != null) {
            if (self.file) |file| {
                file.writeAll("\n]") catch {};
            }
        }
        if (self.file) |f| f.close();
        if (self.rotation) |*r| r.deinit();
        self.buffer.deinit(self.allocator);
        self.formatter.deinit();
        self.allocator.destroy(self);
    }

    pub fn write(self: *Sink, record: *const Record, global_config: anytype) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (!self.enabled) return;

        // Check level filtering
        if (self.config.level) |min_level| {
            if (record.level.priority() < min_level.priority()) {
                return;
            }
        }

        // Check rotation
        if (self.rotation) |*rot| {
            if (self.file) |*f| {
                try rot.checkAndRotate(f);
            }
        }

        // Determine effective config for this sink
        // We need to create a new config struct that overrides specific fields
        var effective_config = global_config;

        // Override JSON setting
        if (self.config.json) {
            effective_config.json = true;
        }
        if (self.config.pretty_json) {
            effective_config.pretty_json = true;
        }

        // Override Color setting
        // If sink is a file, default color to false unless explicitly enabled
        if (self.config.color) |c| {
            effective_config.global_color_display = c;
        } else if (self.file != null) {
            // Default to no color for files
            effective_config.global_color_display = false;
        }

        // Format the message
        const formatted = if (effective_config.json)
            try self.formatter.formatJson(record, effective_config)
        else
            try self.formatter.format(record, effective_config);
        defer self.allocator.free(formatted);

        // Write to console or file
        if (self.file) |file| {
            if (global_config.global_file_storage) {
                // For JSON file output, add comma separator between entries
                const is_json_file = effective_config.json and self.file != null;

                if (self.config.async_write) {
                    // Add comma before entry if not first (for JSON files)
                    if (is_json_file and !self.json_first_entry) {
                        try self.buffer.appendSlice(self.allocator, ",\n");
                    }
                    try self.buffer.appendSlice(self.allocator, formatted);
                    if (!is_json_file) {
                        try self.buffer.append(self.allocator, '\n');
                    }
                    if (is_json_file) {
                        self.json_first_entry = false;
                    }
                    if (self.buffer.items.len >= self.config.buffer_size) {
                        try self.flush();
                    }
                } else {
                    // Add comma before entry if not first (for JSON files)
                    if (is_json_file and !self.json_first_entry) {
                        try file.writeAll(",\n");
                    }
                    try file.writeAll(formatted);
                    if (!is_json_file) {
                        try file.writeAll("\n");
                    }
                    if (is_json_file) {
                        self.json_first_entry = false;
                    }
                }
            }
        } else {
            // Console output
            if (global_config.global_console_display) {
                var stdout_buffer: [4096]u8 = undefined;
                var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
                const stdout = &stdout_writer.interface;
                try stdout.writeAll(formatted);
                try stdout.writeAll("\n");
                try stdout.flush();
            }
        }
    }

    pub fn flush(self: *Sink) !void {
        if (self.buffer.items.len == 0) return;
        if (self.file) |file| {
            try file.writeAll(self.buffer.items);
            self.buffer.clearRetainingCapacity();
        }
    }
};
