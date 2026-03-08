# sklient

A terminal client for [Sklad](https://github.com/sklad-dev/Sklad) database.

## Features

- **TUI Mode**: Interactive interface with dropdown menus and guided input
- **Raw Mode**: Direct query input for power users
- Query support: `set`, `get`, `get range`, `delete`

## Building

Requires Zig 0.15.2

```
zig build --release=safe
```

## Usage

The client connects to Sklad server at `127.0.0.1:7733` by default.

| Key | Action |
|-----|--------|
| <kbd>Space</kbd> | Start query / interact |
| <kbd>↑</kbd> <kbd>↓</kbd> | Navigate dropdown options |
| <kbd>Enter</kbd> | Confirm selection |
| <kbd>Ctrl</kbd>+<kbd>T</kbd> | Toggle TUI/Raw mode |
| <kbd>Ctrl</kbd>+<kbd>C</kbd> | Exit |

## Todo
- Render the response as a table
- Attempt reconnect
- Pass host and port values via command line arguments
- TUI mode functionality:
  - Support `expire` syntax
  - Support setting multiple key-value pairs in one query
- Query history
