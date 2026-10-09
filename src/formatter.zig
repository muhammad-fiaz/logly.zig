//! Record formatting.
//!
//! Renders records as text, JSON, or custom templates for display or storage.
const std = @import("std");
const Config = @import("config.zig").Config;
const Record = @import("record.zig").Record;
const Level = @import("level.zig").Level;
const Constants = @import("constants.zig");
const Utils = @import("utils.zig");
const Color = @import("color.zig");

/// Handles the formatting of log records into strings or JSON.
pub const Formatter = struct {
    /// Formatter statistics for monitoring and diagnostics.
    pub const FormatterStats = struct {
        totalRecordsFormatted: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        jsonFormats: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        customFormats: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        formatErrors: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        totalBytesFormatted: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),

        /// Get total records formatted.
        pub fn getTotalFormatted(self: *const FormatterStats) u64 {
            return Utils.atomicLoadU64(&self.totalRecordsFormatted);
        }

        /// Get total JSON formats.
        pub fn getJsonFormats(self: *const FormatterStats) u64 {
            return Utils.atomicLoadU64(&self.jsonFormats);
        }

        /// Get total custom formats.
        pub fn getCustomFormats(self: *const FormatterStats) u64 {
            return Utils.atomicLoadU64(&self.customFormats);
        }

        /// Get total format errors.
        pub fn getFormatErrors(self: *const FormatterStats) u64 {
            return Utils.atomicLoadU64(&self.formatErrors);
        }

        /// Get total bytes formatted.
        pub fn getTotalBytesFormatted(self: *const FormatterStats) u64 {
            return Utils.atomicLoadU64(&self.totalBytesFormatted);
        }

        /// Get plain text formats (total - json - custom).
        pub fn getPlainFormats(self: *const FormatterStats) u64 {
            const total = Utils.atomicLoadU64(&self.totalRecordsFormatted);
            const jsonCount = Utils.atomicLoadU64(&self.jsonFormats);
            const customCount = Utils.atomicLoadU64(&self.customFormats);
            if (total > jsonCount + customCount) {
                return total - jsonCount - customCount;
            }
            return 0;
        }

        /// Check if any records have been formatted.
        pub fn hasFormatted(self: *const FormatterStats) bool {
            return Utils.atomicLoadU64(&self.totalRecordsFormatted) > 0;
        }

        /// Check if any JSON formats have been used.
        pub fn hasJsonFormats(self: *const FormatterStats) bool {
            return Utils.atomicLoadU64(&self.jsonFormats) > 0;
        }

        /// Check if any custom formats have been used.
        pub fn hasCustomFormats(self: *const FormatterStats) bool {
            return Utils.atomicLoadU64(&self.customFormats) > 0;
        }

        /// Check if any format errors have occurred.
        pub fn hasErrors(self: *const FormatterStats) bool {
            return Utils.atomicLoadU64(&self.formatErrors) > 0;
        }

        /// Calculate JSON format usage rate (0.0 - 1.0).
        pub fn jsonUsageRate(self: *const FormatterStats) f64 {
            return Utils.calculateRate(
                self.getJsonFormats(),
                self.getTotalFormatted(),
            );
        }

        /// Calculate custom format usage rate (0.0 - 1.0).
        pub fn customUsageRate(self: *const FormatterStats) f64 {
            return Utils.calculateRate(
                self.getCustomFormats(),
                self.getTotalFormatted(),
            );
        }

        /// Calculate average format size
        pub fn avgFormatSize(self: *const FormatterStats) f64 {
            return Utils.calculateAverage(
                self.getTotalBytesFormatted(),
                self.getTotalFormatted(),
            );
        }

        /// Calculate error rate (0.0 - 1.0)
        pub fn errorRate(self: *const FormatterStats) f64 {
            return Utils.calculateErrorRate(
                self.getFormatErrors(),
                self.getTotalFormatted(),
            );
        }

        /// Calculate success rate (0.0 - 1.0).
        pub fn successRate(self: *const FormatterStats) f64 {
            return 1.0 - self.errorRate();
        }

        /// Calculate throughput (bytes per second).
        pub fn throughputBytesPerSecond(self: *const FormatterStats, elapsedSeconds: f64) f64 {
            return Utils.safeFloatDiv(
                @as(f64, @floatFromInt(Utils.atomicLoadU64(&self.totalBytesFormatted))),
                elapsedSeconds,
            );
        }

        /// Reset all statistics to initial state.
        pub fn reset(self: *FormatterStats) void {
            self.totalRecordsFormatted.store(0, .monotonic);
            self.jsonFormats.store(0, .monotonic);
            self.customFormats.store(0, .monotonic);
            self.formatErrors.store(0, .monotonic);
            self.totalBytesFormatted.store(0, .monotonic);
        }
    };

    /// Memory allocator for formatting operations.
    allocator: std.mem.Allocator,
    /// Formatter statistics.
    stats: FormatterStats = .{},
    /// Mutex for thread-safe operations.
    mutex: std.Io.Mutex = std.Io.Mutex.init,
    /// I/O handle for synchronization and debug symbol resolution.
    io: std.Io = Utils.defaultIo(),

    /// Cached hostname of the current machine.
    hostname: ?[]const u8 = null,

    /// Cached process ID.
    pid: usize = 0,

    /// Cached debug info for stack trace symbolization.
    /// Loaded lazily upon first request for symbolization.
    debugInfo: ?*std.debug.SelfInfo = null,

    /// Callback invoked after a record is formatted.
    onFormatComplete: ?*const fn (u32, u64) void = null,

    /// Callback invoked when formatting as JSON.
    onJsonFormat: ?*const fn (*const Record, u64) void = null,

    /// Callback invoked when using custom format.
    onCustomFormat: ?*const fn ([]const u8, u64) void = null,

    /// Callback invoked on formatting error.
    onFormatError: ?*const fn ([]const u8) void = null,

    /// Custom color theme for log levels.
    theme: ?Theme = null,

    /// Color style mode for output.
    colorStyle: ColorStyle = .default,

    /// Custom level color overrides.
    levelColorOverrides: ?*const std.StringHashMap([]const u8) = null,

    /// Color style options.
    pub const ColorStyle = enum {
        default,
        bright,
        dim,
        color256,
        minimal,
        neon,
        pastel,
        dark,
        light,
    };

    /// Defines a color theme for log levels, backed by tint.zig.
    ///
    /// Each field is a tint `Color` value (plain data, no allocation).
    /// Render with `color.sequence(color, capability)` and write
    /// `Sequence.slice()` to the sink.
    pub const Theme = struct {
        trace: Color.Color = Color.Tint.color.ansi4.cyan,
        debug: Color.Color = Color.Tint.color.ansi4.blue,
        info: Color.Color = Color.Tint.color.ansi4.white,
        notice: Color.Color = Color.Tint.color.ansi4.brightCyan,
        success: Color.Color = Color.Tint.color.ansi4.green,
        warning: Color.Color = Color.Tint.color.ansi4.yellow,
        err: Color.Color = Color.Tint.color.ansi4.red,
        fail: Color.Color = Color.Tint.color.ansi4.magenta,
        critical: Color.Color = Color.Tint.color.ansi4.brightRed,
        fatal: Color.Color = Color.Tint.color.ansi4.brightWhite,

        /// Returns the color configured for a specific log level.
        pub fn getColor(self: Theme, level: Level) Color.Color {
            return switch (level) {
                .trace => self.trace,
                .debug => self.debug,
                .info => self.info,
                .notice => self.notice,
                .success => self.success,
                .warning => self.warning,
                .err => self.err,
                .fail => self.fail,
                .critical => self.critical,
                .fatal => self.fatal,
            };
        }

        /// Preset: bright colors.
        pub fn bright() Theme {
            const a = Color.Tint.color.ansi4;
            return .{
                .trace = a.brightCyan,
                .debug = a.brightBlue,
                .info = a.brightWhite,
                .notice = a.brightCyan,
                .success = a.brightGreen,
                .warning = a.brightYellow,
                .err = a.brightRed,
                .fail = a.brightMagenta,
                .critical = a.brightRed,
                .fatal = a.brightWhite,
            };
        }

        /// Preset: dim colors (same hues; apply `Style.dim` at render time
        /// for the dim attribute, since dimness is a text attribute in tint).
        pub fn dim() Theme {
            return .{};
        }

        /// Preset: minimal colors (only important levels colored).
        pub fn minimal() Theme {
            const a = Color.Tint.color.ansi4;
            return .{
                .trace = a.brightBlack,
                .debug = a.brightBlack,
                .info = a.white,
                .notice = a.white,
                .success = a.white,
                .warning = a.yellow,
                .err = a.red,
                .fail = a.red,
                .critical = a.brightRed,
                .fatal = a.brightRed,
            };
        }

        /// Preset: neon colors (256-color palette).
        pub fn neon() Theme {
            const a = Color.Tint.color.ansi256;
            return .{
                .trace = a.index(51),
                .debug = a.index(33),
                .info = a.index(255),
                .notice = a.index(123),
                .success = a.index(46),
                .warning = a.index(226),
                .err = a.index(196),
                .fail = a.index(201),
                .critical = a.index(196),
                .fatal = a.index(231),
            };
        }

        /// Preset: pastel colors.
        pub fn pastel() Theme {
            const a = Color.Tint.color.ansi256;
            return .{
                .trace = a.index(159),
                .debug = a.index(117),
                .info = a.index(188),
                .notice = a.index(153),
                .success = a.index(157),
                .warning = a.index(222),
                .err = a.index(210),
                .fail = a.index(218),
                .critical = a.index(203),
                .fatal = a.index(231),
            };
        }

        /// Preset: dark theme.
        pub fn dark() Theme {
            const a = Color.Tint.color.ansi256;
            return .{
                .trace = a.index(244),
                .debug = a.index(75),
                .info = a.index(252),
                .notice = a.index(81),
                .success = a.index(114),
                .warning = a.index(220),
                .err = a.index(203),
                .fail = a.index(168),
                .critical = a.index(196),
                .fatal = a.index(231),
            };
        }

        /// Preset: light theme.
        pub fn light() Theme {
            const a = Color.Tint.color.ansi256;
            return .{
                .trace = a.index(242),
                .debug = a.index(24),
                .info = a.index(235),
                .notice = a.index(30),
                .success = a.index(28),
                .warning = a.index(130),
                .err = a.index(124),
                .fail = a.index(127),
                .critical = a.index(160),
                .fatal = a.index(160),
            };
        }

        /// Create a custom theme from RGB values.
        pub fn fromRgb(
            traceRgb: struct { r: u8, g: u8, b: u8 },
            debugRgb: struct { r: u8, g: u8, b: u8 },
            infoRgb: struct { r: u8, g: u8, b: u8 },
            warningRgb: struct { r: u8, g: u8, b: u8 },
            errRgb: struct { r: u8, g: u8, b: u8 },
        ) Theme {
            const rgb = Color.Tint.color.rgb;
            var theme = Theme{};
            theme.trace = rgb(traceRgb.r, traceRgb.g, traceRgb.b);
            theme.debug = rgb(debugRgb.r, debugRgb.g, debugRgb.b);
            theme.info = rgb(infoRgb.r, infoRgb.g, infoRgb.b);
            theme.warning = rgb(warningRgb.r, warningRgb.g, warningRgb.b);
            theme.err = rgb(errRgb.r, errRgb.g, errRgb.b);
            return theme;
        }
    };

    /// Initializes a new Formatter and pre-fetches system metadata.
    pub fn init(allocator: std.mem.Allocator) Formatter {
        return initWithIo(allocator, Utils.defaultIo());
    }

    /// Initializes a new Formatter instance with explicit I/O.
    ///
    /// Complexity: O(1) + Hostname syscall cost
    pub fn initWithIo(allocator: std.mem.Allocator, io_handle: std.Io) Formatter {
        var self = Formatter{
            .allocator = allocator,
            .io = io_handle,
            .pid = fetchPID(),
        };
        self.hostname = fetchHostname(allocator) catch null;
        return self;
    }

    /// Deinitializes the Formatter and frees cached resources.
    pub fn deinit(self: *Formatter) void {
        if (self.hostname) |h| {
            self.allocator.free(h);
        }
        // debug_info is a pointer to a global singleton managed by std.debug.
        // We do not own it and should not deinit it.
    }

    /// Sets the callback for format completion.
    pub fn setFormatCompleteCallback(self: *Formatter, callback: *const fn (u32, u64) void) void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        self.onFormatComplete = callback;
    }

    /// Sets the callback for JSON formatting.
    pub fn setJsonFormatCallback(self: *Formatter, callback: *const fn (*const Record, u64) void) void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        self.onJsonFormat = callback;
    }

    /// Sets the callback for custom formatting.
    pub fn setCustomFormatCallback(self: *Formatter, callback: *const fn ([]const u8, u64) void) void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        self.onCustomFormat = callback;
    }

    /// Sets the callback for format errors.
    pub fn setErrorCallback(self: *Formatter, callback: *const fn ([]const u8) void) void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        self.onFormatError = callback;
    }

    /// Sets a custom color theme.
    pub fn setTheme(self: *Formatter, theme: Theme) void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        self.theme = theme;
    }

    /// Returns formatter statistics.
    pub fn getStats(self: *Formatter) FormatterStats {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);

        return self.stats;
    }

    /// Formats a log record into a string.
    ///
    /// This function handles:
    ///   - Custom format strings (parsing tags like `{time}`, `{level}`).
    ///   - Default text formatting.
    ///   - Color application (ENTIRE line is colored, not just level tag).
    ///
    /// Complexity: O(N) where N is generated string length.
    pub fn format(self: *Formatter, record: *const Record, config: anytype) ![]u8 {
        return self.formatWithAllocator(record, config, null);
    }

    /// Formats a log record into a string using an optional scratch allocator.
    ///
    /// Format precedence when several flags are set (also documented on
    /// Config): msgpack > ndjson > syslog > syslog3164 > csv > keyValue >
    /// logfmt > cef > clf > combined > json > plain text. Set exactly one
    /// format flag; the precedence only resolves accidental combinations.
    ///
    /// Useful for temporary allocations to avoid defragmentation or for arena usage.
    pub fn formatWithAllocator(self: *Formatter, record: *const Record, config: anytype, scratchAllocator: ?std.mem.Allocator) ![]u8 {
        const alloc = scratchAllocator orelse self.allocator;
        const startTime = Utils.currentNanos();
        var bytesFormatted: Constants.AtomicUnsigned = 0;
        defer {
            const current = Utils.currentNanos();
            const elapsed = @as(u64, @intCast(@max(0, current - startTime)));
            _ = self.stats.totalRecordsFormatted.fetchAdd(1, .monotonic);
            _ = self.stats.totalBytesFormatted.fetchAdd(bytesFormatted, .monotonic);
            _ = elapsed;
        }

        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);

        // Explicit format selection: exactly one format renders each
        // record. No precedence chain, no competing flags.
        switch (resolveFormat(config)) {
            .msgpack => {
                const res = try self.formatMsgpackWithAllocator(record, config, scratchAllocator);
                bytesFormatted = res.len;
                return res;
            },
            .ndjson => {
                const res = try self.formatJsonWithAllocator(record, config, scratchAllocator);
                bytesFormatted = res.len;
                return res;
            },
            .syslog => {
                const res = try self.formatSyslogWithAllocator(record, config, scratchAllocator);
                bytesFormatted = res.len;
                return res;
            },
            .syslog3164 => {
                const res = try self.formatSyslog3164WithAllocator(record, config, scratchAllocator);
                bytesFormatted = res.len;
                return res;
            },
            .logfmt => {
                const res = try self.formatLogfmtWithAllocator(record, config, scratchAllocator);
                bytesFormatted = res.len;
                return res;
            },
            .json => {
                const res = try self.formatJsonWithAllocator(record, config, scratchAllocator);
                bytesFormatted = res.len;
                return res;
            },
            .text => {},
        }

        var buf = std.Io.Writer.Allocating.init(alloc);
        errdefer buf.deinit();
        const writer = &buf.writer;

        if (self.configIsCustom(config)) {
            _ = self.stats.customFormats.fetchAdd(1, .monotonic);
        }

        try self.formatToWriter(writer, record, config);

        if (self.onFormatComplete) |cb| {
            cb(0, buf.written().len);
        }

        const res = try buf.toOwnedSlice();
        bytesFormatted = res.len;
        return res;
    }

    /// Resolves the output format from any config carrying a Format value.
    /// Configs without a format field render plain text.
    fn resolveFormat(config: anytype) Config.Format {
        if (@hasField(@TypeOf(config), "format")) {
            const f = config.format;
            if (@TypeOf(f) == ?Config.Format) return f orelse .text;
            return f;
        }
        return .text;
    }

    /// Internal helper to detect if custom format is active.
    fn configIsCustom(self: *Formatter, config: anytype) bool {
        _ = self;
        return if (@hasField(@TypeOf(config), "logFormat")) config.logFormat != null else false;
    }

    /// Formats a timestamp string using the provided configuration.
    ///
    /// This reuses the same timestamp logic as plain-text and JSON record formatting.
    pub fn formatTimestamp(self: *Formatter, timestampMs: i64, config: anytype) ![]u8 {
        return self.formatTimestampWithAllocator(timestampMs, config, null);
    }

    /// Formats a timestamp string using an optional scratch allocator.
    pub fn formatTimestampWithAllocator(self: *Formatter, timestampMs: i64, config: anytype, scratchAllocator: ?std.mem.Allocator) ![]u8 {
        const alloc = scratchAllocator orelse self.allocator;
        var buf = std.Io.Writer.Allocating.init(alloc);
        errdefer buf.deinit();

        try self.writeTimestamp(&buf.writer, timestampMs, config);
        return buf.toOwnedSlice();
    }

    /// Returns the number of interpolation placeholders in a custom format template.
    ///
    /// Supported placeholders are balanced `{name}` tokens. Escaped braces `{{` and `}}`
    /// are treated as literal braces.
    pub fn countTemplatePlaceholders(template: []const u8) !usize {
        var count: usize = 0;
        var i: usize = 0;

        while (i < template.len) {
            switch (template[i]) {
                '{' => {
                    if (i + 1 < template.len and template[i + 1] == '{') {
                        i += 2;
                        continue;
                    }

                    const end = std.mem.indexOfScalarPos(u8, template, i + 1, '}') orelse return error.UnbalancedBraces;
                    if (end == i + 1) return error.InvalidTemplate;
                    count += 1;
                    i = end + 1;
                },
                '}' => {
                    if (i + 1 < template.len and template[i + 1] == '}') {
                        i += 2;
                        continue;
                    }
                    return error.UnbalancedBraces;
                },
                else => i += 1,
            }
        }

        return count;
    }

    /// Validates that a custom format template only uses balanced placeholder braces.
    ///
    /// This is a lightweight syntax check for custom formatter strings and does not
    /// allocate or change the formatter state.
    pub fn validateTemplate(template: []const u8) !void {
        _ = try countTemplatePlaceholders(template);
    }

    /// Resolves the display color for a record under a config and theme.
    ///
    /// Central color decision shared by inline text coloring and
    /// structured presentation coloring (see the color policy matrix in
    /// `Color` docs). Returns null when coloring is disabled
    /// (`colorMode.none`, or `color`/`globalColorDisplay` off).
    ///
    /// Precedence: record custom color → per-level config override →
    /// non-default theme palette → sink/formatter theme → default level
    /// palette. Custom log levels without an explicit color resolve
    /// through their mapped base level, deterministically.
    ///
    /// Pure computation on values; no allocation, thread-safe.
    pub fn resolveRecordColor(record: *const Record, config: anytype, theme: ?Theme) ?Color.Color {
        // colorMode.none disables all coloring regardless of other flags.
        const modeNone = @hasField(@TypeOf(config), "colorMode") and config.colorMode == .none;
        if (modeNone) return null;
        if (!config.color or !config.globalColorDisplay) return null;
        // Fast path: when colors are off, skip all tint resolution/rendering.
        // Render the SGR sequence lazily only if a colored write occurs.
        if (record.customLevelColor) |c| return c;

        // If no custom color from record, check explicit config overrides first.
        if (@hasField(@TypeOf(config), "levelColors")) {
            if (config.levelColors.getOverrideForLevel(record.level)) |override| {
                return override;
            } else if (!config.levelColors.usesDefaultTheme()) {
                return config.levelColors.getColorForLevel(record.level);
            }
        }

        // If still no color, check the formatter/sink theme.
        if (theme) |t| {
            return t.getColor(record.level);
        }

        // Fallback to default config/level colors.
        if (@hasField(@TypeOf(config), "levelColors")) {
            return config.levelColors.getColorForLevel(record.level);
        }
        return record.level.defaultColor();
    }

    /// Formats a log record directly to a writer.
    ///
    /// This avoids intermediate allocations when writing directly to a sink.
    pub fn formatToWriter(self: *Formatter, writer: anytype, record: *const Record, config: anytype) !void {
        const resolvedColor: ?Color.Color = resolveRecordColor(record, config, self.theme);

        // Render the SGR sequence once via tint, only when coloring.
        // The Sequence owns its bytes inline; valid for this call.
        const colorSeq = if (resolvedColor) |c| Color.sequence(c, Color.defaultCapability) else null;

        // Vertical mode: precompute per-column sequences. Level falls back
        // to the resolved level color; other columns render uncolored unless
        // explicitly configured. All Sequences are stack values (no alloc).
        const useColor = resolvedColor != null;
        const isVertical = useColor and
            @hasField(@TypeOf(config), "colorMode") and config.colorMode == .vertical;
        const colSeqs = if (isVertical) verticalColumnSeqs(config, resolvedColor) else null;

        // Check if custom log format.
        //
        // Custom formatter contract: the template string selects fields;
        // Logly owns all coloring exactly once (horizontal whole-line wrap,
        // or per-field spans in vertical mode, always reset-terminated).
        // Templates must not embed raw ANSI sequences: embedded bytes pass
        // through as data and are never reset by Logly, which would leak
        // terminal state.
        if (config.logFormat) |fmtStr| {
            // Start color for entire line (horizontal only; vertical
            // colors each field independently below).
            if (useColor and colSeqs == null) {
                if (colorSeq) |seq| try writer.writeAll(seq.slice());
            }

            var i: usize = 0;
            while (i < fmtStr.len) {
                if (fmtStr[i] == '{') {
                    const end = std.mem.indexOfScalarPos(u8, fmtStr, i + 1, '}') orelse {
                        try writer.writeByte(fmtStr[i]);
                        i += 1;
                        continue;
                    };
                    const tag = fmtStr[i + 1 .. end];

                    var fieldName = tag;
                    var formatSpec: []const u8 = "";
                    if (std.mem.indexOfScalar(u8, tag, ':')) |colonIdx| {
                        fieldName = tag[0..colonIdx];
                        formatSpec = tag[colonIdx + 1 ..];
                    }

                    // Vertical mode: open the field's color before rendering.
                    const fieldSeq = if (colSeqs) |cs| templateFieldSeq(fieldName, cs) else null;
                    if (fieldSeq) |s| try writer.writeAll(s.slice());

                    if (std.mem.eql(u8, fieldName, "time")) {
                        try self.writeTimestamp(writer, record.timestamp, config);
                    } else if (std.mem.eql(u8, fieldName, "level")) {
                        try writePadded(writer, record.levelName(), formatSpec);
                    } else if (std.mem.eql(u8, fieldName, "message")) {
                        try writePadded(writer, record.message, formatSpec);
                    } else if (std.mem.eql(u8, fieldName, "module")) {
                        try writePadded(writer, record.module orelse "", formatSpec);
                    } else if (std.mem.eql(u8, fieldName, "function")) {
                        try writePadded(writer, record.function orelse "", formatSpec);
                    } else if (std.mem.eql(u8, fieldName, "file")) {
                        try writePadded(writer, record.filename orelse "", formatSpec);
                    } else if (std.mem.eql(u8, fieldName, "line")) {
                        if (record.line) |l| {
                            var numBuf: [32]u8 = undefined;
                            const numStr = std.fmt.bufPrint(&numBuf, "{d}", .{l}) catch "";
                            try writePadded(writer, numStr, formatSpec);
                        } else {
                            try writePadded(writer, "", formatSpec);
                        }
                    } else if (std.mem.eql(u8, fieldName, "thread")) {
                        if (record.threadId) |tid| {
                            var numBuf: [32]u8 = undefined;
                            const numStr = std.fmt.bufPrint(&numBuf, "{d}", .{tid}) catch "";
                            try writePadded(writer, numStr, formatSpec);
                        } else {
                            try writePadded(writer, "", formatSpec);
                        }
                    } else if (std.mem.eql(u8, fieldName, "traceId")) {
                        try writePadded(writer, record.traceId orelse "", formatSpec);
                    } else if (std.mem.eql(u8, fieldName, "spanId")) {
                        try writePadded(writer, record.spanId orelse "", formatSpec);
                    } else if (std.mem.eql(u8, fieldName, "fields")) {
                        var it = record.context.iterator();
                        var first = true;
                        while (it.next()) |entry| {
                            if (!first) try writer.writeByte(' ');
                            try writer.writeAll(entry.key_ptr.*);
                            try writer.writeByte('=');
                            switch (entry.value_ptr.*) {
                                .string => |s| try writeLogfmtValue(writer, s),
                                .integer => |in| try writer.print("{d}", .{in}),
                                .float => |fl| try writer.print("{d}", .{fl}),
                                .bool => |b| try writer.writeAll(if (b) "true" else "false"),
                                else => try writer.writeAll("null"),
                            }
                            first = false;
                        }
                    } else {
                        // Unknown tag, print as is
                        try writer.writeAll(fmtStr[i .. end + 1]);
                    }
                    // Vertical mode: close the field color (prevents bleed).
                    if (fieldSeq != null) try writer.writeAll(Color.resetAll);
                    i = end + 1;
                } else {
                    try writer.writeByte(fmtStr[i]);
                    i += 1;
                }
            }

            // Reset color at end of entire line
            if (useColor) {
                try writer.writeAll(Color.resetAll);
            }
        } else {
            // Default format.
            // Horizontal: one level color for the whole line (existing behavior).
            // Vertical: per-field colors with reset boundaries (no bleed).
            const vertical = colSeqs != null;

            // Start color for entire line (horizontal only).
            if (useColor and !vertical) {
                if (colorSeq) |seq| try writer.writeAll(seq.slice());
            }

            // Timestamp
            if (config.showTime) {
                if (colSeqs) |cs| if (cs.timestamp) |s| try writer.writeAll(s.slice());
                try writer.writeAll("[");
                try self.writeTimestamp(writer, record.timestamp, config);
                try writer.writeAll("] ");
                if (colSeqs) |cs| if (cs.timestamp != null) try writer.writeAll(Color.resetAll);
            }

            // Level (use custom name if available)
            if (colSeqs) |cs| if (cs.level) |s| try writer.writeAll(s.slice());
            try writer.writeByte('[');
            try writer.writeAll(record.levelName());
            try writer.writeAll("] ");
            if (colSeqs) |cs| if (cs.level != null) try writer.writeAll(Color.resetAll);

            // Module
            if (config.showModule and record.module != null) {
                if (colSeqs) |cs| if (cs.module) |s| try writer.writeAll(s.slice());
                try writer.writeByte('[');
                try writer.writeAll(record.module.?);
                try writer.writeAll("] ");
                if (colSeqs) |cs| if (cs.module != null) try writer.writeAll(Color.resetAll);
            }

            // Function
            if (config.showFunction and record.function != null) {
                if (colSeqs) |cs| if (cs.function) |s| try writer.writeAll(s.slice());
                try writer.writeByte('[');
                try writer.writeAll(record.function.?);
                try writer.writeAll("] ");
                if (colSeqs) |cs| if (cs.function != null) try writer.writeAll(Color.resetAll);
            }

            // Thread ID (uses module color when vertical; no dedicated column)
            if (config.showThreadId and record.threadId != null) {
                if (colSeqs) |cs| if (cs.module) |s| try writer.writeAll(s.slice());
                try writer.writeAll("[TID:");
                try Utils.writeInt(writer, record.threadId.?);
                try writer.writeAll("] ");
                if (colSeqs) |cs| if (cs.module != null) try writer.writeAll(Color.resetAll);
            }

            // Filename and line (Clickable format: file:line:column: for terminal clickability)
            if (config.showFilename and record.filename != null) {
                if (colSeqs) |cs| if (cs.filename) |s| try writer.writeAll(s.slice());
                try writer.writeAll(record.filename.?);
                if (colSeqs) |cs| if (cs.filename != null) try writer.writeAll(Color.resetAll);
                if (config.showLineno and record.line != null) {
                    if (colSeqs) |cs| if (cs.line) |s| try writer.writeAll(s.slice());
                    try writer.writeByte(':');
                    try Utils.writeInt(writer, record.line.?);
                    try writer.writeByte(':');
                    if (record.column) |col| {
                        try Utils.writeInt(writer, col);
                    } else {
                        try writer.writeByte('0');
                    }
                    try writer.writeByte(':');
                    if (colSeqs) |cs| if (cs.line != null) try writer.writeAll(Color.resetAll);
                } else {
                    try writer.writeAll(":0:0:");
                }
                try writer.writeByte(' ');
            }

            // Message (wrapped whole; embedded newlines inherit the color,
            // trailing reset prevents leakage into later output)
            if (colSeqs) |cs| if (cs.message) |s| try writer.writeAll(s.slice());
            try writer.writeAll(record.message);
            if (colSeqs) |cs| if (cs.message != null) try writer.writeAll(Color.resetAll);

            // Stack Trace (if present)
            if (record.stackTrace) |st| {
                try writer.writeAll("\nStack Trace:\n");

                // Check for symbolization config
                const symbolize = if (@hasField(@TypeOf(config), "symbolizeStackTrace")) config.symbolizeStackTrace else false;

                if (symbolize) {
                    // Lazy load debug info to avoid repeatedly parsing DWARF info (expensive!)
                    if (self.debugInfo == null) {
                        // We swallow the error here as we can fallback to raw addresses
                        self.debugInfo = std.debug.getSelfDebugInfo() catch null;
                    }

                    const count = @min(st.index, st.instruction_addresses.len);

                    for (st.instruction_addresses[0..count]) |addr| {
                        if (self.debugInfo) |di| {
                            if (di.getModuleName(self.io, addr) catch null) |moduleName| {
                                try writer.print("  {s}:0x{x}\n", .{ moduleName, addr });
                            } else {
                                try writer.print("  0x{x}\n", .{addr});
                            }
                        } else {
                            try writer.print("  0x{x}\n", .{addr});
                        }
                    }
                } else {
                    // Default: print raw addresses
                    const count = @min(st.index, st.instruction_addresses.len);
                    for (st.instruction_addresses[0..count]) |addr| {
                        try writer.print("  0x{x}\n", .{addr});
                    }
                }
            }

            // Reset color at end of entire line
            if (useColor) {
                try writer.writeAll(Color.resetAll);
            }
        }

        // Render rule messages if present
        if (record.invokeMessages) |messages| {
            const Invoke = @import("invoke.zig").Invoke;
            var invokeTemp = Invoke.init(self.allocator);
            defer invokeTemp.deinit();
            try invokeTemp.formatMessages(messages, writer, useColor);
        }
    }

    /// Per-column rendered sequences for vertical mode. All optional;
    /// null means "render this field uncolored". Stack-allocated values.
    const ColumnSeqs = struct {
        timestamp: ?Color.Sequence = null,
        level: ?Color.Sequence = null,
        module: ?Color.Sequence = null,
        function: ?Color.Sequence = null,
        filename: ?Color.Sequence = null,
        line: ?Color.Sequence = null,
        message: ?Color.Sequence = null,
    };

    /// Resolves vertical column sequences from config plus level fallback.
    ///
    /// The `level` column uses `columnColors.level` when set, else the
    /// resolved level color. Other columns use only their explicit config;
    /// unset columns stay uncolored so default vertical output is not a
    /// rainbow. Pure computation on values; no allocation, thread-safe.
    fn verticalColumnSeqs(
        config: anytype,
        resolvedLevelColor: ?Color.Color,
    ) ColumnSeqs {
        var out = ColumnSeqs{};
        if (!@hasField(@TypeOf(config), "columnColors")) return out;
        const cols = config.columnColors;
        const cap = Color.defaultCapability;
        if (cols.timestamp) |c| out.timestamp = Color.sequence(c, cap);
        if (cols.level) |c| {
            out.level = Color.sequence(c, cap);
        } else if (resolvedLevelColor) |c| {
            out.level = Color.sequence(c, cap);
        }
        if (cols.module) |c| out.module = Color.sequence(c, cap);
        if (cols.function) |c| out.function = Color.sequence(c, cap);
        if (cols.filename) |c| out.filename = Color.sequence(c, cap);
        if (cols.line) |c| out.line = Color.sequence(c, cap);
        if (cols.message) |c| out.message = Color.sequence(c, cap);
        return out;
    }

    /// Maps a template placeholder name to its vertical column sequence.
    ///
    /// Returns null for uncolored fields or unknown names. The `level`
    /// placeholder falls back to the resolved level color (already included
    /// in `cs.level` by `verticalColumnSeqs`). Pure lookup; no allocation.
    fn templateFieldSeq(fieldName: []const u8, cs: ColumnSeqs) ?Color.Sequence {
        if (std.mem.eql(u8, fieldName, "time")) return cs.timestamp;
        if (std.mem.eql(u8, fieldName, "level")) return cs.level;
        if (std.mem.eql(u8, fieldName, "message")) return cs.message;
        if (std.mem.eql(u8, fieldName, "module")) return cs.module;
        if (std.mem.eql(u8, fieldName, "function")) return cs.function;
        if (std.mem.eql(u8, fieldName, "file") or std.mem.eql(u8, fieldName, "filename")) return cs.filename;
        if (std.mem.eql(u8, fieldName, "line")) return cs.line;
        if (std.mem.eql(u8, fieldName, "context") or std.mem.eql(u8, fieldName, "fields")) return cs.message;
        return null;
    }

    /// Maps a top-level JSON object key to its presentation color.
    ///
    /// Returns null when no explicit column color applies (the caller keeps
    /// the base level color, emitting no extra sequence). Mirrors the
    /// template mapping above, including `context` falling back to the
    /// message column and `level` to the resolved base color.
    fn jsonKeyColor(fieldName: []const u8, config: anytype, base: Color.Color) ?Color.Color {
        if (!@hasField(@TypeOf(config), "columnColors")) return null;
        const cols = config.columnColors;
        if (std.mem.eql(u8, fieldName, "timestamp")) return cols.timestamp;
        if (std.mem.eql(u8, fieldName, "level")) return cols.level orelse base;
        if (std.mem.eql(u8, fieldName, "module")) return cols.module;
        if (std.mem.eql(u8, fieldName, "function")) return cols.function;
        if (std.mem.eql(u8, fieldName, "filename")) return cols.filename;
        if (std.mem.eql(u8, fieldName, "line")) return cols.line;
        if (std.mem.eql(u8, fieldName, "message")) return cols.message;
        if (std.mem.eql(u8, fieldName, "context")) return cols.context orelse cols.message;
        return null;
    }

    /// Formats a record as JSON with terminal presentation colors.
    ///
    /// Serializes valid JSON first, then applies per-field colors as a
    /// presentation layer: the whole line carries the resolved level color
    /// while top-level keys with configured column colors are overridden.
    /// The returned bytes are display text (strip ANSI to recover the exact
    /// valid JSON). One transient allocation beyond the plain rendering;
    /// used only for vertical terminal presentation, never on hot paths.
    pub fn formatJsonHighlighted(self: *Formatter, record: *const Record, config: anytype) ![]u8 {
        const plain = try self.formatJsonWithAllocator(record, config, null);
        defer self.allocator.free(plain);
        const base = resolveRecordColor(record, config, self.theme) orelse {
            return try self.allocator.dupe(u8, plain);
        };
        var out = std.Io.Writer.Allocating.init(self.allocator);
        errdefer out.deinit();
        try writeHighlightedJson(&out.writer, plain, base, config);
        return out.toOwnedSlice();
    }

    /// Wraps already-serialized bytes in a presentation color plus reset.
    ///
    /// Allocating counterpart of the sink's zero-alloc buffer surgery, for
    /// paths that queue owned strings (async dispatch). The bytes themselves
    /// are untouched; color opens before the first byte and resets after
    /// the last, so stripping ANSI recovers the exact input.
    pub fn wrapPresented(allocator: std.mem.Allocator, color: Color.Color, bytes: []const u8) ![]u8 {
        const seq = Color.sequence(color, Color.defaultCapability);
        var out = std.Io.Writer.Allocating.init(allocator);
        errdefer out.deinit();
        try out.writer.writeAll(seq.slice());
        try out.writer.writeAll(bytes);
        try out.writer.writeAll(Color.resetAll);
        return out.toOwnedSlice();
    }

    /// Writes JSON bytes with terminal presentation colors.
    ///
    /// Single-pass scanner: tracks object depth plus string/escape state
    /// (ASCII-only delimiters, so UTF-8 passes through untouched) and
    /// recolors top-level `"key":` tokens. Everything else inherits the
    /// base level color. Opens with the base sequence and always closes
    /// with a reset, so no color bleeds past the record.
    pub fn writeHighlightedJson(writer: anytype, json: []const u8, base: Color.Color, config: anytype) !void {
        if (json.len == 0) return;
        const cap = Color.defaultCapability;
        const baseSeq = Color.sequence(base, cap);
        try writer.writeAll(baseSeq.slice());

        var depth: usize = 0;
        var inStr = false;
        var esc = false;
        var strStart: usize = 0;
        var flushFrom: usize = 0;
        var i: usize = 0;
        while (i < json.len) {
            const c = json[i];
            if (inStr) {
                if (esc) {
                    esc = false;
                } else if (c == '\\') {
                    esc = true;
                } else if (c == '"') {
                    inStr = false;
                    if (depth == 1) {
                        var j = i + 1;
                        while (j < json.len and (json[j] == ' ' or json[j] == '\t' or json[j] == '\n' or json[j] == '\r')) : (j += 1) {}
                        if (j < json.len and json[j] == ':') {
                            const key = json[strStart + 1 .. i];
                            try writer.writeAll(json[flushFrom..strStart]);
                            if (jsonKeyColor(key, config, base)) |kc| {
                                const keySeq = Color.sequence(kc, cap);
                                if (!keySeq.eql(&baseSeq)) {
                                    try writer.writeAll(keySeq.slice());
                                    try writer.writeAll(json[strStart .. i + 1]);
                                    try writer.writeAll(baseSeq.slice());
                                } else {
                                    try writer.writeAll(json[strStart .. i + 1]);
                                }
                            } else {
                                try writer.writeAll(json[strStart .. i + 1]);
                            }
                            flushFrom = i + 1;
                        }
                    }
                }
            } else {
                switch (c) {
                    '"' => {
                        inStr = true;
                        strStart = i;
                    },
                    '{', '[' => depth += 1,
                    '}', ']' => depth -|= 1,
                    else => {},
                }
            }
            i += 1;
        }
        try writer.writeAll(json[flushFrom..]);
        try writer.writeAll(Color.resetAll);
    }

    fn normalizedTimeFormat(rawTimeFormat: []const u8) []const u8 {
        if (std.mem.eql(u8, rawTimeFormat, Config.TimeFormat.defaultAlias)) {
            return Config.TimeFormat.defaultPattern;
        }
        return rawTimeFormat;
    }

    fn isUnixSecondsFormat(timeFormat: []const u8) bool {
        return std.mem.eql(u8, timeFormat, Config.TimeFormat.unix);
    }

    fn isUnixMillisFormat(timeFormat: []const u8) bool {
        return std.mem.eql(u8, timeFormat, Config.TimeFormat.unixMs);
    }

    fn isNumericTimestampFormat(timeFormat: []const u8) bool {
        return isUnixSecondsFormat(timeFormat) or isUnixMillisFormat(timeFormat);
    }

    fn writeNumericTimestamp(writer: anytype, timestampMs: i64, timeFormat: []const u8) !void {
        if (isUnixSecondsFormat(timeFormat)) {
            const unixSeconds = @divFloor(timestampMs, @as(i64, @intCast(Constants.TimeConstants.msPerSecond)));
            try Utils.writeInt(writer, unixSeconds);
            return;
        }

        // unix_ms
        try Utils.writeInt(writer, timestampMs);
    }

    /// Writes a timestamp according to configured format and timezone.
    ///
    /// Supports predefined formats (`ISO8601`, `RFC3339`, `unix`, `unix_ms`) and
    /// custom patterns via `Utils.formatDatePatternWithOffset`.
    fn writeTimestamp(self: *Formatter, writer: anytype, timestampMs: i64, config: anytype) !void {
        _ = self;

        const timeFormat = normalizedTimeFormat(config.timeFormat);

        // Handle special time formats
        if (isNumericTimestampFormat(timeFormat)) {
            try writeNumericTimestamp(writer, timestampMs, timeFormat);
            return;
        }

        const useLocalTimezone = if (@hasField(@TypeOf(config), "timezone"))
            config.timezone == .local
        else
            false;
        const tc = if (useLocalTimezone)
            Utils.fromMilliTimestampLocal(timestampMs)
        else
            Utils.fromMilliTimestamp(timestampMs);
        const utcOffsetMinutes: i16 = if (useLocalTimezone)
            Utils.localUtcOffsetMinutes(timestampMs)
        else
            0;
        const absTs = if (timestampMs < 0) 0 else @as(u64, @intCast(timestampMs));
        const millis = absTs % Constants.TimeConstants.msPerSecond;

        // ISO8601 format: 2025-12-04T06:39:53.091Z or 2025-12-04T07:39:53.091+01:00
        if (std.mem.eql(u8, timeFormat, Config.TimeFormat.iso8601)) {
            try Utils.writeIsoDateTime(writer, tc);
            try writer.writeByte('.');
            try Utils.write3Digits(writer, millis);
            if (useLocalTimezone) {
                try Utils.writeUtcOffset(writer, utcOffsetMinutes);
            } else {
                try writer.writeByte('Z');
            }
            return;
        }

        // RFC3339 format: 2025-12-04T06:39:53+00:00 or 2025-12-04T07:39:53+01:00
        if (std.mem.eql(u8, timeFormat, Config.TimeFormat.rfc3339)) {
            try Utils.writeIsoDateTime(writer, tc);
            try Utils.writeUtcOffset(writer, utcOffsetMinutes);
            return;
        }

        // Custom format parsing - supports any format with placeholders:
        // YYYY = 4-digit year, YY = 2-digit year
        // MM = 2-digit month, M = 1-2 digit month
        // DD = 2-digit day, D = 1-2 digit day
        // HH = 2-digit hour (24h), hh = 2-digit hour (12h)
        // mm = 2-digit minute
        // ss = 2-digit second
        // Custom format parsing via shared utility
        try Utils.formatDatePatternWithOffset(writer, timeFormat, tc.year, tc.month, tc.day, tc.hour, tc.minute, tc.second, millis, utcOffsetMinutes);
    }

    /// Writes timestamp field value for JSON output.
    /// Numeric formats stay numeric; all others are quoted strings.
    fn writeJsonTimestampValue(self: *Formatter, writer: anytype, timestampMs: i64, config: anytype) !void {
        const timeFormat = normalizedTimeFormat(config.timeFormat);
        if (isNumericTimestampFormat(timeFormat)) {
            try writeNumericTimestamp(writer, timestampMs, timeFormat);
        } else {
            try writer.writeAll("\"");
            try self.writeTimestamp(writer, timestampMs, config);
            try writer.writeAll("\"");
        }
    }

    /// Formats a log record as JSON string.
    pub fn formatJson(self: *Formatter, record: *const Record, config: anytype) ![]u8 {
        return self.formatJsonWithAllocator(record, config, null);
    }

    /// Formats a log record as JSON using optional allocator.
    pub fn formatJsonWithAllocator(self: *Formatter, record: *const Record, config: anytype, scratchAllocator: ?std.mem.Allocator) ![]u8 {
        const alloc = scratchAllocator orelse self.allocator;
        var buf = std.Io.Writer.Allocating.init(alloc);
        errdefer buf.deinit();
        const writer = &buf.writer;
        try self.formatJsonToWriter(writer, record, config);

        _ = self.stats.jsonFormats.fetchAdd(1, .monotonic);

        if (self.onJsonFormat) |cb| {
            cb(record, buf.written().len);
        }

        return buf.toOwnedSlice();
    }

    /// Formats a log record as JSON directly to a writer.
    ///
    /// Use this for zero-allocation streaming (assuming buffered writer).
    pub fn formatJsonToWriter(self: *Formatter, writer: anytype, record: *const Record, config: anytype) !void {
        const escapeJsonString = Utils.escapeJsonString;
        const pretty = if (@hasField(@TypeOf(config), "prettyJson")) config.prettyJson else false;
        const indent = if (pretty) "  " else "";
        const newline = if (pretty) "\n" else "";
        const sep = if (pretty) ": " else ":";
        const comma = if (pretty) ",\n" else ",";

        // JSON is a serialization format, never a presentation format:
        // ANSI colors are intentionally not emitted here even when the
        // surrounding config enables colors. Terminal coloring applies to
        // plain text, logfmt, and key-value output only.

        try writer.writeAll("{");
        try writer.writeAll(newline);

        // Timestamp
        try writer.writeAll(indent);
        try writer.writeAll("\"timestamp\"");
        try writer.writeAll(sep);
        try self.writeJsonTimestampValue(writer, record.timestamp, config);

        // Level (use custom name if available)
        try writer.writeAll(comma);
        try writer.writeAll(indent);
        try writer.writeAll("\"level\"");
        try writer.writeAll(sep);
        try writer.writeByte('"');
        try writer.writeAll(record.levelName());
        try writer.writeByte('"');

        // Message
        try writer.writeAll(comma);
        try writer.writeAll(indent);
        try writer.writeAll("\"message\"");
        try writer.writeAll(sep);
        try writer.writeByte('"');
        try escapeJsonString(writer, record.message);
        try writer.writeByte('"');

        // Optional fields
        if (record.module) |m| {
            try writer.writeAll(comma);
            try writer.writeAll(indent);
            try writer.writeAll("\"module\"");
            try writer.writeAll(sep);
            try writer.writeByte('"');
            try escapeJsonString(writer, m);
            try writer.writeByte('"');
        }
        if (record.function) |f| {
            try writer.writeAll(comma);
            try writer.writeAll(indent);
            try writer.writeAll("\"function\"");
            try writer.writeAll(sep);
            try writer.writeByte('"');
            try escapeJsonString(writer, f);
            try writer.writeByte('"');
        }
        if (record.filename) |f| {
            try writer.writeAll(comma);
            try writer.writeAll(indent);
            try writer.writeAll("\"filename\"");
            try writer.writeAll(sep);
            try writer.writeByte('"');
            try escapeJsonString(writer, f);
            try writer.writeByte('"');
        }
        if (record.line) |l| {
            try writer.writeAll(comma);
            try writer.writeAll(indent);
            try writer.writeAll("\"line\"");
            try writer.writeAll(sep);
            try Utils.writeInt(writer, l);
        }

        // Hostname and PID
        if (config.includeHostname) {
            try writer.writeAll(comma);
            try writer.writeAll(indent);
            try writer.writeAll("\"hostname\"");
            try writer.writeAll(sep);
            try writer.writeByte('"');
            if (self.hostname) |h| {
                try escapeJsonString(writer, h);
            } else {
                try writer.writeAll("unknown-host");
            }
            try writer.writeByte('"');
        }

        if (config.includePid) {
            try writer.writeAll(comma);
            try writer.writeAll(indent);
            try writer.writeAll("\"pid\"");
            try writer.writeAll(sep);
            try Utils.writeInt(writer, self.pid);
        }

        // Distributed Context
        if (@hasField(@TypeOf(config), "distributed")) {
            if (config.distributed.enabled) {
                if (config.distributed.serviceName) |s| {
                    try writer.writeAll(comma);
                    try writer.writeAll(indent);
                    try writer.writeAll("\"service\"");
                    try writer.writeAll(sep);
                    try writer.writeByte('"');
                    try escapeJsonString(writer, s);
                    try writer.writeByte('"');
                }
                if (config.distributed.serviceVersion) |v| {
                    try writer.writeAll(comma);
                    try writer.writeAll(indent);
                    try writer.writeAll("\"version\"");
                    try writer.writeAll(sep);
                    try writer.writeByte('"');
                    try escapeJsonString(writer, v);
                    try writer.writeByte('"');
                }
                if (config.distributed.environment) |e| {
                    try writer.writeAll(comma);
                    try writer.writeAll(indent);
                    try writer.writeAll("\"env\"");
                    try writer.writeAll(sep);
                    try writer.writeByte('"');
                    try escapeJsonString(writer, e);
                    try writer.writeByte('"');
                }
                if (config.distributed.region) |r| {
                    try writer.writeAll(comma);
                    try writer.writeAll(indent);
                    try writer.writeAll("\"region\"");
                    try writer.writeAll(sep);
                    try writer.writeByte('"');
                    try escapeJsonString(writer, r);
                    try writer.writeByte('"');
                }
                if (config.distributed.datacenter) |d| {
                    try writer.writeAll(comma);
                    try writer.writeAll(indent);
                    try writer.writeAll("\"datacenter\"");
                    try writer.writeAll(sep);
                    try writer.writeByte('"');
                    try escapeJsonString(writer, d);
                    try writer.writeByte('"');
                }
                if (config.distributed.instanceId) |i| {
                    try writer.writeAll(comma);
                    try writer.writeAll(indent);
                    try writer.writeAll("\"instanceId\"");
                    try writer.writeAll(sep);
                    try writer.writeByte('"');
                    try escapeJsonString(writer, i);
                    try writer.writeByte('"');
                }
            }
        }

        // Stack Trace
        if (record.stackTrace) |st| {
            try writer.writeAll(comma);
            try writer.writeAll(indent);
            try writer.writeAll("\"stackTrace\"");
            try writer.writeAll(sep);
            try writer.writeByte('[');

            // We can't easily symbolize here without debug info, but we can print addresses
            var firstAddr = true;
            const count = @min(st.index, st.instruction_addresses.len);

            // If symbolization is enabled in config (passed via config param)
            // Note: config is 'anytype' here, so we check if it has the field
            const symbolize = if (@hasField(@TypeOf(config), "symbolizeStackTrace")) config.symbolizeStackTrace else false;

            if (symbolize) {
                // Attempt to symbolize using cached debug info
                if (self.debugInfo == null) {
                    self.debugInfo = std.debug.getSelfDebugInfo() catch null;
                }

                for (st.instruction_addresses[0..count]) |addr| {
                    if (!firstAddr) try writer.writeAll(", ");

                    if (self.debugInfo) |di| {
                        if (di.getModuleName(self.io, addr) catch null) |moduleName| {
                            try writer.print("\"{s}:0x{x}\"", .{ moduleName, addr });
                        } else {
                            try writer.print("\"{x}\"", .{addr});
                        }
                    } else {
                        try writer.print("\"{x}\"", .{addr});
                    }
                    firstAddr = false;
                }
            } else {
                for (st.instruction_addresses[0..count]) |addr| {
                    if (!firstAddr) try writer.writeAll(", ");
                    try writer.print("\"{x}\"", .{addr});
                    firstAddr = false;
                }
            }
            try writer.writeAll("]");
        }

        // Trace ID
        if (record.traceId) |tid| {
            try writer.writeAll(comma);
            try writer.writeAll(indent);
            try writer.writeAll("\"traceId\"");
            try writer.writeAll(sep);
            try writer.writeByte('"');
            try escapeJsonString(writer, tid);
            try writer.writeByte('"');
        }

        // Span ID
        if (record.spanId) |sid| {
            try writer.writeAll(comma);
            try writer.writeAll(indent);
            try writer.writeAll("\"spanId\"");
            try writer.writeAll(sep);
            try writer.writeByte('"');
            try escapeJsonString(writer, sid);
            try writer.writeByte('"');
        }

        // Parent Span ID
        if (record.parentSpanId) |pid| {
            try writer.writeAll(comma);
            try writer.writeAll(indent);
            try writer.writeAll("\"parentSpanId\"");
            try writer.writeAll(sep);
            try writer.writeByte('"');
            try escapeJsonString(writer, pid);
            try writer.writeByte('"');
        }

        // Context fields
        if (record.context.count() > 0) {
            try writer.writeAll(comma);
            try writer.writeAll(indent);
            try writer.writeAll("\"context\"");
            try writer.writeAll(sep);
            try writer.writeByte('{');
            try writer.writeAll(newline);

            var it = record.context.iterator();
            var first = true;
            while (it.next()) |entry| {
                if (!first) {
                    try writer.writeAll(comma);
                }
                try writer.writeAll(indent);
                try writer.writeAll(indent);
                try writer.writeByte('"');
                try writer.writeAll(entry.key_ptr.*);
                try writer.writeAll("\"");
                try writer.writeAll(sep);

                switch (entry.value_ptr.*) {
                    .string => |s| {
                        try writer.writeByte('"');
                        try escapeJsonString(writer, s);
                        try writer.writeByte('"');
                    },
                    .integer => |i| try Utils.writeInt(writer, i), // Utils.writeInt handles signed i64
                    .float => |f| try writer.print("{d}", .{f}),
                    .bool => |b| try writer.writeAll(if (b) "true" else "false"),
                    else => try writer.writeAll("null"),
                }
                first = false;
            }
            try writer.writeAll(newline);
            try writer.writeAll(indent);
            try writer.writeByte('}');
        }

        // Invoke messages
        if (record.invokeMessages) |messages| {
            try writer.writeAll(comma);
            try writer.writeAll(indent);
            try writer.writeAll("\"invoke\"");
            try writer.writeAll(sep);
            const Invoke = @import("invoke.zig").Invoke;
            var invokeTemp = Invoke.init(self.allocator);
            defer invokeTemp.deinit();
            try invokeTemp.formatMessagesJson(messages, writer, pretty);
        }

        try writer.writeAll(newline);
        try writer.writeAll("}");
    }

    /// Returns true if the formatter has a custom theme.
    pub fn hasTheme(self: *const Formatter) bool {
        return self.theme != null;
    }

    /// Resets statistics.
    pub fn resetStats(self: *Formatter) void {
        self.stats = .{};
    }

    /// Formats a log record as logfmt.
    pub fn formatLogfmt(self: *Formatter, record: *const Record, config: anytype) ![]u8 {
        return self.formatLogfmtWithAllocator(record, config, null);
    }

    /// Formats a log record as logfmt using the provided allocator.
    pub fn formatLogfmtWithAllocator(self: *Formatter, record: *const Record, config: anytype, scratchAllocator: ?std.mem.Allocator) ![]u8 {
        const alloc = scratchAllocator orelse self.allocator;
        var buf = std.Io.Writer.Allocating.init(alloc);
        errdefer buf.deinit();
        try self.formatLogfmtToWriter(&buf.writer, record, config);
        return buf.toOwnedSlice();
    }

    /// Formats a log record as logfmt directly to a writer.
    pub fn formatLogfmtToWriter(self: *Formatter, writer: anytype, record: *const Record, config: anytype) !void {
        // Write standard logfmt: ts=... level=... msg=... [optional fields] [context fields]
        try writer.writeAll("ts=");
        var tsBuf: [64]u8 = undefined;
        var tsWriter = std.Io.Writer.fixed(&tsBuf);
        try self.writeTimestamp(&tsWriter, record.timestamp, config);
        try writeLogfmtValue(writer, tsBuf[0..tsWriter.end]);

        try writer.writeAll(" level=");
        try writeLogfmtValue(writer, record.levelName());

        try writer.writeAll(" msg=");
        try writeLogfmtValue(writer, record.message);

        if (record.module) |m| {
            try writer.writeAll(" module=");
            try writeLogfmtValue(writer, m);
        }
        if (record.function) |f| {
            try writer.writeAll(" function=");
            try writeLogfmtValue(writer, f);
        }
        if (record.filename) |f| {
            try writer.writeAll(" file=");
            try writeLogfmtValue(writer, f);
        }
        if (record.line) |l| {
            try writer.writeAll(" line=");
            try writer.print("{d}", .{l});
        }
        if (config.includePid) {
            try writer.writeAll(" pid=");
            try writer.print("{d}", .{self.pid});
        }
        if (config.includeHostname) {
            try writer.writeAll(" hostname=");
            if (self.hostname) |h| {
                try writeLogfmtValue(writer, h);
            } else {
                try writer.writeAll("unknown-host");
            }
        }
        if (record.traceId) |tid| {
            try writer.writeAll(" traceId=");
            try writeLogfmtValue(writer, tid);
        }
        if (record.spanId) |sid| {
            try writer.writeAll(" spanId=");
            try writeLogfmtValue(writer, sid);
        }
        if (record.parentSpanId) |pid| {
            try writer.writeAll(" parentSpanId=");
            try writeLogfmtValue(writer, pid);
        }

        if (@hasField(@TypeOf(config), "distributed") and config.distributed.enabled) {
            if (config.distributed.serviceName) |s| {
                try writer.writeAll(" service=");
                try writeLogfmtValue(writer, s);
            }
            if (config.distributed.serviceVersion) |v| {
                try writer.writeAll(" version=");
                try writeLogfmtValue(writer, v);
            }
            if (config.distributed.environment) |e| {
                try writer.writeAll(" env=");
                try writeLogfmtValue(writer, e);
            }
            if (config.distributed.region) |r| {
                try writer.writeAll(" region=");
                try writeLogfmtValue(writer, r);
            }
            if (config.distributed.datacenter) |d| {
                try writer.writeAll(" datacenter=");
                try writeLogfmtValue(writer, d);
            }
            if (config.distributed.instanceId) |i| {
                try writer.writeAll(" instance_id=");
                try writeLogfmtValue(writer, i);
            }
        }

        var it = record.context.iterator();
        while (it.next()) |entry| {
            try writer.writeByte(' ');
            try writer.writeAll(entry.key_ptr.*);
            try writer.writeByte('=');
            switch (entry.value_ptr.*) {
                .string => |s| try writeLogfmtValue(writer, s),
                .integer => |i| try writer.print("{d}", .{i}),
                .float => |f| try writer.print("{d}", .{f}),
                .bool => |b| try writer.writeAll(if (b) "true" else "false"),
                else => try writer.writeAll("null"),
            }
        }
    }

    /// Formats a log record as RFC5424 syslog.
    ///
    /// `<pri>1 TIMESTAMP HOST APP PID MSGID SD MSG` with UTC RFC3339
    /// timestamps, facility user(1), and `-` for MSGID/structured-data
    /// (documented limitation: no SD params emitted). The message is
    /// flattened to a single line. No trailing newline; the sink adds one.
    pub fn formatSyslog(self: *Formatter, record: *const Record, config: anytype) ![]u8 {
        return self.formatSyslogWithAllocator(record, config, null);
    }

    /// Formats a log record as RFC5424 syslog using an optional allocator.
    pub fn formatSyslogWithAllocator(self: *Formatter, record: *const Record, config: anytype, scratchAllocator: ?std.mem.Allocator) ![]u8 {
        const alloc = scratchAllocator orelse self.allocator;
        var buf = std.Io.Writer.Allocating.init(alloc);
        errdefer buf.deinit();
        try self.formatSyslogToWriter(&buf.writer, record, config);
        return buf.toOwnedSlice();
    }

    /// Formats a log record as RFC5424 syslog directly to a writer.
    pub fn formatSyslogToWriter(self: *Formatter, writer: anytype, record: *const Record, config: anytype) !void {
        const severity = Constants.SyslogConstants.Severity.fromLogLevel(record.level);
        const priority = 1 * 8 + @as(u8, @intCast(@backingInt(severity)));
        try writer.print("<{d}>1 ", .{priority});
        try writeSyslogTimestamp(writer, record.timestamp);
        try writer.writeByte(' ');
        if (self.hostname) |h| {
            try writer.writeAll(h);
        } else {
            try writer.writeAll("unknown-host");
        }
        try writer.writeByte(' ');
        try writer.writeAll(syslogAppName(config));
        try writer.writeByte(' ');
        try Utils.writeInt(writer, self.pid);
        try writer.writeAll(" - - ");
        try writeSingleLine(writer, record.message);
    }

    /// Formats a log record as RFC3164 (BSD) syslog.
    ///
    /// `<pri>Mmm DD HH:MM:SS HOST TAG[PID]: MSG`. Day is space-padded per
    /// the RFC. No trailing newline; the sink adds one.
    pub fn formatSyslog3164(self: *Formatter, record: *const Record, config: anytype) ![]u8 {
        return self.formatSyslog3164WithAllocator(record, config, null);
    }

    /// Formats a log record as RFC3164 syslog using an optional allocator.
    pub fn formatSyslog3164WithAllocator(self: *Formatter, record: *const Record, config: anytype, scratchAllocator: ?std.mem.Allocator) ![]u8 {
        const alloc = scratchAllocator orelse self.allocator;
        var buf = std.Io.Writer.Allocating.init(alloc);
        errdefer buf.deinit();
        try self.formatSyslog3164ToWriter(&buf.writer, record, config);
        return buf.toOwnedSlice();
    }

    /// Formats a log record as RFC3164 syslog directly to a writer.
    pub fn formatSyslog3164ToWriter(self: *Formatter, writer: anytype, record: *const Record, config: anytype) !void {
        const severity = Constants.SyslogConstants.Severity.fromLogLevel(record.level);
        const priority = 1 * 8 + @as(u8, @intCast(@backingInt(severity)));
        const tc = Utils.fromMilliTimestamp(record.timestamp);
        try writer.print("<{d}>", .{priority});
        try writer.writeAll(monthShort(tc.month));
        try writer.writeByte(' ');
        if (tc.day < 10) try writer.writeByte(' ');
        try Utils.writeInt(writer, tc.day);
        try writer.writeByte(' ');
        try Utils.write2Digits(writer, tc.hour);
        try writer.writeByte(':');
        try Utils.write2Digits(writer, tc.minute);
        try writer.writeByte(':');
        try Utils.write2Digits(writer, tc.second);
        try writer.writeByte(' ');
        if (self.hostname) |h| {
            try writer.writeAll(h);
        } else {
            try writer.writeAll("unknown-host");
        }
        try writer.writeByte(' ');
        try writer.writeAll(syslogAppName(config));
        try writer.writeByte('[');
        try Utils.writeInt(writer, self.pid);
        try writer.writeAll("]: ");
        try writeSingleLine(writer, record.message);
    }

    /// Represents a snapshot of the Formatter state and statistics.
    pub const Snapshot = struct {
        totalRecordsFormatted: u64,
        jsonFormats: u64,
        customFormats: u64,
        formatErrors: u64,
        totalBytesFormatted: u64,
        hostname: ?[]const u8 = null,
        pid: usize,
        allocator: std.mem.Allocator,

        pub fn deinit(self: *Snapshot) void {
            if (self.hostname) |h| {
                self.allocator.free(h);
            }
        }
    };

    /// Takes a snapshot of the Formatter statistics and state.
    pub fn getSnapshot(self: *Formatter, allocator: std.mem.Allocator) !Snapshot {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);

        const hostnameCopy = if (self.hostname) |h| try allocator.dupe(u8, h) else null;
        return Snapshot{
            .totalRecordsFormatted = Utils.atomicLoadU64(&self.stats.totalRecordsFormatted),
            .jsonFormats = Utils.atomicLoadU64(&self.stats.jsonFormats),
            .customFormats = Utils.atomicLoadU64(&self.stats.customFormats),
            .formatErrors = Utils.atomicLoadU64(&self.stats.formatErrors),
            .totalBytesFormatted = Utils.atomicLoadU64(&self.stats.totalBytesFormatted),
            .hostname = hostnameCopy,
            .pid = self.pid,
            .allocator = allocator,
        };
    }

    /// Frees resources associated with a snapshot.
    pub fn freeSnapshot(self: *Formatter, snapshot: Snapshot) void {
        _ = self;
        var snap = snapshot;
        snap.deinit();
    }

    /// Formats a log record as MessagePack binary format.
    pub fn formatMsgpackWithAllocator(self: *Formatter, record: *const Record, config: anytype, scratchAllocator: ?std.mem.Allocator) ![]u8 {
        _ = config;
        const alloc = scratchAllocator orelse self.allocator;

        var buf = std.Io.Writer.Allocating.init(alloc);
        errdefer buf.deinit();
        try self.formatMsgpackToWriter(&buf.writer, record);
        return buf.toOwnedSlice();
    }

    /// Formats a log record as MessagePack.
    pub fn formatMsgpack(self: *Formatter, record: *const Record, config: anytype) ![]u8 {
        return self.formatMsgpackWithAllocator(record, config, null);
    }

    /// Writes one log record as MessagePack directly to a writer.
    /// See formatMsgpackToWriterImpl for the wire layout.
    pub fn formatMsgpackToWriter(self: *Formatter, writer: anytype, record: *const Record) !void {
        _ = self;
        try formatMsgpackToWriterImpl(writer, record);
    }
};

fn writePadded(writer: anytype, value: []const u8, spec: []const u8) !void {
    if (spec.len == 0) {
        try writer.writeAll(value);
        return;
    }

    var alignDir: enum { left, right, center } = .left;
    var widthStr = spec;

    if (spec[0] == '>') {
        alignDir = .right;
        widthStr = spec[1..];
    } else if (spec[0] == '<') {
        alignDir = .left;
        widthStr = spec[1..];
    } else if (spec[0] == '^') {
        alignDir = .center;
        widthStr = spec[1..];
    }

    const width = std.fmt.parseInt(usize, widthStr, 10) catch {
        try writer.writeAll(value);
        return;
    };

    if (value.len >= width) {
        try writer.writeAll(value);
    } else {
        const diff = width - value.len;
        switch (alignDir) {
            .left => {
                try writer.writeAll(value);
                var k: usize = 0;
                while (k < diff) : (k += 1) {
                    try writer.writeByte(' ');
                }
            },
            .right => {
                var k: usize = 0;
                while (k < diff) : (k += 1) {
                    try writer.writeByte(' ');
                }
                try writer.writeAll(value);
            },
            .center => {
                const leftPadding = diff / 2;
                const rightPadding = diff - leftPadding;
                var k: usize = 0;
                while (k < leftPadding) : (k += 1) {
                    try writer.writeByte(' ');
                }
                try writer.writeAll(value);
                k = 0;
                while (k < rightPadding) : (k += 1) {
                    try writer.writeByte(' ');
                }
            },
        }
    }
}

fn writeLogfmtValue(writer: anytype, value: []const u8) !void {
    var needsQuoting = false;
    if (value.len == 0) {
        needsQuoting = true;
    } else {
        for (value) |c| {
            if (c == ' ' or c == '=' or c == '"' or c == '\\' or c == '\n' or c == '\r' or c == '\t') {
                needsQuoting = true;
                break;
            }
        }
    }

    if (needsQuoting) {
        try writer.writeByte('"');
        for (value) |c| {
            switch (c) {
                '\\' => try writer.writeAll("\\\\"),
                '"' => try writer.writeAll("\\\""),
                '\n' => try writer.writeAll("\\n"),
                '\r' => try writer.writeAll("\\r"),
                '\t' => try writer.writeAll("\\t"),
                else => try writer.writeByte(c),
            }
        }
        try writer.writeByte('"');
    } else {
        try writer.writeAll(value);
    }
}

/// Flattens a message to a single line for line-oriented wire formats.
fn writeSingleLine(writer: anytype, value: []const u8) !void {
    for (value) |c| {
        switch (c) {
            '\n', '\r' => try writer.writeByte(' '),
            else => try writer.writeByte(c),
        }
    }
}

/// Writes a UTC RFC3339 timestamp with milliseconds for syslog (RFC5424).
fn writeSyslogTimestamp(writer: anytype, timestampMs: i64) !void {
    const tc = Utils.fromMilliTimestamp(timestampMs);
    const absTs = if (timestampMs < 0) 0 else @as(u64, @intCast(timestampMs));
    const millis = absTs % Constants.TimeConstants.msPerSecond;
    try Utils.writeIsoDateTime(writer, tc);
    try writer.writeByte('.');
    try Utils.write3Digits(writer, millis);
    try writer.writeByte('Z');
}

/// Resolves the syslog app name from config, defaulting to "logly".
fn syslogAppName(config: anytype) []const u8 {
    if (@hasField(@TypeOf(config), "appName")) {
        if (config.appName) |name| return name;
    }
    return "logly";
}

/// Three-letter month abbreviation (1-12); out-of-range yields "???".
fn monthShort(month: u8) []const u8 {
    const names = [_][]const u8{
        "Jan", "Feb", "Mar", "Apr", "May", "Jun",
        "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
    };
    if (month >= 1 and month <= 12) return names[month - 1];
    return "???";
}

/// Fetches the current hostname using platform-specific APIs.
fn fetchHostname(allocator: std.mem.Allocator) ![]const u8 {
    const builtin = @import("builtin");
    if (builtin.os.tag == .windows) {
        const win32 = struct {
            extern "kernel32" fn GetComputerNameW(lpBuffer: ?[*]u16, nSize: *u32) callconv(.winapi) i32;
        };
        var buf: [256]u16 = undefined;
        var size: u32 = buf.len;
        if (win32.GetComputerNameW(&buf, &size) != 0) {
            // size does not include null terminator if success
            return std.unicode.utf16LeToUtf8Alloc(allocator, buf[0..size]);
        }
        return error.HostnameFetchFailed;
    } else {
        var buf: [std.posix.HOST_NAME_MAX]u8 = undefined;
        const hostname = try std.posix.gethostname(&buf);
        return try allocator.dupe(u8, hostname);
    }
}

/// Fetches the current process ID in a cross-platform way.
fn fetchPID() usize {
    const builtin = @import("builtin");
    // Use std.posix where available for portability
    if (builtin.os.tag == .windows) {
        return @as(usize, std.os.windows.GetCurrentProcessId());
    }

    // For Linux/macOS/BSD/WASI, try std.posix
    if (@hasDecl(std.posix, "getpid")) {
        return @as(usize, @intCast(std.posix.getpid()));
    }

    // Fallback to libc if linked
    if (builtin.link_libc) {
        return @as(usize, @intCast(std.c.getpid()));
    }

    return 0;
}

/// Pre-built formatter configurations.
pub const FormatterPresets = struct {
    /// Creates a formatter with no colors.
    pub fn plain(allocator: std.mem.Allocator) Formatter {
        var f = Formatter.init(allocator);
        f.theme = null;
        return f;
    }

    /// Creates a formatter with dark theme.
    pub fn dark(allocator: std.mem.Allocator) Formatter {
        var f = Formatter.init(allocator);
        f.theme = Formatter.Theme.dark();
        return f;
    }

    /// Creates a formatter with light theme.
    pub fn light(allocator: std.mem.Allocator) Formatter {
        var f = Formatter.init(allocator);
        f.theme = Formatter.Theme.light();
        return f;
    }
};

/// Formats an offset suffix for test assertions.
fn formatOffsetSuffixForTest(buf: []u8, offsetMinutes: i16) ![]const u8 {
    var writer = std.Io.Writer.fixed(buf);
    try Utils.writeUtcOffset(&writer, offsetMinutes);
    return buf[0..writer.end];
}

test "formatter ISO8601 UTC uses Z suffix" {
    const allocator = std.testing.allocator;
    var formatter = Formatter.init(allocator);
    defer formatter.deinit();

    var record = Record.init(allocator, .info, "UTC test");
    defer record.deinit();
    record.timestamp = 1700000000000;

    var config = Config{};
    config.timeFormat = Config.TimeFormat.iso8601;
    config.timezone = .utc;

    var buf = std.Io.Writer.Allocating.init(allocator);
    defer buf.deinit();

    try formatter.formatJsonToWriter(&buf.writer, &record, config);
    try std.testing.expect(std.mem.indexOf(u8, buf.written(), "Z\"") != null);
}

test "formatter ISO8601 local uses local offset suffix" {
    const allocator = std.testing.allocator;
    var formatter = Formatter.init(allocator);
    defer formatter.deinit();

    var record = Record.init(allocator, .info, "Local timezone test");
    defer record.deinit();
    record.timestamp = 1700000000000;

    var config = Config{};
    config.timeFormat = Config.TimeFormat.iso8601;
    config.timezone = .local;

    var buf = std.Io.Writer.Allocating.init(allocator);
    defer buf.deinit();

    try formatter.formatJsonToWriter(&buf.writer, &record, config);

    const offsetMinutes = Utils.localUtcOffsetMinutes(record.timestamp);
    var expectedOffsetBuf: [6]u8 = undefined;
    const expectedOffset = try formatOffsetSuffixForTest(&expectedOffsetBuf, offsetMinutes);

    try std.testing.expect(std.mem.indexOf(u8, buf.written(), expectedOffset) != null);
    try std.testing.expect(std.mem.indexOf(u8, buf.written(), "Z\"") == null);
}

test "formatter RFC3339 UTC uses +00:00 suffix" {
    const allocator = std.testing.allocator;
    var formatter = Formatter.init(allocator);
    defer formatter.deinit();

    var record = Record.init(allocator, .info, "RFC3339 UTC test");
    defer record.deinit();
    record.timestamp = 1700000000000;

    var config = Config{};
    config.timeFormat = Config.TimeFormat.rfc3339;
    config.timezone = .utc;

    var buf = std.Io.Writer.Allocating.init(allocator);
    defer buf.deinit();

    try formatter.formatJsonToWriter(&buf.writer, &record, config);
    try std.testing.expect(std.mem.indexOf(u8, buf.written(), "+00:00\"") != null);
}

test "formatter RFC3339 local uses local offset suffix" {
    const allocator = std.testing.allocator;
    var formatter = Formatter.init(allocator);
    defer formatter.deinit();

    var record = Record.init(allocator, .info, "RFC3339 local test");
    defer record.deinit();
    record.timestamp = 1700000000000;

    var config = Config{};
    config.timeFormat = Config.TimeFormat.rfc3339;
    config.timezone = .local;

    var buf = std.Io.Writer.Allocating.init(allocator);
    defer buf.deinit();

    try formatter.formatJsonToWriter(&buf.writer, &record, config);

    const offsetMinutes = Utils.localUtcOffsetMinutes(record.timestamp);
    var expectedOffsetBuf: [6]u8 = undefined;
    const expectedOffset = try formatOffsetSuffixForTest(&expectedOffsetBuf, offsetMinutes);

    try std.testing.expect(std.mem.indexOf(u8, buf.written(), expectedOffset) != null);
}

test "formatter unix and unix_ms remain numeric" {
    const allocator = std.testing.allocator;
    var formatter = Formatter.init(allocator);
    defer formatter.deinit();

    var record = Record.init(allocator, .info, "Unix format test");
    defer record.deinit();
    record.timestamp = 1700000000123;

    var unixConfig = Config{};
    unixConfig.timeFormat = Config.TimeFormat.unix;
    unixConfig.timezone = .local;

    var unixBuf = std.Io.Writer.Allocating.init(allocator);
    defer unixBuf.deinit();

    try formatter.formatJsonToWriter(&unixBuf.writer, &record, unixConfig);
    try std.testing.expect(std.mem.indexOf(u8, unixBuf.written(), "\"timestamp\":1700000000") != null);

    var unixMsConfig = Config{};
    unixMsConfig.timeFormat = Config.TimeFormat.unixMs;
    unixMsConfig.timezone = .local;

    var unixMsBuf = std.Io.Writer.Allocating.init(allocator);
    defer unixMsBuf.deinit();

    try formatter.formatJsonToWriter(&unixMsBuf.writer, &record, unixMsConfig);
    try std.testing.expect(std.mem.indexOf(u8, unixMsBuf.written(), "\"timestamp\":1700000000123") != null);
    try std.testing.expect(std.mem.indexOf(u8, unixMsBuf.written(), "\"timestamp\":\"1700000000123\"") == null);
}

test "formatter default time format alias maps to configured default pattern" {
    const allocator = std.testing.allocator;
    var formatter = Formatter.init(allocator);
    defer formatter.deinit();

    var record = Record.init(allocator, .info, "Default alias test");
    defer record.deinit();
    record.timestamp = 1700000000123;

    var config = Config{};
    config.timezone = .utc;
    config.timeFormat = Config.TimeFormat.defaultAlias;

    var buf = std.Io.Writer.Allocating.init(allocator);
    defer buf.deinit();

    try formatter.formatJsonToWriter(&buf.writer, &record, config);

    try std.testing.expect(std.mem.indexOf(u8, buf.written(), "\"timestamp\":\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, buf.written(), "default") == null);
}

test "formatter custom pattern supports timezone tokens" {
    const allocator = std.testing.allocator;
    var formatter = Formatter.init(allocator);
    defer formatter.deinit();

    var record = Record.init(allocator, .info, "Timezone token test");
    defer record.deinit();
    record.timestamp = 1700000000000;

    var config = Config{};
    config.timezone = .local;
    config.timeFormat = "YYYY-MM-DD HH:mm:ss ZZZ ZZ";

    var buf = std.Io.Writer.Allocating.init(allocator);
    defer buf.deinit();

    try formatter.formatJsonToWriter(&buf.writer, &record, config);

    const offsetMinutes = Utils.localUtcOffsetMinutes(record.timestamp);
    var expectedColonBuf: [6]u8 = undefined;
    const expectedColon = try formatOffsetSuffixForTest(&expectedColonBuf, offsetMinutes);

    var expectedCompactBuf: [5]u8 = undefined;
    var compactWriter = std.Io.Writer.fixed(&expectedCompactBuf);
    try Utils.writeUtcOffsetCompact(&compactWriter, offsetMinutes);
    const expectedCompact = expectedCompactBuf[0..compactWriter.end];

    try std.testing.expect(std.mem.indexOf(u8, buf.written(), expectedColon) != null);
    try std.testing.expect(std.mem.indexOf(u8, buf.written(), expectedCompact) != null);
}

test "formatter timestamp helper formats numeric and textual values" {
    const allocator = std.testing.allocator;
    var formatter = Formatter.init(allocator);
    defer formatter.deinit();

    var unixCfg = Config{};
    unixCfg.timezone = .utc;
    unixCfg.timeFormat = Config.TimeFormat.unixMs;

    const unixText = try formatter.formatTimestamp(1700000000123, unixCfg);
    defer allocator.free(unixText);
    try std.testing.expectEqualStrings("1700000000123", unixText);

    var textualCfg = Config{};
    textualCfg.timezone = .utc;
    textualCfg.timeFormat = Config.TimeFormat.defaultAlias;

    const textual = try formatter.formatTimestampWithAllocator(1700000000123, textualCfg, allocator);
    defer allocator.free(textual);

    try std.testing.expect(textual.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, textual, "default") == null);
}

test "formatter template validation" {
    try std.testing.expectEqual(@as(usize, 3), try Formatter.countTemplatePlaceholders("{time} [{level}] {message}"));
    try std.testing.expectEqual(@as(usize, 1), try Formatter.countTemplatePlaceholders("prefix {{literal}} {message}"));
    try Formatter.validateTemplate("{time} - {message}");
    try std.testing.expectError(error.UnbalancedBraces, Formatter.validateTemplate("{time"));
    try std.testing.expectError(error.InvalidTemplate, Formatter.validateTemplate("{}"));
}

test "formatter plain text" {
    const allocator = std.testing.allocator;
    var formatter = Formatter.init(allocator);
    defer formatter.deinit();

    var record = Record.init(allocator, .info, "Test message");
    defer record.deinit();
    record.module = "test_mod";
    record.timestamp = 1700000000000;

    var buf = std.Io.Writer.Allocating.init(allocator);
    defer buf.deinit();

    try formatter.formatToWriter(&buf.writer, &record, Config{});
    const outputStr = buf.written();

    try std.testing.expect(std.mem.indexOf(u8, outputStr, "INFO") != null);
    try std.testing.expect(std.mem.indexOf(u8, outputStr, "test_mod") != null);
    try std.testing.expect(std.mem.indexOf(u8, outputStr, "Test message") != null);
}

test "formatter sink theme applies when config colors are default" {
    const allocator = std.testing.allocator;
    var formatter = Formatter.init(allocator);
    defer formatter.deinit();
    formatter.setTheme(Formatter.Theme.neon());

    var record = Record.init(allocator, .info, "Themed message");
    defer record.deinit();
    record.timestamp = 1700000000000;

    var config = Config{};
    config.color = true;
    config.globalColorDisplay = true;

    var buf = std.Io.Writer.Allocating.init(allocator);
    defer buf.deinit();

    try formatter.formatToWriter(&buf.writer, &record, config);
    const outputStr = buf.written();

    try std.testing.expect(std.mem.indexOf(u8, outputStr, "\x1b[38;5;255m") != null);
}

test "formatter explicit level color overrides sink theme" {
    const allocator = std.testing.allocator;
    var formatter = Formatter.init(allocator);
    defer formatter.deinit();
    formatter.setTheme(Formatter.Theme.neon());

    var record = Record.init(allocator, .info, "Override message");
    defer record.deinit();
    record.timestamp = 1700000000000;

    var config = Config{};
    config.color = true;
    config.globalColorDisplay = true;
    config.levelColors.infoColor = Color.Tint.color.ansi4.magenta;

    var buf = std.Io.Writer.Allocating.init(allocator);
    defer buf.deinit();

    try formatter.formatToWriter(&buf.writer, &record, config);
    const outputStr = buf.written();

    try std.testing.expect(std.mem.indexOf(u8, outputStr, "\x1b[35m") != null);
    try std.testing.expect(std.mem.indexOf(u8, outputStr, "\x1b[38;5;255m") == null);
}

test "formatter json" {
    const allocator = std.testing.allocator;
    var formatter = Formatter.init(allocator);
    defer formatter.deinit();

    var record = Record.init(allocator, .err, "Error occurred");
    defer record.deinit();
    record.module = "api";
    record.timestamp = 1700000000000;

    var buf = std.Io.Writer.Allocating.init(allocator);
    defer buf.deinit();

    try formatter.formatJsonToWriter(&buf.writer, &record, Config{});
    const outputStr = buf.written();

    try std.testing.expect(std.mem.indexOf(u8, outputStr, "\"level\":\"ERROR\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, outputStr, "\"message\":\"Error occurred\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, outputStr, "\"module\":\"api\"") != null);
}

test "formatter json distributed fields" {
    const allocator = std.testing.allocator;
    var formatter = Formatter.init(allocator);
    defer formatter.deinit();

    var record = Record.init(allocator, .info, "Distributed log");
    defer record.deinit();

    // Set trace context
    record.traceId = "trace-123";
    record.spanId = "span-456";

    var config = Config{};
    config.distributed.enabled = true;
    config.distributed.serviceName = "test-service";
    config.distributed.region = "us-east-1";

    var buf = std.Io.Writer.Allocating.init(allocator);
    defer buf.deinit();

    try formatter.formatJsonToWriter(&buf.writer, &record, config);
    const outputStr = buf.written();

    try std.testing.expect(std.mem.indexOf(u8, outputStr, "\"service\":\"test-service\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, outputStr, "\"region\":\"us-east-1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, outputStr, "\"traceId\":\"trace-123\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, outputStr, "\"spanId\":\"span-456\"") != null);
}

test "theme preset default" {
    const theme = Formatter.Theme{};
    try std.testing.expectEqual(Color.Tint.color.ansi4.cyan, theme.trace);
    try std.testing.expectEqual(Color.Tint.color.ansi4.blue, theme.debug);
    try std.testing.expectEqual(Color.Tint.color.ansi4.white, theme.info);
    try std.testing.expectEqual(Color.Tint.color.ansi4.green, theme.success);
    try std.testing.expectEqual(Color.Tint.color.ansi4.yellow, theme.warning);
    try std.testing.expectEqual(Color.Tint.color.ansi4.red, theme.err);
    try std.testing.expectEqual(Color.Tint.color.ansi4.brightRed, theme.critical);
    try std.testing.expectEqual(Color.Tint.color.ansi4.brightWhite, theme.fatal);
}

test "theme preset bright" {
    const theme = Formatter.Theme.bright();
    try std.testing.expectEqual(Color.Tint.color.ansi4.brightCyan, theme.trace);
    try std.testing.expectEqual(Color.Tint.color.ansi4.brightBlue, theme.debug);
    try std.testing.expectEqual(Color.Tint.color.ansi4.brightWhite, theme.info);
    try std.testing.expectEqual(Color.Tint.color.ansi4.brightRed, theme.err);
}

test "theme preset dim" {
    const theme = Formatter.Theme.dim();
    try std.testing.expectEqual(Color.Tint.color.ansi4.cyan, theme.trace);
    try std.testing.expectEqual(Color.Tint.color.ansi4.blue, theme.debug);
    try std.testing.expectEqual(Color.Tint.color.ansi4.white, theme.info);
}

test "theme preset minimal" {
    const theme = Formatter.Theme.minimal();
    try std.testing.expectEqual(Color.Tint.color.ansi4.brightBlack, theme.trace);
    try std.testing.expectEqual(Color.Tint.color.ansi4.brightBlack, theme.debug);
    try std.testing.expectEqual(Color.Tint.color.ansi4.white, theme.info);
}

test "theme preset neon" {
    const theme = Formatter.Theme.neon();
    try std.testing.expectEqual(Color.Tint.color.ansi256.index(51), theme.trace);
    try std.testing.expectEqual(Color.Tint.color.ansi256.index(33), theme.debug);
    try std.testing.expectEqual(Color.Tint.color.ansi256.index(196), theme.err);
}

test "theme preset pastel" {
    const theme = Formatter.Theme.pastel();
    try std.testing.expectEqual(Color.Tint.color.ansi256.index(159), theme.trace);
    try std.testing.expectEqual(Color.Tint.color.ansi256.index(117), theme.debug);
    try std.testing.expectEqual(Color.Tint.color.ansi256.index(210), theme.err);
}

test "theme preset dark" {
    const theme = Formatter.Theme.dark();
    try std.testing.expectEqual(Color.Tint.color.ansi256.index(244), theme.trace);
    try std.testing.expectEqual(Color.Tint.color.ansi256.index(75), theme.debug);
    try std.testing.expectEqual(Color.Tint.color.ansi256.index(203), theme.err);
}

test "theme preset light" {
    const theme = Formatter.Theme.light();
    try std.testing.expectEqual(Color.Tint.color.ansi256.index(242), theme.trace);
    try std.testing.expectEqual(Color.Tint.color.ansi256.index(24), theme.debug);
    try std.testing.expectEqual(Color.Tint.color.ansi256.index(124), theme.err);
}

test "theme getColor" {
    const theme = Formatter.Theme{};
    try std.testing.expectEqual(Color.Tint.color.ansi4.cyan, theme.getColor(.trace));
    try std.testing.expectEqual(Color.Tint.color.ansi4.blue, theme.getColor(.debug));
    try std.testing.expectEqual(Color.Tint.color.ansi4.white, theme.getColor(.info));
    try std.testing.expectEqual(Color.Tint.color.ansi4.yellow, theme.getColor(.warning));
    try std.testing.expectEqual(Color.Tint.color.ansi4.red, theme.getColor(.err));
    try std.testing.expectEqual(Color.Tint.color.ansi4.brightWhite, theme.getColor(.fatal));
}

test "formatter stats" {
    const allocator = std.testing.allocator;
    var formatter = Formatter.init(allocator);
    defer formatter.deinit();

    const stats = formatter.getStats();
    try std.testing.expectEqual(@as(u64, 0), stats.getTotalFormatted());
    try std.testing.expectEqual(@as(u64, 0), stats.getJsonFormats());
    try std.testing.expectEqual(@as(u64, 0), stats.getFormatErrors());
    try std.testing.expect(!stats.hasFormatted());
    try std.testing.expect(!stats.hasErrors());
}

test "formatter preset plain" {
    const allocator = std.testing.allocator;
    var formatter = FormatterPresets.plain(allocator);
    defer formatter.deinit();
    try std.testing.expect(!formatter.hasTheme());
}

test "formatter preset dark" {
    const allocator = std.testing.allocator;
    var formatter = FormatterPresets.dark(allocator);
    defer formatter.deinit();
    try std.testing.expect(formatter.hasTheme());
}

test "formatter preset light" {
    const allocator = std.testing.allocator;
    var formatter = FormatterPresets.light(allocator);
    defer formatter.deinit();
    try std.testing.expect(formatter.hasTheme());
}

test "color style enum" {
    const style = Formatter.ColorStyle.bright;
    try std.testing.expect(style == .bright);
    try std.testing.expect(Formatter.ColorStyle.default != .neon);
}

fn writeMsgpackInt(writer: anytype, val: i64) !void {
    if (val >= 0 and val <= 127) {
        try writer.writeByte(@intCast(val));
    } else if (val >= -32 and val < 0) {
        try writer.writeByte(@bitCast(@as(i8, @intCast(val))));
    } else if (val >= -128 and val <= 127) {
        try writer.writeByte(0xd0);
        try writer.writeByte(@bitCast(@as(i8, @intCast(val))));
    } else if (val >= -32768 and val <= 32767) {
        try writer.writeByte(0xd1);
        try writer.writeInt(i16, @intCast(val), .big);
    } else if (val >= -2147483648 and val <= 2147483647) {
        try writer.writeByte(0xd2);
        try writer.writeInt(i32, @intCast(val), .big);
    } else {
        try writer.writeByte(0xd3);
        try writer.writeInt(i64, val, .big);
    }
}

fn writeMsgpackStr(writer: anytype, str: []const u8) !void {
    const len = str.len;
    if (len <= 31) {
        try writer.writeByte(0xa0 | @as(u8, @intCast(len)));
    } else if (len <= 255) {
        try writer.writeByte(0xd9);
        try writer.writeByte(@intCast(len));
    } else if (len <= 65535) {
        try writer.writeByte(0xda);
        try writer.writeInt(u16, @intCast(len), .big);
    } else {
        try writer.writeByte(0xdb);
        try writer.writeInt(u32, @intCast(len), .big);
    }
    try writer.writeAll(str);
}

/// Maximum nesting depth for MessagePack container encoding. Deeper values
/// encode as nil instead of recursing without bound.
const msgpackMaxDepth: u8 = 16;

/// Writes a JSON value as MessagePack, preserving native types: strings,
/// integers, floats (as f64), booleans, null (as nil), and nested arrays
/// and maps up to msgpackMaxDepth. `number_string` values encode as int or
/// float when they parse, otherwise as strings.
fn writeMsgpackValue(writer: anytype, value: std.json.Value, depth: u8) !void {
    if (depth > msgpackMaxDepth) {
        try writer.writeByte(0xc0);
        return;
    }
    switch (value) {
        .null => try writer.writeByte(0xc0),
        .bool => |b| try writer.writeByte(if (b) 0xc3 else 0xc2),
        .integer => |i| try writeMsgpackInt(writer, i),
        .float => |f| {
            try writer.writeByte(0xcb);
            try writer.writeInt(u64, @bitCast(f), .big);
        },
        .number_string => |s| {
            if (std.fmt.parseInt(i64, s, 10)) |i| {
                try writeMsgpackInt(writer, i);
            } else |_| if (std.fmt.parseFloat(f64, s)) |f| {
                try writer.writeByte(0xcb);
                try writer.writeInt(u64, @bitCast(f), .big);
            } else |_| {
                try writeMsgpackStr(writer, s);
            }
        },
        .string => |s| try writeMsgpackStr(writer, s),
        .array => |arr| {
            if (arr.items.len <= 15) {
                try writer.writeByte(0x90 | @as(u8, @intCast(arr.items.len)));
            } else if (arr.items.len <= 65535) {
                try writer.writeByte(0xdc);
                try writer.writeInt(u16, @intCast(arr.items.len), .big);
            } else {
                try writer.writeByte(0xdd);
                try writer.writeInt(u32, @intCast(arr.items.len), .big);
            }
            for (arr.items) |item| {
                try writeMsgpackValue(writer, item, depth + 1);
            }
        },
        .object => |obj| {
            const count = obj.count();
            if (count <= 15) {
                try writer.writeByte(0x80 | @as(u8, @intCast(count)));
            } else if (count <= 65535) {
                try writer.writeByte(0xde);
                try writer.writeInt(u16, @intCast(count), .big);
            } else {
                try writer.writeByte(0xdf);
                try writer.writeInt(u32, @intCast(count), .big);
            }
            var it = obj.iterator();
            while (it.next()) |entry| {
                try writeMsgpackStr(writer, entry.key_ptr.*);
                try writeMsgpackValue(writer, entry.value_ptr.*, depth + 1);
            }
        },
    }
}

/// Writes one log record as a 7-field MessagePack map directly to a writer:
/// timestamp, level (custom-level aware), message, module, filename, line,
/// context. The top-level map is self-delimiting, so concatenated records
/// form a valid MessagePack stream without separators.
fn formatMsgpackToWriterImpl(writer: anytype, record: *const Record) !void {
    try writer.writeByte(0x87);
    try writeMsgpackStr(writer, "timestamp");
    try writeMsgpackInt(writer, record.timestamp);
    try writeMsgpackStr(writer, "level");
    try writeMsgpackStr(writer, record.levelName());
    try writeMsgpackStr(writer, "message");
    try writeMsgpackStr(writer, record.message);
    try writeMsgpackStr(writer, "module");
    try writeMsgpackStr(writer, record.module orelse "");
    try writeMsgpackStr(writer, "filename");
    try writeMsgpackStr(writer, record.filename orelse "");
    try writeMsgpackStr(writer, "line");
    try writeMsgpackInt(writer, @intCast(record.line orelse 0));
    try writeMsgpackStr(writer, "context");
    const ctxCount = record.context.count();
    if (ctxCount <= 15) {
        try writer.writeByte(0x80 | @as(u8, @intCast(ctxCount)));
    } else if (ctxCount <= 65535) {
        try writer.writeByte(0xde);
        try writer.writeInt(u16, @intCast(ctxCount), .big);
    } else {
        try writer.writeByte(0xdf);
        try writer.writeInt(u32, @intCast(ctxCount), .big);
    }
    var it = record.context.iterator();
    while (it.next()) |entry| {
        try writeMsgpackStr(writer, entry.key_ptr.*);
        try writeMsgpackValue(writer, entry.value_ptr.*, 0);
    }
}

test "formatter Msgpack" {
    const allocator = std.testing.allocator;
    var formatter = Formatter.init(allocator);
    defer formatter.deinit();

    var record = Record.init(allocator, .info, "msgpack test message");
    defer record.deinit();
    record.module = "test_binary";

    // Test Msgpack
    var config = Config.default();
    config.format = .msgpack;
    const msgpackData = try formatter.format(&record, config);
    defer allocator.free(msgpackData);

    try std.testing.expect(msgpackData.len > 0);
    // Map header 0x87
    try std.testing.expectEqual(@as(u8, 0x87), msgpackData[0]);
}

test "formatter horizontal colors whole line" {
    const allocator = std.testing.allocator;
    var formatter = Formatter.init(allocator);
    defer formatter.deinit();

    var record = Record.init(allocator, .info, "hello");
    defer record.deinit();
    record.timestamp = 1700000000000;

    var config = Config{};
    config.color = true;
    config.globalColorDisplay = true;
    config.colorMode = .horizontal;

    var buf = std.Io.Writer.Allocating.init(allocator);
    defer buf.deinit();
    try formatter.formatToWriter(&buf.writer, &record, config);
    const out = buf.written();
    // Horizontal: single level color at start, reset at end.
    try std.testing.expect(std.mem.startsWith(u8, out, "\x1b[37m"));
    try std.testing.expect(std.mem.endsWith(u8, out, "\x1b[0m"));
}

test "formatter vertical colors per column" {
    const allocator = std.testing.allocator;
    var formatter = Formatter.init(allocator);
    defer formatter.deinit();

    var record = Record.init(allocator, .err, "oops");
    defer record.deinit();
    record.timestamp = 1700000000000;

    var config = Config{};
    config.color = true;
    config.globalColorDisplay = true;
    config.colorMode = .vertical;
    config.columnColors.timestamp = Color.Tint.color.ansi4.blue;
    config.columnColors.message = Color.Tint.color.ansi4.yellow;

    var buf = std.Io.Writer.Allocating.init(allocator);
    defer buf.deinit();
    try formatter.formatToWriter(&buf.writer, &record, config);
    const out = buf.written();
    // Vertical: timestamp blue, level red (default), message yellow, each reset.
    try std.testing.expect(std.mem.indexOf(u8, out, "\x1b[34m[") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\x1b[31m[ERROR]") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\x1b[33moops\x1b[0m") != null);
}

test "formatter vertical level override wins" {
    const allocator = std.testing.allocator;
    var formatter = Formatter.init(allocator);
    defer formatter.deinit();

    var record = Record.init(allocator, .info, "hi");
    defer record.deinit();
    record.timestamp = 1700000000000;

    var config = Config{};
    config.color = true;
    config.globalColorDisplay = true;
    config.colorMode = .vertical;
    config.levelColors.infoColor = Color.Tint.color.ansi4.magenta;
    config.columnColors.level = Color.Tint.color.ansi4.cyan;

    var buf = std.Io.Writer.Allocating.init(allocator);
    defer buf.deinit();
    try formatter.formatToWriter(&buf.writer, &record, config);
    // Column color wins over level override for the level field.
    try std.testing.expect(std.mem.indexOf(u8, buf.written(), "\x1b[36m[INFO]") != null);
}

test "formatter color transitions reset" {
    const allocator = std.testing.allocator;
    var formatter = Formatter.init(allocator);
    defer formatter.deinit();

    var config = Config{};
    config.color = true;
    config.globalColorDisplay = true;
    config.colorMode = .vertical;
    config.columnColors.message = Color.Tint.color.ansi4.green;

    // INFO then ERROR: each record ends reset, no leakage.
    for ([_]Level{ .info, .err, .debug, .warning }) |lvl| {
        var record = Record.init(allocator, lvl, "msg");
        defer record.deinit();
        record.timestamp = 1700000000000;
        var buf = std.Io.Writer.Allocating.init(allocator);
        defer buf.deinit();
        try formatter.formatToWriter(&buf.writer, &record, config);
        try std.testing.expect(std.mem.endsWith(u8, buf.written(), &[_]u8{ 0x1b, '[', '0', 'm' }));
    }
}

test "formatter syslog5424 framing" {
    const allocator = std.testing.allocator;
    var formatter = Formatter.init(allocator);
    defer formatter.deinit();

    var record = Record.init(allocator, .err, "disk failing\nnow");
    defer record.deinit();
    record.timestamp = 1700000000000;

    var config = Config{};
    config.format = .syslog;
    const out = try formatter.formatSyslog(&record, config);
    defer allocator.free(out);

    // facility user(1) * 8 + err(3) = 11, RFC5424 version 1, UTC timestamp.
    try std.testing.expect(std.mem.startsWith(u8, out, "<11>1 "));
    try std.testing.expect(std.mem.indexOf(u8, out, "T") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "Z ") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, " - - ") != null);
    // Message flattened to one line, no trailing newline from formatter.
    try std.testing.expect(std.mem.indexOf(u8, out, "disk failing now") != null);
    try std.testing.expect(!std.mem.endsWith(u8, out, "\n"));
}

test "formatter syslog3164 framing" {
    const allocator = std.testing.allocator;
    var formatter = Formatter.init(allocator);
    defer formatter.deinit();

    var record = Record.init(allocator, .warning, "high latency");
    defer record.deinit();
    record.timestamp = 1700000000000;

    var config = Config{};
    config.format = .syslog3164;
    const out = try formatter.formatSyslog3164(&record, config);
    defer allocator.free(out);

    // facility user(1) * 8 + warning(4) = 12, BSD timestamp, TAG[PID].
    try std.testing.expect(std.mem.startsWith(u8, out, "<12>"));
    try std.testing.expect(std.mem.indexOf(u8, out, "]: high latency") != null);
    try std.testing.expect(!std.mem.endsWith(u8, out, "\n"));
}

test "formatter msgpack typed values" {
    const allocator = std.testing.allocator;
    var formatter = Formatter.init(allocator);
    defer formatter.deinit();

    var record = Record.initCustom(allocator, .info, "AUDIT", Color.Tint.color.ansi4.cyan, "audit event");
    defer record.deinit();
    record.timestamp = 1700000000000;
    try record.context.put("ok", .{ .bool = true });
    try record.context.put("n", .{ .integer = -5 });
    try record.context.put("nothing", .null);

    var config = Config{};
    config.format = .msgpack;
    const out = try formatter.formatMsgpack(&record, config);
    defer allocator.free(out);

    // Map header, custom level name, typed values incl. nil (0xc0).
    try std.testing.expectEqual(@as(u8, 0x87), out[0]);
    try std.testing.expect(std.mem.indexOf(u8, out, "AUDIT") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "nothing") != null);
    var hasNil = false;
    for (out) |b| {
        if (b == 0xc0) {
            hasNil = true;
            break;
        }
    }
    try std.testing.expect(hasNil);
}

test "formatter json has no ansi" {
    const allocator = std.testing.allocator;
    var formatter = Formatter.init(allocator);
    defer formatter.deinit();

    var record = Record.init(allocator, .err, "boom");
    defer record.deinit();
    record.timestamp = 1700000000000;

    var config = Config{};
    config.format = .json;
    config.color = true;
    config.globalColorDisplay = true;
    const out = try formatter.formatJson(&record, config);
    defer allocator.free(out);

    try std.testing.expect(std.mem.indexOf(u8, out, "\x1b") == null);
}

test "resolver precedence custom override default" {
    // customLevelColor wins over everything.
    var record = Record.init(std.testing.allocator, .info, "x");
    defer record.deinit();
    record.customLevelColor = Color.Tint.color.ansi4.magenta;
    var config = Config{};
    config.levelColors.infoColor = Color.Tint.color.ansi4.cyan;
    try std.testing.expectEqual(Color.Tint.color.ansi4.magenta, Formatter.resolveRecordColor(&record, config, null).?);
    // Per-level override wins over the default palette.
    record.customLevelColor = null;
    try std.testing.expectEqual(Color.Tint.color.ansi4.cyan, Formatter.resolveRecordColor(&record, config, null).?);
    // Disabled paths resolve to null.
    config.colorMode = .none;
    try std.testing.expect(Formatter.resolveRecordColor(&record, config, null) == null);
    config.colorMode = .horizontal;
    config.color = false;
    try std.testing.expect(Formatter.resolveRecordColor(&record, config, null) == null);
    config.color = true;
    config.globalColorDisplay = false;
    try std.testing.expect(Formatter.resolveRecordColor(&record, config, null) == null);
}

test "wrapPresented round-trips bytes" {
    const allocator = std.testing.allocator;
    const bytes = "{\"level\":\"INFO\"}";
    const out = try Formatter.wrapPresented(allocator, Color.Tint.color.ansi4.green, bytes);
    defer allocator.free(out);
    const seq = Color.sequence(Color.Tint.color.ansi4.green, Color.defaultCapability);
    try std.testing.expect(std.mem.startsWith(u8, out, seq.slice()));
    try std.testing.expect(std.mem.endsWith(u8, out, Color.resetAll));
    try std.testing.expectEqualStrings(bytes, out[seq.slice().len .. out.len - Color.resetAll.len]);
}

test "highlighted json keeps valid data" {
    const allocator = std.testing.allocator;
    var formatter = Formatter.init(allocator);
    defer formatter.deinit();

    var record = Record.init(allocator, .warning, "hello \"quoted\" world");
    defer record.deinit();
    record.timestamp = 1700000000000;
    record.module = "svc";
    try record.context.put("user", .{ .string = "bob" });
    try record.context.put("n", .{ .integer = 3 });

    var config = Config{};
    config.colorMode = .vertical;
    config.columnColors.timestamp = Color.Tint.color.ansi4.blue;
    config.columnColors.message = Color.Tint.color.ansi4.yellow;
    const out = try formatter.formatJsonHighlighted(&record, config);
    defer allocator.free(out);

    // Ends with a single reset: no bleed.
    try std.testing.expect(std.mem.endsWith(u8, out, Color.resetAll));
    // Timestamp key recolored away from the base level color.
    const baseSeq = Color.sequence(Color.Tint.color.ansi4.yellow, Color.defaultCapability);
    const tsSeq = Color.sequence(Color.Tint.color.ansi4.blue, Color.defaultCapability);
    try std.testing.expect(std.mem.startsWith(u8, out, baseSeq.slice()));
    try std.testing.expect(std.mem.indexOf(u8, out, tsSeq.slice()) != null);
    // Key bytes intact, quotes and escapes preserved.
    try std.testing.expect(std.mem.indexOf(u8, out, "\"timestamp\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\\\"quoted\\\"") != null);
    // Strip ANSI -> byte-identical to the plain rendering.
    const plain = try formatter.formatJson(&record, config);
    defer allocator.free(plain);
    const stripped = try stripAnsiForTest(allocator, out);
    defer allocator.free(stripped);
    try std.testing.expectEqualStrings(plain, stripped);
    // ... which parses.
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, stripped, .{});
    defer parsed.deinit();
    try std.testing.expect(parsed.value == .object);
}

test "highlighted pretty json is multiline safe" {
    const allocator = std.testing.allocator;
    var formatter = Formatter.init(allocator);
    defer formatter.deinit();

    var record = Record.init(allocator, .info, "multi\nline");
    defer record.deinit();
    record.timestamp = 1700000000000;

    var config = Config{};
    config.prettyJson = true;
    const out = try formatter.formatJsonHighlighted(&record, config);
    defer allocator.free(out);

    try std.testing.expect(std.mem.endsWith(u8, out, Color.resetAll));
    try std.testing.expect(std.mem.indexOf(u8, out, "\n") != null);
    const stripped = try stripAnsiForTest(allocator, out);
    defer allocator.free(stripped);
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, stripped, .{});
    defer parsed.deinit();
    try std.testing.expect(parsed.value == .object);
}

/// Strips ANSI SGR sequences (test helper only, not a product parser).
fn stripAnsiForTest(allocator: std.mem.Allocator, s: []const u8) ![]u8 {
    var out = std.Io.Writer.Allocating.init(allocator);
    errdefer out.deinit();
    var i: usize = 0;
    while (i < s.len) {
        if (s[i] == 0x1b and i + 1 < s.len and s[i + 1] == '[') {
            i += 2;
            while (i < s.len and s[i] != 'm') : (i += 1) {}
            i += @intFromBool(i < s.len);
        } else {
            try out.writer.writeByte(s[i]);
            i += 1;
        }
    }
    return out.toOwnedSlice();
}
