#!/usr/bin/env bash
# Open a NetworkManager UI: nm-connection-editor, else nmtui in a terminal.
set -euo pipefail

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

close_menus

if command -v nm-connection-editor >/dev/null 2>&1; then
	exec nm-connection-editor
elif command -v nmtui >/dev/null 2>&1; then
	exec "${HOME}/.config/i3/scripts/i3_term" -e nmtui 2>/dev/null || exec x-terminal-emulator -e nmtui
fi
