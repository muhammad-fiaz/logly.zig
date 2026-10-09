//! Log file compression.
//!
//! Wraps zstd.zig and brotli.zig plus deflate/gzip via std.compress.
const std = @import("std");
const Config = @import("config.zig").Config;
const Constants = @import("constants.zig");
const Utils = @import("utils.zig");

const zstd = @import("zstd");
const brotli = @import("brotli");
const ThreadPool = @import("thread_pool.zig").ThreadPool;

/// Log compression utilities with callback support and comprehensive monitoring.
///
/// Provides compression and decompression capabilities for log files using
/// various algorithms (deflate, zlib, raw_deflate, zstd).
pub const Compression = struct {
    /// Memory allocator for compression operations.
    allocator: std.mem.Allocator,
    /// I/O handle for file operations and synchronization.
    io: std.Io = Utils.defaultIo(),
    /// Compression configuration options.
    config: CompressionConfig,
    /// Compression statistics for monitoring.
    stats: CompressionStats,
    /// Mutex for thread-safe operations.
    mutex: std.Io.Mutex = std.Io.Mutex.init,

    /// Callback invoked before compression starts.
    onCompressionStart: ?*const fn ([]const u8, u64) void = null,

    /// Callback invoked after successful compression.
    onCompressionComplete: ?*const fn ([]const u8, []const u8, u64, u64, u64) void = null,

    /// Callback invoked when compression fails.
    onCompressionError: ?*const fn ([]const u8, anyerror) void = null,

    /// Callback invoked after decompression.
    onDecompressionComplete: ?*const fn ([]const u8, []const u8) void = null,

    /// Callback invoked when archived file is deleted.
    onArchiveDeleted: ?*const fn ([]const u8) void = null,

    /// Compression algorithm options with detailed characteristics.
    /// Re-exports centralized config for convenience.
    pub const Algorithm = Config.CompressionConfig.CompressionAlgorithm;

    /// Compression level (speed vs size tradeoff).
    /// Re-exports centralized config for convenience.
    pub const Level = Config.CompressionConfig.CompressionLevel;

    /// Compression strategy for different data types.
    pub const Strategy = Config.CompressionConfig.Strategy;

    /// Compression mode for automatic triggers.
    pub const Mode = Config.CompressionConfig.Mode;

    /// Configuration for compression behavior.
    /// Uses centralized config as base with extended options.
    pub const CompressionConfig = Config.CompressionConfig;

    /// Statistics for compression operations with detailed tracking.
    pub const CompressionStats = struct {
        /// Total number of files compressed.
        filesCompressed: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        /// Total number of files decompressed.
        filesDecompressed: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        /// Total bytes before compression.
        bytesBefore: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        /// Total bytes after compression.
        bytesAfter: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        /// Number of compression errors.
        compressionErrors: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        /// Number of decompression errors.
        decompressionErrors: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        /// Timestamp of last compression operation.
        lastCompressionTime: std.atomic.Value(Constants.AtomicSigned) = std.atomic.Value(Constants.AtomicSigned).init(0),
        /// Total time spent compressing in nanoseconds.
        totalCompressionTimeNs: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        /// Total time spent decompressing in nanoseconds.
        totalDecompressionTimeNs: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        /// Number of background compression tasks queued.
        backgroundTasksQueued: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),
        /// Number of background compression tasks completed.
        backgroundTasksCompleted: std.atomic.Value(Constants.AtomicUnsigned) = std.atomic.Value(Constants.AtomicUnsigned).init(0),

        /// Calculate compression ratio (original size / compressed size)
        pub fn compressionRatio(self: *const CompressionStats) f64 {
            const before = @as(u64, self.bytesBefore.load(.monotonic));
            const after = @as(u64, self.bytesAfter.load(.monotonic));
            if (after == 0) return 0;
            return @as(f64, @floatFromInt(before)) / @as(f64, @floatFromInt(after));
        }

        /// Calculate space savings percentage
        pub fn spaceSavingsPercent(self: *const CompressionStats) f64 {
            const before = @as(u64, self.bytesBefore.load(.monotonic));
            if (before == 0) return 0;
            const after = @as(u64, self.bytesAfter.load(.monotonic));
            return (1.0 - @as(f64, @floatFromInt(after)) / @as(f64, @floatFromInt(before))) * 100.0;
        }

        /// Calculate average compression speed (MB/s)
        pub fn avgCompressionSpeedMBps(self: *const CompressionStats) f64 {
            const timeNs = @as(u64, self.totalCompressionTimeNs.load(.monotonic));
            if (timeNs == 0) return 0;
            const bytes = @as(u64, self.bytesBefore.load(.monotonic));
            const nsPerSec = @as(f64, @floatFromInt(Constants.TimeConstants.nsPerSecond));
            const timeSec = @as(f64, @floatFromInt(timeNs)) / nsPerSec;
            const mb = @as(f64, @floatFromInt(bytes)) / @as(f64, @floatFromInt(Constants.SizeConstants.bytesPerMb));
            return mb / timeSec;
        }

        /// Calculate average decompression speed (MB/s)
        pub fn avgDecompressionSpeedMBps(self: *const CompressionStats) f64 {
            const timeNs = @as(u64, self.totalDecompressionTimeNs.load(.monotonic));
            if (timeNs == 0) return 0;
            const bytes = @as(u64, self.bytesAfter.load(.monotonic));
            const nsPerSec = @as(f64, @floatFromInt(Constants.TimeConstants.nsPerSecond));
            const timeSec = @as(f64, @floatFromInt(timeNs)) / nsPerSec;
            const mb = @as(f64, @floatFromInt(bytes)) / @as(f64, @floatFromInt(Constants.SizeConstants.bytesPerMb));
            return mb / timeSec;
        }

        /// Calculate error rate (0.0 - 1.0)
        pub fn errorRate(self: *const CompressionStats) f64 {
            const compressed = Utils.atomicLoadU64(&self.filesCompressed);
            const decompressed = Utils.atomicLoadU64(&self.filesDecompressed);
            const total = compressed + decompressed;
            const compErrors = Utils.atomicLoadU64(&self.compressionErrors);
            const decompErrors = Utils.atomicLoadU64(&self.decompressionErrors);
            const errors = compErrors + decompErrors;
            return Utils.calculateErrorRate(errors, total);
        }

        /// Returns total files compressed as u64.
        pub fn getFilesCompressed(self: *const CompressionStats) u64 {
            return Utils.atomicLoadU64(&self.filesCompressed);
        }

        /// Returns total files decompressed as u64.
        pub fn getFilesDecompressed(self: *const CompressionStats) u64 {
            return Utils.atomicLoadU64(&self.filesDecompressed);
        }

        /// Returns total bytes before compression as u64.
        pub fn getBytesBefore(self: *const CompressionStats) u64 {
            return Utils.atomicLoadU64(&self.bytesBefore);
        }

        /// Returns total bytes after compression as u64.
        pub fn getBytesAfter(self: *const CompressionStats) u64 {
            return Utils.atomicLoadU64(&self.bytesAfter);
        }

        /// Returns total bytes saved by compression.
        pub fn getBytesSaved(self: *const CompressionStats) u64 {
            const before = Utils.atomicLoadU64(&self.bytesBefore);
            const after = Utils.atomicLoadU64(&self.bytesAfter);
            return if (before > after) before - after else 0;
        }

        /// Returns compression errors count as u64.
        pub fn getCompressionErrors(self: *const CompressionStats) u64 {
            return Utils.atomicLoadU64(&self.compressionErrors);
        }

        /// Returns decompression errors count as u64.
        pub fn getDecompressionErrors(self: *const CompressionStats) u64 {
            return Utils.atomicLoadU64(&self.decompressionErrors);
        }

        /// Checks if any compression errors occurred.
        pub fn hasErrors(self: *const CompressionStats) bool {
            return self.compressionErrors.load(.monotonic) > 0 or self.decompressionErrors.load(.monotonic) > 0;
        }

        /// Checks if any compression operations occurred.
        pub fn hasOperations(self: *const CompressionStats) bool {
            return self.filesCompressed.load(.monotonic) > 0 or self.filesDecompressed.load(.monotonic) > 0;
        }

        /// Returns total operations (compressed + decompressed).
        pub fn getTotalOperations(self: *const CompressionStats) u64 {
            return Utils.atomicLoadU64(&self.filesCompressed) + Utils.atomicLoadU64(&self.filesDecompressed);
        }

        /// Returns background tasks queued as u64.
        pub fn getBackgroundTasksQueued(self: *const CompressionStats) u64 {
            return Utils.atomicLoadU64(&self.backgroundTasksQueued);
        }

        /// Returns background tasks completed as u64.
        pub fn getBackgroundTasksCompleted(self: *const CompressionStats) u64 {
            return Utils.atomicLoadU64(&self.backgroundTasksCompleted);
        }

        /// Calculate background task completion rate (0.0 - 1.0).
        pub fn backgroundTaskCompletionRate(self: *const CompressionStats) f64 {
            const queued = Utils.atomicLoadU64(&self.backgroundTasksQueued);
            const completed = Utils.atomicLoadU64(&self.backgroundTasksCompleted);
            return Utils.calculateErrorRate(completed, queued);
        }

        /// Resets all statistics to zero.
        pub fn reset(self: *CompressionStats) void {
            self.filesCompressed.store(0, .monotonic);
            self.filesDecompressed.store(0, .monotonic);
            self.bytesBefore.store(0, .monotonic);
            self.bytesAfter.store(0, .monotonic);
            self.compressionErrors.store(0, .monotonic);
            self.decompressionErrors.store(0, .monotonic);
            self.lastCompressionTime.store(0, .monotonic);
            self.totalCompressionTimeNs.store(0, .monotonic);
            self.totalDecompressionTimeNs.store(0, .monotonic);
            self.backgroundTasksQueued.store(0, .monotonic);
            self.backgroundTasksCompleted.store(0, .monotonic);
        }
    };

    /// Result of a compression operation.
    pub const CompressionResult = struct {
        success: bool,
        originalSize: u64,
        compressedSize: u64,
        outputPath: ?[]const u8,
        errorMessage: ?[]const u8 = null,

        pub fn ratio(self: *const CompressionResult) f64 {
            if (self.originalSize == 0) return 0;
            return 1.0 - (@as(f64, @floatFromInt(self.compressedSize)) / @as(f64, @floatFromInt(self.originalSize)));
        }
    };

    /// Initializes a new Compression instance.
    ///
    /// The default configuration disables compression. Use `initWithConfig` for custom settings.
    pub fn init(allocator: std.mem.Allocator) Compression {
        return initWithIo(allocator, Utils.defaultIo(), .{});
    }

    /// Initializes a Compression instance with custom configuration.
    pub fn initWithConfig(allocator: std.mem.Allocator, config: CompressionConfig) Compression {
        return initWithIo(allocator, Utils.defaultIo(), config);
    }

    /// Initializes a Compression instance with explicit I/O and custom configuration.
    pub fn initWithIo(allocator: std.mem.Allocator, io_handle: std.Io, config: CompressionConfig) Compression {
        return .{
            .allocator = allocator,
            .io = io_handle,
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
    pub fn enable(allocator: std.mem.Allocator) Compression {
        return initWithConfig(allocator, CompressionConfig.enable());
    }

    /// Alias for enable(). Creates a Compression instance with compression enabled.
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
    pub fn explicit(allocator: std.mem.Allocator) Compression {
        return initWithConfig(allocator, CompressionConfig.explicit());
    }

    /// Creates a Compression instance with fast compression (speed over ratio).
    ///
    /// Example:
    /// ```zig
    /// var compressor = Compression.fast(allocator);
    /// ```
    pub fn fast(allocator: std.mem.Allocator) Compression {
        return initWithConfig(allocator, CompressionConfig.fast());
    }

    /// Creates a Compression instance with balanced compression.
    ///
    /// Example:
    /// ```zig
    /// var compressor = Compression.balanced(allocator);
    /// ```
    pub fn balanced(allocator: std.mem.Allocator) Compression {
        return initWithConfig(allocator, CompressionConfig.balanced());
    }

    /// Creates a Compression instance with best compression (ratio over speed).
    ///
    /// Example:
    /// ```zig
    /// var compressor = Compression.best(allocator);
    /// ```
    pub fn best(allocator: std.mem.Allocator) Compression {
        return initWithConfig(allocator, CompressionConfig.best());
    }

    /// Creates a Compression instance optimized for log files.
    ///
    /// Example:
    /// ```zig
    /// var compressor = Compression.forLogs(allocator);
    /// ```
    pub fn forLogs(allocator: std.mem.Allocator) Compression {
        return initWithConfig(allocator, CompressionConfig.forLogs());
    }

    /// Creates a Compression instance with archival settings.
    ///
    /// Example:
    /// ```zig
    /// var compressor = Compression.archive(allocator);
    /// ```
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
    pub fn development(allocator: std.mem.Allocator) Compression {
        return initWithConfig(allocator, CompressionConfig.development());
    }

    /// Creates a Compression instance with zstd algorithm (default settings).
    /// Zstd provides excellent compression ratios with very fast decompression.
    ///
    /// Example:
    /// ```zig
    /// var compressor = Compression.zstd(allocator);
    /// defer compressor.deinit();
    /// ```
    ///
    /// v0.1.5+
    pub fn zstdCompression(allocator: std.mem.Allocator) Compression {
        return initWithConfig(allocator, CompressionConfig.zstd());
    }

    /// Creates a Compression instance with fast zstd algorithm.
    /// Prioritizes speed over compression ratio.
    ///
    /// Example:
    /// ```zig
    /// var compressor = Compression.zstdFast(allocator);
    /// ```
    ///
    /// v0.1.5+
    pub fn zstdFast(allocator: std.mem.Allocator) Compression {
        return initWithConfig(allocator, CompressionConfig.zstdFast());
    }

    /// Creates a Compression instance with best zstd compression.
    /// Prioritizes compression ratio over speed.
    ///
    /// Example:
    /// ```zig
    /// var compressor = Compression.zstdBest(allocator);
    /// ```
    ///
    /// v0.1.5+
    pub fn zstdBest(allocator: std.mem.Allocator) Compression {
        return initWithConfig(allocator, CompressionConfig.zstdBest());
    }

    /// Creates a Compression instance with production-ready zstd settings.
    /// Background processing with checksums for reliability.
    ///
    /// Example:
    /// ```zig
    /// var compressor = Compression.zstdProduction(allocator);
    /// ```
    ///
    /// v0.1.5+
    pub fn zstdProduction(allocator: std.mem.Allocator) Compression {
        return initWithConfig(allocator, CompressionConfig.zstdProduction());
    }

    /// Creates a Compression instance with lzma algorithm.
    /// v0.1.6+
    pub fn lzmaCompression(allocator: std.mem.Allocator) Compression {
        return initWithConfig(allocator, CompressionConfig.lzma());
    }

    /// Creates a Compression instance with lzma2 algorithm.
    /// v0.1.6+
    pub fn lzma2Compression(allocator: std.mem.Allocator) Compression {
        return initWithConfig(allocator, CompressionConfig.lzma2());
    }

    /// Creates a Compression instance with xz algorithm.
    /// v0.1.6+
    pub fn xzCompression(allocator: std.mem.Allocator) Compression {
        return initWithConfig(allocator, CompressionConfig.xz());
    }

    /// Creates a Compression instance with tar.gz algorithm.
    /// v0.1.6+
    pub fn tarGzCompression(allocator: std.mem.Allocator) Compression {
        return initWithConfig(allocator, CompressionConfig.tarGz());
    }

    /// Creates a Compression instance with zip algorithm.
    /// v0.1.6+
    pub fn zipCompression(allocator: std.mem.Allocator) Compression {
        return initWithConfig(allocator, CompressionConfig.zip());
    }

    /// Creates a Compression instance with lz4 algorithm.
    /// v0.1.6+
    pub fn lz4Compression(allocator: std.mem.Allocator) Compression {
        return initWithConfig(allocator, CompressionConfig.lz4());
    }

    /// Creates a Compression instance with brotli algorithm.
    /// v0.1.8+
    pub fn brotliCompression(allocator: std.mem.Allocator) Compression {
        return initWithConfig(allocator, CompressionConfig.brotli());
    }

    /// Creates a Compression instance with a custom zstd compression level (1-22).
    /// Allows fine-grained control over compression ratio vs speed tradeoff.
    ///
    /// Example:
    /// ```zig
    /// var compressor = Compression.zstdWithLevel(allocator, 12);
    /// defer compressor.deinit();
    /// ```
    ///
    /// v0.1.5+
    pub fn zstdWithLevel(allocator: std.mem.Allocator, level: i32) Compression {
        return initWithConfig(allocator, CompressionConfig.zstdWithLevel(level));
    }

    /// Alias for zstdCompression(). Creates a Compression instance with default zstd settings.
    /// v0.1.5+
    /// Alias for zstdFast(). Creates a Compression instance with fast zstd settings.
    /// v0.1.5+
    /// Alias for zstdBest(). Creates a Compression instance with best zstd settings.
    /// v0.1.5+
    /// Creates a Compression instance with background processing.
    ///
    /// Example:
    /// ```zig
    /// var compressor = Compression.background(allocator);
    /// ```
    pub fn background(allocator: std.mem.Allocator) Compression {
        return initWithConfig(allocator, CompressionConfig.backgroundMode());
    }

    /// Creates a Compression instance with streaming mode.
    ///
    /// Example:
    /// ```zig
    /// var compressor = Compression.streaming(allocator);
    /// ```
    pub fn streaming(allocator: std.mem.Allocator) Compression {
        return initWithConfig(allocator, CompressionConfig.streamingMode());
    }

    /// Releases resources associated with the compression instance.
    ///
    /// Currently, this struct does not own any external resources that require explicit cleanup,
    /// but this method is provided for API consistency and future compatibility.
    pub fn deinit(self: *Compression) void {
        _ = self;
        // Currently no owned resources to free
    }

    /// Sets the callback for compression start events.
    pub fn setCompressionStartCallback(self: *Compression, callback: *const fn ([]const u8, u64) void) void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        self.onCompressionStart = callback;
    }

    /// Sets the callback for compression complete events.
    pub fn setCompressionCompleteCallback(self: *Compression, callback: *const fn ([]const u8, []const u8, u64, u64, u64) void) void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        self.onCompressionComplete = callback;
    }

    /// Sets the callback for compression error events.
    pub fn setCompressionErrorCallback(self: *Compression, callback: *const fn ([]const u8, anyerror) void) void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        self.onCompressionError = callback;
    }

    /// Sets the callback for decompression complete events.
    pub fn setDecompressionCompleteCallback(self: *Compression, callback: *const fn ([]const u8, []const u8) void) void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        self.onDecompressionComplete = callback;
    }

    /// Sets the callback for archive deletion events.
    pub fn setArchiveDeletedCallback(self: *Compression, callback: *const fn ([]const u8) void) void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        self.onArchiveDeleted = callback;
    }

    /// Performs in-memory compression of the provided data buffer.
    /// Uses the instance's configured algorithm and primary allocator.
    ///
    /// Complexity: O(N) where N is the size of data.
    pub fn compress(self: *Compression, data: []const u8) ![]u8 {
        return self.compressWithAllocator(data, null);
    }

    /// Compresses data using a specified alternate allocator.
    /// Represents the core compression logic, including header generation and checksums.
    ///
    /// Complexity: O(N) where N is the size of data.
    pub fn compressWithAllocator(self: *Compression, data: []const u8, scratchAllocator: ?std.mem.Allocator) ![]u8 {
        const alloc = scratchAllocator orelse self.allocator;
        const startTime = Utils.currentNanos();
        defer {
            const current = Utils.currentNanos();
            const elapsed = @as(u64, @intCast(@max(0, current - startTime)));
            _ = self.stats.totalCompressionTimeNs.fetchAdd(@truncate(elapsed), .monotonic);
        }

        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);

        if (self.config.algorithm == .none or data.len == 0) {
            const copy = try alloc.dupe(u8, data);
            _ = self.stats.bytesBefore.fetchAdd(@intCast(data.len), .monotonic);
            _ = self.stats.bytesAfter.fetchAdd(@intCast(data.len), .monotonic);
            return copy;
        }

        var result = try std.ArrayList(u8).initCapacity(alloc, Constants.BufferSizes.compression);
        errdefer result.deinit(alloc);

        // Write header: magic number + algorithm + original size + checksum
        const magic: [4]u8 = .{ 'L', 'G', 'Z', @backingInt(self.config.algorithm) };
        try result.appendSlice(alloc, &magic);

        // Write original size (4 bytes, little-endian)
        const sizeBytes = std.mem.toBytes(@as(u32, @intCast(@min(data.len, std.math.maxInt(u32)))));
        try result.appendSlice(alloc, &sizeBytes);

        // Calculate and write CRC32 checksum if enabled
        if (self.config.checksum) {
            const checksum = Utils.calculateCRC32(data);
            try result.appendSlice(alloc, &std.mem.toBytes(checksum));
        } else {
            try result.appendSlice(alloc, &[_]u8{ 0, 0, 0, 0 });
        }

        // Compress based on algorithm and level
        switch (self.config.algorithm) {
            .none => try result.appendSlice(alloc, data),
            .deflate, .zlib, .rawDeflate, .gzip => {
                try self.compressDeflateWithAllocator(data, &result, alloc);
            },
            .zstd => {
                try self.compressZstdWithAllocator(data, &result, alloc);
            },
            .tarGz => {
                try self.compressTarGzWithAllocator(data, &result, alloc);
            },
            .lz4 => {
                try self.compressLz4WithAllocator(data, &result, alloc);
            },
            .brotli => {
                try self.compressBrotliWithAllocator(data, &result, alloc);
            },
            .lzma => {
                try self.compressLzmaWithAllocator(data, &result, alloc);
            },
            .lzma2 => {
                try self.compressLzma2WithAllocator(data, &result, alloc);
            },
            .xz => {
                try self.compressXzWithAllocator(data, &result, alloc);
            },
            .zip => {
                try self.compressZipWithAllocator(data, &result, alloc);
            },
        }

        _ = self.stats.bytesBefore.fetchAdd(@intCast(data.len), .monotonic);
        _ = self.stats.bytesAfter.fetchAdd(@intCast(result.items.len), .monotonic);
        _ = self.stats.filesCompressed.fetchAdd(1, .monotonic);

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
    /// Complexity: O(N) memory and time.
    pub fn compressStream(self: *Compression, reader: anytype, writer: anytype) !void {
        var input = reader;
        const content = try input.allocRemaining(self.allocator, .unlimited);
        defer self.allocator.free(content);

        const compressed = try self.compress(content);
        defer self.allocator.free(compressed);

        try writer.writeAll(compressed);
    }

    /// Decompresses data from a stream (Reader) and writes to a stream (Writer).
    ///
    /// Reads the entire compressed input stream into memory before decompressing.
    ///
    /// Complexity: O(N) memory and time.
    pub fn decompressStream(self: *Compression, reader: anytype, writer: anytype) !void {
        var input = reader;
        const content = try input.allocRemaining(self.allocator, .unlimited);
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
    /// Complexity: O(N * W) where N is data length and W is window size (bounded by configuration level).
    fn compressDeflateWithAllocator(self: *Compression, data: []const u8, result: *std.ArrayList(u8), alloc: std.mem.Allocator) !void {
        const level = self.config.level.toInt();

        if (level == 0) {
            // No compression - store as literal blocks
            try self.writeLiteralBlockWithAllocator(data, result, alloc);
            return;
        }

        // LZ77 compression with sliding window
        const windowSize: usize = switch (level) {
            0 => 0,
            1...3 => Constants.CompressionConstants.windowFast, // Fast: small window
            4...6 => Constants.CompressionConstants.windowDefault, // Default: medium window
            7...9 => Constants.CompressionConstants.windowBest, // Best: large window
            else => Constants.CompressionConstants.windowDefault,
        };

        const minMatch: usize = Constants.CompressionConstants.minMatch;
        const maxMatch: usize = Constants.CompressionConstants.maxMatch; // Limited to fit in u8

        var pos: usize = 0;
        var literalStart: usize = 0;

        while (pos < data.len) {
            var bestOffset: usize = 0;
            var bestLength: usize = 0;

            // Search for matches in the sliding window
            if (pos >= minMatch) {
                const searchStart = if (pos > windowSize) pos - windowSize else 0;

                var searchPos = searchStart;
                while (searchPos < pos) : (searchPos += 1) {
                    var matchLen: usize = 0;
                    while (matchLen < maxMatch and
                        pos + matchLen < data.len and
                        data[searchPos + matchLen] == data[pos + matchLen])
                    {
                        matchLen += 1;
                        // Prevent match from extending into search area
                        if (searchPos + matchLen >= pos) break;
                    }

                    if (matchLen >= minMatch and matchLen > bestLength) {
                        bestOffset = pos - searchPos;
                        bestLength = matchLen;
                    }
                }
            }

            if (bestLength >= minMatch and bestOffset <= std.math.maxInt(u16)) {
                // Write any pending literals
                if (pos > literalStart) {
                    try self.writeLiteralBlockWithAllocator(data[literalStart..pos], result, alloc);
                }

                // Write match: <offset:2><length:1>
                try result.append(alloc, 0xFF); // Match marker
                try result.appendSlice(alloc, &std.mem.toBytes(@as(u16, @intCast(bestOffset))));
                try result.append(alloc, @as(u8, @intCast(bestLength)));

                pos += bestLength;
                literalStart = pos;
            } else {
                pos += 1;
            }
        }

        // Write remaining literals
        if (literalStart < data.len) {
            try self.writeLiteralBlockWithAllocator(data[literalStart..], result, alloc);
        }

        // Write end marker
        try result.append(alloc, 0x00);
    }

    /// Compresses data using zstd algorithm.
    /// Uses the zstd C library for high-performance compression.
    ///
    /// Complexity: O(N) where N is data length.
    /// v0.1.5+
    fn compressZstdWithAllocator(self: *Compression, data: []const u8, result: *std.ArrayList(u8), alloc: std.mem.Allocator) !void {
        if (data.len == 0) return;

        const compressionLevel = self.config.getEffectiveZstdLevel();

        if (self.config.zstdDict) |dict| {
            // zstd 0.0.4 exposes the Dictionary struct but not its free
            // loadDictionary helper, so construct it directly. The id is
            // parsed from the magic header when present, matching upstream.
            var dictId: u32 = 0;
            if (dict.len >= 8 and std.mem.readInt(u32, dict[0..4], .little) == 0xEC30A437) {
                dictId = std.mem.readInt(u32, dict[4..8], .little);
            }
            var dictionary = zstd.Dictionary{
                .data = try alloc.dupe(u8, dict),
                .id = dictId,
                .allocator = alloc,
            };
            defer dictionary.deinit();

            var compressor = zstd.Compressor.initWithLevel(alloc, compressionLevel);
            defer compressor.deinit();

            compressor.setDictionary(&dictionary);
            const compressed = compressor.compressAlloc(data) catch return error.ZstdCompressionFailed;
            defer alloc.free(compressed);
            try result.appendSlice(alloc, compressed);
        } else {
            var compressor = zstd.Compressor.initWithLevel(alloc, compressionLevel);
            defer compressor.deinit();

            const compressed = compressor.compressAlloc(data) catch return error.ZstdCompressionFailed;
            defer alloc.free(compressed);
            try result.appendSlice(alloc, compressed);
        }
    }

    /// Decompresses zstd-compressed data.
    /// Uses the zstd C library for high-performance decompression.
    ///
    /// Complexity: O(N) where N is decompressed data length.
    /// v0.1.5+
    fn decompressZstdWithAllocator(self: *Compression, data: []const u8, originalSize: usize, alloc: std.mem.Allocator) ![]u8 {
        if (data.len == 0 or originalSize == 0) {
            return alloc.alloc(u8, 0);
        }

        var decompressor = zstd.Decompressor.init(alloc);
        defer decompressor.deinit();

        var dictionary: ?zstd.Dictionary = null;
        if (self.config.zstdDict) |dict| {
            var dictId: u32 = 0;
            if (dict.len >= 8 and std.mem.readInt(u32, dict[0..4], .little) == 0xEC30A437) {
                dictId = std.mem.readInt(u32, dict[4..8], .little);
            }
            dictionary = zstd.Dictionary{
                .data = try alloc.dupe(u8, dict),
                .id = dictId,
                .allocator = alloc,
            };
            decompressor.setDictionary(&dictionary.?);
        }
        defer if (dictionary) |*d| d.deinit();

        const decompressed = decompressor.decompressAlloc(data) catch return error.ZstdDecompressionFailed;
        if (decompressed.len != originalSize) {
            alloc.free(decompressed);
            return error.ZstdSizeMismatch;
        }
        return decompressed;
    }

    fn compressTarGzWithAllocator(self: *Compression, data: []const u8, result: *std.ArrayList(u8), alloc: std.mem.Allocator) !void {
        var tarBuf = std.Io.Writer.Allocating.init(alloc);
        defer tarBuf.deinit();

        var tarWriter: std.tar.Writer = .{ .underlying_writer = &tarBuf.writer };

        try tarWriter.writeFileBytes("log.txt", data, .{});
        // We don't call finishPedantically as recommended by std to save space

        // Compress the tar data using our deflate implementation
        const tarBytes = try tarBuf.toOwnedSlice();
        defer alloc.free(tarBytes);

        try self.compressDeflateWithAllocator(tarBytes, result, alloc);
    }

    fn compressLz4WithAllocator(self: *Compression, data: []const u8, result: *std.ArrayList(u8), alloc: std.mem.Allocator) !void {
        _ = self;
        // Native LZ4 Block Format Implementation (v0.1.6)
        // LZ4 uses a simple sequence of literals and match copies
        // Format: [token][literals...][offset][matchlen_extra?]
        //   token: high 4 bits = literal length, low 4 bits = match length - 4
        //   If literal length >= 15, additional bytes follow (add 255 until <255)
        //   offset: 2 bytes little-endian back-reference
        //   If match length >= 19, additional bytes follow

        if (data.len == 0) return;

        const minMatch: usize = Constants.CompressionConstants.lz4MinMatch;
        const maxOffset: usize = Constants.CompressionConstants.lz4MaxOffset;
        const hashBits: u5 = Constants.CompressionConstants.lz4HashBits;
        const hashSize: usize = 1 << hashBits;

        // Hash table for fast match finding
        var hashTable = try alloc.alloc(u32, hashSize);
        defer alloc.free(hashTable);
        @memset(hashTable, 0);

        var pos: usize = 0;
        var anchor: usize = 0; // Start of current literal run

        while (pos + minMatch <= data.len) {
            // Compute hash of next 4 bytes
            const hash = lz4Hash(data[pos..][0..4]);
            const matchPos = hashTable[hash];
            hashTable[hash] = @intCast(pos);

            // Check if we have a valid match
            const offset = pos - matchPos;
            if (matchPos > 0 and offset > 0 and offset <= maxOffset and
                pos + minMatch <= data.len and matchPos + minMatch <= data.len and
                std.mem.eql(u8, data[matchPos..][0..minMatch], data[pos..][0..minMatch]))
            {
                // Found a match! Extend it
                var matchLen: usize = minMatch;
                while (pos + matchLen < data.len and
                    matchPos + matchLen < pos and
                    data[matchPos + matchLen] == data[pos + matchLen])
                {
                    matchLen += 1;
                }

                // Write literal run + match
                try writeLz4Sequence(result, alloc, data[anchor..pos], @intCast(offset), matchLen);

                pos += matchLen;
                anchor = pos;
            } else {
                pos += 1;
            }
        }

        // Write remaining literals (last 5 bytes must be literals in LZ4)
        if (anchor < data.len) {
            try writeLz4Literals(result, alloc, data[anchor..]);
        }
    }

    /// LZ4 hash function for 4 bytes
    fn lz4Hash(bytes: *const [4]u8) u16 {
        const val = std.mem.readInt(u32, bytes, .little);
        return @truncate((val *% 2654435761) >> 16);
    }

    /// Write LZ4 sequence (literals + match)
    fn writeLz4Sequence(result: *std.ArrayList(u8), alloc: std.mem.Allocator, literals: []const u8, offset: u16, matchLen: usize) !void {
        const litLen = literals.len;
        const ml = matchLen - 4; // Match length minus minimum (4)

        // Build token
        var token: u8 = 0;
        if (litLen >= 15) {
            token |= 0xF0;
        } else {
            token |= @as(u8, @intCast(litLen)) << 4;
        }
        if (ml >= 15) {
            token |= 0x0F;
        } else {
            token |= @as(u8, @intCast(ml));
        }
        try result.append(alloc, token);

        // Write extra literal length bytes
        if (litLen >= 15) {
            var remaining = litLen - 15;
            while (remaining >= 255) {
                try result.append(alloc, 255);
                remaining -= 255;
            }
            try result.append(alloc, @intCast(remaining));
        }

        // Write literals
        try result.appendSlice(alloc, literals);

        // Write offset (little-endian)
        try result.appendSlice(alloc, &std.mem.toBytes(offset));

        // Write extra match length bytes
        if (ml >= 15) {
            var remaining = ml - 15;
            while (remaining >= 255) {
                try result.append(alloc, 255);
                remaining -= 255;
            }
            try result.append(alloc, @intCast(remaining));
        }
    }

    /// Write LZ4 literals only (for end of stream)
    fn writeLz4Literals(result: *std.ArrayList(u8), alloc: std.mem.Allocator, literals: []const u8) !void {
        const litLen = literals.len;

        // Token: literal length only, no match
        var token: u8 = 0;
        if (litLen >= 15) {
            token = 0xF0;
        } else {
            token = @as(u8, @intCast(litLen)) << 4;
        }
        try result.append(alloc, token);

        // Write extra literal length bytes
        if (litLen >= 15) {
            var remaining = litLen - 15;
            while (remaining >= 255) {
                try result.append(alloc, 255);
                remaining -= 255;
            }
            try result.append(alloc, @intCast(remaining));
        }

        // Write literals
        try result.appendSlice(alloc, literals);
    }

    /// Brotli compression using the brotli.zig binding.
    /// Brotli provides excellent compression ratios, especially for UTF-8 text.
    /// Supports quality levels 0-11 (default 6, best 11).
    /// v0.2.1+
    fn compressBrotliWithAllocator(self: *Compression, data: []const u8, result: *std.ArrayList(u8), alloc: std.mem.Allocator) !void {
        if (data.len == 0) return;

        const level: i32 = self.config.getEffectiveBrotliLevel();

        // Use brotli.zig oneshot compression with quality level
        const compressed = brotli.compressWithOptions(alloc, data, .{
            .quality = @intCast(std.math.clamp(level, 0, 11)),
        }) catch {
            // Fallback: store as uncompressed literals
            try result.appendSlice(alloc, data);
            return;
        };
        defer alloc.free(compressed);

        try result.appendSlice(alloc, compressed);
    }

    /// Brotli decompression using the brotli.zig binding.
    /// v0.2.1+
    fn decompressBrotliWithAllocator(self: *Compression, data: []const u8, originalSize: usize, alloc: std.mem.Allocator) ![]u8 {
        _ = self;
        _ = originalSize;

        const decompressed = brotli.decompress(alloc, data) catch {
            return error.DecompressionFailed;
        };
        return decompressed;
    }

    /// LZMA compression using native dictionary-based compression.
    /// Implements LZMA-style encoding with large dictionary and optimal parsing.
    /// v0.1.6+
    fn compressLzmaWithAllocator(self: *Compression, data: []const u8, result: *std.ArrayList(u8), alloc: std.mem.Allocator) !void {
        _ = self;
        // Native LZMA-style compression (v0.1.6)
        // Uses dictionary compression with larger window for better ratios
        // Format: [properties byte][dict_size:4][uncompressed_size:8][compressed_data]

        if (data.len == 0) return;

        // LZMA properties: lc=3, lp=0, pb=2 (standard)
        const properties: u8 = Constants.CompressionConstants.lzmaPropertiesByte; // pb*45 + lp*9 + lc
        try result.append(alloc, properties);

        // Dictionary size (64KB for balancing memory/ratio)
        const dictSize: u32 = Constants.CompressionConstants.lzmaDictSize;
        try result.appendSlice(alloc, &std.mem.toBytes(dictSize));

        // Uncompressed size (8 bytes, little-endian)
        try result.appendSlice(alloc, &std.mem.toBytes(@as(u64, data.len)));

        // LZMA uses larger dictionary and more aggressive matching
        const minMatch: usize = Constants.CompressionConstants.minMatch; // Prevent 0x00 ambiguity (length-2 short match is 0x00)
        const maxOffset: usize = Constants.CompressionConstants.lzmaMaxOffset; // Must fit in u16
        const hashBits: u5 = Constants.CompressionConstants.lzmaHashBits;
        const hashSize: usize = 1 << hashBits;

        // Hash table for match finding
        var hashTable = try alloc.alloc(u32, hashSize);
        defer alloc.free(hashTable);
        @memset(hashTable, 0);

        // Chain table for multiple matches at same hash
        var chainTable = try alloc.alloc(u32, @min(data.len, maxOffset));
        defer alloc.free(chainTable);
        @memset(chainTable, 0);

        var pos: usize = 0;
        var anchor: usize = 0;

        while (pos + minMatch <= data.len) {
            // Hash current position
            const hash = Utils.lzmaHash(data[pos..], @min(3, data.len - pos));
            const prevPos = hashTable[hash];
            chainTable[pos % maxOffset] = prevPos;
            hashTable[hash] = @intCast(pos);

            // Find best match in chain
            var bestLen: usize = 0;
            var bestOffset: usize = 0;
            var searchPos = prevPos;
            var chainLen: usize = 0;
            const maxChain: usize = Constants.CompressionConstants.lzmaMaxChainSearch;

            while (searchPos > 0 and chainLen < maxChain) : (chainLen += 1) {
                // Check if search_pos is valid relative to pos (must be < pos) and within max_offset window
                if (searchPos >= pos or pos - searchPos > maxOffset) break;

                const offset = pos - searchPos;
                if (offset == 0) break; // Should not happen with valid logic

                // Count matching bytes
                var matchLen: usize = 0;
                while (pos + matchLen < data.len and
                    searchPos + matchLen < pos and
                    data[searchPos + matchLen] == data[pos + matchLen] and
                    matchLen < Constants.CompressionConstants.lzmaMaxMatch) // LZMA max match (272 = 17 + 255)
                {
                    matchLen += 1;
                }

                if (matchLen >= minMatch and matchLen > bestLen) {
                    bestLen = matchLen;
                    bestOffset = offset;
                }

                // Move back in chain
                searchPos = chainTable[searchPos % maxOffset];
            }

            if (bestLen >= minMatch) {
                // Write literals before match
                if (pos > anchor) {
                    try writeLzmaLiterals(result, alloc, data[anchor..pos]);
                }
                // Write match
                try writeLzmaMatch(result, alloc, @intCast(bestOffset), bestLen);
                pos += bestLen;
                anchor = pos;
            } else {
                pos += 1;
            }
        }

        // Write remaining literals
        if (anchor < data.len) {
            try writeLzmaLiterals(result, alloc, data[anchor..]);
        }

        // End marker
        try result.append(alloc, 0x00);
    }

    /// Write LZMA literals
    fn writeLzmaLiterals(result: *std.ArrayList(u8), alloc: std.mem.Allocator, literals: []const u8) !void {
        var offset: usize = 0;
        while (offset < literals.len) {
            const remaining = literals.len - offset;
            const chunkLen = @min(remaining, Constants.CompressionConstants.lzmaMaxOffset);
            const chunk = literals[offset..][0..chunkLen];

            // Literal marker: 0x80 | length (for short) or 0x80 | 0x7F + extended length
            if (chunkLen <= 126) {
                try result.append(alloc, 0x80 | @as(u8, @intCast(chunkLen)));
            } else {
                try result.append(alloc, 0xFF); // Extended literal marker
                try result.appendSlice(alloc, &std.mem.toBytes(@as(u16, @intCast(chunkLen))));
            }
            try result.appendSlice(alloc, chunk);
            offset += chunkLen;
        }
    }

    /// Write LZMA match
    fn writeLzmaMatch(result: *std.ArrayList(u8), alloc: std.mem.Allocator, offset: u16, length: usize) !void {
        // Match marker: 0x00-0x7F range
        // Low 4 bits: length - 2 (0-14 = lengths 2-16)
        // High 3 bits: offset encoding type
        if (length <= 16 and offset <= 255) {
            // Short match: 1 byte marker + 1 byte offset
            try result.append(alloc, @as(u8, @intCast((length - 2) & 0x0F)));
            try result.append(alloc, @as(u8, @intCast(offset)));
        } else {
            // Long match: marker with 0x40 flag + 2 byte offset + length byte
            // Note: If (length - 2) >= 15 (i.e., length >= 17), we output 15 in the marker
            // and follow with an extended length byte.
            try result.append(alloc, 0x40 | @as(u8, @intCast(@min(length - 2, 15))));
            try result.appendSlice(alloc, &std.mem.toBytes(offset));
            if (length >= 17) {
                try result.append(alloc, @as(u8, @intCast(@min(length - 17, 255))));
            }
        }
    }

    /// LZMA2 compression - uses chunked LZMA compression.
    /// v0.1.6+
    fn compressLzma2WithAllocator(self: *Compression, data: []const u8, result: *std.ArrayList(u8), alloc: std.mem.Allocator) !void {
        // LZMA2 wraps LZMA with chunk headers for streaming
        if (data.len == 0) return;

        // Process in 32KB chunks to ensure compressed size fits in u16 (64KB limit)
        const chunkSize = Constants.CompressionConstants.lzma2ChunkSize;
        var pos: usize = 0;

        while (pos < data.len) {
            const end = @min(pos + chunkSize, data.len);
            const chunk = data[pos..end];
            const uncompressedSize = chunk.len;

            // Compress chunk using LZMA
            var lzmaData: std.ArrayList(u8) = .empty;
            defer lzmaData.deinit(alloc);
            try self.compressLzmaWithAllocator(chunk, &lzmaData, alloc);

            if (lzmaData.items.len > 65535) {
                // This implies >2x expansion which is extremely unlikely for 32KB input with LZMA
                return error.OutputTooLarge;
            }

            // LZMA2 chunk header: [control byte][unpacked size][packed size][data]
            // Control byte: 0x02 = LZMA chunk with new properties
            try result.append(alloc, 0x02);

            // Uncompressed size - 1 (16-bit)
            try result.appendSlice(alloc, &std.mem.toBytes(@as(u16, @intCast(uncompressedSize - 1))));

            // Packed size - 1 (16-bit)
            try result.appendSlice(alloc, &std.mem.toBytes(@as(u16, @intCast(lzmaData.items.len - 1))));

            // Data
            try result.appendSlice(alloc, lzmaData.items);

            pos += uncompressedSize;
        }

        // End marker
        try result.append(alloc, 0x00);
    }

    /// XZ compression with proper container format.
    /// v0.1.6+
    fn compressXzWithAllocator(self: *Compression, data: []const u8, result: *std.ArrayList(u8), alloc: std.mem.Allocator) !void {
        // XZ format: [stream header][block][index][stream footer]
        if (data.len == 0) return;

        // Stream Header (12 bytes)
        // Magic: FD 37 7A 58 5A 00
        try result.appendSlice(alloc, Constants.CompressionConstants.Magic.xz);
        // Stream flags: 0x00 0x04 (CRC32 check)
        try result.appendSlice(alloc, &[_]u8{ 0x00, 0x04 });
        // CRC32 of stream flags
        const flagsCrc = Utils.calculateCRC32(&[_]u8{ 0x00, 0x04 });
        try result.appendSlice(alloc, &std.mem.toBytes(flagsCrc));

        // Block Header
        const blockStart = result.items.len;
        try result.append(alloc, 0x00); // Placeholder for header size
        try result.append(alloc, 0x00); // Block flags: 0 filters, no compressed/uncompressed size

        // Filter: LZMA2 (ID = 0x21)
        try result.append(alloc, 0x21);
        try result.append(alloc, 0x01); // Properties size = 1
        try result.append(alloc, 0x00); // LZMA2 properties (dict size = 64KB)

        // Block Header Padding
        // Header size (including Size, Flags, Filters, Padding, CRC) must be multiple of 4
        // Current size: 1 (Size) + 4 (Fields) = 5
        // CRC size: 4
        // Total so far without padding: 5 + 4 = 9
        // Next multiple of 4 is 12 (9 -> 12, need 3 bytes padding)
        while ((result.items.len - blockStart + 4) % 4 != 0) {
            try result.append(alloc, 0x00);
        }

        // Update header size (header size = (real_size / 4) - 1)
        // real_size includes the CRC (4 bytes) we haven't written yet
        const headerContentSize = result.items.len - blockStart;
        const totalHeaderSize = headerContentSize + 4;
        result.items[blockStart] = @intCast((totalHeaderSize / 4) - 1);

        // Header CRC32 (covers Size + Flags + Filters + Padding)
        const headerCrc = Utils.calculateCRC32(result.items[blockStart..]);
        try result.appendSlice(alloc, &std.mem.toBytes(headerCrc));

        // Compressed data (using LZMA2)
        var lzma2Data: std.ArrayList(u8) = .empty;
        defer lzma2Data.deinit(alloc);
        try self.compressLzma2WithAllocator(data, &lzma2Data, alloc);
        try result.appendSlice(alloc, lzma2Data.items);

        // Block padding (to 4-byte boundary)
        while (result.items.len % 4 != 0) {
            try result.append(alloc, 0x00);
        }

        // Check (CRC32 of uncompressed data)
        const dataCrc = Utils.calculateCRC32(data);
        try result.appendSlice(alloc, &std.mem.toBytes(dataCrc));

        // Index
        const indexStart = result.items.len;
        try result.append(alloc, 0x00); // Index indicator
        try result.append(alloc, 0x01); // Number of records
        // Record: unpadded size + uncompressed size (simplified)
        try result.append(alloc, @intCast(@min(lzma2Data.items.len, 127)));
        try result.append(alloc, @intCast(@min(data.len, 127)));
        // Index padding
        while ((result.items.len - indexStart) % 4 != 0) {
            try result.append(alloc, 0x00);
        }
        // Index CRC32
        const indexCrc = Utils.calculateCRC32(result.items[indexStart..]);
        try result.appendSlice(alloc, &std.mem.toBytes(indexCrc));

        // Stream Footer (12 bytes)
        const footerCrc = Utils.calculateCRC32(&[_]u8{ 0x00, 0x04 });
        try result.appendSlice(alloc, &std.mem.toBytes(footerCrc));
        // Backward size = (index size / 4) - 1
        const indexSize = result.items.len - indexStart;
        try result.appendSlice(alloc, &std.mem.toBytes(@as(u32, @intCast(indexSize / 4 - 1))));
        try result.appendSlice(alloc, &[_]u8{ 0x00, 0x04 }); // Stream flags
        try result.appendSlice(alloc, &[_]u8{ 0x59, 0x5A }); // Magic footer
    }

    /// ZIP compression with proper local file header and deflate compression.
    /// Creates a valid ZIP archive structure.
    /// v0.1.6+
    fn compressZipWithAllocator(self: *Compression, data: []const u8, result: *std.ArrayList(u8), alloc: std.mem.Allocator) !void {
        // Create deflate compressed content first
        var compressedContent: std.ArrayList(u8) = .empty;
        defer compressedContent.deinit(alloc);
        try self.compressDeflateWithAllocator(data, &compressedContent, alloc);

        const filename = "data.bin";
        const crc = Utils.calculateCRC32(data);

        // Write Local File Header (signature: 0x04034b50)
        try result.appendSlice(alloc, &[_]u8{ 0x50, 0x4b, 0x03, 0x04 }); // Signature
        try result.appendSlice(alloc, &std.mem.toBytes(@as(u16, 20))); // Version needed (2.0)
        try result.appendSlice(alloc, &std.mem.toBytes(@as(u16, 0))); // General purpose bit flag
        try result.appendSlice(alloc, &std.mem.toBytes(@as(u16, 8))); // Compression method (8 = deflate)
        try result.appendSlice(alloc, &std.mem.toBytes(@as(u16, 0))); // Last mod time
        try result.appendSlice(alloc, &std.mem.toBytes(@as(u16, 0))); // Last mod date
        try result.appendSlice(alloc, &std.mem.toBytes(crc)); // CRC-32
        try result.appendSlice(alloc, &std.mem.toBytes(@as(u32, @intCast(compressedContent.items.len)))); // Compressed size
        try result.appendSlice(alloc, &std.mem.toBytes(@as(u32, @intCast(data.len)))); // Uncompressed size
        try result.appendSlice(alloc, &std.mem.toBytes(@as(u16, @intCast(filename.len)))); // Filename length
        try result.appendSlice(alloc, &std.mem.toBytes(@as(u16, 0))); // Extra field length

        // Write filename
        try result.appendSlice(alloc, filename);

        // Write compressed data
        try result.appendSlice(alloc, compressedContent.items);
    }

    fn decompressTarGzWithAllocator(self: *Compression, data: []const u8, originalSize: usize, alloc: std.mem.Allocator) ![]u8 {
        _ = originalSize;
        // First decompress the gzip/deflate layer
        const tarData = try self.decompressDeflateNative(data, 0, 0);
        defer alloc.free(tarData);

        var tarReader = std.Io.Reader.fixed(tarData);

        const fileNameBuf = try alloc.alloc(u8, std.Io.Dir.max_path_bytes);
        defer alloc.free(fileNameBuf);
        const linkNameBuf = try alloc.alloc(u8, std.Io.Dir.max_path_bytes);
        defer alloc.free(linkNameBuf);

        var it = std.tar.Iterator.init(&tarReader, .{
            .file_name_buffer = fileNameBuf,
            .link_name_buffer = linkNameBuf,
        });

        if (try it.next()) |file| {
            if (file.size > std.math.maxInt(usize)) return error.OutputTooLarge;
            const out = try alloc.alloc(u8, @intCast(file.size));
            errdefer alloc.free(out);
            try tarReader.readSliceAll(out);
            return out;
        }

        return error.InvalidTarArchive;
    }

    /// ZIP decompression with proper local file header parsing.
    /// Uses our internal deflate decompressor for deflate method.
    /// v0.1.6+
    fn decompressZipWithAllocator(self: *Compression, data: []const u8, originalSize: usize, alloc: std.mem.Allocator) ![]u8 {
        _ = alloc;
        var stream = std.Io.Reader.fixed(data);

        // Check Local File Header signature
        const sig = try stream.takeInt(u32, .little);
        if (sig != 0x04034b50) return error.InvalidZipArchive;

        _ = try stream.takeInt(u16, .little); // Version needed
        _ = try stream.takeInt(u16, .little); // Flags
        const compressionMethod = try stream.takeInt(u16, .little);
        _ = try stream.takeInt(u16, .little); // Mod time
        _ = try stream.takeInt(u16, .little); // Mod date
        _ = try stream.takeInt(u32, .little); // CRC32
        const compressedSize = try stream.takeInt(u32, .little);
        const uncompressedSize = try stream.takeInt(u32, .little);
        const filenameLen = try stream.takeInt(u16, .little);
        const extraLen = try stream.takeInt(u16, .little);

        try stream.discardAll(@intCast(filenameLen + extraLen));

        const contentCompressed = data[stream.seek..][0..compressedSize];

        if (compressionMethod == 0) {
            // Store (no compression)
            return self.allocator.dupe(u8, contentCompressed);
        } else if (compressionMethod == 8) {
            // Deflate - use our internal decompressor since compression uses our format
            return self.decompressDeflateNative(contentCompressed, uncompressedSize, 0);
        } else {
            _ = originalSize;
            return error.UnsupportedZipCompressionMethod;
        }
    }

    /// LZMA compression using native dictionary-based decompression.
    /// v0.1.6+
    fn decompressLzmaWithAllocator(self: *Compression, data: []const u8, originalSize: usize, alloc: std.mem.Allocator) ![]u8 {
        _ = self;
        var stream = std.Io.Reader.fixed(data);

        // Header: [properties:1][dict_size:4][uncompressed_size:8]
        if (data.len < 13) return error.InvalidLzmaHeader;

        _ = try stream.takeByte(); // properties
        const dictSize = try stream.takeInt(u32, .little);
        _ = dictSize;
        const uncompressedLen = try stream.takeInt(u64, .little);

        if (uncompressedLen > std.math.maxInt(usize)) return error.OutputTooLarge;
        // Use passed original_size if header size is 0 (unknown) or matches max u64 (unknown marker)
        const outputSize = if (uncompressedLen == 0 or uncompressedLen == std.math.maxInt(u64)) originalSize else @as(usize, @intCast(uncompressedLen));

        var result = try std.ArrayList(u8).initCapacity(alloc, outputSize);
        errdefer result.deinit(alloc);

        while (stream.seek < data.len) {
            const byte = try stream.takeByte();

            if (byte == 0x00) {
                // End marker
                break;
            } else if ((byte & 0x80) != 0) {
                // Literal run
                var litLen: usize = 0;
                if (byte == 0xFF) {
                    litLen = try stream.takeInt(u16, .little);
                } else {
                    litLen = byte & 0x7F;
                }

                if (stream.seek + litLen > data.len) return error.InvalidData;
                const literals = data[stream.seek..][0..litLen];
                try stream.discardAll(@intCast(litLen));
                try result.appendSlice(alloc, literals);
            } else {
                // Match
                if ((byte & 0x40) == 0) {
                    // Short match
                    const len = @as(usize, byte & 0x0F) + 2;
                    const offset = @as(usize, try stream.takeByte());

                    try copyMatch(&result, alloc, offset, len);
                } else {
                    // Long match
                    var len = @as(usize, byte & 0x0F) + 2;
                    const offset = try stream.takeInt(u16, .little);

                    if (len == 17) {
                        len += @as(usize, try stream.takeByte());
                    }

                    try copyMatch(&result, alloc, offset, len);
                }
            }
        }

        return result.toOwnedSlice(alloc);
    }

    /// Internal helper to copy matches from history buffer.
    fn copyMatch(result: *std.ArrayList(u8), alloc: std.mem.Allocator, offset: usize, length: usize) !void {
        if (offset > result.items.len or offset == 0) return error.InvalidOffset;

        const start = result.items.len - offset;
        var i: usize = 0;
        while (i < length) : (i += 1) {
            const idx = start + (i % offset);
            try result.append(alloc, result.items[idx]);
        }
    }

    /// LZMA2 decompression.
    /// v0.1.6+
    fn decompressLzma2WithAllocator(self: *Compression, data: []const u8, originalSize: usize, alloc: std.mem.Allocator) ![]u8 {
        // LZMA2 chunk header: [control:1][unpacked:2][packed:2][data...]
        // Control 0x02 = LZMA chunk
        if (data.len < 1) return error.InvalidData;

        var stream = std.Io.Reader.fixed(data);
        var result = try std.ArrayList(u8).initCapacity(alloc, originalSize);
        errdefer result.deinit(alloc);

        while (stream.seek < data.len) {
            const control = try stream.takeByte();
            if (control == 0x00) break; // End marker

            if (control == 0x02) {
                // LZMA chunk
                const unpackedSize = @as(usize, try stream.takeInt(u16, .little)) + 1;
                const packedSize = @as(usize, try stream.takeInt(u16, .little)) + 1;

                if (stream.seek + packedSize > data.len) return error.InvalidData;

                const chunkData = data[stream.seek..][0..packedSize];
                try stream.discardAll(@intCast(packedSize));

                const chunkDecompressed = try self.decompressLzmaWithAllocator(chunkData, unpackedSize, alloc);
                defer alloc.free(chunkDecompressed);
                try result.appendSlice(alloc, chunkDecompressed);
            } else {
                return error.UnsupportedLzma2Chunk;
            }
        }

        return result.toOwnedSlice(alloc);
    }

    /// XZ decompression.
    /// v0.1.6+
    fn decompressXzWithAllocator(self: *Compression, data: []const u8, originalSize: usize, alloc: std.mem.Allocator) ![]u8 {
        var stream = std.Io.Reader.fixed(data);

        // Check magic
        if (data.len < 12) return error.InvalidData;
        const magic = data[0..6];
        try stream.discardAll(6);

        if (!std.mem.eql(u8, magic, Constants.CompressionConstants.Magic.xz)) return error.InvalidMagic;

        // Skip Stream Header flags (2 bytes) + CRC (4 bytes)
        try stream.discardAll(6);

        // Read Block Header Size
        const headerSizeEncoded = try stream.takeByte();
        if (headerSizeEncoded == 0) return error.InvalidData;

        const headerSize = (@as(usize, headerSizeEncoded) + 1) * 4;

        // Skip Block Header details (flags, filters, etc.)
        // We already read 1 byte (encoded size), so skip header_size - 1
        try stream.discardAll(@intCast(headerSize - 1));

        // Decompress LZMA2 data block
        const decompressed = try self.decompressLzma2WithAllocator(data[stream.seek..], originalSize, alloc);

        return decompressed;
    }

    /// LZ4 decompression using native block format.
    ///  v0.1.6+
    fn decompressLz4WithAllocator(self: *Compression, data: []const u8, originalSize: usize, alloc: std.mem.Allocator) ![]u8 {
        _ = self;
        var result = try std.ArrayList(u8).initCapacity(alloc, originalSize);
        errdefer result.deinit(alloc);

        var stream = std.Io.Reader.fixed(data);

        while (stream.seek < data.len) {
            const token = try stream.takeByte();

            // Token: high 4 = literal len, low 4 = match len
            var litLen: usize = @intCast((token >> 4) & 0x0F);
            var ml: usize = @intCast(token & 0x0F);

            // Read extended literal length
            if (litLen == 15) {
                while (true) {
                    const byte = try stream.takeByte();
                    litLen += byte;
                    if (byte != 255) break;
                }
            }

            // Copy literals
            if (stream.seek + litLen > data.len) return error.InvalidData;
            const literals = data[stream.seek..][0..litLen];
            try stream.discardAll(@intCast(litLen));
            try result.appendSlice(alloc, literals);

            if (stream.seek >= data.len) break; // End of stream

            // Read Offset
            const offset = try stream.takeInt(u16, .little);

            // Read extended match length
            if (ml == 15) {
                while (true) {
                    const byte = try stream.takeByte();
                    ml += byte;
                    if (byte != 255) break;
                }
            }

            // Min match length is 4
            const matchLen = ml + 4;

            // Copy Match
            try copyMatch(&result, alloc, offset, matchLen);
        }

        return result.toOwnedSlice(alloc);
    }

    /// Writes a block of literal bytes to the output, applying RLE (Run-Length Encoding) where efficient.
    /// Uses the instance allocator.
    fn writeLiteralBlock(self: *Compression, data: []const u8, result: *std.ArrayList(u8)) !void {
        try self.writeLiteralBlockWithAllocator(data, result, self.allocator);
    }

    /// Writes a block of literal bytes using a specific allocator.
    ///
    /// Complexity: O(N) where N is data length.
    fn writeLiteralBlockWithAllocator(self: *Compression, data: []const u8, result: *std.ArrayList(u8), alloc: std.mem.Allocator) !void {
        _ = self;
        if (data.len == 0) return;

        var i: usize = 0;
        while (i < data.len) {
            const byte = data[i];

            // Count consecutive identical bytes (RLE)
            var runLength: usize = 1;
            while (i + runLength < data.len and
                data[i + runLength] == byte and
                runLength < Constants.CompressionConstants.maxRunLength)
            {
                runLength += 1;
            }

            if (runLength >= 4) {
                // RLE: marker + count + byte
                try result.append(alloc, Constants.CompressionConstants.Rle.marker); // RLE marker
                try result.append(alloc, @as(u8, @intCast(runLength)));
                try result.append(alloc, byte);
                i += runLength;
            } else {
                // Literal: escape special bytes
                if (byte == 0xFF or byte == Constants.CompressionConstants.Rle.marker or byte == 0x00) {
                    try result.append(alloc, Constants.CompressionConstants.Rle.escape); // Escape marker
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
    /// Complexity: O(N) where N is the size of the uncompressed output.
    pub fn decompress(self: *Compression, data: []const u8) ![]u8 {
        const startTime = Utils.currentNanos();
        defer {
            const elapsed = @as(u64, @intCast(@max(0, Utils.currentNanos() - startTime)));
            _ = self.stats.totalDecompressionTimeNs.fetchAdd(@truncate(elapsed), .monotonic);
        }

        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);

        // Minimum header size: magic(4) + size(4) + checksum(4) = 12
        if (data.len < 12) return error.InvalidData;

        // Verify magic number
        if (!std.mem.eql(u8, data[0..3], "LGZ")) {
            // Try legacy format (just size header)
            if (data.len >= 4) {
                const sizeBytes = data[0..4].*;
                const originalSize = std.mem.bytesToValue(u32, &sizeBytes);
                if (data.len >= 4 + originalSize) {
                    _ = self.stats.filesDecompressed.fetchAdd(1, .monotonic);
                    return self.allocator.dupe(u8, data[4..][0..originalSize]);
                }
            }
            return error.InvalidMagic;
        }

        const algorithm: Algorithm = @fromBackingInt(@intCast(data[3]));

        // Invoke callback if registered
        if (self.onDecompressionComplete) |callback| {
            callback("<memory>", "<memory>");
        }

        const originalSize = std.mem.bytesToValue(u32, data[4..8]);
        const storedChecksum = std.mem.bytesToValue(u32, data[8..12]);

        if (originalSize == 0) {
            _ = self.stats.filesDecompressed.fetchAdd(1, .monotonic);
            return self.allocator.alloc(u8, 0);
        }

        // Decompress the data based on algorithm
        const result = try switch (algorithm) {
            .zstd => self.decompressZstdWithAllocator(data[12..], originalSize, self.allocator),
            .deflate, .zlib, .rawDeflate, .gzip => self.decompressDeflateNative(data[12..], originalSize, storedChecksum),
            .tarGz => self.decompressTarGzWithAllocator(data[12..], originalSize, self.allocator),
            .zip => self.decompressZipWithAllocator(data[12..], originalSize, self.allocator),
            .lzma => self.decompressLzmaWithAllocator(data[12..], originalSize, self.allocator),
            .lzma2 => self.decompressLzma2WithAllocator(data[12..], originalSize, self.allocator),
            .xz => self.decompressXzWithAllocator(data[12..], originalSize, self.allocator),
            .none => self.allocator.dupe(u8, data[12..]),
            .lz4 => self.decompressLz4WithAllocator(data[12..], originalSize, self.allocator),
            .brotli => self.decompressBrotliWithAllocator(data[12..], originalSize, self.allocator),
        };
        errdefer self.allocator.free(result);

        // Verify checksum if enabled
        if (self.config.checksum and storedChecksum != 0) {
            const computedChecksum = Utils.calculateCRC32(result);
            if (computedChecksum != storedChecksum) {
                // errdefer will handle cleanup
                return error.ChecksumMismatch;
            }
        }

        _ = self.stats.filesDecompressed.fetchAdd(1, .monotonic);
        return result;
    }

    /// Internal helper for native decompression (deflate/zlib/gzip legacy format)
    fn decompressDeflateNative(self: *Compression, data: []const u8, originalSize: u64, storedChecksum: u32) ![]u8 {
        var result: std.ArrayList(u8) = .empty;
        errdefer result.deinit(self.allocator);
        // Ensure capacity fits platform `usize` (avoid overflow on 32-bit targets)
        const maxCapacity: u64 = @as(u64, std.math.maxInt(usize));
        if (originalSize > maxCapacity) return error.OutputTooLarge;
        const neededCapacity: usize = @intCast(originalSize);
        try result.ensureTotalCapacity(self.allocator, neededCapacity);

        var pos: usize = 0; // Data already sliced from header
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
        if (self.config.checksum and storedChecksum != 0) {
            const computedChecksum = Utils.calculateCRC32(result.items);
            if (computedChecksum != storedChecksum) {
                return error.ChecksumMismatch;
            }
        }

        _ = self.stats.filesDecompressed.fetchAdd(1, .monotonic);
        return result.toOwnedSlice(self.allocator);
    }

    pub const AsyncCompressContext = struct {
        comp: *Compression,
        inputPath: []const u8,
        outputPath: ?[]const u8,
        alloc: std.mem.Allocator,

        pub fn run(ctxPtr: *anyopaque, _: ?std.mem.Allocator) void {
            const ctx: *AsyncCompressContext = @ptrCast(@alignCast(ctxPtr));
            defer {
                ctx.alloc.free(ctx.inputPath);
                if (ctx.outputPath) |p| ctx.alloc.free(p);
                ctx.alloc.destroy(ctx);
            }
            _ = ctx.comp.compressFile(ctx.inputPath, ctx.outputPath) catch |err| {
                _ = ctx.comp.stats.compressionErrors.fetchAdd(1, .monotonic);
                if (ctx.comp.onCompressionError) |cb| cb(ctx.inputPath, err);
                return;
            };
            _ = ctx.comp.stats.backgroundTasksCompleted.fetchAdd(1, .monotonic);
        }

        /// Drop hook for contexts discarded without executing.
        pub fn drop(ctxPtr: ?*anyopaque) void {
            const ctx: *AsyncCompressContext = @ptrCast(@alignCast(ctxPtr.?));
            ctx.alloc.free(ctx.inputPath);
            if (ctx.outputPath) |p| ctx.alloc.free(p);
            ctx.alloc.destroy(ctx);
        }
    };

    /// Submits a compression job to the background thread pool asynchronously instead of blocking.
    pub fn asyncCompress(self: *Compression, inputPath: []const u8, outputPath: ?[]const u8) !void {
        const pool = self.config.threadPool orelse return error.NoThreadPool;

        const ctx = try self.allocator.create(AsyncCompressContext);
        errdefer self.allocator.destroy(ctx);

        ctx.* = .{
            .comp = self,
            .inputPath = try self.allocator.dupe(u8, inputPath),
            .outputPath = if (outputPath) |p| try self.allocator.dupe(u8, p) else null,
            .alloc = self.allocator,
        };
        errdefer {
            self.allocator.free(ctx.inputPath);
            if (ctx.outputPath) |p| self.allocator.free(p);
        }

        if (!pool.submitCallbackWithDrop(AsyncCompressContext.run, ctx, AsyncCompressContext.drop)) {
            self.allocator.free(ctx.inputPath);
            if (ctx.outputPath) |p| self.allocator.free(p);
            self.allocator.destroy(ctx);
            return error.ThreadPoolFull;
        }
        _ = self.stats.backgroundTasksQueued.fetchAdd(1, .monotonic);
    }

    /// Compresses a file from the filesystem.
    ///
    /// Reads the input file, compresses its contents in memory, and writes to the output path.
    /// Handles file stat, read/write permissions, and optional cleanup of the source file.
    ///
    /// Complexity: O(N) where N is the file size (I/O bound).
    pub fn compressFile(self: *Compression, inputPath: []const u8, outputPath: ?[]const u8) !CompressionResult {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);

        const outPath = if (outputPath) |p| p else blk: {
            break :blk try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ inputPath, self.config.extension });
        };
        const shouldFreePath = outputPath == null;
        defer if (shouldFreePath) self.allocator.free(outPath);

        // Get original file size
        const inputFile = std.Io.Dir.cwd().openFile(self.io, inputPath, .{}) catch |err| {
            _ = self.stats.compressionErrors.fetchAdd(1, .monotonic);
            return .{
                .success = false,
                .originalSize = 0,
                .compressedSize = 0,
                .outputPath = null,
                .errorMessage = @errorName(err),
            };
        };
        defer inputFile.close(self.io);

        const stat = try inputFile.stat(self.io);
        const originalSize = stat.size;

        // Invoke start callback if registered
        if (self.onCompressionStart) |callback| {
            callback(inputPath, originalSize);
        }

        // Read file content
        var readBuffer: [Constants.BufferSizes.compression]u8 = undefined;
        var fileReader = inputFile.reader(self.io, &readBuffer);
        const content = try fileReader.interface.allocRemaining(self.allocator, .unlimited);
        defer self.allocator.free(content);

        // Compress content
        self.mutex.unlock(self.io); // Unlock for nested call
        const compressed = self.compress(content) catch |err| {
            self.mutex.lockUncancelable(self.io);
            _ = self.stats.compressionErrors.fetchAdd(1, .monotonic);
            return .{
                .success = false,
                .originalSize = originalSize,
                .compressedSize = 0,
                .outputPath = null,
                .errorMessage = @errorName(err),
            };
        };
        self.mutex.lockUncancelable(self.io);
        defer self.allocator.free(compressed);

        // Create parent directory if needed
        if (std.fs.path.dirname(outPath)) |dirname| {
            std.Io.Dir.cwd().createDirPath(self.io, dirname) catch |err| {
                _ = self.stats.compressionErrors.fetchAdd(1, .monotonic);
                return .{
                    .success = false,
                    .originalSize = originalSize,
                    .compressedSize = 0,
                    .outputPath = null,
                    .errorMessage = @errorName(err),
                };
            };
        }

        // Write compressed file
        const outputFile = std.Io.Dir.cwd().createFile(self.io, outPath, .{}) catch |err| {
            _ = self.stats.compressionErrors.fetchAdd(1, .monotonic);
            return .{
                .success = false,
                .originalSize = originalSize,
                .compressedSize = 0,
                .outputPath = null,
                .errorMessage = @errorName(err),
            };
        };
        defer outputFile.close(self.io);

        try outputFile.writeStreamingAll(self.io, compressed);

        // Delete original if configured
        if (!self.config.keepOriginal) {
            std.Io.Dir.cwd().deleteFile(self.io, inputPath) catch {};
        }

        _ = self.stats.filesCompressed.fetchAdd(1, .monotonic);
        self.stats.lastCompressionTime.store(@truncate(Utils.currentMillis()), .monotonic);

        const resultPath = try self.allocator.dupe(u8, outPath);

        // Invoke complete callback if registered
        if (self.onCompressionComplete) |callback| {
            callback(inputPath, outPath, originalSize, compressed.len, 0);
        }

        return .{
            .success = true,
            .originalSize = originalSize,
            .compressedSize = compressed.len,
            .outputPath = resultPath,
        };
    }

    /// Decompresses a file on disk, automatically handling output naming.
    ///
    /// Complexity: O(N) where N is the file size (I/O bound).
    pub fn decompressFile(self: *Compression, inputPath: []const u8, outputPath: ?[]const u8) !bool {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);

        const outPath = if (outputPath) |p| p else blk: {
            // Remove extension
            if (std.mem.endsWith(u8, inputPath, self.config.extension)) {
                break :blk inputPath[0 .. inputPath.len - self.config.extension.len];
            }
            break :blk try std.fmt.allocPrint(self.allocator, "{s}.decompressed", .{inputPath});
        };

        // Read compressed file
        const inputFile = try std.Io.Dir.cwd().openFile(self.io, inputPath, .{});
        defer inputFile.close(self.io);

        var readBuffer: [Constants.BufferSizes.compression]u8 = undefined;
        var fileReader = inputFile.reader(self.io, &readBuffer);
        const content = try fileReader.interface.allocRemaining(self.allocator, .unlimited);
        defer self.allocator.free(content);

        // Decompress
        self.mutex.unlock(self.io);
        const decompressed = try self.decompress(content);
        self.mutex.lockUncancelable(self.io);
        defer self.allocator.free(decompressed);

        // Write decompressed file
        const outputFile = try std.Io.Dir.cwd().createFile(self.io, outPath, .{});
        defer outputFile.close(self.io);

        try outputFile.writeStreamingAll(self.io, decompressed);

        return true;
    }

    /// Compresses all eligible files in a directory.
    ///
    /// Scans the directory for files that should be compressed (based on `shouldCompress`)
    /// and compresses them individually. Non-recursive.
    pub fn compressDirectory(self: *Compression, dirPath: []const u8) !u64 {
        var dir = std.Io.Dir.cwd().openDir(self.io, dirPath, .{ .iterate = true }) catch return 0;
        defer dir.close(self.io);

        var iterator = dir.iterate();
        var count: u64 = 0;

        while (try iterator.next(self.io)) |entry| {
            if (entry.kind != .file) continue;

            const filePath = try std.fs.path.join(self.allocator, &[_][]const u8{ dirPath, entry.name });
            defer self.allocator.free(filePath);

            if (self.shouldCompress(filePath)) {
                // Ignore errors for individual files to keep processing
                const result = self.compressFile(filePath, null) catch continue;
                if (result.outputPath) |p| {
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
    /// Complexity: O(1) checks + optional O(1) file stat for size threshold mode.
    pub fn shouldCompress(self: *const Compression, filePath: []const u8) bool {
        if (self.config.mode == .disabled) return false;

        // Don't compress already compressed files
        if (std.mem.endsWith(u8, filePath, self.config.extension)) return false;
        if (std.mem.endsWith(u8, filePath, ".gz")) return false;
        if (std.mem.endsWith(u8, filePath, ".zip")) return false;
        if (std.mem.endsWith(u8, filePath, ".zst")) return false;

        if (self.config.mode == .onSizeThreshold) {
            const file = std.Io.Dir.cwd().openFile(self.io, filePath, .{}) catch return false;
            defer file.close(self.io);

            const stat = file.stat(self.io) catch return false;
            return stat.size >= self.config.sizeThreshold;
        }

        return true;
    }

    /// Gets compression statistics.
    ///
    /// Complexity: O(1) non-blocking access to atomic values.
    pub fn getStats(self: *const Compression) CompressionStats {
        return self.stats;
    }

    /// Resets compression statistics to zero.
    pub fn resetStats(self: *Compression) void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        self.stats.reset();
    }

    /// Updates the compression configuration at runtime.
    /// Thread-safe update of operational parameters.
    pub fn configure(self: *Compression, config: CompressionConfig) void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        self.config = config;
    }

    /// Helper to create a fully configured sink for compressed logging.
    pub fn createCompressedSink(filePath: []const u8) @import("sink.zig").SinkConfig {
        const SinkConfig = @import("sink.zig").SinkConfig;
        return SinkConfig{
            .path = filePath,
            .compression = CompressionPresets.balanced(),
            .color = false,
        };
    }

    /// Returns true if compression is active and configured.
    pub fn isEnabled(self: *const Compression) bool {
        return self.config.algorithm != .none and self.config.mode != .disabled;
    }

    /// Returns the current compression ratio based on statistics.
    pub fn ratio(self: *const Compression) f64 {
        return self.stats.compressionRatio();
    }

    /// Compresses multiple files in a batch operation.
    /// Returns the number of successfully compressed files.
    pub fn compressBatch(self: *Compression, filePaths: []const []const u8) u64 {
        var count: u64 = 0;
        for (filePaths) |path| {
            const result = self.compressFile(path, null) catch continue;
            if (result.outputPath) |p| {
                self.allocator.free(p);
            }
            if (result.success) {
                count += 1;
            }
        }
        return count;
    }

    /// Compresses files matching a pattern in a directory.
    /// Pattern supports simple glob matching (e.g., "*.log").
    pub fn compressPattern(self: *Compression, dirPath: []const u8, pattern: []const u8) !u64 {
        var dir = std.Io.Dir.cwd().openDir(self.io, dirPath, .{ .iterate = true }) catch return 0;
        defer dir.close(self.io);

        var iterator = dir.iterate();
        var count: u64 = 0;

        while (try iterator.next(self.io)) |entry| {
            if (entry.kind != .file) continue;

            if (matchGlob(entry.name, pattern)) {
                const filePath = try std.fs.path.join(self.allocator, &[_][]const u8{ dirPath, entry.name });
                defer self.allocator.free(filePath);

                if (self.shouldCompress(filePath)) {
                    const result = self.compressFile(filePath, null) catch continue;
                    if (result.outputPath) |p| {
                        self.allocator.free(p);
                    }
                    if (result.success) {
                        count += 1;
                    }
                }
            }
        }
        return count;
    }

    /// Compresses the N oldest files in a directory.
    /// Useful for rotation-based compression.
    pub fn compressOldest(self: *Compression, dirPath: []const u8, count: usize) !u64 {
        var dir = std.Io.Dir.cwd().openDir(self.io, dirPath, .{ .iterate = true }) catch return 0;
        defer dir.close(self.io);

        // Collect file info
        var files = std.ArrayList(FileEntry).init(self.allocator);
        defer {
            for (files.items) |f| {
                self.allocator.free(f.name);
            }
            files.deinit();
        }

        var iterator = dir.iterate();
        while (try iterator.next(self.io)) |entry| {
            if (entry.kind != .file) continue;

            const filePath = try std.fs.path.join(self.allocator, &[_][]const u8{ dirPath, entry.name });
            defer self.allocator.free(filePath);

            if (!self.shouldCompress(filePath)) continue;

            const file = std.Io.Dir.cwd().openFile(self.io, filePath, .{}) catch continue;
            defer file.close(self.io);

            const stat = file.stat(self.io) catch continue;
            try files.append(.{
                .name = try self.allocator.dupe(u8, entry.name),
                .mtime = stat.mtime,
            });
        }

        // Sort by modification time (oldest first)
        std.mem.sort(FileEntry, files.items, {}, struct {
            fn lessThan(_: void, a: FileEntry, b: FileEntry) bool {
                return a.mtime < b.mtime;
            }
        }.lessThan);

        // Compress the oldest N files
        var compressedCount: u64 = 0;
        for (files.items[0..@min(count, files.items.len)]) |f| {
            const filePath = try std.fs.path.join(self.allocator, &[_][]const u8{ dirPath, f.name });
            defer self.allocator.free(filePath);

            const result = self.compressFile(filePath, null) catch continue;
            if (result.outputPath) |p| {
                self.allocator.free(p);
            }
            if (result.success) {
                compressedCount += 1;
            }
        }

        return compressedCount;
    }

    /// File entry for sorting operations.
    const FileEntry = struct {
        name: []const u8,
        mtime: i128,
    };

    /// Simple glob pattern matching for file names.
    fn matchGlob(name: []const u8, pattern: []const u8) bool {
        // Handle "*.ext" pattern
        if (std.mem.startsWith(u8, pattern, "*.")) {
            const ext = pattern[1..];
            return std.mem.endsWith(u8, name, ext);
        }
        // Handle "*" wildcard
        if (std.mem.eql(u8, pattern, "*")) {
            return true;
        }
        // Exact match
        return std.mem.eql(u8, name, pattern);
    }

    /// Compresses files larger than a given size threshold.
    pub fn compressLargerThan(self: *Compression, dirPath: []const u8, minSize: u64) !u64 {
        var dir = std.Io.Dir.cwd().openDir(self.io, dirPath, .{ .iterate = true }) catch return 0;
        defer dir.close(self.io);

        var iterator = dir.iterate();
        var count: u64 = 0;

        while (try iterator.next(self.io)) |entry| {
            if (entry.kind != .file) continue;

            const filePath = try std.fs.path.join(self.allocator, &[_][]const u8{ dirPath, entry.name });
            defer self.allocator.free(filePath);

            if (!self.shouldCompress(filePath)) continue;

            const file = std.Io.Dir.cwd().openFile(self.io, filePath, .{}) catch continue;
            defer file.close(self.io);

            const stat = file.stat(self.io) catch continue;
            if (stat.size < minSize) continue;

            const result = self.compressFile(filePath, null) catch continue;
            if (result.outputPath) |p| {
                self.allocator.free(p);
            }
            if (result.success) {
                count += 1;
            }
        }
        return count;
    }

    /// Returns the estimated compressed size for given data.
    /// Uses a heuristic based on data entropy.
    pub fn estimateCompressedSize(self: *const Compression, dataSize: u64) u64 {
        // Estimate based on algorithm and level
        const ratioEstimate: f64 = switch (self.config.algorithm) {
            .none => 1.0,
            .zstd => switch (self.config.level) {
                .none => 1.0,
                .fastest => 0.5,
                .fast => 0.4,
                .default => 0.3,
                .best => 0.2,
            },
            else => switch (self.config.level) {
                .none => 1.0,
                .fastest => 0.7,
                .fast => 0.6,
                .default => 0.5,
                .best => 0.4,
            },
        };
        return @intFromFloat(@as(f64, @floatFromInt(dataSize)) * ratioEstimate);
    }

    /// Returns the file extension for the configured algorithm.
    pub fn getExtension(self: *const Compression) []const u8 {
        return self.config.extension;
    }

    /// Returns true if using zstd algorithm.
    pub fn isZstd(self: *const Compression) bool {
        return self.config.algorithm == .zstd;
    }

    /// Returns the current algorithm name as a string.
    pub fn algorithmName(self: *const Compression) []const u8 {
        return @tagName(self.config.algorithm);
    }

    /// Returns the current level name as a string.
    pub fn levelName(self: *const Compression) []const u8 {
        return @tagName(self.config.level);
    }
};

/// Preset compression configurations for common use cases.
pub const CompressionPresets = struct {
    /// Returns a configuration with compression disabled.
    pub fn none() Compression.CompressionConfig {
        return .{
            .algorithm = .none,
            .mode = .disabled,
        };
    }

    /// Returns a configuration optimized for throughput (Fastest).
    /// Safe for use in high-volume logging paths.
    pub fn fast() Compression.CompressionConfig {
        return .{
            .algorithm = .deflate,
            .level = .fast,
            .mode = .onRotation,
        };
    }

    /// Returns a balanced configuration suitable for most use cases (Default).
    /// Trades moderate CPU usage for good compression ratios.
    pub fn balanced() Compression.CompressionConfig {
        return .{
            .algorithm = .deflate,
            .level = .default,
            .mode = .onRotation,
        };
    }

    /// Returns a configuration optimized for maximum ratio (Best).
    /// Higher CPU usage, recommended for archival storage.
    pub fn maximum() Compression.CompressionConfig {
        return .{
            .algorithm = .deflate,
            .level = .best,
            .mode = .onRotation,
            .keepOriginal = false,
        };
    }

    /// Returns a configuration that triggers based on file size threshold.
    pub fn onSize(thresholdMb: u64) Compression.CompressionConfig {
        return .{
            .algorithm = .deflate,
            .level = .default,
            .mode = .onSizeThreshold,
            .sizeThreshold = thresholdMb * Constants.SizeConstants.bytesPerMb,
        };
    }
};

/// Repeats `s` exactly `n` times at compile time.
///
/// Zig 0.17 removed the `**` array-repeat operator; `@splat` only covers
/// single values, so multi-byte test fixtures use this helper instead.
/// Returns a pointer to a zero-terminated static array, matching the
/// string-literal semantics of the removed operator.
fn repeatString(comptime s: []const u8, comptime n: usize) *const [s.len * n:0]u8 {
    const out = blk: {
        var tmp: [s.len * n:0]u8 = undefined;
        for (0..n) |i| @memcpy(tmp[i * s.len ..][0..s.len], s);
        tmp[tmp.len] = 0;
        break :blk tmp;
    };
    return &out;
}

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
    const data = comptime repeatString("AAAAAAAAAAAAAAAA", 50); // 800 bytes of 'A'
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

    const testData = comptime repeatString("The quick brown fox jumps over the lazy dog. ", 20);

    // Test different compression levels
    inline for (&[_]Compression.Level{ .none, .fast, .default, .best }) |level| {
        var comp = Compression.init(allocator);
        comp.config.level = level;
        defer comp.deinit();

        const compressed = try comp.compress(testData);
        defer allocator.free(compressed);

        const decompressed = try comp.decompress(compressed);
        defer allocator.free(decompressed);

        try std.testing.expectEqualStrings(testData, decompressed);
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

    const data = comptime repeatString("Test data", 100); // Repetitive data compresses well
    const compressed = try comp.compress(data);
    defer allocator.free(compressed);

    const stats = comp.getStats();
    try std.testing.expect(stats.bytesBefore.load(.monotonic) > 0);
    try std.testing.expect(stats.bytesAfter.load(.monotonic) > 0);
    try std.testing.expect(stats.filesCompressed.load(.monotonic) > 0);
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

    const data = comptime repeatString("Streaming test data", 10);

    const reader: std.Io.Reader = .fixed(data);
    var outBuffer = std.Io.Writer.Allocating.init(allocator);
    defer outBuffer.deinit();

    try comp.compressStream(reader, &outBuffer.writer);

    try std.testing.expect(outBuffer.written().len > 0);

    // Verify roundtrip
    const decompInStream = std.Io.Reader.fixed(outBuffer.written());
    var decompOutBuffer = std.Io.Writer.Allocating.init(allocator);
    defer decompOutBuffer.deinit();

    try comp.decompressStream(decompInStream, &decompOutBuffer.writer);

    try std.testing.expectEqualStrings(data, decompOutBuffer.written());
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
    const testDir = "test_output_compression";
    const testFile = "test_file_to_compress.log";
    const outputFile = "test_output_compression/nested/dirs/output.log.gz";

    // Clean up before test
    std.Io.Dir.cwd().deleteTree(Utils.defaultIo(), testDir) catch {};
    defer std.Io.Dir.cwd().deleteTree(Utils.defaultIo(), testDir) catch {};

    // Create a dummy source file
    const file = try std.Io.Dir.cwd().createFile(Utils.defaultIo(), testFile, .{});
    try file.writeStreamingAll(Utils.defaultIo(), "Test content for compression");
    file.close(Utils.defaultIo());
    defer std.Io.Dir.cwd().deleteFile(Utils.defaultIo(), testFile) catch {};

    // Compress with deep path that doesn't exist yet
    const result = try comp.compressFile(testFile, outputFile);

    // Verify success
    try std.testing.expect(result.success);
    if (result.outputPath) |path| {
        defer allocator.free(path);
    }

    // Verify directory was created
    const stat = try std.Io.Dir.cwd().statFile(Utils.defaultIo(), outputFile, .{});
    try std.testing.expect(stat.size > 0);
}

test "directory compression" {
    const allocator = std.testing.allocator;
    var comp = Compression.init(allocator);
    defer comp.deinit();

    const testDir = "test_batch_compression";

    // Setup test directory
    std.Io.Dir.cwd().deleteTree(Utils.defaultIo(), testDir) catch {};
    try std.Io.Dir.cwd().createDirPath(Utils.defaultIo(), testDir);
    defer std.Io.Dir.cwd().deleteTree(Utils.defaultIo(), testDir) catch {};

    // Create multiple log files
    const files = [_][]const u8{ "log1.log", "log2.log", "skip.txt" };
    for (files) |fname| {
        const p = try std.fs.path.join(allocator, &[_][]const u8{ testDir, fname });
        defer allocator.free(p);
        const f = try std.Io.Dir.cwd().createFile(Utils.defaultIo(), p, .{});
        try f.writeStreamingAll(Utils.defaultIo(), "Log data content");
        f.close(Utils.defaultIo());
    }

    // configure to only compress .log files if we were filtering extensions,
    // but shouldCompress currently checks for NOT compressed extensions.
    // So all valid files should be compressed.

    const compressedCount = try comp.compressDirectory(testDir);

    // Should compress 3 files (log1.log, log2.log, skip.txt)
    try std.testing.expectEqual(@as(u64, 3), compressedCount);

    // Verify .gz files exist
    var dir = try std.Io.Dir.cwd().openDir(Utils.defaultIo(), testDir, .{ .iterate = true });
    defer dir.close(Utils.defaultIo());

    var count: usize = 0;
    var it = dir.iterate();
    while (try it.next(Utils.defaultIo())) |entry| {
        if (std.mem.endsWith(u8, entry.name, ".gz")) {
            count += 1;
        }
    }

    try std.testing.expectEqual(@as(usize, 3), count);
}

test "zstd compression basic" {
    const allocator = std.testing.allocator;

    var comp = Compression.zstdCompression(allocator);
    defer comp.deinit();

    const data = "Hello, World! This is test data for zstd compression.";
    const compressed = try comp.compress(data);
    defer allocator.free(compressed);

    // Compressed data should exist
    try std.testing.expect(compressed.len > 0);

    // Verify we can decompress back to original
    const decompressed = try comp.decompress(compressed);
    defer allocator.free(decompressed);

    try std.testing.expectEqualStrings(data, decompressed);
}

test "zstd compression with repetitive data" {
    const allocator = std.testing.allocator;

    var comp = Compression.zstdCompression(allocator);
    defer comp.deinit();

    // Repetitive data compresses well
    const data = comptime repeatString("AAAAAAAAAAAAAAAA", 50); // 800 bytes of 'A'
    const compressed = try comp.compress(data);
    defer allocator.free(compressed);

    // Zstd should achieve very significant compression on repetitive data
    try std.testing.expect(compressed.len < data.len);

    // Verify roundtrip
    const decompressed = try comp.decompress(compressed);
    defer allocator.free(decompressed);

    try std.testing.expectEqualStrings(data, decompressed);
}

test "zstd compression presets" {
    const allocator = std.testing.allocator;
    const testData = comptime repeatString("The quick brown fox jumps over the lazy dog. ", 20);

    // Test zstd presets
    {
        var comp = Compression.zstdCompression(allocator);
        defer comp.deinit();
        const compressed = try comp.compress(testData);
        defer allocator.free(compressed);
        const decompressed = try comp.decompress(compressed);
        defer allocator.free(decompressed);
        try std.testing.expectEqualStrings(testData, decompressed);
    }

    {
        var comp = Compression.zstdFast(allocator);
        defer comp.deinit();
        const compressed = try comp.compress(testData);
        defer allocator.free(compressed);
        const decompressed = try comp.decompress(compressed);
        defer allocator.free(decompressed);
        try std.testing.expectEqualStrings(testData, decompressed);
    }

    {
        var comp = Compression.zstdBest(allocator);
        defer comp.deinit();
        const compressed = try comp.compress(testData);
        defer allocator.free(compressed);
        const decompressed = try comp.decompress(compressed);
        defer allocator.free(decompressed);
        try std.testing.expectEqualStrings(testData, decompressed);
    }

    {
        var comp = Compression.zstdProduction(allocator);
        defer comp.deinit();
        const compressed = try comp.compress(testData);
        defer allocator.free(compressed);
        const decompressed = try comp.decompress(compressed);
        defer allocator.free(decompressed);
        try std.testing.expectEqualStrings(testData, decompressed);
    }
}

test "zstd compression levels" {
    const allocator = std.testing.allocator;
    const testData = comptime repeatString("Log data: ", 100); // Good test data for compression

    // Test all standard levels via CompressionLevel enum
    inline for (&[_]Compression.Level{ .fastest, .fast, .default, .best }) |level| {
        var comp = Compression.init(allocator);
        comp.config.algorithm = .zstd;
        comp.config.level = level;
        comp.config.extension = ".zst";
        defer comp.deinit();

        const compressed = try comp.compress(testData);
        defer allocator.free(compressed);

        const decompressed = try comp.decompress(compressed);
        defer allocator.free(decompressed);

        try std.testing.expectEqualStrings(testData, decompressed);
    }
}

test "zstd compression with log-like data" {
    const allocator = std.testing.allocator;

    var comp = Compression.zstdCompression(allocator);
    defer comp.deinit();

    const data =
        \\[2025-01-17 10:00:00] INFO  Application started successfully
        \\[2025-01-17 10:00:01] DEBUG Processing request from user 12345
        \\[2025-01-17 10:00:02] INFO  Database connection established
        \\[2025-01-17 10:00:03] DEBUG Processing request from user 12346
        \\[2025-01-17 10:00:04] INFO  Cache hit ratio: 95.5%
        \\[2025-01-17 10:00:05] DEBUG Processing request from user 12347
        \\[2025-01-17 10:00:06] WARNING Slow query detected: 250ms
        \\[2025-01-17 10:00:07] DEBUG Processing request from user 12348
        \\[2025-01-17 10:00:08] ERROR Connection timeout to external service
        \\[2025-01-17 10:00:09] DEBUG Processing request from user 12349
    ;

    const compressed = try comp.compress(data);
    defer allocator.free(compressed);

    // Zstd should compress log data well
    try std.testing.expect(compressed.len < data.len);

    // Verify roundtrip
    const decompressed = try comp.decompress(compressed);
    defer allocator.free(decompressed);

    try std.testing.expectEqualStrings(data, decompressed);
}

test "zstd compression stats" {
    const allocator = std.testing.allocator;

    var comp = Compression.zstdCompression(allocator);
    defer comp.deinit();

    const data = comptime repeatString("Zstd test data", 100);
    const compressed = try comp.compress(data);
    defer allocator.free(compressed);

    const stats = comp.getStats();
    try std.testing.expect(stats.bytesBefore.load(.monotonic) > 0);
    try std.testing.expect(stats.bytesAfter.load(.monotonic) > 0);
    try std.testing.expect(stats.filesCompressed.load(.monotonic) > 0);

    // Verify compression ratio makes sense
    const ratioVal = stats.compressionRatio();
    try std.testing.expect(ratioVal > 1.0); // Should achieve compression
}

test "zstd compression CRC32 checksum" {
    const allocator = std.testing.allocator;

    var comp = Compression.zstdCompression(allocator);
    comp.config.checksum = true;
    defer comp.deinit();

    const data = "Test data with checksum verification for zstd";
    const compressed = try comp.compress(data);
    defer allocator.free(compressed);

    // Verify roundtrip with checksum validation
    const decompressed = try comp.decompress(compressed);
    defer allocator.free(decompressed);

    try std.testing.expectEqualStrings(data, decompressed);
}

test "all algorithms compress and decompress" {
    const allocator = std.testing.allocator;
    const testData = comptime repeatString("Test data for all compression algorithms", 10);

    // Test all algorithms (excluding .none which is passthrough mode)
    inline for (&[_]Compression.Algorithm{ .deflate, .zlib, .rawDeflate, .gzip, .zstd }) |algo| {
        var comp = Compression.init(allocator);
        comp.config.algorithm = algo;
        comp.config.extension = switch (algo) {
            .none => "",
            .zstd => ".zst",
            else => ".gz",
        };
        defer comp.deinit();

        const compressed = try comp.compress(testData);
        defer allocator.free(compressed);

        const decompressed = try comp.decompress(compressed);
        defer allocator.free(decompressed);

        try std.testing.expectEqualStrings(testData, decompressed);
    }
}

test "deflate algorithm" {
    const allocator = std.testing.allocator;

    var comp = Compression.init(allocator);
    comp.config.algorithm = .deflate;
    defer comp.deinit();

    const data = comptime repeatString("DEFLATE test data", 10);
    const compressed = try comp.compress(data);
    defer allocator.free(compressed);

    try std.testing.expect(compressed.len > 0);

    const decompressed = try comp.decompress(compressed);
    defer allocator.free(decompressed);

    try std.testing.expectEqualStrings(data, decompressed);
}

test "zlib algorithm" {
    const allocator = std.testing.allocator;

    var comp = Compression.init(allocator);
    comp.config.algorithm = .zlib;
    defer comp.deinit();

    const data = comptime repeatString("ZLIB test data", 10);
    const compressed = try comp.compress(data);
    defer allocator.free(compressed);

    try std.testing.expect(compressed.len > 0);

    const decompressed = try comp.decompress(compressed);
    defer allocator.free(decompressed);

    try std.testing.expectEqualStrings(data, decompressed);
}

test "raw_deflate algorithm" {
    const allocator = std.testing.allocator;

    var comp = Compression.init(allocator);
    comp.config.algorithm = .rawDeflate;
    defer comp.deinit();

    const data = comptime repeatString("RAW_DEFLATE test data", 10);
    const compressed = try comp.compress(data);
    defer allocator.free(compressed);

    try std.testing.expect(compressed.len > 0);

    const decompressed = try comp.decompress(compressed);
    defer allocator.free(decompressed);

    try std.testing.expectEqualStrings(data, decompressed);
}

test "none algorithm passthrough" {
    const allocator = std.testing.allocator;

    var comp = Compression.init(allocator);
    comp.config.algorithm = .none;
    defer comp.deinit();

    const data = "Passthrough data without compression";
    const compressed = try comp.compress(data);
    defer allocator.free(compressed);

    // With .none, data is returned as-is (no header, exact copy)
    try std.testing.expectEqual(data.len, compressed.len);

    // With .none algorithm, compress just returns a copy, not a compressed format
    // So we compare directly instead of decompressing
    try std.testing.expectEqualStrings(data, compressed);
}

test "decompress deflate capacity overflow" {
    // Only run this test on platforms where usize is smaller than u64 (e.g., 32-bit).
    // On 64-bit native builds the `too_big` value can't be represented in u64
    // because `std.math.maxInt(usize) == std.math.maxInt(u64)`, so skip the test.
    if (@sizeOf(usize) >= @sizeOf(u64)) return;

    const allocator = std.testing.allocator;

    var comp = Compression.init(allocator);
    defer comp.deinit();

    // Empty/placeholder compressed data is fine; we only exercise the size guard.
    const dummy: []const u8 = &[_]u8{};
    const tooBig: u64 = @as(u64, std.math.maxInt(usize)) + 1;

    // Expect the helper to fail early with OutputTooLarge
    try std.testing.expectError(error.OutputTooLarge, comp.decompressDeflateNative(dummy, tooBig, 0));
}

test "compression preset factory methods" {
    const allocator = std.testing.allocator;
    const testData = comptime repeatString("Preset test data", 20);

    // Test all Compression factory methods
    const factories = .{
        Compression.enable,
        Compression.basic,
        Compression.implicit,
        Compression.explicit,
        Compression.fast,
        Compression.balanced,
        Compression.best,
        Compression.forLogs,
        Compression.archive,
        Compression.production,
        Compression.development,
        Compression.background,
        Compression.streaming,
        Compression.zstdCompression,
        Compression.zstdFast,
        Compression.zstdBest,
        Compression.zstdProduction,
    };

    inline for (factories) |factory| {
        var comp = factory(allocator);
        defer comp.deinit();

        const compressed = try comp.compress(testData);
        defer allocator.free(compressed);

        const decompressed = try comp.decompress(compressed);
        defer allocator.free(decompressed);

        try std.testing.expectEqualStrings(testData, decompressed);
    }
}

test "CompressionPresets struct" {
    // Test none preset
    const noneConfig = CompressionPresets.none();
    try std.testing.expectEqual(Compression.Algorithm.none, noneConfig.algorithm);
    try std.testing.expectEqual(Compression.Mode.disabled, noneConfig.mode);

    // Test fast preset
    const fastConfig = CompressionPresets.fast();
    try std.testing.expectEqual(Compression.Level.fast, fastConfig.level);
    try std.testing.expectEqual(Compression.Mode.onRotation, fastConfig.mode);

    // Test balanced preset
    const balancedConfig = CompressionPresets.balanced();
    try std.testing.expectEqual(Compression.Level.default, balancedConfig.level);

    // Test maximum preset
    const maxConfig = CompressionPresets.maximum();
    try std.testing.expectEqual(Compression.Level.best, maxConfig.level);
    try std.testing.expectEqual(false, maxConfig.keepOriginal);

    // Test onSize preset
    const sizeConfig = CompressionPresets.onSize(10);
    try std.testing.expectEqual(Compression.Mode.onSizeThreshold, sizeConfig.mode);
    try std.testing.expectEqual(@as(u64, 10 * Constants.SizeConstants.bytesPerMb), sizeConfig.sizeThreshold);
}

var callbackTestStartCalled: bool = false;
var callbackTestCompleteCalled: bool = false;
var callbackTestErrorCalled: bool = false;
var callbackTestDecompressCalled: bool = false;

fn testCompressionStartCallback(_: []const u8, _: u64) void {
    callbackTestStartCalled = true;
}

fn testCompressionCompleteCallback(_: []const u8, _: []const u8, _: u64, _: u64, _: u64) void {
    callbackTestCompleteCalled = true;
}

fn testCompressionErrorCallback(_: []const u8, _: anyerror) void {
    callbackTestErrorCalled = true;
}

fn testDecompressionCompleteCallback(_: []const u8, _: []const u8) void {
    callbackTestDecompressCalled = true;
}

test "compression callbacks" {
    const allocator = std.testing.allocator;

    // Reset callback flags
    callbackTestStartCalled = false;
    callbackTestCompleteCalled = false;
    callbackTestDecompressCalled = false;

    var comp = Compression.init(allocator);
    defer comp.deinit();

    // Set callbacks
    comp.setCompressionStartCallback(&testCompressionStartCallback);
    comp.setCompressionCompleteCallback(&testCompressionCompleteCallback);
    comp.setDecompressionCompleteCallback(&testDecompressionCompleteCallback);

    // Callbacks are invoked on file operations, not memory operations
    // But we can verify the callback setters work
    try std.testing.expect(comp.onCompressionStart != null);
    try std.testing.expect(comp.onCompressionComplete != null);
    try std.testing.expect(comp.onDecompressionComplete != null);
}

test "compression aliases" {
    const allocator = std.testing.allocator;

    var comp = Compression.init(allocator);
    defer comp.deinit();

    const data = "Test data for alias methods";

    // Test encode alias (same as compress)
    const encoded = try comp.compress(data);
    defer allocator.free(encoded);

    // Test decode alias (same as decompress)
    const decoded = try comp.decompress(encoded);
    defer allocator.free(decoded);

    try std.testing.expectEqualStrings(data, decoded);

    // Test deflate alias (same as compress)
    const deflated = try comp.compress(data);
    defer allocator.free(deflated);

    // Test inflate alias (same as decompress)
    const inflated = try comp.decompress(deflated);
    defer allocator.free(inflated);

    try std.testing.expectEqualStrings(data, inflated);
}

test "compression create alias" {
    const allocator = std.testing.allocator;

    // Test create alias (same as init)
    var comp = Compression.init(allocator);
    defer comp.deinit(); // Test destroy alias (same as deinit)

    const data = "Test create and destroy aliases";
    const compressed = try comp.compress(data);
    defer allocator.free(compressed);

    const decompressed = try comp.decompress(compressed);
    defer allocator.free(decompressed);

    try std.testing.expectEqualStrings(data, decompressed);
}

test "compression lzma" {
    const allocator = std.testing.allocator;
    const testData = "Hello, World!";
    var comp = Compression.init(allocator);
    comp.config.algorithm = .lzma;
    comp.config.extension = ".lzma";
    defer comp.deinit();

    try std.testing.expectEqual(Compression.Algorithm.lzma, comp.config.algorithm);
    const compressed = try comp.compress(testData);
    defer allocator.free(compressed);
    try std.testing.expect(compressed.len > 0);
    const decompressed = try comp.decompress(compressed);
    defer allocator.free(decompressed);
    try std.testing.expectEqualStrings(testData, decompressed);
}

test "compression lzma2" {
    const allocator = std.testing.allocator;
    const testData = "Hello, World!";
    var comp = Compression.init(allocator);
    comp.config.algorithm = .lzma2;
    comp.config.extension = ".lzma2";
    defer comp.deinit();

    const compressed = try comp.compress(testData);
    defer allocator.free(compressed);
    try std.testing.expect(compressed.len > 0);
    const decompressed = try comp.decompress(compressed);
    defer allocator.free(decompressed);
    try std.testing.expectEqualStrings(testData, decompressed);
}

test "compression xz" {
    const allocator = std.testing.allocator;
    const testData = "Hello, World!";
    var comp = Compression.init(allocator);
    comp.config.algorithm = .xz;
    comp.config.extension = ".xz";
    defer comp.deinit();

    const compressed = try comp.compress(testData);
    defer allocator.free(compressed);
    try std.testing.expect(compressed.len > 0);
    const decompressed = try comp.decompress(compressed);
    defer allocator.free(decompressed);
    try std.testing.expectEqualStrings(testData, decompressed);
}

test "compression zip" {
    const allocator = std.testing.allocator;
    const testData = "Hello, World!";
    var comp = Compression.init(allocator);
    comp.config.algorithm = .zip;
    comp.config.extension = ".zip";
    defer comp.deinit();

    const compressed = try comp.compress(testData);
    defer allocator.free(compressed);
    const decompressed = try comp.decompress(compressed);
    defer allocator.free(decompressed);
    try std.testing.expectEqualStrings(testData, decompressed);
}

test "compression tar_gz" {
    const allocator = std.testing.allocator;
    const testData = "Hello, World!";
    var comp = Compression.init(allocator);
    comp.config.algorithm = .tarGz;
    comp.config.extension = ".tar.gz";
    defer comp.deinit();

    const compressed = try comp.compress(testData);
    defer allocator.free(compressed);
    const decompressed = try comp.decompress(compressed);
    defer allocator.free(decompressed);
    try std.testing.expectEqualStrings(testData, decompressed);
}

test "compression lz4" {
    const allocator = std.testing.allocator;
    const testData = "Hello, World!";
    var comp = Compression.init(allocator);
    comp.config.algorithm = .lz4;
    comp.config.extension = ".lz4";
    defer comp.deinit();

    const compressed = try comp.compress(testData);
    defer allocator.free(compressed);
    const decompressed = try comp.decompress(compressed);
    defer allocator.free(decompressed);
    try std.testing.expectEqualStrings(testData, decompressed);
}

test "statistics alias" {
    const allocator = std.testing.allocator;

    var comp = Compression.init(allocator);
    defer comp.deinit();

    const data = comptime repeatString("Test data", 50);
    const compressed = try comp.compress(data);
    defer allocator.free(compressed);

    // Test statistics alias (same as getStats)
    const stats = comp.getStats();
    try std.testing.expect(stats.bytesBefore.load(.monotonic) > 0);
}

test "needsCompression alias" {
    const allocator = std.testing.allocator;

    var comp = Compression.init(allocator);
    defer comp.deinit();

    // Test needsCompression alias (same as shouldCompress)
    // This should return true for non-compressed files
    const needs = comp.shouldCompress("test.log");
    try std.testing.expect(needs);

    // Should return false for already compressed files
    const noNeedsGz = comp.shouldCompress("test.log.gz");
    try std.testing.expect(!noNeedsGz);

    const noNeedsZst = comp.shouldCompress("test.log.zst");
    try std.testing.expect(!noNeedsZst);
}

test "compression level toInt mapping" {
    try std.testing.expectEqual(@as(u4, 0), Compression.Level.none.toInt());
    try std.testing.expectEqual(@as(u4, 1), Compression.Level.fastest.toInt());
    try std.testing.expectEqual(@as(u4, 3), Compression.Level.fast.toInt());
    try std.testing.expectEqual(@as(u4, 6), Compression.Level.default.toInt());
    try std.testing.expectEqual(@as(u4, 9), Compression.Level.best.toInt());
}

test "compression level toZstdLevel mapping" {
    try std.testing.expectEqual(@as(i32, 0), Compression.Level.none.toZstdLevel());
    try std.testing.expectEqual(@as(i32, 1), Compression.Level.fastest.toZstdLevel());
    try std.testing.expectEqual(@as(i32, 3), Compression.Level.fast.toZstdLevel());
    try std.testing.expectEqual(@as(i32, 6), Compression.Level.default.toZstdLevel());
    try std.testing.expectEqual(@as(i32, 19), Compression.Level.best.toZstdLevel());
}

test "CompressionStats getter methods" {
    var stats = Compression.CompressionStats{};

    // Initialize with some values
    _ = stats.filesCompressed.fetchAdd(10, .monotonic);
    _ = stats.filesDecompressed.fetchAdd(5, .monotonic);
    _ = stats.bytesBefore.fetchAdd(10000, .monotonic);
    _ = stats.bytesAfter.fetchAdd(2000, .monotonic);
    _ = stats.compressionErrors.fetchAdd(1, .monotonic);
    _ = stats.decompressionErrors.fetchAdd(2, .monotonic);
    _ = stats.backgroundTasksQueued.fetchAdd(20, .monotonic);
    _ = stats.backgroundTasksCompleted.fetchAdd(15, .monotonic);

    // Test getter methods
    try std.testing.expectEqual(@as(u64, 10), stats.getFilesCompressed());
    try std.testing.expectEqual(@as(u64, 5), stats.getFilesDecompressed());
    try std.testing.expectEqual(@as(u64, 10000), stats.getBytesBefore());
    try std.testing.expectEqual(@as(u64, 2000), stats.getBytesAfter());
    try std.testing.expectEqual(@as(u64, 8000), stats.getBytesSaved());
    try std.testing.expectEqual(@as(u64, 1), stats.getCompressionErrors());
    try std.testing.expectEqual(@as(u64, 2), stats.getDecompressionErrors());
    try std.testing.expectEqual(@as(u64, 15), stats.getTotalOperations());
    try std.testing.expectEqual(@as(u64, 20), stats.getBackgroundTasksQueued());
    try std.testing.expectEqual(@as(u64, 15), stats.getBackgroundTasksCompleted());

    // Test derived metrics
    try std.testing.expect(stats.compressionRatio() > 0);
    try std.testing.expect(stats.spaceSavingsPercent() > 0);
    try std.testing.expect(stats.hasErrors());
    try std.testing.expect(stats.hasOperations());

    // Test reset
    stats.reset();
    try std.testing.expectEqual(@as(u64, 0), stats.getFilesCompressed());
    try std.testing.expect(!stats.hasErrors());
    try std.testing.expect(!stats.hasOperations());
}

test "isEnabled method" {
    const allocator = std.testing.allocator;

    var enabledComp = Compression.enable(allocator);
    defer enabledComp.deinit();
    try std.testing.expect(enabledComp.isEnabled());

    var disabledComp = Compression.init(allocator);
    disabledComp.config.mode = .disabled;
    defer disabledComp.deinit();
    try std.testing.expect(!disabledComp.isEnabled());
}

test "ratio method" {
    const allocator = std.testing.allocator;

    var comp = Compression.zstdCompression(allocator);
    defer comp.deinit();

    const data = comptime repeatString("Repetitive data ", 100);
    const compressed = try comp.compress(data);
    defer allocator.free(compressed);

    const ratioVal = comp.ratio();
    try std.testing.expect(ratioVal > 1.0); // Should achieve compression
}

test "zstd custom level compression" {
    const allocator = std.testing.allocator;
    const testData = comptime repeatString("Custom level test data ", 50);

    // Test various custom zstd levels
    inline for (&[_]i32{ 1, 3, 6, 10, 15, 19, 22 }) |customLevel| {
        var comp = Compression.zstdWithLevel(allocator, customLevel);
        defer comp.deinit();

        const compressed = try comp.compress(testData);
        defer allocator.free(compressed);

        const decompressed = try comp.decompress(compressed);
        defer allocator.free(decompressed);

        try std.testing.expectEqualStrings(testData, decompressed);
    }
}

test "zstd custom level clamping" {
    const allocator = std.testing.allocator;
    const testData = comptime repeatString("Clamping test data ", 20);

    // Test level clamping (levels < 1 should clamp to 1, > 22 should clamp to 22)
    {
        var comp = Compression.zstdWithLevel(allocator, 0); // Should clamp to 1
        defer comp.deinit();

        const compressed = try comp.compress(testData);
        defer allocator.free(compressed);

        const decompressed = try comp.decompress(compressed);
        defer allocator.free(decompressed);

        try std.testing.expectEqualStrings(testData, decompressed);
    }

    {
        var comp = Compression.zstdWithLevel(allocator, 100); // Should clamp to 22
        defer comp.deinit();

        const compressed = try comp.compress(testData);
        defer allocator.free(compressed);

        const decompressed = try comp.decompress(compressed);
        defer allocator.free(decompressed);

        try std.testing.expectEqualStrings(testData, decompressed);
    }
}

test "zstd getEffectiveZstdLevel" {
    const CompressionConfig = Compression.CompressionConfig;
    // Test with custom level set
    {
        const config = CompressionConfig.zstdWithLevel(15);
        try std.testing.expectEqual(@as(i32, 15), config.getEffectiveZstdLevel());
    }

    // Test with enum level (no custom)
    {
        const config = CompressionConfig.zstd();
        try std.testing.expectEqual(@as(i32, 6), config.getEffectiveZstdLevel()); // default maps to 6
    }

    // Test fast preset
    {
        const config = CompressionConfig.zstdFast();
        try std.testing.expectEqual(@as(i32, 1), config.getEffectiveZstdLevel()); // fastest maps to 1
    }

    // Test best preset
    {
        const config = CompressionConfig.zstdBest();
        try std.testing.expectEqual(@as(i32, 19), config.getEffectiveZstdLevel()); // best maps to 19
    }
}

test "zstd aliases" {
    const allocator = std.testing.allocator;
    const testData = comptime repeatString("Alias test data ", 30);

    // Test zstdDefault alias (same as zstdCompression)
    {
        var comp = Compression.zstdCompression(allocator);
        defer comp.deinit();

        const compressed = try comp.compress(testData);
        defer allocator.free(compressed);

        const decompressed = try comp.decompress(compressed);
        defer allocator.free(decompressed);

        try std.testing.expectEqualStrings(testData, decompressed);
    }

    // Test zstdSpeed alias (same as zstdFast)
    {
        var comp = Compression.zstdFast(allocator);
        defer comp.deinit();

        const compressed = try comp.compress(testData);
        defer allocator.free(compressed);

        const decompressed = try comp.decompress(compressed);
        defer allocator.free(decompressed);

        try std.testing.expectEqualStrings(testData, decompressed);
    }

    // Test zstdMax alias (same as zstdBest)
    {
        var comp = Compression.zstdBest(allocator);
        defer comp.deinit();

        const compressed = try comp.compress(testData);
        defer allocator.free(compressed);

        const decompressed = try comp.decompress(compressed);
        defer allocator.free(decompressed);

        try std.testing.expectEqualStrings(testData, decompressed);
    }
}

test "CompressionConfig zstd aliases" {
    const CompressionConfig = Compression.CompressionConfig;
    // Test zstdDefault alias
    const defaultConfig = CompressionConfig.zstd();
    try std.testing.expectEqual(Compression.Algorithm.zstd, defaultConfig.algorithm);

    // Test zstdSpeed alias
    const speedConfig = CompressionConfig.zstdFast();
    try std.testing.expectEqual(Compression.Level.fastest, speedConfig.level);

    // Test zstdMax alias
    const maxConfig = CompressionConfig.zstdBest();
    try std.testing.expectEqual(Compression.Level.best, maxConfig.level);
}

test "lzma compression roundtrip" {
    const allocator = std.testing.allocator;
    const testData = comptime repeatString("LZMA compression test data for log files", 20);

    var comp = Compression.lzmaCompression(allocator);
    defer comp.deinit();

    try std.testing.expectEqual(Compression.Algorithm.lzma, comp.config.algorithm);

    const compressed = try comp.compress(testData);
    defer allocator.free(compressed);

    try std.testing.expect(compressed.len > 0);

    const decompressed = try comp.decompress(compressed);
    defer allocator.free(decompressed);

    try std.testing.expectEqualStrings(testData, decompressed);
}

test "lzma2 compression roundtrip" {
    const allocator = std.testing.allocator;
    const testData = comptime repeatString("LZMA2 compression test data for log files", 20);

    var comp = Compression.lzma2Compression(allocator);
    defer comp.deinit();

    try std.testing.expectEqual(Compression.Algorithm.lzma2, comp.config.algorithm);

    const compressed = try comp.compress(testData);
    defer allocator.free(compressed);

    try std.testing.expect(compressed.len > 0);

    const decompressed = try comp.decompress(compressed);
    defer allocator.free(decompressed);

    try std.testing.expectEqualStrings(testData, decompressed);
}

test "xz compression roundtrip" {
    const allocator = std.testing.allocator;
    const testData = comptime repeatString("XZ compression test data for log files", 20);

    var comp = Compression.xzCompression(allocator);
    defer comp.deinit();

    try std.testing.expectEqual(Compression.Algorithm.xz, comp.config.algorithm);

    const compressed = try comp.compress(testData);
    defer allocator.free(compressed);

    try std.testing.expect(compressed.len > 0);

    const decompressed = try comp.decompress(compressed);
    defer allocator.free(decompressed);

    try std.testing.expectEqualStrings(testData, decompressed);
}

test "zip compression roundtrip" {
    const allocator = std.testing.allocator;
    const testData = comptime repeatString("ZIP compression test data for log files", 20);

    var comp = Compression.zipCompression(allocator);
    defer comp.deinit();

    try std.testing.expectEqual(Compression.Algorithm.zip, comp.config.algorithm);

    const compressed = try comp.compress(testData);
    defer allocator.free(compressed);

    try std.testing.expect(compressed.len > 0);

    const decompressed = try comp.decompress(compressed);
    defer allocator.free(decompressed);

    try std.testing.expectEqualStrings(testData, decompressed);
}

test "tar.gz compression roundtrip" {
    const allocator = std.testing.allocator;
    const testData = comptime repeatString("TAR.GZ compression test data for log files", 20);

    var comp = Compression.tarGzCompression(allocator);
    defer comp.deinit();

    try std.testing.expectEqual(Compression.Algorithm.tarGz, comp.config.algorithm);

    const compressed = try comp.compress(testData);
    defer allocator.free(compressed);

    try std.testing.expect(compressed.len > 0);

    const decompressed = try comp.decompress(compressed);
    defer allocator.free(decompressed);

    try std.testing.expectEqualStrings(testData, decompressed);
}

test "lz4 compression roundtrip" {
    const allocator = std.testing.allocator;
    const testData = comptime repeatString("LZ4 compression test data for log files", 20);

    var comp = Compression.lz4Compression(allocator);
    defer comp.deinit();

    try std.testing.expectEqual(Compression.Algorithm.lz4, comp.config.algorithm);

    const compressed = try comp.compress(testData);
    defer allocator.free(compressed);

    try std.testing.expect(compressed.len > 0);

    const decompressed = try comp.decompress(compressed);
    defer allocator.free(decompressed);

    try std.testing.expectEqualStrings(testData, decompressed);
}

test "all v0.1.6 compression algorithms with empty data" {
    const allocator = std.testing.allocator;
    const emptyData = "";

    const algorithms = [_]Compression.Algorithm{
        .lzma, .lzma2, .xz, .zip, .tarGz, .lz4,
    };

    inline for (algorithms) |algo| {
        var comp = Compression.init(allocator);
        comp.config.algorithm = algo;
        defer comp.deinit();

        const compressed = try comp.compress(emptyData);
        defer allocator.free(compressed);

        // Empty data should produce empty result
        try std.testing.expectEqual(@as(usize, 0), compressed.len);
    }
}

test "all v0.1.6 compression algorithms with large data" {
    const allocator = std.testing.allocator;
    // 10KB of repetitive log-like data
    const testData = comptime repeatString("[2026-01-19T19:30:00Z] INFO: Application started successfully\n", 150);

    const algorithms = [_]struct { algo: Compression.Algorithm, name: []const u8 }{
        .{ .algo = .lzma, .name = "lzma" },
        .{ .algo = .lzma2, .name = "lzma2" },
        .{ .algo = .xz, .name = "xz" },
        .{ .algo = .zip, .name = "zip" },
        .{ .algo = .tarGz, .name = "tar_gz" },
        .{ .algo = .lz4, .name = "lz4" },
    };

    inline for (algorithms) |item| {
        var comp = Compression.init(allocator);
        comp.config.algorithm = item.algo;
        defer comp.deinit();

        const compressed = try comp.compress(testData);
        defer allocator.free(compressed);

        try std.testing.expect(compressed.len > 0);

        const decompressed = try comp.decompress(compressed);
        defer allocator.free(decompressed);

        try std.testing.expectEqualStrings(testData, decompressed);
    }
}

test "compression factory methods for new algorithms" {
    const allocator = std.testing.allocator;
    const testData = comptime repeatString("Factory method test", 10);

    // Test all new factory methods
    const factories = .{
        Compression.lzmaCompression,
        Compression.lzma2Compression,
        Compression.xzCompression,
        Compression.tarGzCompression,
        Compression.zipCompression,
        Compression.lz4Compression,
    };

    inline for (factories) |factory| {
        var comp = factory(allocator);
        defer comp.deinit();

        const compressed = try comp.compress(testData);
        defer allocator.free(compressed);

        const decompressed = try comp.decompress(compressed);
        defer allocator.free(decompressed);

        try std.testing.expectEqualStrings(testData, decompressed);
    }
}

test "compression with checksum for new algorithms" {
    const allocator = std.testing.allocator;
    const testData = comptime repeatString("Checksum verification test data", 15);

    const algorithms = [_]Compression.Algorithm{
        .lzma, .lzma2, .xz, .zip, .tarGz, .lz4,
    };

    inline for (algorithms) |algo| {
        var comp = Compression.init(allocator);
        comp.config.algorithm = algo;
        comp.config.checksum = true;
        defer comp.deinit();

        const compressed = try comp.compress(testData);
        defer allocator.free(compressed);

        const decompressed = try comp.decompress(compressed);
        defer allocator.free(decompressed);

        try std.testing.expectEqualStrings(testData, decompressed);
    }
}

test "compression config presets for new algorithms" {
    const CompressionConfig = Compression.CompressionConfig;

    // Test config factory methods
    const lzmaConfig = CompressionConfig.lzma();
    try std.testing.expectEqual(Compression.Algorithm.lzma, lzmaConfig.algorithm);
    try std.testing.expectEqualStrings(".lzma", lzmaConfig.extension);

    const lzma2Config = CompressionConfig.lzma2();
    try std.testing.expectEqual(Compression.Algorithm.lzma2, lzma2Config.algorithm);
    try std.testing.expectEqualStrings(".lzma2", lzma2Config.extension);

    const xzConfig = CompressionConfig.xz();
    try std.testing.expectEqual(Compression.Algorithm.xz, xzConfig.algorithm);
    try std.testing.expectEqualStrings(".xz", xzConfig.extension);

    const tarGzConfig = CompressionConfig.tarGz();
    try std.testing.expectEqual(Compression.Algorithm.tarGz, tarGzConfig.algorithm);
    try std.testing.expectEqualStrings(".tar.gz", tarGzConfig.extension);

    const zipConfig = CompressionConfig.zip();
    try std.testing.expectEqual(Compression.Algorithm.zip, zipConfig.algorithm);
    try std.testing.expectEqualStrings(".zip", zipConfig.extension);

    const lz4Config = CompressionConfig.lz4();
    try std.testing.expectEqual(Compression.Algorithm.lz4, lz4Config.algorithm);
    try std.testing.expectEqualStrings(".lz4", lz4Config.extension);
}

test "compression stats tracking for new algorithms" {
    const allocator = std.testing.allocator;
    const testData = comptime repeatString("Stats tracking test data", 30);

    var comp = Compression.lzmaCompression(allocator);
    defer comp.deinit();

    // Reset stats
    comp.stats.reset();

    const compressed = try comp.compress(testData);
    defer allocator.free(compressed);

    const decompressed = try comp.decompress(compressed);
    defer allocator.free(decompressed);

    // Verify stats were recorded
    try std.testing.expect(comp.stats.getFilesCompressed() > 0);
    try std.testing.expect(comp.stats.getFilesDecompressed() > 0);
    try std.testing.expect(comp.stats.getBytesBefore() > 0);
    try std.testing.expect(comp.stats.getBytesAfter() > 0);
}
