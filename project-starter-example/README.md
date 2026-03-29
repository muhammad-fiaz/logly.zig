# Logly Starter Example

A starter project demonstrating the **[Logly](https://github.com/muhammad-fiaz/logly.zig)** logging library for Zig.

## 📥 Download

**[⬇️ Download this starter template](https://github.com/muhammad-fiaz/logly.zig/releases/latest/download/project-starter-example.zip)**

Or clone the repository:
```bash
git clone https://github.com/muhammad-fiaz/logly.zig.git
cd logly.zig/project-starter-example
```

## Quick Start

```bash
# Build
zig build

# Run
zig build run
```

## Allocator Defaults

This starter uses `std.heap.GeneralPurposeAllocator` as the base allocator.

- Default logger behavior uses the allocator passed to `Logger.init(...)`.
- Arena scratch allocation is optional and controlled by `Config.use_arena_allocator`.

Equivalent arena enablement styles:

```zig
var config = logly.Config.default();
config.use_arena_allocator = true;

// or
config = config.withArenaAllocator();
```

Both forms enable the same logger behavior. The field form mutates in place, while the builder form returns a modified copy.

## Project Structure

```
logly-starter-example/
├── build.zig
├── build.zig.zon
├── README.md
├── LICENSE
├── src/
│   └── main.zig
└── logs/           (generated)
    ├── app.log
    ├── app.json
    ├── daily.log
    ├── size_rotated.log
    └── errors.log
```

## Learn More

- [Logly Documentation](https://muhammad-fiaz.github.io/logly.zig)
- [Logly GitHub](https://github.com/muhammad-fiaz/logly.zig)

## License

MIT License
