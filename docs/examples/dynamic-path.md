---
title: Dynamic Path Example
description: Example of dynamic path formatting in Logly.zig. Use date and time placeholders like {date}, {YYYY}, {MM}, {DD} to create timestamped log file paths.
head:
  - - meta
    - name: keywords
      content: dynamic path, date placeholder, time format, log file naming, timestamp path, date directory
  - - meta
    - property: og:title
      content: Dynamic Path Example | Logly.zig
  - - meta
    - property: og:image
      content: https://muhammad-fiaz.github.io/logly.zig/cover.png
---

# Dynamic Path and Folder Control

Logly allows you to dynamically set the full path of the log file, effectively controlling the folder structure based on dates or times.
Because dynamic paths are resolved at startup (or file creation time), they prevent conflicts with rotation by establishing the *active* file's location.

**How it works with Rotation:**
1. **Dynamic Path** determines where the *Active* (current) log file is written (example: `logs/2023-10-25/app.log`).
2. **Rotation** takes this file, renames it (example: `app-2023-10-25-14.log`), and either leaves it in that folder or moves it to a configured `archive_dir`.

This separation allows you to have:
*   Daily Date Folders: `logs/{date}/`
*   Rotated Files within those folders OR
*   Centralized Archives (`logs/archive/`) regardless of the date folder.

Several sinks support dynamic path formatting, which lets you include date and time placeholders that are resolved when the sink initializes or when creating rotated files.

Common placeholders supported by `SinkConfig.path` include:

- `{date}` → `YYYY-MM-DD` (e.g., "2023-10-25")
- `{time}` → `HH-mm-ss` (e.g., "14-30-00")
- `{timestamp}` → Unix timestamp (milliseconds)
- `{YYYY}`, `{YY}` → Year
- `{MM}`, `{M}` → Month (01-12, 1-12)
- `{DD}`, `{D}` → Day (01-31, 1-31)
- `{HH}`, `{H}` → Hour (00-23, 0-23)
- `{mm}`, `{m}` → Minute (00-59, 0-59)
- `{ss}`, `{s}` → Second (00-59, 0-59)

### Usage with Rotation
Dynamic paths work seamlessly with **rotation** and **compression**. The placeholders are resolved when the file is created.

**Example: Organized Logs by Date**

This configuration:
1. Creates a folder for today's date (e.g., `logs/2023-10-25/`).
2. Creates a file named with the current time (e.g., `app-14-30-00.log`).
3. Rotates within that folder.

```zig
_ = try logger.addSink(.{
    .path = "logs_dynamic/{date}/test-{HH}-{mm}-{ss}.log",
    .json = false,
});

try logger.info("This log should be in a date-stamped folder", null);
```

Tip: To experiment locally, run the `examples/dynamic_path.zig` program and inspect the `logs_dynamic/` directory to confirm the generated path format.
