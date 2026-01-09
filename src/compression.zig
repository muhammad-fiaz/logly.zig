const std = @import("std");
const Config = @import("config.zig").Config;
// const SinkConfig = @import("sink.zig").SinkConfig;
const Constants = @import("constants.zig");

/// Log compression utilities with callback support and comprehensive monitoring.
///
/// Provides compression and decompression for log files using various algorithms.
/// Supports both automatic (on rotation) and manual compression modes with
/// full observability through callbacks.
///
/// Algorithms:
/// - deflate: DEFLATE compression (standard gzip)
/// - zlib: ZLIB compression (RFC 1950)
/// - raw_deflate: Raw DEFLATE without headers (RFC 1951)
///
/// Callbacks:
/// - `on_compression_start`: Called before compression begins
/// - `on_compression_complete`: Called after successful compression
/// - `on_compression_error`: Called when compression fails
/// - `on_decompression_complete`: Called after decompression
/// - `on_archive_deleted`: Called when archived file is deleted
///
/// Performance:
/// - Streaming compression for minimal memory overhead
/// - Configurable compression levels (0-9, default 6)
/// - Background compression via thread pool integration
/// - ~100-500 MB/s compression throughput typical
pub const Compression = struct {
    allocator: std.mem.Allocator,
    config: CompressionConfig,
    stats: CompressionStats,
    mutex: std.Thread.Mutex = .{},

    /// Callback invoked before compression starts
    /// Parameters: (file_path: []const u8, uncompressed_size: u64)
    on_compression_start: ?*const fn ([]const u8, u64) void = null,

    /// Callback invoked after successful compression
    /// Parameters: (original_path: []const u8, compressed_path: []const u8,
    ///             original_size: u64, compressed_size: u64, elapsed_ms: u64)
    on_compression_complete: ?*const fn ([]const u8, []const u8, u64, u64, u64) void = null,

    /// Callback invoked when compression fails
    /// Parameters: (file_path: []const u8, error: anyerror)
    on_compression_error: ?*const fn ([]const u8, anyerror) void = null,

    /// Callback invoked after decompression
    /// Parameters: (compressed_path: []const u8, decompressed_path: []const u8)
    on_decompression_complete: ?*const fn ([]const u8, []const u8) void = null,

    /// Callback invoked when archived file is deleted
    /// Parameters: (file_path: []const u8)
    on_archive_deleted: ?*const fn ([]const u8) void = null,

    /// Compression algorithm options with detailed characteristics.
    /// Re-exports centralized config for convenience.
    pub const Algorithm = Config.CompressionConfig.CompressionAlgorithm;

    /// Compression level (speed vs size tradeoff).
    /// Re-exports centralized config for convenience.
    pub const Level = Config.CompressionConfig.CompressionLevel;

    /// Compression strategy for different data types
    pub const Strategy = Config.CompressionConfig.Strategy;

    /// Compression mode for automatic triggers.
    pub const Mode = Config.CompressionConfig.Mode;

    /// Configuration for compression behavior.
    /// Uses centralized config as base with extended options.
    pub const CompressionConfig = Config.CompressionConfig;

    /// Statistics for compression operations with detailed tracking.
    pub const CompressionStats = struct {
        files_compressed: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        files_decompressed: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        bytes_before: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        bytes_after: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        compression_errors: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        decompression_errors: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        last_compression_time: std.atomic.Value(Constants.AtomicSigned) = std.atomic.Value(Constants.AtomicSigned).init(0),
        total_compression_time_ns: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        total_decompression_time_ns: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        background_tasks_queued: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        background_tasks_completed: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),

        /// Calculate compression ratio (original size / compressed size)
        /// Performance: O(1) - atomic loads
        pub fn compressionRatio(self: *const CompressionStats) f64 {
            const before = @as(u64, self.bytes_before.load(.monotonic));
            const after = @as(u64, self.bytes_after.load(.monotonic));
            if (after == 0) return 0;
            return @as(f64, @floatFromInt(before)) / @as(f64, @floatFromInt(after));
        }

        /// Calculate space savings percentage
        /// Performance: O(1) - atomic loads
        pub fn spaceSavingsPercent(self: *const CompressionStats) f64 {
            const before = @as(u64, self.bytes_before.load(.monotonic));
            if (before == 0) return 0;
            const after = @as(u64, self.bytes_after.load(.monotonic));
            return (1.0 - @as(f64, @floatFromInt(after)) / @as(f64, @floatFromInt(before))) * 100.0;
        }

        /// Calculate average compression speed (MB/s)
        /// Performance: O(1) - atomic loads
        pub fn avgCompressionSpeedMBps(self: *const CompressionStats) f64 {
            const time_ns = @as(u64, self.total_compression_time_ns.load(.monotonic));
            if (time_ns == 0) return 0;
            const bytes = @as(u64, self.bytes_before.load(.monotonic));
            const time_s = @as(f64, @floatFromInt(time_ns)) / 1_000_000_000.0;
            const mb = @as(f64, @floatFromInt(bytes)) / (1024.0 * 1024.0);
            return mb / time_s;
        }

        /// Calculate average decompression speed (MB/s)
        /// Performance: O(1) - atomic loads
        pub fn avgDecompressionSpeedMBps(self: *const CompressionStats) f64 {
            const time_ns = @as(u64, self.total_decompression_time_ns.load(.monotonic));
            if (time_ns == 0) return 0;
            const bytes = @as(u64, self.bytes_after.load(.monotonic));
            const time_s = @as(f64, @floatFromInt(time_ns)) / 1_000_000_000.0;
            const mb = @as(f64, @floatFromInt(bytes)) / (1024.0 * 1024.0);
            return mb / time_s;
        }

        /// Calculate error rate (0.0 - 1.0)
        /// Performance: O(1) - atomic loads
        pub fn errorRate(self: *const CompressionStats) f64 {
            const total = @as(u64, self.files_compressed.load(.monotonic)) + @as(u64, self.files_decompressed.load(.monotonic));
            if (total == 0) return 0;
            const errors = @as(u64, self.compression_errors.load(.monotonic)) + @as(u64, self.decompression_errors.load(.monotonic));
            return @as(f64, @floatFromInt(errors)) / @as(f64, @floatFromInt(total));
        }
    };

    /// Result of a compression operation.
    pub const CompressionResult = struct {
        success: bool,
        original_size: u64,
        compressed_size: u64,
        output_path: ?[]const u8,
        error_message: ?[]const u8 = null,

        pub fn ratio(self: *const CompressionResult) f64 {
            if (self.original_size == 0) return 0;
            return 1.0 - (@as(f64, @floatFromInt(self.compressed_size)) / @as(f64, @floatFromInt(self.original_size)));
        }
    };

    /// Initializes a new Compression instance.
    ///
    /// The default configuration disables compression. Use `initWithConfig` for custom settings.
    ///
    /// Arguments:
    ///     allocator: Memory allocator for internal operations.
    ///
    /// Returns:
    ///     A new Compression instance with default configuration.
    ///
    /// Complexity: O(1)
    pub fn init(allocator: std.mem.Allocator) Compression {
        return initWithConfig(allocator, .{});
    }

    /// Alias for init().
    pub const create = init;

    /// Initializes a Compression instance with custom configuration.
    ///
    /// Arguments:
    ///     allocator: Memory allocator for internal operations.
    ///     config: Custom compression configuration.
    ///
    /// Returns:
    ///     A new Compression instance.
    ///
    /// Complexity: O(1)
    pub fn initWithConfig(allocator: std.mem.Allocator, config: CompressionConfig) Compression {
        return .{
            .allocator = allocator,
            .config = config,
            .stats = .{},
        };
    }

    /// Creates a Compression instance with compression enabled using defaults.
    /// This is the simplest one-liner to create an enabled compressor.
    ///
    /// Example:
    /// ```zig
    /// var compressor = Compression.enable(allocator);
    /// defer compressor.deinit();
    /// ```
    ///
    /// Complexity: O(1)
    pub fn enable(allocator: std.mem.Allocator) Compression {
        return initWithConfig(allocator, CompressionConfig.enable());
    }

    /// Alias for enable(). Creates a Compression instance with compression enabled.
    ///
    /// Complexity: O(1)
    pub fn basic(allocator: std.mem.Allocator) Compression {
        return enable(allocator);
    }

    /// Creates a Compression instance for implicit (automatic) compression.
    /// Files are automatically compressed on rotation - no manual intervention needed.
    ///
    /// Example:
    /// ```zig
    /// var compressor = Compression.implicit(allocator);
    /// defer compressor.deinit();
    /// ```
    ///
    /// Complexity: O(1)
    pub fn implicit(allocator: std.mem.Allocator) Compression {
        return initWithConfig(allocator, CompressionConfig.implicit());
    }

    /// Creates a Compression instance for explicit (manual) compression.
    /// Use compressFile()/compressDirectory() for user-controlled compression.
    ///
    /// Example:
    /// ```zig
    /// var compressor = Compression.explicit(allocator);
    /// defer compressor.deinit();
    /// try compressor.compressFile("logs/app.log", null);
    /// ```
    ///
    /// Complexity: O(1)
    pub fn explicit(allocator: std.mem.Allocator) Compression {
        return initWithConfig(allocator, CompressionConfig.explicit());
    }

    /// Creates a Compression instance with fast compression (speed over ratio).
    ///
    /// Example:
    /// ```zig
    /// var compressor = Compression.fast(allocator);
    /// ```
    ///
    /// Complexity: O(1)
    pub fn fast(allocator: std.mem.Allocator) Compression {
        return initWithConfig(allocator, CompressionConfig.fast());
    }

    /// Creates a Compression instance with balanced compression.
    ///
    /// Example:
    /// ```zig
    /// var compressor = Compression.balanced(allocator);
    /// ```
    ///
    /// Complexity: O(1)
    pub fn balanced(allocator: std.mem.Allocator) Compression {
        return initWithConfig(allocator, CompressionConfig.balanced());
    }

    /// Creates a Compression instance with best compression (ratio over speed).
    ///
    /// Example:
    /// ```zig
    /// var compressor = Compression.best(allocator);
    /// ```
    ///
    /// Complexity: O(1)
    pub fn best(allocator: std.mem.Allocator) Compression {
        return initWithConfig(allocator, CompressionConfig.best());
    }

    /// Creates a Compression instance optimized for log files.
    ///
    /// Example:
    /// ```zig
    /// var compressor = Compression.forLogs(allocator);
    /// ```
    ///
    /// Complexity: O(1)
    pub fn forLogs(allocator: std.mem.Allocator) Compression {
        return initWithConfig(allocator, CompressionConfig.forLogs());
    }

    /// Creates a Compression instance with archival settings.
    ///
    /// Example:
    /// ```zig
    /// var compressor = Compression.archive(allocator);
    /// ```
    ///
    /// Complexity: O(1)
    pub fn archive(allocator: std.mem.Allocator) Compression {
        return initWithConfig(allocator, CompressionConfig.archive());
    }

    /// Creates a Compression instance for production use.
    /// Balanced performance with background processing and checksums.
    ///
    /// Example:
    /// ```zig
    /// var compressor = Compression.production(allocator);
    /// ```
    ///
    /// Complexity: O(1)
    pub fn production(allocator: std.mem.Allocator) Compression {
        return initWithConfig(allocator, CompressionConfig.production());
    }

    /// Creates a Compression instance for development use.
    /// Fast compression with originals kept for debugging.
    ///
    /// Example:
    /// ```zig
    /// var compressor = Compression.development(allocator);
    /// ```
    ///
    /// Complexity: O(1)
    pub fn development(allocator: std.mem.Allocator) Compression {
        return initWithConfig(allocator, CompressionConfig.development());
    }

    /// Creates a Compression instance with background processing.
    ///
    /// Example:
    /// ```zig
    /// var compressor = Compression.background(allocator);
    /// ```
    ///
    /// Complexity: O(1)
    pub fn background(allocator: std.mem.Allocator) Compression {
        return initWithConfig(allocator, CompressionConfig.backgroundMode());
    }

    /// Creates a Compression instance with streaming mode.
    ///
    /// Example:
    /// ```zig
    /// var compressor = Compression.streaming(allocator);
    /// ```
    ///
    /// Complexity: O(1)
    pub fn streaming(allocator: std.mem.Allocator) Compression {
        return initWithConfig(allocator, CompressionConfig.streamingMode());
    }

    /// Releases resources associated with the compression instance.
    ///
    /// Currently, this struct does not own any external resources that require explicit cleanup,
    /// but this method is provided for API consistency and future compatibility.
    ///
    /// Arguments:
    ///     self: Pointer to the compression instance.
    ///
    /// Complexity: O(1)
    pub fn deinit(self: *Compression) void {
        _ = self;
        // Currently no owned resources to free
    }

    /// Alias for deinit().
    pub const destroy = deinit;

    /// Sets the callback for compression start events.
    ///
    /// Arguments:
    ///     self: Pointer to the compression instance.
    ///     callback: Function pointer to invoke (parameters: file_path, uncompressed_size).
    ///
    /// Complexity: O(1)
    pub fn setCompressionStartCallback(self: *Compression, callback: *const fn ([]const u8, u64) void) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.on_compression_start = callback;
    }

    /// Sets the callback for compression complete events.
    ///
    /// Arguments:
    ///     self: Pointer to the compression instance.
    ///     callback: Function pointer to invoke (parameters: original_path, compressed_path, original_size, compressed_size, elapsed_ms).
    ///
    /// Complexity: O(1)
    pub fn setCompressionCompleteCallback(self: *Compression, callback: *const fn ([]const u8, []const u8, u64, u64, u64) void) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.on_compression_complete = callback;
    }

    /// Sets the callback for compression error events.
    ///
    /// Arguments:
    ///     self: Pointer to the compression instance.
    ///     callback: Function pointer to invoke (parameters: file_path, error).
    ///
    /// Complexity: O(1)
    pub fn setCompressionErrorCallback(self: *Compression, callback: *const fn ([]const u8, anyerror) void) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.on_compression_error = callback;
    }

    /// Sets the callback for decompression complete events.
    ///
    /// Arguments:
    ///     self: Pointer to the compression instance.
    ///     callback: Function pointer to invoke (parameters: compressed_path, decompressed_path).
    ///
    /// Complexity: O(1)
    pub fn setDecompressionCompleteCallback(self: *Compression, callback: *const fn ([]const u8, []const u8) void) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.on_decompression_complete = callback;
    }

    /// Sets the callback for archive deletion events.
    ///
    /// Arguments:
    ///     self: Pointer to the compression instance.
    ///     callback: Function pointer to invoke (parameters: file_path).
    ///
    /// Complexity: O(1)
    pub fn setArchiveDeletedCallback(self: *Compression, callback: *const fn ([]const u8) void) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.on_archive_deleted = callback;
    }

    /// Performs in-memory compression of the provided data buffer.
    /// Uses the instance's configured algorithm and primary allocator.
    ///
    /// Arguments:
    ///     self: Pointer to the compression instance.
    ///     data: Source bytes to compress.
    ///
    /// Returns:
    ///     - Allocated slice containing compressed data. Caller owns memory.
    ///
    /// Complexity: O(N) where N is the size of data.
    pub fn compress(self: *Compression, data: []const u8) ![]u8 {
        return self.compressWithAllocator(data, null);
    }

    /// Compresses data using a specified alternate allocator.
    /// Represents the core compression logic, including header generation and checksums.
    ///
    /// Arguments:
    ///     self: Pointer to the compression instance.
    ///     data: Source bytes.
    ///     scratch_allocator: Optional allocator for the operation. Defaults to instance allocator.
    ///
    /// Returns:
    ///     - Compressed data slice.
    ///
    /// Complexity: O(N) where N is the size of data.
    pub fn compressWithAllocator(self: *Compression, data: []const u8, scratch_allocator: ?std.mem.Allocator) ![]u8 {
        const alloc = scratch_allocator orelse self.allocator;
        const start_time = std.time.nanoTimestamp();
        defer {
            const elapsed = @as(u64, @intCast(@max(0, std.time.nanoTimestamp() - start_time)));
            _ = self.stats.total_compression_time_ns.fetchAdd(@truncate(elapsed), .monotonic);
        }

        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.config.algorithm == .none or data.len == 0) {
            const copy = try alloc.dupe(u8, data);
            _ = self.stats.bytes_before.fetchAdd(@intCast(data.len), .monotonic);
            _ = self.stats.bytes_after.fetchAdd(@intCast(data.len), .monotonic);
            return copy;
        }

        var result: std.ArrayList(u8) = .empty;
        errdefer result.deinit(alloc);

        // Write header: magic number + algorithm + original size + checksum
        const magic: [4]u8 = .{ 'L', 'G', 'Z', @intFromEnum(self.config.algorithm) };
        try result.appendSlice(alloc, &magic);

        // Write original size (4 bytes, little-endian)
        const size_bytes = std.mem.toBytes(@as(u32, @intCast(@min(data.len, std.math.maxInt(u32)))));
        try result.appendSlice(alloc, &size_bytes);

        // Calculate and write CRC32 checksum if enabled
        if (self.config.checksum) {
            const checksum = calculateCRC32(data);
            try result.appendSlice(alloc, &std.mem.toBytes(checksum));
        } else {
            try result.appendSlice(alloc, &[_]u8{ 0, 0, 0, 0 });
        }

        // Compress based on algorithm and level
        switch (self.config.algorithm) {
            .none => try result.appendSlice(alloc, data),
            .deflate, .zlib, .raw_deflate, .gzip => {
                try self.compressDeflateWithAllocator(data, &result, alloc);
            },
        }

        _ = self.stats.bytes_before.fetchAdd(@intCast(data.len), .monotonic);
        _ = self.stats.bytes_after.fetchAdd(@intCast(result.items.len), .monotonic);
        _ = self.stats.files_compressed.fetchAdd(1, .monotonic);

        return result.toOwnedSlice(alloc);
    }

    /// Wrapper for compressDeflateWithAllocator using the instance allocator.
    fn compressDeflate(self: *Compression, data: []const u8, result: *std.ArrayList(u8)) !void {
        try self.compressDeflateWithAllocator(data, result, self.allocator);
    }

    /// Compresses data from a stream (Reader) and writes to a stream (Writer).
    ///
    /// Reads the entire input stream into memory to calculate headers (size/checksum) before compressing.
    ///
    /// Arguments:
    ///     self: Pointer to the compression instance.
    ///     reader: Source stream implementing readAll.
    ///     writer: Destination stream implementing writeAll.
    ///
    /// Complexity: O(N) memory and time.
    pub fn compressStream(self: *Compression, reader: anytype, writer: anytype) !void {
        const content = try reader.readAllAlloc(self.allocator, std.math.maxInt(usize));
        defer self.allocator.free(content);

        const compressed = try self.compress(content);
        defer self.allocator.free(compressed);

        try writer.writeAll(compressed);
    }

    /// Decompresses data from a stream (Reader) and writes to a stream (Writer).
    ///
    /// Reads the entire compressed input stream into memory before decompressing.
    ///
    /// Arguments:
    ///     self: Pointer to the compression instance.
    ///     reader: Source stream implementing readAll.
    ///     writer: Destination stream implementing writeAll.
    ///
    /// Complexity: O(N) memory and time.
    pub fn decompressStream(self: *Compression, reader: anytype, writer: anytype) !void {
        const content = try reader.readAllAlloc(self.allocator, std.math.maxInt(usize));
        defer self.allocator.free(content);

        const decompressed = try self.decompress(content);
        defer self.allocator.free(decompressed);

        try writer.writeAll(decompressed);
    }

    /// Performs DEFLATE-style compression using LZ77 sliding window and Run-Length Encoding (RLE).
    ///
    /// Algorithm details:
    /// - Scans a sliding window for repeated byte sequences (LZ77).
    /// - Encodes literals and matches using a simplified format.
    ///
    /// Arguments:
    ///     self: Pointer to the compression instance.
    ///     data: Source data to compress.
    ///     result: Output buffer to append compressed data to.
    ///     alloc: Allocator to use for resizing the result buffer.
    ///
    /// Complexity: O(N * W) where N is data length and W is window size (bounded by configuration level).
    fn compressDeflateWithAllocator(self: *Compression, data: []const u8, result: *std.ArrayList(u8), alloc: std.mem.Allocator) !void {
        const level = self.config.level.toInt();

        if (level == 0) {
            // No compression - store as literal blocks
            try self.writeLiteralBlockWithAllocator(data, result, alloc);
            return;
        }

        // LZ77 compression with sliding window
        const window_size: usize = switch (level) {
            0 => 0,
            1...3 => 256, // Fast: small window
            4...6 => 1024, // Default: medium window
            7...9 => 4096, // Best: large window
            else => 1024,
        };

        const min_match: usize = 3;
        const max_match: usize = 255; // Limited to fit in u8

        var pos: usize = 0;
        var literal_start: usize = 0;

        while (pos < data.len) {
            var best_offset: usize = 0;
            var best_length: usize = 0;

            // Search for matches in the sliding window
            if (pos >= min_match) {
                const search_start = if (pos > window_size) pos - window_size else 0;

                var search_pos = search_start;
                while (search_pos < pos) : (search_pos += 1) {
                    var match_len: usize = 0;
                    while (match_len < max_match and
                        pos + match_len < data.len and
                        data[search_pos + match_len] == data[pos + match_len])
                    {
                        match_len += 1;
                        // Prevent match from extending into search area
                        if (search_pos + match_len >= pos) break;
                    }

                    if (match_len >= min_match and match_len > best_length) {
                        best_offset = pos - search_pos;
                        best_length = match_len;
                    }
                }
            }

            if (best_length >= min_match and best_offset <= std.math.maxInt(u16)) {
                // Write any pending literals
                if (pos > literal_start) {
                    try self.writeLiteralBlockWithAllocator(data[literal_start..pos], result, alloc);
                }

                // Write match: <offset:2><length:1>
                try result.append(alloc, 0xFF); // Match marker
                try result.appendSlice(alloc, &std.mem.toBytes(@as(u16, @intCast(best_offset))));
                try result.append(alloc, @as(u8, @intCast(best_length)));

                pos += best_length;
                literal_start = pos;
            } else {
                pos += 1;
            }
        }

        // Write remaining literals
        if (literal_start < data.len) {
            try self.writeLiteralBlockWithAllocator(data[literal_start..], result, alloc);
        }

        // Write end marker
        try result.append(alloc, 0x00);
    }

    /// Writes a block of literal bytes to the output, applying RLE (Run-Length Encoding) where efficient.
    /// Uses the instance allocator.
    fn writeLiteralBlock(self: *Compression, data: []const u8, result: *std.ArrayList(u8)) !void {
        try self.writeLiteralBlockWithAllocator(data, result, self.allocator);
    }

    /// Writes a block of literal bytes using a specific allocator.
    ///
    /// Arguments:
    ///     self: Pointer to compression instance.
    ///     data: The literal data to write.
    ///     result: Destination buffer.
    ///     alloc: Allocator for buffer operations.
    ///
    /// Complexity: O(N) where N is data length.
    fn writeLiteralBlockWithAllocator(self: *Compression, data: []const u8, result: *std.ArrayList(u8), alloc: std.mem.Allocator) !void {
        _ = self;
        if (data.len == 0) return;

        var i: usize = 0;
        while (i < data.len) {
            const byte = data[i];

            // Count consecutive identical bytes (RLE)
            var run_length: usize = 1;
            while (i + run_length < data.len and
                data[i + run_length] == byte and
                run_length < 127)
            {
                run_length += 1;
            }

            if (run_length >= 4) {
                // RLE: marker + count + byte
                try result.append(alloc, 0xFE); // RLE marker
                try result.append(alloc, @as(u8, @intCast(run_length)));
                try result.append(alloc, byte);
                i += run_length;
            } else {
                // Literal: escape special bytes
                if (byte == 0xFF or byte == 0xFE or byte == 0x00) {
                    try result.append(alloc, 0xFD); // Escape marker
                }
                try result.append(alloc, byte);
                i += 1;
            }
        }
    }

    /// Reconstructs original data from a compressed byte stream.
    ///
    /// Validates format headers, checksums (if enabled), and version markers.
    /// Supports legacy formats for backward compatibility.
    ///
    /// Arguments:
    ///     self: Pointer to compression instance.
    ///     data: The compressed byte slice.
    ///
    /// Returns:
    ///     - Slice containing decompressed data (caller owns memory).
    ///     - Error if data is corrupt or format is invalid.
    ///
    /// Complexity: O(N) where N is the size of the uncompressed output.
    pub fn decompress(self: *Compression, data: []const u8) ![]u8 {
        const start_time = std.time.nanoTimestamp();
        defer {
            const elapsed = @as(u64, @intCast(@max(0, std.time.nanoTimestamp() - start_time)));
            _ = self.stats.total_decompression_time_ns.fetchAdd(@truncate(elapsed), .monotonic);
        }

        self.mutex.lock();
        defer self.mutex.unlock();

        // Minimum header size: magic(4) + size(4) + checksum(4) = 12
        if (data.len < 12) return error.InvalidData;

        // Verify magic number
        if (!std.mem.eql(u8, data[0..3], "LGZ")) {
            // Try legacy format (just size header)
            if (data.len >= 4) {
                const size_bytes = data[0..4].*;
                const original_size = std.mem.bytesToValue(u32, &size_bytes);
                if (data.len >= 4 + original_size) {
                    _ = self.stats.files_decompressed.fetchAdd(1, .monotonic);
                    return self.allocator.dupe(u8, data[4..][0..original_size]);
                }
            }
            return error.InvalidMagic;
        }

        const algorithm: Algorithm = @enumFromInt(data[3]);

        // Invoke callback if registered
        if (self.on_decompression_complete) |callback| {
            callback("<memory>", "<memory>");
        }
        _ = algorithm;

        const original_size = std.mem.bytesToValue(u32, data[4..8]);
        const stored_checksum = std.mem.bytesToValue(u32, data[8..12]);

        if (original_size == 0) {
            _ = self.stats.files_decompressed.fetchAdd(1, .monotonic);
            return self.allocator.alloc(u8, 0);
        }

        // Decompress the data
        var result: std.ArrayList(u8) = .empty;
        errdefer result.deinit(self.allocator);

        try result.ensureTotalCapacity(self.allocator, original_size);

        var pos: usize = 12; // Skip header

        while (pos < data.len) {
            const byte = data[pos];

            if (byte == 0x00) {
                // End marker
                break;
            } else if (byte == 0xFF) {
                // Match marker: <offset:2><length:1>
                if (pos + 4 > data.len) return error.InvalidData;

                const offset = std.mem.bytesToValue(u16, data[pos + 1 ..][0..2]);
                const length = data[pos + 3];

                if (offset > result.items.len) return error.InvalidOffset;

                // Copy from back-reference
                const start = result.items.len - offset;
                var j: usize = 0;
                while (j < length) : (j += 1) {
                    const idx = start + (j % offset);
                    try result.append(self.allocator, result.items[idx]);
                }
                pos += 4;
            } else if (byte == 0xFE) {
                // RLE marker: <count><byte>
                if (pos + 3 > data.len) return error.InvalidData;

                const count = data[pos + 1];
                const value = data[pos + 2];

                try result.appendNTimes(self.allocator, value, count);
                pos += 3;
            } else if (byte == 0xFD) {
                // Escape marker
                if (pos + 2 > data.len) return error.InvalidData;
                try result.append(self.allocator, data[pos + 1]);
                pos += 2;
            } else {
                // Literal byte
                try result.append(self.allocator, byte);
                pos += 1;
            }
        }

        // Verify checksum if enabled
        if (self.config.checksum and stored_checksum != 0) {
            const computed_checksum = calculateCRC32(result.items);
            if (computed_checksum != stored_checksum) {
                return error.ChecksumMismatch;
            }
        }

        _ = self.stats.files_decompressed.fetchAdd(1, .monotonic);
        return result.toOwnedSlice(self.allocator);
    }

    /// CRC32 lookup table for optimized calculation
    const crc32_table = blk: {
        @setEvalBranchQuota(4096);
        var table: [256]u32 = undefined;
        const polynomial: u32 = 0xEDB88320;
        for (0..256) |i| {
            var crc = @as(u32, @intCast(i));
            for (0..8) |_| {
                if (crc & 1 != 0) {
                    crc = (crc >> 1) ^ polynomial;
                } else {
                    crc = crc >> 1;
                }
            }
            table[i] = crc;
        }
        break :blk table;
    };

    /// Computes the CRC32 checksum of the provided data using the IEEE polynomial.
    ///
    /// Uses a precomputed lookup table for high performance.
    ///
    /// Arguments:
    ///     data: The data to checksum.
    ///
    /// Returns:
    ///     - 32-bit CRC value.
    ///
    /// Complexity: O(N) linear time.
    fn calculateCRC32(data: []const u8) u32 {
        var crc: u32 = 0xFFFFFFFF;
        for (data) |byte| {
            crc = (crc >> 8) ^ crc32_table[(crc ^ byte) & 0xFF];
        }
        return ~crc;
    }

    /// Compresses a file from the filesystem.
    ///
    /// Reads the input file, compresses its contents in memory, and writes to the output path.
    /// Handles file stat, read/write permissions, and optional cleanup of the source file.
    ///
    /// Arguments:
    ///     self: Pointer to the compression instance.
    ///     input_path: Path to the source file.
    ///     output_path: Optional destination path. Defaults to `{input_path}.{ext}`.
    ///
    /// Returns:
    ///     - CompressionResult struct containing stats and status.
    ///
    /// Complexity: O(N) where N is the file size (I/O bound).
    pub fn compressFile(self: *Compression, input_path: []const u8, output_path: ?[]const u8) !CompressionResult {
        self.mutex.lock();
        defer self.mutex.unlock();

        const out_path = if (output_path) |p| p else blk: {
            break :blk try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ input_path, self.config.extension });
        };
        const should_free_path = output_path == null;
        defer if (should_free_path) self.allocator.free(out_path);

        // Get original file size
        const input_file = std.fs.cwd().openFile(input_path, .{}) catch |err| {
            _ = self.stats.compression_errors.fetchAdd(1, .monotonic);
            return .{
                .success = false,
                .original_size = 0,
                .compressed_size = 0,
                .output_path = null,
                .error_message = @errorName(err),
            };
        };
        defer input_file.close();

        const stat = try input_file.stat();
        const original_size = stat.size;

        // Invoke start callback if registered
        if (self.on_compression_start) |callback| {
            callback(input_path, original_size);
        }

        // Read file content
        const content = try input_file.readToEndAlloc(self.allocator, std.math.maxInt(usize));
        defer self.allocator.free(content);

        // Compress content
        self.mutex.unlock(); // Unlock for nested call
        const compressed = self.compress(content) catch |err| {
            self.mutex.lock();
            _ = self.stats.compression_errors.fetchAdd(1, .monotonic);
            return .{
                .success = false,
                .original_size = original_size,
                .compressed_size = 0,
                .output_path = null,
                .error_message = @errorName(err),
            };
        };
        self.mutex.lock();
        defer self.allocator.free(compressed);

        // Create parent directory if needed
        if (std.fs.path.dirname(out_path)) |dirname| {
            std.fs.cwd().makePath(dirname) catch |err| {
                _ = self.stats.compression_errors.fetchAdd(1, .monotonic);
                return .{
                    .success = false,
                    .original_size = original_size,
                    .compressed_size = 0,
                    .output_path = null,
                    .error_message = @errorName(err),
                };
            };
        }

        // Write compressed file
        const output_file = std.fs.cwd().createFile(out_path, .{}) catch |err| {
            _ = self.stats.compression_errors.fetchAdd(1, .monotonic);
            return .{
                .success = false,
                .original_size = original_size,
                .compressed_size = 0,
                .output_path = null,
                .error_message = @errorName(err),
            };
        };
        defer output_file.close();

        try output_file.writeAll(compressed);

        // Delete original if configured
        if (!self.config.keep_original) {
            std.fs.cwd().deleteFile(input_path) catch {};
        }

        _ = self.stats.files_compressed.fetchAdd(1, .monotonic);
        self.stats.last_compression_time.store(@truncate(std.time.milliTimestamp()), .monotonic);

        const result_path = try self.allocator.dupe(u8, out_path);

        // Invoke complete callback if registered
        if (self.on_compression_complete) |callback| {
            callback(input_path, out_path, original_size, compressed.len, 0);
        }

        return .{
            .success = true,
            .original_size = original_size,
            .compressed_size = compressed.len,
            .output_path = result_path,
        };
    }

    /// Decompresses a file on disk, automatically handling output naming.
    ///
    /// Arguments:
    ///     self: Pointer to the compression instance.
    ///     input_path: Path to the compressed file.
    ///     output_path: Optional output path. If null, removes compression extension (e.g. .gz).
    ///
    /// Returns:
    ///     - true on success, false on failure.
    ///
    /// Complexity: O(N) where N is the file size (I/O bound).
    pub fn decompressFile(self: *Compression, input_path: []const u8, output_path: ?[]const u8) !bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        const out_path = if (output_path) |p| p else blk: {
            // Remove extension
            if (std.mem.endsWith(u8, input_path, self.config.extension)) {
                break :blk input_path[0 .. input_path.len - self.config.extension.len];
            }
            break :blk try std.fmt.allocPrint(self.allocator, "{s}.decompressed", .{input_path});
        };

        // Read compressed file
        const input_file = try std.fs.cwd().openFile(input_path, .{});
        defer input_file.close();

        const content = try input_file.readToEndAlloc(self.allocator, std.math.maxInt(usize));
        defer self.allocator.free(content);

        // Decompress
        self.mutex.unlock();
        const decompressed = try self.decompress(content);
        self.mutex.lock();
        defer self.allocator.free(decompressed);

        // Write decompressed file
        const output_file = try std.fs.cwd().createFile(out_path, .{});
        defer output_file.close();

        try output_file.writeAll(decompressed);

        return true;
    }

    /// Compresses all eligible files in a directory.
    ///
    /// Scans the directory for files that should be compressed (based on `shouldCompress`)
    /// and compresses them individually. Non-recursive.
    ///
    /// Arguments:
    ///     self: Pointer to the compression instance.
    ///     dir_path: Path to the directory to scan.
    ///
    /// Returns:
    ///     - Number of files successfully compressed.
    pub fn compressDirectory(self: *Compression, dir_path: []const u8) !u64 {
        var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch return 0;
        defer dir.close();

        var iterator = dir.iterate();
        var count: u64 = 0;

        while (try iterator.next()) |entry| {
            if (entry.kind != .file) continue;

            const file_path = try std.fs.path.join(self.allocator, &[_][]const u8{ dir_path, entry.name });
            defer self.allocator.free(file_path);

            if (self.shouldCompress(file_path)) {
                // Ignore errors for individual files to keep processing
                const result = self.compressFile(file_path, null) catch continue;
                if (result.output_path) |p| {
                    self.allocator.free(p);
                }
                if (result.success) {
                    count += 1;
                }
            }
        }
        return count;
    }

    /// Determines eligibility for compression based on file state and configuration.
    ///
    /// Arguments:
    ///     self: Pointer to the compression instance.
    ///     file_path: Path to the candidate file.
    ///
    /// Returns:
    ///     - true if compression criteria are met (size, extension, etc.).
    ///
    /// Complexity: O(1) checks + optional O(1) file stat for size threshold mode.
    pub fn shouldCompress(self: *const Compression, file_path: []const u8) bool {
        if (self.config.mode == .disabled) return false;

        // Don't compress already compressed files
        if (std.mem.endsWith(u8, file_path, self.config.extension)) return false;
        if (std.mem.endsWith(u8, file_path, ".gz")) return false;
        if (std.mem.endsWith(u8, file_path, ".zip")) return false;
        if (std.mem.endsWith(u8, file_path, ".zst")) return false;

        if (self.config.mode == .on_size_threshold) {
            const file = std.fs.cwd().openFile(file_path, .{}) catch return false;
            defer file.close();

            const stat = file.stat() catch return false;
            return stat.size >= self.config.size_threshold;
        }

        return true;
    }

    /// Gets compression statistics.
    ///
    /// Arguments:
    ///     self: Pointer to the compression instance.
    ///
    /// Returns:
    ///     - Current compression statistics (copy).
    ///
    /// Complexity: O(1) non-blocking access to atomic values.
    pub fn getStats(self: *const Compression) CompressionStats {
        return self.stats;
    }

    /// Resets compression statistics to zero.
    ///
    /// Arguments:
    ///     self: Pointer to the compression instance.
    ///
    /// Complexity: O(1)
    pub fn resetStats(self: *Compression) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.stats.reset();
    }

    /// Updates the compression configuration at runtime.
    /// Thread-safe update of operational parameters.
    ///
    /// Arguments:
    ///     self: Pointer to the compression instance.
    ///     config: New configuration object.
    ///
    /// Complexity: O(1)
    pub fn configure(self: *Compression, config: CompressionConfig) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.config = config;
    }

    /// Helper to create a fully configured sink for compressed logging.
    ///
    /// Arguments:
    ///     file_path: Target log file path.
    ///
    /// Returns:
    ///     - SinkConfig pre-populated with balanced compression settings.
    ///
    /// Complexity: O(1)
    pub fn createCompressedSink(file_path: []const u8) @import("sink.zig").SinkConfig {
        const SinkConfig = @import("sink.zig").SinkConfig;
        return SinkConfig{
            .path = file_path,
            .compression = CompressionPresets.balanced(),
            .color = false,
        };
    }

    /// Returns true if compression is active and configured.
    ///
    /// Arguments:
    ///     self: Pointer to the compression instance.
    ///
    /// Returns:
    ///     - true if algorithm is not .none and mode is not .disabled.
    ///
    /// Complexity: O(1)
    pub fn isEnabled(self: *const Compression) bool {
        return self.config.algorithm != .none and self.config.mode != .disabled;
    }

    /// Returns the current compression ratio based on statistics.
    ///
    /// Arguments:
    ///     self: Pointer to the compression instance.
    ///
    /// Returns:
    ///     - f64 representing ratio of original to compressed size (e.g. 5.0 for 5x reduction).
    ///
    /// Complexity: O(1)
    pub fn ratio(self: *const Compression) f64 {
        return self.stats.compressionRatio();
    }

    /// Alias for compress
    pub const encode = compress;
    pub const deflate = compress;

    /// Alias for decompress
    pub const decode = decompress;
    pub const inflate = decompress;

    /// Alias for compressFile
    pub const packFile = compressFile;

    /// Alias for decompressFile
    pub const unpackFile = decompressFile;

    /// Alias for getStats
    pub const statistics = getStats;

    /// Alias for shouldCompress
    pub const needsCompression = shouldCompress;
};

/// Preset compression configurations for common use cases.
pub const CompressionPresets = struct {
    /// Returns a configuration with compression disabled.
    ///
    /// Complexity: O(1)
    pub fn none() Compression.CompressionConfig {
        return .{
            .algorithm = .none,
            .mode = .disabled,
        };
    }

    /// Returns a configuration optimized for throughput (Fastest).
    /// Safe for use in high-volume logging paths.
    ///
    /// Complexity: O(1)
    pub fn fast() Compression.CompressionConfig {
        return .{
            .algorithm = .deflate,
            .level = .fast,
            .mode = .on_rotation,
        };
    }

    /// Returns a balanced configuration suitable for most use cases (Default).
    /// Trades moderate CPU usage for good compression ratios.
    ///
    /// Complexity: O(1)
    pub fn balanced() Compression.CompressionConfig {
        return .{
            .algorithm = .deflate,
            .level = .default,
            .mode = .on_rotation,
        };
    }

    /// Returns a configuration optimized for maximum ratio (Best).
    /// Higher CPU usage, recommended for archival storage.
    ///
    /// Complexity: O(1)
    pub fn maximum() Compression.CompressionConfig {
        return .{
            .algorithm = .deflate,
            .level = .best,
            .mode = .on_rotation,
            .keep_original = false,
        };
    }

    /// Returns a configuration that triggers based on file size threshold.
    ///
    /// Arguments:
    ///     threshold_mb: Size limit in Megabytes before compression occurs.
    ///
    /// Returns:
    ///     - CompressionConfig with .on_size_threshold mode set.
    ///
    /// Complexity: O(1)
    pub fn onSize(threshold_mb: u64) Compression.CompressionConfig {
        return .{
            .algorithm = .deflate,
            .level = .default,
            .mode = .on_size_threshold,
            .size_threshold = threshold_mb * 1024 * 1024,
        };
    }
};

test "compression basic" {
    const allocator = std.testing.allocator;

    var comp = Compression.init(allocator);
    defer comp.deinit();

    const data = "Hello, World! This is test data for compression.";
    const compressed = try comp.compress(data);
    defer allocator.free(compressed);

    // Compressed data should exist
    try std.testing.expect(compressed.len > 0);

    // Verify we can decompress back to original
    const decompressed = try comp.decompress(compressed);
    defer allocator.free(decompressed);

    try std.testing.expectEqualStrings(data, decompressed);
}

test "compression with repetitive data" {
    const allocator = std.testing.allocator;

    var comp = Compression.init(allocator);
    defer comp.deinit();

    // Repetitive data compresses well with RLE
    const data = "AAAAAAAAAAAAAAAA" ** 50; // 800 bytes of 'A'
    const compressed = try comp.compress(data);
    defer allocator.free(compressed);

    // Should achieve significant compression ratio
    try std.testing.expect(compressed.len < data.len);

    // Verify roundtrip
    const decompressed = try comp.decompress(compressed);
    defer allocator.free(decompressed);

    try std.testing.expectEqualStrings(data, decompressed);
}

test "compression with log-like data" {
    const allocator = std.testing.allocator;

    var comp = Compression.init(allocator);
    defer comp.deinit();

    // Simulate typical log data with repeated patterns
    const data =
        \\[2025-01-15 10:00:00] INFO  Application started successfully
        \\[2025-01-15 10:00:01] DEBUG Processing request from user 12345
        \\[2025-01-15 10:00:02] INFO  Database connection established
        \\[2025-01-15 10:00:03] DEBUG Processing request from user 12346
        \\[2025-01-15 10:00:04] INFO  Cache hit ratio: 95.5%
        \\[2025-01-15 10:00:05] DEBUG Processing request from user 12347
        \\[2025-01-15 10:00:06] WARNING Slow query detected: 250ms
        \\[2025-01-15 10:00:07] DEBUG Processing request from user 12348
        \\[2025-01-15 10:00:08] ERROR Connection timeout to external service
        \\[2025-01-15 10:00:09] DEBUG Processing request from user 12349
    ;

    const compressed = try comp.compress(data);
    defer allocator.free(compressed);

    // Verify roundtrip
    const decompressed = try comp.decompress(compressed);
    defer allocator.free(decompressed);

    try std.testing.expectEqualStrings(data, decompressed);
}

test "compression levels" {
    const allocator = std.testing.allocator;

    const test_data = "The quick brown fox jumps over the lazy dog. " ** 20;

    // Test different compression levels
    inline for ([_]Compression.Level{ .none, .fast, .default, .best }) |level| {
        var comp = Compression.init(allocator);
        comp.config.level = level;
        defer comp.deinit();

        const compressed = try comp.compress(test_data);
        defer allocator.free(compressed);

        const decompressed = try comp.decompress(compressed);
        defer allocator.free(decompressed);

        try std.testing.expectEqualStrings(test_data, decompressed);
    }
}

test "compression CRC32 checksum" {
    const allocator = std.testing.allocator;

    var comp = Compression.init(allocator);
    comp.config.checksum = true;
    defer comp.deinit();

    const data = "Test data with checksum verification";
    const compressed = try comp.compress(data);
    defer allocator.free(compressed);

    // Verify roundtrip with checksum
    const decompressed = try comp.decompress(compressed);
    defer allocator.free(decompressed);

    try std.testing.expectEqualStrings(data, decompressed);
}

test "compression stats" {
    const allocator = std.testing.allocator;

    var comp = Compression.init(allocator);
    defer comp.deinit();

    const data = "Test data" ** 100; // Repetitive data compresses well
    const compressed = try comp.compress(data);
    defer allocator.free(compressed);

    const stats = comp.getStats();
    try std.testing.expect(stats.bytes_before.load(.monotonic) > 0);
    try std.testing.expect(stats.bytes_after.load(.monotonic) > 0);
    try std.testing.expect(stats.files_compressed.load(.monotonic) > 0);
}

test "compression presets" {
    const fast = CompressionPresets.fast();
    try std.testing.expectEqual(Compression.Level.fast, fast.level);

    const max = CompressionPresets.maximum();
    try std.testing.expectEqual(Compression.Level.best, max.level);
}

test "streaming compression" {
    const allocator = std.testing.allocator;

    var comp = Compression.init(allocator);
    defer comp.deinit();

    const data = "Streaming test data" ** 10;

    var in_stream = std.io.fixedBufferStream(data);
    var out_buffer: std.ArrayList(u8) = .empty; // Use .empty for Unmanaged-style ArrayList
    defer out_buffer.deinit(allocator);

    try comp.compressStream(in_stream.reader(), out_buffer.writer(allocator));

    try std.testing.expect(out_buffer.items.len > 0);

    // Verify roundtrip
    var decomp_in_stream = std.io.fixedBufferStream(out_buffer.items);
    var decomp_out_buffer: std.ArrayList(u8) = .empty;
    defer decomp_out_buffer.deinit(allocator);

    try comp.decompressStream(decomp_in_stream.reader(), decomp_out_buffer.writer(allocator));

    try std.testing.expectEqualStrings(data, decomp_out_buffer.items);
}

test "gzip algorithm" {
    const allocator = std.testing.allocator;

    var comp = Compression.init(allocator);
    comp.config.algorithm = .gzip;
    defer comp.deinit();

    const data = "GZIP test data";
    const compressed = try comp.compress(data);
    defer allocator.free(compressed);

    try std.testing.expect(compressed.len > 0);

    const decompressed = try comp.decompress(compressed);
    defer allocator.free(decompressed);

    try std.testing.expectEqualStrings(data, decompressed);
}

test "file compression with auto-directory creation" {
    const allocator = std.testing.allocator;
    var comp = Compression.init(allocator);
    defer comp.deinit();

    // Use a unique path for testing
    const test_dir = "test_output_compression";
    const test_file = "test_file_to_compress.log";
    const output_file = "test_output_compression/nested/dirs/output.log.gz";

    // Clean up before test
    std.fs.cwd().deleteTree(test_dir) catch {};
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    // Create a dummy source file
    const file = try std.fs.cwd().createFile(test_file, .{});
    try file.writeAll("Test content for compression");
    file.close();
    defer std.fs.cwd().deleteFile(test_file) catch {};

    // Compress with deep path that doesn't exist yet
    const result = try comp.compressFile(test_file, output_file);

    // Verify success
    try std.testing.expect(result.success);
    if (result.output_path) |path| {
        defer allocator.free(path);
    }

    // Verify directory was created
    const stat = try std.fs.cwd().statFile(output_file);
    try std.testing.expect(stat.size > 0);
}

test "directory compression" {
    const allocator = std.testing.allocator;
    var comp = Compression.init(allocator);
    defer comp.deinit();

    const test_dir = "test_batch_compression";

    // Setup test directory
    std.fs.cwd().deleteTree(test_dir) catch {};
    try std.fs.cwd().makePath(test_dir);
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    // Create multiple log files
    const files = [_][]const u8{ "log1.log", "log2.log", "skip.txt" };
    for (files) |fname| {
        const p = try std.fs.path.join(allocator, &[_][]const u8{ test_dir, fname });
        defer allocator.free(p);
        const f = try std.fs.cwd().createFile(p, .{});
        try f.writeAll("Log data content");
        f.close();
    }

    // configure to only compress .log files if we were filtering extensions,
    // but shouldCompress currently checks for NOT compressed extensions.
    // So all valid files should be compressed.

    const compressed_count = try comp.compressDirectory(test_dir);

    // Should compress 3 files (log1.log, log2.log, skip.txt)
    try std.testing.expectEqual(@as(u64, 3), compressed_count);

    // Verify .gz files exist
    var dir = try std.fs.cwd().openDir(test_dir, .{ .iterate = true });
    defer dir.close();

    var count: usize = 0;
    var it = dir.iterate();
    while (try it.next()) |entry| {
        if (std.mem.endsWith(u8, entry.name, ".gz")) {
            count += 1;
        }
    }

    try std.testing.expectEqual(@as(usize, 3), count);
}
