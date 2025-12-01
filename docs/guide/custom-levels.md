# Custom Log Levels

While Logly-Zig comes with 8 built-in levels, you might need to define your own levels for specific domain requirements.

## Adding a Custom Level

You can add a custom level with a name, priority, and color code.

```zig
// Add a NOTICE level with priority 35 (between WARNING and ERROR)
// "96" is the ANSI color code for Cyan
try logger.addCustomLevel("NOTICE", 35, "96");
```

## Using Custom Levels

To log using a custom level, use the `custom` method.

```zig
try logger.custom("NOTICE", "This is a notice message");
```

## Priorities

Standard levels have the following priorities:

- TRACE: 5
- DEBUG: 10
- INFO: 20
- SUCCESS: 25
- WARNING: 30
- ERROR: 40
- FAIL: 45
- CRITICAL: 50

Choose a priority for your custom level that fits into this hierarchy. For example, a priority of 35 places the level between WARNING and ERROR.
