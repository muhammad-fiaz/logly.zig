# Utils API

The `utils` module contains shared utility functions used internally by Logly.

## Functions

### `parseSize`

Parses a size string (e.g., "10MB", "5GB") into bytes.

```zig
pub fn parseSize(s: []const u8) ?u64
```

**Parameters:**
- `s`: Size string to parse (e.g., "10MB", "1KB", "500B")

**Returns:**
- The size in bytes, or `null` if parsing fails

**Supported Units:**
| Unit | Description | Multiplier |
|------|-------------|------------|
| `B` | Bytes | 1 |
| `KB` / `K` | Kilobytes | 1024 |
| `MB` / `M` | Megabytes | 1024² |
| `GB` / `G` | Gigabytes | 1024³ |
| `TB` / `T` | Terabytes | 1024⁴ |

All units are **case-insensitive**.

**Examples:**

```zig
const Utils = @import("logly").Utils;

// Parse various size formats
const size1 = Utils.parseSize("1024");     // 1024 bytes
const size2 = Utils.parseSize("1KB");      // 1024 bytes  
const size3 = Utils.parseSize("10MB");     // 10 * 1024 * 1024 bytes
const size4 = Utils.parseSize("5G");       // 5 * 1024³ bytes
const size5 = Utils.parseSize("100 MB");   // Whitespace allowed
const size6 = Utils.parseSize("invalid");  // null
```

## Usage in Configuration

Size parsing is used internally by:
- `SinkConfig.size_limit_str` - For setting rotation size limits
- `RotationConfig.size_limit_str` - For global rotation configuration

```zig
var config = SinkConfig.default();
config.path = "logs/app.log";
config.size_limit_str = "50MB";  // Parsed internally using Utils.parseSize
```
