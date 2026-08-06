# CLAUDE.md — claunch

## Project Overview

**claunch** is a TUI (Terminal User Interface) launcher for Claude Code. It presents all of Claude Code's CLI options as a visual checklist in a two-column grid layout, letting users toggle flags, enter values for options that require input, and launch claude with their selected configuration.

GitHub org: `arjuhe`

## Architecture

The entire project is a single bash script (`claunch`). No external dependencies beyond bash 4+ and a terminal that supports 24-bit true color.

### Key Design Decisions

- **Pure bash TUI** — no ncurses, dialog, fzf, or external TUI libraries. Uses ANSI escape codes and Unicode box-drawing characters (`╭╮╰╯│─├┤`) for rendering.
- **`set -uo pipefail` (NOT `-e`)** — arithmetic expressions like `((CURSOR > 0))` return exit code 1 when false, which kills the script under `set -e`.
- **`#!/usr/bin/env bash`** — macOS ships bash 3.2 at `/bin/bash` which lacks features we need. This picks up Homebrew's bash 5+ from PATH. The script does NOT currently have a version guard but should work on bash 4+.
- **Alternate screen buffer** — `tput smcup/rmcup` so the TUI doesn't pollute scroll-back history.
- **Raw terminal input** — `stty -echo -icanon` for keystroke-by-keystroke reading. Original stty settings saved in `ORIG_STTY` and restored on exit and during value input prompts.
- **ESC key detection** — reads 1 byte after `\x1b` with 100ms timeout (`read -rsn1 -t 0.1`) to distinguish bare ESC (quit) from arrow key sequences (`\x1b[A`, etc.).

### Color Palette

Uses the **Aardvark Blue** iTerm2 color palette with 24-bit RGB true-color escape sequences (`\033[38;2;R;G;Bm`). All color variables are defined at the top of the script.

### Data Model

Options are defined in a flat array `FLAT_OPTS` using the format `"flag|description|arg_hint"` with group separators `"---|GroupName|"`. This is parsed into:

- `OPT_FLAG[]`, `OPT_DESC[]`, `OPT_ARG[]` — flat option arrays (no separators)
- `SELECTED[]`, `VALUES[]` — per-option selection state
- `GROUP_NAME[]`, `GROUP_START[]`, `GROUP_COUNT[]` — group metadata

### Layout Structure

```
Row 0:     ╭── top border ──╮
Row 1:     │ logo + "claunch v0"
Row 2:     │ logo + "Found claude code version: vX.Y.Z"
Row 3:     │ logo feet
Row 4:     │ (blank)
Row 5:     │ key bindings help
Row 6:     ├── scroll window top border ──┤
Row 7+:    │ scrollable content area (groups + options in 2-col grid)
           ├── description bar ──┤
           │ DESCRIPTION: <highlighted option's description>
           ├── command preview ──┤
           │ ❯ claude <selected flags>
           ╰── bottom border ──╯
```

### Two-Column Grid

Options within each group fill two columns, row by row. Cursor state is `CUR_GROUP`, `CUR_ROW`, `CUR_COL`. The `grid_to_flat()` function maps grid position to the flat option index.

### Sticky Section Headers

When scrolling, if a group's header bar has scrolled above the viewport but the group still has visible options, the header is pinned to the top row of the scroll area. Implemented via `find_sticky_group()`.

### Navigation

- **↑/↓**: Move within group rows; cross group boundaries at edges
- **←/→**: Switch between left/right columns
- **SPACE**: Toggle option (prompts for value if option has `arg_hint`)
- **ENTER**: Launch claude with selected options
- **ESC / Q**: Quit
- **Page Up/Down**: Jump by group

### Value Input

When toggling an option that requires input (`arg_hint` is non-empty), `prompt_value()` restores terminal to normal stty settings for clean `read -r` input, then re-enters raw mode. Empty input deselects the option.

## Common Tasks

### Testing changes
```bash
# Syntax check
bash -n claunch

# Run directly
./claunch
```

### Updating options
Edit the `FLAT_OPTS` array. Format: `"--flag|Human-readable description|arg_hint"`. Use `"---|Group Name|"` for group separators. Options with empty `arg_hint` are simple toggles; non-empty means the user will be prompted for a value.

### Known Issues / TODO

- `--exclude-dynamic-system-prompt` should be `--exclude-dynamic-system-prompt-sections` (per `claude --help`)
- Options list should be synced against latest `claude --help` output — some flags may be missing or renamed
- No `--version` / `--help` flags for claunch itself yet
- No install script or packaging yet
