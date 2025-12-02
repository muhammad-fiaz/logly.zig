//! # Logly
//!
//! A high-performance, structured logging library for Zig.
//!
//! Logly provides a clean, Python-like API for logging with support for:
//! - 🎨 Colored output
//! - 📊 JSON formatting
//! - 📁 File rotation
//! - ⚡ Async I/O
//! - 🔗 Context binding
//! - 🎭 Custom log levels
//!
//! ## Usage
//!
//! ```zig
//! const logly = @import("logly");
//!
//! pub fn main() !void {
//!     var gpa = std.heap.GeneralPurposeAllocator(.{}){};
//!     const allocator = gpa.allocator();
//!
//!     const logger = try logly.Logger.init(allocator);
//!     defer logger.deinit();
//!
//!     try logger.info("Hello, Logly!");
//! }
//! ```

const std = @import("std");

pub const Level = @import("level.zig").Level;
pub const Logger = @import("logger.zig").Logger;
pub const ScopedLogger = @import("logger.zig").ScopedLogger;
pub const Config = @import("config.zig").Config;
pub const Sink = @import("sink.zig").Sink;
pub const SinkConfig = @import("sink.zig").SinkConfig;
pub const Record = @import("record.zig").Record;
pub const Formatter = @import("formatter.zig").Formatter;
pub const Rotation = @import("rotation.zig").Rotation;

test {
    std.testing.refAllDecls(@This());
}
