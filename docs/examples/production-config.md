# Production Configuration Example

Enterprise-ready logging configurations for production environments.

## Configuration Presets

Logly provides built-in presets for common scenarios:

### Production Preset

```zig
const Config = logly.Config;

const logger = try logly.Logger.init(allocator);
defer logger.deinit();

const config = Config.production();
logger.configure(config);

// Applies:
// - Level: info
// - JSON format for log aggregation
// - Sampling: enabled at 10%
// - Metrics enabled
// - Structured logging
// - Colors disabled
```

### Development Preset

```zig
const config = Config.development();
logger.configure(config);

// Applies:
// - Level: debug (verbose)
// - Colored console output
// - Source location shown (function, filename, line number)
// - Debug mode enabled
```

### High Throughput Preset

```zig
const config = Config.highThroughput();
logger.configure(config);

// Applies:
// - Level: warning
// - Large buffer sizes (65KB)
// - Adaptive sampling at 50%
// - Rate limiting (10000/sec)
// - Optimized flush intervals
```

### Secure Preset

```zig
const config = Config.secure();
logger.configure(config);

// Applies:
// - Redaction enabled
// - Structured logging
// - No hostname/PID in output (privacy)
```

## Custom Production Configuration

```zig
const Config = logly.Config;

// Start with production preset and customize
var config = Config.production();

config.level = .info;           // Allow info logs
config.include_hostname = true;  // Include server hostname
config.include_pid = true;       // Include process ID
config.show_thread_id = true;    // Include thread ID
config.time_format = "iso8601";  // ISO timestamps

logger.configure(config);

// Add file sink
_ = try logger.addSink(.{
    .path = "logs/production.log",
    .json = true,
    .rotation = "daily",
    .retention = 30,  // Keep 30 rotated files
});
```

## Multi-Sink Architecture

```zig
var config = Config.default();
config.level = .debug;
logger.configure(config);

// Console: Colored warnings+ for monitoring
_ = try logger.addSink(.{
    .name = "console",
    .level = .warning,
    .color = true,
});

// Application log: All info+
_ = try logger.addSink(.{
    .name = "app-log",
    .path = "logs/app.log",
    .json = true,
    .level = .info,
    .rotation = "daily",
    .retention = 14,
});

// Error log: Errors only, longer retention
_ = try logger.addSink(.{
    .name = "error-log",
    .path = "logs/error.log",
    .json = true,
    .level = .err,
    .retention = 90,
});
```

## Environment-Specific Config

```zig
fn getConfig() logly.Config {
    const env = std.process.getEnvVarOwned(allocator, "ENVIRONMENT") 
                catch "development";
    defer if (env) |e| allocator.free(e);
    
    if (std.mem.eql(u8, env, "production")) {
        return logly.ConfigPresets.production();
    } else if (std.mem.eql(u8, env, "staging")) {
        var config = logly.ConfigPresets.production();
        config.level = .debug;  // More verbose in staging
        return config;
    } else {
        return logly.ConfigPresets.development();
    }
}
```

## Recommended Settings by Environment

| Setting | Development | Staging | Production |
|---------|-------------|---------|------------|
| Level | debug | debug | warning |
| Format | text | json | json |
| Colors | yes | no | no |
| Sampling | none | light | moderate |
| Rotation | none | daily | daily |
| Retention | 1 day | 7 days | 30+ days |

## Health Monitoring

```zig
const Metrics = logly.Metrics;

// Create metrics collector
var metrics = Metrics.init(allocator);
defer metrics.deinit();

// Record logs and check health
metrics.recordLog(.info, 100);
metrics.recordLog(.err, 50);

// Periodic health check
pub fn checkHealth(m: *Metrics) bool {
    const snapshot = m.getSnapshot();
    
    // Alert if error rate > 5%
    if (snapshot.total_records > 0) {
        const error_rate = @as(f64, @floatFromInt(snapshot.error_count)) / 
                          @as(f64, @floatFromInt(snapshot.total_records));
        return error_rate < 0.05;
    }
    
    return true;
}

// Get formatted metrics output
const formatted = try metrics.format(allocator);
defer allocator.free(formatted);
std.debug.print("{s}\n", .{formatted});
```

## Best Practices

1. **Use JSON in production** - Enables log aggregation tools
2. **Set appropriate levels** - Debug in dev, warning+ in prod
3. **Enable rotation** - Prevent disk space issues
4. **Add monitoring** - Track error rates and volumes
5. **Separate error logs** - Keep errors in dedicated files
6. **Use correlation IDs** - Link logs across services
7. **Test configuration** - Verify logs work as expected
