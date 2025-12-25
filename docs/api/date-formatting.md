# Date Formatting API

The `date_formatting` module provides shared date/time formatting utilities for custom naming patterns.

## Functions

### `format`

Formats a date/time string based on a format pattern using granular tokens.

```zig
pub fn format(
    writer: anytype,
    fmt: []const u8,
    year: i32,
    month: u8,
    day: u8,
    hour: u64,
    minute: u64,
    second: u64
) !void
```

**Parameters:**
- `writer`: Any writer that implements the standard Zig writer interface
- `fmt`: Format pattern string containing tokens
- `year`: 4-digit year (e.g., 2025)
- `month`: Month number (1-12)
- `day`: Day of month (1-31)
- `hour`: Hour (0-23)
- `minute`: Minute (0-59)
- `second`: Second (0-59)

## Supported Tokens

| Token | Description | Example Output |
|-------|-------------|----------------|
| `YYYY` | 4-digit year | `2025` |
| `YY` | 2-digit year | `25` |
| `MM` | 2-digit month (zero-padded) | `01`, `12` |
| `M` | Month (no padding) | `1`, `12` |
| `DD` | 2-digit day (zero-padded) | `05`, `25` |
| `D` | Day (no padding) | `5`, `25` |
| `HH` | 2-digit hour (zero-padded) | `08`, `23` |
| `H` | Hour (no padding) | `8`, `23` |
| `mm` | 2-digit minute (zero-padded) | `05`, `45` |
| `m` | Minute (no padding) | `5`, `45` |
| `ss` | 2-digit second (zero-padded) | `03`, `59` |
| `s` | Second (no padding) | `3`, `59` |

Any characters not matching these tokens are passed through literally (e.g., `-`, `/`, `_`, `.`).

## Usage Examples

### Custom Rotation Naming

```zig
const Rotation = @import("logly").Rotation;

var rotation = try Rotation.init(allocator, "logs/app.log", .daily, null, 7);
rotation.withNamingFormat("{base}_{YYYY}-{MM}-{DD}{ext}");
// Produces: app_2025-12-25.log
```

### Custom Path Patterns

```zig
var config = SinkConfig.default();
config.path = "logs/{YYYY}/{MM}/app-{DD}.log";
// Creates dynamic paths like: logs/2025/12/app-25.log
```

### Flexible Date Separators

```zig
// Using slashes
"{YYYY}/{MM}/{DD}"  // -> 2025/12/25

// Using dots
"{YYYY}.{MM}.{DD}"  // -> 2025.12.25

// Mixed format with time
"{YYYY}-{MM}-{DD}T{HH}:{mm}:{ss}"  // -> 2025-12-25T14:30:45

// Compact format
"{YYYYMMDD}_{HH}{mm}"  // -> 20251225_1430
```

## Internal Usage

This module is used by:
- `Rotation.generateRotatedPath()` - For custom naming strategies
- `Sink.resolvePath()` - For dynamic path patterns
