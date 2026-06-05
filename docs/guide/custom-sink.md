---
title: Custom Sinks
description: Route logly output to a custom backend (database, Kafka, serial port, ...) using the CustomSink user-data callback.
head:
  - - meta
    - name: keywords
      content: logly, zig, custom sink, custom writer, kafka, database, syslog, plugin
---

# Custom Sinks

`logly.CustomSink` is the supported way to route logly output to a backend the library does not ship with — a custom binary encoder, a database writer, a Kafka producer, a hardware serial port, a remote syslog daemon with a proprietary wire format, etc.

It is a thin wrapper around a user-supplied `*const fn ([]const u8, *anyopaque) anyerror!void` write callback (plus optional flush / close callbacks). It tracks bytes written and records handled, surfaces write errors to the caller, and never assumes ownership of the user data.

## Basic Usage

```zig
const logly = @import("logly");
const std = @import("std");

const Backend = struct {
    bytes: std.ArrayListUnmanaged(u8) = .empty,
    alloc: std.mem.Allocator,

    fn writer(data: []const u8, user_data: *anyopaque) anyerror!void {
        const self: *@This() = @ptrCast(@alignCast(user_data));
        try self.bytes.appendSlice(self.alloc, data);
    }
};

var backend: Backend = .{ .alloc = std.heap.page_allocator };
var custom: logly.CustomSink = .{
    .write_fn = Backend.writer,
    .user_data = @ptrCast(&backend),
    .name = "my-bridge",
};
defer custom.close();

try custom.write("[bridge] hello from a custom sink\n");
try custom.flush();
```

> [!TIP]
> `CustomSink` does not own `user_data`. Resource lifetime is the caller's responsibility; the optional `close_fn` is fired only when you call `custom.close()`.

## Optional Flush & Close

```zig
fn flushImpl(user_data: *anyopaque) anyerror!void {
    const self: *Backend = @ptrCast(@alignCast(user_data));
    // flush backend.bytes somewhere
}

fn closeImpl(user_data: *anyopaque) void {
    _ = user_data;
    // release backend-specific resources
}

var custom: logly.CustomSink = .{
    .write_fn = Backend.writer,
    .flush_fn = flushImpl,
    .close_fn = closeImpl,
    .user_data = @ptrCast(&backend),
    .name = "my-bridge",
};
```

> [!WARNING]
> `user_data` must point to memory that is alive for the lifetime of the `CustomSink`. The library performs no reference counting.

## Counting & Reset

`CustomSink` keeps two atomic counters:

- `custom.getBytesWritten()` / `custom.bytesSent` / `custom.totalBytes`
- `custom.getRecordsWritten()` / `custom.recordsSent` / `custom.totalRecords`

Call `custom.resetCounters()` (alias `custom.reset`) to zero both counters without touching the writer.

## Error Propagation

If your `write_fn` returns an error, `custom.write` returns the same error to the caller. The corresponding counter is **not** incremented on failure.

> [!CAUTION]
> When using `CustomSink` in a hot path, prefer to buffer the bytes in `write_fn` and flush in batches. The wrapper does not perform any batching or coalescing on your behalf.

## See Also

- [Sinks](sinks.md) — first-party sinks shipped with logly.
- [Sink formats](sink-formats.md) — first-party format options.
