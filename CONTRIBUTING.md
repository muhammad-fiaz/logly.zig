# Contributing to Logly

Thank you for your interest in contributing to Logly! We welcome contributions from everyone.

## How to Contribute

1.  **Fork the repository** and create your branch from `main`.
2.  **Clone the repository** to your local machine.
3.  **Install Zig**: Ensure you have Zig 0.17.0 installed.
4.  **Run Tests**: Make sure all tests pass before submitting your changes.
    ```bash
    zig build test
    ```
5.  **Make your changes**: Implement your feature or fix.
6.  **Add Tests**: If you are adding a new feature, please add tests to cover it.
7.  **Run Examples**: Verify that examples still work.
    ```bash
    zig build run-all-examples
    ```
8.  **Commit your changes**: Use clear and descriptive commit messages.
9.  **Push to your fork** and submit a Pull Request.

## Writing Tests

`zig build` runs the test binary with `--listen=-`, which means **stdout
carries Zig's own progress protocol**. A test that prints to stdout corrupts
that stream and the build appears to hang on the test that printed.

Tests must therefore stay silent:

```zig
test "example" {
    var config = Config.default();
    config.autoSink = false;              // no automatic console sink
    config.globalConsoleDisplay = false;   // and no console output if one is added
    const logger = try Logger.initWithConfig(std.testing.allocator, config);
    defer logger.deinit();
    // ...
}
```

To assert on rendered output, write to a temporary file or a memory sink and
read it back, rather than relying on console output.

Two more notes:

- `std.testing.allocator` poisons freed memory with `0x55`. Free a value only
  after you have finished asserting on it, or assertions will read garbage.
- Run a single test group with
  `zig build test -Dtest-filter="rotation"`. The build seeds each test binary
  differently, so a full `zig build test` recompiles every time.

## Pull Request Guidelines

- Ensure your code follows the existing style.
- Update documentation if necessary.
- Fill out the Pull Request Template completely.
- Be respectful and constructive in discussions.

## Reporting Issues

If you find a bug or have a feature request, please open an issue on GitHub. Provide as much detail as possible, including:

- Zig version
- Operating System
- Steps to reproduce
- Expected vs. actual behavior

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
