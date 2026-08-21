#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LINK_TARGET="/usr/local/bin/claunch"

if [[ -e "$LINK_TARGET" || -L "$LINK_TARGET" ]]; then
  echo "Removing existing $LINK_TARGET"
  sudo rm "$LINK_TARGET"
fi

sudo ln -s "${SCRIPT_DIR}/claunch" "$LINK_TARGET"
echo "Symlinked ${SCRIPT_DIR}/claunch → $LINK_TARGET"
