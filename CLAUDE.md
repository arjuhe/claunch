# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

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

### Performance (no-fork rendering)

The render path is deliberately fork-free — every keystroke redraws without spawning subprocesses, which is what makes navigation feel instant:

- **`cup()` instead of `tput cup`** — cursor positioning is done with a raw `printf '\033[%d;%dH'` escape rather than `tput`, which would fork per call.
- **Pre-generated dash strings** — `_DASHES` / `_HEAVY_DASHES` are built once (300-char strings) and sliced with `${_DASHES:0:N}`, avoiding repeated string construction.
- **`_partial_redraw()`** — on ordinary cursor movement (no scroll, no resize) only the two affected option rows (old + new cursor position) are repainted, plus the footer. Full `draw_all()` is reserved for resize; `draw_content` + `draw_footer` for scroll changes. See the redraw dispatch at the bottom of the main loop.

### Launch / Countdown Screen

After the user presses ENTER, the TUI tears down (`cleanup`, leaves the alternate screen) and `draw_launch_screen()` renders a confirmation box in the normal buffer showing the assembled `claude` command. A 5-second countdown (`draw_countdown()`) then runs; ENTER launches immediately, ESC aborts. The final launch uses `exec "$CLAUDE_BIN" "${CMD_ARGS[@]}"` so claude replaces the launcher process. The countdown screen redraws itself in place using cursor-up escapes (`\033[8A`) and handles resize via its own WINCH trap.

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
Row 1:     │ logo + "Claude Code Launcher v0"
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
- **W**: Write selected options as standalone bash script
- **ENTER**: Launch claude with selected options
- **ESC / Q**: Quit
- **Page Up/Down**: Jump by group

### Value Input

When toggling an option that requires input (`arg_hint` is non-empty), `prompt_value()` restores terminal to normal stty settings for clean `read -r` input, then re-enters raw mode. Empty input deselects the option.

### Script Export

Pressing **W** prompts for an output path/filename (default: `./claude-launch`) and writes a simple, readable bash script with the selected options. If the file already exists, claunch asks for confirmation before overwriting (default is NO for safety). After generating the script, claunch displays a goodbye screen with the ASCII art logo and exits.

**Design Philosophy**: The generated script is intentionally minimal and operator-friendly. Unlike claunch's interactive TUI, the exported script focuses on clarity and ease of editing. It's just a clean bash script with backslash line continuations - the simplest possible format.

**Overwrite Protection**: If the output file already exists, claunch displays a warning message with the filename in yellow and "EXISTS! YES TO OVERWRITE" in red: "{FILENAME in yellow} EXISTS! YES TO OVERWRITE (y/N)" and waits for confirmation. The default is NO (pressing ENTER cancels) — any answer other than 'y' or 'Y' cancels the write and returns to the TUI. This prevents accidental overwrites of existing launcher scripts.

The script includes:
- `#!/usr/bin/env bash` shebang
- Comment with the script's full path for identification
- Direct `exec claude` command with backslash line continuations
- One option per line (quoted values for safety)
- Made executable (`chmod +x`)

**Example generated script (~8-10 lines):**
```bash
#!/usr/bin/env bash
# /path/to/claude-launch
# Generated by claunch - https://github.com/arjuhe/claunch

exec claude \
  --continue \
  --model "sonnet" \
  --effort "high" \
  --add-dir "/home/user/project"
```

The goodbye screen shows:
```
╭━━━━━━━━━━━━━┯━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
│             │ Script Generated Successfully!
│   ▐▛███▜▌   │ ✓ Wrote: ./claude-launch
│  ▝▜█████▛▘  │
│    ▘▘ ▝▝    │
│             │ Run it with: ./claude-launch
│             │ Happy coding! ◡̈
╰─────────────┴───────────────────────────────────────
```

The execution command automatically formats based on the path:
- Relative/plain filenames: adds `./` prefix (e.g., `./claude-launch`)
- Absolute paths: shown as-is (e.g., `/usr/local/bin/my-launcher`)

**Why keep it simple?** The whole point of claunch is to make things easier for operators. The generated script should be easy to read, easy to edit, and easy to understand. It's just `exec claude` with backslash line continuations — the simplest possible format. Complex UIs, arrays, loops, and color codes belong in claunch's interactive TUI — not in the exported configuration scripts that operators need to maintain and modify.

## Common Tasks

### Testing changes
```bash
# Syntax check
bash -n claunch

# Run directly
./claunch

# claunch's own help
./claunch --help
```

### Installing
```bash
# Symlinks ./claunch → /usr/local/bin/claunch (uses sudo)
./install.sh
```

### Updating options

Edit the `FLAT_OPTS` array directly. Format: `"--flag|Human-readable description|arg_hint"`. Use `"---|Group Name|"` for group separators. Options with empty `arg_hint` are simple toggles; non-empty means the user will be prompted for a value.

### Known Issues / TODO

- No `--version` flag for claunch itself yet (`--help` is implemented; version is hardcoded in `LAUNCHER_VERSION`)
- Some newer options may require additional description refinement for brevity
