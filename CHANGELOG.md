# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

> **Note:** Documentation for versions below 0.1.2 is not available. Please refer to commit history or pull requests for those versions.

## [0.1.7]

### Added

- **Custom Timezone Placeholders in `time_format`**:
  - `ZZZ` for timezone offsets in `+HH:MM` format.
  - `ZZ` for compact timezone offsets in `+HHMM` format.
- **Centralized Time Format Constants**:
  - Added `Config.TimeFormat` constants (`default_pattern`, `default_alias`, `iso8601`, `rfc3339`, `unix`, `unix_ms`) to avoid string-literal drift in production code.
- **Timezone-Aware Pattern Formatting Utilities**:
  - Added `Utils.formatDatePatternWithOffset(...)` and `Utils.formatDateToBufWithOffset(...)`.
  - Added `Utils.writeUtcOffsetCompact(...)` for reusable compact offset formatting.
- **W3C Trace Context Logger Helpers**:
  - Added `Logger.setTraceContextFromTraceparent(...)` for safe trace context ingestion from incoming headers.
  - Added `Logger.withTraceparent(...)` and `Logger.getTraceparentHeader(...)` for request-scoped propagation.
  - Added `DistributedLogger.child(...)` and `DistributedLogger.inModule(...)` helpers for nested spans and module-scoped tracing.
- **Sink Reliability & Observability Enhancements**:
  - Centralized sink write/flush error handling through configured `SinkConfig.on_error` behavior.
  - Added buffered record accounting in sink internals to improve flush statistics accuracy.
  - Added retry-aware TCP reconnect behavior using centralized `Constants.TimeDefaults` retry settings.
- **Allocator Ergonomics Improvements**:
  - Added `Config.withArenaAllocator()` and `Config.withArena()` aliases for clearer arena configuration in production code.
  - Refactored logger initialization paths to reuse shared setup internals and improve consistency.
  - Added explicit test coverage for `Logger` initialization with `GeneralPurposeAllocator`.
  - Added allocator strategy example (`examples/allocator_strategies.zig`) and matching docs page (`docs/examples/allocator-strategies.md`).
- **Metrics Observability Extensions**:
  - Added latency percentile helpers: `latencyPercentileNs(...)` and `latencyPercentileMs(...)`.
  - Added `getLatencySummary()` with `min`, `max`, `avg`, `p50`, `p95`, `p99`, and sample count.
  - Added sink aggregate helpers: `totalSinkErrors()` and `totalSinkFlushes()`.
  - Added `lastRecordAgeMs()` to track time since most recent recorded log.
- **Async Queue Control Extensions**:
  - Added queue capacity helpers: `availableCapacity()`, `queueUtilization()`, and `isNearCapacity(...)`.
  - Added bounded drain wait helper: `waitUntilDrained(timeout_ms)`.
  - Added `AsyncStats.inFlight()` for queued-but-not-yet-written record tracking.
- **Thread Pool Capacity Extensions**:
  - Added queue metrics helpers: `queueCapacity()`, `availableQueueCapacity()`, `queueUtilization()`, and `isSaturated(...)`.
  - Added bounded completion wait helper: `waitAllTimeout(timeout_ms)`.
- **Rotation Decision Extensions**:
  - Added `RotationReason` enum (`interval`, `size`, `interval_and_size`).
  - Added rotation introspection helpers: `getRotationReason(...)`, `shouldRotate(...)`, and `nextRotationInSeconds()`.
  - Added `previewNextPath()` for pre-rotation path planning without mutating state.
- **Redactor Rule Management Extensions**:
  - Added `addFields(...)` for batch field registration.
  - Added preflight helpers: `wouldRedact(...)` and `hasFieldRule(...)`.
  - Added `previewFieldRedaction(...)` for non-mutating redaction previews.
- **Sampler, Scheduler, and Rules Operational Controls**:
  - Sampler: added structured sampling decisions (`shouldSampleWithReason(...)`), runtime strategy switching (`setStrategy(...)`), and rate-limit introspection (`remainingWindowQuota(...)`, `windowResetInMs(...)`).
  - Scheduler: added task introspection/count helpers, schedule update helpers (`setTaskSchedule(...)`, `rescheduleNow(...)`), and richer tick callback readiness reporting.
  - Rules: added bulk enable/disable and name-based removal helpers, non-mutating match preview APIs (`wouldMatchAny(...)`, `matchingRuleIds(...)`), priority sorting helper (`sortByPriority(...)`), and `max_messages_per_rule` enforcement during evaluation.
- **Additional Redactor, Rules, and Formatter Enhancements**:
  - Redactor: added batch pattern registration (`addPatterns(...)`), field and pattern removal helpers (`removeField(...)`, `removePatternByName(...)`), message-level preview APIs (`previewRedaction(...)`, `previewRedactionWithAllocator(...)`), and matching pattern count helper (`matchingPatternCount(...)`).
  - Rules: added non-mutating match count and first-match preview helpers (`matchingRuleCount(...)`, `firstMatchingRuleId(...)`), per-rule priority update API (`setRulePriority(...)`), and disabled-rule pruning helper (`removeDisabledRules(...)`).
  - Formatter: added timestamp-only formatting APIs (`formatTimestamp(...)`, `formatTimestampWithAllocator(...)`) and centralized JSON timestamp value rendering for consistent numeric/text timestamp handling.
- **Rotation, Sampler, Thread Pool, Scheduler, and Telemetry Explicit Controls**:
  - Rotation: added direct control helpers for interval/size/retention (`setInterval(...)`, `setIntervalFromString(...)`, `setSizeLimit(...)`, `setRetentionCount(...)`, `setRetentionPolicy(...)`) and manual trigger API (`forceRotate(...)`).
  - Sampler: added direct runtime strategy setters (`setProbability(...)`, `setRateLimit(...)`, `setEveryN(...)`, `setAdaptive(...)`) plus fast disable helper (`disableSampling(...)`).
  - Thread Pool: added retry-aware batch submission (`submitBatchWithRetry(...)`), queue breakdown snapshot (`pendingTasksByQueue(...)`), capacity check (`canAcceptTasks(...)`), and threshold wait (`waitUntilQueueBelow(...)`).
  - Scheduler: added immutable task snapshots (`getTaskSnapshot(...)`, `getTaskSnapshotByName(...)`) and name-based controls (`setTaskEnabledByName(...)`, `removeTaskByName(...)`, `nextRunInMsByName(...)`, `runNowByName(...)`).
  - Telemetry: added runtime sampling/header controls (`setSampling(...)`, `setContextHeaders(...)`), pending-state helpers, metric batch recording (`recordMetricsBatch(...)`), and span batch attribute setter (`Span.setAttributes(...)`).

### Fixed

- **Timezone Local Formatting (#29)**: `Config.timezone = .local` now formats timestamps using the process/system local timezone when libc localtime support is available.
- **ISO8601/RFC3339 Timezone Suffixes**: `ISO8601` and `RFC3339` timestamp output now emits timezone-aware suffixes (`Z` for UTC, `+/-HH:MM` for local).
- **Cross-Platform Fallback Safety**: On targets where localtime APIs are unavailable, formatting safely falls back to UTC behavior.
- **Default Time Format Alias**: `time_format = "default"` now resolves to the canonical default pattern (`YYYY-MM-DD HH:mm:ss.SSS`) instead of being treated as a custom literal pattern.
- **JSON Numeric Timestamp Consistency**: `unix` and `unix_ms` formats now always emit numeric JSON values (not quoted strings).
- **Sink Error Policy Consistency**: Sink write and flush failures now consistently apply `.silent`, `.log_stderr`, `.disable_sink`, and `.propagate` behavior.
- **Sink Flush Statistics**: Async and manual flush paths now update `SinkStats` counters consistently for records, bytes, and flush count.
- **Arena Reset Threshold Enforcement**: `Config.arena_reset_threshold` is now actively enforced by logger arena scratch allocation logic between records.
- **Telemetry Baggage Replacement Safety**: `Baggage.set(...)` now frees replaced key/value entries when updating existing baggage keys.
- **Sampling Rate Normalization Safety**: Runtime sampling updates now handle `NaN` input defensively and normalize through shared clamp utilities.

### Changed

- Bumped project version to `0.1.7` in package/runtime metadata and documentation.
- Updated installation and quick-start fetch URLs to `tags/0.1.7.tar.gz`.
- Replaced timestamp/time-offset magic values in time utilities with centralized `Constants.TimeConstants` values.
- Clarified allocator docs/examples to preserve explicit `config.use_arena_allocator = true` usage and document mutation-vs-builder behavior for `withArenaAllocation()` aliases.
- Updated architecture-sized constants (`AtomicUnsigned`, `AtomicSigned`, `NativeUint`, `NativeInt`) to derive from pointer width for consistent 32-bit/64-bit target behavior.
- Centralized distributed tracing header defaults under `Constants.ConfigDefaults` and reused them across `Config`/`DistributedConfig` defaults.

### Tests

- Added formatter tests to validate UTC vs local ISO8601 timezone suffix behavior.
- Added utility tests for local timestamp conversion validity and UTC offset bounds.
- Added formatter regression coverage for `Config.TimeFormat.default_alias` and strict numeric `unix_ms` JSON output.
- Added logger tests for traceparent parsing/propagation helper methods and distributed logger child/module helpers.
- Added sink tests for flush stats correctness, error behavior (`disable_sink` / `propagate`), and manual `flushNow()` flow.
- Added logger tests validating arena threshold reset behavior and `GeneralPurposeAllocator` compatibility.
- Added regression tests for new metrics percentile/summary helpers and sink aggregate helpers.
- Added regression tests for async in-flight stats and queue drain/utilization helpers.
- Added regression tests for thread pool queue capacity/load helpers and timeout waits.
- Added regression tests for rotation reason detection, preview path generation, and interval countdown.
- Added regression tests for redactor batch field registration and redaction preflight/preview helpers.
- Added regression tests for sampler decision/reason payloads and runtime strategy/quota helpers.
- Added regression tests for scheduler introspection and schedule tick callback readiness totals.
- Added regression tests for rules bulk enable/disable counts, non-mutating match previews, priority sorting, and max message cap enforcement.
- Added deterministic heavy-concurrency stress tests for rules and thread pool behavior under multi-thread contention.
- Added regression tests for redactor batch pattern management/removal and non-mutating message preview behavior.
- Added regression tests for rules match-count/first-match helpers, priority updates, and disabled-rule pruning.
- Added formatter regression tests for standalone timestamp helper APIs.
- Added regression tests for explicit rotation control setters and forced-rotation behavior.
- Added regression tests for sampler direct strategy control helpers.
- Added regression tests for thread pool retry-batch submission and queue-threshold waiting helpers.
- Added regression tests for scheduler name-based controls and immutable task snapshots.
- Added regression tests for telemetry sampling/header controls, metric batch recording, pending-state helpers, and span batch attributes.
- Added regression test coverage for baggage key replacement updates.

## [0.1.6]

### Added

- **Full Compression Algorithm Support**: Complete compression and decompression for all algorithms:
  - **LZMA** (`Compression.lzmaCompression()`, `CompressionConfig.lzma()`) - High-ratio compression
  - **LZMA2** (`Compression.lzma2Compression()`, `CompressionConfig.lzma2()`) - Multi-block LZMA
  - **XZ** (`Compression.xzCompression()`, `CompressionConfig.xz()`) - XZ container format
  - **ZIP** (`Compression.zipCompression()`, `CompressionConfig.zip()`) - ZIP archive with deflate
  - **TAR.GZ** (`Compression.tarGzCompression()`, `CompressionConfig.tarGz()`) - Tar archive + gzip
  - **LZ4** (`Compression.lz4Compression()`, `CompressionConfig.lz4()`) - Fast compression

- **Expanded Compression Archiving**: Support for multiple log archiving formats:
  - Added `zip`, `tar.gz`, `xz`, `lzma`, `lzma2`, and `lz4` to `CompressionAlgorithm`
  - Centralized extension mapping in `Constants.CompressionConstants.ArchivingExtensions`
  - Added `Utils.getCompressionExtension()` helper function for consistent extension use
  - Added new factory methods in `Config` and `Compression` for all supported formats
  - Refactored `uniqueCompressedPath` and `CompressionConfig` to use centralized constants

- **Comprehensive Compression Tests**: 12 new test cases for v0.1.6 algorithms:
  - Individual roundtrip tests for lzma, lzma2, xz, zip, tar.gz, lz4
  - Empty data handling, large data compression, checksum verification
  - Factory method tests, config preset tests, stats tracking tests

### Fixed

- **Critical Performance Regression Fix**: Restored performance to v0.1.4 levels (~13x improvement)
  - Changed `auto_flush` default from `true` to `false`. Flushing after every log operation was the primary cause of the massive performance degradation in v0.1.5
  - Changed `enable_callbacks` default from `true` to `false`. Callback checks on every log are unnecessary overhead when callbacks aren't used
  - Optimized context copying in hot path: Skip HashMap iteration when context is empty (fast path optimization)
- **Telemetry Fix**: Fixed a compile-time issue in the Telemetry module (OTLP exporter) by removing an unnecessary discard of the `self` parameter in `writeOtlpSpan`, ensuring the telemetry feature compiles and functions correctly.
- ⚠️ **Note:** The `true` default caused a significant performance regression (~13x slower in v0.1.5). Fixed in v0.1.6 by changing default to `false`

### Changed

- **Performance-First Defaults**: Default configuration now prioritizes performance:
  - `auto_flush: bool = false` - Set to `true` only when immediate output visibility is critical
  - `enable_callbacks: bool = false` - Enable only when using log callbacks

### Performance & Core Improvements

- **Centralized Constants**: Added new `Constants.TimeDefaults` and `Constants.Limits` structs:
  - `TimeDefaults.flush_interval_ms`, `write_timeout_ms`, `connection_timeout_ms`, `retry_delay_ms`, `max_retries`
  - `Limits.max_async_queue_size`, `max_pending_records`, `max_sinks`, `max_custom_levels`
- **Config Reuses Constants**: `Config.BufferConfig` now uses `Constants.BufferSizes.format`, `Constants.TimeDefaults.flush_interval_ms`, and `Constants.Limits.max_async_queue_size` for consistent defaults
- **Color Themes Use Constants**: `Config.LevelColorConfig.getColorForLevel()` now uses `Constants.Colors.Themes` (pastel, dark, light) instead of hardcoded ANSI codes
- **Architecture-Aware Types**: `Constants.AtomicUnsigned`, `AtomicSigned`, `NativeUint`, `NativeInt` provide optimal types for 32-bit (x86, ARM) and 64-bit (x86_64, aarch64, riscv64) architectures

### Refactored

- **Internal Architecture Overhaul**: Refactored core modules (`constants.zig`, `utils.zig`, `redactor.zig`, `compression.zig`, `config.zig`) for better consistency, code reuse, and maintainability.
- **Utils Module Expansion**: Added `maskString`, `replaceString`, and `computeRedactionHash` utilities to centralize string manipulation logic.
- **Redactor Optimization**: Migrated `Redactor` to use the new optimized `Utils` functions, significantly reducing code duplication and memory overhead.
- **Compression Enhancements**: Optimized `compressZstdWithAllocator` to perform direct buffer compression, reducing intermediate allocations.
- **Documentation Standardization**: Extensive updates to API documentation (`constants.md`, `utils.md`) to reflect the new architecture and fix formatting issues.

## [0.1.5]

### Added

- **ThreadPool Presets**: New preset configurations for optimized workloads.
  
- `ThreadPoolPresets.ioBound()` - Optimized for disk/network I/O workloads with 2x CPU cores.
  - `ThreadPoolPresets.cpuBound()` - Optimized for compute-heavy tasks using exact CPU core count.
  - All presets now use `Constants.ThreadDefaults` for consistent configuration values.
- **ThreadPool Constants Integration**: Centralized configuration reuse from `Constants.ThreadDefaults`.
  - `thread_count`, `queue_size`, `stack_size` from constants for maintainability.
  - `wait_timeout_ns` for worker loop wait operations.
  - `recommendedThreadCount()`, `ioBoundThreadCount()`, `cpuBoundThreadCount()` helper functions.
- **Improved Regex Engine**: Replaced basic wildcard matching with a robust, backtracking regex-like engine in `Utils`.
  - Supports standard quantifiers: `*` (zero or more), `+` (one or more), `?` (optional).
  - Supports character classes: `\d` (digit), `\w` (alphanumeric), `\s` (whitespace) and their negated forms (`\D`, `\W`, `\S`).
  - Supports `.` for matching any single character.
  - Added `Utils.matchRegexPattern` for anchored matching at string start.
  - Added `Utils.findRegexPattern` for searching patterns anywhere in a string.
- **Enhanced Filter & Redactor**: Unified all pattern matching to use the centralized `Utils` regex engine for consistency and improved performance.
- **Optimized Search Logic**: Refactored `Filter` rule evaluation to use `findRegexPattern`, eliminating manual search loops.

- **Auto-Flush**: New configuration option `auto_flush` (defaults to `true`) in `Config` struct.
  - Automatically flushes all sinks after every log operation.
  - Ensures immediate output visibility for both standard logs and custom levels.
  - Prevents log output reordering issues relative to `std.debug.print`.
  - Applies to all logging methods including `log`, `logCustomLevel`, `logError`, `logTimed`, and `logSystemDiagnostics`.
- **Dynamic Async Control**: Runtime enable/disable of async logging and per-sink async writing.
  - `Logger.enableAsync()`, `Logger.disableAsync()`, `Logger.isAsyncEnabled()` for global async control.
  - `Sink.enableAsync()`, `Sink.disableAsync()`, `Sink.isAsyncEnabled()` for per-sink async control.
  - `Sink.flushNow()` for manual immediate flushing of individual sinks.
- **Dynamic Flush Control**: Runtime control of auto-flush behavior.
  - `Logger.enableAutoFlush()`, `Logger.disableAutoFlush()`, `Logger.isAutoFlushEnabled()` for global auto-flush control.
  - Consistent auto-flush behavior across all dispatch paths (async logger, thread pool, direct sinks).
- **Zstandard (Zstd) Compression Support**: Added Zstd compression algorithm for log file archiving.
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

### ThreadPool & System Enhancements

- **ThreadPool Optimization**: Improved thread pool efficiency with centralized constant reuse from `config.zig`, `constants.zig`, and `utils.zig`.
  - Worker loop now uses `Constants.ThreadDefaults.wait_timeout_ns` for consistent wait operations.
  - All presets use `Constants.ThreadDefaults` values for thread count, queue size, and stack size.
  - Statistics methods use `Utils.atomicLoadU64()` and `Utils.calculateErrorRate()` for efficient calculations.
- **LevelColorConfig**: Added `theme_preset`, `notice_color`, `fatal_color` fields and `getColorForLevel()` method.
- **Formatter.Theme**: Added `notice` and `fatal` fields for complete level coverage.
- **Telemetry Export**: Improved provider detection and format-specific export with proper JSON structures.
- **Documentation**: Updated compression, telemetry, scheduler, and thread-pool guides with v0.1.5 features.
- **Examples**: Updated `compression_demo.zig`, `scheduler_demo.zig`, and `telemetry.zig` with v0.1.5 features.

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

**Refactoring & Optimization**:
- **Centralized Time Management**: Unified all timestamp retrieval through the `Utils` module.
  - Replaced all direct `std.time` calls (`timestamp`, `nanoTimestamp`, `milliTimestamp`) with `Utils.currentSeconds()`, `Utils.currentNanos()`, and `Utils.currentMillis()`.
  - Ensures consistent time source across all modules (Logger, Telemetry, Rotation, Compression, Scheduler, etc.).
- **Precise Formatter Statistics**: Implemented exact byte tracking in `Formatter.formatWithAllocator`.
  - Replaced estimated constant (100 bytes) with precise length of the actual formatted message.
  - Improves accuracy of `total_bytes_formatted` in `FormatterStats`.
- **Atomic Operation Utilities**: Consolidated atomic load/store operations in `Utils` for consistent cross-platform behavior.
- **Math & Rate Utilities**: Centralized common calculations like `calculateRate`, `calculateAverage`, and `calculateErrorRate` in `Utils` for efficient reuse in all statistics modules.

- **Advanced Logging Filter**: Major enhancements to the filtering engine.
  - Added support for multiple logical modes: `all` (AND), `any` (OR), `none` (NOR), and `not_all` (NAND).
  - Expanded rule types including `module_regex`, `message_regex`, `source_file_match`, `function_match`, `trace_id_match`, and `context_value_match`.
  - Added support for context-based filtering with pattern matching on specific keys.
  - Implemented regular expression (regex-like) matching for module names, messages, and source metadata.
  - Added numerous convenience aliases (`allow`, `deny`, `keep`, `drop`, `include`, `exclude`).
  - Expanded `FilterPresets` with `development`, `verbose`, `warningsAndErrors`, `noNetwork`, `audit`, and `security`.

### Fixed

- Improved thread safety for span and metric operations with mutex protection.

### Enhancements v0.1.3

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

