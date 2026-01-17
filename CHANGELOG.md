# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

> **Note:** Documentation for versions below 0.1.2 is not available. Please refer to commit history or pull requests for those versions.

---

## [0.1.5]

### Added

- **Zstd Compression Support**: High-performance Zstandard compression algorithm for log files.
  - New algorithm: `CompressionAlgorithm.zstd` with excellent compression ratios and very fast decompression.
  - Compression presets: `zstd()`, `zstdFast()`, `zstdBest()`, `zstdProduction()`.
  - Config builder methods: `withZstdCompression()`, `withZstdFastCompression()`, `withZstdBestCompression()`, `withZstdProductionCompression()`.
  - Compression factory methods: `Compression.zstdCompression()`, `Compression.zstdFast()`, `Compression.zstdBest()`, `Compression.zstdProduction()`.
  - `CompressionLevel.toZstdLevel()` method for mapping compression levels to zstd-specific levels (1-22).
  - Uses `.zst` file extension for zstd-compressed files.
  - Integrated via [zstd.zig](https://github.com/muhammad-fiaz/zstd.zig) wrapper for Facebook's zstd library.
- **Custom Zstd Levels**: Fine-grained control over zstd compression levels (1-22).
  - New field: `CompressionConfig.custom_zstd_level` for custom level specification.
  - New preset: `CompressionConfig.zstdWithLevel(level)` for custom level configs.
  - New factory: `Compression.zstdWithLevel(allocator, level)` for custom level compressors.
  - New method: `CompressionConfig.getEffectiveZstdLevel()` returns the effective zstd level.
- **Batch Compression Operations**: Compress multiple files in a single operation.
  - `Compression.compressBatch(file_paths)` - Compress multiple files at once.
  - `Compression.compressPattern(dir, pattern)` - Compress files matching a glob pattern (e.g., `*.log`).
  - `Compression.compressOldest(dir, count)` - Compress the N oldest files in a directory.
  - `Compression.compressLargerThan(dir, min_size)` - Compress files larger than a threshold.
- **Compression Utility Methods**: Additional helper methods for compression.
  - `Compression.estimateCompressedSize(data_size)` - Estimate compressed size for given data.
  - `Compression.getExtension()` - Get the file extension for the configured algorithm.
  - `Compression.isZstd()` - Check if using zstd algorithm.
  - `Compression.algorithmName()` - Get the algorithm name as a string.
  - `Compression.levelName()` - Get the compression level name as a string.
- **Enhanced Compression Aliases**: More convenient alias methods.
  - `Compression.packDirectory()` / `archiveFolder()` aliases for `compressDirectory()`.
  - `Compression.clearStats()` alias for `resetStats()`.
  - `Compression.setConfig()` / `updateConfig()` aliases for `configure()`.
- **OpenTelemetry Protocol (OTLP) Export**: Full OTLP JSON format support for span export.
  - `Telemetry.exportToOtlp()` - Export spans in OTLP-compatible format.
  - Proper `resourceSpans` structure with `scopeSpans` and full span attributes.
  - Compatible with OpenTelemetry Collector and OTLP receivers.
- **Provider-Specific Span Exporters**: Dedicated export methods for each telemetry provider.
  - `exportToJaeger()` - Jaeger Thrift format export.
  - `exportToZipkin()` - Zipkin JSON format export.
  - `exportToDatadog()` - Datadog APM format export.
  - `exportToGoogleCloud()` - Google Cloud Trace format.
  - `exportToGoogleAnalytics()` - GA4 Measurement Protocol format.
  - `exportToGoogleTagManager()` - GTM server-side format.
  - `exportToAwsXray()` - AWS X-Ray segment format.
  - `exportToAzure()` - Azure Application Insights envelope format.
- **Scheduler Compression Presets**: Pre-configured task configurations for common scenarios.
  - `SchedulerPresets.hourlyArchive(path)` - Compress files hourly after 1 day.
  - `SchedulerPresets.compressOnRotation(path)` - Compress files after rotation.
  - `SchedulerPresets.sizeBasedCompression(path, max_bytes)` - Compress when size exceeds threshold.
  - `SchedulerPresets.diskUsageTriggered(path, percent)` - Compress when disk usage is high.
  - `SchedulerPresets.lowDiskSpaceTriggered(path, min_free)` - Compress when disk space is low.
  - `SchedulerPresets.recursiveCompression(path, min_age_days)` - Recursive directory compression.
- **Additional Schedule Presets**: More scheduling convenience methods.
  - `SchedulerPresets.every15Minutes()` - Run every 15 minutes.
  - `SchedulerPresets.onceAfter(seconds)` - Run once after delay.
  - `SchedulerPresets.healthCheckSchedule()` - Standard health check interval (5 min).
  - `SchedulerPresets.metricsSchedule()` - Standard metrics collection interval (1 min).
- **Rotation Presets**: Comprehensive pre-configured rotation strategies for common use cases.
  - **Time-Based Presets**: `daily7Days()`, `daily30Days()`, `daily90Days()`, `daily365Days()`, `hourly24Hours()`, `hourly48Hours()`, `hourly7Days()`, `weekly4Weeks()`, `weekly12Weeks()`, `monthly12Months()`, `minutely60()`.
  - **Size-Based Presets**: `size1MB()`, `size5MB()`, `size10MB()`, `size25MB()`, `size50MB()`, `size100MB()`, `size250MB()`, `size500MB()`, `size1GB()`.
  - **Hybrid Presets**: `dailyOr100MB()`, `hourlyOr50MB()`, `dailyOr500MB()` - Rotate on time OR size.
  - **Production Presets**: `production()` (daily, 30 days, gzip), `enterprise()` (daily, 90 days, best compression, ISO naming), `debug()` (minutely, 60 files), `highVolume()` (hourly OR 500MB, 7 days), `audit()` (daily, 365 days, keep all archives), `minimal()` (10MB, 3 files, index naming).
  - **Sink Helpers**: `dailySink()`, `hourlySink()`, `weeklySink()`, `monthlySink()`, `sizeSink()`.
  - **Preset Aliases**: `daily`, `hourly`, `weekly`, `monthly` shortcuts.
- **Rotation Tests**: Added 10 new test cases for rotation presets, intervals, stats, and configuration methods.
- **Compression Aliases**: Convenient alias methods for common compression operations.
  - `Compression.create()` alias for `init()`, `Compression.destroy()` alias for `deinit()`.
  - `Compression.encode()` / `decode()` aliases for `compress()` / `decompress()`.
  - `Compression.deflate()` / `inflate()` aliases for `compress()` / `decompress()`.
  - `Compression.packFile()` / `unpackFile()` aliases for file operations.
  - `Compression.statistics()` alias for `getStats()`.
  - `Compression.needsCompression()` alias for `shouldCompress()`.
  - `Compression.zstdDefault()`, `zstdSpeed()`, `zstdMax()` preset aliases.
  - `CompressionConfig.zstdDefault()`, `zstdSpeed()`, `zstdMax()` config aliases.
- **Compression Callbacks**: Event hooks for monitoring compression operations.
  - `on_compression_start` callback before compression begins.
  - `on_compression_complete` callback after successful compression.
  - `on_compression_error` callback on compression failures.
  - `on_decompression_complete` callback after decompression.
  - `on_archive_deleted` callback when archived files are deleted.
  - Setter methods: `setCompressionStartCallback()`, `setCompressionCompleteCallback()`, etc.
- **Enhanced Color System**: Comprehensive ANSI color support with theme presets and individual level overrides.
- **Theme Presets**: Built-in color themes - `default`, `bright`, `dim`, `minimal`, `neon`, `pastel`, `dark`, `light`.
- **Per-Level Color Override**: Configure individual colors per log level while using a base theme via `Config.level_colors`.
- **Level Color Variants**: New methods on `Level` enum - `brightColor()`, `dimColor()`, `underlineColor()`, `color256()`.
- **Advanced CustomLevel**: Full color control with new constructors:
  - `initFull()` - All color variants (base, bright, dim, 256-color)
  - `initRgb()` - RGB color specification
  - `initStyled()` - With text style (bold, italic, underline)
  - `initWithBackground()` - With background color
- **Color Constants**: New `Constants.Colors` struct with comprehensive color definitions:
  - `Fg` - Standard foreground colors (30-37)
  - `BrightFg` - Bright foreground colors (90-97)
  - `Bg` - Background colors (40-47)
  - `BrightBg` - Bright background colors (100-107)
  - `Style` - Text styles (bold, dim, italic, underline, blink, reverse, strikethrough)
  - `LevelColors` - Predefined level color mappings
  - `Themes` - Theme preset definitions
- **RGB/256-Color Functions**: 
  - `Colors.fgRgb(r, g, b)` - RGB foreground color code
  - `Colors.bgRgb(r, g, b)` - RGB background color code
  - `Colors.fg256(index)` - 256-color palette foreground
  - `Colors.bg256(index)` - 256-color palette background
- **Config Theme Integration**: `LevelColorConfig.theme_preset` for global theme selection.
- **Theme/Override Combination**: Use theme as base with individual level overrides taking precedence.
- **ColorStyle Enum**: Formatter color style selection (`default`, `bright`, `dim`, `color256`, `minimal`, `neon`, `pastel`, `dark`, `light`).
- **Formatter Theme Presets**: `Theme.bright()`, `Theme.dim()`, `Theme.minimal()`, `Theme.neon()`, `Theme.pastel()`, `Theme.dark()`, `Theme.light()`.
- **CustomLevel Helper Methods**: `effectiveColor()`, `getBrightColor()`, `getDimColor()`, `get256Color()`, `hasRgbColor()`, `has256Color()`, `hasBackground()`, `hasStyle()`.
- **Comprehensive Compression Tests**: Test coverage for all algorithms (deflate, zlib, raw_deflate, gzip, zstd), levels, presets, aliases, callbacks, and statistics.

### Enhanced

- **LevelColorConfig**: Added `theme_preset`, `notice_color`, `fatal_color` fields and `getColorForLevel()` method.
- **Formatter.Theme**: Added `notice` and `fatal` fields for complete level coverage.
- **Telemetry Export**: Improved provider detection and format-specific export with proper JSON structures.
- **Documentation**: Updated compression, telemetry, and scheduler guides with v0.1.5 features.
- **Examples**: Updated `compression_demo.zig`, `scheduler_demo.zig`, and `telemetry.zig` with v0.1.5 features.

---

## [0.1.4]

### API Changes Summary

This section documents breaking changes and renamed APIs for migration:

| Module | Old API | New API / Change | Notes |
|--------|---------|------------------|-------|
| Stats Structs | `.field.load(.monotonic)` | `.getField()` | All stats structs now have getter methods (e.g., `stats.getExecuted()` instead of `stats.tasks_executed.load(.monotonic)`) |
| Telemetry | `Telemetry.Span` | `Span` | Use directly imported `Span` type |
| SchedulerStats | Direct atomic access | Getter methods | Use `getExecuted()`, `getFailed()`, `getFilesCleaned()`, etc. |
| CompressionStats | Direct atomic access | Getter methods | Use `getFilesCompressed()`, `getBytesBefore()`, `getBytesAfter()`, etc. |
| ThreadPoolStats | Direct atomic access | Getter methods | Use `getSubmitted()`, `getCompleted()`, `getDropped()`, `getStolen()` |
| AsyncStats | Direct atomic access | Getter methods | Use `getQueued()`, `getWritten()`, `getDropped()` |
| RulesStats | Direct atomic access | Getter methods | Use `getRulesEvaluated()`, `getRulesMatched()` |
| LoggerStats | Direct atomic access | Getter methods | Use `getTotalLogged()`, `getFiltered()`, `getSinkErrors()`, `getBytesWritten()`, `getActiveSinks()` |

### Added

- **OpenTelemetry Integration**: Full OpenTelemetry support with multiple providers (Jaeger, Zipkin, Datadog, Google Cloud, AWS X-Ray, Azure, and generic OTEL Collector).
- **Distributed Tracing**: Native span and trace management with W3C Trace Context propagation.
- **W3C Baggage Support**: Context propagation for arbitrary key-value pairs across service boundaries with `count()`, `isEmpty()`, `clear()`, `contains()` helper methods.
- **Metrics Export**: Comprehensive metrics collection and export in OTLP, Prometheus, and JSON formats.
- **Resource Detection**: Automatic system resource detection and custom resource configuration.
- **Span Processors**: Simple and batch span processors with configurable export settings.
- **Sampling Strategies**: Multiple sampling strategies (always-on, always-off, trace-id-ratio, parent-based).
- **Telemetry Callbacks**: Custom callbacks for span lifecycle and metric recording events.
- **Service Identity**: Automatic service name, version, environment, and datacenter tracking.
- **File Exporter**: JSONL-based file exporter for development and testing.
- **Custom Exporters**: Plugin architecture for custom exporter implementations with callback function interface.
- **Google Analytics 4 Provider**: GA4 Measurement Protocol integration for analytics tracking.
- **Google Tag Manager Provider**: Server-side GTM container integration.
- **Exporter Statistics**: Real-time monitoring of export performance with atomic counters (`ExporterStats`).
- **Network Integration**: UDP/TCP transport for span export via `network.zig` module.
- **Utils Integration**: Leverages `utils.zig` for ID generation, time calculations, JSON escaping, and error rate calculations.
- **Update Checker Control**: `setEnabled(bool)` function to globally enable/disable update checks project-wide.
- **Runtime Telemetry Control**: `setEnabled()`, `isEnabled()`, `getResource()`, `setResource()`, `resetStats()` for runtime configuration.
- **Distributed Trace Continuation**: `startSpanFromTraceparent()` to create spans from incoming W3C traceparent headers.
- **Span Lookup**: `findSpanByTraceId()` to find active spans for trace continuation.

**Metrics Module Enhancements**:
- **Callback Setters**: `setRecordLoggedCallback()`, `setSnapshotCallback()`, `setThresholdCallback()`, `setErrorCallback()` for event-driven metrics monitoring.
- **Configuration Access**: `getConfig()`, `isEnabled()` for runtime configuration inspection.
- **Sink Flush Tracking**: `recordSinkFlush()` for tracking flush operations.
- **Sink Lookup**: `getSinkMetrics()`, `getSinkMetricsByName()` for retrieving sink-specific metrics.
- **State Helpers**: `hasErrors()`, `hasDropped()`, `bytesPerSecond()` for convenient state checking.

**Record Module Enhancements**:
- **ID Setters**: `setParentSpanId()`, `setRequestId()`, `setSessionId()`, `setUserId()` for complete tracing context.
- **State Queries**: `hasParentSpan()`, `hasRequestId()`, `hasSessionId()`, `hasUserId()` for checking field presence.
- **Aliases**: `parentSpan`, `request`, `session`, `user` convenience aliases.

**Sampler Module Enhancements**:
- **SamplerStats Helpers**: `getRejectRate()`, `hasRejections()`, `hasRateLimitExceeded()`, `getRateLimitExceededRate()`, `getTotal()`, `getAccepted()`, `getRejected()` for comprehensive sampling statistics.

**Filter Module Enhancements**:
- **FilterStats Helpers**: `denyRate()`, `hasDenied()`, `hasEvaluationErrors()`, `getTotal()`, `getAllowed()`, `getDenied()`, `getRulesAdded()` for comprehensive filter statistics.

**Logger Module Enhancements**:
- **LoggerStats Helpers**: `sinkErrorRate()`, `hasFiltered()`, `hasSinkErrors()`, `getTotalLogged()`, `getFiltered()`, `getSinkErrors()`, `getBytesWritten()`, `bytesPerSecond()` for comprehensive logger statistics.

**Scheduler Module Enhancements**:
- **SchedulerStats Atomic Counters**: Thread-safe statistics using `Constants.AtomicUnsigned` for cross-platform 32/64-bit support.
- **New Stats Fields**: Added `files_compressed`, `bytes_saved`, `start_time` for comprehensive tracking.
- **SchedulerStats Helpers**: `successRate()`, `failureRate()`, `hasFailures()`, `getExecuted()`, `getFailed()`, `getFilesCleaned()`, `getFilesCompressed()`, `getBytesFreed()`, `getBytesSaved()`, `uptimeSeconds()`, `tasksPerHour()`, `compressionRatio()` for convenient statistics access.
- **Telemetry Integration**: Optional telemetry support with `setTelemetry()` and `clearTelemetry()` methods. Task executions create spans with task-specific attributes (`task.type`, `task.priority`, `task.duration_ms`, cleanup/compression stats).
- **Task Execution Tracing**: Automatic span creation for each task with error status tracking.
- **Telemetry Metrics**: Records `scheduler.tasks_executed` counter and `scheduler.task_duration_ms` gauge metrics.

**Cross-Platform Compatibility**:
- All atomic counters across `Sampler`, `Filter`, `Logger`, and `Scheduler` modules now use `Constants.AtomicUnsigned` for proper 32-bit and 64-bit architecture support.

- **TelemetryConfig Factory Functions**: Added preset configurations for all providers (`jaeger()`, `zipkin()`, `datadog()`, `googleCloud()`, `googleAnalytics()`, `googleTagManager()`, `awsXray()`, `azure()`, `otelCollector()`, `file()`, `custom()`, `highThroughput()`, `development()`).

### Fixed

- Improved thread safety for span and metric operations with mutex protection.

### Enhanced

**Stats Helper Methods Enhancement** - Comprehensive enhancement of all Stats structs with consistent getter methods, boolean checks, rate calculations, and reset functionality using Utils module for efficient code reuse.

**AsyncStats Enhancements**:
- Added getter methods: `getQueued()`, `getWritten()`, `getDropped()`, `getFlushCount()`, `getMaxQueueDepth()`, `getBufferOverflows()`
- Added boolean checks: `hasDropped()`, `hasOverflows()`
- Added rate calculations: `successRate()`, `throughputRecordsPerSecond()`, `averageLatencyMs()`
- Added `reset()` method for statistics reset
- Added Utils import for consistent atomic load operations

**ThreadPoolStats Enhancements**:
- Added getter methods: `getSubmitted()`, `getCompleted()`, `getDropped()`, `getStolen()`, `getTotalWaitTimeNs()`, `getTotalExecTimeNs()`, `getActiveThreads()`
- Added boolean checks: `hasSubmitted()`, `hasCompleted()`, `hasDropped()`, `hasStolen()`
- Added rate calculations: `completionRate()`, `dropRate()`, `stealRate()`, `avgWaitTimeMs()`, `avgExecTimeMs()`
- Added `reset()` method for statistics reset
- Added Utils import for consistent atomic load operations

**RotationStats Enhancements**:
- Added getter methods: `getTotalRotations()`, `getFilesArchived()`, `getFilesDeleted()`, `getRotationErrors()`, `getCompressionErrors()`, `getTotalErrors()`
- Added boolean checks: `hasRotated()`, `hasErrors()`, `hasCompressionErrors()`, `hasArchived()`
- Added rate calculations: `successRate()`, `errorRate()`, `totalErrorRate()`, `archiveRate()`
- Added `reset()` method for statistics reset

**CompressionStats Enhancements**:
- Added getter methods: `getFilesCompressed()`, `getFilesDecompressed()`, `getBytesBefore()`, `getBytesAfter()`, `getBytesSaved()`, `getCompressionErrors()`, `getDecompressionErrors()`, `getTotalErrors()`, `getBackgroundTasksQueued()`, `getBackgroundTasksCompleted()`, `getTotalOperations()`
- Added boolean checks: `hasOperations()`, `hasErrors()`, `hasCompressionErrors()`, `hasDecompressionErrors()`, `hasPendingBackgroundTasks()`
- Added rate calculations: `successRate()`, `backgroundTaskCompletionRate()`, `avgBytesPerOperation()`
- Added `reset()` method for statistics reset

**NetworkStats Enhancements**:
- Added getter methods: `getBytesSent()`, `getBytesReceived()`, `getConnectionsOpened()`, `getConnectionsClosed()`, `getConnectionErrors()`, `getSendErrors()`, `getReceiveErrors()`
- Added aggregate methods: `totalBytesReceived()`, `totalConnectionsMade()`, `totalErrors()`, `totalBytesTransferred()`
- Added boolean checks: `hasErrors()`, `hasConnections()`
- Added rate calculations: `avgBytesPerMessage()`

**SinkStats Enhancements**:
- Added getter methods: `getTotalWritten()`, `getBytesWritten()`, `getWriteErrors()`, `getFlushCount()`, `getRotationCount()`
- Added boolean checks: `hasWritten()`, `hasErrors()`, `hasFlushed()`, `hasRotated()`
- Added rate calculations: `throughputRecordsPerSecond()`, `successRate()`, `avgFlushesPerRotation()`
- Added `reset()` method for statistics reset

**FormatterStats Enhancements**:
- Added getter methods: `getTotalFormatted()`, `getJsonFormats()`, `getCustomFormats()`, `getFormatErrors()`, `getTotalBytesFormatted()`, `getPlainFormats()`
- Added boolean checks: `hasFormatted()`, `hasJsonFormats()`, `hasCustomFormats()`, `hasErrors()`
- Added rate calculations: `jsonUsageRate()`, `customUsageRate()`, `successRate()`, `throughputBytesPerSecond()`
- Added `reset()` method for statistics reset

**RulesStats Enhancements**:
- Added getter methods: `getRulesEvaluated()`, `getRulesMatched()`, `getMessagesEmitted()`, `getEvaluationsSkipped()`
- Added boolean checks: `hasEvaluated()`, `hasMatched()`, `hasEmitted()`, `hasSkipped()`
- Added rate calculations: `skipRate()`, `avgMessagesPerMatch()`, `efficiencyRate()`
- Updated `matchRate()` to use Utils helpers

**RedactorStats Enhancements**:
- Added getter methods: `getTotalProcessed()`, `getValuesRedacted()`, `getPatternsMatched()`, `getFieldsRedacted()`, `getRedactionErrors()`
- Added boolean checks: `hasProcessed()`, `hasRedacted()`, `hasMatchedPatterns()`, `hasErrors()`
- Added rate calculations: `successRate()`, `patternMatchRate()`, `avgRedactionsPerValue()`
- Added `reset()` method for statistics reset

**ExporterStats Enhancements** (Telemetry):
- Added recording method: `recordMetricExport()`
- Added getter methods: `getMetricsExported()`, `getBatchExports()`, `getNetworkExports()`, `getLastExportTimeNs()`, `getTotalExports()`
- Added boolean checks: `hasExportedSpans()`, `hasExportedMetrics()`, `hasErrors()`, `hasBatchExports()`, `hasNetworkExports()`
- Added rate calculations: `getSuccessRate()`, `avgSpansPerBatch()`, `avgBytesPerSpan()`, `throughputBytesPerSecond()`
- Added `reset()` method for statistics reset

**SinkMetrics Enhancements** (Metrics module):
- Added getter methods: `getRecordsWritten()`, `getBytesWritten()`, `getWriteErrors()`, `getFlushCount()`
- Added boolean checks: `hasWritten()`, `hasErrors()`
- Added rate calculations: `getSuccessRate()`, `avgBytesPerRecord()`, `avgRecordsPerFlush()`, `throughputBytesPerSecond()`
- Added `reset()` method for statistics reset

### Documentation Updates

- Updated [async.md](docs/api/async.md) with comprehensive AsyncStats helper method documentation
- Updated [sink.md](docs/api/sink.md) with SinkStats helper method documentation
- Updated [formatter.md](docs/api/formatter.md) with FormatterStats helper method documentation
- Updated [thread-pool.md](docs/api/thread-pool.md) with ThreadPoolStats helper method documentation
- Updated [compression.md](docs/api/compression.md) with CompressionStats helper method documentation
- Updated [network.md](docs/api/network.md) with NetworkStats helper method documentation
- Updated [rotation.md](docs/api/rotation.md) with RotationStats helper method documentation
- Updated [rules.md](docs/api/rules.md) with RulesStats helper method documentation
- Updated [redactor.md](docs/api/redactor.md) with RedactorStats helper method documentation
- Updated [telemetry.md](docs/api/telemetry.md) with ExporterStats helper method documentation
- Updated [metrics.md](docs/api/metrics.md) with SinkMetrics helper method documentation


---

## [0.1.3]

### Changed

- **Code Optimization**: Consolidated common utility functions in `utils.zig` for better code reuse.
- **Refactored Statistics**: Shared utility functions for error rate, average, and throughput calculations across all modules.

### Improved

- **Documentation**: Enhanced docstrings for Filter, Formatter, Sink, Compression, Rotation, Sampler, Scheduler, ThreadPool, Network, Metrics, Diagnostics, Rules, and Redactor modules for `zig build docs` generation.

---

## [0.1.2]

### Added

- **File Name Customization**: Full control over compressed/rotated file names (`file_prefix`, `file_suffix`, `naming_pattern`).
- **Archive Root Directory**: Centralized folder support for all compressed files with optional date-based subdirectories.
- **Compression Presets**: Added `enable()`, `implicit()`, `fast()`, `balanced()`, `best()`, `production()`, and more.
- **Enhanced Scheduler**: 12 new options including compression algorithm/level, archive paths, and concurrent limits.
- **Enhanced Rotation**: Added archive root, compression during retention, and file prefixes/suffixes.

### Improved

- **Documentation**: New file customization guide, updated API references, and additional examples.

---

## Earlier Versions

Documentation for versions prior to 0.1.2 is not available in this changelog. 
For historical changes, please refer to:
- [Commit History](https://github.com/muhammad-fiaz/logly.zig/commits/main)
- [Pull Requests](https://github.com/muhammad-fiaz/logly.zig/pulls?q=is%3Apr+is%3Aclosed)

