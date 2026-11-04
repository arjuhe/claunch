#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LINK_TARGET="/usr/local/bin/claunch"
SOURCE_FILE="${SCRIPT_DIR}/claunch"

# Verify source file exists
if [[ ! -f "$SOURCE_FILE" ]]; then
  echo "Error: claunch script not found at $SOURCE_FILE"
  exit 1
fi

# Verify target directory exists
if [[ ! -d "/usr/local/bin" ]]; then
  echo "Error: /usr/local/bin directory does not exist"
  exit 1
fi

if [[ -e "$LINK_TARGET" || -L "$LINK_TARGET" ]]; then
  echo "Removing existing $LINK_TARGET"
  sudo rm "$LINK_TARGET"
fi

sudo ln -s "$SOURCE_FILE" "$LINK_TARGET"
echo "Symlinked $SOURCE_FILE → $LINK_TARGET"
