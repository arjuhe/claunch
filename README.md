# claunch

A TUI launcher for [Claude Code](https://docs.anthropic.com/en/docs/claude-code). Toggle flags, enter values, and launch claude with your selected configuration — all from a visual checklist.

<p align="center">
  <img src="https://raw.githubusercontent.com/arjuhe/claunch/main/assets/screenshot.svg" alt="claunch screenshot" width="780">
</p>

## Features

- Two-column grid layout with grouped options
- Inline value display for options that take arguments
- Live command preview as you toggle options
- Sticky section headers while scrolling
- Countdown launch screen with ESC to cancel
- Pure bash — no external TUI libraries

## Requirements

- **bash 4+** (macOS ships bash 3.2 — install a newer version with `brew install bash`)
- **Claude Code** CLI installed and in your PATH

## Installation

```bash
git clone https://github.com/arjuhe/claunch.git
cd claunch
chmod +x claunch
```

Or just copy the `claunch` script anywhere in your PATH.

## Usage

```bash
./claunch          # launch the TUI
./claunch --help   # show help
```

### Controls

| Key | Action |
|-----|--------|
| `↑` `↓` `←` `→` | Navigate options |
| `SPACE` | Toggle option (prompts for value if needed) |
| `ENTER` | Launch claude with selected options |
| `Page Up/Down` | Jump by group |
| `ESC` / `Q` | Quit |

## License

[MIT](LICENSE)
