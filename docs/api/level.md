# Level API

The `Level` enum defines the standard log levels.

## Enum Values

### `trace` (5)

Very detailed debugging information.

### `debug` (10)

Debugging information.

### `info` (20)

General information.

### `success` (25)

Successful operations.

### `warning` (30)

Warning messages.

### `err` (40)

Error conditions.

### `fail` (45)

Operation failures.

### `critical` (50)

Critical system errors.

## Methods

### `priority() u8`

Returns the numeric priority of the level.

### `asString() []const u8`

Returns the string representation of the level.
